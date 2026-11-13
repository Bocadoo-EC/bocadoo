import 'package:flutter/foundation.dart';

/// Modelo inmutable de un paquete de almuerzos disponible para el Comensal.
@immutable
class PlanOption {
  final String id;
  final String name;
  final int lunchesCount;
  final double price;
  final double savings;
  final int validityDays;
  final bool isPopular;

  const PlanOption({
    required this.id,
    required this.name,
    required this.lunchesCount,
    required this.price,
    this.savings = 0,
    this.validityDays = 30,
    this.isPopular = false,
  });

  /// Precio unitario por almuerzo dentro del paquete.
  double get unitPrice => lunchesCount > 0 ? price / lunchesCount : price;

  /// Etiqueta de ahorro en formato oficial (ej. `Ahorras $5`), o `null`.
  String? get savingsLabel {
    if (savings <= 0) return null;
    if (savings == savings.roundToDouble()) {
      return 'Ahorras \$${savings.toInt()}';
    }
    return 'Ahorras \$${savings.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  /// Formatea cualquier monto al estilo monetario Ecuador (`$55,00`, `$2,75`).
  static String formatEcuadorMoney(double amount) {
    return '\$${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

