import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';
import '../domain/models/cash_models.dart';
import '../domain/repositories/i_owner_repository.dart';

/// Repositorio mock del Dueño. Porta la lógica del PMV Web
/// (`src/domain/redemption.ts`, `plans.ts` y `cash.ts`):
/// - Validación de QR con [BocadooQrParser] (formato, firma y ventana de 30 s).
/// - Descuento FIFO: se consume del plan que vence primero.
/// - Control de doble escaneo: un comensal no se valida dos veces en < 60 s.
/// - Cierre de caja: solo el efectivo cobrado hoy es "esperado" en gaveta.
// TODO: Conectar con provider de backend
class MockOwnerRepository implements IOwnerRepository, IOwnerCashRepository {
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
          OwnerClient(id: s.userId, name: s.name, phone: s.phone),
    ];
  }

  @override
  Future<List<OwnerPlanTemplate>> getPlanTemplates(String restaurantId) async {
    await _simulateLatency();
    return const [
      OwnerPlanTemplate(
          id: 'tpl-semanal', name: 'Plan semanal', lunches: 5, price: 15, validityDays: 7),
      OwnerPlanTemplate(
          id: 'tpl-quincenal', name: 'Plan quincenal', lunches: 10, price: 28, validityDays: 15),
      OwnerPlanTemplate(
          id: 'tpl-mensual',
          name: 'Plan mensual ejecutivo',
          lunches: 20,
          price: 55,
          validityDays: 30),
    ];
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
    return 1;
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

  _Student _registerStudent(String identifier, {String? name}) {
    final student = _Student(
      userId: identifier,
      name: name ?? identifier,
      career: 'Estudiante',
      restaurantId: restaurantId,
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

    _Plan plan(String id, int total, int remaining, int days) => _Plan(
          id: id,
          total: total,
          remaining: remaining,
          expiresAt: now.add(Duration(days: days)),
        );

    add('u1', 'Carlos Mejía', 'Ing. de Sistemas',
        [plan('seed-1', 20, 12, 20)], phone: '0991234567'); // VERDE
    add('u2', 'Valentina Ortiz', 'Administración',
        [plan('seed-2', 10, 1, 15)], phone: '0987654321'); // ADVERTENCIA: último almuerzo
    add('u3', 'Sofía Almeida', 'Diseño Gráfico',
        [plan('seed-3', 15, 8, 2)], phone: '0998877665'); // ADVERTENCIA: vence pronto
    add('u4', 'Diego Salazar', 'Derecho',
        [plan('seed-4', 10, 4, -2)], phone: '0976543210'); // ROJO: plan vencido
    add('u5', 'Luis Paredes', 'Psicología',
        [plan('seed-5', 10, 0, 10)], phone: '0965432109'); // ROJO: sin almuerzos
    add('u6', 'Andrés Ortiz', 'Medicina',
        [plan('seed-6', 20, 15, 25)],
        restaurant: 'rest-otro'); // ROJO: otro local
  }
}

class _Plan {
  _Plan({
    required this.id,
    required this.total,
    required this.remaining,
    required this.expiresAt,
  });

  final String id;
  final int total;
  int remaining;
  final DateTime expiresAt;
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
