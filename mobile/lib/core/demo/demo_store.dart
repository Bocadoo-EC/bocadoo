import 'package:flutter/foundation.dart';

import '../contracts/models.dart';
import '../contracts/qr_parser.dart';

/// Estado de una preorden en el almacén de demostración.
enum PreorderStatus { pending, delivered, acknowledged, cancelled }

/// Preorden compartida entre el comensal (C3, C8) y la caja (O12).
class DemoPreorder {
  DemoPreorder({
    required this.number,
    required this.restaurantId,
    required this.restaurantName,
    required this.dinerUserId,
    required this.dinerName,
    required this.amount,
    required this.createdAt,
    required this.expiresAt,
    this.soup,
    this.main,
    this.detail = '',
    this.takeaway = false,
    this.takeawaySurcharge = 0.25,
    this.singleLunchPrice = 3.00,
    this.basePriceCents = 0,
    this.takeawaySurchargeCents = 0,
    this.totalCents = 0,
    this.estimatedArrivalLabel,
    this.hasPlan = false,
  });

  final String number;
  final String restaurantId;
  final String restaurantName;
  final String dinerUserId;
  final String dinerName;
  final String? soup;
  final String? main;
  final String detail;
  final bool takeaway;
  final double takeawaySurcharge;
  final double singleLunchPrice;
  final int basePriceCents;
  final int takeawaySurchargeCents;
  final int totalCents;
  final String? estimatedArrivalLabel;
  final bool hasPlan;

  /// Lo que se cobra en caja (las preórdenes se cobran en efectivo).
  final double amount;
  final DateTime createdAt;
  final DateTime expiresAt;

  PreorderStatus status = PreorderStatus.pending;
  DateTime? deliveredAt;

  /// Con plan: la caja ya leyó el QR y descontó el almuerzo.
  bool validated = false;

  bool get isOpen => status == PreorderStatus.pending;

  int get effectiveBaseCents =>
      basePriceCents > 0 ? basePriceCents : (singleLunchPrice * 100).round();

  int get effectiveSurchargeCents => takeaway
      ? (takeawaySurchargeCents > 0
          ? takeawaySurchargeCents
          : (takeawaySurcharge * 100).round())
      : 0;

  int get effectiveTotalCents {
    if (hasPlan) return 0;
    if (totalCents > 0) return totalCents;
    return effectiveBaseCents + effectiveSurchargeCents;
  }
}

/// Calificación rápida de un comensal (C10 → O15).
class DemoFeedback {
  DemoFeedback({
    required this.id,
    required this.restaurantId,
    required this.dinerName,
    required this.tag,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String restaurantId;
  final String dinerName;
  final String tag;
  final String? note;
  final DateTime createdAt;

  /// Respuesta del dueño ("Agradecer", "Reponer almuerzo"…); `null` = pendiente.
  String? reply;
}

/// Datos en memoria que comparten los mocks de comensal y dueño mientras no
/// exista la API: una preorden entregada en caja la ve el comensal, y una
/// mesa armada en C9 aparece en Caja.
// TODO: Conectar con provider de backend (desaparece cuando exista la API).
class DemoStore extends ChangeNotifier {
  DemoStore._() {
    _seed();
  }

  static final DemoStore instance = DemoStore._();

  /// Local de la caja de demostración (La Cuchara de San Blas).
  static const ownerRestaurantId = 'r1';

  /// Usuario comensal de la sesión de demostración.
  static const dinerUserId = 'u1';

  final List<DemoPreorder> preorders = [];
  final Map<String, SharedTable> tables = {};

  /// Mesas ya cobradas en caja.
  final Set<String> settledTables = {};
  final List<DemoFeedback> feedback = [];
  final Map<String, String> occupancyOverrides = {};
  final Map<String, int> remainingLunchesByRest = {'r1': 14, 'r2': 6};

  int _orderSeq = 43;
  int _tableSeq = 1235;
  int _feedbackSeq = 0;

  String nextOrderNumber() => '${++_orderSeq}';
  String nextTableId() => 'M${_tableSeq++}';
  String nextFeedbackId() => 'op-${++_feedbackSeq}';

  DemoPreorder? preorderByNumber(String number) =>
      preorders.where((o) => o.number == number).firstOrNull;

  /// Avisa a quien escuche (Caja, Mi Pase) que algo cambió.
  void changed() => notifyListeners();

  void _seed() {
    final now = DateTime.now();
    preorders.addAll([
      // Pedido cubierto por un plan prepagado: se valida con su QR y se entrega.
      DemoPreorder(
        number: '40',
        restaurantId: ownerRestaurantId,
        restaurantName: 'La Cuchara de San Blas',
        dinerUserId: 'u-sofia',
        dinerName: 'Sofía Almeida',
        soup: 'Locro de papa con queso',
        main: 'Seco de pollo con maduro',
        detail: 'Locro de papa con queso · Seco de pollo con maduro',
        basePriceCents: 300,
        totalCents: 0,
        estimatedArrivalLabel: '12:30',
        amount: 0,
        hasPlan: true,
        createdAt: now.subtract(const Duration(minutes: 3)),
        expiresAt: now.add(const Duration(minutes: 27)),
      ),
      DemoPreorder(
        number: '42',
        restaurantId: ownerRestaurantId,
        restaurantName: 'La Cuchara de San Blas',
        dinerUserId: dinerUserId,
        dinerName: 'Carlos Mejía',
        soup: 'Locro de papa con queso',
        main: 'Seco de pollo con maduro',
        detail: 'Locro de papa con queso · Seco de pollo con maduro',
        basePriceCents: 300,
        totalCents: 300,
        estimatedArrivalLabel: 'En 15 min',
        amount: 3.00,
        createdAt: now.subtract(const Duration(minutes: 6)),
        expiresAt: now.add(const Duration(minutes: 24)),
      ),
      DemoPreorder(
        number: '43',
        restaurantId: ownerRestaurantId,
        restaurantName: 'La Cuchara de San Blas',
        dinerUserId: 'u-andrea',
        dinerName: 'Andrea Morales',
        soup: 'Sopa de lenteja',
        main: 'Trucha frita con ensalada',
        detail: 'Sopa de lenteja · Trucha frita con ensalada',
        basePriceCents: 300,
        totalCents: 300,
        estimatedArrivalLabel: '13:00',
        amount: 3.00,
        createdAt: now.subtract(const Duration(minutes: 12)),
        expiresAt: now.add(const Duration(minutes: 18)),
      ),
    ]);

    const soups = ['Locro de papa con queso y aguacate', 'Sopa criolla de verduras'];
    const mains = [
      TableDish(
        id: 'r1-m1',
        name: 'Seco de pollo tierno con maduro frito',
        price: 3.00,
        imageUrl: 'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?auto=format&fit=crop&w=300&q=80',
      ),
      TableDish(
        id: 'r1-m2',
        name: 'Chuleta ahumada al grill con menestra',
        price: 3.25,
        imageUrl: 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=300&q=80',
      ),
    ];
    tables['M1234'] = SharedTable(
      id: 'M1234',
      restaurantId: ownerRestaurantId,
      restaurantName: 'La Cuchara de San Blas',
      hostName: 'Carlos Mejía',
      time: '13:00',
      qrPayload: BocadooQrParser.generateTableCode('M1234', restaurantId: ownerRestaurantId),
      // TODO: Definir el enlace de invitación de la app (ficha Fase 5, B12).
      shareUrl: 'https://bocadoo.ec/app/comensal/mesa/M1234',
      occupancyLabel: 'Fluido · Llegas y te sientas',
      soups: soups,
      mains: mains,
      members: [
        TableMember(id: 'mem-host', name: 'Carlos Mejía', isHost: true, soup: soups[0], main: mains[0].name),
        TableMember(id: 'mem-2', name: 'Valentina Ortiz', soup: soups[1], main: mains[1].name),
        TableMember(id: 'mem-3', name: 'Mateo Ruiz', soup: soups[0], main: mains[0].name, takeaway: true),
      ],
    );

    for (final o in preorders) {
      BocadooQrParser.generateOrderCode(
        o.number,
        orderId: o.number,
        restaurantId: o.restaurantId,
      );
    }

    feedback.addAll([
      DemoFeedback(
        id: nextFeedbackId(),
        restaurantId: ownerRestaurantId,
        dinerName: 'Carlos Mejía',
        tag: 'Rápido',
        note: 'Excelente atención y la sopa estuvo caliente.',
        createdAt: now.subtract(const Duration(minutes: 20)),
      ),
      DemoFeedback(
        id: nextFeedbackId(),
        restaurantId: ownerRestaurantId,
        dinerName: 'Andrea Morales',
        tag: 'Porción',
        note: 'Un poquito más de arroz por favor.',
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      DemoFeedback(
        id: nextFeedbackId(),
        restaurantId: ownerRestaurantId,
        dinerName: 'Valentina Ortiz',
        tag: 'Rico',
        note: 'El seco de pollo estuvo buenísimo, lo recomiendo.',
        createdAt: now.subtract(const Duration(hours: 26)),
      )..reply = 'Agradecer',
    ]);
  }
}
