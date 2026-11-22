import 'dart:typed_data';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/demo/demo_store.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/formatters.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/extras_models.dart';
import '../domain/models/metrics_models.dart';
import '../domain/repositories/i_owner_repository.dart';

/// Repositorio mock del Dueño. Porta la lógica del PMV Web
/// (`src/domain/redemption.ts`, `plans.ts` y `cash.ts`):
/// - Validación de QR con [BocadooQrParser] (formato, firma y ventana de 30 s).
/// - Descuento FIFO: se consume del plan que vence primero.
/// - Control de doble escaneo: un comensal no se valida dos veces en < 60 s.
/// - Cierre de caja: solo el efectivo cobrado hoy es "esperado" en gaveta.
// TODO: Conectar con provider de backend
class MockOwnerRepository
    implements
        IOwnerRepository,
        IOwnerCashRepository,
        IOwnerMetricsRepository,
        IOwnerOrdersRepository,
        IOwnerTablesRepository,
        IOwnerFeedbackRepository,
        IOwnerSettingsRepository {
  MockOwnerRepository({
    this.restaurantId = 'rest-001',
    this.latency = const Duration(milliseconds: 250),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _seed();
  }

  /// Restaurante al que pertenece la caja de este dueño.
  final String restaurantId;

  /// Latencia simulada de red.
  final Duration latency;

  final DateTime Function() _clock;

  static const Duration _doubleScanWindow = Duration(seconds: 60);
  static const int _defaultPlanValidityDays = 30;

  final Map<String, _Student> _studentsByUserId = {};
  final List<_Redemption> _redemptions = [];
  final List<TransactionItem> _transactions = [];
  int _sequence = 0;

  static const double _singleLunchPrice = 3.00;

  /// Venta de plan → (userId, planId), para poder deshacerla.
  final Map<String, (String, String)> _planSales = {};

  /// Venta del POS → almuerzos servidos en esa venta.
  final Map<String, int> _posLunchUnits = {};

  /// Canje de plan → cantidad total de almuerzos (titular + invitados extras).
  final Map<String, int> _planRedemptionUnits = {};
  final Map<String, _RedemptionBatch> _batchesById = {};
  final Map<String, String> _lastBatchByPassId = {};
  final Map<String, String> _pendingBatchIdByPassId = {};

  FlashOffer? _scheduledOffer;
  bool _shiftClosed = false;
  bool _weeklySummary = true;

  final List<OwnerPlanTemplate> _templates = [
    const OwnerPlanTemplate(
      id: 'tpl-semanal',
      name: 'Plan semanal',
      lunches: 5,
      price: 15,
      validityDays: 7,
      kind: PlanKind.semanal,
      quota: 20,
    ),
    const OwnerPlanTemplate(
      id: 'tpl-quincenal',
      name: 'Plan quincenal',
      lunches: 15,
      price: 42,
      validityDays: 15,
      kind: PlanKind.quincenal,
      quota: 30,
    ),
    const OwnerPlanTemplate(
      id: 'tpl-mensual',
      name: 'Plan mensual ejecutivo',
      lunches: 20,
      price: 55,
      validityDays: 30,
      kind: PlanKind.mensual,
      quota: 40,
    ),
  ];

  // ---------------------------------------------------------------------------
  // IOwnerRepository
  // ---------------------------------------------------------------------------

  final Set<String> _redeemedCodes = <String>{};
  String? _lastValidatedCodeKey;

  DemoPreorder? _findPreorderByCode(String rawPayload) {
    final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
    final resolvedNum = BocadooQrParser.resolveOrderNumber(rawPayload);
    if (resolvedNum != null) {
      return _store.preorderByNumber(resolvedNum);
    }
    final upper = rawPayload.trim().toUpperCase();
    if (upper.startsWith('BCD-ORD-')) {
      return _store.preorderByNumber(rawPayload.trim().substring('BCD-ORD-'.length).trim());
    }
    if (upper.startsWith('#') && upper.length > 1) {
      return _store.preorderByNumber(upper.substring(1).trim());
    }
    if (cleaned.length == BocadooQrParser.shortCodeLength) {
      for (final o in _store.preorders) {
        final code = BocadooQrParser.generateOrderCode(
          o.number,
          orderId: o.number,
          restaurantId: o.restaurantId,
        );
        if (code == cleaned) return o;
      }
    }
    return null;
  }

  SharedTable? _findTableByCode(String rawPayload) {
    final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
    final resolvedId = BocadooQrParser.resolveTableId(rawPayload);
    if (resolvedId != null) {
      return _store.tables[resolvedId.toUpperCase()] ?? _store.tables[resolvedId];
    }
    final upper = rawPayload.trim().toUpperCase();
    if (upper.startsWith('BCD-MESA-')) {
      final id = rawPayload.trim().substring('BCD-MESA-'.length).trim().toUpperCase();
      return _store.tables[id];
    }
    if (cleaned.length == BocadooQrParser.shortCodeLength) {
      for (final t in _store.tables.values) {
        final code = BocadooQrParser.generateTableCode(
          t.id,
          restaurantId: t.restaurantId,
        );
        if (code == cleaned) return t;
      }
    }
    return null;
  }

  @override
  Future<ScanResult> validateQrCode(String rawPayload) async {
    await _simulateLatency();
    final now = _clock();
    final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
    final codeKey = cleaned.length == BocadooQrParser.shortCodeLength
        ? cleaned
        : rawPayload.trim().toUpperCase();

    // 1. Verificar si es una preorden (código de 6 caracteres o BCD-ORD-).
    final preorder = _findPreorderByCode(rawPayload);
    if (preorder != null) {
      if (preorder.restaurantId != restaurantId) {
        return const ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Es de otro local',
          supportingLine: 'Este código pertenece a otro restaurante',
          actionRequired: 'NINGUNA',
        );
      }
      final ordKey = 'ORD:${preorder.number}';
      if (!preorder.isOpen ||
          _redeemedCodes.contains(ordKey) ||
          _redeemedCodes.contains(codeKey)) {
        return ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Ya canjeado',
          supportingLine: 'Este código ya fue canjeado anteriormente',
          studentName: preorder.dinerName,
          actionRequired: 'NINGUNA',
        );
      }
      _lastValidatedCodeKey = codeKey;
      return ScanResult(
        isValid: true,
        outcome: 'VERDE',
        title: 'Preorden #${preorder.number} registrada',
        supportingLine: '${preorder.soup} · ${preorder.main}',
        studentName: preorder.dinerName,
        passId: ordKey,
        actionRequired: 'NINGUNA',
        planCreditsUsed: preorder.planCreditsUsed,
        cashToCollectCents: preorder.cashToCollectCents,
        cashItems: preorder.cashItems,
      );
    }

    // 2. Verificar si es una mesa activa (código de 6 caracteres o BCD-MESA-).
    final table = _findTableByCode(rawPayload);
    if (table != null) {
      if (table.restaurantId != restaurantId) {
        return const ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Es de otro local',
          supportingLine: 'Este código pertenece a otro restaurante',
          actionRequired: 'NINGUNA',
        );
      }
      final tableKey = 'MESA:${table.id}';
      if (_store.settledTables.contains(table.id) ||
          _redeemedCodes.contains(tableKey) ||
          _redeemedCodes.contains(codeKey)) {
        return ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Ya canjeado',
          supportingLine: 'Este código ya fue canjeado anteriormente',
          studentName: table.hostName,
          actionRequired: 'NINGUNA',
        );
      }
      _lastValidatedCodeKey = codeKey;
      return ScanResult(
        isValid: true,
        outcome: 'VERDE',
        title: 'Mesa ${table.id} registrada',
        supportingLine: '${table.members.length} comensales · ${table.hostName}',
        studentName: table.hostName,
        passId: tableKey,
        actionRequired: 'NINGUNA',
      );
    }

    // 3. Verificar pertenencia al local registrada en el generador de códigos.
    final codeRestId = BocadooQrParser.restaurantForCode(rawPayload);
    if (codeRestId != null &&
        codeRestId.isNotEmpty &&
        codeRestId != restaurantId) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Es de otro local',
        supportingLine: 'Este código pertenece a otro restaurante',
        actionRequired: 'NINGUNA',
      );
    }

    // 4. Regla de estado: no validar pase directo si el menú de hoy no está publicado o está agotado.
    final avail = DemoStore.instance.menuAvailabilityByRest[restaurantId] ??
        DemoStore.instance.menuAvailabilityByRest[DemoStore.ownerRestaurantId] ??
        ((DemoStore.instance.menuPublishedByRest[restaurantId] ??
                DemoStore.instance.menuPublishedByRest[DemoStore.ownerRestaurantId] ??
                false)
            ? MenuAvailabilityState.disponible
            : MenuAvailabilityState.sinPublicar);
    if (avail == MenuAvailabilityState.sinPublicar) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Menú no publicado',
        supportingLine:
            'No se puede escanear QR sin haber publicado el menú de hoy',
        actionRequired: 'NINGUNA',
      );
    }
    if (avail == MenuAvailabilityState.agotadoTotal) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Almuerzos agotados hoy',
        supportingLine:
            'Todos los platos del menú de hoy están agotados. Solo puedes canjear preórdenes ya reservadas.',
        actionRequired: 'NINGUNA',
      );
    }

    // 5. Bloqueo de doble escaneo por código único ya consumido.
    if (_redeemedCodes.contains(codeKey)) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Ya canjeado',
        supportingLine: 'Este código ya fue canjeado anteriormente',
        actionRequired: 'NINGUNA',
      );
    }

    final qr = BocadooQrParser.parseAndValidate(rawPayload, now);

    if (qr.isExpired) {
      return ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Código vencido',
        supportingLine: 'Pide al comensal abrir su app.',
        actionRequired: 'COBRAR_SUELTO',
      );
    }
    if (!qr.isValid) {
      return ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'QR no válido',
        supportingLine: qr.errorMessage ?? 'No se pudo leer el código.',
        actionRequired: 'NINGUNA',
      );
    }

    final student = _studentsByUserId[qr.userId];
    if (student == null) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Sin plan',
        supportingLine: 'Este comensal no tiene un plan. Véndele uno.',
        actionRequired: 'VENDER_PLAN',
      );
    }

    _lastValidatedCodeKey = codeKey;
    return _evaluate(student, now);
  }

  @override
  Future<bool> confirmRedeem(String passId) async {
    await _simulateLatency();
    final now = _clock();

    if (passId.startsWith('ORD:')) {
      final orderNumber = passId.substring(4);
      final res = await confirmAndRedeemOrder(orderNumber, restaurantId);
      return res.isValid;
    }

    if (passId.startsWith('MESA:')) {
      final tableId = passId.substring(5);
      final table = _store.tables[tableId];
      if (table == null ||
          table.restaurantId != restaurantId ||
          _store.settledTables.contains(tableId) ||
          _redeemedCodes.contains(passId)) {
        return false;
      }
      _redeemedCodes.add(passId);
      if (_lastValidatedCodeKey != null) {
        _redeemedCodes.add(_lastValidatedCodeKey!);
      }
      final chargeId = await chargeTable(restaurantId, tableId);
      return chargeId != null;
    }

    final student = _studentByPassId(passId);
    if (student == null) return false;
    if (student.restaurantId != restaurantId) return false;

    // Idempotencia: si ya se canjeó hace < 60 s o con el mismo código, bloquear.
    if (_recentRedemption(student, now) != null) return false;
    if (_lastValidatedCodeKey != null &&
        _redeemedCodes.contains(_lastValidatedCodeKey!)) {
      return false;
    }

    final plan = student.nextRedeemablePlan(now);
    if (plan == null) return false;

    if (_lastValidatedCodeKey != null) {
      _redeemedCodes.add(_lastValidatedCodeKey!);
    }

    plan.remaining -= 1;
    _adjustDemoDinerBalance(student, -1);
    final redemption = _Redemption(
      id: _nextId('red'),
      userId: student.userId,
      planId: plan.id,
      timestamp: now,
    );
    _redemptions.add(redemption);
    _transactions.add(
      TransactionItem(
        id: redemption.id,
        customerName: student.name,
        type: 'Canje de plan',
        amount: 0,
        paymentMethod: 'Plan',
        timestamp: now,
        detail: 'Canje de plan · Almuerzo del día (Prepagado)',
      ),
    );
    _planRedemptionUnits[redemption.id] = 1;
    final batchId = _pendingBatchIdByPassId.remove(passId) ?? uuidV4();
    _batchesById[batchId] = _RedemptionBatch(
      batchId: batchId,
      passId: passId,
      userId: student.userId,
      restaurantId: student.restaurantId,
      customerName: student.name,
      transactionId: redemption.id,
      redemptions: [redemption],
    );
    _lastBatchByPassId[passId] = batchId;

    // Si este comensal tenía una preorden EN_CAMINO con plan en este local,
    // márcala como entregada/canjeada para descontar de "X en camino".
    for (final o in _store.preorders) {
      if (o.restaurantId == restaurantId &&
          o.isOpen &&
          o.dinerName.toLowerCase() == student.name.toLowerCase()) {
        o
          ..validated = true
          ..status = PreorderStatus.delivered
          ..deliveredAt = now;
        _redeemedCodes.add('ORD:${o.number}');
        _store.changed();
        break;
      }
    }
    return true;
  }

  @override
  Future<bool> sellPlan({
    required String studentIdentifier,
    required int lunchCount,
    required String paymentMethod,
    required double amount,
  }) async {
    await _simulateLatency();
    final now = _clock();

    final identifier = studentIdentifier.trim();
    final method = _normalizePaymentMethod(paymentMethod);
    if (identifier.isEmpty || lunchCount <= 0 || amount < 0 || method == null) {
      return false;
    }

    final student = _findStudent(identifier) ?? _registerStudent(identifier);

    // Cada compra es un plan independiente con su propio vencimiento:
    // nunca se suman fechas (regla del PMV Web).
    student.plans.add(
      _Plan(
        id: _nextId('plan'),
        total: lunchCount,
        remaining: lunchCount,
        expiresAt: now.add(const Duration(days: _defaultPlanValidityDays)),
      ),
    );
    _transactions.add(
      TransactionItem(
        id: _nextId('sale'),
        customerName: student.name,
        type: 'Venta Plan',
        amount: _round2(amount),
        paymentMethod: method,
        timestamp: now,
      ),
    );
    return true;
  }

  @override
  Future<TransactionSummary> getDailyClosingSummary(String restaurantId) async {
    await _simulateLatency();
    final now = _clock();
    final today = _todayTransactions(now);

    final redeemed = today
            .where((t) => t.type == 'Validado' || t.type == 'Canje de plan')
            .fold<int>(0, (sum, t) => sum + (_planRedemptionUnits[t.id] ?? 1)) +
        today.fold<int>(0, (sum, t) => sum + (_posLunchUnits[t.id] ?? 0));
    final plansSold = today.where((t) => t.type == 'Venta Plan').length;
    final income = today.fold<double>(0, (sum, t) => sum + t.amount);
    // Solo el efectivo cobrado hoy forma parte de lo esperado en gaveta;
    // los canjes de plan no suman efectivo (ingresó al vender el plan).
    final expectedCash = today
        .where((t) => t.paymentMethod == 'Efectivo')
        .fold<double>(0, (sum, t) => sum + t.amount);

    // La interfaz no permite declarar el efectivo contado: el mock asume
    // que la gaveta cuadra. El backend real lo recibirá del arqueo.
    final counted = expectedCash;
    final difference = _round2(counted - expectedCash);

    final deliveredToday = _store.preorders.where((o) =>
        o.restaurantId == DemoStore.ownerRestaurantId &&
        o.status == PreorderStatus.delivered);

    return TransactionSummary(
      date: now,
      planCreditsUsedToday:
          deliveredToday.fold<int>(0, (sum, o) => sum + o.planCreditsUsed),
      cashToCollectToday:
          deliveredToday.fold<int>(0, (sum, o) => sum + o.cashToCollectCents),
      lunchesRedeemedToday: redeemed,
      plansSoldToday: plansSold,
      totalIncomeToday: _round2(income),
      cashCounted: _round2(counted),
      cashExpected: _round2(expectedCash),
      cashDifference: difference,
      cashStatus: difference == 0
          ? 'Cuadra'
          : (difference < 0 ? 'Falta' : 'Sobra'),
      transactions: List.unmodifiable(today),
    );
  }

  @override
  Future<List<TransactionItem>> getTodayTransactions(
    String restaurantId,
  ) async {
    await _simulateLatency();
    return List.unmodifiable(_todayTransactions(_clock()));
  }

  @override
  Future<CajaMovementsPage> getCajaMovements(
    String restaurantId, {
    required String fecha,
    String? cursor,
    int limit = 20,
  }) async {
    await _simulateLatency();
    final now = _clock();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (fecha != todayStr) {
      return CajaMovementsPage(fecha: fecha, items: const []);
    }

    final list = _todayTransactions(now).reversed.toList();
    final mapped = <CajaMovement>[];
    for (final tx in list) {
      final isPreorden = tx.customerName.startsWith('Pedido #');
      final isPlan = tx.amount <= 0 &&
          (tx.type == 'Canje de plan' ||
              tx.type == 'Validado' ||
              tx.paymentMethod == 'Plan');
      if (isPreorden) {
        mapped.add(
          CajaMovement(
            id: tx.id,
            tipo: CajaMovementType.pedido,
            timestamp: tx.timestamp,
            title: tx.customerName,
            subtitle: tx.detail ?? 'Preorden entregada',
            valorPedidoCentavos: isPlan
                ? (_singleLunchPrice * 100).round()
                : (tx.amount * 100).round(),
            pagoEstado: isPlan ? 'PLAN' : 'CONFIRMADO',
            metodoPago: tx.paymentMethod,
            platoNombre: tx.detail,
            customerName: tx.customerName,
          ),
        );
      } else if (isPlan) {
        mapped.add(
          CajaMovement(
            id: tx.id,
            tipo: CajaMovementType.canjeDirecto,
            timestamp: tx.timestamp,
            title: tx.customerName,
            subtitle: tx.detail ?? 'Almuerzo del día (Prepagado)',
            pagoEstado: 'CONFIRMADO',
            metodoPago: 'Plan',
            customerName: tx.customerName,
          ),
        );
      } else {
        mapped.add(
          CajaMovement(
            id: tx.id,
            tipo: CajaMovementType.venta,
            timestamp: tx.timestamp,
            title: tx.customerName,
            subtitle: '${tx.type} · ${tx.paymentMethod}',
            montoCentavos: (tx.amount * 100).round(),
            pagoEstado: 'CONFIRMADO',
            metodoPago: tx.paymentMethod,
            customerName: tx.customerName,
          ),
        );
      }
    }

    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit).clamp(0, mapped.length);
    final pageItems = start >= mapped.length
        ? const <CajaMovement>[]
        : mapped.sublist(start, end);
    final nextCursor = end < mapped.length ? '$end' : null;
    return CajaMovementsPage(
      fecha: fecha,
      items: pageItems,
      nextCursor: nextCursor,
    );
  }

  // ---------------------------------------------------------------------------
  // IOwnerCashRepository
  // ---------------------------------------------------------------------------

  @override
  Future<double> getSingleLunchPrice(String restaurantId) async =>
      _singleLunchPrice;

  @override
  Future<List<OwnerClient>> getClients(String restaurantId) async {
    await _simulateLatency();
    return [
      for (final s in _studentsByUserId.values)
        if (s.restaurantId == this.restaurantId)
          OwnerClient(
            id: s.userId,
            name: s.name,
            phone: s.phone,
            email: s.email,
            notes: s.notes,
            habitualPlan: _templateName(s.plans.lastOrNull?.templateId),
          ),
    ];
  }

  @override
  Future<OwnerClient> addClient(
    String restaurantId, {
    required String name,
    required String phone,
    String email = '',
    String notes = '',
  }) async {
    await _simulateLatency();
    final id = _nextId('c-new');
    final student = _registerStudent(id, name: name.trim(), phone: phone.trim());
    student
      ..email = email.trim()
      ..notes = notes.trim();
    return OwnerClient(id: id, name: student.name, phone: student.phone, email: student.email, notes: student.notes);
  }

  String? _templateName(String? templateId) =>
      _templates.where((t) => t.id == templateId).firstOrNull?.name;

  @override
  Future<List<OwnerPlanTemplate>> getPlanTemplates(String restaurantId) async {
    await _simulateLatency();
    return List.unmodifiable(_templates);
  }

  @override
  Future<OwnerPlanTemplate> savePlanTemplate(String restaurantId, OwnerPlanTemplate template) async {
    await _simulateLatency();
    final i = _templates.indexWhere((t) => t.id == template.id);
    if (template.id.isNotEmpty && i >= 0) {
      _templates[i] = template;
      return template;
    }
    final created = template.copyWith(id: _nextId('tpl'));
    _templates.add(created);
    return created;
  }

  @override
  Future<bool> setPlanActive(String restaurantId, String templateId, {required bool active}) async {
    await _simulateLatency();
    final i = _templates.indexWhere((t) => t.id == templateId);
    if (i < 0) return false;
    _templates[i] = _templates[i].copyWith(active: active);
    return true;
  }

  @override
  Future<Map<String, int>> getPlanClientCounts(String restaurantId) async {
    await _simulateLatency();
    final counts = <String, int>{};
    for (final s in _studentsByUserId.values) {
      if (s.restaurantId != this.restaurantId) continue;
      for (final id in {for (final p in s.plans) ?p.templateId}) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  // ---------------------------------------------------------------------------
  // IOwnerMetricsRepository (datos de muestra donde aún no hay historial)
  // ---------------------------------------------------------------------------

  @override
  Future<OwnerMetrics> getMetrics(String restaurantId, {required MetricsPeriod period}) async {
    await _simulateLatency();
    final now = _clock();
    final today = _todayTransactions(now);
    final servedToday = today.where((t) => t.type == 'Validado').length +
        today.fold<int>(0, (sum, t) => sum + (_posLunchUnits[t.id] ?? 0));

    var pending = 0;
    var withPlan = 0;
    final renewals = <ClientFollowUp>[];
    for (final s in _studentsByUserId.values) {
      if (s.restaurantId != this.restaurantId) continue;
      final balance = s.redeemableBalance(now);
      if (balance <= 0) continue;
      pending += balance;
      withPlan++;
      final next = s.nextRedeemablePlan(now);
      if (next == null) continue;
      final daysLeft = _calendarDaysBetween(now, next.expiresAt);
      if (daysLeft <= 5) {
        renewals.add(ClientFollowUp(name: s.name, phone: s.phone, days: daysLeft, lunchesLeft: balance));
      }
    }
    renewals.sort((a, b) => a.days.compareTo(b.days));

    final soldToday = today.where((t) => t.type == 'Venta Plan');
    final cashToday = soldToday.where((t) => t.paymentMethod == 'Efectivo').fold<double>(0, (s, t) => s + t.amount);
    final otherToday = soldToday.where((t) => t.paymentMethod != 'Efectivo').fold<double>(0, (s, t) => s + t.amount);
    final isWeek = period == MetricsPeriod.semana;

    return OwnerMetrics(
      servedToday: servedToday,
      servedLastWeekSameTime: 12,
      pendingLunches: pending,
      clientsWithPlan: withPlan,
      dishes: const [
        DishRank(name: 'Seco de pollo con maduro', orders: 42, rating: 4.7),
        DishRank(name: 'Pollo a la plancha', orders: 35, rating: 4.5),
        DishRank(name: 'Locro de papa con queso', orders: 28, rating: 4.6),
        DishRank(name: 'Bowl de quinoa', orders: 12, rating: 3.9),
      ],
      expiredLunches: 23,
      expiredPlans: 6,
      expiredValue: 63.25,
      salesCash: (isWeek ? 165 : 610) + cashToday,
      salesTransfer: (isWeek ? 110 : 495) + otherToday,
      plansSold: (isWeek ? 5 : 21) + soldToday.length,
      renewals: renewals,
      absent: const [
        ClientFollowUp(name: 'Andrea Molina', phone: '0991112233', days: 9, lunchesLeft: 6),
        ClientFollowUp(name: 'Jorge Castillo', phone: '0994455667', days: 12, lunchesLeft: 3),
      ],
      peakDays: const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie'],
      peakHours: const ['12:00', '12:30', '13:00', '13:30', '14:00'],
      peakGrid: const [
        [4, 9, 14, 8, 3],
        [5, 10, 16, 9, 4],
        [6, 12, 19, 11, 5],
        [5, 11, 17, 10, 4],
        [7, 13, 21, 12, 6],
      ],
      weeklySummaryEnabled: _weeklySummary,
      weekServed: 142 + servedToday,
      weekCollected: 275 + cashToday + otherToday,
    );
  }

  @override
  Future<bool> setWeeklySummary(String restaurantId, {required bool enabled}) async {
    await _simulateLatency();
    _weeklySummary = enabled;
    return true;
  }

  @override
  Future<String?> sellPlanTemplate({
    required String restaurantId,
    String? clientId,
    String? newClientName,
    required OwnerPlanTemplate template,
    required OwnerPayMethod method,
  }) async {
    await _simulateLatency();
    final now = _clock();
    final _Student? student;
    if (clientId != null) {
      student = _studentsByUserId[clientId];
    } else if (newClientName != null && newClientName.trim().isNotEmpty) {
      student = _registerStudent(_nextId('c-quick'), name: newClientName.trim());
    } else {
      student = null;
    }
    if (student == null) return null;

    final plan = _Plan(
      id: _nextId('plan'),
      total: template.lunches,
      remaining: template.lunches,
      expiresAt: now.add(Duration(days: template.validityDays)),
      templateId: template.id,
    );
    student.plans.add(plan);
    final saleId = _nextId('sale');
    _transactions.add(TransactionItem(
      id: saleId,
      customerName: student.name,
      type: 'Venta Plan',
      amount: _round2(template.price),
      paymentMethod: method.label,
      timestamp: now,
    ));
    _planSales[saleId] = (student.userId, plan.id);
    return saleId;
  }

  @override
  Future<bool> undoTransaction(String transactionId) async {
    await _simulateLatency();
    final removed = _transactions.length;
    _transactions.removeWhere((t) => t.id == transactionId);
    if (_transactions.length == removed) return false;

    final planSale = _planSales.remove(transactionId);
    if (planSale != null) {
      _studentsByUserId[planSale.$1]?.plans.removeWhere((p) => p.id == planSale.$2);
    }
    _posLunchUnits.remove(transactionId);
    return true;
  }

  void _adjustDemoDinerBalance(_Student student, int delta) {
    if (student.userId != DemoStore.dinerUserId) return;
    final key = _store.remainingLunchesByRest.containsKey(student.restaurantId)
        ? student.restaurantId
        : DemoStore.ownerRestaurantId;
    final curr = _store.remainingLunchesByRest[key] ?? 0;
    final next = (curr + delta).clamp(0, 9999);
    _store.remainingLunchesByRest[key] = next;
    _store.changed();
  }

  @override
  Future<bool> commitExtraGuests({
    required String passId,
    required int extraGuests,
    String? batchRedemptionId,
  }) async {
    await _simulateLatency();
    if (extraGuests <= 0) return true;
    final batch = (batchRedemptionId != null
            ? _batchesById[batchRedemptionId]
            : null) ??
        _batchesById[_lastBatchByPassId[passId]];
    if (batch == null || batch.undone) return false;
    final student = _studentsByUserId[batch.userId] ?? _studentByPassId(passId);
    if (student == null) return false;

    final now = _clock();
    if (student.redeemableBalance(now) < extraGuests) return false;

    for (var i = 0; i < extraGuests; i++) {
      final plan = student.nextRedeemablePlan(now);
      if (plan == null) break;
      plan.remaining -= 1;
      final extraR = _Redemption(
        id: _nextId('red'),
        userId: student.userId,
        planId: plan.id,
        timestamp: now,
      );
      _redemptions.add(extraR);
      batch.redemptions.add(extraR);
    }

    _adjustDemoDinerBalance(student, -extraGuests);
    final total = batch.redemptions.length;
    _planRedemptionUnits[batch.transactionId] = total;

    final txIdx = _transactions.indexWhere((t) => t.id == batch.transactionId);
    if (txIdx >= 0) {
      _transactions[txIdx] = _transactions[txIdx].copyWith(
        detail: total == 1
            ? 'Canje de plan · Almuerzo del día (Prepagado)'
            : 'Canje de plan · $total almuerzos (Prepagado)',
      );
    }
    return true;
  }

  @override
  Future<bool> undoBatchRedemption(
    String batchRedemptionId, {
    String? fallbackPassId,
  }) async {
    await _simulateLatency();
    final batch = _batchesById[batchRedemptionId] ??
        (fallbackPassId != null
            ? _batchesById[_lastBatchByPassId[fallbackPassId]]
            : null);
    if (batch == null) {
      return fallbackPassId != null ? _undoLegacyRedeem(fallbackPassId) : false;
    }
    if (batch.undone) return false;
    batch.undone = true;

    final student = _studentsByUserId[batch.userId];
    var restored = 0;
    for (final r in batch.redemptions) {
      if (r.annulled) continue;
      r.annulled = true;
      restored++;
      for (final p in student?.plans ?? const <_Plan>[]) {
        if (p.id == r.planId) p.remaining += 1;
      }
    }
    if (student != null && restored > 0) {
      _adjustDemoDinerBalance(student, restored);
    }
    _transactions.removeWhere((t) => t.id == batch.transactionId);
    _planRedemptionUnits.remove(batch.transactionId);
    return restored > 0;
  }

  @override
  Future<bool> undoRedeem(String passId) async {
    final batchId = _lastBatchByPassId[passId];
    if (batchId != null && !(_batchesById[batchId]?.undone ?? true)) {
      return undoBatchRedemption(batchId, fallbackPassId: passId);
    }
    await _simulateLatency();
    return _undoLegacyRedeem(passId);
  }

  bool _undoLegacyRedeem(String passId) {
    final student = _studentByPassId(passId);
    if (student == null) return false;
    for (final r in _redemptions.reversed) {
      if (r.userId != student.userId || r.annulled) continue;
      r.annulled = true;
      for (final p in student.plans) {
        if (p.id == r.planId) p.remaining += 1;
      }
      _adjustDemoDinerBalance(student, 1);
      _transactions.removeWhere((t) => t.id == r.id);
      _planRedemptionUnits.remove(r.id);
      return true;
    }
    return false;
  }

  @override
  Future<List<CatalogItem>> getCatalog(String restaurantId) async {
    await _simulateLatency();
    CatalogItem item(String id, String name, String desc, double price, PosCategory c) =>
        CatalogItem(id: id, name: name, description: desc, price: price, category: c);
    return [
      item('des-1', 'Desayuno criollo', 'Bolón, huevo y café', 2.50, PosCategory.desayunos),
      item('des-2', 'Desayuno continental', 'Pan, huevos, jugo y café', 2.50, PosCategory.desayunos),
      item('car-1', 'Churrasco montado', 'Lomo, huevo, papas y ensalada', 5.50, PosCategory.carta),
      item('car-2', 'Seco de chivo', 'Con arroz amarillo y maduro', 6.00, PosCategory.carta),
      item('car-3', 'Trucha frita', 'Con patacones y ensalada', 6.50, PosCategory.carta),
      item('car-4', 'Lomo saltado', 'Res salteada con cebolla y tomate', 5.00, PosCategory.carta),
      item('car-5', 'Pechuga a la plancha', 'Con menestra de lenteja', 4.50, PosCategory.carta),
      item('ext-1', 'Aguacate', 'Porción', 0.75, PosCategory.extras),
      item('ext-2', 'Huevo frito', 'Adicional', 0.50, PosCategory.extras),
      item('ext-3', 'Maduro con queso', 'Porción', 0.75, PosCategory.extras),
      item('ext-4', 'Papas fritas', 'Porción', 1.00, PosCategory.extras),
      item('ext-5', 'Arroz extra', 'Porción', 0.50, PosCategory.extras),
      item('ext-6', 'Ensalada', 'Porción', 0.75, PosCategory.extras),
      item('beb-1', 'Jugo de naranjilla', 'Natural', 0.75, PosCategory.bebidas),
      item('beb-2', 'Limonada', 'Con hierbabuena', 1.00, PosCategory.bebidas),
      item('beb-3', 'Gaseosa personal', '300 ml', 1.00, PosCategory.bebidas),
      item('beb-4', 'Agua', '500 ml', 0.75, PosCategory.bebidas),
      item('beb-5', 'Postre del día', 'Flan o tres leches', 1.00, PosCategory.bebidas),
      item('beb-6', 'Café', 'Pasado', 1.00, PosCategory.bebidas),
    ];
  }

  @override
  Future<String?> registerPosSale({
    required String restaurantId,
    required String label,
    required List<PosSaleLine> lines,
    required double total,
    required OwnerPayMethod method,
  }) async {
    await _simulateLatency();
    if (lines.isEmpty || total < 0) return null;
    final saleId = _nextId('pos');
    _transactions.add(TransactionItem(
      id: saleId,
      customerName: label,
      type: 'Venta Suelta',
      amount: _round2(total),
      paymentMethod: method.label,
      timestamp: _clock(),
    ));
    _posLunchUnits[saleId] =
        lines.where((l) => l.isLunch).fold<int>(0, (sum, l) => sum + l.qty);
    return saleId;
  }

  static const _scheduledOfferId = 'programada';

  @override
  bool get supportsOfferPause => true;

  @override
  Future<List<FlashOffer>> getActiveOffers(String restaurantId) async {
    await _simulateLatency();
    final now = _clock();
    return [
      for (final o in _store.flashOffers)
        if (o.restaurantId == DemoStore.ownerRestaurantId &&
            o.slotsLeft > 0 &&
            o.endsAt.isAfter(now))
          FlashOffer(
            id: o.id,
            kind: OfferKind.flash,
            title: o.dishName,
            dishId: o.dishId,
            discountPercent: o.discountPercent,
            slots: o.slotsLeft,
            slotsTotal: o.slotsTotal,
            price: o.price,
            originalPrice: o.originalPrice,
            endsAt: o.endsAt,
            paused: o.paused,
          ),
      ?_scheduledOffer,
    ];
  }

  @override
  Future<String?> publishOffer(String restaurantId, FlashOffer offer) async {
    await _simulateLatency();
    if (offer.kind == OfferKind.programada) {
      _scheduledOffer = FlashOffer(
        id: _scheduledOfferId,
        kind: OfferKind.programada,
        title: offer.title,
        discountPercent: offer.discountPercent,
        slots: offer.slots,
        price: offer.price,
        days: offer.days,
        fromMinutes: offer.fromMinutes,
        toMinutes: offer.toMinutes,
      );
      return _scheduledOfferId;
    }
    final until = offer.validUntil;
    if (until == null || until.isEmpty) return null;
    final id = _store.nextOfferId();
    _store.flashOffers.add(DemoFlashOffer(
      id: id,
      restaurantId: DemoStore.ownerRestaurantId,
      dishName: offer.title,
      dishId: offer.dishId,
      price: offer.price,
      originalPrice: offer.originalPrice ?? offer.price,
      slotsTotal: offer.slots,
      endsAt: EcuadorTime.todayAtUtc(until),
    ));
    _store.changed();
    return id;
  }

  @override
  Future<bool> cancelOffer(String restaurantId, {String? offerId}) async {
    await _simulateLatency();
    if (offerId == _scheduledOfferId) _scheduledOffer = null;
    _store.flashOffers.removeWhere(
      (o) =>
          o.restaurantId == DemoStore.ownerRestaurantId &&
          (offerId == null || o.id == offerId),
    );
    _store.changed();
    return true;
  }

  @override
  Future<bool> setOfferPaused(
    String restaurantId,
    String offerId, {
    required bool paused,
  }) async {
    await _simulateLatency();
    final offer = _store.flashOffers.where((o) => o.id == offerId).firstOrNull;
    if (offer == null) return false;
    offer.paused = paused;
    _store.changed();
    return true;
  }

  @override
  Future<bool> setManualBusy(String restaurantId, {required bool busy}) async {
    await setManualOccupancy(
      restaurantId,
      status: busy ? ManualOccupancyStatus.lleno : ManualOccupancyStatus.libre,
    );
    return true;
  }

  @override
  Future<DateTime?> setManualOccupancy(
    String restaurantId, {
    required ManualOccupancyStatus status,
    DateTime? fullUntil,
  }) async {
    await _simulateLatency();
    final legacy = switch (status) {
      ManualOccupancyStatus.cerrado => 'CERRADO',
      ManualOccupancyStatus.lleno => 'LLENO',
      ManualOccupancyStatus.concurrido => 'MOVIDO',
      ManualOccupancyStatus.libre => 'LIBRE',
    };
    final effectiveUntil = (status == ManualOccupancyStatus.lleno ||
            status == ManualOccupancyStatus.concurrido)
        ? (fullUntil ?? DateTime.now().add(const Duration(minutes: 20)))
        : null;
    final isOpen = status != ManualOccupancyStatus.cerrado;
    _store.occupancyOverrides[DemoStore.ownerRestaurantId] = legacy;
    _store.occupancyOverrides[restaurantId] = legacy;
    _store.fullUntilByRest[DemoStore.ownerRestaurantId] = effectiveUntil;
    _store.fullUntilByRest[restaurantId] = effectiveUntil;
    _store.storeOpenByRest[DemoStore.ownerRestaurantId] = isOpen;
    _store.storeOpenByRest[restaurantId] = isOpen;
    _store.changed();
    return effectiveUntil;
  }

  @override
  Future<int> getOrdersOnTheWayCount(String restaurantId) async {
    await _simulateLatency();
    return _openPreorders().length;
  }

  @override
  Future<bool> isShiftClosed(String restaurantId) async => _shiftClosed;

  @override
  Future<bool> closeShift(String restaurantId, {required double countedCash}) async {
    await _simulateLatency();
    _shiftClosed = true;
    return true;
  }

  @override
  Future<bool> reopenShift(String restaurantId) async {
    await _simulateLatency();
    _shiftClosed = false;
    return true;
  }

  // ---------------------------------------------------------------------------
  // O10 · Pasar cartulina
  // ---------------------------------------------------------------------------

  /// Cartulina digitalizada → (userId, planId, cliente creado en ese momento).
  final Map<String, (String, String, bool)> _cards = {};

  @override
  Future<String?> registerPhysicalCard({
    required String restaurantId,
    String? clientId,
    String? newClientName,
    String? phone,
    required OwnerPlanTemplate template,
    required int used,
  }) async {
    await _simulateLatency();
    final remaining = template.lunches - used;
    if (remaining <= 0) return null;
    _Student? student;
    var created = false;
    if (clientId != null) {
      student = _studentsByUserId[clientId];
    } else if (newClientName != null && newClientName.trim().isNotEmpty) {
      student = _registerStudent(_nextId('c-card'), name: newClientName.trim(), phone: phone ?? '');
      created = true;
    }
    if (student == null) return null;
    final plan = _Plan(
      id: _nextId('plan-card'),
      total: template.lunches,
      remaining: remaining,
      expiresAt: _clock().add(Duration(days: template.validityDays)),
      templateId: template.id,
    );
    student.plans.add(plan);
    final id = _nextId('card');
    _cards[id] = (student.userId, plan.id, created);
    return id;
  }

  @override
  Future<bool> undoPhysicalCard(String cardId) async {
    await _simulateLatency();
    final card = _cards.remove(cardId);
    if (card == null) return false;
    final (userId, planId, created) = card;
    if (created) {
      _studentsByUserId.remove(userId);
    } else {
      _studentsByUserId[userId]?.plans.removeWhere((p) => p.id == planId);
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // O12 · Pedidos en camino (preórdenes del almacén compartido)
  // ---------------------------------------------------------------------------

  DemoStore get _store => DemoStore.instance;

  /// Preorden entregada → id de la venta en caja.
  final Map<String, String> _deliveredSales = {};

  List<DemoPreorder> _openPreorders() => _store.preorders
      .where((o) => o.restaurantId == DemoStore.ownerRestaurantId && o.isOpen)
      .toList()
    ..sort((a, b) => (int.tryParse(a.number) ?? 0).compareTo(int.tryParse(b.number) ?? 0));

  @override
  Future<List<OwnerOrder>> getActiveOrders(String restaurantId) async {
    await _simulateLatency();
    return [
      for (final o in _openPreorders())
        OwnerOrder(
          number: o.number,
          restaurantId: o.restaurantId,
          dinerName: o.dinerName,
          soup: o.soup,
          main: o.main,
          takeaway: o.takeaway,
          takeawaySurchargeCents: o.effectiveSurchargeCents,
          amount: Money.fromCents(o.effectiveTotalCents),
          totalCents: o.effectiveTotalCents,
          createdAt: o.createdAt,
          estimatedArrivalLabel: o.estimatedArrivalLabel,
          paidByPlan: o.hasPlan,
          validated: o.validated,
          planCreditsUsed: o.planCreditsUsed,
          cashToCollectCents: o.cashToCollectCents,
          cashItems: o.cashItems,
        ),
    ];
  }

  /// Pedido con plan → (plan y comensal al que se le descontó, id del descuento).
  final Map<String, (String, String, String)> _validatedOrders = {};

  @override
  Future<({bool isValid, OwnerOrder? order, String? errorMessage})>
      verifyOrderQrCode(
    String rawPayload,
    String activeRestaurantId, {
    OwnerOrder? expectedOrder,
  }) async {
    await _simulateLatency();
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

    var preorder = _findPreorderByCode(rawPayload);
    if (preorder == null && expectedOrder != null) {
      final cleaned = BocadooQrParser.sanitizeManualInput(rawPayload);
      final expectedShort = BocadooQrParser.generateOrderCode(
        expectedOrder.number,
        orderId: expectedOrder.id ?? expectedOrder.number,
        restaurantId: activeRestaurantId,
      );
      final matchesDirect = upper == expectedOrder.number.toUpperCase() ||
          upper == '#${expectedOrder.number.toUpperCase()}' ||
          (cleaned.length == BocadooQrParser.shortCodeLength &&
              cleaned == expectedShort);
      if (matchesDirect) {
        preorder = _store.preorderByNumber(expectedOrder.number);
      }
    }

    if (preorder == null) {
      return (
        isValid: false,
        order: null,
        errorMessage: expectedOrder != null
            ? 'El código no coincide con el pedido #${expectedOrder.number}.'
            : 'No encontramos esa preorden activa.',
      );
    }

    if (preorder.restaurantId != activeRestaurantId) {
      return (
        isValid: false,
        order: null,
        errorMessage: 'Este código pertenece a otro restaurante.',
      );
    }

    if (expectedOrder != null && preorder.number != expectedOrder.number) {
      return (
        isValid: false,
        order: null,
        errorMessage:
            'Este QR corresponde al pedido #${preorder.number}, no al pedido #${expectedOrder.number}.',
      );
    }

    final ordKey = 'ORD:${preorder.number}';
    if (!preorder.isOpen || _redeemedCodes.contains(ordKey)) {
      return (
        isValid: false,
        order: null,
        errorMessage: 'Este pedido ya fue cobrado y entregado.',
      );
    }

    return (
      isValid: true,
      order: OwnerOrder(
        id: preorder.number,
        restaurantId: preorder.restaurantId,
        number: preorder.number,
        dinerName: preorder.dinerName,
        amount: preorder.amount,
        totalCents: preorder.effectiveTotalCents,
        createdAt: preorder.createdAt,
        soup: preorder.soup,
        main: preorder.main,
        drink: preorder.drink,
        estimatedArrivalLabel: preorder.estimatedArrivalLabel,
        takeaway: preorder.takeaway,
        takeawaySurchargeCents: preorder.takeawaySurchargeCents,
        paidByPlan: preorder.hasPlan,
        validated: preorder.validated,
        planCreditsUsed: preorder.planCreditsUsed,
        cashToCollectCents: preorder.cashToCollectCents,
        cashItems: preorder.cashItems,
      ),
      errorMessage: null,
    );
  }

  @override
  Future<ScanResult> confirmAndRedeemOrder(
    String orderIdOrCode,
    String activeRestaurantId, {
    OwnerPayMethod paymentMethod = OwnerPayMethod.efectivo,
  }) async {
    await _simulateLatency();
    final now = _clock();
    final cleaned = BocadooQrParser.sanitizeManualInput(orderIdOrCode);
    final codeKey = cleaned.length == BocadooQrParser.shortCodeLength
        ? cleaned
        : orderIdOrCode.trim().toUpperCase();

    final order = _findPreorderByCode(orderIdOrCode) ??
        _store.preorderByNumber(orderIdOrCode.trim());
    if (order == null) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'No encontrado',
        supportingLine: 'No encontramos esa preorden activa.',
        actionRequired: 'NINGUNA',
      );
    }

    if (order.restaurantId != activeRestaurantId) {
      return const ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Es de otro local',
        supportingLine: 'Este código pertenece a otro restaurante',
        actionRequired: 'NINGUNA',
      );
    }

    final ordKey = 'ORD:${order.number}';
    if (!order.isOpen ||
        _redeemedCodes.contains(ordKey) ||
        _redeemedCodes.contains(codeKey)) {
      return ScanResult(
        isValid: false,
        outcome: 'ROJO',
        title: 'Ya canjeado',
        supportingLine: 'Este código ya fue canjeado anteriormente',
        studentName: order.dinerName,
        actionRequired: 'NINGUNA',
      );
    }

    _redeemedCodes.add(ordKey);
    _redeemedCodes.add(codeKey);
    _redeemedCodes.add(
      BocadooQrParser.generateOrderCode(
        order.number,
        orderId: order.number,
        restaurantId: order.restaurantId,
      ),
    );

    if (order.hasPlan) {
      final student = _studentByName(order.dinerName);
      final plan = student?.nextRedeemablePlan(now);
      if (student == null || plan == null) {
        _redeemedCodes.remove(ordKey);
        _redeemedCodes.remove(codeKey);
        return ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Sin saldo',
          supportingLine: 'El comensal no tiene almuerzos disponibles en su plan.',
          studentName: order.dinerName,
          actionRequired: 'VENDER_PLAN',
        );
      }
      plan.remaining -= 1;
      if (student.userId == DemoStore.dinerUserId) {
        final curr = _store.remainingLunchesByRest[order.restaurantId] ?? 0;
        if (curr > 0) _store.remainingLunchesByRest[order.restaurantId] = curr - 1;
      }
      final r = _Redemption(
        id: _nextId('red'),
        userId: student.userId,
        planId: plan.id,
        timestamp: now,
      );
      _redemptions.add(r);
      final dishParts = <String>[
        if (order.soup != null && order.soup!.isNotEmpty) order.soup!,
        if (order.main != null && order.main!.isNotEmpty) order.main!,
      ];
      final dishLabel =
          dishParts.isNotEmpty ? dishParts.join(' + ') : 'Almuerzo completo';
      _transactions.add(TransactionItem(
        id: r.id,
        customerName: 'Pedido #${order.number} · ${order.dinerName}',
        type: 'Canje de plan',
        amount: 0,
        paymentMethod: 'Plan',
        timestamp: now,
        detail: 'Canje de plan · $dishLabel (Prepagado)',
      ));
      order
        ..validated = true
        ..status = PreorderStatus.delivered
        ..deliveredAt = now;
      _validatedOrders[order.number] = (student.userId, plan.id, r.id);
      _store.changed();
      return ScanResult(
        isValid: true,
        outcome: 'VERDE',
        title: 'Preorden #${order.number} canjeada',
        supportingLine: 'Canje de plan · $dishLabel (Prepagado)',
        studentName: order.dinerName,
        remainingLunches: plan.remaining,
        redemptionId: r.id,
        redeemedAt: now,
        actionRequired: 'NINGUNA',
      );
    }

    final totalCents = order.effectiveTotalCents;
    final saleId = _nextId('ord');
    _transactions.add(TransactionItem(
      id: saleId,
      customerName: 'Pedido #${order.number} · ${order.dinerName}',
      type: 'Venta Suelta',
      amount: Money.fromCents(totalCents),
      paymentMethod: paymentMethod.label,
      timestamp: now,
    ));
    _posLunchUnits[saleId] = 1;
    _deliveredSales[order.number] = saleId;
    order
      ..status = PreorderStatus.delivered
      ..deliveredAt = now;
    _store.changed();

    return ScanResult(
      isValid: true,
      outcome: 'VERDE',
      title: 'Preorden #${order.number} cobrada',
      supportingLine: '${order.soup ?? ''} · ${order.main ?? ''}'.trim(),
      studentName: order.dinerName,
      redemptionId: saleId,
      redeemedAt: now,
      actionRequired: 'NINGUNA',
    );
  }

  @override
  Future<bool> validateOrder(String restaurantId, String orderNumber) async {
    await _simulateLatency();
    final order = _store.preorderByNumber(orderNumber);
    if (order == null || !order.isOpen || !order.hasPlan || order.validated) return false;
    final now = _clock();
    final student = _studentByName(order.dinerName);
    final plan = student?.nextRedeemablePlan(now);
    if (student == null || plan == null) return false;
    plan.remaining -= 1;
    if (student.userId == DemoStore.dinerUserId) {
      final curr = _store.remainingLunchesByRest[order.restaurantId] ?? 0;
      if (curr > 0) _store.remainingLunchesByRest[order.restaurantId] = curr - 1;
    }
    final r = _Redemption(id: _nextId('red'), userId: student.userId, planId: plan.id, timestamp: now);
    _redemptions.add(r);
    final dishParts = <String>[
      if (order.soup != null && order.soup!.isNotEmpty) order.soup!,
      if (order.main != null && order.main!.isNotEmpty) order.main!,
    ];
    final dishLabel =
        dishParts.isNotEmpty ? dishParts.join(' + ') : 'Almuerzo completo';
    _transactions.add(TransactionItem(
      id: r.id,
      customerName: 'Pedido #$orderNumber · ${order.dinerName}',
      type: 'Canje de plan',
      amount: 0,
      paymentMethod: 'Plan',
      timestamp: now,
      detail: 'Canje de plan · $dishLabel (Prepagado)',
    ));
    order.validated = true;
    _validatedOrders[orderNumber] = (student.userId, plan.id, r.id);
    _store.changed();
    return true;
  }

  @override
  Future<bool> undoValidate(String restaurantId, String orderNumber) async {
    await _simulateLatency();
    final order = _store.preorderByNumber(orderNumber);
    final done = _validatedOrders.remove(orderNumber);
    if (order == null || done == null) return false;
    final (userId, planId, redemptionId) = done;
    for (final p in _studentsByUserId[userId]?.plans ?? const <_Plan>[]) {
      if (p.id == planId) p.remaining += 1;
    }
    for (final r in _redemptions) {
      if (r.id == redemptionId) r.annulled = true;
    }
    _transactions.removeWhere((t) => t.id == redemptionId);
    order.validated = false;
    _store.changed();
    return true;
  }

  @override
  Future<bool> deliverOrder(String restaurantId, String orderNumber) async {
    final res = await confirmAndRedeemOrder(orderNumber, restaurantId);
    return res.isValid;
  }

  @override
  Future<bool> undoDeliver(String restaurantId, String orderNumber) async {
    await _simulateLatency();
    final order = _store.preorderByNumber(orderNumber);
    if (order == null || order.status != PreorderStatus.delivered) return false;
    final saleId = _deliveredSales.remove(orderNumber);
    if (saleId == null && !order.hasPlan) return false;
    order
      ..status = PreorderStatus.pending
      ..deliveredAt = null;
    if (saleId != null) {
      _transactions.removeWhere((t) => t.id == saleId);
      _posLunchUnits.remove(saleId);
    }
    _store.changed();
    return true;
  }

  // ---------------------------------------------------------------------------
  // O5 · Cobrar mesa
  // ---------------------------------------------------------------------------

  static const double _tableLunchPrice = 3.00;

  /// Cobro de mesa → (mesa, planes descontados, ventas en caja).
  final Map<String, (String, List<(String, String)>, List<String>)> _tableCharges = {};

  _Student? _studentByName(String name) {
    final needle = name.trim().toLowerCase();
    for (final s in _studentsByUserId.values) {
      if (s.restaurantId == restaurantId && s.name.toLowerCase() == needle) return s;
    }
    return null;
  }

  @override
  Future<List<PendingTable>> getPendingTables(String restaurantId) async {
    await _simulateLatency();
    final out = <PendingTable>[];
    for (final t in _store.tables.values) {
      if (t.restaurantId != DemoStore.ownerRestaurantId ||
          t.members.isEmpty ||
          _store.settledTables.contains(t.id)) {
        continue;
      }
      final preview = _preview(t.id);
      var planCount = 0;
      var cashCount = 0;
      for (final line in preview.lines) {
        if (line.via == TableChargeVia.cash) {
          cashCount++;
        } else {
          planCount++;
        }
      }
      final takeawayCount = t.members.where((m) => m.takeaway).length;
      final unitSurchargeCents = (t.takeawaySurcharge * 100).round();
      final totalSurchargeCents = takeawayCount > 0
          ? takeawayCount * unitSurchargeCents
          : (t.takeaway ? t.effectivePartySize * unitSurchargeCents : 0);
      final memberDishes = <PendingTableMemberDish>[
        for (var i = 0; i < t.members.length; i++)
          PendingTableMemberDish(
            memberName: t.members[i].name,
            soup: t.members[i].soup,
            main: t.members[i].main,
            takeaway: t.members[i].takeaway,
            hasPlan: i < preview.lines.length &&
                preview.lines[i].via != TableChargeVia.cash,
          ),
      ];
      out.add(
        PendingTable(
          id: t.id,
          hostName: t.hostName,
          members: t.members.length,
          time: t.time,
          planCount: planCount,
          cashCount: cashCount,
          takeawayCount: takeawayCount > 0 ? takeawayCount : (t.takeaway ? t.effectivePartySize : 0),
          takeawaySurchargeCents: totalSurchargeCents,
          memberDishes: memberDishes,
        ),
      );
    }
    return out;
  }

  TablePreview _preview(String tableId) {
    final id = tableId.toUpperCase();
    final table = _store.tables[id];
    if (table == null) {
      return TablePreview(tableId: id, hostName: '', time: '', mode: TableMode.eachOwn, error: 'Mesa no encontrada.');
    }
    final settled = _store.settledTables.contains(id);
    final now = _clock();
    final lines = <TableChargeLine>[];
    final stamps = <String, int>{};
    String? error;

    if (table.mode == TableMode.hostPays) {
      final host = _studentByName(table.hostName);
      final balance = host?.redeemableBalance(now) ?? 0;
      if (balance < table.members.length) {
        error = 'El plan de ${table.hostName} no alcanza para ${table.members.length} almuerzos (tiene $balance).';
      }
      for (final m in table.members) {
        lines.add(TableChargeLine(
          name: m.name,
          soup: m.soup,
          main: m.main,
          isHost: m.isHost,
          takeaway: m.takeaway,
          via: TableChargeVia.hostPlan,
          amount: 0,
        ));
        stamps[table.hostName] = (stamps[table.hostName] ?? 0) + 1;
      }
    } else {
      for (final m in table.members) {
        final student = _studentByName(m.name);
        final hasPlan = student != null && student.redeemableBalance(now) > 0;
        lines.add(TableChargeLine(
          name: m.name,
          soup: m.soup,
          main: m.main,
          isHost: m.isHost,
          takeaway: m.takeaway,
          via: hasPlan ? TableChargeVia.plan : TableChargeVia.cash,
          amount: hasPlan ? 0 : _tableLunchPrice + (m.takeaway ? table.takeawaySurcharge : 0),
        ));
        if (student != null) stamps[m.name] = (stamps[m.name] ?? 0) + 1;
      }
    }
    return TablePreview(
      tableId: id,
      hostName: table.hostName,
      time: table.time,
      mode: table.mode,
      lines: lines,
      stamps: [for (final e in stamps.entries) (e.key, e.value)],
      error: settled ? 'Esta mesa ya fue cobrada.' : error,
      settled: settled,
    );
  }

  @override
  Future<TablePreview> previewTable(String restaurantId, String tableId) async {
    await _simulateLatency();
    return _preview(tableId);
  }

  @override
  Future<TablePreview> setTableMode(String restaurantId, String tableId, TableMode mode) async {
    await _simulateLatency();
    final id = tableId.toUpperCase();
    final table = _store.tables[id];
    if (table != null && !_store.settledTables.contains(id)) {
      _store.tables[id] = table.copyWith(mode: mode);
      _store.changed();
    }
    return _preview(id);
  }

  @override
  Future<String?> chargeTable(String restaurantId, String tableId) async {
    await _simulateLatency();
    final preview = _preview(tableId);
    final table = _store.tables[preview.tableId];
    if (!preview.canCharge || table == null) return null;
    final now = _clock();
    final deducted = <(String, String)>[];
    final sales = <String>[];

    bool takeFrom(_Student s, String customer) {
      final plan = s.nextRedeemablePlan(now);
      if (plan == null) return false;
      plan.remaining -= 1;
      final r = _Redemption(id: _nextId('red'), userId: s.userId, planId: plan.id, timestamp: now);
      _redemptions.add(r);
      _transactions.add(TransactionItem(
        id: r.id,
        customerName: customer,
        type: 'Validado',
        amount: 0,
        paymentMethod: 'Plan',
        timestamp: now,
      ));
      deducted.add((s.userId, plan.id));
      sales.add(r.id);
      return true;
    }

    final host = _studentByName(table.hostName);
    var cash = 0.0;
    var cashLunches = 0;
    for (final line in preview.lines) {
      switch (line.via) {
        case TableChargeVia.hostPlan:
          if (host != null) takeFrom(host, 'Mesa #${table.id} · ${line.name}');
        case TableChargeVia.plan:
          final s = _studentByName(line.name);
          if (s != null) takeFrom(s, 'Mesa #${table.id} · ${line.name}');
        case TableChargeVia.cash:
          cash += line.amount;
          cashLunches++;
      }
    }
    if (cash > 0) {
      final saleId = _nextId('mesa');
      _transactions.add(TransactionItem(
        id: saleId,
        customerName: 'Mesa #${table.id} · sueltos',
        type: 'Venta Suelta',
        amount: _round2(cash),
        paymentMethod: 'Efectivo',
        timestamp: now,
      ));
      _posLunchUnits[saleId] = cashLunches;
      sales.add(saleId);
    }
    _store.settledTables.add(table.id);
    _store.changed();
    final chargeId = _nextId('cobro-mesa');
    _tableCharges[chargeId] = (table.id, deducted, sales);
    return chargeId;
  }

  @override
  Future<bool> undoTableCharge(String chargeId) async {
    await _simulateLatency();
    final charge = _tableCharges.remove(chargeId);
    if (charge == null) return false;
    final (tableId, deducted, sales) = charge;
    for (final (userId, planId) in deducted) {
      for (final p in _studentsByUserId[userId]?.plans ?? const <_Plan>[]) {
        if (p.id == planId) p.remaining += 1;
      }
    }
    for (final r in _redemptions) {
      if (sales.contains(r.id)) r.annulled = true;
    }
    _transactions.removeWhere((t) => sales.contains(t.id));
    for (final id in sales) {
      _posLunchUnits.remove(id);
    }
    _store.settledTables.remove(tableId);
    _store.changed();
    return true;
  }

  // ---------------------------------------------------------------------------
  // O15 · Opiniones
  // ---------------------------------------------------------------------------

  /// Opinión → plan al que se le repuso un almuerzo (para deshacer).
  final Map<String, (String, String)> _replacedLunches = {};

  @override
  Future<List<OwnerOpinion>> getOpinions(String restaurantId) async {
    await _simulateLatency();
    final now = _clock();
    final list = _store.feedback.where((f) => f.restaurantId == DemoStore.ownerRestaurantId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      for (final f in list)
        () {
          final s = _studentByName(f.dinerName);
          return OwnerOpinion(
            id: f.id,
            dinerName: f.dinerName,
            tag: f.tag,
            note: f.note,
            createdAt: f.createdAt,
            reply: f.reply,
            phone: s == null || s.phone.isEmpty ? null : s.phone,
            canReplaceLunch: s != null && s.nextRedeemablePlan(now) != null,
          );
        }(),
    ];
  }

  @override
  Future<bool> replyOpinion(String restaurantId, String opinionId, OpinionReply reply) async {
    await _simulateLatency();
    final f = _store.feedback.where((x) => x.id == opinionId).firstOrNull;
    if (f == null || f.reply != null) return false;
    if (reply == OpinionReply.replaceLunch) {
      final s = _studentByName(f.dinerName);
      final plan = s?.nextRedeemablePlan(_clock());
      if (s == null || plan == null) return false;
      plan.remaining += 1;
      _replacedLunches[opinionId] = (s.userId, plan.id);
    }
    f.reply = reply.label;
    _store.changed();
    return true;
  }

  @override
  Future<bool> undoReply(String opinionId) async {
    await _simulateLatency();
    final f = _store.feedback.where((x) => x.id == opinionId).firstOrNull;
    if (f == null || f.reply == null) return false;
    final replaced = _replacedLunches.remove(opinionId);
    if (replaced != null) {
      for (final p in _studentsByUserId[replaced.$1]?.plans ?? const <_Plan>[]) {
        if (p.id == replaced.$2) p.remaining -= 1;
      }
    }
    f.reply = null;
    _store.changed();
    return true;
  }

  // ---------------------------------------------------------------------------
  // O16 · Datos del local
  // ---------------------------------------------------------------------------

  Uint8List? _logo;

  @override
  Future<LocalInfo> getLocalInfo(String restaurantId) async {
    await _simulateLatency();
    return LocalInfo(name: 'La Cuchara de San Blas', address: 'San Blas, Quito', seats: 24, logo: _logo);
  }

  @override
  Future<bool> setLogo(String restaurantId, Uint8List? bytes) async {
    await _simulateLatency();
    // TODO: Conectar con provider de backend (subir el logo al almacenamiento del local).
    _logo = bytes;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Reglas de validación
  // ---------------------------------------------------------------------------

  ScanResult _evaluate(_Student student, DateTime now) {
    if (student.restaurantId != restaurantId) {
      return _result(
        student,
        isValid: false,
        outcome: 'ROJO',
        title: 'Es de otro local',
        supportingLine: 'Este código pertenece a otro restaurante',
        action: 'VENDER_PLAN',
      );
    }

    // Doble escaneo (< 60 s).
    final recent = _recentRedemption(student, now);
    if (recent != null) {
      return _result(
        student,
        isValid: false,
        outcome: 'ROJO',
        title: 'Ya canjeado',
        supportingLine: 'Este código ya fue canjeado anteriormente',
        action: 'NINGUNA',
        redemption: recent,
      );
    }

    final plan = student.nextRedeemablePlan(now);
    if (plan == null) {
      final hasBalance = student.plans.any((p) => p.remaining > 0);
      return _result(
        student,
        isValid: false,
        outcome: 'ROJO',
        title: 'Sin saldo activo',
        supportingLine: hasBalance
            ? 'Su plan anterior ya venció.'
            : 'No le quedan almuerzos disponibles.',
        action: 'VENDER_PLAN',
      );
    }

    // Saldo que quedará una vez confirmado el canje.
    final remainingAfter = student.redeemableBalance(now) - 1;
    final daysLeft = _calendarDaysBetween(now, plan.expiresAt);

    if (remainingAfter <= 0) {
      return _result(
        student,
        isValid: true,
        outcome: 'ADVERTENCIA',
        title: 'Último almuerzo',
        supportingLine: 'Su plan acaba de terminar hoy.',
        action: 'VENDER_PLAN',
        remaining: 0,
      );
    }
    if (daysLeft <= 3) {
      return _result(
        student,
        isValid: true,
        outcome: 'ADVERTENCIA',
        title: 'Vence pronto',
        supportingLine:
            'Su plan vence en $daysLeft ${daysLeft == 1 ? 'día' : 'días'}.',
        action: 'VENDER_PLAN',
        remaining: remainingAfter,
      );
    }
    return _result(
      student,
      isValid: true,
      outcome: 'VERDE',
      title: 'Almuerzo registrado',
      supportingLine: 'Le quedan $remainingAfter almuerzos',
      action: 'NINGUNA',
      remaining: remainingAfter,
    );
  }

  /// `remainingLunches` en un resultado válido es el saldo *después* del canje.
  ScanResult _result(
    _Student student, {
    required bool isValid,
    required String outcome,
    required String title,
    required String supportingLine,
    required String action,
    int? remaining,
    _Redemption? redemption,
  }) {
    final batchId = isValid
        ? (_pendingBatchIdByPassId[student.passId] ??= uuidV4())
        : null;
    return ScanResult(
      isValid: isValid,
      outcome: outcome,
      title: title,
      supportingLine: supportingLine,
      studentName: student.name,
      studentCareer: student.career,
      passId: student.passId,
      totalLunches: student.plans.fold<int>(0, (s, p) => s + p.total),
      remainingLunches: remaining,
      redemptionId: redemption?.id,
      batchRedemptionId: batchId,
      redeemedAt: redemption?.timestamp,
      actionRequired: action,
    );
  }

  _Redemption? _recentRedemption(_Student student, DateTime now) {
    for (final r in _redemptions.reversed) {
      if (r.userId != student.userId || r.annulled) continue;
      return now.difference(r.timestamp) < _doubleScanWindow ? r : null;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  Future<void> _simulateLatency() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  _Student? _studentByPassId(String passId) {
    for (final s in _studentsByUserId.values) {
      if (s.passId == passId) return s;
    }
    return null;
  }

  /// Busca por userId exacto o por nombre (sin distinguir mayúsculas).
  _Student? _findStudent(String identifier) {
    final byId = _studentsByUserId[identifier];
    if (byId != null) return byId;
    final needle = identifier.toLowerCase();
    for (final s in _studentsByUserId.values) {
      if (s.name.toLowerCase().contains(needle)) return s;
    }
    return null;
  }

  _Student _registerStudent(String identifier, {String? name, String phone = ''}) {
    final student = _Student(
      userId: identifier,
      name: name ?? identifier,
      career: 'Estudiante',
      restaurantId: restaurantId,
      phone: phone,
    );
    _studentsByUserId[identifier] = student;
    return student;
  }

  String? _normalizePaymentMethod(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'efectivo':
        return 'Efectivo';
      case 'transferencia':
        return 'Transferencia';
      case 'deuna':
        return 'Deuna';
      case 'tarjeta':
        return 'Tarjeta';
      default:
        return null;
    }
  }

  List<TransactionItem> _todayTransactions(DateTime now) {
    final list = _transactions.where((t) => _sameDay(t.timestamp, now)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  String _nextId(String prefix) => '${prefix}_${++_sequence}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _calendarDaysBetween(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  // ---------------------------------------------------------------------------
  // Datos semilla (QR de prueba: userId u1..u6, ver docs del parser)
  // ---------------------------------------------------------------------------

  void _seed() {
    final now = _clock();

    void add(
      String userId,
      String name,
      String career,
      List<_Plan> plans, {
      String? restaurant,
      String phone = '',
    }) {
      _studentsByUserId[userId] = _Student(
        userId: userId,
        name: name,
        career: career,
        restaurantId: restaurant ?? restaurantId,
        plans: plans,
        phone: phone,
      );
    }

    _Plan plan(String id, int total, int remaining, int days, String templateId) => _Plan(
          id: id,
          total: total,
          remaining: remaining,
          expiresAt: now.add(Duration(days: days)),
          templateId: templateId,
        );

    add('u1', 'Carlos Mejía', 'Ing. de Sistemas',
        [plan('seed-1', 20, 12, 20, 'tpl-mensual')], phone: '0991234567'); // VERDE
    add('u2', 'Valentina Ortiz', 'Administración',
        [plan('seed-2', 10, 1, 15, 'tpl-quincenal')], phone: '0987654321'); // ADVERTENCIA: último almuerzo
    add('u3', 'Sofía Almeida', 'Diseño Gráfico',
        [plan('seed-3', 10, 8, 2, 'tpl-quincenal')], phone: '0998877665'); // ADVERTENCIA: vence pronto
    add('u4', 'Diego Salazar', 'Derecho',
        [plan('seed-4', 5, 4, -2, 'tpl-semanal')], phone: '0976543210'); // ROJO: plan vencido
    add('u5', 'Luis Paredes', 'Psicología',
        [plan('seed-5', 20, 0, 10, 'tpl-mensual')], phone: '0965432109'); // ROJO: sin almuerzos
    add('u6', 'Andrés Ortiz', 'Medicina',
        [plan('seed-6', 20, 15, 25, 'tpl-mensual')],
        restaurant: 'rest-otro'); // ROJO: otro local
  }
}

class _Plan {
  _Plan({
    required this.id,
    required this.total,
    required this.remaining,
    required this.expiresAt,
    this.templateId,
  });

  final String id;
  final int total;
  int remaining;
  final DateTime expiresAt;
  final String? templateId;
}

class _Student {
  _Student({
    required this.userId,
    required this.name,
    required this.career,
    required this.restaurantId,
    List<_Plan>? plans,
    this.phone = '',
  }) : plans = plans ?? [];

  final String userId;
  final String name;
  final String career;
  final String phone;
  final String restaurantId;
  final List<_Plan> plans;
  String email = '';
  String notes = '';

  String get passId => 'pass-$userId';

  bool _isLive(_Plan p, DateTime now) =>
      p.remaining > 0 &&
      !DateTime(p.expiresAt.year, p.expiresAt.month, p.expiresAt.day)
          .isBefore(DateTime(now.year, now.month, now.day));

  /// FIFO: el plan con saldo que vence primero y aún no ha caducado.
  _Plan? nextRedeemablePlan(DateTime now) {
    final live = plans.where((p) => _isLive(p, now)).toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    return live.isEmpty ? null : live.first;
  }

  int redeemableBalance(DateTime now) =>
      plans.where((p) => _isLive(p, now)).fold<int>(0, (s, p) => s + p.remaining);
}

class _Redemption {
  _Redemption({
    required this.id,
    required this.userId,
    required this.planId,
    required this.timestamp,
  });

  final String id;
  final String userId;
  final String planId;
  final DateTime timestamp;
  bool annulled = false;
}

class _RedemptionBatch {
  _RedemptionBatch({
    required this.batchId,
    required this.passId,
    required this.userId,
    required this.restaurantId,
    required this.customerName,
    required this.transactionId,
    required this.redemptions,
  });

  final String batchId;
  final String passId;
  final String userId;
  final String restaurantId;
  final String customerName;
  final String transactionId;
  final List<_Redemption> redemptions;
  bool undone = false;
}
