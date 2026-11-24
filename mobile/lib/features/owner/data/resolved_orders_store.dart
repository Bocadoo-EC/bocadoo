import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/extras_models.dart';

/// Persistencia diaria (`resolved_orders_YYYY-MM-DD`) y conciliación de
/// preórdenes ya cubiertas, canjeadas o cerradas contra `Cobros de hoy`.
class ResolvedOrdersStore {
  ResolvedOrdersStore._();

  static final ResolvedOrdersStore instance = ResolvedOrdersStore._();

  static const String _keyPrefix = 'resolved_orders_';

  String _loadedDay = '';
  final Set<String> _resolvedIds = <String>{};
  final Set<String> _resolvedNumbers = <String>{};
  Future<void>? _loadingFuture;

  String get _todayKey => '$_keyPrefix${EcuadorTime.today()}';

  static String normalizeOrderNumber(String raw) =>
      raw.replaceAll('#', '').trim();

  static String _normalizeName(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> ensureLoaded() async {
    final today = EcuadorTime.today();
    if (_loadedDay == today) return;
    if (_loadingFuture != null) {
      await _loadingFuture;
      if (_loadedDay == today) return;
    }
    final completer = _loadForDay(today);
    _loadingFuture = completer;
    try {
      await completer;
    } finally {
      if (identical(_loadingFuture, completer)) {
        _loadingFuture = null;
      }
    }
  }

  Future<void> _loadForDay(String today) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$today';
      final rawJson = prefs.getString(key);
      _resolvedIds.clear();
      _resolvedNumbers.clear();
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          final ids = decoded['ids'];
          if (ids is List) {
            for (final id in ids) {
              final s = id?.toString().trim() ?? '';
              if (s.isNotEmpty) _resolvedIds.add(s);
            }
          }
          final nums = decoded['numbers'];
          if (nums is List) {
            for (final n in nums) {
              final s = normalizeOrderNumber(n?.toString() ?? '');
              if (s.isNotEmpty) _resolvedNumbers.add(s);
            }
          }
        }
      }
      for (final existingKey in prefs.getKeys()) {
        if (existingKey.startsWith(_keyPrefix) && existingKey != key) {
          await prefs.remove(existingKey);
        }
      }
      _loadedDay = today;
    } catch (_) {
      _loadedDay = today;
    }
  }

  Future<void> _persistToday() async {
    final today = EcuadorTime.today();
    if (_loadedDay != today) {
      _resolvedIds.clear();
      _resolvedNumbers.clear();
      _loadedDay = today;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _todayKey;
      final payload = jsonEncode({
        'ids': _resolvedIds.toList(),
        'numbers': _resolvedNumbers.toList(),
      });
      await prefs.setString(key, payload);
      for (final existingKey in prefs.getKeys()) {
        if (existingKey.startsWith(_keyPrefix) && existingKey != key) {
          await prefs.remove(existingKey);
        }
      }
    } catch (_) {}
  }

  Future<void> markResolved({String? id, String? number}) async {
    await ensureLoaded();
    var changed = false;
    final cleanId = id?.trim() ?? '';
    if (cleanId.isNotEmpty) {
      changed = _resolvedIds.add(cleanId) || changed;
    }
    final cleanNum = normalizeOrderNumber(number ?? '');
    if (cleanNum.isNotEmpty) {
      changed = _resolvedNumbers.add(cleanNum) || changed;
    }
    if (changed) {
      await _persistToday();
    }
  }

  bool isMarkedResolved({String? id, String? number}) {
    final today = EcuadorTime.today();
    if (_loadedDay != today) return false;
    final cleanId = id?.trim() ?? '';
    if (cleanId.isNotEmpty && _resolvedIds.contains(cleanId)) return true;
    final cleanNum = normalizeOrderNumber(number ?? '');
    if (cleanNum.isNotEmpty && _resolvedNumbers.contains(cleanNum)) return true;
    return false;
  }

  static bool isOpenOrderStatus(String estado) {
    final upper = estado.trim().toUpperCase();
    return upper == 'EN_CAMINO' || upper == 'PENDIENTE';
  }

  static final RegExp _orderNumberRegex = RegExp(r'#(\d+)');

  /// Determina si una preorden ya cuenta con un consumo o cobro equivalente en
  /// `Cobros de hoy` (p. ej. `CANJE_DIRECTO` anterior al PR 10, `PEDIDO` o `VENTA` confirmada).
  bool isOrderCoveredInMovements(
    OwnerOrder order,
    List<CajaMovement> movements,
  ) {
    if (movements.isEmpty) return false;
    final orderNum = normalizeOrderNumber(order.number);
    final orderId = order.id?.trim() ?? '';
    final dinerNorm = _normalizeName(order.dinerName);
    final orderCreatedUtc = order.createdAt.toUtc();
    final thresholdUtc = orderCreatedUtc.subtract(const Duration(minutes: 2));

    for (final m in movements) {
      if (m.revertido) continue;
      final pagoEstado = m.pagoEstado?.trim().toUpperCase() ?? '';
      if (pagoEstado == 'RECHAZADO' || pagoEstado == 'ANULADO') continue;
      if (m.tipo == CajaMovementType.venta &&
          pagoEstado.isNotEmpty &&
          pagoEstado != 'CONFIRMADO') {
        continue;
      }

      if (orderId.isNotEmpty && m.id.trim() == orderId) {
        return true;
      }

      if (orderNum.isNotEmpty && m.tipo == CajaMovementType.pedido) {
        final titleMatch = _orderNumberRegex.firstMatch(m.title);
        final subMatch = m.subtitle != null
            ? _orderNumberRegex.firstMatch(m.subtitle!)
            : null;
        if (titleMatch?.group(1) == orderNum || subMatch?.group(1) == orderNum) {
          return true;
        }
      }

      if (dinerNorm.isEmpty) continue;
      final candidateNames = <String>{};
      if (m.customerName != null && m.customerName!.trim().isNotEmpty) {
        candidateNames.add(_normalizeName(m.customerName!));
      }
      final titleParts = m.title.split('·');
      for (final part in titleParts) {
        final cleaned = _normalizeName(part);
        if (cleaned.isNotEmpty) candidateNames.add(cleaned);
      }

      if (!candidateNames.contains(dinerNorm)) continue;

      final isPlanOrOrderMovement =
          m.tipo == CajaMovementType.canjeDirecto ||
          m.tipo == CajaMovementType.pedido;
      if (!isPlanOrOrderMovement) continue;

      // Si `timestamp` es null en un movimiento de hoy (`CANJE_DIRECTO`),
      // coincide igual por ser de la fecha actual.
      if (m.timestamp == null) return true;
      if (!m.timestamp!.toUtc().isBefore(thresholdUtc)) {
        return true;
      }
    }
    return false;
  }

  List<OwnerOrder> filterOrdersSync(
    List<OwnerOrder> orders, {
    List<CajaMovement> movements = const [],
  }) {
    return [
      for (final o in orders)
        if (isOpenOrderStatus(o.estado) &&
            !isMarkedResolved(id: o.id, number: o.number) &&
            !isOrderCoveredInMovements(o, movements))
          o,
    ];
  }

  Future<List<OwnerOrder>> filterAndReconcileOrders(
    List<OwnerOrder> orders, {
    List<CajaMovement> movements = const [],
  }) async {
    await ensureLoaded();
    final remaining = <OwnerOrder>[];
    for (final o in orders) {
      if (!isOpenOrderStatus(o.estado)) continue;
      if (isMarkedResolved(id: o.id, number: o.number)) continue;
      if (isOrderCoveredInMovements(o, movements)) {
        await markResolved(id: o.id, number: o.number);
        continue;
      }
      remaining.add(o);
    }
    return remaining;
  }
}
