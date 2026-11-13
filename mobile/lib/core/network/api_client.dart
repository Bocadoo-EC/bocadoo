import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_config.dart';

/// Excepción de red unificada con soporte para respuestas RFC 9457
/// (`application/problem+json`).
class NetworkException implements Exception {
  final String message;
  final int? statusCode;
  final String? title;
  final String? detail;
  final String? requestId;
  final bool isOffline;

  const NetworkException({
    required this.message,
    this.statusCode,
    this.title,
    this.detail,
    this.requestId,
    this.isOffline = false,
  });

  factory NetworkException.fromDioException(DioException error) {
    if (error.error is NetworkException) {
      return error.error! as NetworkException;
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return const NetworkException(
        message: 'Sin conexión con el servidor. Revisa tu internet.',
        isOffline: true,
      );
    }

    final response = error.response;
    final status = response?.statusCode;
    final data = response?.data;

    if (data is Map<String, dynamic>) {
      final problemStatus = (data['status'] as num?)?.toInt() ?? status;
      final title = data['title'] as String?;
      final detail = data['detail'] as String?;
      final requestId =
          (data['requestId'] ?? data['request_id']) as String?;

      final resolvedMessage = _resolveSpanishMessage(
        statusCode: problemStatus,
        detail: detail,
        title: title,
      );

      return NetworkException(
        message: resolvedMessage,
        statusCode: problemStatus,
        title: title,
        detail: detail,
        requestId: requestId,
      );
    }

    return NetworkException(
      message: _resolveSpanishMessage(statusCode: status),
      statusCode: status,
    );
  }

  static String _resolveSpanishMessage({
    int? statusCode,
    String? detail,
    String? title,
  }) {
    if (detail != null && detail.trim().isNotEmpty) {
      return detail.trim();
    }
    if (title != null && title.trim().isNotEmpty) {
      return title.trim();
    }
    return switch (statusCode) {
      400 => 'Los datos enviados no son válidos.',
      401 => 'Tu sesión expiró. Inicia sesión de nuevo.',
      403 => 'No tienes permiso para realizar esta acción.',
      404 => 'No encontramos el recurso solicitado.',
      409 => 'La operación ya fue registrada anteriormente.',
      422 => 'Revisa los campos ingresados e intenta de nuevo.',
      429 => 'Demasiados intentos. Espera unos segundos.',
      final code when code != null && code >= 500 =>
        'El servidor tuvo un inconveniente. Intenta más tarde.',
      _ => 'No se pudo completar la solicitud. Intenta de nuevo.',
    };
  }

  @override
  String toString() => message;
}

/// Almacenamiento seguro de credenciales (`access_token` y `refresh_token`)
/// respaldado por [FlutterSecureStorage], con respaldo en memoria para tests.
class TokenStorage {
  static const String _accessTokenKey = 'bocadoo_access_token';
  static const String _refreshTokenKey = 'bocadoo_refresh_token';

  final FlutterSecureStorage _storage;
  String? _memoryAccessToken;
  String? _memoryRefreshToken;

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> getAccessToken() async {
    try {
      final value = await _storage.read(key: _accessTokenKey);
      _memoryAccessToken = value ?? _memoryAccessToken;
      return _memoryAccessToken;
    } catch (_) {
      return _memoryAccessToken;
    }
  }

  Future<String?> getRefreshToken() async {
    try {
      final value = await _storage.read(key: _refreshTokenKey);
      _memoryRefreshToken = value ?? _memoryRefreshToken;
      return _memoryRefreshToken;
    } catch (_) {
      return _memoryRefreshToken;
    }
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _memoryAccessToken = accessToken;
    _memoryRefreshToken = refreshToken;
    try {
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
      ]);
    } catch (_) {
      // Mantiene respaldo en memoria si el canal nativo no está disponible.
    }
  }

  Future<void> clearTokens() async {
    _memoryAccessToken = null;
    _memoryRefreshToken = null;
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
      ]);
    } catch (_) {}
  }
}

/// Interceptor en cola que adjunta el Bearer JWT y rota el `refresh_token`
/// una sola vez ante respuestas `401` (evitando reutilización de familia).
class AuthQueuedInterceptor extends QueuedInterceptor {
  final TokenStorage _tokenStorage;
  final Dio _retryDio;
  final Dio _refreshDio;
  final VoidCallback? onSessionExpired;

  AuthQueuedInterceptor({
    required TokenStorage tokenStorage,
    required Dio retryDio,
    Dio? refreshDio,
    this.onSessionExpired,
  })  : _tokenStorage = tokenStorage,
        _retryDio = retryDio,
        _refreshDio = refreshDio ??
            Dio(
              BaseOptions(
                baseUrl: retryDio.options.baseUrl,
                connectTimeout: ApiConfig.connectTimeout,
                receiveTimeout: ApiConfig.receiveTimeout,
                sendTimeout: ApiConfig.sendTimeout,
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json, application/problem+json',
                },
              ),
            );

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] == true) {
      return handler.next(options);
    }

    final accessToken = await _tokenStorage.getAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final options = err.requestOptions;

    if (statusCode != 401 ||
        options.extra['skipAuth'] == true ||
        options.extra['_retried'] == true) {
      return handler.next(err);
    }

    final failedAuth = options.headers['Authorization'] as String?;
    final latestAccess = await _tokenStorage.getAccessToken();

    // Si otra petición en cola ya rotó el token, reintenta sin volver a rotar.
    if (latestAccess != null &&
        latestAccess.isNotEmpty &&
        failedAuth != 'Bearer $latestAccess') {
      return _retryRequest(options, latestAccess, handler, err);
    }

    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _tokenStorage.clearTokens();
      onSessionExpired?.call();
      return handler.next(err);
    }

    try {
      final refreshResponse = await _refreshDio.post<Map<String, dynamic>>(
        ApiConfig.refresh,
        data: {'refresh_token': refreshToken},
      );

      final data = refreshResponse.data;
      final newAccess = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;

      if (newAccess == null ||
          newAccess.isEmpty ||
          newRefresh == null ||
          newRefresh.isEmpty) {
        await _tokenStorage.clearTokens();
        onSessionExpired?.call();
        return handler.next(err);
      }

      await _tokenStorage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );

      return _retryRequest(options, newAccess, handler, err);
    } catch (_) {
      await _tokenStorage.clearTokens();
      onSessionExpired?.call();
      return handler.next(err);
    }
  }

  Future<void> _retryRequest(
    RequestOptions options,
    String accessToken,
    ErrorInterceptorHandler handler,
    DioException originalError,
  ) async {
    try {
      options.headers['Authorization'] = 'Bearer $accessToken';
      options.extra['_retried'] = true;
      final response = await _retryDio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    } catch (_) {
      handler.next(originalError);
    }
  }
}

/// Inyecta `Idempotency-Key` (UUID v4) en peticiones `POST` de caja, cobros
/// y venta/solicitud de planes.
class IdempotencyInterceptor extends Interceptor {
  static final Random _secureRandom = Random.secure();

  static const List<String> _idempotentPathFragments = [
    '/cash',
    '/caja',
    '/redeem',
    '/charge',
    '/cobro',
    '/plan',
    '/plans',
    '/orders',
  ];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    final path = options.path.toLowerCase();

    final requiresIdempotency = method == 'POST' &&
        !path.startsWith('/auth') &&
        _idempotentPathFragments.any(path.contains);

    if (requiresIdempotency && !options.headers.containsKey('Idempotency-Key')) {
      options.headers['Idempotency-Key'] = generateUuidV4();
    }
    handler.next(options);
  }

  /// Genera un identificador UUID v4 criptográficamente aleatorio.
  static String generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}

/// Convierte errores [DioException] en errores con [NetworkException] RFC 9457.
class Rfc9457ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final mapped = NetworkException.fromDioException(err);
    handler.next(
      err.copyWith(
        error: mapped,
        message: mapped.message,
      ),
    );
  }
}

/// Cliente HTTP central de Bocadoo configurado con Dio, JWT ES256,
/// rotación en cola, idempotencia y parseo RFC 9457.
class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;

  ApiClient({
    TokenStorage? tokenStorage,
    Dio? customDio,
    VoidCallback? onSessionExpired,
  })  : tokenStorage = tokenStorage ?? TokenStorage(),
        dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: ApiConfig.connectTimeout,
                receiveTimeout: ApiConfig.receiveTimeout,
                sendTimeout: ApiConfig.sendTimeout,
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json, application/problem+json',
                },
              ),
            ) {
    dio.interceptors.addAll([
      IdempotencyInterceptor(),
      AuthQueuedInterceptor(
        tokenStorage: this.tokenStorage,
        retryDio: dio,
        onSessionExpired: onSessionExpired,
      ),
      Rfc9457ErrorInterceptor(),
    ]);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  return ApiClient(tokenStorage: storage);
});

final dioProvider = Provider<Dio>((ref) {
  return ref.watch(apiClientProvider).dio;
});

