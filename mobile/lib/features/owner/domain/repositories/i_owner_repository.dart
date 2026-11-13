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
