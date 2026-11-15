import '../session/session_notifier.dart';
import 'app_mode.dart';

/// Capacidades de backend disponibles en la versión actual de la API.
///
/// En modo mock todas las capacidades están habilitadas para demostración offline.
/// En modo API cada bandera controla los ajustes mínimos permitidos (E3) hasta
/// que el backend entregue el endpoint correspondiente.
class ApiCapabilities {
  ApiCapabilities._();

  static bool get _api => !AppMode.useMock;

  // Mesas compartidas
  static bool get sharedTableModeChange => !_api;
  static bool get sharedTableNotifyKitchen => !_api;
  static bool get sharedTableDishChoice => !_api;
  static bool get ownerPendingTablesList => !_api;

  // Auth
  static bool get googleSignIn => !_api;
  static bool get forgotPassword => !_api;

  // Dueño
  static bool get cardPayment => !_api;
  static bool get flashScheduledOffer => !_api;
  static bool get weeklySummaryToggle => !_api;
  static bool get expiredLunchesReport => !_api;
  static bool get peakByWeekday => !_api;
  static bool get salesByMethodRange => !_api;
  static bool get orderUndoDelivery => !_api;

  // Comensal
  static bool get claimStampReward => !_api;
  static bool get cancelPlanRequest => !_api;

  /// Una cuenta con rol CAJERO en backend no puede subir al modo Dueño en el dispositivo.
  static bool get canSwitchToOwner =>
      AppMode.useMock || !sessionNotifier.isCashierAccount;
}
