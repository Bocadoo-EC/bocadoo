import 'package:flutter/foundation.dart';

enum MetricsPeriod { semana, mes }

@immutable
class DishRank {
  const DishRank({required this.name, required this.orders, this.rating});

  final String name;
  final int orders;
  final double? rating;
}

@immutable
class ClientFollowUp {
  const ClientFollowUp({
    required this.name,
    required this.phone,
    required this.days,
    this.lunchesLeft = 0,
  });

  final String name;
  final String phone;

  /// Días hasta que vence (por renovar) o días sin venir (no han vuelto).
  final int days;
  final int lunchesLeft;
}

/// "Tus números" (O14). Un solo objeto por periodo para pintar las tres pestañas.
@immutable
class OwnerMetrics {
  const OwnerMetrics({
    required this.servedToday,
    required this.servedLastWeekSameTime,
    required this.pendingLunches,
    required this.clientsWithPlan,
    required this.dishes,
    required this.expiredLunches,
    required this.expiredPlans,
    required this.expiredValue,
    required this.salesCash,
    required this.salesTransfer,
    required this.plansSold,
    required this.renewals,
    required this.absent,
    required this.peakGrid,
    required this.peakDays,
    required this.peakHours,
    required this.weeklySummaryEnabled,
    required this.weekServed,
    required this.weekCollected,
  });

  final int servedToday;
  final int? servedLastWeekSameTime;
  final int pendingLunches;
  final int clientsWithPlan;
  final List<DishRank> dishes;
  final int expiredLunches;
  final int expiredPlans;
  final double expiredValue;
  final double salesCash;
  final double salesTransfer;
  final int plansSold;
  final List<ClientFollowUp> renewals;
  final List<ClientFollowUp> absent;

  /// Almuerzos por día (filas, [peakDays]) y hora (columnas, [peakHours]).
  final List<List<int>> peakGrid;
  final List<String> peakDays;
  final List<String> peakHours;

  final bool weeklySummaryEnabled;
  final int weekServed;
  final double weekCollected;
}
