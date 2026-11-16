import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_notifier.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

typedef ApiErrorReporter = void Function({
  required String method,
  required String path,
  int? status,
  required String code,
  String? requestId,
});

/// Cliente HTTP centralizado para comunicarse con el backend de Bocadoo.
///
/// Cadena de interceptores en orden estricto:
/// 1. Auth (Bearer + single-flight refresh)
/// 2. Restaurante activo (`x-restaurant-id`)
/// 3. Reintentos (solo GET / `Idempotency-Key` en timeouts y 502/503/504)
/// 4. Traducción RFC 9457 (`ApiException`)
/// 5. Registro seguro en modo debug (sin cabeceras ni cuerpos de `/auth/*`)
class ApiClient {
  ApiClient({
    required TokenStore tokens,
    required void Function() onSessionExpired,
    ApiErrorReporter? onErrorReported,
  }) {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: const {'Accept': 'application/json'},
        contentType: 'application/json',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );

    final refreshDio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: const {'Accept': 'application/json'},
        contentType: 'application/json',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );

    dio.interceptors.addAll([
      _AuthInterceptor(dio, refreshDio, tokens, onSessionExpired),
      _RestaurantInterceptor(tokens),
      _RetryInterceptor(dio),
      _ProblemInterceptor(onErrorReported),
      if (kDebugMode) _SafeDebugLogInterceptor(),
    ]);
  }

  late final Dio dio;

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
    bool restaurant = false,
    bool auth = true,
    Duration? receiveTimeout,
  }) async {
    final response = await dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
      options: _options(
        restaurant: restaurant,
        auth: auth,
        receiveTimeout: receiveTimeout,
      ),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
    bool restaurant = false,
    bool auth = true,
  }) async {
    final response = await dio.get<List<dynamic>>(
      path,
      queryParameters: query,
      options: _options(restaurant: restaurant, auth: auth),
    );
    return response.data ?? <dynamic>[];
  }

  /// Ejecuta POST/PATCH/PUT/DELETE. Solo reintenta si [idempotencyKey] != null.
  Future<T?> send<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool restaurant = false,
    String? idempotencyKey,
    bool auth = true,
    Duration? receiveTimeout,
  }) async {
    final response = await dio.request<T>(
      path,
      data: body,
      queryParameters: query,
      options: _options(
        method: method,
        restaurant: restaurant,
        idempotencyKey: idempotencyKey,
        auth: auth,
        receiveTimeout: receiveTimeout,
      ),
    );
    return response.data;
  }

  Options _options({
    String? method,
    bool restaurant = false,
    String? idempotencyKey,
    bool auth = true,
    Duration? receiveTimeout,
  }) {
    return Options(
      method: method,
      receiveTimeout: receiveTimeout,
      headers: {
        'Idempotency-Key': ?idempotencyKey,
      },
      extra: {
        'restaurant': restaurant,
        'auth': auth,
        'retryable': idempotencyKey != null,
      },
    );
  }
}

/// Convierte cualquier [DioException] en [ApiException] normalizada.
Future<T> guard<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } on ApiException {
    rethrow;
  } on DioException catch (e) {
    if (e.error is ApiException) {
      throw e.error as ApiException;
    }
    throw ApiException.network();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ref.watch(sessionProvider).api;
});

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio, this._refreshDio, this._tokens, this._onExpired);

  final Dio _dio;
  final Dio _refreshDio;
  final TokenStore _tokens;
  final void Function() _onExpired;
  Future<bool>? _refreshing;

  Future<bool> _refresh() => _refreshing ??= _doRefresh();

  Future<bool> _doRefresh() async {
    try {
      final refreshToken = await _tokens.refresh;
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '${ApiConfig.v1}/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data;
      if (data == null) return false;
      await _tokens.saveTokens(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
        expiresInSeconds: (data['expiresIn'] as num).toInt(),
      );
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        await _tokens.clear();
        _onExpired();
      }
      // Ante fallos de red/timeout no se cierra la sesión.
      return false;
    } finally {
      _refreshing = null;
    }
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['auth'] == false) {
      return handler.next(options);
    }
    final expiresAt = await _tokens.accessExpiresAt;
    if (expiresAt != null &&
        expiresAt.difference(DateTime.now()) < const Duration(seconds: 60)) {
      await _refresh();
    }
    final accessToken = await _tokens.access;
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
    final options = err.requestOptions;
    if (err.response?.statusCode == 401 &&
        options.extra['auth'] != false &&
        options.extra['retried'] != true) {
      if (await _refresh()) {
        options.extra['retried'] = true;
        final newToken = await _tokens.access;
        if (newToken != null && newToken.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $newToken';
        }
        try {
          return handler.resolve(await _dio.fetch(options));
        } on DioException catch (retryErr) {
          return handler.next(retryErr);
        }
      }
    }
    handler.next(err);
  }
}

class _RestaurantInterceptor extends Interceptor {
  _RestaurantInterceptor(this._tokens);

  final TokenStore _tokens;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['restaurant'] == true) {
      final restaurantId = await _tokens.restaurantId;
      if (restaurantId == null || restaurantId.isEmpty) {
        return handler.reject(
          DioException(
            requestOptions: options,
            error: ApiException(code: 'SIN_RESTAURANTE'),
          ),
        );
      }
      options.headers['x-restaurant-id'] = restaurantId;
    }
    handler.next(options);
  }
}

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;

  static const List<Duration> _delays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  bool _canRetry(DioException err) {
    final method = err.requestOptions.method.toUpperCase();
    final isSafeMethod =
        method == 'GET' || err.requestOptions.extra['retryable'] == true;
    if (!isSafeMethod) return false;

    final status = err.response?.statusCode;
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        status == 502 ||
        status == 503 ||
        status == 504;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = (err.requestOptions.extra['retryCount'] as int?) ?? 0;
    if (attempt >= _delays.length || !_canRetry(err)) {
      return handler.next(err);
    }

    await Future<void>.delayed(_delays[attempt]);
    final options = err.requestOptions;
    options.extra['retryCount'] = attempt + 1;

    try {
      return handler.resolve(await _dio.fetch(options));
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    }
  }
}

class _ProblemInterceptor extends Interceptor {
  _ProblemInterceptor(this._onErrorReported);

  final ApiErrorReporter? _onErrorReported;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final ApiException apiError;
    if (err.error is ApiException) {
      apiError = err.error as ApiException;
    } else {
      final response = err.response;
      apiError = response != null
          ? ApiException.fromResponse(response)
          : ApiException.network();
    }
    _onErrorReported?.call(
      method: err.requestOptions.method,
      path: err.requestOptions.path,
      status: apiError.status,
      code: apiError.code,
      requestId: apiError.requestId,
    );
    if (err.error is ApiException) {
      return handler.next(err);
    }
    handler.next(err.copyWith(error: apiError));
  }
}

class _SafeDebugLogInterceptor extends Interceptor {
  bool _isSensitivePath(String path) => path.contains('/auth/');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[API] --> ${options.method} ${options.path}');
    if (!_isSensitivePath(options.path) && options.data != null) {
      debugPrint('[API] req body: ${options.data}');
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final path = response.requestOptions.path;
    debugPrint('[API] <-- ${response.statusCode} $path');
    if (!_isSensitivePath(path) && response.data != null) {
      debugPrint('[API] res body: ${response.data}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final path = err.requestOptions.path;
    final status = err.response?.statusCode;
    final apiErr = err.error is ApiException ? err.error as ApiException : null;
    debugPrint(
      '[API] ERR ${status ?? 'NET'} $path code=${apiErr?.code ?? err.type.name} '
      'requestId=${apiErr?.requestId ?? '-'}',
    );
    handler.next(err);
  }
}
