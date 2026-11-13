import 'package:flutter/foundation.dart';

/// Categorías fijas del menú del día.
const List<String> kMenuCategories = ['Sopa', 'Fuerte', 'Jugo', 'Postre'];

@immutable
class DailyMenuCourse {
  const DailyMenuCourse({
    required this.id,
    required this.name,
    required this.category,
    this.isSoldOut = false,
  });

  final String id;
  final String name;
  final String category; // 'Sopa', 'Fuerte', 'Jugo', 'Postre'
  final bool isSoldOut;

  DailyMenuCourse copyWith({
    String? id,
    String? name,
    String? category,
    bool? isSoldOut,
  }) {
    return DailyMenuCourse(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      isSoldOut: isSoldOut ?? this.isSoldOut,
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
