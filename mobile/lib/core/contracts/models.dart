import 'package:flutter/foundation.dart';

/// Modelo inmutable de un Pase de Almuerzos para el Comensal
@immutable
class CustomerPass {
  final String id;
  final String userId;
  final String studentName;
  final String studentCareer;
  final String planName;
  final int totalLunches;
  final int remainingLunches;
  final DateTime expiresAt;
  final String status; // ACTIVO, POR_VENCER, AGOTADO, VENCIDO
  final String qrToken;
  final String restaurantId;
  final String restaurantName;
  final String? avatarUrl;

  const CustomerPass({
    required this.id,
    required this.userId,
    required this.studentName,
    this.studentCareer = 'Estudiante',
    required this.planName,
    required this.totalLunches,
    required this.remainingLunches,
    required this.expiresAt,
    this.status = 'ACTIVO',
    required this.qrToken,
    required this.restaurantId,
    required this.restaurantName,
    this.avatarUrl,
  });

  bool get isExpiringSoon {
    if (remainingLunches <= 3) return true;
    final diff = expiresAt.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= 3;
  }

  bool get isExpired {
    return DateTime.now().isAfter(expiresAt) || remainingLunches <= 0;
  }

  CustomerPass copyWith({
    String? id,
    String? userId,
    String? studentName,
    String? studentCareer,
    String? planName,
    int? totalLunches,
    int? remainingLunches,
    DateTime? expiresAt,
    String? status,
    String? qrToken,
    String? restaurantId,
    String? restaurantName,
    String? avatarUrl,
  }) {
    return CustomerPass(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      studentName: studentName ?? this.studentName,
      studentCareer: studentCareer ?? this.studentCareer,
      planName: planName ?? this.planName,
      totalLunches: totalLunches ?? this.totalLunches,
      remainingLunches: remainingLunches ?? this.remainingLunches,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      qrToken: qrToken ?? this.qrToken,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'studentName': studentName,
      'studentCareer': studentCareer,
      'planName': planName,
      'totalLunches': totalLunches,
      'remainingLunches': remainingLunches,
      'expiresAt': expiresAt.toIso8601String(),
      'status': status,
      'qrToken': qrToken,
      'restaurantId': restaurantId,
      'restaurantName': restaurantName,
      'avatarUrl': avatarUrl,
    };
  }

  factory CustomerPass.fromMap(Map<String, dynamic> map) {
    return CustomerPass(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      studentName: map['studentName'] as String? ?? '',
      studentCareer: map['studentCareer'] as String? ?? 'Estudiante',
      planName: map['planName'] as String? ?? '',
      totalLunches: map['totalLunches'] as int? ?? 0,
      remainingLunches: map['remainingLunches'] as int? ?? 0,
      expiresAt: DateTime.tryParse(map['expiresAt'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 30)),
      status: map['status'] as String? ?? 'ACTIVO',
      qrToken: map['qrToken'] as String? ?? '',
      restaurantId: map['restaurantId'] as String? ?? '',
      restaurantName: map['restaurantName'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String?,
    );
  }
}

/// Modelo inmutable de un Restaurante universitario
@immutable
class Restaurant {
  final String id;
  final String name;
  final String description;
  final String address;
  final String zone;
  final double rating;
  final double distanceKm;
  final String imageUrl;
  final String? logoUrl;
  final double singleLunchPrice;
  final double? planLunchPrice;
  final String occupancy; // LIBRE, MOVIDO, LLENO
  final bool isOpen;
  final List<String> categories;
  final List<MenuItem> todayMenu;
  final String featuredDish;
  final bool hasPlan;
  final List<RestaurantOffer> offers;
  final String schedule;
  final List<String> tags;
  final String juice;
  final String dessert;
  final double takeawaySurcharge;

  /// Coordenadas del local para el mapa (C11). `null` si no se conocen.
  final double? latitude;
  final double? longitude;

  const Restaurant({
    required this.id,
    required this.name,
    this.description = '',
    this.address = '',
    this.zone = '',
    this.rating = 4.5,
    this.distanceKm = 0.5,
    required this.imageUrl,
    this.logoUrl,
    required this.singleLunchPrice,
    this.planLunchPrice,
    this.occupancy = 'LIBRE',
    this.isOpen = true,
    this.categories = const ['Todos'],
    this.todayMenu = const [],
    this.featuredDish = '',
    this.hasPlan = false,
    this.offers = const [],
    this.schedule = '11:30 - 15:30',
    this.tags = const [],
    this.juice = '',
    this.dessert = '',
    this.takeawaySurcharge = 0.25,
    this.latitude,
    this.longitude,
  });

  bool get hasLocation => latitude != null && longitude != null;

  int get walkingMinutes {
    final minutes = (distanceKm * 12).round();
    return minutes < 2 ? 2 : minutes;
  }

  List<MenuItem> get soups =>
      todayMenu.where((m) => m.category == 'Sopa').toList();
  List<MenuItem> get mains =>
      todayMenu.where((m) => m.category == 'Plato Fuerte').toList();
  List<MenuItem> get breakfasts =>
      todayMenu.where((m) => m.category == 'Desayuno').toList();
  bool get hasMenu => soups.isNotEmpty || mains.isNotEmpty;
  bool get hasOffer => offers.isNotEmpty;
  bool get hasBreakfastToday => breakfasts.any((b) => !b.isSoldOut);

  Restaurant copyWith({
    String? id,
    String? name,
    String? description,
    String? address,
    String? zone,
    double? rating,
    double? distanceKm,
    String? imageUrl,
    String? logoUrl,
    double? singleLunchPrice,
    double? planLunchPrice,
    String? occupancy,
    bool? isOpen,
    List<String>? categories,
    List<MenuItem>? todayMenu,
  }) {
    return Restaurant(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      address: address ?? this.address,
      zone: zone ?? this.zone,
      rating: rating ?? this.rating,
      distanceKm: distanceKm ?? this.distanceKm,
      imageUrl: imageUrl ?? this.imageUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      singleLunchPrice: singleLunchPrice ?? this.singleLunchPrice,
      planLunchPrice: planLunchPrice ?? this.planLunchPrice,
      occupancy: occupancy ?? this.occupancy,
      isOpen: isOpen ?? this.isOpen,
      categories: categories ?? this.categories,
      todayMenu: todayMenu ?? this.todayMenu,
      featuredDish: featuredDish,
      hasPlan: hasPlan,
      offers: offers,
      schedule: schedule,
      tags: tags,
      juice: juice,
      dessert: dessert,
      takeawaySurcharge: takeawaySurcharge,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

/// Oferta publicada por un local: flash de hoy o promo programada.
@immutable
class RestaurantOffer {
  final String id;
  final String restaurantId;
  final String title;
  final String badge;
  final double? price;
  final double? originalPrice;
  final int slotsLeft;
  final bool availableNow;
  final bool appliesToday;
  final bool reservable;

  const RestaurantOffer({
    required this.id,
    required this.restaurantId,
    required this.title,
    required this.badge,
    this.price,
    this.originalPrice,
    this.slotsLeft = 0,
    this.availableNow = true,
    this.appliesToday = true,
    this.reservable = false,
  });
}

/// Plan que un local publica para que el comensal lo solicite.
@immutable
class PlanTemplate {
  final String id;
  final String restaurantId;
  final String type; // Semanal, Quincenal, Mensual
  final String name;
  final int lunches;
  final int priceCents;
  final int validityDays;
  final String category; // ALMUERZO, DESAYUNO, MIXTO

  const PlanTemplate({
    required this.id,
    required this.restaurantId,
    required this.type,
    required this.name,
    required this.lunches,
    required this.priceCents,
    required this.validityDays,
    this.category = 'ALMUERZO',
  });

  int get perLunchCents => (priceCents / lunches).round();
}

/// Tarjeta de sellos del comensal en un local.
@immutable
class StampCard {
  final String restaurantId;
  final String name;
  final int current;
  final int goal;
  final String reward;
  final int rewardsAvailable;

  const StampCard({
    required this.restaurantId,
    required this.name,
    required this.current,
    required this.goal,
    this.reward = 'Almuerzo gratis',
    this.rewardsAvailable = 0,
  });
}

/// Mesa con amigos activa del comensal.
@immutable
class ActiveTable {
  final String id;
  final String restaurantName;
  final String time;
  final int membersCount;
  final String url;

  const ActiveTable({
    required this.id,
    required this.restaurantName,
    required this.time,
    required this.membersCount,
    required this.url,
  });
}

/// Preorden activa del comensal.
@immutable
class ActiveOrder {
  final String orderNumber;
  final String status; // PREPARANDO, LISTO, ENTREGADO
  final String restaurantName;
  final String qrPayload;
  final String detail;
  final String? soup;
  final String? main;
  final bool takeaway;
  final double takeawaySurcharge;
  final double singleLunchPrice;
  final bool hasPlan;

  /// Hasta cuándo se guarda la preorden (cuenta regresiva de C8).
  final DateTime? expiresAt;

  /// Lo que pagó en caja al recibirlo (solo con estado ENTREGADO).
  final double? paidAmount;

  bool get isDelivered => status == 'ENTREGADO';

  const ActiveOrder({
    required this.orderNumber,
    required this.restaurantName,
    required this.qrPayload,
    this.status = 'PREPARANDO',
    this.detail = '',
    this.soup,
    this.main,
    this.takeaway = false,
    this.takeawaySurcharge = 0.25,
    this.singleLunchPrice = 3.00,
    this.hasPlan = false,
    this.expiresAt,
    this.paidAmount,
  });
}

/// Cómo se cobra la mesa con amigos.
enum TableMode { eachOwn, hostPays }

@immutable
class TableMember {
  final String id;
  final String name;
  final bool isHost;
  final String? soup;
  final String? main;
  final bool takeaway;

  const TableMember({
    required this.id,
    required this.name,
    this.isHost = false,
    this.soup,
    this.main,
    this.takeaway = false,
  });
}

/// Plato fuerte que puede elegir un invitado (C7).
@immutable
class TableDish {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  final bool isVeggie;

  const TableDish({
    required this.id,
    required this.name,
    required this.price,
    this.imageUrl,
    this.isVeggie = false,
  });
}

/// Mesa con amigos (C9) e invitación (C7).
@immutable
class SharedTable {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String hostName;
  final String time;
  final TableMode mode;
  final List<TableMember> members;
  final bool onTheWay;

  /// Texto de ocupación del local ("Fluido · Llegas y te sientas").
  final String occupancyLabel;
  final List<String> soups;
  final List<TableDish> mains;
  final double takeawaySurcharge;

  /// Lo que lee la caja para validar la mesa completa.
  final String qrPayload;

  /// Enlace que se comparte con los invitados.
  final String shareUrl;

  const SharedTable({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.hostName,
    required this.time,
    required this.qrPayload,
    required this.shareUrl,
    this.mode = TableMode.eachOwn,
    this.members = const [],
    this.onTheWay = false,
    this.occupancyLabel = '',
    this.soups = const [],
    this.mains = const [],
    this.takeawaySurcharge = 0.25,
  });

  SharedTable copyWith({TableMode? mode, List<TableMember>? members, bool? onTheWay}) => SharedTable(
        id: id,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        hostName: hostName,
        time: time,
        qrPayload: qrPayload,
        shareUrl: shareUrl,
        mode: mode ?? this.mode,
        members: members ?? this.members,
        onTheWay: onTheWay ?? this.onTheWay,
        occupancyLabel: occupancyLabel,
        soups: soups,
        mains: mains,
        takeawaySurcharge: takeawaySurcharge,
      );
}

/// Perfil del comensal (C6).
@immutable
class CustomerProfile {
  final String name;
  final String phone;
  final String? habitualPlanName;
  final List<String> habitualPlanIncludes;

  /// Número de WhatsApp de soporte de Bocadoo (formato internacional sin "+").
  final String supportWhatsApp;

  const CustomerProfile({
    required this.name,
    required this.phone,
    required this.supportWhatsApp,
    this.habitualPlanName,
    this.habitualPlanIncludes = const [],
  });
}

/// Almuerzo validado que todavía puede calificarse (C10).
@immutable
class PendingFeedback {
  final String redemptionId;
  final String restaurantId;
  final String restaurantName;
  final DateTime validatedAt;

  const PendingFeedback({
    required this.redemptionId,
    required this.restaurantId,
    required this.restaurantName,
    required this.validatedAt,
  });
}

/// Movimiento reciente del comensal (consumo, compra de plan u otro).
@immutable
class ActivityItem {
  final String id;
  final String name;
  final String detail;
  final String value;
  final bool positive;
  final String kind; // lunch, plan, other

  const ActivityItem({
    required this.id,
    required this.name,
    required this.detail,
    required this.value,
    this.positive = false,
    this.kind = 'other',
  });
}

/// Modelo inmutable de un ítem de Menú
@immutable
class MenuItem {
  final String id;
  final String name;
  final String category; // Sopa, Plato Fuerte, Bebida, Postre, Desayuno
  final double? price;
  final bool isSoldOut;
  final String? imageUrl;
  final bool isVeggie;

  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    this.price,
    this.isSoldOut = false,
    this.imageUrl,
    this.isVeggie = false,
  });

  MenuItem copyWith({
    String? id,
    String? name,
    String? category,
    double? price,
    bool? isSoldOut,
    String? imageUrl,
    bool? isVeggie,
  }) {
    return MenuItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      isSoldOut: isSoldOut ?? this.isSoldOut,
      imageUrl: imageUrl ?? this.imageUrl,
      isVeggie: isVeggie ?? this.isVeggie,
    );
  }
}

/// Modelo inmutable de Registro de Consumo / Canje
@immutable
class ConsumptionRecord {
  final String id;
  final String passId;
  final String restaurantName;
  final String restaurantId;
  final DateTime date;
  final String description;
  final int lunchesUsed;
  final int remainingAfter;
  final String status; // Validado, Anulado

  const ConsumptionRecord({
    required this.id,
    required this.passId,
    required this.restaurantName,
    required this.restaurantId,
    required this.date,
    this.description = 'Almuerzo universitario diario',
    this.lunchesUsed = 1,
    required this.remainingAfter,
    this.status = 'Validado',
  });

  ConsumptionRecord copyWith({
    String? id,
    String? passId,
    String? restaurantName,
    String? restaurantId,
    DateTime? date,
    String? description,
    int? lunchesUsed,
    int? remainingAfter,
    String? status,
  }) {
    return ConsumptionRecord(
      id: id ?? this.id,
      passId: passId ?? this.passId,
      restaurantName: restaurantName ?? this.restaurantName,
      restaurantId: restaurantId ?? this.restaurantId,
      date: date ?? this.date,
      description: description ?? this.description,
      lunchesUsed: lunchesUsed ?? this.lunchesUsed,
      remainingAfter: remainingAfter ?? this.remainingAfter,
      status: status ?? this.status,
    );
  }
}

/// Modelo inmutable de la Tienda / Restaurante del Dueño
@immutable
class OwnerStore {
  final String id;
  final String name;
  final String ownerName;
  final String ruc;
  final String zone;
  final String address;
  final double defaultLunchPrice;
  final bool isOpen;

  const OwnerStore({
    required this.id,
    required this.name,
    required this.ownerName,
    this.ruc = '',
    this.zone = '',
    this.address = '',
    this.defaultLunchPrice = 3.50,
    this.isOpen = true,
  });

  OwnerStore copyWith({
    String? id,
    String? name,
    String? ownerName,
    String? ruc,
    String? zone,
    String? address,
    double? defaultLunchPrice,
    bool? isOpen,
  }) {
    return OwnerStore(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerName: ownerName ?? this.ownerName,
      ruc: ruc ?? this.ruc,
      zone: zone ?? this.zone,
      address: address ?? this.address,
      defaultLunchPrice: defaultLunchPrice ?? this.defaultLunchPrice,
      isOpen: isOpen ?? this.isOpen,
    );
  }
}

/// Modelo inmutable del Resultado de Validación de un QR escaneado
@immutable
class ScanResult {
  final bool isValid;
  final String outcome; // VERDE, ADVERTENCIA, ROJO, GRIS
  final String title;
  final String supportingLine;
  final String? studentName;
  final String? studentCareer;
  final String? studentAvatar;
  final String? passId;
  final int? totalLunches;
  final int? remainingLunches;
  final String? redemptionId;
  final DateTime? redeemedAt;
  final String? actionRequired; // VENDER_PLAN, COBRAR_SUELTO, NINGUNA

  const ScanResult({
    required this.isValid,
    required this.outcome,
    required this.title,
    required this.supportingLine,
    this.studentName,
    this.studentCareer,
    this.studentAvatar,
    this.passId,
    this.totalLunches,
    this.remainingLunches,
    this.redemptionId,
    this.redeemedAt,
    this.actionRequired,
  });

  bool get isSuccess => outcome == 'VERDE';
  bool get isWarning => outcome == 'ADVERTENCIA';
  bool get isError => outcome == 'ROJO';
  bool get isAlreadyRedeemed => outcome == 'GRIS';

  ScanResult copyWith({
    bool? isValid,
    String? outcome,
    String? title,
    String? supportingLine,
    String? studentName,
    String? studentCareer,
    String? studentAvatar,
    String? passId,
    int? totalLunches,
    int? remainingLunches,
    String? redemptionId,
    DateTime? redeemedAt,
    String? actionRequired,
  }) {
    return ScanResult(
      isValid: isValid ?? this.isValid,
      outcome: outcome ?? this.outcome,
      title: title ?? this.title,
      supportingLine: supportingLine ?? this.supportingLine,
      studentName: studentName ?? this.studentName,
      studentCareer: studentCareer ?? this.studentCareer,
      studentAvatar: studentAvatar ?? this.studentAvatar,
      passId: passId ?? this.passId,
      totalLunches: totalLunches ?? this.totalLunches,
      remainingLunches: remainingLunches ?? this.remainingLunches,
      redemptionId: redemptionId ?? this.redemptionId,
      redeemedAt: redeemedAt ?? this.redeemedAt,
      actionRequired: actionRequired ?? this.actionRequired,
    );
  }
}

/// Modelo inmutable de Transacción individual para el dueño
@immutable
class TransactionItem {
  final String id;
  final String customerName;
  final String type; // Canje, Venta Plan, Venta Suelta
  final double amount;
  final String paymentMethod; // Efectivo, Transferencia, Plan
  final DateTime timestamp;

  const TransactionItem({
    required this.id,
    required this.customerName,
    required this.type,
    required this.amount,
    required this.paymentMethod,
    required this.timestamp,
  });

  TransactionItem copyWith({
    String? id,
    String? customerName,
    String? type,
    double? amount,
    String? paymentMethod,
    DateTime? timestamp,
  }) {
    return TransactionItem(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Modelo inmutable del Resumen de Cierre de Caja
@immutable
class TransactionSummary {
  final DateTime date;
  final int lunchesRedeemedToday;
  final int plansSoldToday;
  final double totalIncomeToday;
  final double cashCounted;
  final double cashExpected;
  final double cashDifference;
  final String cashStatus; // Cuadra, Falta, Sobra
  final List<TransactionItem> transactions;

  const TransactionSummary({
    required this.date,
    this.lunchesRedeemedToday = 0,
    this.plansSoldToday = 0,
    this.totalIncomeToday = 0.0,
    this.cashCounted = 0.0,
    this.cashExpected = 0.0,
    this.cashDifference = 0.0,
    this.cashStatus = 'Cuadra',
    this.transactions = const [],
  });

  TransactionSummary copyWith({
    DateTime? date,
    int? lunchesRedeemedToday,
    int? plansSoldToday,
    double? totalIncomeToday,
    double? cashCounted,
    double? cashExpected,
    double? cashDifference,
    String? cashStatus,
    List<TransactionItem>? transactions,
  }) {
    return TransactionSummary(
      date: date ?? this.date,
      lunchesRedeemedToday: lunchesRedeemedToday ?? this.lunchesRedeemedToday,
      plansSoldToday: plansSoldToday ?? this.plansSoldToday,
      totalIncomeToday: totalIncomeToday ?? this.totalIncomeToday,
      cashCounted: cashCounted ?? this.cashCounted,
      cashExpected: cashExpected ?? this.cashExpected,
      cashDifference: cashDifference ?? this.cashDifference,
      cashStatus: cashStatus ?? this.cashStatus,
      transactions: transactions ?? this.transactions,
    );
  }
}

