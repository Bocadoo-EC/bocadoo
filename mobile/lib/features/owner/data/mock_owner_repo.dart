import 'dart:typed_data';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/demo/demo_store.dart';
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

  FlashOffer? _activeOffer;
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
      lunches: 10,
      price: 28,
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

  @override
  Future<ScanResult> validateQrCode(String rawPayload) async {
    await _simulateLatency();
    final now = _clock();

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

    return _evaluate(student, now);
  }

  @override
  Future<bool> confirmRedeem(String passId) async {
    await _simulateLatency();
    final now = _clock();

    final student = _studentByPassId(passId);
    if (student == null) return false;

    // Idempotencia: si ya se canjeó hace < 60 s no se descuenta otra vez.
    if (_recentRedemption(student, now) != null) return false;

    final plan = student.nextRedeemablePlan(now);
    if (plan == null) return false;

    plan.remaining -= 1;
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
        type: 'Validado',
        amount: 0,
        paymentMethod: 'Plan',
        timestamp: now,
      ),
    );
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

    final redeemed = today.where((t) => t.type == 'Validado').length +
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

    return TransactionSummary(
      date: now,
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

  @override
  Future<bool> undoRedeem(String passId) async {
    await _simulateLatency();
    final student = _studentByPassId(passId);
    if (student == null) return false;
    for (final r in _redemptions.reversed) {
      if (r.userId != student.userId || r.annulled) continue;
      r.annulled = true;
      for (final p in student.plans) {
        if (p.id == r.planId) p.remaining += 1;
      }
      _transactions.removeWhere((t) => t.id == r.id);
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

  @override
  Future<FlashOffer?> getActiveOffer(String restaurantId) async {
    await _simulateLatency();
    return _activeOffer;
  }

  @override
  Future<bool> publishOffer(String restaurantId, FlashOffer offer) async {
    await _simulateLatency();
    _activeOffer = offer;
    return true;
  }

  @override
  Future<bool> cancelOffer(String restaurantId) async {
    await _simulateLatency();
    _activeOffer = null;
    return true;
  }

  @override
  Future<bool> setManualBusy(String restaurantId, {required bool busy}) async {
    await _simulateLatency();
    return true;
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
          dinerName: o.dinerName,
          soup: o.soup,
          main: o.main,
          takeaway: o.takeaway,
          amount: o.amount,
          createdAt: o.createdAt,
          paidByPlan: o.hasPlan,
          validated: o.validated,
        ),
    ];
  }

  /// Pedido con plan → (plan y comensal al que se le descontó, id del descuento).
  final Map<String, (String, String, String)> _validatedOrders = {};

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
    final r = _Redemption(id: _nextId('red'), userId: student.userId, planId: plan.id, timestamp: now);
    _redemptions.add(r);
    _transactions.add(TransactionItem(
      id: r.id,
      customerName: 'Pedido #$orderNumber · ${order.dinerName}',
      type: 'Validado',
      amount: 0,
      paymentMethod: 'Plan',
      timestamp: now,
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
    await _simulateLatency();
    final order = _store.preorderByNumber(orderNumber);
    if (order == null || !order.isOpen) return false;
    // Con plan, primero se valida su QR (descuenta el almuerzo).
    if (order.hasPlan && !order.validated) return false;
    final now = _clock();
    order
      ..status = PreorderStatus.delivered
      ..deliveredAt = now;
    if (!order.hasPlan) {
      final saleId = _nextId('ord');
      _transactions.add(TransactionItem(
        id: saleId,
        customerName: 'Pedido #$orderNumber · ${order.dinerName}',
        type: 'Venta Suelta',
        amount: _round2(order.amount),
        paymentMethod: 'Efectivo',
        timestamp: now,
      ));
      _posLunchUnits[saleId] = 1;
      _deliveredSales[orderNumber] = saleId;
    }
    _store.changed();
    return true;
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
    return [
      for (final t in _store.tables.values)
        if (t.restaurantId == DemoStore.ownerRestaurantId &&
            t.members.isNotEmpty &&
            !_store.settledTables.contains(t.id))
          PendingTable(id: t.id, hostName: t.hostName, members: t.members.length, time: t.time),
    ];
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
        supportingLine: 'Este plan pertenece a otro restaurante.',
        action: 'VENDER_PLAN',
      );
    }

    // Doble escaneo (< 60 s).
    final recent = _recentRedemption(student, now);
    if (recent != null) {
      return _result(
        student,
        isValid: false,
        outcome: 'GRIS',
        title: 'Ya validado',
        supportingLine: 'Ya se descontó hace un momento.',
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
