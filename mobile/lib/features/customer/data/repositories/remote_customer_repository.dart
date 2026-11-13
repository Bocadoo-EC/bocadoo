import 'package:dio/dio.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/contracts/repositories.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../domain/models/plan_option.dart';
import '../../domain/repositories/i_plan_repository.dart';
import '../local_customer_cache.dart';

/// Implementación remota de [ICustomerRepository] e [IPlanRepository]
/// conectada a `bck-bocadoo` (`/v1`).
class RemoteCustomerRepository implements ICustomerRepository, IPlanRepository {
  final Dio _dio;
  final LocalCustomerCache _cache;

  RemoteCustomerRepository({required this._dio, LocalCustomerCache? cache})
    : _cache = cache ?? LocalCustomerCache();

  @override
  Future<CustomerPass> getActivePass({String? userId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConfig.customerPass,
        queryParameters: userId != null ? {'userId': userId} : null,
      );
      final pass = _parseCustomerPass(response.data ?? const {});
      await _cache.savePass(pass);
      return pass;
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<String> refreshQrToken(String passId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${ApiConfig.customerPass}/refresh-qr',
        data: {'passId': passId},
      );
      final token =
          (response.data?['qrToken'] ?? response.data?['qr_token'] ?? '')
              as String;
      final cached = await _cache.getPass();
      if (cached != null && cached.id == passId && token.isNotEmpty) {
        await _cache.savePass(cached.copyWith(qrToken: token));
      }
      return token;
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<List<Restaurant>> getRestaurants({
    String? query,
    String? category,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        ApiConfig.customerRestaurants,
        queryParameters: {
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          if (category != null && category.isNotEmpty && category != 'Todos')
            'category': category,
        },
      );
      final list = _extractList(response.data);
      return list.map(_parseRestaurant).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<Restaurant?> getRestaurantById(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${ApiConfig.customerRestaurants}/$id',
      );
      if (response.data == null) return null;
      return _parseRestaurant(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<List<MenuItem>> getTodayMenu(String restaurantId) async {
    try {
      final response = await _dio.get<dynamic>(
        '${ApiConfig.customerRestaurants}/$restaurantId/menu',
      );
      final list = _extractList(response.data);
      return list.map(_parseMenuItem).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<List<ConsumptionRecord>> getConsumptionHistory(String passId) async {
    try {
      final response = await _dio.get<dynamic>(
        '${ApiConfig.customerPass}/history',
        queryParameters: {'passId': passId},
      );
      final list = _extractList(response.data);
      return list.map(_parseConsumptionRecord).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<CustomerPass?> getCachedPass() => _cache.getPass();

  @override
  Future<void> saveCachedPass(CustomerPass pass) => _cache.savePass(pass);

  @override
  Future<List<PlanOption>> getPlanOptions({String? restaurantId}) async {
    try {
      final response = await _dio.get<dynamic>(
        ApiConfig.customerPlans,
        queryParameters: restaurantId != null
            ? {'restaurantId': restaurantId}
            : null,
      );
      final list = _extractList(response.data);
      return list.map(_parsePlanOption).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<CustomerPass> acquirePlan({
    required PlanOption option,
    required String restaurantId,
    required String restaurantName,
    CustomerPass? currentPass,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.customerPlans,
        data: {
          'planOptionId': option.id,
          'lunchesCount': option.lunchesCount,
          'restaurantId': restaurantId,
        },
      );
      final pass = _parseCustomerPass(response.data ?? const {});
      await _cache.savePass(pass);
      return pass;
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<void> submitHistoryClaim({
    required String recordId,
    required HistoryClaimType claimType,
  }) async {
    try {
      await _dio.post<void>(
        '${ApiConfig.customerPlans}/claims',
        data: {'recordId': recordId, 'claimType': claimType.name},
      );
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  static List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final items = data['items'] ?? data['data'] ?? data['results'];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  static CustomerPass _parseCustomerPass(Map<String, dynamic> map) {
    final normalized = {
      ...map,
      'id': map['id'] ?? map['passId'] ?? '',
      'userId': map['userId'] ?? map['user_id'] ?? '',
      'studentName': map['studentName'] ?? map['student_name'] ?? '',
      'studentCareer':
          map['studentCareer'] ?? map['student_career'] ?? 'Estudiante',
      'planName': map['planName'] ?? map['plan_name'] ?? 'Plan Bocadoo',
      'totalLunches': map['totalLunches'] ?? map['total_lunches'] ?? 0,
      'remainingLunches':
          map['remainingLunches'] ?? map['remaining_lunches'] ?? 0,
      'expiresAt': map['expiresAt'] ?? map['expires_at'] ?? '',
      'qrToken': map['qrToken'] ?? map['qr_token'] ?? '',
      'restaurantId': map['restaurantId'] ?? map['restaurant_id'] ?? '',
      'restaurantName': map['restaurantName'] ?? map['restaurant_name'] ?? '',
    };
    return CustomerPass.fromMap(normalized);
  }

  static Restaurant _parseRestaurant(Map<String, dynamic> map) {
    final menuRaw = map['todayMenu'] ?? map['today_menu'];
    final menu = menuRaw is List
        ? menuRaw.whereType<Map<String, dynamic>>().map(_parseMenuItem).toList()
        : const <MenuItem>[];

    final categoriesRaw = map['categories'];
    final categories = categoriesRaw is List
        ? categoriesRaw.map((e) => e.toString()).toList()
        : const ['Todos'];

    return Restaurant(
      id: (map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      description: (map['description'] ?? '') as String,
      address: (map['address'] ?? '') as String,
      zone: (map['zone'] ?? '') as String,
      rating: ((map['rating'] as num?) ?? 4.5).toDouble(),
      distanceKm: ((map['distanceKm'] ?? map['distance_km'] as num?) ?? 0.5)
          .toDouble(),
      imageUrl: (map['imageUrl'] ?? map['image_url'] ?? '') as String,
      logoUrl: (map['logoUrl'] ?? map['logo_url']) as String?,
      singleLunchPrice:
          ((map['singleLunchPrice'] ?? map['single_lunch_price'] as num?) ??
                  3.5)
              .toDouble(),
      planLunchPrice: (map['planLunchPrice'] ?? map['plan_lunch_price'] as num?)
          ?.toDouble(),
      occupancy: (map['occupancy'] ?? 'Libre') as String,
      isOpen: (map['isOpen'] ?? map['is_open'] ?? true) as bool,
      categories: categories,
      todayMenu: menu,
    );
  }

  static MenuItem _parseMenuItem(Map<String, dynamic> map) {
    return MenuItem(
      id: (map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      category: (map['category'] ?? 'Plato Fuerte') as String,
      price: (map['price'] as num?)?.toDouble(),
      isSoldOut: (map['isSoldOut'] ?? map['is_sold_out'] ?? false) as bool,
      imageUrl: (map['imageUrl'] ?? map['image_url']) as String?,
      isVeggie: (map['isVeggie'] ?? map['is_veggie'] ?? false) as bool,
    );
  }

  static ConsumptionRecord _parseConsumptionRecord(Map<String, dynamic> map) {
    final dateRaw = (map['date'] ?? map['redeemedAt'] ?? '') as String;
    return ConsumptionRecord(
      id: (map['id'] ?? '') as String,
      passId: (map['passId'] ?? map['pass_id'] ?? '') as String,
      restaurantName:
          (map['restaurantName'] ?? map['restaurant_name'] ?? '') as String,
      restaurantId:
          (map['restaurantId'] ?? map['restaurant_id'] ?? '') as String,
      date: DateTime.tryParse(dateRaw) ?? DateTime.now(),
      description: (map['description'] ?? 'Almuerzo diario') as String,
      lunchesUsed: (map['lunchesUsed'] ?? map['lunches_used'] ?? 1) as int,
      remainingAfter:
          (map['remainingAfter'] ?? map['remaining_after'] ?? 0) as int,
      status: (map['status'] ?? 'Validado') as String,
    );
  }

  static PlanOption _parsePlanOption(Map<String, dynamic> map) {
    return PlanOption(
      id: (map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      lunchesCount: (map['lunchesCount'] ?? map['lunches_count'] ?? 5) as int,
      price: ((map['price'] as num?) ?? 15.0).toDouble(),
      savings: ((map['savings'] as num?) ?? 0.0).toDouble(),
      validityDays: (map['validityDays'] ?? map['validity_days'] ?? 30) as int,
      isPopular: (map['isPopular'] ?? map['is_popular'] ?? false) as bool,
    );
  }
}
