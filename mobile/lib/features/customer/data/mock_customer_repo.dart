import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';
import 'local_customer_cache.dart';

/// Implementación Mock de [ICustomerRepository] basada en los datos semilla del
/// prototipo React (`store.tsx`).
class MockCustomerRepository implements ICustomerRepository {
  final Duration networkLatency;
  final LocalCustomerCache _cache;
  bool shouldThrowError;

  ActiveOrder? _activeOrder;
  StampCard _cucharaStamps = const StampCard(
    restaurantId: 'r1',
    name: 'Club La Cuchara',
    current: 7,
    goal: 10,
  );

  MockCustomerRepository({
    this.networkLatency = const Duration(milliseconds: 400),
    this.shouldThrowError = false,
    LocalCustomerCache? cache,
  }) : _cache = cache ?? LocalCustomerCache();

  Future<void> _simulateNetwork() async {
    await Future.delayed(networkLatency);
    if (shouldThrowError) {
      throw Exception('Error simulado de red al conectar con Bocadoo API.');
    }
  }

  @override
  Future<CustomerPass> getActivePass({String? userId}) async {
    final passes = await getActivePasses(userId: userId);
    return passes.first;
  }

  @override
  Future<List<CustomerPass>> getActivePasses({String? userId}) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final targetUserId = userId ?? 'u1';
    final now = DateTime.now();

    final passes = [
      CustomerPass(
        id: 'sub-1',
        userId: targetUserId,
        studentName: 'Carlos Mejía',
        studentCareer: 'Ing. de Sistemas · PUCE',
        planName: 'Plan mensual ejecutivo',
        totalLunches: 20,
        remainingLunches: 14,
        expiresAt: now.add(const Duration(days: 27)),
        qrToken: BocadooQrParser.generateQrPayload(targetUserId),
        restaurantId: 'r1',
        restaurantName: 'La Cuchara de San Blas',
      ),
      CustomerPass(
        id: 'sub-2',
        userId: targetUserId,
        studentName: 'Carlos Mejía',
        planName: 'Mensual Saludable',
        totalLunches: 20,
        remainingLunches: 6,
        expiresAt: now.add(const Duration(days: 12)),
        qrToken: BocadooQrParser.generateQrPayload(targetUserId),
        restaurantId: 'r2',
        restaurantName: 'Verde Limón',
      ),
    ];

    await _cache.savePass(passes.first);
    return passes;
  }

  @override
  Future<String> refreshQrToken(String passId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final newToken = BocadooQrParser.generateQrPayload('u1');
    final cached = await _cache.getPass();
    if (cached != null && cached.id == passId) {
      await _cache.savePass(cached.copyWith(qrToken: newToken));
    }
    return newToken;
  }

  @override
  Future<List<Restaurant>> getRestaurants({
    String? query,
    String? category,
  }) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return _allRestaurants;
  }

  @override
  Future<Restaurant?> getRestaurantById(String id) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    for (final r in _allRestaurants) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<List<MenuItem>> getTodayMenu(String restaurantId) async {
    final restaurant = await getRestaurantById(restaurantId);
    return restaurant?.todayMenu ?? const [];
  }

  @override
  Future<List<ConsumptionRecord>> getConsumptionHistory(String passId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return [
      ConsumptionRecord(
        id: 'red-1',
        passId: passId,
        restaurantName: 'La Cuchara de San Blas',
        restaurantId: 'r1',
        date: DateTime.now().subtract(const Duration(minutes: 25)),
        description: 'Locro de papa + Seco de pollo tierno',
        remainingAfter: 14,
      ),
    ];
  }

  @override
  Future<CustomerPass?> getCachedPass() async => _cache.getPass();

  @override
  Future<void> saveCachedPass(CustomerPass pass) async {
    await _cache.savePass(pass);
  }

  @override
  Future<StampCard?> getStampCard(String restaurantId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return restaurantId == 'r1' ? _cucharaStamps : null;
  }

  @override
  Future<bool> claimReward(String restaurantId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    if (restaurantId != 'r1' || _cucharaStamps.rewardsAvailable == 0) {
      return false;
    }
    _cucharaStamps = StampCard(
      restaurantId: _cucharaStamps.restaurantId,
      name: _cucharaStamps.name,
      current: _cucharaStamps.current,
      goal: _cucharaStamps.goal,
      reward: _cucharaStamps.reward,
      rewardsAvailable: _cucharaStamps.rewardsAvailable - 1,
    );
    return true;
  }

  @override
  Future<ActiveTable?> getActiveTable() async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return const ActiveTable(
      id: 'M1234',
      restaurantName: 'La Cuchara de San Blas',
      time: '13:00',
      membersCount: 1,
      url: 'https://bocadoo.ec/app/mesa/M1234',
    );
  }

  @override
  Future<ActiveOrder?> getActiveOrder() async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return _activeOrder;
  }

  @override
  Future<List<ActivityItem>> getRecentActivity() async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return const [
      ActivityItem(
        id: 'act-1',
        name: 'La Cuchara de San Blas',
        detail: 'Almuerzo consumido · 11:58',
        value: '- 1',
        kind: 'lunch',
      ),
      ActivityItem(
        id: 'act-2',
        name: 'La Cuchara de San Blas',
        detail: 'Compra de plan · Transferencia',
        value: r'$55,00',
        kind: 'plan',
      ),
    ];
  }

  @override
  Future<ActiveOrder> preorder({
    required String restaurantId,
    String? soupId,
    String? mainId,
    String? breakfastId,
    String? offerId,
    required bool takeaway,
  }) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final restaurant = await getRestaurantById(restaurantId);
    final menu = restaurant?.todayMenu ?? const <MenuItem>[];
    String nameOf(String? id) {
      for (final m in menu) {
        if (m.id == id) return m.name;
      }
      return '';
    }

    final parts = [
      nameOf(breakfastId),
      nameOf(soupId),
      nameOf(mainId),
      if (offerId != null)
        restaurant?.offers.where((o) => o.id == offerId).firstOrNull?.title ?? '',
      if (takeaway) 'Para llevar',
    ].where((p) => p.isNotEmpty);

    _activeOrder = ActiveOrder(
      orderNumber: '42',
      restaurantName: restaurant?.name ?? 'Restaurante',
      qrPayload: 'BCD-ORD-42',
      detail: parts.join(' · '),
    );
    return _activeOrder!;
  }

  @override
  Future<bool> cancelPreorder(String orderNumber) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    _activeOrder = null;
    return true;
  }

  @override
  Future<List<PlanTemplate>> getPlanTemplates(String restaurantId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return _planTemplates.where((p) => p.restaurantId == restaurantId).toList();
  }

  @override
  Future<PlanTemplate?> getPlanTemplateById(String planId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    for (final p in _planTemplates) {
      if (p.id == planId) return p;
    }
    return null;
  }

  @override
  Future<bool> requestPlan(String planId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return true;
  }

  @override
  Future<bool> cancelPlanRequest(String planId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return true;
  }

  // --- Datos semilla del prototipo (store.tsx) ---

  static const List<PlanTemplate> _planTemplates = [
    PlanTemplate(id: 'p-semanal', restaurantId: 'r1', type: 'Semanal', name: 'Plan semanal', lunches: 5, priceCents: 1500, validityDays: 7),
    PlanTemplate(id: 'p-quincenal', restaurantId: 'r1', type: 'Quincenal', name: 'Plan quincenal', lunches: 10, priceCents: 2800, validityDays: 18),
    PlanTemplate(id: 'p-mensual', restaurantId: 'r1', type: 'Mensual', name: 'Plan mensual ejecutivo', lunches: 20, priceCents: 5500, validityDays: 35),
    PlanTemplate(id: 'p-r2-semanal', restaurantId: 'r2', type: 'Semanal', name: 'Semanal Verde', lunches: 5, priceCents: 1600, validityDays: 7),
    PlanTemplate(id: 'p-r2-mensual', restaurantId: 'r2', type: 'Mensual', name: 'Mensual Saludable', lunches: 20, priceCents: 6000, validityDays: 35),
    PlanTemplate(id: 'p-r3-quincenal', restaurantId: 'r3', type: 'Quincenal', name: 'Quincenal Manaba', lunches: 10, priceCents: 3300, validityDays: 18),
    PlanTemplate(id: 'p-r3-mensual', restaurantId: 'r3', type: 'Mensual', name: 'Mensual Costeño', lunches: 20, priceCents: 6500, validityDays: 35),
    PlanTemplate(id: 'p-r4-mensual', restaurantId: 'r4', type: 'Mensual', name: 'Mensual USFQ', lunches: 20, priceCents: 6800, validityDays: 35),
  ];

  static const List<Restaurant> _allRestaurants = [
    Restaurant(
      id: 'r1',
      name: 'La Cuchara de San Blas',
      description: 'Comida casera tradicional frente a la PUCE',
      featuredDish: 'Comida casera tradicional frente a la PUCE',
      address: 'Av. 12 de Octubre N24-110 y La Católica',
      zone: 'Frente a la PUCE',
      distanceKm: 0.2,
      singleLunchPrice: 3.00,
      planLunchPrice: 2.75,
      occupancy: 'LIBRE',
      hasPlan: true,
      schedule: '11:30 - 15:30',
      tags: ['Comida casera', 'Sazón quiteña', 'Opción vegetariana'],
      juice: 'Jugo natural de temporada',
      dessert: 'Dulce de la casa',
      imageUrl:
          'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=800&q=80',
      todayMenu: [
        MenuItem(id: 'r1-s1', name: 'Locro de papa con queso y aguacate', category: 'Sopa', isVeggie: true),
        MenuItem(id: 'r1-s2', name: 'Sopa criolla de verduras', category: 'Sopa', isVeggie: true),
        MenuItem(
          id: 'r1-m1',
          name: 'Seco de pollo tierno con maduro frito',
          category: 'Plato Fuerte',
          price: 3.00,
          imageUrl:
              'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?auto=format&fit=crop&w=300&q=80',
        ),
        MenuItem(
          id: 'r1-m2',
          name: 'Chuleta ahumada al grill con menestra',
          category: 'Plato Fuerte',
          price: 3.25,
          imageUrl:
              'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=300&q=80',
        ),
      ],
    ),
    Restaurant(
      id: 'r2',
      name: 'Verde Limón',
      description: 'Almuerzos saludables y ensaladas en La Floresta',
      featuredDish: 'Crema de espinaca · Pechuga a las finas hierbas',
      address: 'Calle Madrid 1159 y Coruña, La Floresta',
      zone: 'La Floresta',
      distanceKm: 0.8,
      singleLunchPrice: 3.25,
      planLunchPrice: 3.00,
      occupancy: 'MOVIDO',
      hasPlan: true,
      schedule: '12:00 - 15:30',
      tags: ['Saludable', 'Ensaladas frescas', 'Céntrico'],
      juice: 'Limonada de hierbabuena',
      dessert: 'Fruta picada con miel',
      takeawaySurcharge: 0.30,
      imageUrl:
          'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=800&q=80',
      todayMenu: [
        MenuItem(id: 'r2-d1', name: 'Bolón de verde con café pasado', category: 'Desayuno', price: 2.50),
        MenuItem(id: 'r2-d2', name: 'Tostadas con huevo y jugo', category: 'Desayuno', price: 2.00, isSoldOut: true),
        MenuItem(id: 'r2-s1', name: 'Crema de espinaca con croutons', category: 'Sopa', isVeggie: true),
        MenuItem(id: 'r2-s2', name: 'Sopa de quinoa', category: 'Sopa', isVeggie: true, isSoldOut: true),
        MenuItem(id: 'r2-m1', name: 'Pechuga a las finas hierbas con ensalada', category: 'Plato Fuerte', price: 3.25),
        MenuItem(id: 'r2-m2', name: 'Lasagna de berenjena y champiñones', category: 'Plato Fuerte', price: 3.50, isVeggie: true),
      ],
    ),
    Restaurant(
      id: 'r3',
      name: 'El Rincón Manabita',
      description: 'Especialidad en mariscos y sazón manaba tradicional',
      featuredDish: 'Caldo de bola · Pescado frito con patacones',
      address: 'Av. Amazonas N22-48 y Calle Mariscal Foch',
      zone: 'La Mariscal',
      distanceKm: 1.4,
      singleLunchPrice: 3.50,
      planLunchPrice: 3.30,
      occupancy: 'LLENO',
      schedule: '11:30 - 16:00',
      tags: ['Mariscos frescos', 'Plátano verde', 'Porción generosa'],
      juice: 'Jugo de maracuyá',
      dessert: 'Cocada manaba',
      imageUrl:
          'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80',
      offers: [
        RestaurantOffer(
          id: 'of-r3-1',
          restaurantId: 'r3',
          title: 'Encebollado con jugo',
          badge: 'Flash · Quedan 5 cupos · hasta 14:00',
          price: 2.50,
          originalPrice: 3.50,
          slotsLeft: 5,
          reservable: true,
        ),
      ],
      todayMenu: [
        MenuItem(id: 'r3-s1', name: 'Caldo de bolas de verde con maní', category: 'Sopa'),
        MenuItem(id: 'r3-m1', name: 'Pescado frito con arroz y patacones', category: 'Plato Fuerte', price: 3.50),
      ],
    ),
    Restaurant(
      id: 'r4',
      name: 'Sazón Criolla',
      description: 'Almuerzo ejecutivo universitario junto a la USFQ',
      featuredDish: 'Sopa de lenteja · Lomo saltado criollo',
      address: 'Av. Pampite y Vía Interoceánica, edif. Platinum Plaza',
      zone: 'Cumbayá',
      distanceKm: 3.2,
      singleLunchPrice: 3.75,
      planLunchPrice: 3.40,
      occupancy: 'LIBRE',
      schedule: '12:00 - 16:00',
      tags: ['Almuerzos ejecutivos', 'Ambiente universitario', 'Rápido'],
      juice: 'Jugo de guanábana',
      dessert: 'Tres leches',
      takeawaySurcharge: 0.35,
      imageUrl:
          'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=800&q=80',
      todayMenu: [
        MenuItem(id: 'r4-s1', name: 'Sopa campesina de lenteja con queso', category: 'Sopa', isVeggie: true),
        MenuItem(id: 'r4-m1', name: 'Lomo saltado criollo con papas rústicas', category: 'Plato Fuerte', price: 3.75),
      ],
    ),
    Restaurant(
      id: 'r5',
      name: 'Don Vicho Almuerzos',
      description: 'El almuerzo rendidor y económico del sur de Quito',
      featuredDish: 'Sin menú publicado hoy',
      address: 'Av. Rodrigo de Chávez OE1-24 y 5 de Junio',
      zone: 'Villaflora',
      distanceKm: 6.1,
      singleLunchPrice: 2.75,
      planLunchPrice: 2.50,
      occupancy: 'LIBRE',
      isOpen: false,
      schedule: '11:00 - 14:30',
      tags: ['Económico', 'Sopa criolla'],
      takeawaySurcharge: 0.20,
      imageUrl:
          'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&q=80',
    ),
  ];
}
