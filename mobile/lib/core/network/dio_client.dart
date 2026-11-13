import 'package:dio/dio.dart';

import 'api_config.dart';

/// Cliente HTTP centralizado basado en Dio para Bocadoo
class DioClient {
  final Dio dio;

  DioClient({Dio? customDio})
      : dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: ApiConfig.connectTimeout,
                receiveTimeout: ApiConfig.receiveTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );
}

