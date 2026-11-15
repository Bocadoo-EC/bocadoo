import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacenamiento cifrado exclusivo para tokens de sesión y restaurante activo.
///
/// Nunca guarda credenciales de usuario ni datos personales en SharedPreferences.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';
  static const String _kAccessExpiresAt = 'access_expires_at';
  static const String _kActiveRestaurantId = 'active_restaurant_id';

  Future<String?> get access => _storage.read(key: _kAccessToken);
  Future<String?> get refresh => _storage.read(key: _kRefreshToken);
  Future<String?> get restaurantId =>
      _storage.read(key: _kActiveRestaurantId);

  Future<DateTime?> get accessExpiresAt async {
    final value = await _storage.read(key: _kAccessExpiresAt);
    return value == null ? null : DateTime.tryParse(value);
  }

  /// Reemplaza el par completo de tokens. Cada refresh token es de un solo uso.
  Future<void> saveTokens({
    required String access,
    required String refresh,
    required int expiresInSeconds,
  }) async {
    final expiresAt = DateTime.now().add(Duration(seconds: expiresInSeconds));
    await Future.wait([
      _storage.write(key: _kAccessToken, value: access),
      _storage.write(key: _kRefreshToken, value: refresh),
      _storage.write(key: _kAccessExpiresAt, value: expiresAt.toIso8601String()),
    ]);
  }

  Future<void> setRestaurant(String? id) => id == null
      ? _storage.delete(key: _kActiveRestaurantId)
      : _storage.write(key: _kActiveRestaurantId, value: id);

  Future<void> clear() => _storage.deleteAll();
}
