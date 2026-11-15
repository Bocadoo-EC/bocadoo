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

  /// Planes activos del comensal, uno por local
  Future<List<CustomerPass>> getActivePasses({String? userId});

  /// Tarjeta de sellos del comensal en un local (null si el local no tiene)
  Future<StampCard?> getStampCard(String restaurantId);

  /// Reclama un premio de la tarjeta de sellos
  Future<bool> claimReward(String restaurantId);

  /// Mesa con amigos activa del comensal
  Future<ActiveTable?> getActiveTable();

  /// Preorden activa del comensal
  Future<ActiveOrder?> getActiveOrder();

  /// Últimos movimientos del comensal
  Future<List<ActivityItem>> getRecentActivity();

  /// Crea una preorden de almuerzo o desayuno y devuelve el número de orden
  Future<ActiveOrder> preorder({
    required String restaurantId,
    String? soupId,
    String? mainId,
    String? breakfastId,
    String? offerId,
    required bool takeaway,
  });

  /// Cancela una preorden recién creada (deshacer)
  Future<bool> cancelPreorder(String orderNumber);

  /// El comensal ya vio que su pedido fue entregado: deja de mostrarse.
  Future<bool> acknowledgeOrder(String orderNumber);

  /// Planes que publica un local
  Future<List<PlanTemplate>> getPlanTemplates(String restaurantId);

  /// Detalle de un plan por su ID
  Future<PlanTemplate?> getPlanTemplateById(String planId);

  /// Solicita un plan; se paga en caja al activarlo
  Future<bool> requestPlan(String planId);

  /// Cancela una solicitud de plan recién enviada (deshacer)
  Future<bool> cancelPlanRequest(String planId);

  /// Crea la mesa con amigos del local para esa hora, o recupera la que ya existe (C9)
  Future<SharedTable> openSharedTable({required String restaurantId, required String time});

  /// Mesa por su ID, para la invitación (C7). `null` si ya expiró
  Future<SharedTable?> getSharedTable(String tableId);

  /// Cambia el modo de cobro de la mesa
  Future<SharedTable> setTableMode(String tableId, TableMode mode);

  /// Avisa a cocina que la mesa va en camino
  Future<SharedTable> notifyKitchen(String tableId);

  /// Un invitado se une a la mesa con su elección
  Future<SharedTable> joinTable(
    String tableId, {
    required String name,
    required String soup,
    required String main,
    required bool takeaway,
  });

  /// Perfil del comensal (C6)
  Future<CustomerProfile> getProfile();

  /// Almuerzo validado pendiente de calificar, si hay uno (C10)
  Future<PendingFeedback?> getPendingFeedback();

  /// Envía la calificación de un almuerzo validado
  Future<bool> submitFeedback(String redemptionId, {required String tag, String? note});

  /// Descarta la tarjeta de calificación de un almuerzo
  Future<bool> dismissFeedback(String redemptionId);
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

