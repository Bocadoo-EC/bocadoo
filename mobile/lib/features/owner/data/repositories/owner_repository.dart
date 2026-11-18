import '../../../../core/contracts/models.dart';
import '../../../../core/contracts/repositories.dart';
import '../../../../core/demo/demo_store.dart';
import '../../domain/models/cash_models.dart';
import '../../domain/models/daily_menu.dart';
import '../../domain/models/menu_models.dart';
import '../../domain/repositories/i_owner_repository.dart';
import '../mock_owner_repo.dart';

/// Repositorio concreto del Dueño. Delega operaciones de QR/venta al
/// [MockOwnerRepository] y gestiona el menú diario y el catálogo en memoria.
/// Para pasar al backend real basta con reemplazar [_delegate] por un
/// [ApiOwnerRepository] y conectar [publishMenu] al endpoint correspondiente.
// TODO: Conectar con provider de backend
class OwnerRepository implements IOwnerRepository, IOwnerMenuRepository, IOwnerCatalogRepository {
  OwnerRepository({MockOwnerRepository? delegate})
      : _delegate = delegate ?? MockOwnerRepository();

  final MockOwnerRepository _delegate;

  DailyMenu? _todayMenu;
  int _dishSeq = 0;

  final List<CatalogDish> _dishes = [
    const CatalogDish(id: 'c-s1', name: 'Locro de papa con queso', kind: DishKind.sopa, topPick: true),
    const CatalogDish(id: 'c-s2', name: 'Sopa de lenteja', kind: DishKind.sopa),
    const CatalogDish(id: 'c-s3', name: 'Caldo de gallina criolla', kind: DishKind.sopa),
    const CatalogDish(id: 'c-s4', name: 'Crema de verduras', kind: DishKind.sopa),
    const CatalogDish(id: 'c-m1', name: 'Pollo a la plancha', kind: DishKind.segundo, topPick: true),
    const CatalogDish(id: 'c-m2', name: 'Seco de pollo con maduro', kind: DishKind.segundo),
    const CatalogDish(id: 'c-m3', name: 'Bowl de quinoa', kind: DishKind.segundo, veggie: true),
    const CatalogDish(id: 'c-m4', name: 'Trucha frita con ensalada', kind: DishKind.segundo),
    const CatalogDish(id: 'c-d1', name: 'Higos con queso', kind: DishKind.postre),
    const CatalogDish(id: 'c-d2', name: 'Dulce de zapallo', kind: DishKind.postre),
    const CatalogDish(id: 'c-b1', name: 'Jugo de naranjilla', kind: DishKind.bebida),
    const CatalogDish(id: 'c-b2', name: 'Jugo de mora', kind: DishKind.bebida),
    const CatalogDish(
      id: 'b-1',
      name: 'Desayuno criollo',
      kind: DishKind.desayuno,
      price: 2.50,
      breakfastCategory: BreakfastCategory.combo,
    ),
    const CatalogDish(
      id: 'b-2',
      name: 'Desayuno continental',
      kind: DishKind.desayuno,
      price: 2.50,
      breakfastCategory: BreakfastCategory.combo,
    ),
    const CatalogDish(
      id: 'b-3',
      name: 'Café pasado o chocolate caliente',
      kind: DishKind.desayuno,
      price: 0.75,
      breakfastCategory: BreakfastCategory.bebida,
    ),
    const CatalogDish(
      id: 'b-4',
      name: 'Huevos revueltos con queso',
      kind: DishKind.desayuno,
      price: 1.25,
      breakfastCategory: BreakfastCategory.proteina,
    ),
    const CatalogDish(
      id: 'b-5',
      name: 'Bolón mixto de verde',
      kind: DishKind.desayuno,
      price: 1.75,
      breakfastCategory: BreakfastCategory.pan,
    ),
    const CatalogDish(
        id: 'alc-1',
        name: 'Fritada tradicional con mote',
        kind: DishKind.carta,
        price: 6.50,
        description: 'Carne de cerdo dorada con mote, chulpi y tostado'),
    const CatalogDish(
        id: 'alc-2',
        name: 'Churrasco con papas y huevo',
        kind: DishKind.carta,
        price: 5.50,
        description: 'Lomo a la plancha con papas fritas y ensalada'),
    const CatalogDish(
        id: 'alc-3',
        name: 'Ceviche mixto de camarón',
        kind: DishKind.carta,
        price: 7.00,
        description: 'Con chifle, maíz tostado y aguacate'),
    const CatalogDish(
        id: 'alc-4',
        name: 'Trucha al ajillo con patacones',
        kind: DishKind.carta,
        price: 6.00,
        description: 'Trucha fresca en salsa de ajo con patacones'),
  ];

  // ── IOwnerRepository (delegado al mock) ────────────────────────────────────

  @override
  Future<ScanResult> validateQrCode(String rawPayload) =>
      _delegate.validateQrCode(rawPayload);

  @override
  Future<bool> confirmRedeem(String passId) =>
      _delegate.confirmRedeem(passId);

  @override
  Future<bool> sellPlan({
    required String studentIdentifier,
    required int lunchCount,
    required String paymentMethod,
    required double amount,
  }) =>
      _delegate.sellPlan(
        studentIdentifier: studentIdentifier,
        lunchCount: lunchCount,
        paymentMethod: paymentMethod,
        amount: amount,
      );

  @override
  Future<TransactionSummary> getDailyClosingSummary(String restaurantId) =>
      _delegate.getDailyClosingSummary(restaurantId);

  @override
  Future<List<TransactionItem>> getTodayTransactions(String restaurantId) =>
      _delegate.getTodayTransactions(restaurantId);

  // ── IOwnerMenuRepository ───────────────────────────────────────────────────

  Future<void> _syncDemoMenuState(DailyMenu? menu, {String? restaurantId}) async {
    final avail = menu?.availabilityState ?? MenuAvailabilityState.sinPublicar;
    final availableForOrders = avail == MenuAvailabilityState.disponible;
    final soldOutSet = {
      for (final c in menu?.courses ?? const <DailyMenuCourse>[])
        if (c.isSoldOut) c.name,
    };
    final store = DemoStore.instance;
    store.menuAvailabilityByRest[DemoStore.ownerRestaurantId] = avail;
    store.menuPublishedByRest[DemoStore.ownerRestaurantId] = availableForOrders;
    store.soldOutDishesByRest[DemoStore.ownerRestaurantId] = soldOutSet;

    final rid = menu?.restaurantId ?? restaurantId ?? '';
    if (rid.isNotEmpty) {
      store.menuAvailabilityByRest[rid] = avail;
      store.menuPublishedByRest[rid] = availableForOrders;
      store.soldOutDishesByRest[rid] = soldOutSet;
    }

    // Pausa/cancelación automática de Ofertas Flash si el menú entra en AGOTADO_TOTAL.
    if (avail == MenuAvailabilityState.agotadoTotal) {
      final activeOffer =
          await _delegate.getActiveOffer(rid.isNotEmpty ? rid : 'rest-001');
      if (activeOffer != null && activeOffer.kind == OfferKind.flash) {
        await _delegate.cancelOffer(rid.isNotEmpty ? rid : 'rest-001');
      }
    }
    store.changed();
  }

  @override
  Future<DailyMenu?> getTodayMenu(String restaurantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _todayMenu;
  }

  @override
  Future<DailyMenu?> getYesterdayMenu(String restaurantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _defaultYesterdayMenu(restaurantId);
  }

  @override
  Future<bool> publishMenu(DailyMenu menu) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _todayMenu = menu.copyWith(isPublished: true);
    await _syncDemoMenuState(_todayMenu);
    return true;
  }

  @override
  Future<bool> unpublishMenu(String restaurantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final menu = _todayMenu;
    if (menu == null) return false;
    _todayMenu = menu.copyWith(isPublished: false);
    await _syncDemoMenuState(_todayMenu, restaurantId: restaurantId);
    return true;
  }

  @override
  Future<bool> setCourseSoldOut(String restaurantId, String courseName, {required bool soldOut}) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final menu = _todayMenu;
    if (menu == null) return false;
    _todayMenu = menu.copyWith(courses: [
      for (final c in menu.courses) c.name == courseName ? c.copyWith(isSoldOut: soldOut) : c,
    ]);
    await _syncDemoMenuState(_todayMenu, restaurantId: restaurantId);
    return true;
  }

  // ── IOwnerCatalogRepository ────────────────────────────────────────────────

  @override
  Future<List<CatalogDish>> getDishes(String restaurantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return List.unmodifiable(_dishes);
  }

  @override
  Future<CatalogDish> addDish(
    String restaurantId, {
    required String name,
    required DishKind kind,
    double? price,
    String? description,
    bool veggie = false,
    BreakfastCategory? breakfastCategory,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final dish = CatalogDish(
      id: 'c-new-${++_dishSeq}',
      name: name,
      kind: kind,
      price: price,
      description: description ?? '',
      veggie: veggie,
      breakfastCategory: kind == DishKind.desayuno
          ? (breakfastCategory ?? BreakfastCategory.combo)
          : null,
    );
    _dishes.add(dish);
    return dish;
  }

  @override
  Future<void> setDishArchived(String restaurantId, String dishId, {required bool archived}) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final i = _dishes.indexWhere((d) => d.id == dishId);
    if (i >= 0) _dishes[i] = _dishes[i].copyWith(archived: archived);
  }

  @override
  Future<bool> setStoreOpen(String restaurantId, {required bool isOpen}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (_todayMenu != null) {
      _todayMenu = _todayMenu!.copyWith(isOpen: isOpen);
    }
    return true;
  }

  // ── Semilla de ayer ─────────────────────────────────────────────────────────

  static DailyMenu _defaultYesterdayMenu(String restaurantId) => DailyMenu(
        restaurantId: restaurantId,
        date: DateTime.now().subtract(const Duration(days: 1)),
        courses: const [
          DailyMenuCourse(
              id: 'y1', name: 'Locro de papa', category: 'Sopa'),
          DailyMenuCourse(
              id: 'y2', name: 'Pollo a la plancha', category: 'Fuerte'),
          DailyMenuCourse(
              id: 'y3', name: 'Jugo de naranjilla', category: 'Jugo'),
          DailyMenuCourse(
              id: 'y4', name: 'Higos con queso', category: 'Postre'),
        ],
        isPublished: true,
        isOpen: true,
      );
}
