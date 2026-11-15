import '../models/cash_models.dart';
import '../models/daily_menu.dart';

/// Interfaz de dominio para operaciones de menú del Dueño.
/// Las operaciones de escaneo y venta viven en [IOwnerRepository] (core/contracts).
abstract class IOwnerMenuRepository {
  /// Devuelve el menú del día actual; `null` si aún no se ha publicado nada.
  Future<DailyMenu?> getTodayMenu(String restaurantId);

  /// Devuelve el menú de ayer como plantilla para "Repetir ayer".
  Future<DailyMenu?> getYesterdayMenu(String restaurantId);

  /// Publica el menú del día. Devuelve `true` si tuvo éxito.
  Future<bool> publishMenu(DailyMenu menu);

  /// Marca el restaurante como agotado ("Se acabó"). Devuelve `true` si tuvo éxito.
  Future<bool> markSoldOut(String restaurantId);

  /// Abre o cierra el local. Devuelve `true` si tuvo éxito.
  Future<bool> setStoreOpen(String restaurantId, {required bool isOpen});
}

/// Operaciones de caja del Dueño (Fase 3): venta de planes, POS, ofertas,
/// aforo y cierre de turno. Los métodos que devuelven un id permiten deshacer.
abstract class IOwnerCashRepository {
  Future<double> getSingleLunchPrice(String restaurantId);

  Future<List<OwnerClient>> getClients(String restaurantId);

  Future<List<OwnerPlanTemplate>> getPlanTemplates(String restaurantId);

  /// Vende un plan a un cliente existente ([clientId]) o nuevo ([newClientName]).
  /// Devuelve el id de la venta, o `null` si falló.
  Future<String?> sellPlanTemplate({
    required String restaurantId,
    String? clientId,
    String? newClientName,
    required OwnerPlanTemplate template,
    required OwnerPayMethod method,
  });

  /// Revierte una venta (plan o consumo) dentro del búfer de deshacer.
  Future<bool> undoTransaction(String transactionId);

  /// Revierte el último almuerzo descontado del pase.
  Future<bool> undoRedeem(String passId);

  Future<List<CatalogItem>> getCatalog(String restaurantId);

  /// Registra un consumo del POS. Devuelve el id de la venta.
  Future<String?> registerPosSale({
    required String restaurantId,
    required String label,
    required List<PosSaleLine> lines,
    required double total,
    required OwnerPayMethod method,
  });

  Future<FlashOffer?> getActiveOffer(String restaurantId);

  Future<bool> publishOffer(String restaurantId, FlashOffer offer);

  Future<bool> cancelOffer(String restaurantId);

  Future<bool> setManualBusy(String restaurantId, {required bool busy});

  Future<int> getOrdersOnTheWayCount(String restaurantId);

  Future<bool> isShiftClosed(String restaurantId);

  Future<bool> closeShift(String restaurantId, {required double countedCash});

  Future<bool> reopenShift(String restaurantId);
}
