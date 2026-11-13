import 'package:dio/dio.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/contracts/repositories.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../domain/models/scan_status.dart';

/// Implementación remota de [IOwnerRepository] conectada a `bck-bocadoo` (`/v1`).
class RemoteOwnerRepository implements IOwnerRepository {
  final Dio _dio;

  RemoteOwnerRepository({required Dio dio}) : _dio = dio;

  @override
  Future<ScanResult> validateQrCode(String rawPayload) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.ownerValidateQr,
        data: {'payload': rawPayload},
      );
      return ScanResultMapper.fromApiJson(response.data ?? const {});
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<bool> confirmRedeem(String passId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.ownerRedeem,
        data: {'passId': passId},
      );
      return (response.data?['confirmed'] as bool?) ?? true;
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<bool> sellPlan({
    required String studentIdentifier,
    required int lunchCount,
    required String paymentMethod,
    required double amount,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.ownerSellPlan,
        data: {
          'studentIdentifier': studentIdentifier,
          'lunchCount': lunchCount,
          'paymentMethod': paymentMethod,
          'amount': amount,
        },
      );
      return (response.data?['success'] as bool?) ?? true;
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<TransactionSummary> getDailyClosingSummary(String restaurantId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConfig.ownerCashClosing,
        queryParameters: {'restaurantId': restaurantId},
      );
      final data = response.data ?? const {};
      final rawTx = data['transactions'];
      final transactions = rawTx is List
          ? rawTx
              .whereType<Map<String, dynamic>>()
              .map(_parseTransactionItem)
              .toList()
          : const <TransactionItem>[];

      final dateRaw = data['date'] as String?;
      return TransactionSummary(
        date: dateRaw != null
            ? (DateTime.tryParse(dateRaw) ?? DateTime.now())
            : DateTime.now(),
        lunchesRedeemedToday: (data['lunchesRedeemedToday'] ??
            data['lunches_redeemed_today'] ??
            0) as int,
        plansSoldToday:
            (data['plansSoldToday'] ?? data['plans_sold_today'] ?? 0) as int,
        totalIncomeToday: ((data['totalIncomeToday'] ??
                data['total_income_today'] as num?) ??
            0.0)
            .toDouble(),
        cashCounted:
            ((data['cashCounted'] ?? data['cash_counted'] as num?) ?? 0.0)
                .toDouble(),
        cashExpected:
            ((data['cashExpected'] ?? data['cash_expected'] as num?) ?? 0.0)
                .toDouble(),
        cashDifference:
            ((data['cashDifference'] ?? data['cash_difference'] as num?) ?? 0.0)
                .toDouble(),
        cashStatus:
            (data['cashStatus'] ?? data['cash_status'] ?? 'Cuadra') as String,
        transactions: transactions,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  @override
  Future<List<TransactionItem>> getTodayTransactions(String restaurantId) async {
    try {
      final summary = await getDailyClosingSummary(restaurantId);
      return summary.transactions;
    } on DioException catch (e) {
      throw NetworkException.fromDioException(e);
    }
  }

  static TransactionItem _parseTransactionItem(Map<String, dynamic> map) {
    final tsRaw = (map['timestamp'] ?? map['createdAt'] ?? '') as String;
    return TransactionItem(
      id: (map['id'] ?? '') as String,
      customerName:
          (map['customerName'] ?? map['customer_name'] ?? 'Comensal') as String,
      type: (map['type'] ?? 'Validado') as String,
      amount: ((map['amount'] as num?) ?? 0.0).toDouble(),
      paymentMethod:
          (map['paymentMethod'] ?? map['payment_method'] ?? 'Efectivo')
              as String,
      timestamp: DateTime.tryParse(tsRaw) ?? DateTime.now(),
    );
  }
}

