import 'package:flutter/foundation.dart';

@immutable
class DailyMenuCourse {
  const DailyMenuCourse({
    required this.id,
    required this.name,
    required this.category,
    this.dishId,
    this.isSoldOut = false,
    this.price,
  });

  final String id;
  final String? dishId;
  final String name;
  final String category; // 'Sopa', 'Fuerte', 'Jugo', 'Postre', 'Desayuno'
  final bool isSoldOut;

  /// Solo para desayunos, que tienen precio propio.
  final double? price;

  DailyMenuCourse copyWith({
    String? id,
    String? dishId,
    String? name,
    String? category,
    bool? isSoldOut,
    double? price,
  }) {
    return DailyMenuCourse(
      id: id ?? this.id,
      dishId: dishId ?? this.dishId,
      name: name ?? this.name,
      category: category ?? this.category,
      isSoldOut: isSoldOut ?? this.isSoldOut,
      price: price ?? this.price,
    );
  }
}

@immutable
class DailyMenu {
  const DailyMenu({
    required this.restaurantId,
    required this.date,
    this.courses = const [],
    this.isPublished = false,
    this.isOpen = true,
  });

  final String restaurantId;
  final DateTime date;
  final List<DailyMenuCourse> courses;
  final bool isPublished;
  final bool isOpen;

  DailyMenu copyWith({
    String? restaurantId,
    DateTime? date,
    List<DailyMenuCourse>? courses,
    bool? isPublished,
    bool? isOpen,
  }) {
    return DailyMenu(
      restaurantId: restaurantId ?? this.restaurantId,
      date: date ?? this.date,
      courses: courses ?? this.courses,
      isPublished: isPublished ?? this.isPublished,
      isOpen: isOpen ?? this.isOpen,
    );
  }
}
