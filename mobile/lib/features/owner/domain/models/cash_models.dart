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
  const OwnerClient({
    required this.id,
    required this.name,
    this.phone = '',
    this.habitualPlan,
    this.email = '',
    this.notes = '',
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final String notes;

  /// Nombre del último plan que compró, si tiene alguno.
  final String? habitualPlan;
}

enum PlanKind { semanal, quincenal, mensual, libre }

enum PlanCoverage { almuerzo, desayuno, mixto }

extension PlanCoverageX on PlanCoverage {
  String get label => switch (this) {
        PlanCoverage.almuerzo => 'Almuerzo',
        PlanCoverage.desayuno => 'Desayuno',
        PlanCoverage.mixto => 'Mixto',
      };

  /// Unidad en plural: "almuerzos", "desayunos" o "combos".
  String get unit => switch (this) {
        PlanCoverage.almuerzo => 'almuerzos',
        PlanCoverage.desayuno => 'desayunos',
        PlanCoverage.mixto => 'combos',
      };

  List<String> get includeOptions => switch (this) {
        PlanCoverage.almuerzo => const ['Sopa', 'Segundo', 'Jugo', 'Postre'],
        PlanCoverage.desayuno => const ['Plato principal', 'Bebida', 'Fruta'],
        PlanCoverage.mixto => const ['Desayuno', 'Sopa', 'Segundo', 'Jugo'],
      };

  List<String> get defaultIncludes => switch (this) {
        PlanCoverage.almuerzo => const ['Sopa', 'Segundo', 'Jugo'],
        PlanCoverage.desayuno => const ['Plato principal', 'Bebida'],
        PlanCoverage.mixto => const ['Desayuno', 'Sopa', 'Segundo'],
      };
}

@immutable
class OwnerPlanTemplate {
  const OwnerPlanTemplate({
    required this.id,
    required this.name,
    required this.lunches,
    required this.price,
    required this.validityDays,
    this.kind = PlanKind.mensual,
    this.coverage = PlanCoverage.almuerzo,
    this.includes = const ['Sopa', 'Segundo', 'Jugo'],
    this.days = const [1, 2, 3, 4, 5],
    this.quota = 40,
    this.visible = true,
    this.active = true,
  });

  final String id;
  final String name;
  final int lunches;
  final double price;
  final int validityDays;
  final PlanKind kind;
  final PlanCoverage coverage;
  final List<String> includes;

  /// Días de consumo (1 = lunes … 7 = domingo).
  final List<int> days;
  final int quota;
  final bool visible;
  final bool active;

  double get perLunch => lunches == 0 ? 0 : price / lunches;

  OwnerPlanTemplate copyWith({
    String? id,
    String? name,
    int? lunches,
    double? price,
    int? validityDays,
    PlanKind? kind,
    PlanCoverage? coverage,
    List<String>? includes,
    List<int>? days,
    int? quota,
    bool? visible,
    bool? active,
  }) {
    return OwnerPlanTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      lunches: lunches ?? this.lunches,
      price: price ?? this.price,
      validityDays: validityDays ?? this.validityDays,
      kind: kind ?? this.kind,
      coverage: coverage ?? this.coverage,
      includes: includes ?? this.includes,
      days: days ?? this.days,
      quota: quota ?? this.quota,
      visible: visible ?? this.visible,
      active: active ?? this.active,
    );
  }
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

/// Tipo de movimiento devuelto por `GET /v1/caja/movimientos`.
enum CajaMovementType { venta, pedido, canjeDirecto }

/// Movimiento unificado de Caja (`VENTA`, `PEDIDO`, `CANJE_DIRECTO`).
@immutable
class CajaMovement {
  const CajaMovement({
    required this.id,
    required this.tipo,
    required this.timestamp,
    required this.title,
    this.subtitle,
    this.montoCentavos,
    this.valorPedidoCentavos,
    this.pagoEstado,
    this.metodoPago,
    this.revertido = false,
    this.platoNombre,
    this.customerName,
    this.planNombre,
  });

  final String id;
  final CajaMovementType tipo;
  final DateTime? timestamp;
  final String title;
  final String? subtitle;

  /// Importe real cobrado en caja (`VENTA`).
  final int? montoCentavos;

  /// Valor referencial del pedido (`PEDIDO`); nunca suma al total recaudado.
  final int? valorPedidoCentavos;

  final String? pagoEstado;
  final String? metodoPago;
  final bool revertido;
  final String? platoNombre;
  final String? customerName;
  final String? planNombre;

  /// Regla financiera estricta: solo `VENTA` con `pagoEstado == CONFIRMADO` y `!revertido`
  /// representa dinero recaudado en caja.
  int get cashCollectedCents =>
      (tipo == CajaMovementType.venta &&
              pagoEstado?.toUpperCase() == 'CONFIRMADO' &&
              !revertido)
          ? (montoCentavos ?? 0)
          : 0;
}

/// Página cursorizada de `GET /v1/caja/movimientos?fecha=YYYY-MM-DD`.
@immutable
class CajaMovementsPage {
  const CajaMovementsPage({
    required this.fecha,
    required this.items,
    this.nextCursor,
  });

  final String fecha;
  final List<CajaMovement> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
