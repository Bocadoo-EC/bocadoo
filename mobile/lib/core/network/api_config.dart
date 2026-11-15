/// Configuración de endpoints y red para Bocadoo.
/// Nota de arquitectura: La API la define el backend (Chucho).
/// No inventar endpoints sin aprobación; usar datos mock hasta su integración.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'https://api.bocadoo.app/v1';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);

  // Endpoints estándar proyectados
  static const String login = '/auth/login';
  static const String customerPass = '/customer/pass';
  static const String customerRestaurants = '/customer/restaurants';
  static const String ownerValidateQr = '/owner/validate-qr';
  static const String ownerRedeem = '/owner/redeem';
  static const String ownerCashClosing = '/owner/cash-closing';
}

