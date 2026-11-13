import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_client.dart';
import '../network/api_config.dart';
import 'auth_models.dart';

/// Repositorio de autenticación contra `bck-bocadoo` con respaldo offline/demo.
class AuthRepository {
  static const String _userStorageKey = 'bocadoo_auth_user';
  static const String _roleStorageKey = 'bocadoo_auth_role';
  static const String _publicIdStorageKey = 'bocadoo_auth_public_id';

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final FlutterSecureStorage _storage;

  AuthUser? _memoryUser;

  AuthRepository({
    required this._dio,
    required this._tokenStorage,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  /// Restaura la sesión persistida si existe un `publicId` y rol válidos.
  Future<AuthUser?> restoreSession() async {
    try {
      final rawUser = await _storage.read(key: _userStorageKey);
      if (rawUser != null && rawUser.isNotEmpty) {
        final decoded = jsonDecode(rawUser) as Map<String, dynamic>;
        final user = AuthUser(
          publicId: (decoded['publicId'] as String?) ?? '',
          email: (decoded['email'] as String?) ?? '',
          fullName: (decoded['fullName'] as String?) ?? 'Usuario',
          role: AuthRole.fromApi(decoded['role'] as String?),
          restaurantId: decoded['restaurantId'] as String?,
          isOfflineDemo: (decoded['isOfflineDemo'] as bool?) ?? false,
        );
        if (user.publicId.isNotEmpty) {
          _memoryUser = user;
          return user;
        }
      }
    } catch (_) {
      return _memoryUser;
    }
    return _memoryUser;
  }

  /// Inicia sesión con correo y contraseña. Si [demoFallbackRole] se indica y
  /// no hay conexión con el servidor, activa una sesión demo offline.
  Future<AuthUser> login({
    required String email,
    required String password,
    AuthRole? demoFallbackRole,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.login,
        data: {'email': email.trim(), 'password': password},
        options: Options(extra: const {'skipAuth': true}),
      );

      final data = response.data ?? const {};
      return _persistAuthResponse(data);
    } on DioException catch (e) {
      final netErr = NetworkException.fromDioException(e);
      if (netErr.isOffline && demoFallbackRole != null) {
        return loginDemo(role: demoFallbackRole, email: email);
      }
      throw netErr;
    }
  }

  /// Registra un nuevo usuario (`customer` o `owner`).
  Future<AuthUser> register({
    required String fullName,
    required String email,
    required String password,
    required AuthRole role,
    String? restaurantName,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.register,
        data: {
          'fullName': fullName.trim(),
          'email': email.trim(),
          'password': password,
          'role': role.apiValue,
          if (restaurantName != null && restaurantName.trim().isNotEmpty)
            'restaurantName': restaurantName.trim(),
        },
        options: Options(extra: const {'skipAuth': true}),
      );

      final data = response.data ?? const {};
      return _persistAuthResponse(data);
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  /// Activa una sesión local de demostración/offline sin requerir servidor.
  Future<AuthUser> loginDemo({required AuthRole role, String? email}) async {
    final user = switch (role) {
      AuthRole.customer => AuthUser(
        publicId: '00000000-0000-4000-8000-000000000001',
        email: email?.trim().isNotEmpty == true
            ? email!.trim()
            : 'carlos.mejia@email.com',
        fullName: 'Carlos Mejía',
        role: AuthRole.customer,
        isOfflineDemo: true,
      ),
      AuthRole.owner => AuthUser(
        publicId: '00000000-0000-4000-8000-000000000002',
        email: email?.trim().isNotEmpty == true
            ? email!.trim()
            : 'maria@lacuchara.ec',
        fullName: 'María López',
        role: AuthRole.owner,
        restaurantId: 'rest-001',
        isOfflineDemo: true,
      ),
      AuthRole.cashier => AuthUser(
        publicId: '00000000-0000-4000-8000-000000000003',
        email: email?.trim().isNotEmpty == true
            ? email!.trim()
            : 'caja@lacuchara.ec',
        fullName: 'Caja Principal',
        role: AuthRole.cashier,
        restaurantId: 'rest-001',
        isOfflineDemo: true,
      ),
    };

    await _saveUser(user);
    return user;
  }

  /// Cierra la sesión actual, revocando el refresh token en el backend si hay red.
  Future<void> logout() async {
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _dio.post<void>(
          ApiConfig.logout,
          data: {'refresh_token': refreshToken},
          options: Options(extra: const {'skipAuth': true}),
        );
      }
    } catch (_) {
      // El cierre de sesión local siempre debe completarse aunque no haya red.
    } finally {
      _memoryUser = null;
      await _tokenStorage.clearTokens();
      try {
        await Future.wait([
          _storage.delete(key: _userStorageKey),
          _storage.delete(key: _roleStorageKey),
          _storage.delete(key: _publicIdStorageKey),
        ]);
      } catch (_) {}
    }
  }

  Future<AuthUser> _persistAuthResponse(Map<String, dynamic> data) async {
    final accessToken = data['access_token'] as String? ?? '';
    final refreshToken = data['refresh_token'] as String? ?? '';
    if (accessToken.isNotEmpty && refreshToken.isNotEmpty) {
      await _tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }

    final userMap = (data['user'] as Map<String, dynamic>?) ?? data;
    final user = AuthUser.fromJson(userMap);
    await _saveUser(user);
    return user;
  }

  Future<void> _saveUser(AuthUser user) async {
    _memoryUser = user;
    try {
      await Future.wait([
        _storage.write(key: _userStorageKey, value: jsonEncode(user.toJson())),
        _storage.write(key: _roleStorageKey, value: user.role.apiValue),
        _storage.write(key: _publicIdStorageKey, value: user.publicId),
      ]);
    } catch (_) {}
  }
}
