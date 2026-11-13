import 'models.dart';

/// Interfaz abstracta para operaciones del Comensal (Estudiante)
abstract class ICustomerRepository {
  /// Obtiene el pase activo del usuario comensal
  Future<CustomerPass> getActivePass({String? userId});

  /// Solicita refrescar o regenerar el token dinámico de QR
  Future<String> refreshQrToken(String passId);

  /// Obtiene el catálogo de restaurantes universitarios con filtros opcionales
  Future<List<Restaurant>> getRestaurants({String? query, String? category});

  /// Obtiene los detalles de un restaurante por su ID
  Future<Restaurant?> getRestaurantById(String id);

  /// Obtiene el menú del día de un restaurante
  Future<List<MenuItem>> getTodayMenu(String restaurantId);

  /// Obtiene el historial de consumos/almuerzos canjeados
  Future<List<ConsumptionRecord>> getConsumptionHistory(String passId);

  /// Obtiene el pase almacenado en caché local para soporte offline
  Future<CustomerPass?> getCachedPass();

  /// Guarda el pase en almacenamiento local para acceso offline
  Future<void> saveCachedPass(CustomerPass pass);
}

/// Interfaz abstracta para operaciones del Dueño de Restaurante
abstract class IOwnerRepository {
  /// Valida un código QR escaneado (o ingresado manualmente)
  Future<ScanResult> validateQrCode(String rawPayload);

  /// Confirma y descuenta el almuerzo correspondiente al pase
  Future<bool> confirmRedeem(String passId);

  /// Registra la venta de un nuevo plan de almuerzos en caja
  Future<bool> sellPlan({
    required String studentIdentifier,
    required int lunchCount,
    required String paymentMethod,
    required double amount,
  });

  /// Obtiene el resumen consolidado de cierre de caja del día
  Future<TransactionSummary> getDailyClosingSummary(String restaurantId);

  /// Obtiene la lista de transacciones del día para arqueo
  Future<List<TransactionItem>> getTodayTransactions(String restaurantId);
}

