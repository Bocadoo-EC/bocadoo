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
    this.activeLunches = 0,
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

  /// Almuerzos vigentes disponibles del comensal en este local.
  final int activeLunches;
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
    this.isDessert = false,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final PosCategory category;
  final bool isDessert;
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
    this.id,
    this.dishId,
    this.originalPrice,
    this.slotsTotal,
    this.validUntil,
    this.endsAt,
    this.paused = false,
    this.days = const [],
    this.fromMinutes,
    this.toMinutes,
  });

  /// `null` hasta que el repositorio la publica.
  final String? id;
  final OfferKind kind;

  /// Nombre exacto del plato (oferta flash: un único plato por oferta).
  final String title;

  /// Plato del catálogo (`platoId` del backend) cuando sale del menú de hoy.
  final String? dishId;
  final int discountPercent;

  /// Cupos restantes.
  final int slots;
  final double price;

  /// Precio normal del plato (para tachar en la tarjeta del comensal).
  final double? originalPrice;

  /// Cupos con los que se publicó; `null` si el origen no lo informa.
  final int? slotsTotal;

  /// Hora límite de la oferta de hoy, `HH:mm`.
  final String? validUntil;

  /// Instante exacto en que vence; alimenta el cronómetro del gestor.
  final DateTime? endsAt;
  final bool paused;

  int get totalSlots => slotsTotal ?? slots;

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
    this.cleanDishSummary,
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

  /// Etiqueta limpia para "Cobros de hoy" (`Almuerzo`, `Solo Sopa`,
  /// `Solo Segundo`, `Plato Fuerte`, con `+ Bebida` / `+ Postre` si aplica).
  final String? cleanDishSummary;
  final String? customerName;
  final String? planNombre;

  CajaMovement copyWith({
    DateTime? timestamp,
    String? cleanDishSummary,
    String? subtitle,
  }) {
    return CajaMovement(
      id: id,
      tipo: tipo,
      timestamp: timestamp ?? this.timestamp,
      title: title,
      subtitle: subtitle ?? this.subtitle,
      montoCentavos: montoCentavos,
      valorPedidoCentavos: valorPedidoCentavos,
      pagoEstado: pagoEstado,
      metodoPago: metodoPago,
      revertido: revertido,
      platoNombre: platoNombre,
      cleanDishSummary: cleanDishSummary ?? this.cleanDishSummary,
      customerName: customerName,
      planNombre: planNombre,
    );
  }

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

/// Item unificado devuelto por `GET /v1/pagos/pendientes` (PR #53: `PLAN`, `POS`, `CUENTA`).
@immutable
class PendingPaymentItem {
  const PendingPaymentItem({
    required this.origen,
    required this.pagoId,
    required this.origenId,
    required this.montoCentavos,
    required this.metodo,
    this.fecha,
    this.comprobanteUrl,
    this.creadoEn,
    this.clienteNombre,
    this.referencia = '',
  });

  /// `PLAN`, `POS` o `CUENTA`.
  final String origen;
  final String pagoId;
  final String origenId;
  final int montoCentavos;
  final String metodo;
  final String? fecha;
  final String? comprobanteUrl;
  final DateTime? creadoEn;
  final String? clienteNombre;
  final String referencia;

  bool get isPlan => origen.toUpperCase() == 'PLAN';

  String get displayName {
    final c = clienteNombre?.trim() ?? '';
    if (c.isNotEmpty) return c;
    final r = referencia.trim();
    if (r.isNotEmpty) return r;
    return 'Cliente';
  }
}

/// Resumen liviano de una cuenta devuelta por `GET /v1/caja/cuentas`.
@immutable
class CajaCuentaItem {
  const CajaCuentaItem({
    required this.id,
    required this.origen,
    required this.estado,
    this.pagadorNombre,
    this.saldoCentavos = 0,
    this.pagadoCentavos = 0,
    this.cleanDishSummary,
    this.pedidoId,
    this.creadaEn,
    this.cobradaEn,
  });

  final String id;
  final String origen;
  final String estado;
  final String? pagadorNombre;
  final int saldoCentavos;
  final int pagadoCentavos;
  final String? cleanDishSummary;
  final String? pedidoId;
  final DateTime? creadaEn;
  final DateTime? cobradaEn;
}

/// Formateador puro de etiquetas limpias para "Cobros de hoy":
/// `Almuerzo`, `Solo Sopa`, `Solo Segundo`, `Plato Fuerte`, con `+ Bebida`
/// y/o `+ Postre` únicamente cuando el comensal los incluyó.
class CajaDishSummaryBuilder {
  CajaDishSummaryBuilder._();

  static String? fromPayload({
    Map<dynamic, dynamic>? almuerzo,
    List<dynamic>? cartaItems,
    List<dynamic>? extras,
    Map<dynamic, dynamic>? cotizacion,
    List<dynamic>? ventaItems,
    String? platoNombre,
    Map<String, String>? dishSectionByLowerName,
    bool fallbackToAlmuerzoIfNamed = false,
  }) {
    var hasSopa = false;
    var hasSegundo = false;
    var hasCartaFuerte = false;
    var hasBebida = false;
    var hasPostre = false;
    var almuerzoCourseCountKnown = false;

    void applyTokenByCatalog(String name) {
      final sec = dishSectionByLowerName?[name.trim().toLowerCase()];
      if (sec == null) return;
      switch (sec) {
        case 'SOPA':
          hasSopa = true;
        case 'FUERTE':
        case 'SEGUNDO':
        case 'PLATO_FUERTE':
          hasSegundo = true;
        case 'JUGO':
        case 'BEBIDA':
          hasBebida = true;
        case 'POSTRE':
          hasPostre = true;
        case 'CARTA':
        case 'A_LA_CARTA':
          hasCartaFuerte = true;
      }
    }

    void classifySectionCategory(
      String? seccionRaw,
      String? categoriaRaw, {
      String? nombre,
      bool fromAlmuerzo = false,
      bool fromCarta = false,
    }) {
      final sec = (seccionRaw ?? '').trim().toUpperCase();
      final cat = (categoriaRaw ?? '').trim().toUpperCase();

      if (sec == 'JUGO' || sec == 'BEBIDA' || cat == 'BEBIDA') {
        hasBebida = true;
        return;
      }
      if (sec == 'POSTRE' || cat == 'POSTRE') {
        hasPostre = true;
        return;
      }
      if (fromCarta && (cat.isEmpty || cat == 'A_LA_CARTA')) {
        hasCartaFuerte = true;
        return;
      }
      if (!fromAlmuerzo && cat == 'A_LA_CARTA') {
        hasCartaFuerte = true;
        return;
      }
      if (sec == 'SOPA') {
        hasSopa = true;
        return;
      }
      if (sec == 'FUERTE' || sec == 'SEGUNDO' || sec == 'PLATO_FUERTE') {
        hasSegundo = true;
        return;
      }
      if (nombre != null && nombre.trim().isNotEmpty) {
        applyTokenByCatalog(nombre);
      }
    }

    if (almuerzo != null) {
      final rawPlatos = almuerzo['platos'];
      if (rawPlatos is List && rawPlatos.isNotEmpty) {
        for (final p in rawPlatos) {
          if (p is Map) {
            final sec = p['seccion']?.toString();
            final cat = p['categoria']?.toString();
            final nom = p['nombre']?.toString();
            if ((sec != null && sec.trim().isNotEmpty) ||
                (nom != null && nom.trim().isNotEmpty)) {
              almuerzoCourseCountKnown = true;
            }
            classifySectionCategory(
              sec,
              cat,
              nombre: nom,
              fromAlmuerzo: true,
            );
          } else if (p is String && p.trim().isNotEmpty) {
            almuerzoCourseCountKnown = true;
            applyTokenByCatalog(p);
          }
        }
      }
      final sRaw = almuerzo['sopa']?.toString().trim() ?? '';
      final mRaw =
          (almuerzo['segundo'] ?? almuerzo['fuerte'])?.toString().trim() ?? '';
      final bRaw =
          (almuerzo['jugo'] ?? almuerzo['bebida'])?.toString().trim() ?? '';
      final dRaw = almuerzo['postre']?.toString().trim() ?? '';
      if (sRaw.isNotEmpty) {
        hasSopa = true;
        almuerzoCourseCountKnown = true;
      }
      if (mRaw.isNotEmpty) {
        hasSegundo = true;
        almuerzoCourseCountKnown = true;
      }
      if (bRaw.isNotEmpty) hasBebida = true;
      if (dRaw.isNotEmpty) hasPostre = true;
    }

    if (cartaItems != null) {
      for (final c in cartaItems.whereType<Map>()) {
        final plato = c['plato'] is Map ? c['plato'] as Map : null;
        final sec = (c['seccion'] ?? plato?['seccion'])?.toString();
        final cat = (c['categoria'] ?? plato?['categoria'])?.toString();
        final nom = (c['nombre'] ?? plato?['nombre'])?.toString();
        classifySectionCategory(
          sec,
          cat,
          nombre: nom,
          fromCarta: true,
        );
      }
    }

    if (extras != null) {
      for (final ex in extras.whereType<Map>()) {
        final plato = ex['plato'] is Map ? ex['plato'] as Map : null;
        final sec = (ex['seccion'] ?? plato?['seccion'])?.toString();
        final cat = (ex['categoria'] ?? plato?['categoria'])?.toString();
        final nom = (ex['nombre'] ?? plato?['nombre'])?.toString();
        classifySectionCategory(sec, cat, nombre: nom);
      }
    }

    if (cotizacion != null && cotizacion['lineas'] is List) {
      for (final l in (cotizacion['lineas'] as List).whereType<Map>()) {
        final tipo = (l['tipo'] ?? '').toString().trim().toUpperCase();
        final ref = (l['ref'] ?? '').toString().trim().toLowerCase();
        final sec = (l['seccion'] ?? '').toString().trim().toUpperCase();
        if (tipo == 'RECARGO' || ref.startsWith('recargo')) continue;

        if (tipo == 'A_LA_CARTA') {
          hasCartaFuerte = true;
        } else if (tipo == 'BEBIDA' || sec == 'JUGO' || sec == 'BEBIDA') {
          hasBebida = true;
        } else if (tipo == 'POSTRE' || (tipo == 'EXTRA' && sec == 'POSTRE')) {
          hasPostre = true;
        } else if (tipo == 'ALMUERZO') {
          if (l['platos'] is List && (l['platos'] as List).isNotEmpty) {
            for (final p in (l['platos'] as List).whereType<Map>()) {
              classifySectionCategory(
                p['seccion']?.toString(),
                p['categoria']?.toString(),
                nombre: p['nombre']?.toString(),
                fromAlmuerzo: true,
              );
            }
          } else if (sec.isNotEmpty) {
            classifySectionCategory(sec, tipo, fromAlmuerzo: true);
          } else if (!almuerzoCourseCountKnown && !hasSopa && !hasSegundo) {
            hasSopa = true;
            hasSegundo = true;
          }
        } else if (tipo == 'EXTRA') {
          final nom = l['nombre']?.toString();
          if (nom != null && nom.trim().isNotEmpty) {
            applyTokenByCatalog(nom);
          }
        }
      }
    }

    if (ventaItems != null) {
      for (final item in ventaItems.whereType<Map>()) {
        final plato = item['plato'] is Map ? item['plato'] as Map : null;
        final tipo = (item['tipo'] ?? '').toString().trim().toUpperCase();
        final esAlmuerzo = item['esAlmuerzo'] == true;
        final sec = (item['seccion'] ?? plato?['seccion'])?.toString() ?? '';
        final cat =
            (item['categoria'] ?? plato?['categoria'])?.toString() ?? '';
        final nom = (item['nombre'] ?? plato?['nombre'])?.toString();

        if (tipo == 'ALMUERZO' || esAlmuerzo) {
          final upperSec = sec.trim().toUpperCase();
          if (upperSec == 'SOPA') {
            hasSopa = true;
          } else if (upperSec == 'FUERTE' ||
              upperSec == 'SEGUNDO' ||
              upperSec == 'PLATO_FUERTE') {
            hasSegundo = true;
          } else {
            hasSopa = true;
            hasSegundo = true;
          }
        } else if (tipo == 'A_LA_CARTA' || cat.toUpperCase() == 'A_LA_CARTA') {
          hasCartaFuerte = true;
        } else if (tipo == 'BEBIDA' ||
            cat.toUpperCase() == 'BEBIDA' ||
            sec.toUpperCase() == 'JUGO' ||
            sec.toUpperCase() == 'BEBIDA') {
          hasBebida = true;
        } else if (tipo == 'POSTRE' ||
            cat.toUpperCase() == 'POSTRE' ||
            sec.toUpperCase() == 'POSTRE') {
          hasPostre = true;
        } else if (tipo == 'EXTRA' && nom != null && nom.trim().isNotEmpty) {
          applyTokenByCatalog(nom);
        }
      }
    }

    final trimmedName = platoNombre?.trim() ?? '';
    if (!hasSopa &&
        !hasSegundo &&
        !hasCartaFuerte &&
        !hasBebida &&
        !hasPostre &&
        trimmedName.isNotEmpty) {
      final tokens = trimmedName
          .split(RegExp(r'\s*[+,·]\s*'))
          .where((t) => t.trim().isNotEmpty)
          .toList();
      for (final token in tokens) {
        applyTokenByCatalog(token);
      }
      if (!hasSopa &&
          !hasSegundo &&
          !hasCartaFuerte &&
          !hasBebida &&
          !hasPostre &&
          fallbackToAlmuerzoIfNamed) {
        hasSopa = true;
        hasSegundo = true;
      }
    }

    String? base;
    if (hasSopa && hasSegundo) {
      base = 'Almuerzo';
    } else if (hasSopa) {
      base = 'Solo Sopa';
    } else if (hasSegundo) {
      base = 'Solo Segundo';
    } else if (hasCartaFuerte) {
      base = 'Plato Fuerte';
    } else if (almuerzo != null) {
      base = 'Almuerzo';
    }

    final parts = <String>[
      ?base,
      if (hasCartaFuerte && (hasSopa || hasSegundo)) 'Plato Fuerte',
      if (hasBebida) 'Bebida',
      if (hasPostre) 'Postre',
    ];

    if (parts.isEmpty) {
      return fallbackToAlmuerzoIfNamed ? 'Almuerzo' : null;
    }
    return parts.join(' + ');
  }
}
