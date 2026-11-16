import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/analytics/events_service.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/deferred_commit.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/utils/formatters.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/daily_menu.dart';
import '../domain/models/extras_models.dart';
import '../domain/models/menu_models.dart';
import '../domain/models/metrics_models.dart';
import '../domain/repositories/i_owner_repository.dart';

enum _SaleUndoKind { plan, pos }

class _OrderCacheEntry {
  _OrderCacheEntry({
    required this.id,
    required this.number,
    required this.paidByPlan,
    required this.validated,
    required this.amount,
    this.consumoId,
  });

  final String id;
  final String number;
  final bool paidByPlan;
  bool validated;
  final double amount;
  String? consumoId;
}

class _TableUndoEntry {
  const _TableUndoEntry({required this.consumoIds, this.ventaId});

  final List<String> consumoIds;
  final String? ventaId;
}

class _MetricsCacheEntry {
  const _MetricsCacheEntry({required this.value, required this.at});

  final OwnerMetrics value;
  final DateTime at;
}

/// Repositorio real del módulo Dueño/Caja (`O1`–`O16`, `P-01`).
class ApiOwnerRepository
    implements
        IOwnerRepository,
        IOwnerCashRepository,
        IOwnerOrdersRepository,
        IOwnerTablesRepository,
        IOwnerMenuRepository,
        IOwnerCatalogRepository,
        IOwnerMetricsRepository,
        IOwnerFeedbackRepository,
        IOwnerSettingsRepository {
  ApiOwnerRepository({
    required this._api,
    required this._session,
  });

  final ApiClient _api;
  final SessionNotifier _session;
  final IdempotencyStore _idempotency = IdempotencyStore();

  final Map<String, String> _consumoIdByPassId = {};
  final Map<String, _SaleUndoKind> _saleUndoById = {};
  final Map<String, _OrderCacheEntry> _ordersByNumber = {};
  final Map<String, DeferredCommit> _orderDeliverCommits = {};
  final Set<String> _pendingDeliverOrders = {};
  final Map<String, _TableUndoEntry> _tableUndoByChargeId = {};
  final Map<String, DeferredCommit> _opinionReplyCommits = {};
  final Map<String, String> _optimisticOpinionReplies = {};
  final Map<String, String> _clientIdByOpinionId = {};
  final Map<String, String> _todayMenuItemIdByName = {};
  final Map<String, String> _physicalCardCreatedClientId = {};
  final Map<MetricsPeriod, _MetricsCacheEntry> _metricsCache = {};

  final List<CatalogItem> _catalogCache = [];
  int _cachedLunchPriceCents = 0;
  String? _activeOfferId;
  String? _lastError;

  bool get _isCashier => _session.isCashierAccount;

  /// Devuelve y limpia el último mensaje de error legible generado por una
  /// operación de caja/pedidos/cierre que retorna `bool` o `null`.
  String? consumeLastError() {
    final err = _lastError;
    _lastError = null;
    return err;
  }

  void dispose() {
    for (final c in _orderDeliverCommits.values) {
      c.dispose();
    }
    _orderDeliverCommits.clear();
    for (final c in _opinionReplyCommits.values) {
      c.dispose();
    }
    _opinionReplyCommits.clear();
  }

  // ---------------------------------------------------------------------------
  // Auxiliares internos
  // ---------------------------------------------------------------------------

  static int _asInt(dynamic v, [int fallback = 0]) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static int? _asNullableInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime _parseDateTime(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }

  static String _hhmmEcuador(DateTime utcOrLocal) {
    final ec = utcOrLocal.toUtc().subtract(const Duration(hours: 5));
    return '${ec.hour.toString().padLeft(2, '0')}:'
        '${ec.minute.toString().padLeft(2, '0')}';
  }

  static String _mapPayMethodApi(OwnerPayMethod m) => switch (m) {
        OwnerPayMethod.efectivo => 'EFECTIVO',
        OwnerPayMethod.transferencia => 'TRANSFERENCIA',
        OwnerPayMethod.deuna => 'DEUNA',
        // Tarjeta se oculta en UI mediante ApiCapabilities.cardPayment.
        OwnerPayMethod.tarjeta => 'TRANSFERENCIA',
      };

  static String _mapMetodoToUi(dynamic raw) {
    return switch ((raw ?? '').toString().toUpperCase()) {
      'EFECTIVO' => 'Efectivo',
      'TRANSFERENCIA' => 'Transferencia',
      'DEUNA' => 'Deuna',
      'PLAN' => 'Plan',
      _ => 'Efectivo',
    };
  }

  Future<Map<String, dynamic>> _fetchRestaurantMap() async {
    final data = await guard(
      () => _api.getMap('${ApiConfig.v1}/restaurante', restaurant: true),
    );
    final lunchCents = _asInt(data['precioSueltoCentavos']);
    if (lunchCents > 0) _cachedLunchPriceCents = lunchCents;
    return data;
  }

  /// Lee `llenoManualHasta` desde `GET /v1/restaurante` para inicializar el
  /// estado del interruptor de local lleno al abrir Caja.
  Future<DateTime?> fetchManualBusyUntil() async {
    try {
      final data = await _fetchRestaurantMap();
      final raw = data['llenoManualHasta'];
      if (raw is String && raw.isNotEmpty) {
        final dt = DateTime.tryParse(raw)?.toLocal();
        if (dt != null && dt.isAfter(DateTime.now())) {
          return dt;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Busca una preorden por UUID (`GET /v1/caja/pedidos/{id}`) para
  /// redirección universal del escáner (`O2`).
  Future<OwnerOrder?> resolveOrderById(String id) async {
    try {
      final data = await guard(
        () => _api.getMap(
          '${ApiConfig.v1}/caja/pedidos/$id',
          restaurant: true,
        ),
      );
      return _mapOrder(data);
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return null;
    }
  }

  /// Busca una preorden activa por número visible (p. ej. `#42` o `42`).
  Future<OwnerOrder?> resolveOrderByNumber(String number) async {
    final orders = await getActiveOrders(_session.activeRestaurantId ?? '');
    return orders.where((o) => o.number == number).firstOrNull;
  }

  OwnerOrder _mapOrder(Map<String, dynamic> json) {
    final almuerzo = json['almuerzo'] is Map
        ? Map<String, dynamic>.from(json['almuerzo'] as Map)
        : null;
    final platos = almuerzo?['platos'] is List
        ? almuerzo!['platos'] as List
        : const [];

    String? soup;
    String? mainDish;
    for (final p in platos.whereType<Map>()) {
      final seccion = (p['seccion'] ?? '').toString().toUpperCase();
      final nombre = (p['nombre'] ?? '').toString();
      if (nombre.isEmpty) continue;
      if (seccion == 'SOPA') {
        soup ??= nombre;
      } else if (seccion == 'FUERTE') {
        mainDish ??= nombre;
      }
    }

    final extras = json['extras'] is List ? json['extras'] as List : const [];
    if (mainDish == null && extras.isNotEmpty) {
      mainDish = extras
          .whereType<Map>()
          .map((e) {
            final q = _asInt(e['cantidad'], 1);
            final n = (e['nombre'] ?? '').toString();
            return q > 1 ? '${q}x $n' : n;
          })
          .where((s) => s.isNotEmpty)
          .join(', ');
    }

    final cliente = json['cliente'] is Map ? json['cliente'] as Map : null;
    final comensal = json['comensal'] is Map ? json['comensal'] as Map : null;
    final dinerName = (cliente?['nombre'] ?? comensal?['nombre'] ?? 'Comensal')
        .toString();

    final estado = (json['estado'] ?? '').toString().toUpperCase();
    final paidByPlan = almuerzo?['cubiertoPorPlan'] == true;
    final number = _asInt(json['numero']).toString();
    final id = (json['id'] ?? '').toString();
    final amount = Money.fromCents(_asInt(json['totalCentavos']));
    final validated = estado == 'CANJEADA';

    if (id.isNotEmpty && number.isNotEmpty) {
      final prev = _ordersByNumber[number];
      _ordersByNumber[number] = _OrderCacheEntry(
        id: id,
        number: number,
        paidByPlan: paidByPlan,
        validated: validated,
        amount: amount,
        consumoId: prev?.consumoId,
      );
    }

    return OwnerOrder(
      id: id.isEmpty ? null : id,
      number: number,
      dinerName: dinerName,
      amount: amount,
      createdAt: _parseDateTime(json['creadoEn']),
      soup: soup,
      main: mainDish,
      takeaway: json['paraLlevar'] == true,
      paidByPlan: paidByPlan,
      validated: validated,
    );
  }

  // ---------------------------------------------------------------------------
  // IOwnerRepository (Escáner O2 + Cierre / Resumen O1, O4)
  // ---------------------------------------------------------------------------

  @override
  Future<ScanResult> validateQrCode(String rawPayload) async {
    _lastError = null;
    final restaurantId = _session.activeRestaurantId ?? '';
    final intent = 'validar:$restaurantId:$rawPayload';
    final ik = _idempotency.keyFor(intent);
    try {
      final data = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/validar',
              body: {'codigoQr': rawPayload},
              restaurant: true,
              idempotencyKey: ik,
            ).then((v) => v ?? <String, dynamic>{}),
      );

      final resultado = (data['resultado'] ?? '').toString().toUpperCase();
      final mensaje = (data['mensaje'] ?? '').toString();
      final cliente = data['cliente'] is Map ? data['cliente'] as Map : null;
      final consumo = data['consumo'] is Map ? data['consumo'] as Map : null;
      final plan = data['plan'] is Map ? data['plan'] as Map : null;

      final clienteId = cliente?['id']?.toString();
      final clienteNombre = cliente?['nombre']?.toString();
      final consumoId = consumo?['id']?.toString();
      final planNombre = plan?['nombre']?.toString();
      final creadoEnRaw = consumo?['creadoEn'];
      final redeemedAt = creadoEnRaw != null ? _parseDateTime(creadoEnRaw) : null;

      final remaining = _asNullableInt(data['almuerzosRestantes']);
      final daysToExpire = _asNullableInt(data['diasParaVencer']);

      eventsService.track(
        'dueno.qr_validado',
        restaurantId: restaurantId,
        props: {
          'resultado': resultado.isEmpty ? 'DESCONOCIDO' : resultado,
          'validado': resultado == 'OK' || resultado == 'OK_ADVERTENCIA',
        },
      );

      final passId = consumoId ??
          clienteId ??
          'qr-${DateTime.now().microsecondsSinceEpoch}';
      if (consumoId != null && consumoId.isNotEmpty) {
        _consumoIdByPassId[passId] = consumoId;
      }

      switch (resultado) {
        case 'OK':
          return ScanResult(
            isValid: true,
            outcome: 'VERDE',
            title: 'Validado',
            supportingLine: (planNombre != null && planNombre.isNotEmpty)
                ? planNombre
                : 'Plan activo',
            studentName: clienteNombre,
            studentCareer: planNombre,
            passId: passId,
            remainingLunches: remaining,
            redemptionId: consumoId,
            redeemedAt: redeemedAt ?? DateTime.now(),
            actionRequired: 'NINGUNA',
          );
        case 'OK_ADVERTENCIA':
          final lowDays = daysToExpire != null && daysToExpire <= 3;
          return ScanResult(
            isValid: true,
            outcome: 'ADVERTENCIA',
            title: lowDays ? 'Por vencer' : 'Último almuerzo',
            supportingLine:
                mensaje.isNotEmpty ? mensaje : 'Renueva su plan hoy',
            studentName: clienteNombre,
            studentCareer: planNombre,
            passId: passId,
            remainingLunches: remaining,
            redemptionId: consumoId,
            redeemedAt: redeemedAt ?? DateTime.now(),
            actionRequired: 'VENDER_PLAN',
          );
        case 'DUPLICADO':
          return ScanResult(
            isValid: false,
            outcome: 'GRIS',
            title: 'Ya almorzó hoy',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'Ya registró su almuerzo hoy',
            studentName: clienteNombre,
            studentCareer: planNombre,
            redeemedAt: redeemedAt,
            actionRequired: 'NINGUNA',
          );
        case 'SIN_SALDO':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Plan agotado',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'Se terminaron los almuerzos de este plan',
            studentName: clienteNombre,
            remainingLunches: 0,
            actionRequired: 'VENDER_PLAN',
          );
        case 'SIN_PLAN':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Sin plan activo',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'No tiene un plan vigente aquí',
            studentName: clienteNombre,
            actionRequired: 'VENDER_PLAN',
          );
        case 'VENCIDO':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Plan vencido',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'La vigencia de este plan terminó',
            studentName: clienteNombre,
            actionRequired: 'VENDER_PLAN',
          );
        case 'DIA_NO_VALIDO':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Hoy no aplica',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'Este plan no incluye el día de hoy',
            studentName: clienteNombre,
            actionRequired: 'NINGUNA',
          );
        case 'OTRO_LOCAL':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Es de otro local',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'Este pase pertenece a otro restaurante',
            studentName: clienteNombre,
            actionRequired: 'NINGUNA',
          );
        case 'QR_EXPIRADO':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'QR expirado',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'Pide al comensal que recargue su pantalla',
            actionRequired: 'SCAN_AGAIN',
          );
        case 'LIMITE_SAAS':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Límite alcanzado',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'Alcanzaste el límite de almuerzos de tu plan Bocadoo',
            actionRequired: 'NINGUNA',
          );
        default:
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Código no válido',
            supportingLine:
                mensaje.isNotEmpty ? mensaje : 'No pudimos validar este QR.',
            actionRequired: 'SCAN_AGAIN',
          );
      }
    } finally {
      _idempotency.done(intent);
    }
  }

  @override
  Future<bool> confirmRedeem(String passId) async {
    // POST /v1/caja/validar ya descuenta atómicamente el almuerzo en backend.
    return true;
  }

  @override
  Future<bool> sellPlan({
    required String studentIdentifier,
    required int lunchCount,
    required String paymentMethod,
    required double amount,
  }) {
    throw UnimplementedError('Usa sellPlanTemplate para vender planes en caja.');
  }

  @override
  Future<TransactionSummary> getDailyClosingSummary(String restaurantId) async {
    final today = EcuadorTime.today();
    final cierreFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/caja/cierre/$today',
        restaurant: true,
      ),
    );
    final Future<Map<String, dynamic>?> resumenFuture = _isCashier
        ? Future.value(null)
        : guard(
            () => _api.getMap(
              '${ApiConfig.v1}/reportes/resumen-diario',
              query: {'fecha': today},
              restaurant: true,
            ),
          ).then<Map<String, dynamic>?>((v) => v).catchError((_) => null);

    final txFuture = getTodayTransactions(restaurantId);

    final cierre = await cierreFuture;
    final resumen = await resumenFuture;
    final transactions = await txFuture;

    final expectedCents = _asInt(cierre['efectivoEsperadoCentavos']);
    final totalIncomeCents = _asInt(cierre['totalCentavos']);
    final lunchesWithPlan = _asInt(cierre['almuerzosConPlan']);

    int plansSoldToday = 0;
    if (resumen != null && resumen['planesVendidos'] is Map) {
      plansSoldToday = _asInt((resumen['planesVendidos'] as Map)['cantidad']);
    }

    final closed = cierre['cierre'] is Map
        ? Map<String, dynamic>.from(cierre['cierre'] as Map)
        : null;
    final double cashCounted;
    final double cashDifference;
    final String cashStatus;

    if (closed != null) {
      cashCounted = Money.fromCents(_asInt(closed['efectivoContadoCentavos']));
      final diffCents = _asInt(closed['diferenciaCentavos']);
      cashDifference = Money.fromCents(diffCents);
      if (diffCents == 0) {
        cashStatus = 'Cuadra';
      } else if (diffCents < 0) {
        cashStatus = 'Falta';
      } else {
        cashStatus = 'Sobra';
      }
    } else {
      cashCounted = Money.fromCents(expectedCents);
      cashDifference = 0.0;
      cashStatus = 'Cuadra';
    }

    return TransactionSummary(
      date: EcuadorTime.now(),
      lunchesRedeemedToday: lunchesWithPlan,
      plansSoldToday: plansSoldToday,
      totalIncomeToday: Money.fromCents(totalIncomeCents),
      cashCounted: cashCounted,
      cashExpected: Money.fromCents(expectedCents),
      cashDifference: cashDifference,
      cashStatus: cashStatus,
      transactions: transactions,
    );
  }

  @override
  Future<List<TransactionItem>> getTodayTransactions(
    String restaurantId,
  ) async {
    final today = EcuadorTime.today();
    final ventasFuture = guard(
      () => _api.getList('${ApiConfig.v1}/caja/ventas', restaurant: true),
    );
    final pedidosFuture = guard(
      () => _api.getList(
        '${ApiConfig.v1}/caja/pedidos',
        query: {'estado': 'SERVIDA'},
        restaurant: true,
      ),
    );

    final rawVentas = await ventasFuture;
    final rawPedidos = await pedidosFuture;

    final out = <TransactionItem>[];
    final ventaOrderRefs = <String>{};

    for (final v in rawVentas.whereType<Map>()) {
      if (v['deshecha'] == true) continue;
      final id = (v['id'] ?? '').toString();
      final ticket = _asInt(v['ticket']);
      final mesaTexto = (v['mesaTexto'] ?? '').toString().trim();
      if (mesaTexto.startsWith('Pedido #')) {
        ventaOrderRefs.add(mesaTexto);
      }

      final items = v['items'] is List ? v['items'] as List : const [];
      final hasLunch = items.whereType<Map>().any((i) => i['esAlmuerzo'] == true);
      final pago = v['pago'] is Map ? v['pago'] as Map : const {};

      final label = mesaTexto.isNotEmpty
          ? 'Ticket #$ticket · $mesaTexto'
          : 'Ticket #$ticket';

      out.add(
        TransactionItem(
          id: id,
          customerName: label,
          type: hasLunch ? 'Venta Suelta' : 'Venta POS',
          amount: Money.fromCents(_asInt(v['totalCentavos'])),
          paymentMethod: _mapMetodoToUi(pago['metodo']),
          timestamp: _parseDateTime(v['creadoEn']),
        ),
      );
    }

    for (final p in rawPedidos.whereType<Map>()) {
      final totalCents = _asInt(p['totalCentavos']);
      if (totalCents <= 0) continue;
      final fecha = (p['fecha'] ?? '').toString();
      if (fecha.isNotEmpty && fecha != today) continue;

      final numero = _asInt(p['numero']).toString();
      if (ventaOrderRefs.contains('Pedido #$numero')) continue;

      final cliente = p['cliente'] is Map ? p['cliente'] as Map : null;
      final comensal = p['comensal'] is Map ? p['comensal'] as Map : null;
      final name = (cliente?['nombre'] ?? comensal?['nombre'] ?? 'Comensal')
          .toString();

      out.add(
        TransactionItem(
          id: (p['id'] ?? '').toString(),
          customerName: name,
          type: 'Pedido #$numero',
          amount: Money.fromCents(totalCents),
          paymentMethod: 'Efectivo',
          timestamp: _parseDateTime(p['servidoEn'] ?? p['creadoEn']),
        ),
      );
    }

    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  // ---------------------------------------------------------------------------
  // IOwnerCashRepository (Fase 3: O1, O3, O4, O6, O8, O11, O13)
  // ---------------------------------------------------------------------------

  @override
  Future<double> getSingleLunchPrice(String restaurantId) async {
    final data = await _fetchRestaurantMap();
    return Money.fromCents(_asInt(data['precioSueltoCentavos']));
  }

  @override
  Future<List<OwnerClient>> getClients(String restaurantId) async {
    final out = <OwnerClient>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final query = <String, dynamic>{
        'limit': 50,
        'cursor': ?cursor,
      };
      final data = await guard(
        () => _api.getMap(
          '${ApiConfig.v1}/clientes',
          query: query,
          restaurant: true,
        ),
      );
      final items = data['items'] is List ? data['items'] as List : const [];
      for (final raw in items.whereType<Map>()) {
        if (raw['activo'] == false) continue;
        final avail = _asInt(raw['almuerzosDisponibles']);
        out.add(
          OwnerClient(
            id: (raw['id'] ?? '').toString(),
            name: (raw['nombre'] ?? '').toString(),
            phone: Phone.toLocal(raw['telefono']?.toString()),
            email: (raw['correo'] ?? '').toString(),
            notes: (raw['nota'] ?? '').toString(),
            habitualPlan: avail > 0
                ? '$avail ${avail == 1 ? 'almuerzo disponible' : 'almuerzos disponibles'}'
                : null,
          ),
        );
      }
      final next = data['nextCursor']?.toString();
      if (next == null || next.isEmpty) break;
      cursor = next;
    }
    return out;
  }

  @override
  Future<OwnerClient> addClient(
    String restaurantId, {
    required String name,
    required String phone,
    String email = '',
    String notes = '',
  }) async {
    final e164 = Phone.toE164(phone);
    final trimmedEmail = email.trim();
    final body = <String, dynamic>{
      'nombre': name.trim(),
      if (e164.isNotEmpty) 'telefono': e164,
      if (trimmedEmail.isNotEmpty) 'correo': trimmedEmail,
      if (notes.trim().isNotEmpty) 'nota': notes.trim(),
    };
    Map<String, dynamic> res;
    try {
      res = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/clientes',
              body: body,
              restaurant: true,
            ).then((v) => v ?? <String, dynamic>{}),
      );
    } on ApiException catch (e) {
      if (e.status == 409) {
        const msg = 'Ya tienes un cliente con ese celular.';
        _lastError = msg;
        throw ApiException(
          status: 409,
          code: e.code,
          detail: e.detail,
          requestId: e.requestId,
          overrideMessage: msg,
        );
      }
      rethrow;
    }
    final clientId = (res['id'] ?? '').toString();
    // P-13: si se capturó correo, intenta vincular en silencio sin bloquear el alta.
    if (trimmedEmail.isNotEmpty && clientId.isNotEmpty) {
      try {
        await guard(
          () => _api.send<dynamic>(
                'POST',
                '${ApiConfig.v1}/clientes/$clientId/vincular',
                body: {'correo': trimmedEmail},
                restaurant: true,
              ),
        );
      } catch (_) {}
    }
    return OwnerClient(
      id: clientId,
      name: (res['nombre'] ?? name.trim()).toString(),
      phone: Phone.toLocal(res['telefono']?.toString()),
      email: (res['correo'] ?? email).toString(),
      notes: (res['nota'] ?? notes).toString(),
    );
  }

  static PlanCoverage _inferCoverage(List<String> includes) {
    final lower = includes.map((e) => e.toLowerCase()).toList();
    final hasBreakfast =
        lower.any((e) => e.contains('desayuno') || e.contains('principal'));
    final hasLunch = lower.any((e) => e.contains('sopa') || e.contains('segundo'));
    if (hasBreakfast && hasLunch) return PlanCoverage.mixto;
    if (hasBreakfast) return PlanCoverage.desayuno;
    return PlanCoverage.almuerzo;
  }

  @override
  Future<List<OwnerPlanTemplate>> getPlanTemplates(String restaurantId) async {
    final list = await guard(
      () => _api.getList('${ApiConfig.v1}/planes', restaurant: true),
    );
    return list.whereType<Map>().map((raw) {
      final tipo = (raw['tipo'] ?? 'MENSUAL').toString().toUpperCase();
      final kind = switch (tipo) {
        'SEMANAL' => PlanKind.semanal,
        'QUINCENAL' => PlanKind.quincenal,
        'LIBRE' => PlanKind.libre,
        _ => PlanKind.mensual,
      };
      final rawDays = raw['diasValidos'] is List ? raw['diasValidos'] as List : const [1, 2, 3, 4, 5];
      final rawIncl = raw['incluye'] is List ? raw['incluye'] as List : const ['Sopa', 'Segundo', 'Jugo'];
      final includes = rawIncl.map((e) => e.toString()).toList();
      return OwnerPlanTemplate(
        id: (raw['id'] ?? '').toString(),
        name: (raw['nombre'] ?? '').toString(),
        lunches: _asInt(raw['almuerzos']),
        price: Money.fromCents(_asInt(raw['precioCentavos'])),
        validityDays: _asInt(raw['vigenciaDias'], 30),
        kind: kind,
        coverage: _inferCoverage(includes),
        includes: includes,
        days: rawDays.map((e) => _asInt(e, 1)).toList(),
        quota: _asInt(raw['cupos'], 0),
        visible: raw['visibleEnMarketplace'] != false,
        active: raw['activo'] != false,
      );
    }).toList();
  }

  @override
  Future<String?> sellPlanTemplate({
    required String restaurantId,
    String? clientId,
    String? newClientName,
    required OwnerPlanTemplate template,
    required OwnerPayMethod method,
  }) async {
    _lastError = null;
    try {
      var targetClientId = clientId;
      if (targetClientId == null || targetClientId.isEmpty) {
        final name = newClientName?.trim() ?? '';
        if (name.isEmpty) {
          _lastError = 'Selecciona o escribe el nombre del comensal.';
          return null;
        }
        final created = await addClient(restaurantId, name: name, phone: '');
        targetClientId = created.id;
      }

      final intent = 'sell_plan:$targetClientId:${template.id}:${_mapPayMethodApi(method)}';
      final ik = _idempotency.keyFor(intent);
      try {
        final res = await guard(
          () => _api.send<Map<String, dynamic>>(
                'POST',
                '${ApiConfig.v1}/clientes/$targetClientId/planes',
                body: {
                  'planId': template.id,
                  'metodoPago': _mapPayMethodApi(method),
                  'pagoConfirmado': true,
                },
                restaurant: true,
                idempotencyKey: ik,
              ).then((v) => v ?? <String, dynamic>{}),
        );
        final id = (res['id'] ?? '').toString();
        if (id.isNotEmpty) {
          _saleUndoById[id] = _SaleUndoKind.plan;
          eventsService.track(
            'dueno.plan_vendido',
            restaurantId: restaurantId,
            props: {
              'metodo': _mapPayMethodApi(method),
              'origen': 'caja',
            },
          );
          return id;
        }
        return null;
      } finally {
        _idempotency.done(intent);
      }
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return null;
    }
  }

  @override
  Future<bool> undoTransaction(String transactionId) async {
    _lastError = null;
    final kind = _saleUndoById[transactionId] ?? _SaleUndoKind.pos;
    final intent = 'undo_tx:$transactionId';
    final ik = _idempotency.keyFor(intent);
    try {
      if (kind == _SaleUndoKind.plan) {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/planes-vendidos/$transactionId/deshacer',
            body: const <String, dynamic>{},
            restaurant: true,
            idempotencyKey: ik,
          ),
        );
      } else {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/caja/ventas/$transactionId/deshacer',
            restaurant: true,
            idempotencyKey: ik,
          ),
        );
      }
      _saleUndoById.remove(transactionId);
      if (kind == _SaleUndoKind.pos) {
        eventsService.track('dueno.pos_venta_deshecha');
      }
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } finally {
      _idempotency.done(intent);
    }
  }

  @override
  Future<bool> undoRedeem(String passId) async {
    _lastError = null;
    final consumoId = _consumoIdByPassId[passId] ?? passId;
    try {
      final res = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/consumos/$consumoId/deshacer',
              restaurant: true,
            ).then((v) => v ?? <String, dynamic>{}),
      );
      _consumoIdByPassId.remove(passId);
      final reverted = res['revertido'] != false;
      if (reverted) {
        eventsService.track('dueno.consumo_deshecho');
      }
      return reverted;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    }
  }

  @override
  Future<List<CatalogItem>> getCatalog(String restaurantId) async {
    final list = await guard(
      () => _api.getList(
        '${ApiConfig.v1}/menu/platos',
        query: {'soloActivos': true},
        restaurant: true,
      ),
    );
    final mapped = <CatalogItem>[];
    for (final raw in list.whereType<Map>()) {
      final categoria = (raw['categoria'] ?? '').toString().toUpperCase();
      if (categoria == 'ALMUERZO') continue;
      final nombre = (raw['nombre'] ?? '').toString();
      final etiquetas = (raw['etiquetas'] is List ? raw['etiquetas'] as List : const [])
          .map((e) => e.toString().toLowerCase())
          .toList();
      final PosCategory cat = switch (categoria) {
        'A_LA_CARTA' => PosCategory.carta,
        'BEBIDA' => PosCategory.bebidas,
        _ => (etiquetas.contains('desayuno') ||
                nombre.toLowerCase().contains('desayuno'))
            ? PosCategory.desayunos
            : PosCategory.extras,
      };
      mapped.add(
        CatalogItem(
          id: (raw['id'] ?? '').toString(),
          name: nombre,
          description: (raw['descripcion'] ?? '').toString(),
          price: Money.fromCents(_asInt(raw['precioCentavos'])),
          category: cat,
        ),
      );
    }
    _catalogCache
      ..clear()
      ..addAll(mapped);
    return mapped;
  }

  @override
  Future<String?> registerPosSale({
    required String restaurantId,
    required String label,
    required List<PosSaleLine> lines,
    required double total,
    required OwnerPayMethod method,
  }) async {
    _lastError = null;
    try {
      if (_cachedLunchPriceCents == 0) {
        await _fetchRestaurantMap();
      }
      if (_catalogCache.isEmpty && lines.any((l) => !l.isLunch)) {
        await getCatalog(restaurantId);
      }

      final targetCents = Money.toCents(total);
      final rawCents = lines.fold<int>(
        0,
        (s, l) => s + Money.toCents(l.unitPrice) * l.qty,
      );

      var effectiveLines = List<PosSaleLine>.from(lines);
      if (targetCents < rawCents) {
        // El POS aplicó descuento de "Plan + Extras": no volvemos a cobrar el
        // almuerzo/desayuno cubierto por el plan del comensal.
        final withoutLunch = lines.where((l) => !l.isLunch).toList();
        final withoutLunchCents = withoutLunch.fold<int>(
          0,
          (s, l) => s + Money.toCents(l.unitPrice) * l.qty,
        );
        if (withoutLunchCents == targetCents) {
          effectiveLines = withoutLunch;
        } else {
          final desc = effectiveLines
              .map((l) => l.qty > 1 ? '${l.qty}x ${l.name}' : l.name)
              .join(', ');
          effectiveLines = [
            PosSaleLine(
              name: desc.isEmpty ? 'Consumo POS' : desc,
              unitPrice: total,
              qty: 1,
            ),
          ];
        }
      }

      final apiItems = <Map<String, dynamic>>[];
      for (final l in effectiveLines) {
        final unitCents = Money.toCents(l.unitPrice);
        if (l.isLunch &&
            l.name == 'Almuerzo' &&
            unitCents == _cachedLunchPriceCents) {
          apiItems.add({'tipo': 'ALMUERZO', 'cantidad': l.qty});
          continue;
        }
        final match = _catalogCache
            .where(
              (c) =>
                  c.name.toLowerCase() == l.name.toLowerCase() &&
                  Money.toCents(c.price) == unitCents,
            )
            .firstOrNull;
        if (match != null) {
          apiItems.add({
            'tipo': 'PLATO',
            'platoId': match.id,
            'cantidad': l.qty,
          });
          continue;
        }
        final nombreLibre = (l.detail != null && l.detail!.isNotEmpty)
            ? '${l.name} (${l.detail})'
            : l.name;
        apiItems.add({
          'tipo': 'LIBRE',
          'nombre': nombreLibre,
          'precioUnitarioCentavos': unitCents,
          'cantidad': l.qty,
        });
      }

      if (apiItems.isEmpty) {
        _lastError = 'No hay montos por cobrar en efectivo o transferencia.';
        return null;
      }

      final mesaTexto = label.split('·').first.trim();
      final paraLlevar = mesaTexto.toLowerCase().startsWith('para llevar');

      final intent =
          'pos:$restaurantId:$mesaTexto:$targetCents:${_mapPayMethodApi(method)}';
      final ik = _idempotency.keyFor(intent);
      try {
        final res = await guard(
          () => _api.send<Map<String, dynamic>>(
                'POST',
                '${ApiConfig.v1}/caja/ventas',
                body: {
                  'items': apiItems,
                  'metodoPago': _mapPayMethodApi(method),
                  'paraLlevar': paraLlevar,
                  if (mesaTexto.isNotEmpty) 'mesaTexto': mesaTexto,
                  'pagoConfirmado': true,
                },
                restaurant: true,
                idempotencyKey: ik,
              ).then((v) => v ?? <String, dynamic>{}),
        );
        final id = (res['id'] ?? '').toString();
        if (id.isNotEmpty) {
          _saleUndoById[id] = _SaleUndoKind.pos;
          eventsService.track(
            'dueno.pos_venta_registrada',
            restaurantId: restaurantId,
            props: {
              'metodo': _mapPayMethodApi(method),
              'items': apiItems.length,
              'para_llevar': paraLlevar,
            },
          );
          return id;
        }
        return null;
      } finally {
        _idempotency.done(intent);
      }
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return null;
    }
  }

  @override
  Future<FlashOffer?> getActiveOffer(String restaurantId) async {
    final data = await guard(
      () => _api.getMap(
        '${ApiConfig.v1}/ofertas',
        query: {'estado': 'VIGENTE', 'limit': 1},
        restaurant: true,
      ),
    );
    final items = data['items'] is List ? data['items'] as List : const [];
    final first = items.whereType<Map>().firstOrNull;
    if (first == null) {
      _activeOfferId = null;
      return null;
    }
    _activeOfferId = (first['id'] ?? '').toString();
    final expiraRaw = first['expiraEn']?.toString();
    final validUntil = expiraRaw != null && expiraRaw.isNotEmpty
        ? _hhmmEcuador(_parseDateTime(expiraRaw))
        : null;
    return FlashOffer(
      kind: OfferKind.flash,
      title: (first['titulo'] ?? '').toString(),
      discountPercent: _asInt(first['descuentoPorcentaje']),
      slots: _asInt(first['stockRestante'], _asInt(first['stockTotal'])),
      price: Money.fromCents(_asInt(first['precioCentavos'])),
      validUntil: validUntil,
    );
  }

  @override
  Future<bool> publishOffer(String restaurantId, FlashOffer offer) async {
    _lastError = null;
    final priceCents = Money.toCents(offer.price);
    final ratio = (100 - offer.discountPercent.clamp(1, 95)) / 100.0;
    final computedOriginal = ratio > 0 ? (priceCents / ratio).round() : priceCents;
    final originalCents =
        computedOriginal > priceCents ? computedOriginal : priceCents + 50;

    int duracionMinutos = 120;
    if (offer.validUntil != null && offer.validUntil!.contains(':')) {
      try {
        final targetUtc = EcuadorTime.todayAtUtc(offer.validUntil!);
        final diff = targetUtc.difference(DateTime.now().toUtc()).inMinutes;
        duracionMinutos = diff.clamp(5, 1440);
      } catch (_) {
        duracionMinutos = 120;
      }
    }

    final intent = 'oferta:$restaurantId:${offer.title}:$priceCents:${offer.slots}';
    final ik = _idempotency.keyFor(intent);
    try {
      final res = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/ofertas',
              body: {
                'titulo': offer.title.trim(),
                'precioCentavos': priceCents,
                'precioOriginalCentavos': originalCents,
                'stock': offer.slots,
                'duracionMinutos': duracionMinutos,
              },
              restaurant: true,
              idempotencyKey: ik,
            ).then((v) => v ?? <String, dynamic>{}),
      );
      _activeOfferId = res['id']?.toString();
      eventsService.track(
        'dueno.oferta_publicada',
        restaurantId: restaurantId,
        props: {
          'stock': offer.slots,
          'descuento': offer.discountPercent,
        },
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } finally {
      _idempotency.done(intent);
    }
  }

  @override
  Future<bool> cancelOffer(String restaurantId) async {
    _lastError = null;
    try {
      var id = _activeOfferId;
      if (id == null || id.isEmpty) {
        await getActiveOffer(restaurantId);
        id = _activeOfferId;
      }
      if (id == null || id.isEmpty) return false;
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/ofertas/$id/cerrar',
          restaurant: true,
        ),
      );
      _activeOfferId = null;
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    }
  }

  @override
  Future<bool> setManualBusy(String restaurantId, {required bool busy}) async {
    _lastError = null;
    try {
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/restaurante/lleno',
          body: {'lleno': busy},
          restaurant: true,
        ),
      );
      eventsService.track(
        'dueno.aforo_cambiado',
        restaurantId: restaurantId,
        props: {'lleno': busy},
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    }
  }

  @override
  Future<int> getOrdersOnTheWayCount(String restaurantId) async {
    final orders = await getActiveOrders(restaurantId);
    return orders.length;
  }

  @override
  Future<bool> isShiftClosed(String restaurantId) async {
    final today = EcuadorTime.today();
    final data = await guard(
      () => _api.getMap(
        '${ApiConfig.v1}/caja/cierre/$today',
        restaurant: true,
      ),
    );
    return data['cierre'] != null;
  }

  @override
  Future<bool> closeShift(
    String restaurantId, {
    required double countedCash,
  }) async {
    _lastError = null;
    final today = EcuadorTime.today();
    try {
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/caja/cierre/$today',
          body: {'efectivoContadoCentavos': Money.toCents(countedCash)},
          restaurant: true,
        ),
      );
      eventsService.track('dueno.cierre_caja', restaurantId: restaurantId);
      return true;
    } on ApiException catch (e) {
      if (e.status == 409) {
        _lastError = 'El cierre de hoy ya fue registrado.';
      } else {
        _lastError = e.userMessage;
      }
      return false;
    }
  }

  @override
  Future<bool> reopenShift(String restaurantId) async {
    _lastError = null;
    if (_isCashier) {
      _lastError = 'Solo el dueño puede reabrir un cierre.';
      return false;
    }
    final today = EcuadorTime.today();
    try {
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/caja/cierre/$today/reabrir',
          restaurant: true,
        ),
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // IOwnerOrdersRepository (O12)
  // ---------------------------------------------------------------------------

  @override
  Future<List<OwnerOrder>> getActiveOrders(String restaurantId) async {
    final list = await guard(
      () => _api.getList('${ApiConfig.v1}/caja/pedidos', restaurant: true),
    );
    final orders = <OwnerOrder>[];
    for (final raw in list.whereType<Map>()) {
      final estado = (raw['estado'] ?? '').toString().toUpperCase();
      if (estado != 'EN_CAMINO' && estado != 'CANJEADA') continue;
      final mapped = _mapOrder(Map<String, dynamic>.from(raw));
      if (_pendingDeliverOrders.contains(mapped.number)) continue;
      orders.add(mapped);
    }
    return orders;
  }

  Future<_OrderCacheEntry?> _resolveCachedOrder(
    String restaurantId,
    String orderNumber,
  ) async {
    final existing = _ordersByNumber[orderNumber];
    if (existing != null) return existing;
    await getActiveOrders(restaurantId);
    return _ordersByNumber[orderNumber];
  }

  @override
  Future<bool> validateOrder(String restaurantId, String orderNumber) async {
    _lastError = null;
    try {
      final entry = await _resolveCachedOrder(restaurantId, orderNumber);
      if (entry == null) {
        _lastError = 'No encontramos ese pedido.';
        return false;
      }
      final intent = 'order_canjear:${entry.id}';
      final ik = _idempotency.keyFor(intent);
      try {
        final res = await guard(
          () => _api.send<Map<String, dynamic>>(
                'POST',
                '${ApiConfig.v1}/caja/pedidos/${entry.id}/canjear',
                restaurant: true,
                idempotencyKey: ik,
              ).then((v) => v ?? <String, dynamic>{}),
        );
        final almuerzo = res['almuerzo'] is Map ? res['almuerzo'] as Map : null;
        final resultado = almuerzo?['resultado']?.toString().toUpperCase();
        final consumoId = almuerzo?['consumoId']?.toString();
        if (consumoId != null && consumoId.isNotEmpty) {
          entry.consumoId = consumoId;
        }
        final ok = res['yaCanjeado'] == true ||
            resultado == null ||
            resultado == 'OK' ||
            resultado == 'OK_ADVERTENCIA';
        if (ok) {
          entry.validated = true;
          eventsService.track(
            'dueno.pedido_validado',
            restaurantId: restaurantId,
          );
      return true;
        }
        _lastError = (almuerzo?['mensaje'] ?? 'No se pudo validar el pase del pedido.')
            .toString();
        return false;
      } finally {
        _idempotency.done(intent);
      }
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    }
  }

  @override
  Future<bool> undoValidate(String restaurantId, String orderNumber) async {
    _lastError = null;
    final entry = _ordersByNumber[orderNumber];
    final consumoId = entry?.consumoId;
    if (consumoId == null || consumoId.isEmpty) {
      _lastError = 'No hay descuento reciente para revertir en este pedido.';
      return false;
    }
    try {
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/caja/consumos/$consumoId/deshacer',
          restaurant: true,
        ),
      );
      entry!.consumoId = null;
      entry.validated = false;
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    }
  }

  @override
  Future<bool> deliverOrder(String restaurantId, String orderNumber) async {
    _lastError = null;
    final entry = await _resolveCachedOrder(restaurantId, orderNumber);
    if (entry == null) {
      _lastError = 'No encontramos ese pedido.';
      return false;
    }

    _pendingDeliverOrders.add(orderNumber);
    final commit = _orderDeliverCommits.putIfAbsent(
      orderNumber,
      () => DeferredCommit(),
    );
    commit.schedule(() => _commitDeliverOrder(entry));
    return true;
  }

  Future<void> _commitDeliverOrder(_OrderCacheEntry entry) async {
    final today = EcuadorTime.today();
    try {
      var porCobrarCents = 0;
      var beforeCashCents = 0;
      final needsCanjear = !entry.validated || !entry.paidByPlan;

      if (entry.amount > 0.005) {
        try {
          final beforeCierre = await guard(
            () => _api.getMap(
              '${ApiConfig.v1}/caja/cierre/$today',
              restaurant: true,
            ),
          );
          beforeCashCents = _asInt(beforeCierre['efectivoEsperadoCentavos']);
        } catch (_) {}
      }

      if (needsCanjear) {
        final intent = 'order_deliver_canjear:${entry.id}';
        final ik = _idempotency.keyFor(intent);
        try {
          final canje = await guard(
            () => _api.send<Map<String, dynamic>>(
                  'POST',
                  '${ApiConfig.v1}/caja/pedidos/${entry.id}/canjear',
                  restaurant: true,
                  idempotencyKey: ik,
                ).then((v) => v ?? <String, dynamic>{}),
          );
          porCobrarCents = _asInt(
            canje['porCobrarCentavos'],
            Money.toCents(entry.amount),
          );
        } finally {
          _idempotency.done(intent);
        }
      } else {
        porCobrarCents = Money.toCents(entry.amount);
      }

      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/caja/pedidos/${entry.id}/servir',
          restaurant: true,
        ),
      );
      eventsService.track(
        'dueno.pedido_entregado',
        props: {'con_efectivo': entry.amount > 0.005},
      );

      // TODO(backend): B-26 — si servir/canjear no incrementa efectivoEsperadoCentavos
      // en cierre, registrar la parte por cobrar como venta POS en efectivo.
      if (porCobrarCents > 0) {
        try {
          final afterCierre = await guard(
            () => _api.getMap(
              '${ApiConfig.v1}/caja/cierre/$today',
              restaurant: true,
            ),
          );
          final afterCashCents = _asInt(afterCierre['efectivoEsperadoCentavos']);
          if (afterCashCents <= beforeCashCents) {
            final ventaIntent = 'b26_order_cash:${entry.id}';
            final ventaIk = _idempotency.keyFor(ventaIntent);
            try {
              await guard(
                () => _api.send<Map<String, dynamic>>(
                  'POST',
                  '${ApiConfig.v1}/caja/ventas',
                  body: {
                    'items': [
                      {
                        'tipo': 'LIBRE',
                        'nombre': 'Pedido #${entry.number}',
                        'precioUnitarioCentavos': porCobrarCents,
                        'cantidad': 1,
                      },
                    ],
                    'metodoPago': 'EFECTIVO',
                    'paraLlevar': false,
                    'mesaTexto': 'Pedido #${entry.number}',
                    'pagoConfirmado': true,
                  },
                  restaurant: true,
                  idempotencyKey: ventaIk,
                ),
              );
            } finally {
              _idempotency.done(ventaIntent);
            }
          }
        } catch (_) {}
      }
    } on ApiException catch (e) {
      _lastError = e.userMessage;
    } finally {
      _pendingDeliverOrders.remove(entry.number);
      _ordersByNumber.remove(entry.number);
    }
  }

  @override
  Future<bool> undoDeliver(String restaurantId, String orderNumber) async {
    final commit = _orderDeliverCommits[orderNumber];
    final cancelled = commit?.cancel() ?? false;
    _pendingDeliverOrders.remove(orderNumber);
    return cancelled;
  }

  // ---------------------------------------------------------------------------
  // IOwnerTablesRepository (O5 — Mesa con amigos)
  // ---------------------------------------------------------------------------

  @override
  Future<List<PendingTable>> getPendingTables(String restaurantId) async {
    // El backend actual no expone listado de mesas pendientes en caja (B-15).
    return const [];
  }

  @override
  Future<TablePreview> previewTable(
    String restaurantId,
    String tableId,
  ) async {
    final mesaFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/caja/mesas/$tableId',
        restaurant: true,
      ),
    );
    final restFuture = _fetchRestaurantMap();

    final mesa = await mesaFuture;
    final rest = await restFuture;

    final lunchCents = _asInt(rest['precioSueltoCentavos']);
    final surchargeCents = _asInt(rest['recargoParaLlevarCentavos']);

    final modoRaw = (mesa['modo'] ?? '').toString().toUpperCase();
    final mode = modoRaw == 'INVITO_YO' ? TableMode.hostPays : TableMode.eachOwn;
    final estado = (mesa['estado'] ?? '').toString().toUpperCase();
    final settled = estado == 'FINALIZADA' || mesa['validadaEn'] != null;

    final rawMembers = mesa['miembros'] is List ? mesa['miembros'] as List : const [];
    final hostMember = rawMembers
        .whereType<Map>()
        .where((m) => m['esAnfitrion'] == true)
        .firstOrNull;
    final hostName = (hostMember?['nombre'] ?? 'Anfitrión').toString();
    var hostAvailable = _asInt(hostMember?['almuerzosDisponibles']);

    final lines = <TableChargeLine>[];
    for (final m in rawMembers.whereType<Map>()) {
      final name = (m['nombre'] ?? 'Comensal').toString();
      final isHost = m['esAnfitrion'] == true;
      final takeaway = m['paraLlevar'] == true;
      final available = _asInt(m['almuerzosDisponibles']);

      late final TableChargeVia via;
      var cashCents = 0;

      if (mode == TableMode.hostPays) {
        if (hostAvailable > 0) {
          via = isHost ? TableChargeVia.plan : TableChargeVia.hostPlan;
          hostAvailable--;
        } else {
          via = TableChargeVia.cash;
          cashCents = lunchCents + (takeaway ? surchargeCents : 0);
        }
      } else {
        if (available > 0) {
          via = TableChargeVia.plan;
        } else {
          via = TableChargeVia.cash;
          cashCents = lunchCents + (takeaway ? surchargeCents : 0);
        }
      }

      lines.add(
        TableChargeLine(
          name: name,
          via: via,
          amount: Money.fromCents(cashCents),
          isHost: isHost,
          takeaway: takeaway,
        ),
      );
    }

    final horaRaw = mesa['horaLlegada']?.toString();
    final timeStr = horaRaw != null && horaRaw.isNotEmpty
        ? _hhmmEcuador(_parseDateTime(horaRaw))
        : '--:--';

    final String? error = estado == 'CANCELADA'
        ? 'Esta mesa fue cancelada.'
        : (estado == 'EXPIRADA' ? 'Esta mesa venció.' : null);

    return TablePreview(
      tableId: tableId,
      hostName: hostName,
      time: timeStr,
      mode: mode,
      lines: lines,
      error: error,
      settled: settled,
    );
  }

  @override
  Future<TablePreview> setTableMode(
    String restaurantId,
    String tableId,
    TableMode mode,
  ) {
    // Ajuste E3: la caja muestra el modo definido por el anfitrión.
    return previewTable(restaurantId, tableId);
  }

  @override
  Future<String?> chargeTable(String restaurantId, String tableId) async {
    _lastError = null;
    final intent = 'mesa_validar:$tableId';
    final ik = _idempotency.keyFor(intent);
    try {
      final today = EcuadorTime.today();
      var beforeCashCents = 0;
      try {
        final beforeCierre = await guard(
          () => _api.getMap(
            '${ApiConfig.v1}/caja/cierre/$today',
            restaurant: true,
          ),
        );
        beforeCashCents = _asInt(beforeCierre['efectivoEsperadoCentavos']);
      } catch (_) {}

      final res = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/mesas/$tableId/validar',
              restaurant: true,
              idempotencyKey: ik,
            ).then((v) => v ?? <String, dynamic>{}),
      );

      final resultados = res['resultados'] is List ? res['resultados'] as List : const [];
      final consumoIds = <String>[];
      for (final r in resultados.whereType<Map>()) {
        final cid = r['consumoId']?.toString();
        if (r['descontado'] == true && cid != null && cid.isNotEmpty) {
          consumoIds.add(cid);
        }
      }

      String? ventaId;
      final porCobrarCount = _asInt(res['porCobrar']);
      if (porCobrarCount > 0) {
        if (_cachedLunchPriceCents == 0) {
          await _fetchRestaurantMap();
        }
        try {
          final afterCierre = await guard(
            () => _api.getMap(
              '${ApiConfig.v1}/caja/cierre/$today',
              restaurant: true,
            ),
          );
          final afterCashCents = _asInt(afterCierre['efectivoEsperadoCentavos']);
          // TODO(backend): B-26 — si validar mesa no sumó los sueltos al
          // efectivo esperado, registrar la venta en efectivo vía POS.
          if (afterCashCents <= beforeCashCents && _cachedLunchPriceCents > 0) {
            final ventaIntent = 'b26_mesa_cash:$tableId';
            final ventaIk = _idempotency.keyFor(ventaIntent);
            try {
              final venta = await guard(
                () => _api.send<Map<String, dynamic>>(
                  'POST',
                  '${ApiConfig.v1}/caja/ventas',
                  body: {
                    'items': [
                      {
                        'tipo': 'ALMUERZO',
                        'cantidad': porCobrarCount,
                      },
                    ],
                    'metodoPago': 'EFECTIVO',
                    'paraLlevar': false,
                    'mesaTexto': 'Mesa en caja',
                    'pagoConfirmado': true,
                  },
                  restaurant: true,
                  idempotencyKey: ventaIk,
                ),
              );
              ventaId = venta?['id']?.toString();
            } finally {
              _idempotency.done(ventaIntent);
            }
          }
        } catch (_) {}
      }

      final chargeId = 'mesa-$tableId-${DateTime.now().microsecondsSinceEpoch}';
      _tableUndoByChargeId[chargeId] = _TableUndoEntry(
        consumoIds: consumoIds,
        ventaId: ventaId,
      );
      eventsService.track(
        'dueno.mesa_cobrada',
        restaurantId: restaurantId,
        props: {'consumos': consumoIds.length},
      );
      return chargeId;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return null;
    } finally {
      _idempotency.done(intent);
    }
  }

  @override
  Future<bool> undoTableCharge(String chargeId) async {
    _lastError = null;
    final entry = _tableUndoByChargeId.remove(chargeId);
    if (entry == null) return false;
    var ok = true;
    for (final cid in entry.consumoIds) {
      try {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/caja/consumos/$cid/deshacer',
            restaurant: true,
          ),
        );
      } catch (_) {
        ok = false;
      }
    }
    if (entry.ventaId != null && entry.ventaId!.isNotEmpty) {
      final intent = 'undo_mesa_venta:${entry.ventaId}';
      final ik = _idempotency.keyFor(intent);
      try {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/caja/ventas/${entry.ventaId}/deshacer',
            restaurant: true,
            idempotencyKey: ik,
          ),
        );
      } catch (_) {
        ok = false;
      } finally {
        _idempotency.done(intent);
      }
    }
    return ok;
  }

  // ---------------------------------------------------------------------------
  // IOwnerMenuRepository & IOwnerCatalogRepository (O7, O16)
  // ---------------------------------------------------------------------------

  static String _formatYmd(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String _ymdOffset(int daysDelta) =>
      _formatYmd(EcuadorTime.now().add(Duration(days: daysDelta)));

  static DishKind _courseCategoryToKind(String category) {
    return switch (category.trim().toLowerCase()) {
      'sopa' => DishKind.sopa,
      'fuerte' => DishKind.segundo,
      'jugo' => DishKind.bebida,
      'postre' => DishKind.postre,
      _ => DishKind.desayuno,
    };
  }

  static String _courseCategoryToSeccion(String category) {
    return switch (category.trim().toLowerCase()) {
      'sopa' => 'SOPA',
      'fuerte' => 'FUERTE',
      'jugo' => 'JUGO',
      'postre' => 'POSTRE',
      _ => 'ADICIONAL',
    };
  }

  static ({String categoria, String seccion, List<String> etiquetas}) _dishKindToApi(
    DishKind kind,
  ) {
    return switch (kind) {
      DishKind.sopa => (categoria: 'ALMUERZO', seccion: 'SOPA', etiquetas: const []),
      DishKind.segundo => (categoria: 'ALMUERZO', seccion: 'FUERTE', etiquetas: const []),
      DishKind.bebida => (categoria: 'ALMUERZO', seccion: 'JUGO', etiquetas: const []),
      DishKind.postre => (categoria: 'ALMUERZO', seccion: 'POSTRE', etiquetas: const []),
      DishKind.desayuno => (
          categoria: 'EXTRA',
          seccion: 'ADICIONAL',
          etiquetas: const ['desayuno'],
        ),
      DishKind.carta => (categoria: 'A_LA_CARTA', seccion: 'FUERTE', etiquetas: const []),
    };
  }

  DailyMenu _parseDailyMenu(
    String restaurantId,
    Map<String, dynamic> data,
    DateTime date, {
    required bool isOpen,
    bool populateSoldOutMap = false,
  }) {
    if (populateSoldOutMap) {
      _todayMenuItemIdByName.clear();
    }
    final rawItems = data['items'] is List ? data['items'] as List : const [];
    final courses = <DailyMenuCourse>[];
    for (final item in rawItems.whereType<Map>()) {
      final itemId = (item['id'] ?? '').toString();
      final platoId = (item['platoId'] ?? '').toString();
      final name = (item['nombre'] ?? '').toString();
      final seccion = (item['seccion'] ?? '').toString().toUpperCase();
      final cat = switch (seccion) {
        'SOPA' => 'Sopa',
        'FUERTE' => 'Fuerte',
        'JUGO' => 'Jugo',
        'POSTRE' => 'Postre',
        _ => 'Desayuno',
      };
      final priceCents = _asNullableInt(item['precioDelDiaCentavos']) ??
          _asNullableInt(item['precioCentavos']);
      if (populateSoldOutMap && itemId.isNotEmpty && name.trim().isNotEmpty) {
        _todayMenuItemIdByName[name.trim()] = itemId;
        _todayMenuItemIdByName[name.trim().toLowerCase()] = itemId;
      }
      courses.add(
        DailyMenuCourse(
          id: itemId,
          name: name,
          category: cat,
          isSoldOut: item['agotado'] == true,
          price: cat == 'Desayuno' && priceCents != null
              ? Money.fromCents(priceCents)
              : null,
          dishId: platoId.isEmpty ? null : platoId,
        ),
      );
    }

    return DailyMenu(
      restaurantId: restaurantId,
      date: date,
      courses: courses,
      isPublished: data['publicado'] == true,
      isOpen: isOpen,
    );
  }

  /// Lee `estado` desde `GET /v1/restaurante` para inicializar el interruptor de local activo/pausado.
  Future<bool> fetchStoreOpen() async {
    try {
      final rest = await _fetchRestaurantMap();
      return (rest['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'ACTIVO';
    } catch (_) {
      return true;
    }
  }

  @override
  Future<DailyMenu?> getTodayMenu(String restaurantId) async {
    final today = EcuadorTime.today();
    final menuFuture = guard(
      () => _api.getMap('${ApiConfig.v1}/menu/$today', restaurant: true),
    );
    final restFuture = _fetchRestaurantMap();

    final data = await menuFuture;
    final rest = await restFuture;
    final isOpen = (rest['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'ACTIVO';

    return _parseDailyMenu(
      restaurantId,
      data,
      EcuadorTime.now(),
      isOpen: isOpen,
      populateSoldOutMap: true,
    );
  }

  @override
  Future<DailyMenu?> getYesterdayMenu(String restaurantId) async {
    final yesterday = _ymdOffset(-1);
    try {
      final data = await guard(
        () => _api.getMap('${ApiConfig.v1}/menu/$yesterday', restaurant: true),
      );
      final menu = _parseDailyMenu(
        restaurantId,
        data,
        EcuadorTime.now().subtract(const Duration(days: 1)),
        isOpen: true,
      );
      return menu.courses.isEmpty ? null : menu;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<bool> publishMenu(DailyMenu menu) async {
    _lastError = null;
    try {
      final dishes = await getDishes(menu.restaurantId);
      final byKindAndName = <(DishKind, String), CatalogDish>{};
      final byName = <String, CatalogDish>{};
      for (final d in dishes) {
        final norm = d.name.trim().toLowerCase();
        byKindAndName[(d.kind, norm)] = d;
        byName.putIfAbsent(norm, () => d);
      }

      final itemsPayload = <Map<String, dynamic>>[];
      var orden = 0;
      for (final course in menu.courses) {
        final name = course.name.trim();
        if (name.isEmpty) continue;
        final kind = _courseCategoryToKind(course.category);
        final seccion = _courseCategoryToSeccion(course.category);

        var platoId = course.dishId ?? '';
        CatalogDish? matched;
        if (platoId.isEmpty) {
          matched = byKindAndName[(kind, name.toLowerCase())] ??
              byName[name.toLowerCase()];
          if (matched != null) {
            platoId = matched.id;
          }
        } else {
          for (final d in dishes) {
            if (d.id == platoId) {
              matched = d;
              break;
            }
          }
        }

        if (matched != null && matched.archived) {
          await setDishArchived(menu.restaurantId, matched.id, archived: false);
        }

        if (platoId.isEmpty) {
          final created = await addDish(
            menu.restaurantId,
            name: name,
            kind: kind,
            price: course.price,
          );
          platoId = created.id;
          byKindAndName[(kind, name.toLowerCase())] = created;
          byName[name.toLowerCase()] = created;
        }

        itemsPayload.add(<String, dynamic>{
          'platoId': platoId,
          'seccion': seccion,
          if (course.price != null) 'precioCentavos': Money.toCents(course.price!),
          'orden': orden++,
        });
      }

      final today = EcuadorTime.today();
      await guard(
        () => _api.send<Map<String, dynamic>>(
              'PUT',
              '${ApiConfig.v1}/menu/$today',
              body: {'items': itemsPayload},
              restaurant: true,
            ).then((v) => v ?? <String, dynamic>{}),
      );
      final publishedMap = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/menu/$today/publicar',
              restaurant: true,
            ).then((v) => v ?? <String, dynamic>{}),
      );

      _parseDailyMenu(
        menu.restaurantId,
        publishedMap,
        EcuadorTime.now(),
        isOpen: menu.isOpen,
        populateSoldOutMap: true,
      );

      // Si el usuario marcó platos como agotados antes de publicar, sincronízalos.
      for (final course in menu.courses) {
        if (!course.isSoldOut) continue;
        final itemId = _todayMenuItemIdByName[course.name.trim()] ??
            _todayMenuItemIdByName[course.name.trim().toLowerCase()];
        if (itemId == null || itemId.isEmpty) continue;
        await guard(
          () => _api.send<dynamic>(
                'PATCH',
                '${ApiConfig.v1}/menu/$today/items/$itemId/agotado',
                body: const {'agotado': true},
                restaurant: true,
              ),
        );
      }
      eventsService.track(
        'dueno.menu_publicado',
        restaurantId: menu.restaurantId,
        props: {'platos': menu.courses.length},
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo publicar el menú de hoy.';
      return false;
    }
  }

  @override
  Future<bool> unpublishMenu(String restaurantId) async {
    _lastError = null;
    try {
      final today = EcuadorTime.today();
      await guard(
        () => _api.send<dynamic>(
              'POST',
              '${ApiConfig.v1}/menu/$today/despublicar',
              restaurant: true,
            ),
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo despublicar el menú de hoy.';
      return false;
    }
  }

  @override
  Future<bool> setCourseSoldOut(
    String restaurantId,
    String courseName, {
    required bool soldOut,
  }) async {
    _lastError = null;
    try {
      final key = courseName.trim();
      var itemId = _todayMenuItemIdByName[key] ??
          _todayMenuItemIdByName[key.toLowerCase()];
      if (itemId == null || itemId.isEmpty) {
        await getTodayMenu(restaurantId);
        itemId = _todayMenuItemIdByName[key] ??
            _todayMenuItemIdByName[key.toLowerCase()];
      }
      if (itemId == null || itemId.isEmpty) {
        _lastError = 'Publica el menú de hoy antes de marcar platos agotados.';
        return false;
      }
      final today = EcuadorTime.today();
      await guard(
        () => _api.send<dynamic>(
              'PATCH',
              '${ApiConfig.v1}/menu/$today/items/$itemId/agotado',
              body: {'agotado': soldOut},
              restaurant: true,
            ),
      );
      eventsService.track(
        'dueno.plato_agotado',
        restaurantId: restaurantId,
        props: {'agotado': soldOut},
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo actualizar el estado del plato.';
      return false;
    }
  }

  @override
  Future<bool> setStoreOpen(String restaurantId, {required bool isOpen}) async {
    _lastError = null;
    try {
      final action = isOpen ? 'activar' : 'pausar';
      await guard(
        () => _api.send<dynamic>(
              'POST',
              '${ApiConfig.v1}/restaurante/$action',
              restaurant: true,
            ),
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo cambiar el estado del local.';
      return false;
    }
  }

  @override
  Future<List<CatalogDish>> getDishes(String restaurantId) async {
    final list = await guard(
      () => _api.getList(
        '${ApiConfig.v1}/menu/platos',
        query: const {'soloActivos': false},
        restaurant: true,
      ),
    );
    return list.whereType<Map>().map((raw) {
      final categoria = (raw['categoria'] ?? '').toString().toUpperCase();
      final seccion = (raw['seccion'] ?? '').toString().toUpperCase();
      final tags = raw['etiquetas'] is List
          ? (raw['etiquetas'] as List).map((e) => e.toString().toLowerCase()).toList()
          : const <String>[];
      final DishKind kind;
      if (categoria == 'A_LA_CARTA') {
        kind = DishKind.carta;
      } else if (categoria == 'EXTRA' ||
          seccion == 'ADICIONAL' ||
          tags.contains('desayuno')) {
        kind = DishKind.desayuno;
      } else {
        kind = switch (seccion) {
          'SOPA' => DishKind.sopa,
          'JUGO' => DishKind.bebida,
          'POSTRE' => DishKind.postre,
          _ => DishKind.segundo,
        };
      }
      final priceCents = _asNullableInt(raw['precioCentavos']);
      final desc = raw['descripcion']?.toString();
      return CatalogDish(
        id: (raw['id'] ?? '').toString(),
        name: (raw['nombre'] ?? '').toString(),
        kind: kind,
        price: priceCents != null ? Money.fromCents(priceCents) : null,
        description: desc != null && desc.trim().isNotEmpty ? desc : '',
        archived: raw['activo'] == false,
      );
    }).toList();
  }

  @override
  Future<CatalogDish> addDish(
    String restaurantId, {
    required String name,
    required DishKind kind,
    double? price,
    String? description,
  }) async {
    final mapped = _dishKindToApi(kind);
    final body = <String, dynamic>{
      'categoria': mapped.categoria,
      'seccion': mapped.seccion,
      'nombre': name.trim(),
      if (description != null && description.trim().isNotEmpty)
        'descripcion': description.trim(),
      if (price != null) 'precioCentavos': Money.toCents(price),
      if (mapped.etiquetas.isNotEmpty) 'etiquetas': mapped.etiquetas,
    };
    final res = await guard(
      () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/menu/platos',
            body: body,
            restaurant: true,
          ).then((v) => v ?? <String, dynamic>{}),
    );
    final priceCents = _asNullableInt(res['precioCentavos']);
    return CatalogDish(
      id: (res['id'] ?? '').toString(),
      name: (res['nombre'] ?? name.trim()).toString(),
      kind: kind,
      price: priceCents != null ? Money.fromCents(priceCents) : price,
      description: res['descripcion']?.toString() ?? description ?? '',
      archived: res['activo'] == false,
    );
  }

  @override
  Future<void> setDishArchived(
    String restaurantId,
    String dishId, {
    required bool archived,
  }) async {
    await guard(
      () => _api.send<dynamic>(
            'PATCH',
            '${ApiConfig.v1}/menu/platos/$dishId',
            body: {'activo': !archived},
            restaurant: true,
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // IOwnerCashRepository — Plantillas de planes y Cartulina (O8, O9, O10)
  // ---------------------------------------------------------------------------

  static String _planKindToApi(PlanKind k) => switch (k) {
        PlanKind.semanal => 'SEMANAL',
        PlanKind.quincenal => 'QUINCENAL',
        PlanKind.mensual => 'MENSUAL',
        PlanKind.libre => 'LIBRE',
      };

  static List<String> _encodeIncludes(OwnerPlanTemplate template) {
    final clean = [
      for (final s in template.includes)
        if (s.trim().isNotEmpty) s.trim(),
    ];
    return switch (template.coverage) {
      PlanCoverage.desayuno => [
          if (!clean.any((e) => e.toLowerCase().contains('desayuno'))) 'Desayuno',
          ...clean.where((e) => !e.toLowerCase().contains('sopa') && !e.toLowerCase().contains('segundo')),
        ],
      PlanCoverage.mixto => [
          if (!clean.any((e) => e.toLowerCase().contains('desayuno'))) 'Desayuno',
          if (!clean.any((e) => e.toLowerCase().contains('sopa'))) 'Sopa',
          if (!clean.any((e) => e.toLowerCase().contains('segundo'))) 'Segundo',
          ...clean.where((e) {
            final l = e.toLowerCase();
            return !l.contains('desayuno') && !l.contains('sopa') && !l.contains('segundo');
          }),
        ],
      PlanCoverage.almuerzo => clean.isEmpty ? const ['Sopa', 'Segundo', 'Jugo'] : clean,
    };
  }

  @override
  Future<OwnerPlanTemplate> savePlanTemplate(
    String restaurantId,
    OwnerPlanTemplate template,
  ) async {
    final isNew = template.id.isEmpty || template.id.startsWith('tpl-');
    final includes = _encodeIncludes(template);
    final baseBody = <String, dynamic>{
      'tipo': _planKindToApi(template.kind),
      'nombre': template.name.trim(),
      'almuerzos': template.lunches,
      'precioCentavos': Money.toCents(template.price),
      'vigenciaDias': template.validityDays,
      'cupos': template.quota > 0 ? template.quota : null,
      'diasValidos': template.days,
      'incluye': includes,
      'visibleEnMarketplace': template.visible,
    };

    Map<String, dynamic> res;
    if (isNew) {
      res = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/planes',
              body: baseBody,
              restaurant: true,
            ).then((v) => v ?? <String, dynamic>{}),
      );
    } else {
      final patchBody = <String, dynamic>{
        ...baseBody,
        'activo': template.active,
      };
      try {
        res = await guard(
          () => _api.send<Map<String, dynamic>>(
                'PATCH',
                '${ApiConfig.v1}/planes/${template.id}',
                body: patchBody,
                restaurant: true,
              ).then((v) => v ?? <String, dynamic>{}),
        );
      } on ApiException catch (e) {
        // OpenAPI tipa `diasValidos` de PATCH como `array<string>` en algunas versiones;
        // si la validación rechaza enteros con 400, reintenta convirtiendo a strings.
        if (e.status != 400) rethrow;
        res = await guard(
          () => _api.send<Map<String, dynamic>>(
                'PATCH',
                '${ApiConfig.v1}/planes/${template.id}',
                body: {
                  ...patchBody,
                  'diasValidos': template.days.map((d) => d.toString()).toList(),
                },
                restaurant: true,
              ).then((v) => v ?? <String, dynamic>{}),
        );
      }
    }

    final rawDays = res['diasValidos'] is List ? res['diasValidos'] as List : template.days;
    final rawIncl = res['incluye'] is List ? res['incluye'] as List : includes;
    final mappedIncl = rawIncl.map((e) => e.toString()).toList();
    return template.copyWith(
      id: (res['id'] ?? template.id).toString(),
      name: (res['nombre'] ?? template.name).toString(),
      lunches: _asInt(res['almuerzos'], template.lunches),
      price: res['precioCentavos'] != null
          ? Money.fromCents(_asInt(res['precioCentavos']))
          : template.price,
      validityDays: _asInt(res['vigenciaDias'], template.validityDays),
      coverage: _inferCoverage(mappedIncl),
      includes: mappedIncl,
      days: rawDays.map((e) => _asInt(e, 1)).toList(),
      quota: _asInt(res['cupos'], template.quota),
      visible: res['visibleEnMarketplace'] ?? template.visible,
      active: res['activo'] ?? template.active,
    );
  }

  @override
  Future<bool> setPlanActive(
    String restaurantId,
    String templateId, {
    required bool active,
  }) async {
    _lastError = null;
    try {
      await guard(
        () => _api.send<dynamic>(
              'PATCH',
              '${ApiConfig.v1}/planes/$templateId',
              body: {'activo': active},
              restaurant: true,
            ),
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo actualizar el estado del plan.';
      return false;
    }
  }

  @override
  Future<Map<String, int>> getPlanClientCounts(String restaurantId) async {
    final list = await guard(
      () => _api.getList('${ApiConfig.v1}/planes', restaurant: true),
    );
    return <String, int>{
      for (final raw in list.whereType<Map>())
        (raw['id'] ?? '').toString(): _asInt(raw['vendidosActivos']),
    };
  }

  @override
  Future<String?> registerPhysicalCard({
    required String restaurantId,
    String? clientId,
    String? newClientName,
    String? phone,
    required OwnerPlanTemplate template,
    required int used,
  }) async {
    _lastError = null;
    if (_isCashier) {
      _lastError = 'Solo el dueño puede registrar cartulinas.';
      return null;
    }
    try {
      var targetClientId = clientId?.trim() ?? '';
      String? createdClientId;
      if (targetClientId.isEmpty) {
        final name = newClientName?.trim() ?? '';
        if (name.isEmpty) {
          _lastError = 'Selecciona o escribe el nombre del cliente.';
          return null;
        }
        final created = await addClient(
          restaurantId,
          name: name,
          phone: phone?.trim() ?? '',
          notes: 'Cartulina migrada',
        );
        targetClientId = created.id;
        createdClientId = created.id;
      }

      final remaining = (template.lunches - used).clamp(1, template.lunches);
      final venceEl = _ymdOffset(template.validityDays);
      final divisor = template.lunches > 0 ? template.lunches : 1;
      final unitCents = (Money.toCents(template.price) / divisor).round();

      final res = await guard(
        () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/clientes/$targetClientId/migrar-cartulina',
              body: {
                'almuerzosRestantes': remaining,
                'venceEl': venceEl,
                'precioUnitarioCentavos': unitCents,
                'nombrePlan': template.name,
                'diasValidos': template.days,
                'anotacion': 'Cartulina de papel ($used/${template.lunches} usados)',
              },
              restaurant: true,
            ).then((v) => v ?? <String, dynamic>{}),
      );

      final planes = res['planes'] is List ? res['planes'] as List : const [];
      var planVendidoId = '';
      for (final p in planes.whereType<Map>()) {
        final id = (p['id'] ?? '').toString();
        if (id.isNotEmpty) {
          planVendidoId = id;
          break;
        }
      }
      if (planVendidoId.isEmpty) {
        _lastError = 'La cartulina se migró sin identificador para deshacer.';
        return null;
      }
      if (createdClientId != null && createdClientId.isNotEmpty) {
        _physicalCardCreatedClientId[planVendidoId] = createdClientId;
      }
      eventsService.track(
        'dueno.cartulina_migrada',
        restaurantId: restaurantId,
        props: {'restantes': remaining},
      );
      return planVendidoId;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return null;
    } catch (_) {
      _lastError = 'No se pudo registrar la cartulina.';
      return null;
    }
  }

  @override
  Future<bool> undoPhysicalCard(String cardId) async {
    _lastError = null;
    if (_isCashier) {
      _lastError = 'Solo el dueño puede deshacer una cartulina.';
      return false;
    }
    final intent = 'deshacer_cartulina_$cardId';
    final key = _idempotency.keyFor(intent);
    var ok = false;
    try {
      // Nota B-24: verificar en smoke test si POST /v1/planes-vendidos/{id}/deshacer
      // permite revertir planes con origen MIGRADA dentro de la ventana de gracia.
      await guard(
        () => _api.send<dynamic>(
              'POST',
              '${ApiConfig.v1}/planes-vendidos/$cardId/deshacer',
              idempotencyKey: key,
              restaurant: true,
            ),
      );
      ok = true;
      final createdClientId = _physicalCardCreatedClientId.remove(cardId);
      if (createdClientId != null && createdClientId.isNotEmpty) {
        try {
          await guard(
            () => _api.send<dynamic>(
                  'PATCH',
                  '${ApiConfig.v1}/clientes/$createdClientId',
                  body: const {'activo': false},
                  restaurant: true,
                ),
          );
        } catch (_) {}
      }
    } on ApiException catch (e) {
      _lastError = e.userMessage;
    } catch (_) {
      _lastError = 'No se pudo deshacer la cartulina.';
    } finally {
      _idempotency.done(intent);
    }
    return ok;
  }

  // ---------------------------------------------------------------------------
  // IOwnerMetricsRepository — "Tus números" (O14)
  // ---------------------------------------------------------------------------

  static const _peakDayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _peakHourIndices = [11, 12, 13, 14, 15];
  static const _peakHourLabels = ['11h', '12h', '13h', '14h', '15h'];

  static String _weeklyPrefKey(String restaurantId) =>
      'bocadoo_weekly_summary_$restaurantId';

  static String _logoPrefKey(String restaurantId) =>
      'bocadoo_local_logo_$restaurantId';

  static DateTime _localDateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Future<OwnerMetrics> getMetrics(
    String restaurantId, {
    required MetricsPeriod period,
  }) async {
    if (_isCashier) {
      return const OwnerMetrics(
        servedToday: 0,
        servedLastWeekSameTime: null,
        pendingLunches: 0,
        clientsWithPlan: 0,
        dishes: [],
        expiredLunches: 0,
        expiredPlans: 0,
        expiredValue: 0,
        salesCash: 0,
        salesTransfer: 0,
        plansSold: 0,
        renewals: [],
        absent: [],
        peakGrid: [],
        peakDays: [],
        peakHours: [],
        weeklySummaryEnabled: false,
        weekServed: 0,
        weekCollected: 0,
      );
    }

    final cached = _metricsCache[period];
    if (cached != null && DateTime.now().difference(cached.at).inSeconds < 60) {
      return cached.value;
    }

    final ecNow = EcuadorTime.now();
    final todayDate = _localDateOnly(ecNow);
    final todayStr = _formatYmd(todayDate);
    final totalDays = period == MetricsPeriod.semana ? 7 : 30;
    final desdeDate = todayDate.subtract(Duration(days: totalDays - 1));
    final desdeStr = _formatYmd(desdeDate);
    final lastWeekSameDayStr = _formatYmd(todayDate.subtract(const Duration(days: 7)));

    // 7 días recientes para el mapa de calor semanal y resumen semanal.
    final weekDates = [
      for (var i = 6; i >= 0; i--) todayDate.subtract(Duration(days: i)),
    ];

    final prefsFuture = SharedPreferences.getInstance();
    final pendingFuture = guard(
      () => _api.getMap('${ApiConfig.v1}/reportes/almuerzos-pendientes', restaurant: true),
    );
    final rankingFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/reportes/ranking-platos',
        query: {'desde': _formatYmd(todayDate.subtract(const Duration(days: 29))), 'hasta': todayStr, 'limit': 5},
        restaurant: true,
      ),
    );
    final ventasPlanesFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/reportes/ventas-planes',
        query: {'desde': desdeStr, 'hasta': todayStr},
        restaurant: true,
      ),
    );
    final followUpFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/reportes/clientes-a-contactar',
        query: const {'limit': 50},
        restaurant: true,
      ),
    );
    final lastWeekHourlyFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/reportes/horas-pico',
        query: {'desde': lastWeekSameDayStr, 'hasta': lastWeekSameDayStr},
        restaurant: true,
      ),
    );

    // Consultas diarias en lotes acotados (máx. 5 paralelas).
    final summariesByDate = <String, Map<String, dynamic>>{};
    final allDates = [
      for (var i = totalDays - 1; i >= 0; i--)
        _formatYmd(todayDate.subtract(Duration(days: i))),
    ];
    for (var i = 0; i < allDates.length; i += 5) {
      final chunk = allDates.sublist(i, (i + 5).clamp(0, allDates.length));
      final results = await Future.wait([
        for (final ymd in chunk)
          guard(
            () => _api.getMap(
              '${ApiConfig.v1}/reportes/resumen-diario',
              query: {'fecha': ymd},
              restaurant: true,
            ),
          ),
      ]);
      for (var j = 0; j < chunk.length; j++) {
        summariesByDate[chunk[j]] = results[j];
      }
    }

    final peakByWeekday = <int, List<int>>{};
    for (var i = 0; i < weekDates.length; i += 4) {
      final chunk = weekDates.sublist(i, (i + 4).clamp(0, weekDates.length));
      final results = await Future.wait([
        for (final dt in chunk)
          guard(
            () => _api.getMap(
              '${ApiConfig.v1}/reportes/horas-pico',
              query: {'desde': _formatYmd(dt), 'hasta': _formatYmd(dt)},
              restaurant: true,
            ),
          ),
      ]);
      for (var j = 0; j < chunk.length; j++) {
        final porHora = results[j]['porHora'] is List ? results[j]['porHora'] as List : const [];
        final countsByHour = <int, int>{};
        for (final row in porHora.whereType<Map>()) {
          countsByHour[_asInt(row['hora'])] = _asInt(row['total']);
        }
        peakByWeekday[chunk[j].weekday - 1] = [
          for (final h in _peakHourIndices) countsByHour[h] ?? 0,
        ];
      }
    }

    final prefs = await prefsFuture;
    final pendingMap = await pendingFuture;
    final rankingMap = await rankingFuture;
    final ventasPlanesMap = await ventasPlanesFuture;
    final followUpMap = await followUpFuture;
    final lastWeekHourlyMap = await lastWeekHourlyFuture;

    // Hoy + misma hora semana pasada
    final todaySummary = summariesByDate[todayStr] ?? const {};
    final todayAlmuerzos = todaySummary['almuerzos'] is Map ? todaySummary['almuerzos'] as Map : const {};
    final todayPos = todaySummary['ventasPos'] is Map ? todaySummary['ventasPos'] as Map : const {};
    final servedToday = _asInt(todayAlmuerzos['servidos']) + _asInt(todayPos['almuerzos']);

    final lastWeekPorHora = lastWeekHourlyMap['porHora'] is List
        ? lastWeekHourlyMap['porHora'] as List
        : const [];
    var servedLastWeekSameTime = 0;
    for (final row in lastWeekPorHora.whereType<Map>()) {
      if (_asInt(row['hora'], 24) <= ecNow.hour) {
        servedLastWeekSameTime += _asInt(row['total']);
      }
    }

    // Almuerzos pendientes
    final pendTotal = pendingMap['total'] is Map ? pendingMap['total'] as Map : const {};
    final pendingLunches = _asInt(pendTotal['almuerzos']);
    final clientsWithPlan = _asInt(pendTotal['clientes']);

    // Ranking de platos
    final rankItems = rankingMap['items'] is List ? rankingMap['items'] as List : const [];
    final dishes = rankItems.whereType<Map>().map((raw) {
      final plato = raw['plato'] is Map ? raw['plato'] as Map : const {};
      return DishRank(
        name: (plato['nombre'] ?? '').toString(),
        orders: _asInt(raw['unidades']),
      );
    }).toList();

    // Dinero: planes vendidos y desglose Efectivo vs Transferencia/Deuna
    final vpTotal = ventasPlanesMap['total'] is Map ? ventasPlanesMap['total'] as Map : const {};
    final plansSold = _asInt(vpTotal['vendidos']);
    var cashCents = 0;
    var transferCents = 0;
    for (final ymd in allDates) {
      final sum = summariesByDate[ymd];
      if (sum == null) continue;
      final ing = sum['ingresos'] is Map ? sum['ingresos'] as Map : const {};
      final metodos = ing['porMetodo'] is List ? ing['porMetodo'] as List : const [];
      for (final m in metodos.whereType<Map>()) {
        final code = (m['metodo'] ?? '').toString().toUpperCase();
        final cents = _asInt(m['centavos']);
        if (code == 'EFECTIVO') {
          cashCents += cents;
        } else if (code == 'TRANSFERENCIA' || code == 'DEUNA') {
          transferCents += cents;
        }
      }
    }

    // Últimos 7 días para la tarjeta "Resumen semanal"
    var weekServed = 0;
    var weekCollectedCents = 0;
    for (final dt in weekDates) {
      final sum = summariesByDate[_formatYmd(dt)];
      if (sum == null) continue;
      final alm = sum['almuerzos'] is Map ? sum['almuerzos'] as Map : const {};
      final pos = sum['ventasPos'] is Map ? sum['ventasPos'] as Map : const {};
      final ing = sum['ingresos'] is Map ? sum['ingresos'] as Map : const {};
      weekServed += _asInt(alm['servidos']) + _asInt(pos['almuerzos']);
      weekCollectedCents += _asInt(ing['totalCentavos']);
    }

    // Seguimiento: por renovar vs no han vuelto
    final followItems = followUpMap['items'] is List ? followUpMap['items'] as List : const [];
    final renewals = <ClientFollowUp>[];
    final absent = <ClientFollowUp>[];
    for (final raw in followItems.whereType<Map>()) {
      final motivos = raw['motivos'] is List
          ? (raw['motivos'] as List).map((e) => e.toString().toUpperCase()).toList()
          : const <String>[];
      final name = (raw['nombre'] ?? '').toString();
      final phone = Phone.toLocal(raw['telefono']?.toString());
      final left = _asInt(raw['almuerzosRestantes']);
      final diasSin = _asInt(raw['diasSinActividad']);
      final venceStr = raw['venceEl']?.toString();
      final venceDt = venceStr != null ? DateTime.tryParse(venceStr) : null;
      final daysToExpire = venceDt == null
          ? diasSin
          : _localDateOnly(venceDt).difference(todayDate).inDays.clamp(0, 999);

      final item = ClientFollowUp(
        name: name,
        phone: phone,
        days: motivos.contains('SIN_VENIR') && !motivos.contains('POR_VENCER') && !motivos.contains('PARA_RENOVAR')
            ? diasSin
            : daysToExpire,
        lunchesLeft: left,
      );
      if (motivos.contains('POR_VENCER') || motivos.contains('PARA_RENOVAR')) {
        renewals.add(item);
      } else if (motivos.contains('SIN_VENIR')) {
        absent.add(item);
      }
    }

    final peakGrid = [
      for (var wd = 0; wd < 7; wd++)
        peakByWeekday[wd] ?? List<int>.filled(_peakHourIndices.length, 0),
    ];

    final metrics = OwnerMetrics(
      servedToday: servedToday,
      servedLastWeekSameTime: servedLastWeekSameTime > 0 ? servedLastWeekSameTime : null,
      pendingLunches: pendingLunches,
      clientsWithPlan: clientsWithPlan,
      dishes: dishes,
      // B-18: ocultado en UI cuando !ApiCapabilities.expiredLunchesReport
      expiredLunches: 0,
      expiredPlans: 0,
      expiredValue: 0,
      salesCash: Money.fromCents(cashCents),
      salesTransfer: Money.fromCents(transferCents),
      plansSold: plansSold,
      renewals: renewals,
      absent: absent,
      peakGrid: peakGrid,
      peakDays: _peakDayNames,
      peakHours: _peakHourLabels,
      weeklySummaryEnabled: prefs.getBool(_weeklyPrefKey(restaurantId)) ?? false,
      weekServed: weekServed,
      weekCollected: Money.fromCents(weekCollectedCents),
    );
    _metricsCache[period] = _MetricsCacheEntry(value: metrics, at: DateTime.now());
    eventsService.track(
      'dueno.metricas_vistas',
      restaurantId: restaurantId,
      props: {'periodo': period.name},
    );
    return metrics;
  }

  @override
  Future<bool> setWeeklySummary(String restaurantId, {required bool enabled}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_weeklyPrefKey(restaurantId), enabled);
      _metricsCache.clear();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // IOwnerSettingsRepository — Datos y logo del local (O16)
  // ---------------------------------------------------------------------------

  @override
  Future<LocalInfo> getLocalInfo(String restaurantId) async {
    final restFuture = _fetchRestaurantMap();
    final prefsFuture = SharedPreferences.getInstance();
    final data = await restFuture;
    final prefs = await prefsFuture;
    final b64 = prefs.getString(_logoPrefKey(restaurantId));
    Uint8List? localLogo;
    if (b64 != null && b64.isNotEmpty) {
      try {
        localLogo = base64Decode(b64);
      } catch (_) {
        localLogo = null;
      }
    }
    final remoteLogo = data['logoUrl']?.toString();
    return LocalInfo(
      name: (data['nombre'] ?? '').toString(),
      address: (data['direccion'] ?? '').toString(),
      seats: _asInt(data['puestos']),
      logo: localLogo,
      logoUrl: remoteLogo != null && remoteLogo.isNotEmpty ? remoteLogo : null,
    );
  }

  @override
  Future<bool> setLogo(String restaurantId, Uint8List? bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _logoPrefKey(restaurantId);
      if (bytes == null || bytes.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, base64Encode(bytes));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // P-01 · Solicitudes de plan enviadas por comensales (solo capa de repositorio)
  // ---------------------------------------------------------------------------

  Future<List<OwnerPlanRequest>> getPlanRequests() async {
    final list = await guard(
      () => _api.getList('${ApiConfig.v1}/solicitudes-plan', restaurant: true),
    );
    return list.whereType<Map>().map((raw) {
      final cliente = raw['cliente'] is Map ? raw['cliente'] as Map : const {};
      final plan = raw['plan'] is Map ? raw['plan'] as Map : const {};
      return OwnerPlanRequest(
        id: (raw['id'] ?? '').toString(),
        clientId: (cliente['id'] ?? '').toString(),
        clientName: (cliente['nombre'] ?? '').toString(),
        planId: (plan['id'] ?? '').toString(),
        planName: (plan['nombre'] ?? '').toString(),
        price: Money.fromCents(_asInt(plan['precioCentavos'])),
        lunches: _asInt(plan['almuerzos']),
        createdAt: _parseDateTime(raw['creadaEn']),
      );
    }).toList();
  }

  Future<bool> chargePlanRequest(
    String requestId, {
    required OwnerPayMethod method,
  }) async {
    _lastError = null;
    final intent = 'cobrar_solicitud_$requestId';
    final key = _idempotency.keyFor(intent);
    var ok = false;
    try {
      await guard(
        () => _api.send<dynamic>(
              'POST',
              '${ApiConfig.v1}/solicitudes-plan/$requestId/cobrar',
              body: {
                'metodoPago': _mapPayMethodApi(method),
                'pagoConfirmado': true,
              },
              idempotencyKey: key,
              restaurant: true,
            ),
      );
      ok = true;
      eventsService.track(
        'dueno.plan_vendido',
        props: {
          'metodo': _mapPayMethodApi(method),
          'origen': 'solicitud',
        },
      );
    } on ApiException catch (e) {
      _lastError = e.userMessage;
    } catch (_) {
      _lastError = 'No se pudo cobrar la solicitud de plan.';
    } finally {
      _idempotency.done(intent);
    }
    return ok;
  }

  Future<bool> rejectPlanRequest(String requestId) async {
    _lastError = null;
    try {
      await guard(
        () => _api.send<dynamic>(
              'POST',
              '${ApiConfig.v1}/solicitudes-plan/$requestId/rechazar',
              restaurant: true,
            ),
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo rechazar la solicitud de plan.';
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Opiniones (Fase 5 · O15)
  // ---------------------------------------------------------------------------

  static String _mapOpinionTagUi(dynamic raw) {
    return switch ((raw ?? '').toString().toUpperCase()) {
      'RICO' => 'Rico',
      'RAPIDO' => 'Rápido',
      'BUENA_PORCION' => 'Porción',
      'BUENA_ATENCION' => 'Buena atención',
      'LIMPIO' => 'Limpio',
      'FRIO' => 'Frío',
      'SALADO' => 'Salado',
      'PORCION_PEQUENA' => 'Porción pequeña',
      'DEMORA' => 'Demora',
      'MALA_ATENCION' => 'Mala atención',
      final other when other.isEmpty => 'Opinión',
      final other =>
        '${other[0].toUpperCase()}${other.substring(1).toLowerCase().replaceAll('_', ' ')}',
    };
  }

  @override
  Future<List<OwnerOpinion>> getOpinions(String restaurantId) async {
    final allRaw = <Map<String, dynamic>>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final res = await guard(
        () => _api.getMap(
          '${ApiConfig.v1}/opiniones',
          query: {
            'limit': 50,
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          },
          restaurant: true,
        ),
      );
      final items = res['items'] is List ? res['items'] as List : const [];
      for (final raw in items.whereType<Map>()) {
        allRaw.add(Map<String, dynamic>.from(raw));
      }
      final next = res['nextCursor']?.toString();
      if (next == null || next.isEmpty) break;
      cursor = next;
    }

    // TODO(backend): B-22 — GET /v1/opiniones no incluye telefono ni clienteId.
    // Se intenta enriquecer por coincidencia exacta única de nombre con /v1/clientes.
    final clientsByLowerName = <String, List<OwnerClient>>{};
    try {
      final clients = await getClients(restaurantId);
      for (final c in clients) {
        final key = c.name.trim().toLowerCase();
        if (key.isEmpty) continue;
        clientsByLowerName.putIfAbsent(key, () => []).add(c);
      }
    } catch (_) {}

    _clientIdByOpinionId.clear();
    final out = <OwnerOpinion>[];
    for (final raw in allRaw) {
      final id = (raw['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final cliente = raw['cliente'] is Map
          ? Map<String, dynamic>.from(raw['cliente'] as Map)
          : const <String, dynamic>{};
      final dinerName = (cliente['nombre'] ?? '').toString();
      final matches = clientsByLowerName[dinerName.trim().toLowerCase()];
      final matchedClient =
          matches != null && matches.length == 1 ? matches.first : null;
      if (matchedClient != null) {
        _clientIdByOpinionId[id] = matchedClient.id;
      }

      final tagsRaw = raw['etiquetas'] is List
          ? raw['etiquetas'] as List
          : const [];
      final tag = tagsRaw.isNotEmpty
          ? _mapOpinionTagUi(tagsRaw.first)
          : 'Opinión';
      final noteRaw = raw['comentario']?.toString().trim();
      final note = noteRaw != null && noteRaw.isNotEmpty ? noteRaw : null;

      final respMap = raw['respuesta'] is Map
          ? Map<String, dynamic>.from(raw['respuesta'] as Map)
          : null;
      final serverReply = respMap?['texto']?.toString().trim();
      final pendingReply = _optimisticOpinionReplies[id];
      final effectiveReply = pendingReply ??
          (serverReply != null && serverReply.isNotEmpty ? serverReply : null);

      out.add(OwnerOpinion(
        id: id,
        dinerName: dinerName,
        tag: tag,
        createdAt: _parseDateTime(raw['creadoEn'] ?? raw['almuerzoEn']),
        note: note,
        reply: effectiveReply,
        phone: matchedClient != null && matchedClient.phone.isNotEmpty
            ? matchedClient.phone
            : null,
        canReplaceLunch:
            matchedClient != null && matchedClient.habitualPlan != null,
      ));
    }

    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<bool> replyOpinion(
    String restaurantId,
    String opinionId,
    OpinionReply reply,
  ) async {
    _lastError = null;
    final clientId = _clientIdByOpinionId[opinionId];
    if (reply == OpinionReply.replaceLunch &&
        (clientId == null || clientId.isEmpty)) {
      _lastError =
          'No pudimos vincular esta opinión con un cliente del local para reponer su almuerzo.';
      return false;
    }

    final replyText = reply == OpinionReply.replaceLunch
        ? 'Almuerzo repuesto (+1) · Gracias por avisarnos'
        : '¡Gracias por tu opinión!';

    // TODO(backend): B-21 — No existe POST /v1/opiniones/{id}/deshacer ni anulación de migrar-cartulina.
    // Se difiere ambos envíos 11 s con DeferredCommit para mantener "Deshacer" real.
    _optimisticOpinionReplies[opinionId] = replyText;
    final commit = _opinionReplyCommits.putIfAbsent(
      opinionId,
      () => DeferredCommit(delay: const Duration(seconds: 11)),
    );
    commit.schedule(
      () async {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/opiniones/$opinionId/responder',
            body: {'respuesta': replyText},
            restaurant: true,
          ),
        );
        if (reply == OpinionReply.replaceLunch &&
            clientId != null &&
            clientId.isNotEmpty) {
          var unitCents = _cachedLunchPriceCents;
          if (unitCents <= 0) {
            try {
              final r = await _fetchRestaurantMap();
              unitCents = _asInt(r['precioSueltoCentavos'], 300);
            } catch (_) {
              unitCents = 300;
            }
          }
          await guard(
            () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/clientes/$clientId/migrar-cartulina',
              body: {
                'almuerzosRestantes': 1,
                'venceEl': _ymdOffset(30),
                'precioUnitarioCentavos': unitCents > 0 ? unitCents : 300,
                'nombrePlan': 'Reposición por opinión',
                'anotacion': 'Reposición desde buzón de opiniones',
              },
              restaurant: true,
            ),
          );
        }
        _optimisticOpinionReplies.remove(opinionId);
        eventsService.track(
          'dueno.opinion_respondida',
          restaurantId: restaurantId,
          props: {'repuso_almuerzo': reply == OpinionReply.replaceLunch},
        );
      },
      onError: (err) {
        _optimisticOpinionReplies.remove(opinionId);
        if (err is ApiException) {
          _lastError = err.userMessage;
        }
      },
    );
    return true;
  }

  @override
  Future<bool> undoReply(String opinionId) async {
    _lastError = null;
    final cancelled = _opinionReplyCommits[opinionId]?.cancel() ?? false;
    if (cancelled) {
      _optimisticOpinionReplies.remove(opinionId);
      return true;
    }
    _lastError = 'El tiempo para deshacer ya venció.';
    return false;
  }
}
