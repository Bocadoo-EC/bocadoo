/// Configuración de endpoints y red para Bocadoo (`bck-bocadoo`).
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'BOCADOO_API_URL',
    defaultValue: 'https://bck-bocadoo.onrender.com/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
  static const Duration sendTimeout = Duration(seconds: 10);

  // Autenticación
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';

  // Comensal
  static const String customerPass = '/customer/pass';
  static const String customerPlans = '/customer/plans';
  static const String customerRestaurants = '/customer/restaurants';

  // Dueño / Caja
  static const String ownerValidateQr = '/owner/validate-qr';
  static const String ownerRedeem = '/owner/redeem';
  static const String ownerSellPlan = '/owner/plans/sell';
  static const String ownerQuickCharge = '/owner/cash/charge';
  static const String ownerCashClosing = '/owner/cash-closing';
}
