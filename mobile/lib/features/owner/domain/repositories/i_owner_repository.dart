import 'dart:typed_data';

import '../../../../core/contracts/models.dart';
import '../models/cash_models.dart';
import '../models/daily_menu.dart';
import '../models/extras_models.dart';
import '../models/menu_models.dart';
import '../models/metrics_models.dart';

/// Interfaz de dominio para operaciones de menú del Dueño.
/// Las operaciones de escaneo y venta viven en [IOwnerRepository] (core/contracts).
abstract class IOwnerMenuRepository {
  /// Devuelve el menú del día actual; `null` si aún no se ha publicado nada.
  Future<DailyMenu?> getTodayMenu(String restaurantId);

  /// Devuelve el menú de ayer como plantilla para "Repetir ayer".
  Future<DailyMenu?> getYesterdayMenu(String restaurantId);

  /// Publica el menú del día. Devuelve `true` si tuvo éxito.
  Future<bool> publishMenu(DailyMenu menu);

  /// Vuelve el menú publicado a borrador (deshacer de "Publicar menú").
  Future<bool> unpublishMenu(String restaurantId);

  /// Marca un solo plato del menú publicado como agotado o disponible, sin
  /// volver a publicar. Los demás platos siguen igual.
  Future<bool> setCourseSoldOut(String restaurantId, String courseName, {required bool soldOut});

  /// Abre o cierra el local. Devuelve `true` si tuvo éxito.
  Future<bool> setStoreOpen(String restaurantId, {required bool isOpen});
}

/// Catálogo de platos de la casa (O7 · Mis platos). Archivar oculta sin borrar.
abstract class IOwnerCatalogRepository {
  Future<List<CatalogDish>> getDishes(String restaurantId);

  Future<CatalogDish> addDish(
    String restaurantId, {
    required String name,
    required DishKind kind,
    double? price,
    String? description,
  });

  Future<void> setDishArchived(String restaurantId, String dishId, {required bool archived});
}

/// "Tus números" (O14).
abstract class IOwnerMetricsRepository {
  Future<OwnerMetrics> getMetrics(String restaurantId, {required MetricsPeriod period});

  Future<bool> setWeeklySummary(String restaurantId, {required bool enabled});
}

/// Operaciones de caja del Dueño (Fase 3): venta de planes, POS, ofertas,
/// aforo y cierre de turno. Los métodos que devuelven un id permiten deshacer.
abstract class IOwnerCashRepository {
  Future<double> getSingleLunchPrice(String restaurantId);

  Future<List<OwnerClient>> getClients(String restaurantId);

  /// O8 · Registra un cliente sin plan para poder venderle uno enseguida.
  Future<OwnerClient> addClient(
    String restaurantId, {
    required String name,
    required String phone,
    String email = '',
    String notes = '',
  });

  /// Todos los planes del local, activos e inactivos.
  Future<List<OwnerPlanTemplate>> getPlanTemplates(String restaurantId);

  /// Crea el plan si su id está vacío; si no, lo reemplaza.
  Future<OwnerPlanTemplate> savePlanTemplate(String restaurantId, OwnerPlanTemplate template);

  Future<bool> setPlanActive(String restaurantId, String templateId, {required bool active});

  /// Clientes distintos que compraron cada plan (id de plan → cantidad).
  Future<Map<String, int>> getPlanClientCounts(String restaurantId);

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

  /// Registra invitados extras (`extraGuests`) asociados al lote de canje en curso.
  Future<bool> commitExtraGuests({
    required String passId,
    required int extraGuests,
    String? batchRedemptionId,
  });

  /// Revierte un lote completo de canje (`1` titular + `invitadosExtras`).
  Future<bool> undoBatchRedemption(
    String batchRedemptionId, {
    String? fallbackPassId,
  });

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

  /// O10 · Pasa una cartulina física a un plan digital: el cliente conserva
  /// los almuerzos que le faltan ([template] menos [used]). No genera cobro.
  /// Devuelve un id para deshacer.
  Future<String?> registerPhysicalCard({
    required String restaurantId,
    String? clientId,
    String? newClientName,
    String? phone,
    required OwnerPlanTemplate template,
    required int used,
  });

  Future<bool> undoPhysicalCard(String cardId);
}

/// O12 · Preórdenes por cobrar (solo efectivo) y entregar.
abstract class IOwnerOrdersRepository {
  Future<List<OwnerOrder>> getActiveOrders(String restaurantId);

  /// Con plan prepagado: lee el QR del pedido y descuenta 1 almuerzo del plan.
  Future<bool> validateOrder(String restaurantId, String orderNumber);

  Future<bool> undoValidate(String restaurantId, String orderNumber);

  /// En efectivo, registra el cobro; con plan, no cobra nada.
  Future<bool> deliverOrder(String restaurantId, String orderNumber);

  Future<bool> undoDeliver(String restaurantId, String orderNumber);

  /// Disparador transaccional único (escáner QR, código de 6 chars o botón
  /// "Cobrar y entregar") con validación de pertenencia al local e idempotencia.
  Future<ScanResult> confirmAndRedeemOrder(
    String orderIdOrCode,
    String activeRestaurantId,
  );
}

/// O5 · Mesas con amigos por cobrar desde caja.
abstract class IOwnerTablesRepository {
  Future<List<PendingTable>> getPendingTables(String restaurantId);

  Future<TablePreview> previewTable(String restaurantId, String tableId);

  Future<TablePreview> setTableMode(String restaurantId, String tableId, TableMode mode);

  /// Descuenta planes, cobra sueltos y reparte sellos. Devuelve un id para deshacer.
  Future<String?> chargeTable(String restaurantId, String tableId);

  Future<bool> undoTableCharge(String chargeId);
}

/// O15 · Opiniones de los comensales.
abstract class IOwnerFeedbackRepository {
  Future<List<OwnerOpinion>> getOpinions(String restaurantId);

  Future<bool> replyOpinion(String restaurantId, String opinionId, OpinionReply reply);

  Future<bool> undoReply(String opinionId);
}

/// O16 · Datos y logo del local.
abstract class IOwnerSettingsRepository {
  Future<LocalInfo> getLocalInfo(String restaurantId);

  Future<bool> setLogo(String restaurantId, Uint8List? bytes);
}
