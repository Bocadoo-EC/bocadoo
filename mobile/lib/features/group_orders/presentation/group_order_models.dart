import 'package:flutter/foundation.dart';

/// Máquina de estados estricta del flujo de Pedido Grupal.
enum GroupOrderStatus {
  draft,
  collecting,
  confirmed,
  expired,
  cancelled,
}

/// Elección de menú del anfitrión durante la configuración del Paso 1.
@immutable
class GroupOrderDishSelection {
  final String? soup;
  final String? main;
  final String? drink;

  const GroupOrderDishSelection({
    this.soup,
    this.main,
    this.drink,
  });

  String get summary {
    final parts = <String>[
      if (soup != null && soup!.trim().isNotEmpty) soup!.trim(),
      if (main != null && main!.trim().isNotEmpty) main!.trim(),
      if (drink != null && drink!.trim().isNotEmpty) drink!.trim(),
    ];
    return parts.isEmpty ? 'Almuerzo del día' : parts.join(' · ');
  }

  GroupOrderDishSelection copyWith({
    String? soup,
    String? main,
    String? drink,
  }) {
    return GroupOrderDishSelection(
      soup: soup ?? this.soup,
      main: main ?? this.main,
      drink: drink ?? this.drink,
    );
  }
}
