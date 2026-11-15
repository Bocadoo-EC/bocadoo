import '../config/app_mode.dart';

/// Configuración de red y tiempos de espera para la API de Bocadoo.
class ApiConfig {
  ApiConfig._();

  /// URL raíz sin sufijo `/v1` (cada endpoint declara `/v1/...` o `/health`).
  static const String baseUrl = AppMode.apiUrl;
  static const String v1 = '/v1';

  // Timeouts amplios considerando arranque en frío del servicio en Render.
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 45);
  static const Duration warmUpTimeout = Duration(seconds: 90);
}
