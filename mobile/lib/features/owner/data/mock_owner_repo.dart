import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';

/// Repositorio mock del Dueño. Porta la lógica del PMV Web
/// (`src/domain/redemption.ts`, `plans.ts` y `cash.ts`):
/// - Validación de QR con [BocadooQrParser] (formato, firma y ventana de 30 s).
/// - Descuento FIFO: se consume del plan que vence primero.
/// - Control de doble escaneo: un comensal no se valida dos veces en < 60 s.
/// - Cierre de caja: solo el efectivo cobrado hoy es "esperado" en gaveta.
class MockOwnerRepository implements IOwnerRepository {
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

    final redeemed = today.where((t) => t.type == 'Canje').length;
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
        title: hasBalance ? 'Plan vencido' : 'Sin almuerzos',
        supportingLine: hasBalance
            ? 'El plan caducó. Ofrécele renovar hoy.'
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
        supportingLine: '¡Se agotará su plan! Ofrécele renovar.',
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
      title: 'Validado',
      supportingLine: 'Le quedarán $remainingAfter.',
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

  _Student _registerStudent(String identifier) {
    final student = _Student(
      userId: identifier,
      name: identifier,
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
    }) {
      _studentsByUserId[userId] = _Student(
        userId: userId,
        name: name,
        career: career,
        restaurantId: restaurant ?? restaurantId,
        plans: plans,
      );
    }

    _Plan plan(String id, int total, int remaining, int days) => _Plan(
          id: id,
          total: total,
          remaining: remaining,
          expiresAt: now.add(Duration(days: days)),
        );

    add('u1', 'Camila Andrade', 'Ing. de Sistemas',
        [plan('seed-1', 20, 12, 20)]); // VERDE
    add('u2', 'Mateo Villacís', 'Administración',
        [plan('seed-2', 10, 1, 15)]); // ADVERTENCIA: último almuerzo
    add('u3', 'Sofía Paredes', 'Diseño Gráfico',
        [plan('seed-3', 15, 8, 2)]); // ADVERTENCIA: vence pronto
    add('u4', 'Diego Salazar', 'Derecho',
        [plan('seed-4', 10, 4, -2)]); // ROJO: plan vencido
    add('u5', 'Valeria Núñez', 'Psicología',
        [plan('seed-5', 10, 0, 10)]); // ROJO: sin almuerzos
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
  }) : plans = plans ?? [];

  final String userId;
  final String name;
  final String career;
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
  final bool annulled = false;
}
