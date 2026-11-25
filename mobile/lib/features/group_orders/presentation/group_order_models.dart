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

/// Construye el deep link nativo de invitación para abrir directo Bocadoo
/// (Login si falta sesión, o directo al pedido grupal si ya está logueado).
String buildGroupInviteLink(String tableIdOrInvite) {
  final clean = tableIdOrInvite.trim();
  if (clean.startsWith('bocadoo://')) return clean;
  return 'bocadoo://mesa/$clean';
}

/// Mensaje prearmado exacto para compartir por WhatsApp.
String buildGroupWhatsAppMessage({
  required String hostName,
  required String restaurantName,
  required String tableCode,
}) {
  final inviteUrl = buildGroupInviteLink(tableCode);
  return '¡Hola qué tal! $hostName te invita a su mesa en $restaurantName, '
      'da clic y únete al pedido en Bocadoo: $inviteUrl';
}

/// Opción fija "sin sopa" del selector de menú diario.
const String kNoSoupOption = 'Sin sopa';

/// Opción fija "sin bebida" del selector de menú diario.
const String kNoDrinkOption = 'Sin bebida';

/// Solo en ofertas flash del Dueño (un combo puede omitir segundo o postre).
const String kNoMainOption = 'Sin segundo';
const String kNoDessertOption = 'Sin postre';

/// Fuente única de verdad del menú publicado del día para un restaurante.
@immutable
class DailyMenu {
  final String restaurantId;
  final String restaurantName;
  final List<String> soups;
  final List<String> mains;
  final List<String> drinks;

  /// Postres publicados hoy. Si está vacío, la sección Postre no se muestra.
  final List<String> desserts;

  /// Etiqueta nutricional por plato fuerte (p. ej. `Fit`, `Vegetariano`).
  final Map<String, String> mainTags;
  final bool isPublished;
  final double takeawaySurcharge;
  final String schedule;

  const DailyMenu({
    required this.restaurantId,
    required this.restaurantName,
    required this.soups,
    required this.mains,
    required this.drinks,
    this.desserts = const [],
    this.mainTags = const {},
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

    final desserts = restaurant.todayMenu
        .where(
          (m) => !m.isSoldOut && m.category.toLowerCase().contains('postre'),
        )
        .map((m) => m.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final mainTags = <String, String>{
      for (final m in restaurant.mains.where((m) => !m.isSoldOut))
        if (m.name.trim().isNotEmpty)
          if (m.name.toLowerCase().contains('fit'))
            m.name.trim(): 'Fit'
          else if (m.isVeggie)
            m.name.trim(): 'Vegetariano',
    };

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
      desserts: desserts,
      mainTags: mainTags,
      isPublished: published,
      takeawaySurcharge: restaurant.takeawaySurcharge,
      schedule: restaurant.schedule,
    );
  }
}

/// Elección de menú + modalidad obligatoria de un participante.
///
/// `soup` y `drink` pueden valer [kNoSoupOption] / [kNoDrinkOption] cuando el
/// comensal decide no llevarlos; `null` significa "aún sin elegir".
@immutable
class GroupOrderDishSelection {
  final String? soup;
  final String? main;
  final String? drink;
  final String? dessert;
  final List<String> extras;
  final bool takeaway;

  /// `true` cuando el backend devolvió `seleccion: null` para otro invitado.
  /// Nunca se infieren ni muestran platos de otros comensales en ese caso.
  final bool selectionHidden;

  const GroupOrderDishSelection({
    this.soup,
    this.main,
    this.drink,
    this.dessert,
    this.extras = const [],
    this.takeaway = false,
    this.selectionHidden = false,
  });

  String get modalityLabel => takeaway ? 'Para llevar' : 'Para comer aquí';

  /// Sopa real elegida (nula si no eligió o escogió "Sin sopa").
  String? get cleanSoup => _clean(soup, kNoSoupOption);

  /// Bebida real elegida (nula si no eligió o escogió "Sin bebida").
  String? get cleanDrink => _clean(drink, kNoDrinkOption);

  static String? _clean(String? value, String skipLabel) {
    final v = value?.trim();
    if (v == null || v.isEmpty || v == skipLabel) return null;
    return v;
  }

  /// Sopa, segundo y bebida elegidos (postre es opcional y nunca bloquea).
  /// Las categorías que el restaurante no publicó no son exigibles.
  bool isCompleteFor(DailyMenu menu) {
    final soupOk = menu.soups.isEmpty || (soup?.trim().isNotEmpty ?? false);
    final mainOk = menu.mains.isEmpty || (main?.trim().isNotEmpty ?? false);
    final drinkOk = menu.drinks.isEmpty || (drink?.trim().isNotEmpty ?? false);
    return soupOk && mainOk && drinkOk;
  }

  /// Resuelve los IDs de platos del menú diario para `PUT /v1/mis/mesas/{id}/seleccion`.
  List<String> resolveLunchDishIds(Restaurant? restaurant) {
    if (restaurant == null || restaurant.todayMenu.isEmpty) return const [];
    final ids = <String>[];
    void matchByName(String? target) {
      final clean = target?.trim().toLowerCase() ?? '';
      if (clean.isEmpty) return;
      final hit = restaurant.todayMenu
          .where((m) => m.name.trim().toLowerCase() == clean && m.id.isNotEmpty)
          .firstOrNull;
      if (hit != null && !ids.contains(hit.id)) {
        ids.add(hit.id);
      }
    }

    matchByName(cleanSoup);
    matchByName(main);
    matchByName(cleanDrink);
    matchByName(dessert);
    return ids;
  }

  /// Resuelve los IDs y cantidades de extras para `PUT /v1/mis/mesas/{id}/seleccion`.
  List<({String dishId, int quantity})> resolveExtras(Restaurant? restaurant) {
    if (restaurant == null || restaurant.todayMenu.isEmpty || extras.isEmpty) {
      return const [];
    }
    final counts = <String, int>{};
    for (final raw in extras) {
      final clean = raw.trim().toLowerCase();
      if (clean.isEmpty) continue;
      final hit = restaurant.todayMenu
          .where((m) => m.name.trim().toLowerCase() == clean && m.id.isNotEmpty)
          .firstOrNull;
      if (hit != null) {
        counts[hit.id] = (counts[hit.id] ?? 0) + 1;
      }
    }
    return [
      for (final e in counts.entries) (dishId: e.key, quantity: e.value),
    ];
  }

  /// Descarta elecciones que ya no existen en el menú publicado.
  GroupOrderDishSelection sanitizedFor(DailyMenu menu) {
    return GroupOrderDishSelection(
      soup: (soup == kNoSoupOption || menu.soups.contains(soup)) ? soup : null,
      main: menu.mains.contains(main) ? main : null,
      drink:
          (drink == kNoDrinkOption || menu.drinks.contains(drink)) ? drink : null,
      dessert: menu.desserts.contains(dessert) ? dessert : null,
      extras: extras,
      takeaway: takeaway,
      selectionHidden: selectionHidden,
    );
  }

  /// Resumen limpio para anfitrión y cocina: omite "Sin sopa" / "Sin bebida".
  /// Cuando [selectionHidden] es `true`, solo muestra la modalidad sin inferir platos.
  String get summary {
    if (selectionHidden) return modalityLabel;
    final dessertText = dessert?.trim() ?? '';
    final parts = <String>[
      ?cleanSoup,
      if (main != null && main!.trim().isNotEmpty) main!.trim(),
      ?cleanDrink,
      if (dessertText.isNotEmpty) dessertText,
      if (extras.isNotEmpty) 'Extras: ${extras.join(', ')}',
    ];
    final dishText = parts.isEmpty ? 'Almuerzo del día' : parts.join(' · ');
    return '$dishText · $modalityLabel';
  }

  GroupOrderDishSelection copyWith({
    String? soup,
    String? main,
    String? drink,
    String? dessert,
    bool clearDessert = false,
    List<String>? extras,
    bool? takeaway,
    bool? selectionHidden,
  }) {
    return GroupOrderDishSelection(
      soup: soup ?? this.soup,
      main: main ?? this.main,
      drink: drink ?? this.drink,
      dessert: clearDessert ? null : (dessert ?? this.dessert),
      extras: extras ?? this.extras,
      takeaway: takeaway ?? this.takeaway,
      selectionHidden: selectionHidden ?? this.selectionHidden,
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
