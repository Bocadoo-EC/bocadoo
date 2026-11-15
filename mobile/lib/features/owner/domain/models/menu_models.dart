import 'package:flutter/foundation.dart';

/// Tipo de plato del catálogo de la casa (O7 · Mis platos).
enum DishKind { sopa, segundo, bebida, postre, desayuno, carta }

extension DishKindX on DishKind {
  /// Categoría que usa [DailyMenuCourse] al publicar.
  String get courseCategory => switch (this) {
        DishKind.sopa => 'Sopa',
        DishKind.segundo => 'Fuerte',
        DishKind.bebida => 'Jugo',
        DishKind.postre => 'Postre',
        DishKind.desayuno => 'Desayuno',
        DishKind.carta => 'Carta',
      };

  String get label => switch (this) {
        DishKind.sopa => 'Sopa',
        DishKind.segundo => 'Segundo',
        DishKind.bebida => 'Bebida',
        DishKind.postre => 'Postre',
        DishKind.desayuno => 'Desayuno',
        DishKind.carta => 'A la carta',
      };

  bool get isLunchSection =>
      this == DishKind.sopa || this == DishKind.segundo || this == DishKind.bebida || this == DishKind.postre;
}

@immutable
class CatalogDish {
  const CatalogDish({
    required this.id,
    required this.name,
    required this.kind,
    this.price,
    this.description = '',
    this.archived = false,
    this.topPick = false,
    this.veggie = false,
  });

  final String id;
  final String name;
  final DishKind kind;
  final double? price;
  final String description;
  final bool archived;
  final bool topPick;
  final bool veggie;

  CatalogDish copyWith({bool? archived}) => CatalogDish(
        id: id,
        name: name,
        kind: kind,
        price: price,
        description: description,
        archived: archived ?? this.archived,
        topPick: topPick,
        veggie: veggie,
      );
}
