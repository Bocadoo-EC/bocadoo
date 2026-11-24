import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/analytics/events_service.dart';
import '../../../core/config/zones.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
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
  int? remainingLunches;
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

class _ApiRedemptionBatch {
  _ApiRedemptionBatch({
    required this.batchId,
    required this.passId,
    required this.restaurantId,
    required this.customerName,
    required this.transactionId,
    this.primaryConsumoId,
    this.clientId,
  });

  final String batchId;
  final String passId;
  final String restaurantId;
  final String customerName;
  final String transactionId;
  final String? primaryConsumoId;
  final String? clientId;
  int extraGuests = 0;
  final List<String> extraConsumoIds = [];
  Future<void>? pendingDispatch;
  bool undone = false;
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
  ApiOwnerRepository({required this._api, required this._session});

  final ApiClient _api;
  final SessionNotifier _session;
  final IdempotencyStore _idempotency = IdempotencyStore();

  final Map<String, String> _consumoIdByPassId = {};
  final Map<String, _ApiRedemptionBatch> _batchesById = {};
  final Map<String, String> _lastBatchByPassId = {};
  final Map<String, _SaleUndoKind> _saleUndoById = {};
  final Map<String, _OrderCacheEntry> _ordersByNumber = {};
  final Map<String, String> _orderClientIdByNumber = {};
  final Map<String, String> _orderDishByNumber = {};

  /// ID de cliente asociado a una preorden cargada recientemente (si el backend lo envió).
  String? clientIdForOrder(String orderNumber) =>
      _orderClientIdByNumber[orderNumber];
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
  String? _lastError;
  Map<String, String> _lastFieldErrors = const {};

  bool get _isCashier => _session.isCashierAccount;

  /// Devuelve y limpia el último mensaje de error legible generado por una
  /// operación de caja/pedidos/cierre que retorna `bool` o `null`.
  String? consumeLastError() {
    final err = _lastError;
    _lastError = null;
    return err;
  }

  /// Devuelve y limpia el mapa de errores de validación por campo (`400 problem+json`).
  Map<String, String> consumeLastFieldErrors() {
    final errs = _lastFieldErrors;
    _lastFieldErrors = const {};
    return errs;
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
    return _tryParseDateTime(raw) ?? DateTime.now();
  }

  /// Parsea fechas ISO o epochs numéricos devolviendo `null` cuando no hay hora
  /// real registrada (evita sustituir logs antiguos por `DateTime.now()`).
  static DateTime? _tryParseDateTime(
    dynamic raw, {
    dynamic timeFallback,
    dynamic dateFallback,
  }) {
    if (raw is DateTime) return raw.toLocal();
    if (raw is int) {
      final ms = raw > 1000000000000 ? raw : raw * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    if (raw is num) {
      final v = raw.toInt();
      final ms = v > 1000000000000 ? v : v * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final s = raw.trim();
      final hasTime = s.contains(':') || s.contains('T');
      if (hasTime) {
        final parsed = DateTime.tryParse(s);
        if (parsed != null) return parsed.toLocal();
      }
    }

    final timeStr = timeFallback?.toString().trim() ?? '';
    if (timeStr.isNotEmpty && timeStr.contains(':')) {
      final dateStr = (raw is String && raw.trim().length >= 10)
          ? raw.trim().substring(0, 10)
          : (dateFallback?.toString().trim() ?? '');
      if (dateStr.length >= 10) {
        final hhmmss = timeStr.length == 5 ? '$timeStr:00' : timeStr;
        final combined = DateTime.tryParse(
          '${dateStr.substring(0, 10)}T$hhmmss',
        );
        if (combined != null) return combined.toLocal();
      }
    }
    return null;
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

  static String _extractPlatosLabel(
    Map? almuerzo, {
    Object? platoNombre,
    String fallback = 'Almuerzo del día',
  }) {
    final direct = platoNombre?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final platos = almuerzo?['platos'] is List
        ? almuerzo!['platos'] as List
        : const [];
    final names = <String>[];
    for (final p in platos.whereType<Map>()) {
      final n = (p['nombre'] ?? '').toString().trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names.isNotEmpty ? names.join(' + ') : fallback;
  }

  Future<Map<String, dynamic>> _fetchRestaurantMap() async {
    final data = await guard(
      () => _api.getMap('${ApiConfig.v1}/restaurante', restaurant: true),
    );
    final lunchCents = _asInt(data['precioSueltoCentavos']);
    if (lunchCents > 0) _cachedLunchPriceCents = lunchCents;
    return data;
  }

  DateTime? _parseFutureLocal(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt != null && dt.isAfter(DateTime.now())) {
      return dt;
    }
    return null;
  }

  /// Lee `llenoManualHasta` desde `GET /v1/restaurante` para inicializar el
  /// estado del interruptor de local lleno al abrir Caja.
  Future<DateTime?> fetchManualBusyUntil() async {
    try {
      final data = await _fetchRestaurantMap();
      return _parseFutureLocal(data['llenoManualHasta']);
    } catch (_) {
      return null;
    }
  }

  /// Lee el estado real de disponibilidad desde `GET /v1/restaurante`
  /// (`estado`, `ocupacion`, `llenoManualHasta` y `concurridoManualHasta`).
  Future<
    ({
      bool isOpen,
      ManualOccupancyStatus manual,
      DateTime? fullUntil,
      DateTime? concurridoUntil,
    })
  >
  fetchManualOccupancyState() async {
    try {
      final data = await _fetchRestaurantMap();
      final estado = (data['estado'] ?? 'ACTIVO').toString().toUpperCase();
      final isOpen = estado == 'ACTIVO';
      if (!isOpen) {
        return (
          isOpen: false,
          manual: ManualOccupancyStatus.cerrado,
          fullUntil: null,
          concurridoUntil: null,
        );
      }

      final fullUntil = _parseFutureLocal(data['llenoManualHasta']);
      final concurridoUntil = _parseFutureLocal(data['concurridoManualHasta']);
      final ocupacion = data['ocupacion'] is Map
          ? data['ocupacion'] as Map
          : const {};
      final nivel = (ocupacion['nivel'] ?? '').toString().toUpperCase();
      final isFullByOccupancy = ocupacion['lleno'] == true || nivel == 'LLENO';

      // Un aforo >= 90% da LLENO aunque el dueño haya marcado Concurrido.
      if (fullUntil != null || isFullByOccupancy) {
        return (
          isOpen: true,
          manual: ManualOccupancyStatus.lleno,
          fullUntil: fullUntil,
          concurridoUntil: null,
        );
      }
      if (concurridoUntil != null) {
        return (
          isOpen: true,
          manual: ManualOccupancyStatus.concurrido,
          fullUntil: null,
          concurridoUntil: concurridoUntil,
        );
      }
      return (
        isOpen: true,
        manual: ManualOccupancyStatus.libre,
        fullUntil: null,
        concurridoUntil: null,
      );
    } catch (_) {
      return (
        isOpen: true,
        manual: ManualOccupancyStatus.libre,
        fullUntil: null,
        concurridoUntil: null,
      );
    }
  }

  /// Busca una preorden por UUID (`GET /v1/caja/pedidos/{id}`) para
  /// redirección universal del escáner (`O2`).
  Future<OwnerOrder?> resolveOrderById(String id) async {
    try {
      final data = await guard(
        () => _api.getMap('${ApiConfig.v1}/caja/pedidos/$id', restaurant: true),
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

  /// `["2x Churrasco", "Cola"]` a partir de `cartaItems` (`nombre` + `cantidad`).
  static List<String> _cartaItemLabels(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final c in raw.whereType<Map>())
        if ((c['nombre'] ??
                (c['plato'] is Map ? (c['plato'] as Map)['nombre'] : null) ??
                '')
            .toString()
            .isNotEmpty)
          () {
            final name = (c['nombre'] ?? (c['plato'] as Map)['nombre'])
                .toString();
            final qty = _asInt(c['cantidad'], 1);
            return qty > 1 ? '${qty}x $name' : name;
          }(),
    ];
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
    String? drink;
    String? dessert;
    for (final p in platos.whereType<Map>()) {
      final seccion = (p['seccion'] ?? '').toString().toUpperCase();
      final nombre = (p['nombre'] ?? '').toString();
      if (nombre.isEmpty) continue;
      if (seccion == 'SOPA') {
        soup ??= nombre;
      } else if (seccion == 'FUERTE' ||
          seccion == 'SEGUNDO' ||
          seccion == 'PLATO_FUERTE') {
        mainDish ??= nombre;
      } else if (seccion == 'JUGO' || seccion == 'BEBIDA') {
        drink ??= nombre;
      } else if (seccion == 'POSTRE') {
        dessert ??= nombre;
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

    final offerIdRaw = almuerzo?['ofertaId']?.toString().trim();
    final offerId = (offerIdRaw != null && offerIdRaw.isNotEmpty)
        ? offerIdRaw
        : null;
    final offersRaw = json['ofertas'] is List
        ? json['ofertas'] as List
        : const [];
    final offers = <String>[
      for (final o in offersRaw)
        if (o is Map && (o['nombre'] ?? o['ofertaId'] ?? o['id']) != null)
          (o['nombre'] ?? o['ofertaId'] ?? o['id']).toString()
        else if (o is String && o.trim().isNotEmpty)
          o.trim(),
    ];

    final cotizacion = json['cotizacion'] is Map
        ? Map<String, dynamic>.from(json['cotizacion'] as Map)
        : null;
    final quoteLineas = cotizacion?['lineas'] is List
        ? cotizacion!['lineas'] as List
        : const [];
    final hasPlanLineInQuote = quoteLineas.whereType<Map>().any(
      (l) => (l['fuente'] ?? '').toString().trim().toUpperCase() == 'PLAN',
    );
    final quoteBalanceToCollectCents = _asNullableInt(
      cotizacion?['saldoPorCobrarCentavos'],
    );

    final cliente = json['cliente'] is Map ? json['cliente'] as Map : null;
    final comensal = json['comensal'] is Map ? json['comensal'] as Map : null;
    final clientId = (cliente?['id'] ?? comensal?['id'] ?? '').toString().trim();
    final dinerName = (cliente?['nombre'] ?? comensal?['nombre'] ?? 'Comensal')
        .toString();

    final estado = (json['estado'] ?? 'EN_CAMINO').toString().toUpperCase();
    final paidByPlan =
        hasPlanLineInQuote || (almuerzo?['cubiertoPorPlan'] == true);
    final takeaway = json['paraLlevar'] == true;
    final number = _asInt(json['numero']).toString();
    final id = (json['id'] ?? '').toString();
    final rest = json['restaurante'] is Map ? json['restaurante'] as Map : null;
    final orderRestId =
        (rest?['id'] ??
                json['restauranteId'] ??
                _session.activeRestaurantId ??
                '')
            .toString();

    final baseCents = _asInt(almuerzo?['precioCentavos']);
    final recargoCents = takeaway
        ? (_asInt(json['recargoLlevarCentavos']) > 0
              ? _asInt(json['recargoLlevarCentavos'])
              : 25)
        : 0;
    final rawTotalCents = _asInt(json['totalCentavos']);
    final resolvedTotalCents = paidByPlan
        ? 0
        : (takeaway && baseCents > 0 && rawTotalCents <= baseCents
              ? baseCents + recargoCents
              : (rawTotalCents > 0
                    ? rawTotalCents
                    : (baseCents > 0 ? baseCents + recargoCents : 0)));
    final planCreditsUsed = _asInt(json['planCreditsUsed']);
    final rawCashToCollect =
        quoteBalanceToCollectCents ??
        json['cashToCollectCents'] ??
        json['saldoPorCobrarCentavos'] ??
        json['porCobrarCentavos'];
    final cashItems = _cartaItemLabels(json['cartaItems']);
    final cashToCollectCents = rawCashToCollect != null
        ? _asInt(rawCashToCollect)
        : (paidByPlan && cashItems.isNotEmpty ? rawTotalCents : 0);
    final amount = Money.fromCents(
      paidByPlan && cashToCollectCents > 0
          ? cashToCollectCents
          : resolvedTotalCents,
    );
    final validated = estado == 'CANJEADA';

    if (id.isNotEmpty && number.isNotEmpty) {
      BocadooQrParser.generateOrderCode(
        number,
        orderId: id,
        restaurantId: orderRestId,
      );
      final prev = _ordersByNumber[number];
      _ordersByNumber[number] = _OrderCacheEntry(
        id: id,
        number: number,
        paidByPlan: paidByPlan,
        validated: validated,
        amount: amount,
        consumoId: prev?.consumoId,
      );
      if (clientId.isNotEmpty) {
        _orderClientIdByNumber[number] = clientId;
      }
    }

    final cleanSummary = CajaDishSummaryBuilder.fromPayload(
      almuerzo: almuerzo,
      cartaItems: json['cartaItems'] is List
          ? json['cartaItems'] as List
          : null,
      extras: extras,
      cotizacion: cotizacion,
      dishSectionByLowerName: _dishSectionByLowerName,
    );
    if (cleanSummary != null && cleanSummary.isNotEmpty) {
      if (id.isNotEmpty) _cleanSummaryByOrderKey[id] = cleanSummary;
      if (number.isNotEmpty) _cleanSummaryByOrderKey['#$number'] = cleanSummary;
    }

    final createdAt = _parseDateTime(json['creadoEn']);
    final rawEta = json['horaEstimada'] ?? json['horaLlegada'];
    final estimatedArrival = rawEta != null
        ? _parseDateTime(rawEta)
        : createdAt.add(const Duration(minutes: 15));

    return OwnerOrder(
      id: id.isEmpty ? null : id,
      restaurantId: orderRestId.isEmpty ? null : orderRestId,
      clientId: clientId.isEmpty ? null : clientId,
      number: number,
      dinerName: dinerName,
      amount: amount,
      totalCents: resolvedTotalCents,
      planCreditsUsed: planCreditsUsed,
      cashToCollectCents: cashToCollectCents,
      cashItems: cashItems,
      createdAt: createdAt,
      estado: estado,
      soup: soup,
      main: mainDish,
      drink: drink,
      dessert: dessert,
      estimatedArrival: estimatedArrival,
      takeaway: takeaway,
      takeawaySurchargeCents: recargoCents > 0 ? recargoCents : 25,
      paidByPlan: paidByPlan,
      validated: validated,
      offerId: offerId,
      offers: offers,
      hasPlanLineInQuote: hasPlanLineInQuote,
      quoteBalanceToCollectCents: quoteBalanceToCollectCents,
    );
  }

  // ---------------------------------------------------------------------------
  // IOwnerRepository (Escáner O2 + Cierre / Resumen O1, O4)
  // ---------------------------------------------------------------------------

  final Set<String> _redeemedCodes = <String>{};
  bool _lastAlreadyRedeemed = false;
  final List<TransactionItem> _sessionValidatedTransactions =
      <TransactionItem>[];

  Future<bool> _isOrderAlreadyServed(
    String orderIdOrCode,
    String activeRestaurantId,
  ) async {
    final cleaned = BocadooQrParser.sanitizeManualInput(orderIdOrCode);
    try {
      final servidas = await guard(
        () => _api.getList(
          '${ApiConfig.v1}/caja/pedidos',
          query: {'estado': 'SERVIDA'},
          restaurant: true,
        ),
      );
      final numTarget =
          BocadooQrParser.resolveOrderNumber(orderIdOrCode) ??
          orderIdOrCode.replaceAll('#', '').trim();
      for (final raw in servidas.whereType<Map>()) {
        final rawNum = _asInt(raw['numero']).toString();
        final rawId = (raw['id'] ?? '').toString();
        final genCode = BocadooQrParser.generateOrderCode(
          rawNum,
          orderId: rawId,
          restaurantId: activeRestaurantId,
        );
        if (rawNum == numTarget ||
            rawId == orderIdOrCode.trim() ||
            (cleaned.length == BocadooQrParser.shortCodeLength &&
                genCode == cleaned)) {
          _redeemedCodes.add('ORD:$rawNum');
          _ordersByNumber.remove(rawNum);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<OwnerOrder?> _findOrderByAnyCode(
    String rawPayload,
    String restaurantId,
  ) async {
    final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
    final resolvedNum = BocadooQrParser.resolveOrderNumber(rawPayload);
    if (resolvedNum != null) {
      if (_uuidRegex.hasMatch(resolvedNum)) {
        return resolveOrderById(resolvedNum);
      }
      return resolveOrderByNumber(resolvedNum);
    }
    final trimmed = rawPayload.trim();
    final upper = trimmed.toUpperCase();
    if (upper.startsWith('BCD-ORD-') && trimmed.length > 8) {
      final q = trimmed.substring(8).trim();
      return _uuidRegex.hasMatch(q)
          ? resolveOrderById(q)
          : resolveOrderByNumber(q);
    }
    if (trimmed.startsWith('#') && trimmed.length > 1) {
      return resolveOrderByNumber(trimmed.substring(1).trim());
    }
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return resolveOrderByNumber(trimmed);
    }
    if (_uuidRegex.hasMatch(trimmed)) {
      return resolveOrderById(trimmed);
    }
    if (cleaned.length == BocadooQrParser.shortCodeLength) {
      final active = await getActiveOrders(restaurantId);
      for (final o in active) {
        final c1 = BocadooQrParser.generateOrderCode(
          o.number,
          orderId: o.id,
          restaurantId: restaurantId,
        );
        final c2 = BocadooQrParser.generateOrderCode(o.number);
        if (c1 == cleaned || c2 == cleaned) return o;
      }
    }
    return null;
  }

  Future<String?> _findTableIdByAnyCode(
    String rawPayload,
    String restaurantId,
  ) async {
    final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
    final resolvedId = BocadooQrParser.resolveTableId(rawPayload);
    if (resolvedId != null && resolvedId.isNotEmpty) return resolvedId;
    final trimmed = rawPayload.trim();
    final upper = trimmed.toUpperCase();
    if (upper.startsWith('BCD-MESA-') && trimmed.length > 9) {
      return trimmed.substring(9).trim();
    }
    if (cleaned.length == BocadooQrParser.shortCodeLength) {
      final tables = await getPendingTables(restaurantId);
      for (final t in tables) {
        final c1 = BocadooQrParser.generateTableCode(
          t.id,
          restaurantId: restaurantId,
        );
        final c2 = BocadooQrParser.generateTableCode(t.id);
        if (c1 == cleaned || c2 == cleaned) return t.id;
      }
    }
    return null;
  }

  @override
  Future<ScanResult> validateQrCode(String rawPayload) async {
    _lastError = null;
    final restaurantId = _session.activeRestaurantId ?? '';
    final isSignedPlanQr = rawPayload.startsWith('BCD1.');

    if (!isSignedPlanQr) {
      final backendCode = BocadooQrParser.extractPlanBackendToken(rawPayload);
      final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
      final codeKey = cleaned.length == BocadooQrParser.shortCodeLength
          ? cleaned
          : backendCode.trim().toUpperCase();

      // Regla 5.1: Validación de pertenencia al local para códigos cortos locales.
      final codeRestId = BocadooQrParser.restaurantForCode(rawPayload);
      if (codeRestId != null &&
          codeRestId.isNotEmpty &&
          restaurantId.isNotEmpty &&
          codeRestId != restaurantId) {
        return const ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Es de otro local',
          supportingLine: 'Este código pertenece a otro restaurante',
          actionRequired: 'NINGUNA',
        );
      }

      // Preorden activa (ORD-XXXXXX, BCD-ORD-, #N o UUID).
      final upperRaw = rawPayload.trim().toUpperCase();
      final isExplicitOrder =
          upperRaw.startsWith(BocadooQrParser.orderPrefix) ||
          upperRaw.startsWith('BCD-ORD-');
      if (!upperRaw.startsWith(BocadooQrParser.planPrefix)) {
        final order = await _findOrderByAnyCode(rawPayload, restaurantId);
        if (order != null) {
          final result = await confirmAndRedeemOrder(
            order.number,
            restaurantId,
            rawCodeKey: codeKey,
          );
          if (!result.isValid && result.supportingLine.isNotEmpty) {
            _lastError = result.supportingLine;
          }
          return result;
        }
        if (isExplicitOrder) {
          return const ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Preorden no encontrada',
            supportingLine: 'No encontramos esa preorden activa.',
            actionRequired: 'NINGUNA',
          );
        }
      }

      // Mesa activa (BCD-MESA- o código de mesa).
      final tableId = await _findTableIdByAnyCode(rawPayload, restaurantId);
      if (tableId != null) {
        final tableKey = 'MESA:$tableId';
        if (_redeemedCodes.contains(tableKey)) {
          return const ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Ya canjeado',
            supportingLine: 'Este código ya fue canjeado anteriormente',
            actionRequired: 'NINGUNA',
          );
        }
        final preview = await previewTable(restaurantId, tableId);
        final chargeId = await chargeTable(restaurantId, tableId);
        if (chargeId == null) {
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'No se pudo cobrar la mesa',
            supportingLine: _lastError ?? 'Verifica el estado de la mesa.',
            actionRequired: 'NINGUNA',
          );
        }
        final cashCollected = preview.lines.fold<double>(
          0,
          (sum, l) => sum + (l.via == TableChargeVia.cash ? l.amount : 0),
        );
        final lunchesFromPlan = preview.lines
            .where(
              (l) =>
                  l.via == TableChargeVia.plan ||
                  l.via == TableChargeVia.hostPlan,
            )
            .length;
        _redeemedCodes.add(tableKey);
        _redeemedCodes.add(codeKey);
        _sessionValidatedTransactions.insert(
          0,
          TransactionItem(
            id: chargeId,
            customerName: 'Mesa $tableId',
            type: cashCollected > 0 ? 'Venta Suelta' : 'Validado',
            amount: cashCollected,
            paymentMethod: cashCollected > 0 ? 'Efectivo' : 'Plan',
            timestamp: DateTime.now(),
          ),
        );
        return ScanResult(
          isValid: true,
          outcome: 'VERDE',
          title: 'Mesa $tableId registrada',
          supportingLine: '$lunchesFromPlan con plan · cobro registrado',
          passId: tableKey,
          actionRequired: 'NINGUNA',
        );
      }
    }

    // Envío exacto de `rawPayload` sin modificarlo, recortarlo ni transformarlo.
    final intent = 'validar:$restaurantId:$rawPayload';
    final ik = _idempotency.keyFor(intent);
    try {
      final data = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/validar',
              body: {'codigoQr': rawPayload},
              restaurant: true,
              idempotencyKey: ik,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
      _idempotency.done(intent);

      final resultado = (data['resultado'] ?? '').toString().toUpperCase();
      final mensaje = (data['mensaje'] ?? '').toString();
      final cliente = data['cliente'] is Map ? data['cliente'] as Map : null;
      final consumo = data['consumo'] is Map ? data['consumo'] as Map : null;
      final consumoPrevio = data['consumoPrevio'] is Map
          ? data['consumoPrevio'] as Map
          : null;
      final plan = data['plan'] is Map ? data['plan'] as Map : null;

      final clienteId = cliente?['id']?.toString();
      final clienteNombre = cliente?['nombre']?.toString();
      final consumoId = consumo?['id']?.toString();
      final planNombre = plan?['nombre']?.toString();
      final creadoEnRaw =
          consumo?['creadoEn'] ??
          consumo?['fecha'] ??
          consumo?['fechaHora'] ??
          data['canjeadoEn'];
      final redeemedAt = _tryParseDateTime(creadoEnRaw);
      if (consumoId != null && consumoId.isNotEmpty && redeemedAt != null) {
        _orderScanTimestampByKey[consumoId] = redeemedAt;
      }
      final prevCreadoRaw =
          consumoPrevio?['creadoEn'] ?? consumoPrevio?['fecha'];
      final DateTime? prevRedeemedAt = _tryParseDateTime(prevCreadoRaw);
      final rawPlatoNombre = (data['platoNombre'] ?? consumo?['platoNombre'])
          ?.toString()
          .trim();
      final dishDisplay = (rawPlatoNombre != null && rawPlatoNombre.isNotEmpty)
          ? rawPlatoNombre
          : 'Almuerzo del día (Prepagado)';
      final dishLabel = _extractPlatosLabel(
        null,
        platoNombre: rawPlatoNombre,
        fallback: 'Almuerzo del día',
      );

      final remaining = _asNullableInt(data['almuerzosRestantes']);
      final daysToExpire = _asNullableInt(data['diasParaVencer']);
      final planCreditsUsed = _asInt(data['planCreditsUsed']);
      final cashToCollectCents = _asInt(data['cashToCollectCents']);
      final cashItems = _cartaItemLabels(data['cartaItems']);

      eventsService.track(
        'dueno.qr_validado',
        restaurantId: restaurantId,
        props: {
          'resultado': resultado.isEmpty ? 'DESCONOCIDO' : resultado,
          'validado': resultado == 'OK' || resultado == 'OK_ADVERTENCIA',
        },
      );

      final passId =
          consumoId ??
          clienteId ??
          'qr-${DateTime.now().microsecondsSinceEpoch}';
      if (consumoId != null && consumoId.isNotEmpty) {
        _consumoIdByPassId[passId] = consumoId;
      }

      String? batchId;
      if (resultado == 'OK' || resultado == 'OK_ADVERTENCIA') {
        final now = DateTime.now();
        final txTime = redeemedAt ?? now;
        batchId = uuidV4();
        _batchesById[batchId] = _ApiRedemptionBatch(
          batchId: batchId,
          passId: passId,
          restaurantId: restaurantId,
          customerName: clienteNombre ?? 'Comensal',
          transactionId: passId,
          primaryConsumoId: consumoId,
          clientId: clienteId,
        );
        _lastBatchByPassId[passId] = batchId;

        // Si el comensal tenía una preorden EN_CAMINO pendiente, cerrarla ahora
        // que su almuerzo ya fue descontado del plan para evitar tarjetas fantasma.
        try {
          final activeOrders = await getEnCaminoOrders(restaurantId);
          final targetId = clienteId?.trim();
          final targetName = clienteNombre?.trim().toLowerCase();
          for (final ord in activeOrders) {
            final matchById =
                targetId != null &&
                targetId.isNotEmpty &&
                ord.clientId == targetId;
            final matchByName =
                targetName != null &&
                targetName.isNotEmpty &&
                ord.dinerName.trim().toLowerCase() == targetName;
            if ((matchById || matchByName) &&
                ord.cashToCollectCents == 0 &&
                ord.id != null &&
                ord.id!.isNotEmpty) {
              try {
                await guard(
                  () => _api.send<Map<String, dynamic>>(
                    'POST',
                    '${ApiConfig.v1}/caja/pedidos/${ord.id}/servir',
                    restaurant: true,
                  ),
                );
              } on ApiException {
                // Idempotente si ya estaba servida en backend.
              }
              _redeemedCodes.add('ORD:${ord.number}');
              _ordersByNumber.remove(ord.number);
              break;
            }
          }
        } catch (_) {}

        final isDup = _sessionValidatedTransactions.any(
          (tx) =>
              tx.id == passId ||
              (tx.customerName == (clienteNombre ?? 'Comensal') &&
                  tx.type == 'Canje de plan' &&
                  txTime.difference(tx.timestamp).abs().inSeconds < 5),
        );
        if (!isDup) {
          _sessionValidatedTransactions.insert(
            0,
            TransactionItem(
              id: passId,
              customerName: clienteNombre ?? 'Comensal',
              type: 'Canje de plan',
              amount: 0,
              paymentMethod: 'Plan',
              timestamp: txTime,
              detail: rawPlatoNombre != null && rawPlatoNombre.isNotEmpty
                  ? 'Canje de plan · $rawPlatoNombre (Prepagado)'
                  : 'Canje de plan · $dishLabel (Prepagado)',
            ),
          );
        }
      }

      switch (resultado) {
        case 'MENU_NO_PUBLICADO':
          return const ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'Menú no publicado',
            supportingLine:
                'No se puede escanear QR sin haber publicado el menú de hoy',
            actionRequired: 'PUBLISH_MENU',
          );
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
            batchRedemptionId: batchId,
            redeemedAt: redeemedAt ?? DateTime.now(),
            dishName: dishDisplay,
            actionRequired: 'NINGUNA',
            planCreditsUsed: planCreditsUsed,
            cashToCollectCents: cashToCollectCents,
            cashItems: cashItems,
          );
        case 'OK_ADVERTENCIA':
          final lowDays = daysToExpire != null && daysToExpire <= 3;
          return ScanResult(
            isValid: true,
            outcome: 'ADVERTENCIA',
            title: lowDays ? 'Por vencer' : 'Último almuerzo',
            supportingLine: mensaje.isNotEmpty
                ? mensaje
                : 'Renueva su plan hoy',
            studentName: clienteNombre,
            studentCareer: planNombre,
            passId: passId,
            remainingLunches: remaining,
            redemptionId: consumoId,
            batchRedemptionId: batchId,
            redeemedAt: redeemedAt ?? DateTime.now(),
            dishName: dishDisplay,
            actionRequired: 'VENDER_PLAN',
            planCreditsUsed: planCreditsUsed,
            cashToCollectCents: cashToCollectCents,
            cashItems: cashItems,
          );
        case 'DUPLICADO':
          return ScanResult(
            isValid: false,
            outcome: 'GRIS',
            title: 'Pedido ya descontado',
            supportingLine: 'Este pedido ya fue descontado anteriormente',
            studentName: clienteNombre,
            studentCareer: planNombre,
            redeemedAt: prevRedeemedAt,
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
            supportingLine: 'Este código pertenece a otro restaurante',
            studentName: clienteNombre,
            actionRequired: 'NINGUNA',
          );
        case 'QR_EXPIRADO':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'QR expirado',
            supportingLine: mensaje.isNotEmpty
                ? '$mensaje Pide al comensal que genere y muestre su código actual.'
                : 'El código venció. Pide al comensal que genere y muestre su código actual.',
            actionRequired: 'SCAN_AGAIN',
          );
        case 'QR_INVALIDO':
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'QR no válido',
            supportingLine: mensaje.isNotEmpty ? mensaje : 'Este código no pertenece a Bocadoo o no corresponde a este local.',
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
            supportingLine: mensaje.isNotEmpty ? mensaje : 'Este código no pertenece a Bocadoo o no corresponde a este local.',
            actionRequired: 'SCAN_AGAIN',
          );
      }
    } on ApiException catch (e) {
      if (!e.isNetwork && e.status != 504) {
        _idempotency.done(intent);
      }
      if (e.code == 'MENU_NO_PUBLICADO') {
        return const ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Menú no publicado',
          supportingLine:
              'No se puede escanear QR sin haber publicado el menú de hoy',
          actionRequired: 'PUBLISH_MENU',
        );
      }
      rethrow;
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
    throw UnimplementedError(
      'Usa sellPlanTemplate para vender planes en caja.',
    );
  }

  @override
  Future<TransactionSummary> getDailyClosingSummary(String restaurantId) async {
    final today = EcuadorTime.today();
    final cierreFuture = guard(
      () => _api.getMap('${ApiConfig.v1}/caja/cierre/$today', restaurant: true),
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

    var planCreditsToday = _asInt(cierre['planCreditsUsed'], -1);
    var cashToCollectToday = _asInt(cierre['cashToCollectCents'], -1);
    if (planCreditsToday < 0 || cashToCollectToday < 0) {
      // El cierre aún no trae el desglose híbrido: se suma desde los pedidos servidos de hoy.
      planCreditsToday = planCreditsToday < 0 ? 0 : planCreditsToday;
      cashToCollectToday = cashToCollectToday < 0 ? 0 : cashToCollectToday;
      try {
        final servidas = await guard(
          () => _api.getList(
            '${ApiConfig.v1}/caja/pedidos',
            query: {'estado': 'SERVIDA'},
            restaurant: true,
          ),
        );
        var credits = 0;
        var cash = 0;
        for (final p in servidas.whereType<Map>()) {
          final fecha = (p['fecha'] ?? '').toString();
          if (fecha.isNotEmpty && fecha != today) continue;
          credits += _asInt(p['planCreditsUsed']);
          cash += _asInt(p['cashToCollectCents']);
        }
        if (cierre['planCreditsUsed'] == null) planCreditsToday = credits;
        if (cierre['cashToCollectCents'] == null) cashToCollectToday = cash;
      } catch (_) {}
    }

    return TransactionSummary(
      date: EcuadorTime.now(),
      planCreditsUsedToday: planCreditsToday,
      cashToCollectToday: cashToCollectToday,
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
      final hasLunch = items.whereType<Map>().any(
        (i) => i['esAlmuerzo'] == true,
      );
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
      final fecha = (p['fecha'] ?? '').toString();
      if (fecha.isNotEmpty && fecha != today) continue;

      final numero = _asInt(p['numero']).toString();
      if (ventaOrderRefs.contains('Pedido #$numero')) continue;

      final cliente = p['cliente'] is Map ? p['cliente'] as Map : null;
      final comensal = p['comensal'] is Map ? p['comensal'] as Map : null;
      final name = (cliente?['nombre'] ?? comensal?['nombre'] ?? 'Comensal')
          .toString();
      final almuerzo = p['almuerzo'] is Map ? p['almuerzo'] as Map : null;
      final paidByPlan = almuerzo?['cubiertoPorPlan'] == true;
      final isPrepaid = paidByPlan && totalCents == 0;
      final dishLabel = _extractPlatosLabel(
        almuerzo,
        platoNombre: p['platoNombre'] ?? _orderDishByNumber[numero],
        fallback: 'Almuerzo del día',
      );

      out.add(
        TransactionItem(
          id: (p['id'] ?? '').toString(),
          customerName: 'Pedido #$numero · $name',
          type: isPrepaid ? 'Canje de plan' : 'Pedido #$numero',
          amount: Money.fromCents(paidByPlan ? 0 : totalCents),
          paymentMethod: isPrepaid ? 'Plan' : 'Efectivo',
          timestamp: _parseDateTime(
            p['canjeadoEn'] ?? p['servidoEn'] ?? p['creadoEn'],
          ),
          detail: isPrepaid ? 'Canje de plan · $dishLabel (Prepagado)' : null,
        ),
      );
      ventaOrderRefs.add('Pedido #$numero');
    }

    final existingIds = out.map((e) => e.id).toSet();
    for (final tx in _sessionValidatedTransactions) {
      if (existingIds.contains(tx.id)) continue;
      if (tx.type.startsWith('Pedido #') && ventaOrderRefs.contains(tx.type)) {
        continue;
      }
      final hasRecentDuplicate = out.any(
        (existing) =>
            existing.type == tx.type &&
            existing.customerName == tx.customerName &&
            existing.timestamp.difference(tx.timestamp).abs().inSeconds < 5,
      );
      if (hasRecentDuplicate) continue;
      out.add(tx);
    }

    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  final Map<String, DateTime> _orderScanTimestampByKey = {};
  final Map<String, String> _cleanSummaryByOrderKey = {};
  final Map<String, String> _cleanSummaryByCuentaId = {};
  final Map<String, String> _cleanSummaryByVentaId = {};
  final Map<String, String> _dishSectionByLowerName = {};

  @override
  Future<List<PendingPaymentItem>> getPendingPayments(
    String restaurantId,
  ) async {
    if (_isCashier) return const [];
    try {
      final rawList = await guard(
        () => _api.send<dynamic>(
          'GET',
          '${ApiConfig.v1}/pagos/pendientes',
          restaurant: true,
        ),
      );
      final list = rawList is List
          ? rawList
          : (rawList is Map
                ? ((rawList['items'] ?? rawList['data']) is List
                      ? (rawList['items'] ?? rawList['data']) as List
                      : const <dynamic>[])
                : const <dynamic>[]);
      return [
        for (final raw in list.whereType<Map>())
          if ((raw['pagoId'] ?? raw['id'] ?? '').toString().isNotEmpty)
            PendingPaymentItem(
              origen: (raw['origen'] ?? '').toString().trim().toUpperCase(),
              pagoId: (raw['pagoId'] ?? raw['id'] ?? '').toString(),
              origenId: (raw['origenId'] ?? '').toString(),
              montoCentavos: _asInt(raw['montoCentavos']),
              metodo: (raw['metodo'] ?? '').toString().trim(),
              fecha: raw['fecha']?.toString(),
              comprobanteUrl: raw['comprobanteUrl']?.toString(),
              creadoEn: _tryParseDateTime(raw['creadoEn']),
              clienteNombre: raw['clienteNombre']?.toString(),
              referencia: (raw['referencia'] ?? '').toString().trim(),
            ),
      ];
    } on ApiException catch (e) {
      if (e.status == 403) return const [];
      rethrow;
    }
  }

  @override
  Future<bool> resolvePendingPayment(
    String pagoId, {
    required bool confirm,
  }) async {
    _lastError = null;
    try {
      final action = confirm ? 'confirmar' : 'rechazar';
      await guard(
        () => _api.send<dynamic>(
          'POST',
          '${ApiConfig.v1}/pagos/$pagoId/$action',
          restaurant: true,
        ),
      );
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo resolver el pago pendiente.';
      return false;
    }
  }

  @override
  Future<List<CajaCuentaItem>> getCajaCuentasToday(String restaurantId) async {
    final res = await _fetchCajaCuentasMap();
    final rawItems = res['items'] is List
        ? res['items'] as List
        : (res['data'] is List ? res['data'] as List : const []);
    final out = <CajaCuentaItem>[];
    for (final raw in rawItems.whereType<Map>()) {
      final id = (raw['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final cotizacion = raw['cotizacion'] is Map
          ? raw['cotizacion'] as Map
          : null;
      final summary = CajaDishSummaryBuilder.fromPayload(
        almuerzo: raw['almuerzo'] is Map ? raw['almuerzo'] as Map : null,
        cartaItems: raw['cartaItems'] is List
            ? raw['cartaItems'] as List
            : null,
        extras: raw['extras'] is List ? raw['extras'] as List : null,
        cotizacion: cotizacion,
        dishSectionByLowerName: _dishSectionByLowerName,
      );
      if (summary != null && summary.isNotEmpty) {
        _cleanSummaryByCuentaId[id] = summary;
        final pid = (raw['pedidoId'] ?? '').toString();
        if (pid.isNotEmpty) _cleanSummaryByOrderKey[pid] = summary;
      }
      final pagador = raw['pagador'] is Map ? raw['pagador'] as Map : null;
      out.add(
        CajaCuentaItem(
          id: id,
          origen: (raw['origen'] ?? '').toString().toUpperCase(),
          estado: (raw['estado'] ?? '').toString().toUpperCase(),
          pagadorNombre: (pagador?['nombre'] ?? raw['pagadorNombre'])
              ?.toString(),
          saldoCentavos: _asInt(raw['saldoCentavos']),
          pagadoCentavos: _asInt(raw['pagadoCentavos']),
          cleanDishSummary: summary,
          pedidoId: raw['pedidoId']?.toString(),
          creadaEn: _tryParseDateTime(raw['creadaEn']),
          cobradaEn: _tryParseDateTime(raw['cobradaEn']),
        ),
      );
    }
    return out;
  }

  Future<Map<String, dynamic>> _fetchCajaCuentasMap() async {
    try {
      final raw = await guard(
        () => _api.send<dynamic>(
          'GET',
          '${ApiConfig.v1}/caja/cuentas',
          query: const {'estado': 'TODAS', 'limit': 50},
          restaurant: true,
        ),
      );
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      if (raw is List) return {'items': raw};
    } catch (_) {}
    return const {'items': <dynamic>[]};
  }

  @override
  Future<CajaMovementsPage> getCajaMovements(
    String restaurantId, {
    required String fecha,
    String? cursor,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'fecha': fecha,
      'limit': limit,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final isFirstTodayPage =
        (cursor == null || cursor.isEmpty) && fecha == EcuadorTime.today();

    final Future<Map<String, dynamic>> movFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/caja/movimientos',
        query: query,
        restaurant: true,
      ),
    );
    final Future<Map<String, dynamic>?> cuentasFuture = isFirstTodayPage
        ? _fetchCajaCuentasMap()
        : Future<Map<String, dynamic>?>.value(null);

    if (_dishSectionByLowerName.isEmpty) {
      try {
        await getDishes(restaurantId);
      } catch (_) {}
    }

    final results = await Future.wait([movFuture, cuentasFuture]);
    final data = results[0] ?? const <String, dynamic>{};
    final cuentasData = results[1];

    if (cuentasData != null) {
      final rawCuentas = cuentasData['items'] is List
          ? cuentasData['items'] as List
          : (cuentasData['data'] is List
                ? cuentasData['data'] as List
                : const []);
      for (final c in rawCuentas.whereType<Map>()) {
        final cid = (c['id'] ?? '').toString();
        final summary = CajaDishSummaryBuilder.fromPayload(
          almuerzo: c['almuerzo'] is Map ? c['almuerzo'] as Map : null,
          cartaItems: c['cartaItems'] is List ? c['cartaItems'] as List : null,
          extras: c['extras'] is List ? c['extras'] as List : null,
          cotizacion: c['cotizacion'] is Map ? c['cotizacion'] as Map : null,
          dishSectionByLowerName: _dishSectionByLowerName,
        );
        if (summary == null || summary.isEmpty) continue;
        if (cid.isNotEmpty) _cleanSummaryByCuentaId[cid] = summary;
        final pid = (c['pedidoId'] ?? '').toString();
        if (pid.isNotEmpty) _cleanSummaryByOrderKey[pid] = summary;
      }
    }

    final rawItems = data['items'] is List
        ? data['items'] as List
        : (data['movimientos'] is List
              ? data['movimientos'] as List
              : (data['data'] is List ? data['data'] as List : const []));

    final responseFecha = (data['fecha'] ?? fecha).toString();
    final mapped = <CajaMovement>[
      for (final raw in rawItems.whereType<Map>())
        _mapCajaMovement(raw, fechaFallback: responseFecha),
    ];

    // Si algún movimiento PEDIDO llegó sin hora o sin detalle estructurado
    // desde `/v1/caja/movimientos` (ej. pedidos solo de carta con `platoNombre: null`),
    // hidrata fecha y etiqueta limpia desde `/v1/caja/pedidos` usando caché local.
    final missingPedidoIndices = <int>[
      for (var i = 0; i < mapped.length; i++)
        if (mapped[i].tipo == CajaMovementType.pedido &&
            (mapped[i].timestamp == null ||
                mapped[i].cleanDishSummary == null))
          i,
    ];
    if (missingPedidoIndices.isNotEmpty) {
      await _hydrateMissingPedidos(
        rawItems: rawItems,
        mapped: mapped,
        missingIndices: missingPedidoIndices,
      );
    }

    // Si algún movimiento VENTA llegó sin detalle estructurado ni caché previa,
    // consulta `/v1/caja/ventas` una sola vez por venta sin etiquetar.
    final missingVentaIndices = <int>[
      for (var i = 0; i < mapped.length; i++)
        if (mapped[i].tipo == CajaMovementType.venta &&
            mapped[i].cleanDishSummary == null &&
            (mapped[i].planNombre == null || mapped[i].planNombre!.isEmpty))
          i,
    ];
    if (missingVentaIndices.isNotEmpty && isFirstTodayPage) {
      await _hydrateMissingVentas(
        rawItems: rawItems,
        mapped: mapped,
        missingIndices: missingVentaIndices,
      );
    }

    final next = data['nextCursor']?.toString();
    return CajaMovementsPage(
      fecha: responseFecha,
      items: mapped,
      nextCursor: (next != null && next.isNotEmpty) ? next : null,
    );
  }

  Future<void> _hydrateMissingPedidos({
    required List<dynamic> rawItems,
    required List<CajaMovement> mapped,
    required List<int> missingIndices,
  }) async {
    bool resolvedAllFromCache = true;
    for (final idx in missingIndices) {
      final raw = rawItems[idx] is Map ? rawItems[idx] as Map : const {};
      final pedId = (raw['pedidoId'] ?? raw['id'] ?? '').toString();
      final numStr =
          _asNullableInt(raw['pedidoNumero'] ?? raw['numero'])?.toString() ??
          '';
      final cachedTs =
          _orderScanTimestampByKey[pedId] ??
          (numStr.isNotEmpty ? _orderScanTimestampByKey['#$numStr'] : null);
      final cachedSummary =
          _cleanSummaryByOrderKey[pedId] ??
          (numStr.isNotEmpty ? _cleanSummaryByOrderKey['#$numStr'] : null);

      final m = mapped[idx];
      final nextTs = m.timestamp ?? cachedTs;
      final nextSummary = m.cleanDishSummary ?? cachedSummary;
      if (nextTs != m.timestamp || nextSummary != m.cleanDishSummary) {
        mapped[idx] = m.copyWith(
          timestamp: nextTs,
          cleanDishSummary: nextSummary,
          subtitle: nextSummary ?? m.subtitle,
        );
      }
      if (mapped[idx].timestamp == null ||
          mapped[idx].cleanDishSummary == null) {
        resolvedAllFromCache = false;
      }
    }
    if (resolvedAllFromCache) return;

    try {
      final lists = await Future.wait([
        guard(
          () => _api.getList(
            '${ApiConfig.v1}/caja/pedidos',
            query: const {'estado': 'SERVIDA'},
            restaurant: true,
          ),
        ).catchError((_) => const <dynamic>[]),
        guard(
          () => _api.getList(
            '${ApiConfig.v1}/caja/pedidos',
            query: const {'estado': 'CANJEADA'},
            restaurant: true,
          ),
        ).catchError((_) => const <dynamic>[]),
      ]);
      for (final list in lists) {
        for (final p in list.whereType<Map>()) {
          final pid = (p['id'] ?? '').toString();
          final pnum = _asNullableInt(p['numero'])?.toString() ?? '';
          final ts = _tryParseDateTime(
            p['canjeadoEn'] ?? p['servidoEn'] ?? p['creadoEn'],
          );
          if (ts != null) {
            if (pid.isNotEmpty) _orderScanTimestampByKey[pid] = ts;
            if (pnum.isNotEmpty) _orderScanTimestampByKey['#$pnum'] = ts;
          }
          final summary = CajaDishSummaryBuilder.fromPayload(
            almuerzo: p['almuerzo'] is Map ? p['almuerzo'] as Map : null,
            cartaItems: p['cartaItems'] is List ? p['cartaItems'] as List : null,
            extras: p['extras'] is List ? p['extras'] as List : null,
            cotizacion: p['cotizacion'] is Map ? p['cotizacion'] as Map : null,
            platoNombre: p['platoNombre']?.toString(),
            dishSectionByLowerName: _dishSectionByLowerName,
            fallbackToAlmuerzoIfNamed: p['almuerzo'] != null,
          );
          if (summary != null && summary.isNotEmpty) {
            if (pid.isNotEmpty) _cleanSummaryByOrderKey[pid] = summary;
            if (pnum.isNotEmpty) _cleanSummaryByOrderKey['#$pnum'] = summary;
          }
        }
      }
      for (final idx in missingIndices) {
        final raw = rawItems[idx] is Map ? rawItems[idx] as Map : const {};
        final pedId = (raw['pedidoId'] ?? raw['id'] ?? '').toString();
        final numStr =
            _asNullableInt(raw['pedidoNumero'] ?? raw['numero'])?.toString() ??
            '';
        final foundTs =
            mapped[idx].timestamp ??
            _orderScanTimestampByKey[pedId] ??
            (numStr.isNotEmpty ? _orderScanTimestampByKey['#$numStr'] : null);
        final foundSummary =
            mapped[idx].cleanDishSummary ??
            _cleanSummaryByOrderKey[pedId] ??
            (numStr.isNotEmpty ? _cleanSummaryByOrderKey['#$numStr'] : null);
        if (foundTs != mapped[idx].timestamp ||
            foundSummary != mapped[idx].cleanDishSummary) {
          final m = mapped[idx];
          mapped[idx] = m.copyWith(
            timestamp: foundTs,
            cleanDishSummary: foundSummary,
            subtitle: foundSummary ?? m.subtitle,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _hydrateMissingVentas({
    required List<dynamic> rawItems,
    required List<CajaMovement> mapped,
    required List<int> missingIndices,
  }) async {
    var allCached = true;
    for (final idx in missingIndices) {
      final raw = rawItems[idx] is Map ? rawItems[idx] as Map : const {};
      final vid = (raw['ventaId'] ?? raw['id'] ?? '').toString();
      final cached = _cleanSummaryByVentaId[vid];
      if (cached != null && cached.isNotEmpty) {
        mapped[idx] = mapped[idx].copyWith(
          cleanDishSummary: cached,
          subtitle: cached,
        );
      } else {
        allCached = false;
      }
    }
    if (allCached) return;

    try {
      final rawVentas = await guard(
        () => _api.getList('${ApiConfig.v1}/caja/ventas', restaurant: true),
      );
      for (final v in rawVentas.whereType<Map>()) {
        final vid = (v['id'] ?? '').toString();
        if (vid.isEmpty) continue;
        final items = v['items'] is List ? v['items'] as List : null;
        final summary = CajaDishSummaryBuilder.fromPayload(
          ventaItems: items,
          cotizacion: v['cotizacion'] is Map ? v['cotizacion'] as Map : null,
          dishSectionByLowerName: _dishSectionByLowerName,
        );
        if (summary != null && summary.isNotEmpty) {
          _cleanSummaryByVentaId[vid] = summary;
        }
      }
      for (final idx in missingIndices) {
        if (mapped[idx].cleanDishSummary != null) continue;
        final raw = rawItems[idx] is Map ? rawItems[idx] as Map : const {};
        final vid = (raw['ventaId'] ?? raw['id'] ?? '').toString();
        final found = _cleanSummaryByVentaId[vid];
        if (found != null && found.isNotEmpty) {
          mapped[idx] = mapped[idx].copyWith(
            cleanDishSummary: found,
            subtitle: found,
          );
        }
      }
    } catch (_) {}
  }

  CajaMovement _mapCajaMovement(Map raw, {String? fechaFallback}) {
    final tipoRaw = (raw['tipo'] ?? '').toString().toUpperCase();
    final tipo = switch (tipoRaw) {
      'VENTA' => CajaMovementType.venta,
      'PEDIDO' => CajaMovementType.pedido,
      'CANJE_DIRECTO' => CajaMovementType.canjeDirecto,
      _ => CajaMovementType.canjeDirecto,
    };

    final pagoMap = raw['pago'] is Map ? raw['pago'] as Map : null;
    final clienteMap = raw['cliente'] is Map ? raw['cliente'] as Map : null;
    final comensalMap = raw['comensal'] is Map ? raw['comensal'] as Map : null;
    final consumoMap = raw['consumo'] is Map ? raw['consumo'] as Map : null;
    final pedidoMap = raw['pedido'] is Map ? raw['pedido'] as Map : null;
    final planMap = raw['plan'] is Map ? raw['plan'] as Map : null;
    final ventaMap = raw['venta'] is Map ? raw['venta'] as Map : null;
    final cuentaMap = raw['cuenta'] is Map ? raw['cuenta'] as Map : null;

    final customerName =
        (raw['clienteNombre'] ??
                raw['comensalNombre'] ??
                clienteMap?['nombre'] ??
                comensalMap?['nombre'])
            ?.toString()
            .trim();
    final planNombre = (raw['planNombre'] ?? planMap?['nombre'])
        ?.toString()
        .trim();
    final rawPlato = (raw['platoNombre'] ?? consumoMap?['platoNombre'])
        ?.toString()
        .trim();
    final metodoRaw = (raw['metodoPago'] ?? pagoMap?['metodo'])?.toString();
    final pagoEstado = (raw['pagoEstado'] ?? pagoMap?['estado'])
        ?.toString()
        .toUpperCase();
    final revertido = raw['revertido'] == true || raw['deshecha'] == true;
    final montoCentavos = _asNullableInt(raw['montoCentavos']);
    final valorPedidoCentavos = _asNullableInt(raw['valorPedidoCentavos']);
    final rawTitulo = (raw['titulo'] ?? raw['descripcion'] ?? '')
        .toString()
        .trim();
    final mesaTexto = (raw['mesaTexto'] ?? '').toString().trim();
    final ticket = _asNullableInt(raw['ticket']);
    final numero = _asNullableInt(raw['pedidoNumero'] ?? raw['numero']);

    final rawId = (raw['id'] ?? '').toString();
    final pedId = (raw['pedidoId'] ?? pedidoMap?['id'] ?? '').toString();
    final cuentaId = (raw['cuentaId'] ?? cuentaMap?['id'] ?? '').toString();
    final ventaId = (raw['ventaId'] ?? ventaMap?['id'] ?? '').toString();

    final almuerzoObj =
        (raw['almuerzo'] ?? pedidoMap?['almuerzo'] ?? cuentaMap?['almuerzo'])
            as Map<dynamic, dynamic>?;
    final cartaItemsList =
        (raw['cartaItems'] ??
                pedidoMap?['cartaItems'] ??
                cuentaMap?['cartaItems'])
            as List<dynamic>?;
    final extrasList =
        (raw['extras'] ?? pedidoMap?['extras'] ?? cuentaMap?['extras'])
            as List<dynamic>?;
    final cotizacionObj =
        (raw['cotizacion'] ??
                pedidoMap?['cotizacion'] ??
                cuentaMap?['cotizacion'])
            as Map<dynamic, dynamic>?;
    final ventaItemsList =
        (raw['items'] ?? ventaMap?['items']) as List<dynamic>?;

    final computedCleanSummary = CajaDishSummaryBuilder.fromPayload(
      almuerzo: almuerzoObj,
      cartaItems: cartaItemsList,
      extras: extrasList,
      cotizacion: cotizacionObj,
      ventaItems: ventaItemsList,
      platoNombre: rawPlato,
      dishSectionByLowerName: _dishSectionByLowerName,
      fallbackToAlmuerzoIfNamed:
          tipo == CajaMovementType.canjeDirecto ||
          tipo == CajaMovementType.pedido,
    );
    final cachedCleanSummary =
        (cuentaId.isNotEmpty ? _cleanSummaryByCuentaId[cuentaId] : null) ??
        (pedId.isNotEmpty ? _cleanSummaryByOrderKey[pedId] : null) ??
        (numero != null ? _cleanSummaryByOrderKey['#$numero'] : null) ??
        (ventaId.isNotEmpty ? _cleanSummaryByVentaId[ventaId] : null) ??
        (rawId.isNotEmpty
            ? (_cleanSummaryByCuentaId[rawId] ??
                  _cleanSummaryByOrderKey[rawId] ??
                  _cleanSummaryByVentaId[rawId])
            : null);
    final cleanDishSummary =
        (computedCleanSummary != null && computedCleanSummary.isNotEmpty)
        ? computedCleanSummary
        : cachedCleanSummary;

    final String title;
    final String? subtitle;
    switch (tipo) {
      case CajaMovementType.venta:
        if (rawTitulo.isNotEmpty) {
          title = rawTitulo;
        } else if (ticket != null) {
          title = mesaTexto.isNotEmpty
              ? 'Ticket #$ticket · $mesaTexto'
              : 'Ticket #$ticket';
        } else if (customerName != null && customerName.isNotEmpty) {
          title = customerName;
        } else {
          title = 'Venta en caja';
        }
        subtitle = (cleanDishSummary != null && cleanDishSummary.isNotEmpty)
            ? cleanDishSummary
            : ((rawPlato != null && rawPlato.isNotEmpty)
                  ? rawPlato
                  : _mapMetodoToUi(metodoRaw));
      case CajaMovementType.pedido:
        if (rawTitulo.isNotEmpty) {
          title = rawTitulo;
        } else if (numero != null) {
          title = (customerName != null && customerName.isNotEmpty)
              ? 'Pedido #$numero · $customerName'
              : 'Pedido #$numero';
        } else {
          title = (customerName != null && customerName.isNotEmpty)
              ? customerName
              : 'Preorden entregada';
        }
        subtitle = (cleanDishSummary != null && cleanDishSummary.isNotEmpty)
            ? cleanDishSummary
            : ((rawPlato != null && rawPlato.isNotEmpty)
                  ? rawPlato
                  : 'Preorden entregada');
      case CajaMovementType.canjeDirecto:
        if (rawTitulo.isNotEmpty) {
          title = rawTitulo;
        } else if (customerName != null && customerName.isNotEmpty) {
          title = customerName;
        } else {
          title = 'Canje directo';
        }
        final dishDisplay =
            (cleanDishSummary != null && cleanDishSummary.isNotEmpty)
            ? cleanDishSummary
            : 'Almuerzo';
        subtitle = (planNombre != null && planNombre.isNotEmpty)
            ? '$planNombre · $dishDisplay'
            : dishDisplay;
    }

    final rawTs = tipo == CajaMovementType.pedido
        ? (raw['canjeadoEn'] ??
              raw['validadoEn'] ??
              raw['servidoEn'] ??
              raw['ocurrioEn'] ??
              raw['fechaHora'] ??
              raw['registradoEn'] ??
              raw['momento'] ??
              raw['en'] ??
              raw['creadoEn'] ??
              raw['timestamp'] ??
              raw['createdAt'] ??
              raw['actualizadoEn'] ??
              raw['fecha'] ??
              pedidoMap?['canjeadoEn'] ??
              pedidoMap?['servidoEn'] ??
              pedidoMap?['creadoEn'] ??
              consumoMap?['creadoEn'] ??
              consumoMap?['fecha'])
        : (raw['creadoEn'] ??
              raw['fechaHora'] ??
              raw['ocurrioEn'] ??
              raw['canjeadoEn'] ??
              raw['validadoEn'] ??
              raw['servidoEn'] ??
              raw['registradoEn'] ??
              raw['momento'] ??
              raw['en'] ??
              raw['timestamp'] ??
              raw['createdAt'] ??
              raw['fecha'] ??
              consumoMap?['creadoEn'] ??
              consumoMap?['fecha'] ??
              pagoMap?['pagadoEn'] ??
              pagoMap?['creadoEn']);

    final resolvedTs = _tryParseDateTime(
      rawTs,
      timeFallback: raw['hora'] ?? raw['horaLocal'],
      dateFallback: raw['fecha'] ?? fechaFallback,
    );

    return CajaMovement(
      id: rawId,
      tipo: tipo,
      timestamp: resolvedTs,
      title: title,
      subtitle: subtitle,
      montoCentavos: montoCentavos,
      valorPedidoCentavos: valorPedidoCentavos,
      pagoEstado: pagoEstado,
      metodoPago: metodoRaw != null ? _mapMetodoToUi(metodoRaw) : null,
      revertido: revertido,
      platoNombre: (rawPlato != null && rawPlato.isNotEmpty) ? rawPlato : null,
      cleanDishSummary: cleanDishSummary,
      customerName: (customerName != null && customerName.isNotEmpty)
          ? customerName
          : null,
      planNombre: (planNombre != null && planNombre.isNotEmpty)
          ? planNombre
          : null,
    );
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
      final query = <String, dynamic>{'limit': 50, 'cursor': ?cursor};
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
            activeLunches: avail,
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
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/clientes',
              body: body,
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
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
    final hasBreakfast = lower.any(
      (e) => e.contains('desayuno') || e.contains('principal'),
    );
    final hasLunch = lower.any(
      (e) => e.contains('sopa') || e.contains('segundo'),
    );
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
      final rawDays = raw['diasValidos'] is List
          ? raw['diasValidos'] as List
          : const [1, 2, 3, 4, 5];
      final rawIncl = raw['incluye'] is List
          ? raw['incluye'] as List
          : const ['Sopa', 'Segundo', 'Jugo'];
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
    bool deductToday = false,
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

      final intent =
          'sell_plan:$targetClientId:${template.id}:${_mapPayMethodApi(method)}';
      final ik = _idempotency.keyFor(intent);
      late final String saleId;
      try {
        final res = await guard(
          () => _api
              .send<Map<String, dynamic>>(
                'POST',
                '${ApiConfig.v1}/clientes/$targetClientId/planes',
                body: {
                  'planId': template.id,
                  'metodoPago': _mapPayMethodApi(method),
                  'pagoConfirmado': true,
                },
                restaurant: true,
                idempotencyKey: ik,
              )
              .then((v) => v ?? <String, dynamic>{}),
        );
        saleId = (res['id'] ?? '').toString();
        if (saleId.isEmpty) return null;
        _saleUndoById[saleId] = _SaleUndoKind.plan;
        eventsService.track(
          'dueno.plan_vendido',
          restaurantId: restaurantId,
          props: {'metodo': _mapPayMethodApi(method), 'origen': 'caja'},
        );
      } finally {
        _idempotency.done(intent);
      }

      if (deductToday) {
        final redeemIntent = 'sell_plan_deduct_today:$saleId:$targetClientId';
        final redeemKey = _idempotency.keyFor(redeemIntent);
        try {
          await guard(
            () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/validar',
              body: {'clienteId': targetClientId},
              restaurant: true,
              idempotencyKey: redeemKey,
            ),
          );
          _idempotency.done(redeemIntent);
        } catch (_) {
          // El plan ya quedó activado; si falla el canje automático (p. ej. sin menú), no revierte la venta.
          _idempotency.done(redeemIntent);
        }
      }

      return saleId;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return null;
    }
  }

  @override
  Future<OwnerClient?> identifyClientByQr(
    String restaurantId,
    String rawQr,
  ) async {
    _lastError = null;
    final trimmed = rawQr.trim();
    if (trimmed.isEmpty) return null;

    final clients = await getClients(restaurantId);
    final parsed = BocadooQrParser.parseAndValidate(trimmed);
    final candidateId = parsed.userId ?? trimmed;
    final direct = clients
        .where((c) => c.id == candidateId || c.id == trimmed)
        .firstOrNull;
    if (direct != null) return direct;

    // Para tokens opacos rotativos del backend: consulta /caja/validar y revierte si descontó.
    final intent =
        'identify_qr:$restaurantId:${DateTime.now().microsecondsSinceEpoch}';
    final ik = _idempotency.keyFor(intent);
    try {
      final data = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/validar',
              body: {'codigoQr': trimmed},
              restaurant: true,
              idempotencyKey: ik,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
      _idempotency.done(intent);
      final cliente = data['cliente'] is Map ? data['cliente'] as Map : null;
      final consumo = data['consumo'] is Map ? data['consumo'] as Map : null;
      final consumoId = consumo?['id']?.toString();
      if (consumoId != null && consumoId.isNotEmpty) {
        try {
          await guard(
            () => _api.send<dynamic>(
              'POST',
              '${ApiConfig.v1}/caja/consumos/$consumoId/deshacer',
              body: const <String, dynamic>{},
              restaurant: true,
            ),
          );
        } catch (_) {}
      }
      final cid = cliente?['id']?.toString() ?? '';
      final cname = cliente?['nombre']?.toString() ?? '';
      if (cid.isEmpty && cname.isEmpty) return null;
      final refreshed = await getClients(restaurantId);
      return refreshed.where((c) => c.id == cid).firstOrNull ??
          OwnerClient(
            id: cid,
            name: cname.isEmpty ? 'Comensal' : cname,
            activeLunches: _asInt(data['almuerzosRestantes']),
          );
    } on ApiException catch (e) {
      _idempotency.done(intent);
      _lastError = e.userMessage;
      return null;
    } catch (_) {
      _idempotency.done(intent);
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
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
      return false;
    } finally {
      _idempotency.done(intent);
    }
  }

  @override
  Future<bool> commitExtraGuests({
    required String passId,
    required int extraGuests,
    String? batchRedemptionId,
  }) async {
    _lastError = null;
    if (extraGuests <= 0) return true;
    final batch =
        (batchRedemptionId != null ? _batchesById[batchRedemptionId] : null) ??
        _batchesById[_lastBatchByPassId[passId]];
    if (batch == null || batch.undone) return false;

    // 1. Actualización optimista inmediata del registro consolidado en Caja.
    batch.extraGuests = extraGuests;
    final totalRedeemed = 1 + extraGuests;
    final idx = _sessionValidatedTransactions.indexWhere(
      (tx) => tx.id == batch.transactionId,
    );
    if (idx >= 0) {
      _sessionValidatedTransactions[idx] = _sessionValidatedTransactions[idx]
          .copyWith(
            detail: totalRedeemed == 1
                ? 'Canje de plan · 1 almuerzo (Prepagado)'
                : 'Canje de plan · $totalRedeemed almuerzos (Prepagado)',
          );
    }

    // 2. Despacho asíncrono con nuevo UUID como Idempotency-Key y canal MANUAL.
    final future = _dispatchExtraGuests(batch, extraGuests);
    batch.pendingDispatch = future;
    try {
      await future;
      return true;
    } on ApiException catch (e) {
      _lastError = e.userMessage;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _dispatchExtraGuests(
    _ApiRedemptionBatch batch,
    int extraGuests,
  ) async {
    final intent = 'extra_guests:${batch.batchId}';
    final freshKey = _idempotency.keyFor(intent);
    late final Map<String, dynamic> res;
    try {
      res = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/validar',
              body: {
                if (batch.clientId != null && batch.clientId!.isNotEmpty)
                  'clienteId': batch.clientId,
                'canal': 'MANUAL',
                'extraGuests': extraGuests,
                'batchRedemptionId': batch.batchId,
                if (batch.primaryConsumoId != null &&
                    batch.primaryConsumoId!.isNotEmpty)
                  'primaryConsumoId': batch.primaryConsumoId,
              },
              restaurant: true,
              idempotencyKey: freshKey,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
      _idempotency.done(intent);
    } on ApiException catch (e) {
      if (!e.isNetwork && e.status != 504) {
        _idempotency.done(intent);
      }
      rethrow;
    }

    final extraConsumos = <String>[];
    final single = res['consumo'] is Map
        ? (res['consumo'] as Map)['id']?.toString()
        : null;
    if (single != null && single.isNotEmpty) {
      extraConsumos.add(single);
    }
    if (res['consumos'] is List) {
      for (final c in res['consumos'] as List) {
        if (c is Map && c['id'] != null) {
          final id = c['id'].toString();
          if (id.isNotEmpty) extraConsumos.add(id);
        } else if (c is String && c.isNotEmpty) {
          extraConsumos.add(c);
        }
      }
    }
    batch.extraConsumoIds.addAll(extraConsumos);
    eventsService.track(
      'dueno.qr_invitados_extras',
      restaurantId: batch.restaurantId,
      props: {'cantidad': extraGuests},
    );

    // Si el cajero ya presionó Deshacer mientras el despacho estaba en curso,
    // revertir de inmediato los consumos recién creados.
    if (batch.undone && extraConsumos.isNotEmpty) {
      for (final cid in extraConsumos) {
        try {
          await guard(
            () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/consumos/$cid/deshacer',
              restaurant: true,
            ),
          );
        } catch (_) {}
      }
    }
  }

  @override
  Future<bool> undoBatchRedemption(
    String batchRedemptionId, {
    String? fallbackPassId,
  }) async {
    _lastError = null;
    final batch =
        _batchesById[batchRedemptionId] ??
        (fallbackPassId != null
            ? _batchesById[_lastBatchByPassId[fallbackPassId]]
            : null);
    if (batch == null) {
      return fallbackPassId != null
          ? _undoSingleConsumo(fallbackPassId)
          : false;
    }
    if (batch.undone) return false;
    batch.undone = true;

    _sessionValidatedTransactions.removeWhere(
      (tx) => tx.id == batch.transactionId,
    );

    if (batch.pendingDispatch != null) {
      try {
        await batch.pendingDispatch;
      } catch (_) {}
    }

    final idsToUndo = <String>{
      if (batch.primaryConsumoId != null && batch.primaryConsumoId!.isNotEmpty)
        batch.primaryConsumoId!,
      ...batch.extraConsumoIds,
    };
    if (idsToUndo.isEmpty && fallbackPassId != null) {
      idsToUndo.add(_consumoIdByPassId[fallbackPassId] ?? fallbackPassId);
    }

    var anyReverted = false;
    for (final cid in idsToUndo) {
      try {
        final res = await guard(
          () => _api
              .send<Map<String, dynamic>>(
                'POST',
                '${ApiConfig.v1}/caja/consumos/$cid/deshacer',
                restaurant: true,
              )
              .then((v) => v ?? <String, dynamic>{}),
        );
        if (res['revertido'] != false) {
          anyReverted = true;
        }
      } on ApiException catch (e) {
        final detail = e.detail.trim();
        _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
            ? detail
            : e.userMessage;
      }
    }

    _consumoIdByPassId.remove(batch.passId);
    if (anyReverted) {
      eventsService.track('dueno.consumo_deshecho');
    }
    return anyReverted;
  }

  @override
  Future<bool> undoRedeem(String passId) async {
    final batchId = _lastBatchByPassId[passId];
    if (batchId != null && !(_batchesById[batchId]?.undone ?? true)) {
      return undoBatchRedemption(batchId, fallbackPassId: passId);
    }
    return _undoSingleConsumo(passId);
  }

  Future<bool> _undoSingleConsumo(String passId) async {
    _lastError = null;
    final consumoId = _consumoIdByPassId[passId] ?? passId;
    try {
      final res = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/consumos/$consumoId/deshacer',
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
      _consumoIdByPassId.remove(passId);
      _sessionValidatedTransactions.removeWhere((tx) => tx.id == passId);
      final reverted = res['revertido'] != false;
      if (reverted) {
        eventsService.track('dueno.consumo_deshecho');
      }
      return reverted;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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
      final seccion = (raw['seccion'] ?? '').toString().toUpperCase();
      final nombre = (raw['nombre'] ?? '').toString();
      final etiquetas =
          (raw['etiquetas'] is List ? raw['etiquetas'] as List : const [])
              .map((e) => e.toString().toLowerCase())
              .toList();
      final PosCategory cat = switch (categoria) {
        'A_LA_CARTA' => PosCategory.carta,
        'BEBIDA' => PosCategory.bebidas,
        _ when seccion == 'JUGO' || seccion == 'BEBIDA' => PosCategory.bebidas,
        _ =>
          (etiquetas.contains('desayuno') ||
                  nombre.toLowerCase().contains('desayuno'))
              ? PosCategory.desayunos
              : PosCategory.extras,
      };
      final isDessert = seccion == 'POSTRE' || etiquetas.contains('postre');
      mapped.add(
        CatalogItem(
          id: (raw['id'] ?? '').toString(),
          name: nombre,
          description: (raw['descripcion'] ?? '').toString(),
          price: Money.fromCents(_asInt(raw['precioCentavos'])),
          category: cat,
          isDessert: isDessert,
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
          () => _api
              .send<Map<String, dynamic>>(
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
              )
              .then((v) => v ?? <String, dynamic>{}),
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
  bool get supportsOfferPause => false;

  @override
  Future<List<FlashOffer>> getActiveOffers(String restaurantId) async {
    final data = await guard(
      () => _api.getMap(
        '${ApiConfig.v1}/ofertas',
        query: {'estado': 'VIGENTE', 'limit': 50},
        restaurant: true,
      ),
    );
    final items = data['items'] is List ? data['items'] as List : const [];
    final offers = <FlashOffer>[];
    for (final raw in items.whereType<Map>()) {
      final expiraRaw = raw['expiraEn']?.toString();
      final endsAt = expiraRaw != null && expiraRaw.isNotEmpty
          ? _parseDateTime(expiraRaw)
          : null;
      final plato = raw['plato'];
      final stockTotal = _asInt(raw['stockTotal']);
      offers.add(
        FlashOffer(
          id: (raw['id'] ?? '').toString(),
          kind: OfferKind.flash,
          title: (raw['titulo'] ?? '').toString(),
          dishId: plato is Map ? plato['id']?.toString() : null,
          discountPercent: _asInt(raw['descuentoPorcentaje']),
          slots: _asInt(raw['stockRestante'], stockTotal),
          slotsTotal: stockTotal,
          price: Money.fromCents(_asInt(raw['precioCentavos'])),
          originalPrice: Money.fromCents(_asInt(raw['precioOriginalCentavos'])),
          validUntil: endsAt != null ? _hhmmEcuador(endsAt) : null,
          endsAt: endsAt,
        ),
      );
    }
    return offers;
  }

  @override
  Future<bool> setOfferPaused(
    String restaurantId,
    String offerId, {
    required bool paused,
  }) async {
    _lastError = 'Pausar ofertas aún no está disponible. Puedes cerrarla.';
    return false;
  }

  @override
  Future<String?> publishOffer(String restaurantId, FlashOffer offer) async {
    _lastError = null;
    final priceCents = Money.toCents(offer.price);
    final ratio = (100 - offer.discountPercent.clamp(1, 95)) / 100.0;
    final computedOriginal = ratio > 0
        ? (priceCents / ratio).round()
        : priceCents;
    final originalCents = offer.originalPrice != null
        ? Money.toCents(offer.originalPrice!)
        : (computedOriginal > priceCents ? computedOriginal : priceCents + 50);

    int duracionMinutos = 30;
    if (offer.endsAt != null) {
      final diff = offer.endsAt!.difference(DateTime.now()).inMinutes;
      duracionMinutos = diff.clamp(15, 1440);
    } else if (offer.validUntil != null && offer.validUntil!.contains(':')) {
      try {
        final targetUtc = EcuadorTime.todayAtUtc(offer.validUntil!);
        final diff = targetUtc.difference(DateTime.now().toUtc()).inMinutes;
        duracionMinutos = diff.clamp(15, 1440);
      } catch (_) {
        duracionMinutos = 30;
      }
    }

    final intent =
        'oferta:$restaurantId:${offer.title}:$priceCents:${offer.slots}';
    final ik = _idempotency.keyFor(intent);
    try {
      final res = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/ofertas',
              body: {
                'titulo': offer.title.trim(),
                if (offer.dishId != null &&
                    _uuidRegex.hasMatch(offer.dishId!.trim()))
                  'platoId': offer.dishId!.trim(),
                'precioCentavos': priceCents,
                'precioOriginalCentavos': originalCents,
                'stock': offer.slots,
                'duracionMinutos': duracionMinutos,
              },
              restaurant: true,
              idempotencyKey: ik,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
      eventsService.track(
        'dueno.oferta_publicada',
        restaurantId: restaurantId,
        props: {'stock': offer.slots, 'descuento': offer.discountPercent},
      );
      final id = res['id']?.toString();
      return (id == null || id.isEmpty) ? 'publicada' : id;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
      return null;
    } finally {
      _idempotency.done(intent);
    }
  }

  @override
  Future<bool> cancelOffer(String restaurantId, {String? offerId}) async {
    _lastError = null;
    try {
      final ids = offerId != null
          ? [offerId]
          : [
              for (final o in await getActiveOffers(restaurantId))
                if (o.id != null && o.id!.isNotEmpty) o.id!,
            ];
      if (ids.isEmpty) return false;
      for (final id in ids) {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/ofertas/$id/cerrar',
            restaurant: true,
          ),
        );
      }
      return true;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
      return false;
    }
  }

  @override
  Future<bool> setManualBusy(String restaurantId, {required bool busy}) async {
    final res = await setManualOccupancy(
      restaurantId,
      status: busy ? ManualOccupancyStatus.lleno : ManualOccupancyStatus.libre,
    );
    return _lastError == null && (!busy || res != null);
  }

  static const String _manualOccupancyPrefPrefix = 'owner_manual_occupancy_';

  /// Lee la preferencia manual local (`libre` | `concurrido`) cuando el servidor no está `lleno`.
  Future<ManualOccupancyStatus> fetchManualOccupancyPreference(
    String restaurantId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_manualOccupancyPrefPrefix$restaurantId');
      return parseManualOccupancy(raw);
    } catch (_) {
      return ManualOccupancyStatus.libre;
    }
  }

  @override
  Future<DateTime?> setManualOccupancy(
    String restaurantId, {
    required ManualOccupancyStatus status,
    DateTime? fullUntil,
  }) async {
    _lastError = null;
    final busy = status == ManualOccupancyStatus.lleno;
    final isClosed = status == ManualOccupancyStatus.cerrado;

    Future<void> clearLegacyPref() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_manualOccupancyPrefPrefix$restaurantId');
      } catch (_) {}
    }

    try {
      if (isClosed) {
        final paused = await setStoreOpen(restaurantId, isOpen: false);
        if (!paused) {
          _lastError ??= 'No se pudo cerrar el local en el servidor.';
          return null;
        }
        try {
          await guard(
            () => _api
                .send<Map<String, dynamic>>(
                  'POST',
                  '${ApiConfig.v1}/restaurante/lleno',
                  body: const {'nivel': 'LIBRE'},
                  restaurant: true,
                )
                .then((v) => v ?? <String, dynamic>{}),
          );
        } catch (_) {}
        await clearLegacyPref();
        eventsService.track(
          'dueno.aforo_cambiado',
          restaurantId: restaurantId,
          props: {'lleno': false, 'estado': status.name, 'cerrado': true},
        );
        return null;
      }

      // Al pasar a Libre / Concurrido / Lleno, verificar/reactivar el local en el servidor primero.
      final currentOpen = await fetchStoreOpen();
      if (!currentOpen) {
        final activated = await setStoreOpen(restaurantId, isOpen: true);
        if (!activated) {
          _lastError ??= 'No se pudo reactivar el local. Verifica tus horarios y precio suelto.';
          return null;
        }
      }

      final nivel = switch (status) {
        ManualOccupancyStatus.lleno => 'LLENO',
        ManualOccupancyStatus.concurrido => 'CONCURRIDO',
        ManualOccupancyStatus.libre || ManualOccupancyStatus.cerrado => 'LIBRE',
      };

      final res = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/restaurante/lleno',
              body: {'nivel': nivel},
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );

      await clearLegacyPref();

      eventsService.track(
        'dueno.aforo_cambiado',
        restaurantId: restaurantId,
        props: {'lleno': busy, 'nivel': nivel, 'estado': status.name},
      );

      if (status == ManualOccupancyStatus.lleno) {
        final serverDt = _parseFutureLocal(res['llenoManualHasta']);
        if (serverDt != null) {
          if (fullUntil != null && fullUntil.isAfter(serverDt)) {
            return fullUntil;
          }
          return serverDt;
        }
        return fullUntil ?? DateTime.now().add(const Duration(minutes: 20));
      }

      if (status == ManualOccupancyStatus.concurrido) {
        return _parseFutureLocal(res['concurridoManualHasta']) ??
            fullUntil ??
            DateTime.now().add(const Duration(minutes: 20));
      }

      return null;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
      return null;
    } catch (_) {
      _lastError = 'Error de red al actualizar la disponibilidad del local.';
      return null;
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
      () => _api.getMap('${ApiConfig.v1}/caja/cierre/$today', restaurant: true),
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
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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

  @override
  Future<List<OwnerOrder>> getEnCaminoOrders(String restaurantId) async {
    final list = await guard(
      () => _api.getList(
        '${ApiConfig.v1}/caja/pedidos',
        query: const {'estado': 'EN_CAMINO'},
        restaurant: true,
      ),
    );
    final orders = <OwnerOrder>[];
    for (final raw in list.whereType<Map>()) {
      final estado = (raw['estado'] ?? '').toString().toUpperCase();
      if (estado != 'EN_CAMINO') continue;
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

  final Set<String> _inFlightOrders = <String>{};

  static bool _matchesExpectedOrderRaw(
    String rawPayload,
    OwnerOrder expected,
    String activeRestaurantId,
  ) {
    final trimmed = rawPayload.trim();
    if (trimmed.isEmpty) return false;
    final upper = trimmed.toUpperCase();
    if (expected.id != null &&
        expected.id!.isNotEmpty &&
        trimmed.toLowerCase() == expected.id!.toLowerCase()) {
      return true;
    }
    if (upper == expected.number.toUpperCase() ||
        upper == '#${expected.number.toUpperCase()}') {
      return true;
    }
    if (upper.startsWith('BCD-ORD-')) {
      final rest = trimmed.substring(8).trim();
      if (rest == expected.number ||
          (expected.id != null &&
              rest.toLowerCase() == expected.id!.toLowerCase())) {
        return true;
      }
    }
    final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
    if (cleaned.length == BocadooQrParser.shortCodeLength) {
      final c1 = BocadooQrParser.generateOrderCode(
        expected.number,
        orderId: expected.id,
        restaurantId: activeRestaurantId,
      );
      final c2 = BocadooQrParser.generateOrderCode(
        expected.number,
        orderId: expected.id,
      );
      final c3 = BocadooQrParser.generateOrderCode(expected.number);
      if (cleaned == c1 || cleaned == c2 || cleaned == c3) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<({bool isValid, OwnerOrder? order, String? errorMessage})>
  verifyOrderQrCode(
    String rawPayload,
    String activeRestaurantId, {
    OwnerOrder? expectedOrder,
  }) async {
    _lastError = null;
    final trimmed = rawPayload.trim();
    final upper = trimmed.toUpperCase();
    if (trimmed.isEmpty ||
        trimmed.startsWith('BCD1.') ||
        upper.startsWith(BocadooQrParser.planPrefix) ||
        upper.startsWith('BCD-MESA-') ||
        upper.startsWith('MESA-')) {
      return (
        isValid: false,
        order: null,
        errorMessage: 'Este código no corresponde a un pedido.',
      );
    }

    final codeRestId = BocadooQrParser.restaurantForCode(rawPayload);
    if (codeRestId != null &&
        codeRestId.isNotEmpty &&
        activeRestaurantId.isNotEmpty &&
        codeRestId != activeRestaurantId) {
      return (
        isValid: false,
        order: null,
        errorMessage: 'Este código pertenece a otro restaurante.',
      );
    }

    var order = await _findOrderByAnyCode(rawPayload, activeRestaurantId);
    if (order == null && expectedOrder != null) {
      if (_matchesExpectedOrderRaw(
        rawPayload,
        expectedOrder,
        activeRestaurantId,
      )) {
        order = expectedOrder;
      }
    }

    if (order == null) {
      if (await _isOrderAlreadyServed(
        expectedOrder?.id ?? rawPayload,
        activeRestaurantId,
      )) {
        return (
          isValid: false,
          order: null,
          errorMessage: 'Este pedido ya fue descontado anteriormente',
        );
      }
      return (
        isValid: false,
        order: null,
        errorMessage: expectedOrder != null
            ? 'El código no coincide con el pedido #${expectedOrder.number}.'
            : 'No encontramos esa preorden activa.',
      );
    }

    if (order.restaurantId != null &&
        order.restaurantId!.isNotEmpty &&
        activeRestaurantId.isNotEmpty &&
        order.restaurantId != activeRestaurantId) {
      return (
        isValid: false,
        order: null,
        errorMessage: 'Este código pertenece a otro restaurante.',
      );
    }

    if (expectedOrder != null && order.number != expectedOrder.number) {
      return (
        isValid: false,
        order: null,
        errorMessage:
            'Este QR corresponde al pedido #${order.number}, no al pedido #${expectedOrder.number}.',
      );
    }

    final ordKey = 'ORD:${order.number}';
    if (_redeemedCodes.contains(ordKey) ||
        _inFlightOrders.contains(order.number)) {
      return (
        isValid: false,
        order: null,
        errorMessage: 'Este pedido ya fue descontado anteriormente',
      );
    }

    return (isValid: true, order: order, errorMessage: null);
  }

  @override
  Future<ScanResult> confirmAndRedeemOrder(
    String orderIdOrCode,
    String activeRestaurantId, {
    String? rawCodeKey,
    OwnerPayMethod paymentMethod = OwnerPayMethod.efectivo,
  }) async {
    _lastError = null;
    _lastAlreadyRedeemed = false;
    final cleaned = BocadooQrParser.sanitizeManualInput(orderIdOrCode);
    final codeKey =
        rawCodeKey ??
        (cleaned.length == BocadooQrParser.shortCodeLength
            ? cleaned
            : orderIdOrCode.trim().toUpperCase());

    final codeRestId = BocadooQrParser.restaurantForCode(orderIdOrCode);
    if (codeRestId != null &&
        codeRestId.isNotEmpty &&
        activeRestaurantId.isNotEmpty &&
        codeRestId != activeRestaurantId) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Es de otro local',
        supportingLine: 'Este código pertenece a otro restaurante',
        actionRequired: 'NINGUNA',
      );
    }

    if (_redeemedCodes.contains(codeKey)) {
      return const ScanResult(
        isValid: false,
        outcome: 'GRIS',
        title: 'Pedido ya descontado',
        supportingLine: 'Este pedido ya fue descontado anteriormente',
        actionRequired: 'NINGUNA',
      );
    }

    var order = await _findOrderByAnyCode(orderIdOrCode, activeRestaurantId);
    order ??= await resolveOrderByNumber(orderIdOrCode.trim());
    if (order == null) {
      // Comprobar si la orden ya fue completada (SERVIDA) hoy para idempotencia.
      if (await _isOrderAlreadyServed(orderIdOrCode, activeRestaurantId)) {
        _redeemedCodes.add(codeKey);
        return const ScanResult(
          isValid: false,
          outcome: 'GRIS',
          title: 'Pedido ya descontado',
          supportingLine: 'Este pedido ya fue descontado anteriormente',
          actionRequired: 'NINGUNA',
        );
      }

      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'No encontrado',
        supportingLine: 'No encontramos esa preorden activa.',
        actionRequired: 'NINGUNA',
      );
    }

    if (order.restaurantId != null &&
        order.restaurantId!.isNotEmpty &&
        activeRestaurantId.isNotEmpty &&
        order.restaurantId != activeRestaurantId) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Es de otro local',
        supportingLine: 'Este código pertenece a otro restaurante',
        actionRequired: 'NINGUNA',
      );
    }

    final ordKey = 'ORD:${order.number}';
    if (_redeemedCodes.contains(ordKey) ||
        _inFlightOrders.contains(order.number)) {
      return ScanResult(
        isValid: false,
        outcome: 'GRIS',
        title: 'Pedido ya descontado',
        supportingLine: 'Este pedido ya fue descontado anteriormente',
        studentName: order.dinerName,
        actionRequired: 'NINGUNA',
      );
    }

    _inFlightOrders.add(order.number);
    try {
      if (order.paidByPlan && !order.validated) {
        final okVal = await validateOrder(activeRestaurantId, order.number);
        if (!okVal) {
          if (_lastAlreadyRedeemed) {
            _redeemedCodes.add(ordKey);
            _ordersByNumber.remove(order.number);
            return ScanResult(
              isValid: false,
              outcome: 'GRIS',
              title: 'Pedido ya descontado',
              supportingLine: 'Este pedido ya fue descontado anteriormente',
              studentName: order.dinerName,
              actionRequired: 'NINGUNA',
            );
          }
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'No se pudo canjear',
            supportingLine:
                _lastError ?? 'No se pudo validar el plan de la preorden.',
            studentName: order.dinerName,
            actionRequired: 'NINGUNA',
          );
        }
      }

      final entry =
          _ordersByNumber[order.number] ??
          _OrderCacheEntry(
            id: order.id ?? order.number,
            number: order.number,
            paidByPlan: order.paidByPlan,
            validated: order.validated,
            amount: Money.fromCents(order.effectiveTotalCents),
          );

      await _commitDeliverOrder(entry, paymentMethod: paymentMethod);
      if (_lastAlreadyRedeemed) {
        _redeemedCodes.add(ordKey);
        _ordersByNumber.remove(order.number);
        return ScanResult(
          isValid: false,
          outcome: 'GRIS',
          title: 'Pedido ya descontado',
          supportingLine: 'Este pedido ya fue descontado anteriormente',
          studentName: order.dinerName,
          actionRequired: 'NINGUNA',
        );
      }
      if (_lastError != null && _lastError!.isNotEmpty) {
        return ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'No se pudo completar',
          supportingLine: _lastError!,
          studentName: order.dinerName,
          actionRequired: 'NINGUNA',
        );
      }

      _redeemedCodes.add(ordKey);
      _redeemedCodes.add(codeKey);
      _redeemedCodes.add(
        BocadooQrParser.generateOrderCode(
          order.number,
          orderId: order.id,
          restaurantId: activeRestaurantId,
        ),
      );
      final dishParts = <String>[
        if (order.soup != null && order.soup!.isNotEmpty) order.soup!,
        if (order.main != null && order.main!.isNotEmpty) order.main!,
      ];
      final cachedDish = _orderDishByNumber[order.number];
      final dishSummary = (cachedDish != null && cachedDish.isNotEmpty)
          ? cachedDish
          : (dishParts.isNotEmpty ? dishParts.join(' + ') : null);
      final scanTs =
          _orderScanTimestampByKey[order.id ?? ''] ??
          _orderScanTimestampByKey['#${order.number}'] ??
          DateTime.now();
      if (order.id != null && order.id!.isNotEmpty) {
        _orderScanTimestampByKey.putIfAbsent(order.id!, () => scanTs);
      }
      _orderScanTimestampByKey.putIfAbsent('#${order.number}', () => scanTs);
      _sessionValidatedTransactions.insert(
        0,
        TransactionItem(
          id: 'ord-${order.number}-${DateTime.now().millisecondsSinceEpoch}',
          customerName: 'Pedido #${order.number} · ${order.dinerName}',
          type: order.paidByPlan ? 'Canje de plan' : 'Pedido #${order.number}',
          amount: order.paidByPlan
              ? Money.fromCents(order.cashToCollectCents)
              : Money.fromCents(order.effectiveTotalCents),
          paymentMethod: order.paidByPlan
              ? (order.cashToCollectCents > 0 ? paymentMethod.label : 'Plan')
              : paymentMethod.label,
          timestamp: scanTs,
          detail: order.paidByPlan
              ? 'Canje de plan · ${dishSummary ?? 'Almuerzo del día'} (Prepagado)'
              : null,
        ),
      );

      return ScanResult(
        isValid: true,
        outcome: 'VERDE',
        title: order.paidByPlan
            ? '1 almuerzo descontado del plan'
            : 'Preorden #${order.number} cobrada',
        supportingLine: order.paidByPlan
            ? '#${order.number} · ${dishSummary ?? 'Almuerzo del día'}'
            : (dishSummary ?? 'Pedido completado'),
        studentName: order.dinerName,
        passId: ordKey,
        remainingLunches: entry.remainingLunches,
        dishName: dishSummary,
        actionRequired: 'NINGUNA',
        planCreditsUsed: order.paidByPlan && order.planCreditsUsed <= 0
            ? 1
            : order.planCreditsUsed,
        cashToCollectCents: order.cashToCollectCents,
        cashItems: order.cashItems,
      );
    } finally {
      _inFlightOrders.remove(order.number);
    }
  }

  /// Prioridad absoluta de plan activo sobre una preorden previa creada sin plan:
  /// descuenta 1 almuerzo del plan activo del comensal (`POST /v1/caja/validar`
  /// con `clienteId`) y cierra la orden pendiente (`POST /v1/caja/pedidos/:id/servir`)
  /// sin cobrar efectivo ni registrar ventas sueltas.
  Future<ScanResult> confirmOrderWithPlanPriority(
    String orderIdOrCode,
    String activeRestaurantId, {
    required String clientId,
    OwnerPayMethod paymentMethod = OwnerPayMethod.efectivo,
  }) async {
    _lastError = null;
    var order = await _findOrderByAnyCode(orderIdOrCode, activeRestaurantId);
    order ??= await resolveOrderByNumber(orderIdOrCode.trim());
    if (order == null) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'No encontrado',
        supportingLine: 'No encontramos esa preorden activa.',
        actionRequired: 'NINGUNA',
      );
    }

    if (order.paidByPlan) {
      return confirmAndRedeemOrder(
        order.number,
        activeRestaurantId,
        paymentMethod: paymentMethod,
      );
    }

    if (order.restaurantId != null &&
        order.restaurantId!.isNotEmpty &&
        activeRestaurantId.isNotEmpty &&
        order.restaurantId != activeRestaurantId) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Es de otro local',
        supportingLine: 'Este código pertenece a otro restaurante',
        actionRequired: 'NINGUNA',
      );
    }

    final ordKey = 'ORD:${order.number}';
    if (_redeemedCodes.contains(ordKey) ||
        _inFlightOrders.contains(order.number)) {
      return ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Ya canjeado',
        supportingLine: 'Este código ya fue canjeado anteriormente',
        studentName: order.dinerName,
        actionRequired: 'NINGUNA',
      );
    }

    final entry =
        _ordersByNumber[order.number] ??
        _OrderCacheEntry(
          id: order.id ?? order.number,
          number: order.number,
          paidByPlan: false,
          validated: order.validated,
          amount: Money.fromCents(0),
        );

    _inFlightOrders.add(order.number);
    String? consumoId;
    try {
      final validarIntent = 'plan_priority_validar:${entry.id}:$clientId';
      final validarIk = _idempotency.keyFor(validarIntent);
      Map<String, dynamic> validarRes;
      try {
        validarRes = await guard(
          () => _api
              .send<Map<String, dynamic>>(
                'POST',
                '${ApiConfig.v1}/caja/validar',
                body: {'clienteId': clientId},
                restaurant: true,
                idempotencyKey: validarIk,
              )
              .then((v) => v ?? <String, dynamic>{}),
        );
        _idempotency.done(validarIntent);
      } on ApiException catch (e) {
        if (!e.isNetwork && e.status != 504) {
          _idempotency.done(validarIntent);
        }
        final detail = e.detail.trim();
        _lastError =
            ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
                ? detail
                : e.userMessage;
        return ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'No se pudo descontar del plan',
          supportingLine: _lastError!,
          studentName: order.dinerName,
          actionRequired: 'NINGUNA',
        );
      }

      final resultado = (validarRes['resultado'] ?? '').toString().toUpperCase();
      final mensaje = (validarRes['mensaje'] ?? '').toString().trim();
      if (resultado == 'DUPLICADO') {
        _redeemedCodes.add(ordKey);
        _ordersByNumber.remove(order.number);
        try {
          await guard(
            () => _api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/pedidos/${entry.id}/servir',
              restaurant: true,
            ),
          );
        } catch (_) {}
        return ScanResult(
          isValid: false,
          outcome: 'GRIS',
          title: 'Pedido ya descontado',
          supportingLine: 'Este pedido ya fue descontado anteriormente',
          studentName: order.dinerName,
          actionRequired: 'NINGUNA',
        );
      }
      if (resultado.isNotEmpty &&
          resultado != 'OK' &&
          resultado != 'OK_ADVERTENCIA') {
        _lastError = mensaje.isNotEmpty
            ? mensaje
            : 'No se pudo descontar 1 almuerzo del plan activo.';
        return ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Plan no disponible',
          supportingLine: _lastError!,
          studentName: order.dinerName,
          actionRequired: 'NINGUNA',
        );
      }

      final remainingLunches = _asNullableInt(validarRes['almuerzosRestantes']);
      final consumoMap =
          validarRes['consumo'] is Map ? validarRes['consumo'] as Map : null;
      consumoId = consumoMap?['id']?.toString();
      if (consumoId != null && consumoId.isNotEmpty) {
        entry.consumoId = consumoId;
      }
      entry.validated = true;

      // Cerrar la preorden previa sin pasar por cobro de efectivo.
      final serveIntent = 'plan_priority_servir:${entry.id}';
      final serveIk = _idempotency.keyFor(serveIntent);
      try {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/caja/pedidos/${entry.id}/servir',
            restaurant: true,
            idempotencyKey: serveIk,
          ),
        );
        _idempotency.done(serveIntent);
      } on ApiException catch (e) {
        if (!e.isNetwork && e.status != 504) {
          _idempotency.done(serveIntent);
        }
        final alreadyServed = e.status == 409 ||
            e.detail.toUpperCase().contains('SERVID');
        if (!alreadyServed) {
          if (consumoId != null && consumoId.isNotEmpty) {
            try {
              await guard(
                () => _api.send<dynamic>(
                  'POST',
                  '${ApiConfig.v1}/caja/consumos/$consumoId/deshacer',
                  body: const <String, dynamic>{},
                  restaurant: true,
                ),
              );
            } catch (_) {}
          }
          final detail = e.detail.trim();
          _lastError =
              ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
                  ? detail
                  : e.userMessage;
          return ScanResult(
            isValid: false,
            outcome: 'ROJO',
            title: 'No se pudo cerrar el pedido',
            supportingLine: _lastError!,
            studentName: order.dinerName,
            actionRequired: 'NINGUNA',
          );
        }
      }

      _redeemedCodes.add(ordKey);
      _redeemedCodes.add(
        BocadooQrParser.generateOrderCode(
          order.number,
          orderId: order.id,
          restaurantId: activeRestaurantId,
        ),
      );

      final dishParts = <String>[
        if (order.soup != null && order.soup!.isNotEmpty) order.soup!,
        if (order.main != null && order.main!.isNotEmpty) order.main!,
      ];
      final cachedDish = _orderDishByNumber[order.number];
      final dishSummary = (cachedDish != null && cachedDish.isNotEmpty)
          ? cachedDish
          : (dishParts.isNotEmpty ? dishParts.join(' + ') : null);
      final now = DateTime.now();
      _sessionValidatedTransactions.insert(
        0,
        TransactionItem(
          id: 'ord-plan-${order.number}-${now.millisecondsSinceEpoch}',
          customerName: 'Pedido #${order.number} · ${order.dinerName}',
          type: 'Canje de plan',
          amount: Money.fromCents(0),
          paymentMethod: 'Plan',
          timestamp: now,
          detail: 'Canje de plan · -1 almuerzo (${dishSummary ?? 'Almuerzo del día'})',
        ),
      );

      eventsService.track(
        'dueno.pedido_plan_prioridad',
        restaurantId: activeRestaurantId,
      );

      final leftLabel = remainingLunches != null
          ? (remainingLunches == 1
              ? 'Queda 1 almuerzo'
              : 'Quedan $remainingLunches almuerzos')
          : '#${order.number} · ${dishSummary ?? 'Almuerzo del día'}';

      return ScanResult(
        isValid: true,
        outcome: 'VERDE',
        title: '1 almuerzo descontado del plan',
        supportingLine: leftLabel,
        studentName: order.dinerName,
        passId: ordKey,
        remainingLunches: remainingLunches,
        dishName: dishSummary,
        actionRequired: 'NINGUNA',
        planCreditsUsed: 1,
        cashToCollectCents: 0,
      );
    } finally {
      _inFlightOrders.remove(order.number);
    }
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
          () => _api
              .send<Map<String, dynamic>>(
                'POST',
                '${ApiConfig.v1}/caja/pedidos/${entry.id}/canjear',
                restaurant: true,
                idempotencyKey: ik,
              )
              .then((v) => v ?? <String, dynamic>{}),
        );
        _idempotency.done(intent);
        final almuerzo = res['almuerzo'] is Map ? res['almuerzo'] as Map : null;
        final pedidoMap = res['pedido'] is Map ? res['pedido'] as Map : null;
        final pedidoAlmuerzo = pedidoMap?['almuerzo'] is Map
            ? pedidoMap!['almuerzo'] as Map
            : null;
        final rawPlato = res['platoNombre']?.toString().trim();
        final resolvedDish = (rawPlato != null && rawPlato.isNotEmpty)
            ? rawPlato
            : _extractPlatosLabel(pedidoAlmuerzo, fallback: '');
        if (resolvedDish.isNotEmpty) {
          _orderDishByNumber[orderNumber] = resolvedDish;
        }
        final resultado = almuerzo?['resultado']?.toString().toUpperCase();
        final consumoId = almuerzo?['consumoId']?.toString();
        if (consumoId != null && consumoId.isNotEmpty) {
          entry.consumoId = consumoId;
        }
        final rem = _asNullableInt(
          res['almuerzosRestantes'] ?? almuerzo?['almuerzosRestantes'],
        );
        if (rem != null) {
          entry.remainingLunches = rem;
        }
        if (resultado == 'DUPLICADO') {
          _lastAlreadyRedeemed = true;
          _lastError = 'Este pedido ya fue descontado anteriormente';
          return false;
        }
        final ok =
            res['yaCanjeado'] == true ||
            resultado == null ||
            resultado == 'OK' ||
            resultado == 'OK_ADVERTENCIA';
        if (ok) {
          entry.validated = true;
          final pedidoTs = _tryParseDateTime(
            pedidoMap?['canjeadoEn'] ??
                pedidoMap?['servidoEn'] ??
                pedidoMap?['creadoEn'],
          );
          if (pedidoTs != null) {
            _orderScanTimestampByKey[entry.id] = pedidoTs;
            _orderScanTimestampByKey['#$orderNumber'] = pedidoTs;
          }
          eventsService.track(
            'dueno.pedido_validado',
            restaurantId: restaurantId,
          );
          return true;
        }
        _lastError =
            (almuerzo?['mensaje'] ?? 'No se pudo validar el pase del pedido.')
                .toString();
        return false;
      } on ApiException catch (e) {
        if (!e.isNetwork && e.status != 504) {
          _idempotency.done(intent);
        }
        rethrow;
      }
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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

  Future<void> _commitDeliverOrder(
    _OrderCacheEntry entry, {
    OwnerPayMethod paymentMethod = OwnerPayMethod.efectivo,
  }) async {
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
            () => _api
                .send<Map<String, dynamic>>(
                  'POST',
                  '${ApiConfig.v1}/caja/pedidos/${entry.id}/canjear',
                  restaurant: true,
                  idempotencyKey: ik,
                )
                .then((v) => v ?? <String, dynamic>{}),
          );
          final localCents = entry.paidByPlan ? 0 : Money.toCents(entry.amount);
          final remoteCents = _asInt(canje['porCobrarCentavos'], localCents);
          porCobrarCents = entry.paidByPlan
              ? remoteCents
              : (localCents > remoteCents ? localCents : remoteCents);
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
        props: {
          'con_efectivo':
              entry.amount > 0.005 && paymentMethod == OwnerPayMethod.efectivo,
          'metodo_pago': _mapPayMethodApi(paymentMethod),
        },
      );

      // TODO(backend): B-26 — si servir/canjear no incrementa efectivoEsperadoCentavos
      // en cierre, registrar la parte por cobrar como venta POS con el método elegido.
      if (porCobrarCents > 0) {
        try {
          final afterCierre = await guard(
            () => _api.getMap(
              '${ApiConfig.v1}/caja/cierre/$today',
              restaurant: true,
            ),
          );
          final afterCashCents = _asInt(
            afterCierre['efectivoEsperadoCentavos'],
          );
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
                    'metodoPago': _mapPayMethodApi(paymentMethod),
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
      final upper = '${e.code} ${e.detail} ${e.userMessage}'.toUpperCase();
      if (e.status == 409 ||
          upper.contains('SERVID') ||
          upper.contains('CANJEAD') ||
          upper.contains('DUPLICAD') ||
          upper.contains('CONSUMO')) {
        _lastAlreadyRedeemed = true;
        _lastError = 'Este pedido ya fue descontado anteriormente';
      } else {
        _lastError = e.userMessage;
      }
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
    try {
      final results = await Future.wait([
        guard(
          () => _api.send<dynamic>(
            'GET',
            '${ApiConfig.v1}/restaurante/mesas',
            restaurant: true,
          ),
        ),
        _fetchRestaurantMap().catchError((_) => const <String, dynamic>{}),
      ]);
      final rawList = results[0];
      final List<dynamic> list = rawList is List
          ? rawList
          : (rawList is Map
                ? ((rawList['items'] ?? rawList['mesas'] ?? rawList['data'])
                          is List
                      ? (rawList['items'] ??
                                rawList['mesas'] ??
                                rawList['data'])
                            as List<dynamic>
                      : const <dynamic>[])
                : const <dynamic>[]);
      final rest = results[1] as Map<String, dynamic>;
      final rawRecargo = _asInt(rest['recargoParaLlevarCentavos']);
      final recargoUnitCents = rawRecargo > 0 ? rawRecargo : 25;

      final activeRaw = <Map<String, dynamic>>[];
      for (final raw in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(raw);
        final estado = (m['estado'] ?? '').toString().toUpperCase();
        if (estado == 'FINALIZADA' ||
            estado == 'CANCELADA' ||
            estado == 'EXPIRADA' ||
            m['validadaEn'] != null) {
          continue;
        }
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        activeRaw.add(m);
      }
      if (activeRaw.isEmpty) return const [];

      final previews = await Future.wait([
        for (final m in activeRaw)
          guard(
            () => _api.getMap(
              '${ApiConfig.v1}/caja/mesas/${m['id']}',
              restaurant: true,
            ),
          ).catchError((_) => const <String, dynamic>{}),
      ]);

      final out = <PendingTable>[];
      for (var i = 0; i < activeRaw.length; i++) {
        final m = activeRaw[i];
        final vista = previews[i];
        final id = (m['id'] ?? '').toString();
        final anfitrion = m['anfitrion'] is Map
            ? Map<String, dynamic>.from(m['anfitrion'] as Map)
            : const <String, dynamic>{};
        final hostName = (anfitrion['nombre'] ?? 'Mesa grupal').toString();

        final rawMembers = vista['miembros'] is List
            ? (vista['miembros'] as List).whereType<Map>().toList()
            : (m['miembros'] is List
                  ? (m['miembros'] as List).whereType<Map>().toList()
                  : const <Map>[]);

        final modoRaw = (vista['modo'] ?? m['modo'] ?? 'CADA_UNO')
            .toString()
            .toUpperCase();
        final hostMember = rawMembers
            .where((mm) => mm['esAnfitrion'] == true)
            .firstOrNull;
        var hostAvailable = _asInt(hostMember?['almuerzosDisponibles']);

        final totalPersonas = _asInt(vista['personas']) > 0
            ? _asInt(vista['personas'])
            : rawMembers.length;
        final hasVistaCounts =
            vista.isNotEmpty && vista.containsKey('cubiertos');
        final cubiertos = hasVistaCounts ? _asInt(vista['cubiertos']) : 0;

        final memberDishes = <PendingTableMemberDish>[];
        var takeawayCount = 0;
        var inferredPlanCount = 0;
        for (final mm in rawMembers) {
          final isTakeaway = mm['paraLlevar'] == true;
          if (isTakeaway) takeawayCount++;

          final available = _asInt(mm['almuerzosDisponibles']);
          bool hasPlan;
          if (modoRaw == 'INVITO_YO') {
            if (hostAvailable > 0) {
              hasPlan = true;
              hostAvailable--;
            } else {
              hasPlan = false;
            }
          } else {
            hasPlan = available > 0;
          }
          if (hasPlan) inferredPlanCount++;

          final parsedSel = _parseTableMemberSelection(mm);
          memberDishes.add(
            PendingTableMemberDish(
              memberName: (mm['nombre'] ?? 'Comensal').toString(),
              soup: parsedSel.soup,
              main: parsedSel.main,
              extras: parsedSel.extras,
              takeaway: isTakeaway,
              hasPlan: hasPlan,
            ),
          );
        }

        final planCount = hasVistaCounts
            ? cubiertos.clamp(0, totalPersonas)
            : inferredPlanCount.clamp(0, totalPersonas);
        final cashCount = (totalPersonas - planCount).clamp(0, totalPersonas);
        final horaRaw = (vista['horaLlegada'] ?? m['horaLlegada'])?.toString();
        final timeStr = horaRaw != null && horaRaw.isNotEmpty
            ? _hhmmEcuador(_parseDateTime(horaRaw))
            : '--:--';

        out.add(
          PendingTable(
            id: id,
            hostName: hostName,
            members: totalPersonas,
            time: timeStr,
            planCount: planCount,
            cashCount: cashCount,
            takeawayCount: takeawayCount,
            takeawaySurchargeCents: takeawayCount * recargoUnitCents,
            memberDishes: memberDishes,
          ),
        );
      }
      return out;
    } on ApiException catch (e) {
      if (e.status == 403) return const [];
      rethrow;
    }
  }

  /// Extrae sopa, segundo y extras desde `miembros[].seleccion` (Entrega C) o campos planos legacy.
  static ({String? soup, String? main, List<String> extras})
  _parseTableMemberSelection(Map mm) {
    String? soup;
    String? main;
    final extras = <String>[];

    void addLunchPlatos(List rawPlatos) {
      for (final p in rawPlatos) {
        if (p is Map) {
          final sec = (p['seccion'] ?? '').toString().toUpperCase();
          final nombre = (p['nombre'] ?? '').toString().trim();
          if (nombre.isEmpty) continue;
          if (sec == 'SOPA') {
            soup ??= nombre;
          } else if (sec == 'FUERTE' ||
              sec == 'SEGUNDO' ||
              sec == 'PLATO_FUERTE') {
            main ??= nombre;
          } else {
            if (main != null) {
              soup ??= nombre;
            }
            main ??= nombre;
          }
        } else if (p is String && p.trim().isNotEmpty) {
          main ??= p.trim();
        }
      }
    }

    final seleccion = mm['seleccion'];
    if (seleccion is Map) {
      final almuerzo = seleccion['almuerzo'];
      if (almuerzo is Map) {
        if (almuerzo['platos'] is List) {
          addLunchPlatos(almuerzo['platos'] as List);
        }
        final sRaw = almuerzo['sopa']?.toString().trim();
        final mRaw = (almuerzo['segundo'] ?? almuerzo['fuerte'])
            ?.toString()
            .trim();
        if (sRaw != null && sRaw.isNotEmpty) soup ??= sRaw;
        if (mRaw != null && mRaw.isNotEmpty) main ??= mRaw;
      } else if (almuerzo is List) {
        addLunchPlatos(almuerzo);
      }
      if (seleccion['extras'] is List) {
        for (final ex in seleccion['extras'] as List) {
          if (ex is Map) {
            final platoMap = ex['plato'] is Map ? ex['plato'] as Map : null;
            final nombre = (ex['nombre'] ?? platoMap?['nombre'] ?? '')
                .toString()
                .trim();
            final qty = _asInt(ex['cantidad'], 1);
            if (nombre.isNotEmpty) {
              extras.add(qty > 1 ? '${qty}x $nombre' : nombre);
            }
          } else if (ex is String && ex.trim().isNotEmpty) {
            extras.add(ex.trim());
          }
        }
      }
    } else if (mm['platos'] is List) {
      addLunchPlatos(mm['platos'] as List);
    } else {
      final sRaw = mm['sopa']?.toString().trim();
      final mRaw = (mm['segundo'] ?? mm['plato'])?.toString().trim();
      if (sRaw != null && sRaw.isNotEmpty) soup = sRaw;
      if (mRaw != null && mRaw.isNotEmpty) main = mRaw;
    }

    final finalSoup = soup;
    final finalMain = main;
    return (
      soup: (finalSoup != null && finalSoup.isNotEmpty) ? finalSoup : null,
      main: (finalMain != null && finalMain.isNotEmpty) ? finalMain : null,
      extras: extras,
    );
  }

  @override
  Future<TablePreview> previewTable(String restaurantId, String tableId) async {
    final mesaFuture = guard(
      () =>
          _api.getMap('${ApiConfig.v1}/caja/mesas/$tableId', restaurant: true),
    );
    final restFuture = _fetchRestaurantMap();

    final mesa = await mesaFuture;
    final rest = await restFuture;

    final lunchCents = _asInt(rest['precioSueltoCentavos']);
    final surchargeCents = _asInt(rest['recargoParaLlevarCentavos']);

    final modoRaw = (mesa['modo'] ?? '').toString().toUpperCase();
    final mode = modoRaw == 'INVITO_YO'
        ? TableMode.hostPays
        : TableMode.eachOwn;
    final estado = (mesa['estado'] ?? '').toString().toUpperCase();
    final settled = estado == 'FINALIZADA' || mesa['validadaEn'] != null;

    final rawMembers = mesa['miembros'] is List
        ? mesa['miembros'] as List
        : const [];
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

      final parsedSel = _parseTableMemberSelection(m);
      lines.add(
        TableChargeLine(
          name: name,
          via: via,
          amount: Money.fromCents(cashCents),
          soup: parsedSel.soup,
          main: parsedSel.main,
          extras: parsedSel.extras,
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
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/caja/mesas/$tableId/validar',
              restaurant: true,
              idempotencyKey: ik,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );

      final resultados = res['resultados'] is List
          ? res['resultados'] as List
          : const [];
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
          final afterCashCents = _asInt(
            afterCierre['efectivoEsperadoCentavos'],
          );
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
                      {'tipo': 'ALMUERZO', 'cantidad': porCobrarCount},
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

  static ({String categoria, String seccion, List<String> etiquetas})
  _dishKindToApi(DishKind kind) {
    return switch (kind) {
      DishKind.sopa => (
        categoria: 'ALMUERZO',
        seccion: 'SOPA',
        etiquetas: const [],
      ),
      DishKind.segundo => (
        categoria: 'ALMUERZO',
        seccion: 'FUERTE',
        etiquetas: const [],
      ),
      DishKind.bebida => (
        categoria: 'ALMUERZO',
        seccion: 'JUGO',
        etiquetas: const [],
      ),
      DishKind.postre => (
        categoria: 'ALMUERZO',
        seccion: 'POSTRE',
        etiquetas: const [],
      ),
      DishKind.desayuno => (
        categoria: 'EXTRA',
        seccion: 'ADICIONAL',
        etiquetas: const ['desayuno'],
      ),
      DishKind.carta => (
        categoria: 'A_LA_CARTA',
        seccion: 'FUERTE',
        etiquetas: const [],
      ),
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
      final priceCents =
          _asNullableInt(item['precioDelDiaCentavos']) ??
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
    final isOpen =
        (rest['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'ACTIVO';

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
      final seenPlatoIds = <String>{};
      var orden = 0;
      for (final course in menu.courses) {
        final name = course.name.trim();
        if (name.isEmpty) continue;
        final kind = _courseCategoryToKind(course.category);
        final seccion = _courseCategoryToSeccion(course.category);

        var platoId = course.dishId ?? '';
        CatalogDish? matched;
        if (platoId.isEmpty) {
          matched =
              byKindAndName[(kind, name.toLowerCase())] ??
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

        if (platoId.isEmpty || !seenPlatoIds.add(platoId)) continue;

        itemsPayload.add(<String, dynamic>{
          'platoId': platoId,
          'seccion': seccion,
          if (course.price != null && course.price! > 0)
            'precioCentavos': Money.toCents(course.price!),
          'orden': orden++,
        });
      }

      if (itemsPayload.isEmpty) {
        _lastError = 'Agrega al menos un plato para publicar el menú.';
        return false;
      }

      final today = EcuadorTime.today();
      await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'PUT',
              '${ApiConfig.v1}/menu/$today',
              body: {'items': itemsPayload},
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
      final publishedMap = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/menu/$today/publicar',
              body: const <String, dynamic>{},
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );

      _parseDailyMenu(
        menu.restaurantId,
        publishedMap,
        EcuadorTime.now(),
        isOpen: menu.isOpen,
        populateSoldOutMap: true,
      );

      // Si el local estaba cerrado/pausado y vuelve a publicar menú, reabrirlo y limpiar estado cerrado.
      await _activateIfDraft(menu, dishes);
      if (menu.availabilityState != MenuAvailabilityState.agotadoTotal) {
        try {
          final isOpen = await fetchStoreOpen();
          if (!isOpen) {
            await setStoreOpen(menu.restaurantId, isOpen: true);
          }
          await guard(
            () => _api
                .send<Map<String, dynamic>>(
                  'POST',
                  '${ApiConfig.v1}/restaurante/lleno',
                  body: const {'nivel': 'LIBRE'},
                  restaurant: true,
                )
                .then((v) => v ?? <String, dynamic>{}),
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('$_manualOccupancyPrefPrefix${menu.restaurantId}');
        } catch (_) {}
      }

      // Si el usuario marcó platos como agotados antes de publicar, sincronízalos.
      for (final course in menu.courses) {
        if (!course.isSoldOut) continue;
        final itemId =
            _todayMenuItemIdByName[course.name.trim()] ??
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
      await _autoCancelFlashOfferIfAllSoldOut(menu.restaurantId, menu);
      return true;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError =
          ((e.status == 400 || e.status == 422 || e.status == 409) &&
              detail.isNotEmpty)
          ? detail
          : e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo publicar el menú de hoy.';
      return false;
    }
  }

  Future<void> _activateIfDraft(
    DailyMenu menu,
    List<CatalogDish> dishes,
  ) async {
    final rest = await guard(
      () => _api.getMap('${ApiConfig.v1}/restaurante', restaurant: true),
    );
    if ((rest['estado'] ?? '').toString() == 'ACTIVO') return;

    final horarios = await guard(
      () => _api.getList(
        '${ApiConfig.v1}/restaurante/horarios',
        restaurant: true,
      ),
    );
    if (horarios.isEmpty) {
      await guard(
        () => _api.send<List<dynamic>>(
          'PUT',
          '${ApiConfig.v1}/restaurante/horarios',
          restaurant: true,
          body: {
            'horarios': [
              for (var day = 1; day <= 5; day++)
                {'diaSemana': day, 'abre': '12:00', 'cierra': '15:30'},
            ],
          },
        ),
      );
    }

    if (_asInt(rest['precioSueltoCentavos']) <= 0) {
      var looseCents = 0;
      for (final c in menu.courses) {
        if (c.category.toLowerCase() == 'fuerte' &&
            c.price != null &&
            c.price! > 0) {
          looseCents = Money.toCents(c.price!);
          break;
        }
      }
      if (looseCents <= 0) {
        for (final c in menu.courses) {
          if (c.price != null && c.price! > 0) {
            final cents = Money.toCents(c.price!);
            if (cents > looseCents) looseCents = cents;
          }
        }
      }
      if (looseCents <= 0) {
        for (final d in dishes) {
          if ((d.kind == DishKind.segundo || d.kind == DishKind.sopa) &&
              d.price != null &&
              d.price! > 0) {
            final cents = Money.toCents(d.price!);
            if (cents > looseCents) looseCents = cents;
          }
        }
      }
      if (looseCents > 0) {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'PATCH',
            '${ApiConfig.v1}/restaurante',
            restaurant: true,
            body: {'precioSueltoCentavos': looseCents},
          ),
        );
      }
    }

    await guard(
      () => _api.send<Map<String, dynamic>>(
        'POST',
        '${ApiConfig.v1}/restaurante/activar',
        restaurant: true,
      ),
    );
  }

  /// Actualiza el precio del almuerzo suelto e intenta activar el local si está en borrador.
  Future<bool> updateSingleLunchPriceAndActivate(double price) async {
    _lastError = null;
    try {
      final cents = Money.toCents(price);
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'PATCH',
          '${ApiConfig.v1}/restaurante',
          restaurant: true,
          body: {'precioSueltoCentavos': cents},
        ),
      );
      final rest = await guard(
        () => _api.getMap('${ApiConfig.v1}/restaurante', restaurant: true),
      );
      if ((rest['estado'] ?? '').toString() != 'ACTIVO') {
        final horarios = await guard(
          () => _api.getList(
            '${ApiConfig.v1}/restaurante/horarios',
            restaurant: true,
          ),
        );
        if (horarios.isEmpty) {
          await guard(
            () => _api.send<List<dynamic>>(
              'PUT',
              '${ApiConfig.v1}/restaurante/horarios',
              restaurant: true,
              body: {
                'horarios': [
                  for (var day = 1; day <= 5; day++)
                    {'diaSemana': day, 'abre': '12:00', 'cierra': '15:30'},
                ],
              },
            ),
          );
        }
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/restaurante/activar',
            restaurant: true,
          ),
        );
      }
      return true;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = detail.isNotEmpty ? detail : e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo actualizar el precio del almuerzo suelto.';
      return false;
    }
  }

  /// Actualiza dirección, zona y coordenadas del local en el servidor y caché local.
  Future<bool> updateLocalLocation({
    required String address,
    String? zone,
    double? lat,
    double? lng,
  }) async {
    _lastError = null;
    try {
      final knownZoneId = resolveKnownZoneId(zone);
      final roundedLat = lat != null
          ? double.parse(lat.toStringAsFixed(6))
          : null;
      final roundedLng = lng != null
          ? double.parse(lng.toStringAsFixed(6))
          : null;
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'PATCH',
          '${ApiConfig.v1}/restaurante',
          restaurant: true,
          body: {
            if (address.trim().isNotEmpty) 'direccion': address.trim(),
            'zonaId': ?knownZoneId,
            'latitud': ?roundedLat,
            'longitud': ?roundedLng,
          },
        ),
      );
      await _session.profile.saveDinerProfile(
        zone: zone,
        lat: roundedLat,
        lng: roundedLng,
      );
      return true;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = detail.isNotEmpty ? detail : e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo guardar la ubicación del local.';
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
          body: const <String, dynamic>{},
          restaurant: true,
        ),
      );
      return true;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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
      var itemId =
          _todayMenuItemIdByName[key] ??
          _todayMenuItemIdByName[key.toLowerCase()];
      if (itemId == null || itemId.isEmpty) {
        await getTodayMenu(restaurantId);
        itemId =
            _todayMenuItemIdByName[key] ??
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
      if (soldOut) {
        try {
          final currentMenu = await getTodayMenu(restaurantId);
          await _autoCancelFlashOfferIfAllSoldOut(restaurantId, currentMenu);
        } catch (_) {}
      }
      return true;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo actualizar el estado del plato.';
      return false;
    }
  }

  Future<void> _autoCancelFlashOfferIfAllSoldOut(
    String restaurantId,
    DailyMenu? menu,
  ) async {
    if (menu == null ||
        menu.availabilityState != MenuAvailabilityState.agotadoTotal) {
      return;
    }
    try {
      final hasFlash = (await getActiveOffers(restaurantId))
          .any((o) => o.kind == OfferKind.flash);
      if (hasFlash) await cancelOffer(restaurantId);
    } catch (_) {}
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
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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
      final rawName = (raw['nombre'] ?? '').toString().trim();
      if (rawName.isNotEmpty) {
        final mappedSection = switch (categoria) {
          'A_LA_CARTA' => 'A_LA_CARTA',
          'BEBIDA' => 'BEBIDA',
          'EXTRA' => seccion == 'POSTRE' ? 'POSTRE' : seccion,
          _ => seccion.isNotEmpty ? seccion : 'FUERTE',
        };
        if (mappedSection.isNotEmpty) {
          _dishSectionByLowerName[rawName.toLowerCase()] = mappedSection;
        }
      }
      final tags = raw['etiquetas'] is List
          ? (raw['etiquetas'] as List)
                .map((e) => e.toString().toLowerCase())
                .toList()
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
      final isVeggie = tags.any((t) => t.contains('veg'));
      BreakfastCategory? bCat;
      if (kind == DishKind.desayuno) {
        if (tags.contains('desayuno:bebida')) {
          bCat = BreakfastCategory.bebida;
        } else if (tags.contains('desayuno:proteina')) {
          bCat = BreakfastCategory.proteina;
        } else if (tags.contains('desayuno:pan')) {
          bCat = BreakfastCategory.pan;
        } else {
          bCat = BreakfastCategory.combo;
        }
      }
      return CatalogDish(
        id: (raw['id'] ?? '').toString(),
        name: (raw['nombre'] ?? '').toString(),
        kind: kind,
        price: priceCents != null ? Money.fromCents(priceCents) : null,
        description: desc != null && desc.trim().isNotEmpty ? desc : '',
        archived: raw['activo'] == false,
        soldOut: raw['agotado'] == true,
        veggie: isVeggie,
        breakfastCategory: bCat,
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
    bool veggie = false,
    BreakfastCategory? breakfastCategory,
  }) async {
    final mapped = _dishKindToApi(kind);
    final etiquetas = <String>[
      ...mapped.etiquetas,
      if (veggie) 'vegetariano',
      if (kind == DishKind.desayuno && breakfastCategory != null)
        'desayuno:${breakfastCategory.name}',
    ];
    final body = <String, dynamic>{
      'categoria': mapped.categoria,
      'seccion': mapped.seccion,
      'nombre': name.trim(),
      if (description != null && description.trim().isNotEmpty)
        'descripcion': description.trim(),
      if (price != null && price > 0) 'precioCentavos': Money.toCents(price),
      if (etiquetas.isNotEmpty) 'etiquetas': etiquetas,
    };
    final res = await guard(
      () => _api
          .send<Map<String, dynamic>>(
            'POST',
            '${ApiConfig.v1}/menu/platos',
            body: body,
            restaurant: true,
          )
          .then((v) => v ?? <String, dynamic>{}),
    );
    final priceCents = _asNullableInt(res['precioCentavos']);
    return CatalogDish(
      id: (res['id'] ?? '').toString(),
      name: (res['nombre'] ?? name.trim()).toString(),
      kind: kind,
      price: priceCents != null ? Money.fromCents(priceCents) : price,
      description: res['descripcion']?.toString() ?? description ?? '',
      archived: res['activo'] == false,
      veggie: veggie,
      breakfastCategory: kind == DishKind.desayuno
          ? (breakfastCategory ?? BreakfastCategory.combo)
          : null,
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

  @override
  Future<bool> setCatalogDishSoldOut(
    String restaurantId,
    String dishId, {
    required bool soldOut,
  }) async {
    _lastError = null;
    try {
      await guard(
        () => _api.send<dynamic>(
          'PATCH',
          '${ApiConfig.v1}/menu/platos/$dishId/agotado',
          body: {'agotado': soldOut},
          restaurant: true,
        ),
      );
      eventsService.track(
        'dueno.carta_plato_agotado',
        restaurantId: restaurantId,
        props: {'agotado': soldOut},
      );
      return true;
    } on ApiException catch (e) {
      if (e.status == 403) {
        _lastError = 'No tienes permisos para modificar este plato.';
      } else {
        final detail = e.detail.trim();
        _lastError = detail.isNotEmpty ? detail : e.userMessage;
      }
      return false;
    } catch (_) {
      _lastError = 'No se pudo actualizar la disponibilidad del plato.';
      return false;
    }
  }

  @override
  Future<CatalogDish?> addPermanentDish(
    String restaurantId, {
    required String name,
    required int priceCents,
    required String categoria,
    required String seccion,
    List<String> etiquetas = const [],
    String? description,
  }) async {
    _lastError = null;
    try {
      final body = <String, dynamic>{
        'categoria': categoria,
        'seccion': seccion,
        'nombre': name.trim(),
        'precioCentavos': priceCents,
        if (etiquetas.isNotEmpty) 'etiquetas': etiquetas,
        if (description != null && description.trim().isNotEmpty)
          'descripcion': description.trim(),
      };
      final res = await guard(
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/menu/platos',
              body: body,
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
      final id = (res['id'] ?? '').toString();
      if (id.isEmpty) return null;
      final resPrice = _asNullableInt(res['precioCentavos']) ?? priceCents;
      return CatalogDish(
        id: id,
        name: (res['nombre'] ?? name.trim()).toString(),
        kind: categoria == 'A_LA_CARTA'
            ? DishKind.carta
            : (seccion == 'POSTRE' ? DishKind.postre : DishKind.bebida),
        price: Money.fromCents(resPrice),
        description: res['descripcion']?.toString() ?? description ?? '',
        archived: res['activo'] == false,
        soldOut: res['agotado'] == true,
      );
    } on ApiException catch (e) {
      final rawNameErr = e.fieldErrors['nombre']?.trim() ?? '';
      final isTechnical =
          e.detail.contains('must be') ||
          e.detail.contains('following values') ||
          e.detail.contains('should not') ||
          e.detail.toLowerCase().contains('seccion') ||
          e.detail.toLowerCase().contains('categoria') ||
          e.detail.toLowerCase().contains('preciocentavos');
      if (rawNameErr.isNotEmpty && !rawNameErr.contains('must be')) {
        _lastError = rawNameErr;
      } else if (e.status == 400 || isTechnical) {
        _lastError = 'No se pudo guardar el ítem. Verifica los datos e intenta de nuevo.';
      } else {
        _lastError = e.userMessage;
      }
      return null;
    }
  }

  @override
  Future<bool> updateCatalogDishPrice(
    String restaurantId,
    String dishId, {
    required int priceCents,
  }) async {
    _lastError = null;
    try {
      await guard(
        () => _api.send<dynamic>(
          'PATCH',
          '${ApiConfig.v1}/menu/platos/$dishId',
          body: {'precioCentavos': priceCents},
          restaurant: true,
        ),
      );
      return true;
    } on ApiException catch (e) {
      final detail = e.detail.trim();
      _lastError = detail.isNotEmpty ? detail : e.userMessage;
      return false;
    }
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
        ...clean.where(
          (e) =>
              !e.toLowerCase().contains('sopa') &&
              !e.toLowerCase().contains('segundo'),
        ),
      ],
      PlanCoverage.mixto => [
        if (!clean.any((e) => e.toLowerCase().contains('desayuno'))) 'Desayuno',
        if (!clean.any((e) => e.toLowerCase().contains('sopa'))) 'Sopa',
        if (!clean.any((e) => e.toLowerCase().contains('segundo'))) 'Segundo',
        ...clean.where((e) {
          final l = e.toLowerCase();
          return !l.contains('desayuno') &&
              !l.contains('sopa') &&
              !l.contains('segundo');
        }),
      ],
      PlanCoverage.almuerzo =>
        clean.isEmpty ? const ['Sopa', 'Segundo', 'Jugo'] : clean,
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
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/planes',
              body: baseBody,
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
      );
    } else {
      final patchBody = <String, dynamic>{
        ...baseBody,
        'activo': template.active,
      };
      try {
        res = await guard(
          () => _api
              .send<Map<String, dynamic>>(
                'PATCH',
                '${ApiConfig.v1}/planes/${template.id}',
                body: patchBody,
                restaurant: true,
              )
              .then((v) => v ?? <String, dynamic>{}),
        );
      } on ApiException catch (e) {
        // OpenAPI tipa `diasValidos` de PATCH como `array<string>` en algunas versiones;
        // si la validación rechaza enteros con 400, reintenta convirtiendo a strings.
        if (e.status != 400) rethrow;
        res = await guard(
          () => _api
              .send<Map<String, dynamic>>(
                'PATCH',
                '${ApiConfig.v1}/planes/${template.id}',
                body: {
                  ...patchBody,
                  'diasValidos': template.days
                      .map((d) => d.toString())
                      .toList(),
                },
                restaurant: true,
              )
              .then((v) => v ?? <String, dynamic>{}),
        );
      }
    }

    final rawDays = res['diasValidos'] is List
        ? res['diasValidos'] as List
        : template.days;
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
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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
        () => _api
            .send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/clientes/$targetClientId/migrar-cartulina',
              body: {
                'almuerzosRestantes': remaining,
                'venceEl': venceEl,
                'precioUnitarioCentavos': unitCents,
                'nombrePlan': template.name,
                'diasValidos': template.days,
                'anotacion':
                    'Cartulina de papel ($used/${template.lunches} usados)',
              },
              restaurant: true,
            )
            .then((v) => v ?? <String, dynamic>{}),
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

  static const _peakDayNames = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];
  static const _peakHourIndices = [11, 12, 13, 14, 15];
  static const _peakHourLabels = ['11h', '12h', '13h', '14h', '15h'];

  static String _weeklyPrefKey(String restaurantId) =>
      'bocadoo_weekly_summary_$restaurantId';

  static String _logoPrefKey(String restaurantId) =>
      'bocadoo_local_logo_$restaurantId';

  static DateTime _localDateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

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
    final lastWeekSameDayStr = _formatYmd(
      todayDate.subtract(const Duration(days: 7)),
    );

    // 7 días recientes para el mapa de calor semanal y resumen semanal.
    final weekDates = [
      for (var i = 6; i >= 0; i--) todayDate.subtract(Duration(days: i)),
    ];

    final prefsFuture = SharedPreferences.getInstance();
    final pendingFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/reportes/almuerzos-pendientes',
        restaurant: true,
      ),
    );
    final rankingFuture = guard(
      () => _api.getMap(
        '${ApiConfig.v1}/reportes/ranking-platos',
        query: {
          'desde': _formatYmd(todayDate.subtract(const Duration(days: 29))),
          'hasta': todayStr,
          'limit': 5,
        },
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
        final porHora = results[j]['porHora'] is List
            ? results[j]['porHora'] as List
            : const [];
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
    final todayAlmuerzos = todaySummary['almuerzos'] is Map
        ? todaySummary['almuerzos'] as Map
        : const {};
    final todayPos = todaySummary['ventasPos'] is Map
        ? todaySummary['ventasPos'] as Map
        : const {};
    final servedToday =
        _asInt(todayAlmuerzos['servidos']) + _asInt(todayPos['almuerzos']);

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
    final pendTotal = pendingMap['total'] is Map
        ? pendingMap['total'] as Map
        : const {};
    final pendingLunches = _asInt(pendTotal['almuerzos']);
    final clientsWithPlan = _asInt(pendTotal['clientes']);

    // Ranking de platos
    final rankItems = rankingMap['items'] is List
        ? rankingMap['items'] as List
        : const [];
    final dishes = rankItems.whereType<Map>().map((raw) {
      final plato = raw['plato'] is Map ? raw['plato'] as Map : const {};
      return DishRank(
        name: (plato['nombre'] ?? '').toString(),
        orders: _asInt(raw['unidades']),
      );
    }).toList();

    // Dinero: planes vendidos y desglose Efectivo vs Transferencia/Deuna
    final vpTotal = ventasPlanesMap['total'] is Map
        ? ventasPlanesMap['total'] as Map
        : const {};
    final plansSold = _asInt(vpTotal['vendidos']);
    var cashCents = 0;
    var transferCents = 0;
    for (final ymd in allDates) {
      final sum = summariesByDate[ymd];
      if (sum == null) continue;
      final ing = sum['ingresos'] is Map ? sum['ingresos'] as Map : const {};
      final metodos = ing['porMetodo'] is List
          ? ing['porMetodo'] as List
          : const [];
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
    final followItems = followUpMap['items'] is List
        ? followUpMap['items'] as List
        : const [];
    final renewals = <ClientFollowUp>[];
    final absent = <ClientFollowUp>[];
    for (final raw in followItems.whereType<Map>()) {
      final motivos = raw['motivos'] is List
          ? (raw['motivos'] as List)
                .map((e) => e.toString().toUpperCase())
                .toList()
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
        days:
            motivos.contains('SIN_VENIR') &&
                !motivos.contains('POR_VENCER') &&
                !motivos.contains('PARA_RENOVAR')
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
      servedLastWeekSameTime: servedLastWeekSameTime > 0
          ? servedLastWeekSameTime
          : null,
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
      weeklySummaryEnabled:
          prefs.getBool(_weeklyPrefKey(restaurantId)) ?? false,
      weekServed: weekServed,
      weekCollected: Money.fromCents(weekCollectedCents),
    );
    _metricsCache[period] = _MetricsCacheEntry(
      value: metrics,
      at: DateTime.now(),
    );
    eventsService.track(
      'dueno.metricas_vistas',
      restaurantId: restaurantId,
      props: {'periodo': period.name},
    );
    return metrics;
  }

  @override
  Future<bool> setWeeklySummary(
    String restaurantId, {
    required bool enabled,
  }) async {
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
    final zonaMap = data['zona'];
    var zone = zonaMap is Map ? (zonaMap['nombre'] ?? '').toString() : '';
    var lat = (data['latitud'] as num?)?.toDouble();
    var lng = (data['longitud'] as num?)?.toDouble();
    final profile = _session.profile;
    if (zone.isEmpty) zone = await profile.getZone() ?? '';
    lat ??= await profile.getLat();
    lng ??= await profile.getLng();
    final rawMaskedCedula = (data['cedulaRucEnmascarada'] ?? data['cedulaRuc'])
        ?.toString()
        .trim();
    final rawPendientes = data['datosPendientes'] is List
        ? (data['datosPendientes'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    final perfilCompleto = data['perfilCompleto'] is bool
        ? data['perfilCompleto'] as bool
        : rawPendientes.isEmpty;
    return LocalInfo(
      name: (data['nombre'] ?? '').toString(),
      address: (data['direccion'] ?? '').toString(),
      seats: _asInt(data['puestos']),
      tablesCount: _asNullableInt(data['mesas']),
      phone: (data['telefono'] ?? '').toString(),
      maskedCedulaRuc: (rawMaskedCedula != null && rawMaskedCedula.isNotEmpty)
          ? rawMaskedCedula
          : null,
      takeawaySurchargeCents: _asNullableInt(data['recargoParaLlevarCentavos']),
      perfilCompleto: perfilCompleto,
      datosPendientes: rawPendientes,
      zone: zone,
      latitude: lat,
      longitude: lng,
      logo: localLogo,
      logoUrl: remoteLogo != null && remoteLogo.isNotEmpty ? remoteLogo : null,
    );
  }

  /// Actualiza datos del perfil del local (`PATCH /v1/restaurante`, Entrega B).
  /// Al fallar con `400 problem+json`, expone errores por campo en [consumeLastFieldErrors].
  Future<bool> updateRestaurantProfile({
    String? name,
    String? address,
    String? zone,
    double? lat,
    double? lng,
    String? phone,
    String? cedulaRuc,
    int? tablesCount,
    int? seats,
    int? singleLunchPriceCents,
    int? takeawaySurchargeCents,
  }) async {
    _lastError = null;
    _lastFieldErrors = const {};
    try {
      final knownZoneId = zone != null ? resolveKnownZoneId(zone) : null;
      final roundedLat = lat != null
          ? double.parse(lat.toStringAsFixed(6))
          : null;
      final roundedLng = lng != null
          ? double.parse(lng.toStringAsFixed(6))
          : null;

      String? phoneToSend;
      if (phone != null && phone.trim().isNotEmpty) {
        final trimmed = phone.trim();
        final e164 = Phone.toE164(trimmed);
        phoneToSend = e164.isNotEmpty ? e164 : trimmed;
      }

      final body = <String, dynamic>{
        if (name != null && name.trim().isNotEmpty) 'nombre': name.trim(),
        if (address != null && address.trim().isNotEmpty)
          'direccion': address.trim(),
        'telefono': ?phoneToSend,
        if (cedulaRuc != null && cedulaRuc.trim().isNotEmpty)
          'cedulaRuc': cedulaRuc.trim(),
        'mesas': ?tablesCount,
        'puestos': ?seats,
        'precioSueltoCentavos': ?singleLunchPriceCents,
        'recargoParaLlevarCentavos': ?takeawaySurchargeCents,
        'zonaId': ?knownZoneId,
        'latitud': ?roundedLat,
        'longitud': ?roundedLng,
      };
      if (body.isEmpty) return true;

      await guard(
        () => _api.send<Map<String, dynamic>>(
          'PATCH',
          '${ApiConfig.v1}/restaurante',
          restaurant: true,
          body: body,
        ),
      );
      if (singleLunchPriceCents != null && singleLunchPriceCents > 0) {
        _cachedLunchPriceCents = singleLunchPriceCents;
      }
      if (zone != null || roundedLat != null || roundedLng != null) {
        await _session.profile.saveDinerProfile(
          zone: zone,
          lat: roundedLat,
          lng: roundedLng,
        );
      }
      if (cedulaRuc != null && cedulaRuc.trim().isNotEmpty) {
        // Nunca conservar la cédula/RUC en claro en disco.
        await _session.profile.saveOwnerRuc(null);
      }
      return true;
    } on ApiException catch (e) {
      _lastFieldErrors = e.fieldErrors;
      final detail = e.detail.trim();
      _lastError = detail.isNotEmpty ? detail : e.userMessage;
      return false;
    } catch (_) {
      _lastError = 'No se pudo actualizar los datos del local.';
      return false;
    }
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
    String? referenciaExterna,
  }) async {
    _lastError = null;
    final intent = 'cobrar_solicitud_$requestId';
    final key = _idempotency.keyFor(intent);
    final trimmedRef = referenciaExterna?.trim();
    var ok = false;
    try {
      await guard(
        () => _api.send<dynamic>(
          'POST',
          '${ApiConfig.v1}/solicitudes-plan/$requestId/cobrar',
          body: {
            'metodoPago': _mapPayMethodApi(method),
            'pagoConfirmado': true,
            if (trimmedRef != null && trimmedRef.isNotEmpty)
              'referenciaExterna': trimmedRef,
          },
          idempotencyKey: key,
          restaurant: true,
        ),
      );
      ok = true;
      eventsService.track(
        'dueno.plan_vendido',
        props: {'metodo': _mapPayMethodApi(method), 'origen': 'solicitud'},
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
      final detail = e.detail.trim();
      _lastError = ((e.status == 400 || e.status == 422) && detail.isNotEmpty)
          ? detail
          : e.userMessage;
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
      final matchedClient = matches != null && matches.length == 1
          ? matches.first
          : null;
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
      final effectiveReply =
          pendingReply ??
          (serverReply != null && serverReply.isNotEmpty ? serverReply : null);

      out.add(
        OwnerOpinion(
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
        ),
      );
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
      _lastError = 'No pudimos vincular esta opinión con un cliente del local para reponer su almuerzo.';
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
