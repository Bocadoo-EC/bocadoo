import '../../../../core/contracts/models.dart';
import '../../../../core/contracts/qr_parser.dart';
import '../../data/local_customer_cache.dart';
import '../../domain/models/plan_option.dart';
import '../../domain/repositories/i_plan_repository.dart';

/// Implementación de [IPlanRepository] con persistencia local y estado mock
/// listo para conmutarse a la API HTTP de Bocadoo.
class CustomerPlanRepository implements IPlanRepository {
  final LocalCustomerCache _cache;
  final Duration networkLatency;
  final Set<String> _claimedRecords = {};

  CustomerPlanRepository({
    LocalCustomerCache? cache,
    this.networkLatency = const Duration(milliseconds: 450),
  }) : _cache = cache ?? LocalCustomerCache();

  static const List<PlanOption> _defaultOptions = [
    PlanOption(
      id: 'plan-5',
      name: 'Paquete de 5',
      lunchesCount: 5,
      price: 15.00,
      savings: 0,
      validityDays: 15,
    ),
    PlanOption(
      id: 'plan-10',
      name: 'Paquete de 10',
      lunchesCount: 10,
      price: 28.00,
      savings: 2,
      validityDays: 30,
    ),
    PlanOption(
      id: 'plan-20',
      name: 'Paquete de 20',
      lunchesCount: 20,
      price: 55.00,
      savings: 5,
      validityDays: 30,
      isPopular: true,
    ),
  ];

  @override
  Future<List<PlanOption>> getPlanOptions({String? restaurantId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _defaultOptions;
  }

  @override
  Future<CustomerPass> acquirePlan({
    required PlanOption option,
    required String restaurantId,
    required String restaurantName,
    CustomerPass? currentPass,
  }) async {
    await Future<void>.delayed(networkLatency);

    final basePass = currentPass ?? await _cache.getPass();
    final userId = basePass?.userId ?? 'u1';
    final newToken = BocadooQrParser.generateQrPayload(userId);
    final currentRemaining =
        (basePass != null && !basePass.isExpired) ? basePass.remainingLunches : 0;
    final updatedRemaining = currentRemaining + option.lunchesCount;

    final updatedPass = CustomerPass(
      id: basePass?.id ?? 'sub-1',
      userId: userId,
      studentName: basePass?.studentName ?? 'Carlos Mejía',
      studentCareer: basePass?.studentCareer ?? 'Ing. de Sistemas · PUCE',
      planName: option.name,
      totalLunches: updatedRemaining > option.lunchesCount
          ? updatedRemaining
          : option.lunchesCount,
      remainingLunches: updatedRemaining,
      expiresAt: DateTime.now().add(Duration(days: option.validityDays)),
      status: 'ACTIVO',
      qrToken: newToken,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      avatarUrl: basePass?.avatarUrl,
    );

    await _cache.savePass(updatedPass);
    return updatedPass;
  }

  @override
  Future<void> submitHistoryClaim({
    required String recordId,
    required HistoryClaimType claimType,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _claimedRecords.add('$recordId:${claimType.name}');
  }
}

