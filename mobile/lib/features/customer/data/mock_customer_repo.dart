import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';
import 'local_customer_cache.dart';

/// Implementación Mock de [ICustomerRepository] basada en los datos y flujos
/// oficiales del PMV Web (Quito / PUCE).
class MockCustomerRepository implements ICustomerRepository {
  final Duration networkLatency;
  final LocalCustomerCache _cache;
  bool shouldThrowError;

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
    await _simulateNetwork();

    final targetUserId = userId ?? 'u1';
    final token = BocadooQrParser.generateQrPayload(targetUserId);

    final pass = CustomerPass(
      id: 'sub-1',
      userId: targetUserId,
      studentName: 'Carlos Mejía',
      studentCareer: 'Ing. de Sistemas · PUCE',
      planName: 'Plan Mensual Ejecutivo',
      totalLunches: 20,
      remainingLunches: 14,
      expiresAt: DateTime.now().add(const Duration(days: 29)),
      status: 'ACTIVO',
      qrToken: token,
      restaurantId: 'r1',
      restaurantName: 'La Cuchara de San Blas',
      avatarUrl:
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=300&q=80',
    );

    await _cache.savePass(pass);
    return pass;
  }

  @override
  Future<String> refreshQrToken(String passId) async {
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
    await _simulateNetwork();

    final list = _allRestaurants;

    return list.where((restaurant) {
      final matchesQuery = query == null ||
          query.trim().isEmpty ||
          restaurant.name.toLowerCase().contains(query.toLowerCase()) ||
          restaurant.zone.toLowerCase().contains(query.toLowerCase()) ||
          restaurant.description.toLowerCase().contains(query.toLowerCase());

      final matchesCategory = category == null ||
          category.isEmpty ||
          category == 'Todos' ||
          restaurant.categories.contains(category);

      return matchesQuery && matchesCategory;
    }).toList();
  }

  @override
  Future<Restaurant?> getRestaurantById(String id) async {
    await _simulateNetwork();
    try {
      return _allRestaurants.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MenuItem>> getTodayMenu(String restaurantId) async {
    await _simulateNetwork();
    final restaurant = await getRestaurantById(restaurantId);
    return restaurant?.todayMenu ?? _defaultMenu;
  }

  @override
  Future<List<ConsumptionRecord>> getConsumptionHistory(String passId) async {
    await _simulateNetwork();
    final now = DateTime.now();

    return [
      ConsumptionRecord(
        id: 'red-1',
        passId: passId,
        restaurantName: 'La Cuchara de San Blas',
        restaurantId: 'r1',
        date: now.subtract(const Duration(minutes: 25)),
        description: 'Locro de papa + Seco de pollo tierno',
        lunchesUsed: 1,
        remainingAfter: 14,
        status: 'Validado',
      ),
      ConsumptionRecord(
        id: 'red-2',
        passId: passId,
        restaurantName: 'La Cuchara de San Blas',
        restaurantId: 'r1',
        date: now.subtract(const Duration(days: 1, hours: 2)),
        description: 'Sopa criolla + Chuleta al grill con menestra',
        lunchesUsed: 1,
        remainingAfter: 15,
        status: 'Validado',
      ),
      ConsumptionRecord(
        id: 'red-3',
        passId: passId,
        restaurantName: 'La Cuchara de San Blas',
        restaurantId: 'r1',
        date: now.subtract(const Duration(days: 2, hours: 1)),
        description: 'Locro de papa + Bowl veggie de quinoa',
        lunchesUsed: 1,
        remainingAfter: 16,
        status: 'Validado',
      ),
      ConsumptionRecord(
        id: 'red-4',
        passId: passId,
        restaurantName: 'La Cuchara de San Blas',
        restaurantId: 'r1',
        date: now.subtract(const Duration(days: 5, hours: 3)),
        description: 'Crema de verduras + Seco de carne',
        lunchesUsed: 1,
        remainingAfter: 17,
        status: 'Validado',
      ),
      ConsumptionRecord(
        id: 'red-5',
        passId: passId,
        restaurantName: 'La Cuchara de San Blas',
        restaurantId: 'r1',
        date: now.subtract(const Duration(days: 6, hours: 4)),
        description: 'Sopa de fideo casera + Filete de pollo',
        lunchesUsed: 1,
        remainingAfter: 18,
        status: 'Validado',
      ),
    ];
  }

  @override
  Future<CustomerPass?> getCachedPass() async {
    return _cache.getPass();
  }

  @override
  Future<void> saveCachedPass(CustomerPass pass) async {
    await _cache.savePass(pass);
  }

  // --- Catálogo y Menús Semilla fieles al PMV Web ---

  static final List<MenuItem> _defaultMenu = [
    const MenuItem(
      id: 'd-sopa-1',
      name: 'Locro de papa con queso y aguacate',
      category: 'Sopa',
      price: null, // Incluido en el almuerzo
      isSoldOut: false,
      isVeggie: true,
      imageUrl:
          'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=600&q=80',
    ),
    const MenuItem(
      id: 'd-fuerte-1',
      name: 'Seco de pollo tierno con maduro frito',
      category: 'Plato Fuerte',
      price: 3.00,
      isSoldOut: false,
      isVeggie: false,
      imageUrl:
          'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?auto=format&fit=crop&w=600&q=80',
    ),
    const MenuItem(
      id: 'd-fuerte-2',
      name: 'Chuleta ahumada al grill con menestra',
      category: 'Plato Fuerte',
      price: 3.25,
      isSoldOut: false,
      isVeggie: false,
      imageUrl:
          'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=600&q=80',
    ),
    const MenuItem(
      id: 'd-fuerte-3',
      name: 'Bowl veggie de quinoa y champiñones',
      category: 'Plato Fuerte',
      price: 3.25,
      isSoldOut: false,
      isVeggie: true,
      imageUrl:
          'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=600&q=80',
    ),
    const MenuItem(
      id: 'd-jugo-1',
      name: 'Jugo natural de naranjilla',
      category: 'Bebida',
      price: null,
      isSoldOut: false,
      isVeggie: true,
      imageUrl:
          'https://images.unsplash.com/photo-1613478223719-2ab802602423?auto=format&fit=crop&w=600&q=80',
    ),
    const MenuItem(
      id: 'd-postre-1',
      name: 'Higos con queso fresco andino',
      category: 'Postre',
      price: 1.00,
      isSoldOut: true,
      isVeggie: true,
      imageUrl:
          'https://images.unsplash.com/photo-1551024709-8f23befc6f87?auto=format&fit=crop&w=600&q=80',
    ),
  ];

  static final List<Restaurant> _allRestaurants = [
    Restaurant(
      id: 'r1',
      name: 'La Cuchara de San Blas',
      description: 'Comida casera tradicional frente a la PUCE',
      address: 'Av. 12 de Octubre N24-110 y La Católica',
      zone: 'Frente a la PUCE',
      rating: 4.8,
      distanceKm: 0.2,
      singleLunchPrice: 3.00,
      planLunchPrice: 2.75,
      occupancy: 'Movido',
      isOpen: true,
      categories: const ['Todos', 'Ejecutivo', 'Cerca', 'Tradicional'],
      imageUrl:
          'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&q=80',
      todayMenu: _defaultMenu,
    ),
    Restaurant(
      id: 'r2',
      name: 'Verde Limón',
      description: 'Almuerzos saludables, ensaladas frescas y bowls',
      address: 'Calle Madrid 1159 y Coruña, La Floresta',
      zone: 'La Floresta',
      rating: 4.6,
      distanceKm: 0.8,
      singleLunchPrice: 3.25,
      planLunchPrice: 3.00,
      occupancy: 'Libre',
      isOpen: true,
      categories: const ['Todos', 'Veggie', 'Saludable', 'Cerca'],
      imageUrl:
          'https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=800&q=80',
      todayMenu: [
        const MenuItem(
          id: 'vl-sopa-1',
          name: 'Crema de espinaca con croutons',
          category: 'Sopa',
          isVeggie: true,
        ),
        const MenuItem(
          id: 'vl-fuerte-1',
          name: 'Pechuga a las finas hierbas con ensalada rusa',
          category: 'Plato Fuerte',
          price: 3.25,
          isVeggie: false,
        ),
        const MenuItem(
          id: 'vl-fuerte-2',
          name: 'Lasagna de berenjena y champiñones',
          category: 'Plato Fuerte',
          price: 3.50,
          isVeggie: true,
        ),
        const MenuItem(
          id: 'vl-jugo-1',
          name: 'Limonada de hierbabuena fría',
          category: 'Bebida',
          isVeggie: true,
        ),
      ],
    ),
    Restaurant(
      id: 'r3',
      name: 'El Rincón Manabita',
      description: 'Especialidad en mariscos y sazón manaba tradicional',
      address: 'Av. Amazonas N22-48 y Calle Mariscal Foch',
      zone: 'La Mariscal',
      rating: 4.7,
      distanceKm: 1.4,
      singleLunchPrice: 3.50,
      planLunchPrice: 3.30,
      occupancy: 'Lleno',
      isOpen: true,
      categories: const ['Todos', 'Ejecutivo', 'Tradicional'],
      imageUrl:
          'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80',
      todayMenu: [
        const MenuItem(
          id: 'rm-sopa-1',
          name: 'Caldo de bolas de verde con maní',
          category: 'Sopa',
          isVeggie: false,
        ),
        const MenuItem(
          id: 'rm-fuerte-1',
          name: 'Pescado frito con arroz, menestra y patacones',
          category: 'Plato Fuerte',
          price: 3.50,
          isVeggie: false,
        ),
        const MenuItem(
          id: 'rm-jugo-1',
          name: 'Jugo de maracuyá helado',
          category: 'Bebida',
          isVeggie: true,
        ),
      ],
    ),
    Restaurant(
      id: 'r4',
      name: 'Sazón Criolla',
      description: 'Almuerzo ejecutivo universitario junto a la USFQ',
      address: 'Av. Pampite y Vía Interoceánica, edif. Platinum Plaza',
      zone: 'Cumbayá',
      rating: 4.9,
      distanceKm: 3.2,
      singleLunchPrice: 3.75,
      planLunchPrice: 3.40,
      occupancy: 'Libre',
      isOpen: true,
      categories: const ['Todos', 'Ejecutivo'],
      imageUrl:
          'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=800&q=80',
      todayMenu: [
        const MenuItem(
          id: 'sc-sopa-1',
          name: 'Sopa campesina de lenteja con queso',
          category: 'Sopa',
          isVeggie: true,
        ),
        const MenuItem(
          id: 'sc-fuerte-1',
          name: 'Lomo saltado criollo con papas rústicas',
          category: 'Plato Fuerte',
          price: 3.75,
          isVeggie: false,
        ),
        const MenuItem(
          id: 'sc-jugo-1',
          name: 'Jugo de guanábana natural',
          category: 'Bebida',
          isVeggie: true,
        ),
      ],
    ),
  ];
}

