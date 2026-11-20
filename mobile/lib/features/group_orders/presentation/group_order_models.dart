import 'package:flutter/foundation.dart';

import '../../../core/contracts/models.dart';

/// Máquina de estados estricta del flujo de Pedido Grupal.
enum GroupOrderStatus {
  draft,
  collecting,
  confirmed,
  expired,
  cancelled,
}

/// Construye la URL modular de invitación para conectar el Deep Link final de backend.
String buildGroupInviteLink(String tableCode) {
  final clean = tableCode.trim();
  return 'https://bocadoo.app/mesa/$clean';
}

/// Mensaje prearmado exacto para compartir por WhatsApp.
String buildGroupWhatsAppMessage({
  required String hostName,
  required String restaurantName,
  required String tableCode,
}) {
  final inviteUrl = buildGroupInviteLink(tableCode);
  return '¡Hola qué tal! $hostName te invita a su mesa en $restaurantName, '
      'da clic y sé parte de un momento de almuerzo: $inviteUrl';
}

/// Fuente única de verdad del menú publicado del día para un restaurante.
@immutable
class DailyMenu {
  final String restaurantId;
  final String restaurantName;
  final List<String> soups;
  final List<String> mains;
  final List<String> drinks;
  final bool isPublished;
  final double takeawaySurcharge;
  final String schedule;

  const DailyMenu({
    required this.restaurantId,
    required this.restaurantName,
    required this.soups,
    required this.mains,
    required this.drinks,
    required this.isPublished,
    this.takeawaySurcharge = 0.25,
    this.schedule = '11:30 - 15:30',
  });

  bool get hasActiveDishes =>
      isPublished && (soups.isNotEmpty || mains.isNotEmpty);

  factory DailyMenu.fromRestaurant(
    Restaurant? restaurant, {
    MenuAvailabilityState? availabilityOverride,
  }) {
    if (restaurant == null) {
      return const DailyMenu(
        restaurantId: '',
        restaurantName: 'Restaurante',
        soups: [],
        mains: [],
        drinks: [],
        isPublished: false,
      );
    }

    final soups = restaurant.soups
        .where((m) => !m.isSoldOut)
        .map((m) => m.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final mains = restaurant.mains
        .where((m) => !m.isSoldOut)
        .map((m) => m.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final menuDrinks = restaurant.todayMenu
        .where(
          (m) =>
              !m.isSoldOut &&
              (m.category.toLowerCase().contains('bebida') ||
                  m.category.toLowerCase().contains('jugo')),
        )
        .map((m) => m.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final drinks = <String>[
      ...menuDrinks,
      if (menuDrinks.isEmpty && restaurant.juice.trim().isNotEmpty)
        restaurant.juice.trim(),
      if (menuDrinks.isEmpty && restaurant.juice.trim().isEmpty)
        ...const ['Jugo del día', 'Limonada', 'Agua'],
    ];

    final effectiveAvailability =
        availabilityOverride ?? restaurant.menuAvailabilityState;
    final hasItems = soups.isNotEmpty || mains.isNotEmpty;
    final published = effectiveAvailability != MenuAvailabilityState.sinPublicar &&
        effectiveAvailability != MenuAvailabilityState.agotadoTotal &&
        hasItems;

    return DailyMenu(
      restaurantId: restaurant.id,
      restaurantName: restaurant.name,
      soups: soups,
      mains: mains,
      drinks: drinks,
      isPublished: published,
      takeawaySurcharge: restaurant.takeawaySurcharge,
      schedule: restaurant.schedule,
    );
  }
}

/// Elección de menú + modalidad obligatoria de un participante.
@immutable
class GroupOrderDishSelection {
  final String? soup;
  final String? main;
  final String? drink;
  final bool takeaway;

  const GroupOrderDishSelection({
    this.soup,
    this.main,
    this.drink,
    this.takeaway = false,
  });

  String get modalityLabel => takeaway ? 'Para llevar' : 'Para comer aquí';

  String get summary {
    final parts = <String>[
      if (soup != null && soup!.trim().isNotEmpty) soup!.trim(),
      if (main != null && main!.trim().isNotEmpty) main!.trim(),
      if (drink != null && drink!.trim().isNotEmpty) drink!.trim(),
    ];
    final dishText = parts.isEmpty ? 'Almuerzo del día' : parts.join(' · ');
    return '$dishText · $modalityLabel';
  }

  GroupOrderDishSelection copyWith({
    String? soup,
    String? main,
    String? drink,
    bool? takeaway,
  }) {
    return GroupOrderDishSelection(
      soup: soup ?? this.soup,
      main: main ?? this.main,
      drink: drink ?? this.drink,
      takeaway: takeaway ?? this.takeaway,
    );
  }
}

/// Participante confirmado dentro de una mesa grupal.
@immutable
class GroupOrderParticipant {
  final String id;
  final String name;
  final bool isHost;
  final GroupOrderDishSelection selection;
  final bool paidByPlan;

  const GroupOrderParticipant({
    required this.id,
    required this.name,
    this.isHost = false,
    required this.selection,
    this.paidByPlan = true,
  });
}
