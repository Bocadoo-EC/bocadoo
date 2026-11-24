import 'package:flutter/foundation.dart';

import '../../../../core/contracts/models.dart';

/// Rol de este dispositivo en el local (O16). El cajero ve Caja, Pedidos y Turno.
enum OwnerRole { owner, cashier }

/// Preorden por cobrar y entregar (O12).
@immutable
class OwnerOrder {
  const OwnerOrder({
    this.id,
    this.restaurantId,
    required this.number,
    required this.dinerName,
    required this.amount,
    this.totalCents,
    required this.createdAt,
    this.estado = 'EN_CAMINO',
    this.soup,
    this.main,
    this.drink,
    this.dessert,
    this.estimatedArrival,
    this.estimatedArrivalLabel,
    this.takeaway = false,
    this.takeawaySurchargeCents = 25,
    this.paidByPlan = false,
    this.validated = false,
    this.planCreditsUsed = 0,
    this.cashToCollectCents = 0,
    this.cashItems = const [],
    this.offerId,
    this.offers = const [],
    this.hasPlanLineInQuote = false,
    this.quoteBalanceToCollectCents,
  });

  /// Orden híbrida: cupos de plan usados y saldo a cobrar en caja.
  final int planCreditsUsed;
  final int cashToCollectCents;
  final List<String> cashItems;
  final String estado;
  final String? offerId;
  final List<String> offers;
  final bool hasPlanLineInQuote;
  final int? quoteBalanceToCollectCents;

  final String? id;
  final String? restaurantId;
  final String number;
  final String dinerName;
  final String? soup;
  final String? main;
  final String? drink;
  final String? dessert;
  final DateTime? estimatedArrival;
  final String? estimatedArrivalLabel;
  final bool takeaway;
  final int takeawaySurchargeCents;

  /// Lo que se cobra en efectivo (0 si lo cubre un plan prepagado).
  final double amount;
  final int? totalCents;
  final DateTime createdAt;

  /// El pedido sale del plan del comensal: no se cobra, se valida con su QR.
  final bool paidByPlan;

  /// Con plan: ya se validó el QR y se descontó el almuerzo; falta entregar.
  final bool validated;

  /// Flujo Oferta Flash (`almuerzo.ofertaId != null` o `ofertas` no vacío).
  bool get hasFlashOffer =>
      (offerId != null && offerId!.trim().isNotEmpty) || offers.isNotEmpty;

  /// Flujo Plan prepagado (cotización con fuente `PLAN` sin oferta).
  bool get isPlanFlow =>
      !hasFlashOffer && (hasPlanLineInQuote || paidByPlan);

  /// Saldo pendiente real a cobrar en caja.
  int get effectiveBalanceToCollectCents =>
      quoteBalanceToCollectCents ?? effectiveTotalCents;

  /// Con plan solo se cobra el saldo de carta / extras (`cashToCollectCents`).
  int get effectiveTotalCents => paidByPlan
      ? cashToCollectCents
      : (quoteBalanceToCollectCents ?? totalCents ?? (amount * 100).round());

  /// `BCD-ORD-42`: lo que lee el escáner de Caja.
  String get qrCode => 'BCD-ORD-$number';

  /// Se puede entregar: en efectivo se cobra al entregar; con plan, solo si ya se validó.
  bool get canDeliver => !paidByPlan || validated;
}

/// Conflicto `409 SALDO_CAMBIO` al canjear una preorden cuyo saldo recalculado
/// en vivo cambió respecto al snapshot guardado al pedir.
@immutable
class SaldoCambioConflict {
  const SaldoCambioConflict({
    required this.orderId,
    required this.orderNumber,
    required this.dinerName,
    required this.previousBalanceCents,
    required this.newBalanceCents,
    required this.coveredByPlan,
    required this.paymentMethod,
  });

  final String orderId;
  final String orderNumber;
  final String dinerName;
  final int previousBalanceCents;
  final int newBalanceCents;
  final bool coveredByPlan;
  final dynamic paymentMethod;
}

/// Plato elegido por un integrante de una mesa grupal.
@immutable
class PendingTableMemberDish {
  const PendingTableMemberDish({
    required this.memberName,
    this.soup,
    this.main,
    this.extras = const [],
    this.takeaway = false,
    this.hasPlan = false,
  });

  final String memberName;
  final String? soup;
  final String? main;
  final List<String> extras;
  final bool takeaway;
  final bool hasPlan;
}

/// Mesa abierta con comensales, por cobrar (banner de Caja / Pedidos en camino).
@immutable
class PendingTable {
  const PendingTable({
    required this.id,
    required this.hostName,
    required this.members,
    required this.time,
    this.planCount = 0,
    this.cashCount = 0,
    this.takeawayCount = 0,
    this.takeawaySurchargeCents = 0,
    this.memberDishes = const [],
    this.isCollecting = false,
    this.confirmedCount,
  });

  final String id;
  final String hostName;
  final int members;
  final String time;
  final int planCount;
  final int cashCount;
  final int takeawayCount;
  final int takeawaySurchargeCents;
  final List<PendingTableMemberDish> memberDishes;
  final bool isCollecting;
  final int? confirmedCount;

  String get shortId {
    final clean = id.replaceAll('-', '').trim().toUpperCase();
    if (clean.length <= 6) return clean;
    return clean.substring(clean.length - 6);
  }
}

/// Cómo paga cada integrante de la mesa (O5).
enum TableChargeVia { plan, hostPlan, cash }

@immutable
class TableChargeLine {
  const TableChargeLine({
    required this.name,
    required this.via,
    required this.amount,
    this.soup,
    this.main,
    this.extras = const [],
    this.isHost = false,
    this.takeaway = false,
  });

  final String name;
  final String? soup;
  final String? main;
  final List<String> extras;
  final bool isHost;
  final bool takeaway;
  final TableChargeVia via;

  /// Monto en efectivo (0 si sale de un plan).
  final double amount;
}

/// Vista previa del cobro de una mesa. Si [error] no es `null`, no se puede cobrar.
@immutable
class TablePreview {
  const TablePreview({
    required this.tableId,
    required this.hostName,
    required this.time,
    required this.mode,
    this.lines = const [],
    this.stamps = const [],
    this.error,
    this.settled = false,
  });

  final String tableId;
  final String hostName;
  final String time;
  final TableMode mode;
  final List<TableChargeLine> lines;

  /// Sellos que se reparten al cobrar: (nombre, cantidad).
  final List<(String, int)> stamps;
  final String? error;
  final bool settled;

  double get totalCash => lines.fold<double>(0, (s, l) => s + l.amount);
  bool get canCharge => error == null && !settled && lines.isNotEmpty;
}

/// Respuesta rápida a una opinión (O15).
enum OpinionReply { thanks, replaceLunch }

extension OpinionReplyX on OpinionReply {
  String get label => switch (this) {
        OpinionReply.thanks => 'Agradecer',
        OpinionReply.replaceLunch => 'Reponer almuerzo',
      };
}

/// Calificación rápida de un comensal con su nota (O15).
@immutable
class OwnerOpinion {
  const OwnerOpinion({
    required this.id,
    required this.dinerName,
    required this.tag,
    required this.createdAt,
    this.note,
    this.reply,
    this.phone,
    this.canReplaceLunch = false,
  });

  final String id;
  final String dinerName;
  final String tag;
  final String? note;
  final DateTime createdAt;

  /// Respuesta ya enviada; `null` = pendiente.
  final String? reply;

  /// Celular del comensal si es cliente del local (para escribirle).
  final String? phone;

  /// `true` si tiene un plan activo al que se le puede sumar un almuerzo.
  final bool canReplaceLunch;

  bool get isPending => reply == null;
}

/// Datos del local para Ajustes (O16).
@immutable
class LocalInfo {
  const LocalInfo({
    required this.name,
    required this.address,
    required this.seats,
    this.tablesCount,
    this.phone = '',
    this.maskedCedulaRuc,
    this.takeawaySurchargeCents,
    this.perfilCompleto = true,
    this.datosPendientes = const [],
    this.zone = '',
    this.latitude,
    this.longitude,
    this.logo,
    this.logoUrl,
  });

  final String name;
  final String address;
  final int seats;
  final int? tablesCount;
  final String phone;

  /// Cédula o RUC enmascarado devuelto por el servidor (nunca reconstruido en cliente).
  final String? maskedCedulaRuc;
  final int? takeawaySurchargeCents;

  /// Calculado únicamente por el backend (`GET /v1/restaurante`).
  final bool perfilCompleto;
  final List<String> datosPendientes;

  final String zone;
  final double? latitude;
  final double? longitude;

  /// Logo subido (JPEG/PNG en memoria); `null` = se muestra el monograma o [logoUrl].
  final Uint8List? logo;
  final String? logoUrl;

  /// Dos iniciales del nombre ("La Cuchara" → "LC").
  String get monogram {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'B';
    if (words.length == 1) return words.first.substring(0, words.first.length.clamp(1, 2)).toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}

/// Solicitud de plan enviada por un comensal pendiente de cobro en caja (P-01).
@immutable
class OwnerPlanRequest {
  const OwnerPlanRequest({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.planId,
    required this.planName,
    required this.price,
    required this.lunches,
    required this.createdAt,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String planId;
  final String planName;
  final double price;
  final int lunches;
  final DateTime createdAt;
}
