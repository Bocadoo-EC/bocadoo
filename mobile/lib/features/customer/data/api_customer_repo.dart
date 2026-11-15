import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/network/dio_client.dart';

/// Implementación real de [ICustomerRepository] conectada al backend REST de Bocadoo.
/// Nota de arquitectura: La API la define el backend (Chucho).
/// Esta clase se conectará cuando los endpoints del backend estén desplegados.
class ApiCustomerRepository implements ICustomerRepository {
  final DioClient client;

  ApiCustomerRepository({DioClient? dioClient})
      : client = dioClient ?? DioClient();

  @override
  Future<CustomerPass> getActivePass({String? userId}) async {
    throw UnimplementedError('API en desarrollo por el backend (Chucho). Usa MockCustomerRepository.');
  }

  @override
  Future<String> refreshQrToken(String passId) async {
    throw UnimplementedError('API en desarrollo por el backend (Chucho). Usa MockCustomerRepository.');
  }

  @override
  Future<List<Restaurant>> getRestaurants({String? query, String? category}) async {
    throw UnimplementedError('API en desarrollo por el backend (Chucho). Usa MockCustomerRepository.');
  }

  @override
  Future<Restaurant?> getRestaurantById(String id) async {
    throw UnimplementedError('API en desarrollo por el backend (Chucho). Usa MockCustomerRepository.');
  }

  @override
  Future<List<MenuItem>> getTodayMenu(String restaurantId) async {
    throw UnimplementedError('API en desarrollo por el backend (Chucho). Usa MockCustomerRepository.');
  }

  @override
  Future<List<ConsumptionRecord>> getConsumptionHistory(String passId) async {
    throw UnimplementedError('API en desarrollo por el backend (Chucho). Usa MockCustomerRepository.');
  }

  @override
  Future<CustomerPass?> getCachedPass() async {
    return null;
  }

  @override
  Future<void> saveCachedPass(CustomerPass pass) async {}

  Never _pending() => throw UnimplementedError(
      'API en desarrollo por el backend (Chucho). Usa MockCustomerRepository.');

  @override
  Future<List<CustomerPass>> getActivePasses({String? userId}) async => _pending();

  @override
  Future<StampCard?> getStampCard(String restaurantId) async => _pending();

  @override
  Future<bool> claimReward(String restaurantId) async => _pending();

  @override
  Future<ActiveTable?> getActiveTable() async => _pending();

  @override
  Future<ActiveOrder?> getActiveOrder() async => _pending();

  @override
  Future<List<ActivityItem>> getRecentActivity() async => _pending();

  @override
  Future<ActiveOrder> preorder({
    required String restaurantId,
    String? soupId,
    String? mainId,
    String? breakfastId,
    String? offerId,
    required bool takeaway,
  }) async =>
      _pending();

  @override
  Future<bool> cancelPreorder(String orderNumber) async => _pending();

  @override
  Future<List<PlanTemplate>> getPlanTemplates(String restaurantId) async => _pending();

  @override
  Future<PlanTemplate?> getPlanTemplateById(String planId) async => _pending();

  @override
  Future<bool> requestPlan(String planId) async => _pending();

  @override
  Future<bool> cancelPlanRequest(String planId) async => _pending();
}

