import 'package:flutter/foundation.dart';

enum OwnerPayMethod { efectivo, transferencia, deuna, tarjeta }

extension OwnerPayMethodX on OwnerPayMethod {
  String get label => switch (this) {
        OwnerPayMethod.efectivo => 'Efectivo',
        OwnerPayMethod.transferencia => 'Transferencia',
        OwnerPayMethod.deuna => 'Deuna',
        OwnerPayMethod.tarjeta => 'Tarjeta',
      };

  String get shortLabel => this == OwnerPayMethod.transferencia ? 'Transfer.' : label;
}

@immutable
class OwnerClient {
  const OwnerClient({required this.id, required this.name, this.phone = ''});

  final String id;
  final String name;
  final String phone;
}

@immutable
class OwnerPlanTemplate {
  const OwnerPlanTemplate({
    required this.id,
    required this.name,
    required this.lunches,
    required this.price,
    required this.validityDays,
  });

  final String id;
  final String name;
  final int lunches;
  final double price;
  final int validityDays;

  double get perLunch => lunches == 0 ? 0 : price / lunches;
}

enum PosCategory { almuerzos, desayunos, carta, extras, bebidas }

@immutable
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final PosCategory category;
}

@immutable
class PosSaleLine {
  const PosSaleLine({
    required this.name,
    required this.unitPrice,
    required this.qty,
    this.detail,
    this.isLunch = false,
  });

  final String name;
  final String? detail;
  final double unitPrice;
  final int qty;
  final bool isLunch;
}

enum OfferKind { flash, programada }

@immutable
class FlashOffer {
  const FlashOffer({
    required this.kind,
    required this.title,
    required this.discountPercent,
    required this.slots,
    required this.price,
    this.validUntil,
    this.days = const [],
    this.fromMinutes,
    this.toMinutes,
  });

  final OfferKind kind;
  final String title;
  final int discountPercent;
  final int slots;
  final double price;

  /// Hora límite de la oferta de hoy, `HH:mm`.
  final String? validUntil;

  /// Días de la semana de la promo programada (1 = lunes … 7 = domingo).
  final List<int> days;
  final int? fromMinutes;
  final int? toMinutes;
}
