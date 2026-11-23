import 'package:latlong2/latlong.dart';

import '../../../core/config/support_config.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/demo/demo_store.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import 'local_customer_cache.dart';

/// Implementación Mock de [ICustomerRepository] basada en los datos semilla del
/// prototipo React (`store.tsx`).
class MockCustomerRepository implements ICustomerRepository {
  final Duration networkLatency;
  final LocalCustomerCache _cache;
  bool shouldThrowError;

  /// Preórdenes, mesas y opiniones viven en [DemoStore] para que la caja del
  /// dueño las vea (O5, O12, O15).
  DemoStore get _store => DemoStore.instance;
  Map<String, SharedTable> get _tables => _store.tables;
  final DateTime _lastValidation = DateTime.now().subtract(const Duration(minutes: 30));
  bool _feedbackClosed = false;

  static const _hostName = 'Carlos Mejía';
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
        remainingLunches: _store.remainingLunchesByRest['r1'] ?? 14,
        expiresAt: now.add(const Duration(days: 27)),
        restaurantId: 'r1',
        restaurantName: 'La Cuchara de San Blas',
      ),
      CustomerPass(
        id: 'sub-2',
        userId: targetUserId,
        studentName: 'Carlos Mejía',
        planName: 'Mensual Saludable',
        totalLunches: 20,
        remainingLunches: _store.remainingLunchesByRest['r2'] ?? 6,
        expiresAt: now.add(const Duration(days: 12)),
        restaurantId: 'r2',
        restaurantName: 'Verde Limón',
      ),
    ];

    await _cache.savePass(passes.first);
    return passes;
  }

  Restaurant _withLiveGeoAndOccupancy(Restaurant r, LatLng userPos) {
    final overrideOcc = _store.occupancyOverrides[r.id];
    final hasOverrideUntil = _store.fullUntilByRest.containsKey(r.id);
    final overrideUntil = _store.fullUntilByRest[r.id];
    final effectiveOcc = overrideOcc ?? r.occupancy;
    final clearFullUntil = effectiveOcc != 'LLENO' ||
        (hasOverrideUntil && overrideUntil == null);
    final avail = _store.menuAvailabilityByRest[r.id] ??
        (_store.menuPublishedByRest[r.id] == false
            ? MenuAvailabilityState.sinPublicar
            : r.menuAvailabilityState);
    final soldOutDishes = _store.soldOutDishesByRest[r.id];
    final List<MenuItem> visibleMenu;
    if (avail == MenuAvailabilityState.sinPublicar) {
      visibleMenu = const <MenuItem>[];
    } else if (soldOutDishes == null && avail == MenuAvailabilityState.disponible) {
      visibleMenu = r.todayMenu;
    } else {
      visibleMenu = [
        for (final m in r.todayMenu)
          m.copyWith(
            isSoldOut: avail == MenuAvailabilityState.agotadoTotal ||
                (soldOutDishes?.contains(m.name) ?? m.isSoldOut),
          ),
      ];
    }
    final effectiveOpen = _store.storeOpenByRest[r.id] ?? r.isOpen;
    final now = DateTime.now();
    final liveOffers = [
      for (final o in r.offers)
        _withTaken(
          o.appliesToday && o.endsAt == null
              ? o.withEndsAt(_mockOfferEndsAt(o.id))
              : o,
        ),
      // Ofertas flash de un plato publicadas desde Caja del Dueño.
      for (final o in _store.flashOffers)
        if (o.restaurantId == r.id && o.isLiveAt(now))
          RestaurantOffer(
            id: o.id,
            restaurantId: r.id,
            title: o.dishName,
            badge: '-${o.discountPercent}% · ${o.dishName}',
            price: o.price,
            originalPrice: o.originalPrice,
            slotsLeft: o.slotsLeft,
            reservable: true,
            endsAt: o.endsAt,
          ),
    ];
    final filteredOffers = avail == MenuAvailabilityState.agotadoTotal
        ? [
            for (final o in liveOffers)
              if (!o.appliesToday) o,
          ]
        : liveOffers;
    if (!r.hasLocation) {
      return r.copyWith(
        occupancy: effectiveOcc,
        isOpen: effectiveOpen,
        fullUntil: overrideUntil,
        clearFullUntil: clearFullUntil,
        todayMenu: visibleMenu,
        offers: filteredOffers,
      );
    }
    final meters = LocationService.meters(userPos, LatLng(r.latitude!, r.longitude!));
    final km = (meters / 100.0).round() / 10.0;
    return r.copyWith(
      distanceMeters: meters,
      distanceKm: km,
      occupancy: effectiveOcc,
      isOpen: effectiveOpen,
      fullUntil: overrideUntil,
      clearFullUntil: clearFullUntil,
      todayMenu: visibleMenu,
      offers: filteredOffers,
    );
  }

  @override
  Future<List<Restaurant>> getRestaurants({
    String? query,
    String? category,
  }) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final (_, userPos) = await LocationService.resolveWithFallback();
    final mapped = [
      for (final r in _allRestaurants) _withLiveGeoAndOccupancy(r, userPos),
    ]..sort((a, b) => a.resolvedMeters.compareTo(b.resolvedMeters));
    return mapped;
  }

  @override
  Future<Restaurant?> getRestaurantById(String id) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final (_, userPos) = await LocationService.resolveWithFallback();
    for (final r in _allRestaurants) {
      if (r.id == id) return _withLiveGeoAndOccupancy(r, userPos);
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
    final table = await openSharedTable(restaurantId: 'r1', time: '13:00');
    return ActiveTable(
      id: table.id,
      restaurantName: table.restaurantName,
      time: table.time,
      membersCount: table.members.length,
      url: table.qrPayload,
    );
  }

  static String _occupancyLabel(String occupancy) => switch (occupancy) {
        'LLENO' => 'Lleno · Mejor llega un poco más tarde',
        'MOVIDO' => 'Movido · Puede haber una espera corta',
        _ => 'Fluido · Llegas y te sientas',
      };

  @override
  Future<SharedTable> openSharedTable({
    required String restaurantId,
    required String time,
    int partySize = 2,
    bool takeaway = false,
    TableMode mode = TableMode.eachOwn,
  }) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final scheduledAt = EcuadorTime.todayAtUtc(time);
    for (final t in _tables.values) {
      if (t.restaurantId == restaurantId && t.time == time) {
        final updated = t.copyWith(
          partySize: partySize,
          takeaway: takeaway,
          mode: mode,
          scheduledAt: scheduledAt,
        );
        _tables[t.id] = updated;
        _store.changed();
        return updated;
      }
    }
    final r = _allRestaurants.where((x) => x.id == restaurantId).firstOrNull ?? _allRestaurants.first;
    final soups = [for (final m in r.soups) m.name];
    final mains = [
      for (final m in r.mains)
        TableDish(id: m.id, name: m.name, price: m.price ?? r.singleLunchPrice, imageUrl: m.imageUrl, isVeggie: m.isVeggie),
    ];
    final id = _store.nextTableId();
    final table = SharedTable(
      id: id,
      restaurantId: r.id,
      restaurantName: r.name,
      hostName: _hostName,
      time: time,
      scheduledAt: scheduledAt,
      partySize: partySize < 2 ? 2 : partySize,
      takeaway: takeaway,
      mode: mode,
      qrPayload: BocadooQrParser.generateTableCode(id, restaurantId: r.id),
      // TODO: Definir el enlace de invitación de la app (ficha Fase 5, B12).
      shareUrl: 'https://bocadoo.ec/app/comensal/mesa/$id',
      occupancyLabel: _occupancyLabel(r.occupancy),
      soups: soups,
      mains: mains,
      takeawaySurcharge: r.takeawaySurcharge,
      members: [
        TableMember(
          id: 'mem-host',
          name: _hostName,
          isHost: true,
          soup: soups.firstOrNull,
          main: mains.firstOrNull?.name,
          takeaway: takeaway,
        ),
      ],
    );
    _tables[id] = table;
    _store.changed();
    return table;
  }

  @override
  Future<void> cancelSharedTable(String tableId) async {
    await _simulateNetwork();
    _tables.remove(tableId.toUpperCase());
    _tables.remove(tableId);
    _store.changed();
  }

  @override
  Future<SharedTable?> getSharedTable(String tableId) async {
    // TODO: Conectar con provider de backend
    if (_tables.isEmpty) await openSharedTable(restaurantId: 'r1', time: '13:00');
    await _simulateNetwork();
    return _tables[tableId.toUpperCase()];
  }

  SharedTable _update(String tableId, SharedTable Function(SharedTable t) change) {
    final current = _tables[tableId.toUpperCase()];
    if (current == null) throw Exception('La mesa ya no existe.');
    final next = change(current);
    _tables[current.id] = next;
    _store.changed();
    return next;
  }

  @override
  Future<SharedTable> setTableMode(String tableId, TableMode mode) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return _update(tableId, (t) => t.copyWith(mode: mode));
  }

  @override
  Future<SharedTable> notifyKitchen(String tableId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return _update(tableId, (t) => t.copyWith(onTheWay: true));
  }

  @override
  Future<SharedTable> joinTable(
    String tableId, {
    required String name,
    required String soup,
    required String main,
    required bool takeaway,
  }) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return _update(
      tableId,
      (t) => t.copyWith(members: [
        ...t.members,
        TableMember(
          id: 'mem-${t.members.length + 1}',
          name: name,
          soup: soup,
          main: main,
          takeaway: takeaway,
        ),
      ]),
    );
  }

  @override
  Future<List<PublicCartaItem>> getRestaurantCarta(String restaurantId) async {
    await _simulateNetwork();
    return const [
      PublicCartaItem(
        id: 'carta-1',
        name: 'Fritada tradicional con mote',
        category: 'A_LA_CARTA',
        priceCents: 650,
        order: 1,
        description: 'Carne de cerdo dorada con mote y tostado',
      ),
      PublicCartaItem(
        id: 'carta-2',
        name: 'Churrasco con papas y huevo',
        category: 'A_LA_CARTA',
        priceCents: 550,
        order: 2,
        description: 'Lomo a la plancha con papas fritas y ensalada',
      ),
      PublicCartaItem(
        id: 'beb-1',
        name: 'Jugo natural de naranjilla',
        category: 'BEBIDA',
        priceCents: 125,
        order: 1,
      ),
      PublicCartaItem(
        id: 'beb-2',
        name: 'Agua mineral sin gas',
        category: 'BEBIDA',
        priceCents: 75,
        order: 2,
      ),
      PublicCartaItem(
        id: 'ext-1',
        name: 'Porción de maduro frito',
        category: 'EXTRA',
        priceCents: 100,
        order: 1,
      ),
    ];
  }

  @override
  Future<SharedTable> updateTableSelection(
    String tableId, {
    required List<String> lunchDishIds,
    List<({String dishId, int quantity})> extras = const [],
  }) async {
    await _simulateNetwork();
    return _update(
      tableId,
      (t) {
        final menuById = <String, String>{};
        for (final d in t.mains) {
          menuById[d.id] = d.name;
        }
        final resolvedNames = [
          for (final id in lunchDishIds) menuById[id] ?? id,
        ];
        final sel = TableMemberSelection(
          lunchDishes: resolvedNames,
          soup: resolvedNames.length > 1 ? resolvedNames.first : null,
          main: resolvedNames.isNotEmpty ? resolvedNames.last : null,
          extras: [
            for (final e in extras)
              TableSelectionExtra(
                dishId: e.dishId,
                name: e.dishId,
                quantity: e.quantity,
              ),
          ],
        );
        if (t.members.isEmpty) return t;
        final updatedMembers = [...t.members];
        final idx = updatedMembers.lastIndexWhere((m) => m.id == 'self');
        final targetIdx = idx >= 0 ? idx : updatedMembers.length - 1;
        final m = updatedMembers[targetIdx];
        updatedMembers[targetIdx] = TableMember(
          id: m.id,
          name: m.name,
          isHost: m.isHost,
          soup: sel.soup ?? m.soup,
          main: sel.main ?? m.main,
          takeaway: m.takeaway,
          selection: sel,
        );
        return t.copyWith(members: updatedMembers);
      },
    );
  }

  @override
  Future<CustomerProfile> getProfile() async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    return const CustomerProfile(
      name: _hostName,
      phone: '0991234567',
      habitualPlanName: 'Plan mensual ejecutivo',
      habitualPlanIncludes: ['Sopa', 'Segundo', 'Bebida'],
      // Se define al compilar (--dart-define), ver SupportConfig.
      supportWhatsApp: SupportConfig.whatsApp,
    );
  }

  @override
  Future<PendingFeedback?> getPendingFeedback() async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    if (_feedbackClosed) return null;
    return PendingFeedback(
      redemptionId: 'red-1',
      restaurantId: 'r1',
      restaurantName: 'La Cuchara de San Blas',
      validatedAt: _lastValidation,
    );
  }

  @override
  Future<bool> submitFeedback(String redemptionId, {required String tag, String? note}) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    _feedbackClosed = true;
    _store.feedback.insert(
      0,
      DemoFeedback(
        id: _store.nextFeedbackId(),
        restaurantId: 'r1',
        dinerName: _hostName,
        tag: tag,
        note: note,
        createdAt: DateTime.now(),
      ),
    );
    _store.changed();
    return true;
  }

  @override
  Future<bool> dismissFeedback(String redemptionId) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    _feedbackClosed = true;
    return true;
  }

  @override
  Future<ActiveOrder?> getActiveOrder() async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final mine = _store.preorders.where((o) =>
        o.dinerUserId == DemoStore.dinerUserId &&
        (o.status == PreorderStatus.pending || o.status == PreorderStatus.delivered));
    return mine.isEmpty ? null : _toActiveOrder(mine.last);
  }

  static ActiveOrder _toActiveOrder(DemoPreorder o) => ActiveOrder(
        orderNumber: o.number,
        restaurantId: o.restaurantId,
        restaurantName: o.restaurantName,
        qrPayload: BocadooQrParser.generateOrderCode(
          o.number,
          orderId: o.number,
          restaurantId: o.restaurantId,
        ),
        status: o.status == PreorderStatus.delivered ? 'ENTREGADO' : 'PREPARANDO',
        detail: o.detail,
        soup: o.soup,
        main: o.main,
        takeaway: o.takeaway,
        takeawaySurcharge: o.takeawaySurcharge,
        singleLunchPrice: o.singleLunchPrice,
        basePriceCents: o.effectiveBaseCents,
        takeawaySurchargeCents: o.effectiveSurchargeCents,
        totalCents: o.effectiveTotalCents,
        estimatedArrivalLabel: o.estimatedArrivalLabel,
        hasPlan: o.hasPlan,
        planCreditsUsed: o.planCreditsUsed,
        cashToCollectCents: o.cashToCollectCents,
        expiresAt: o.expiresAt,
        paidAmount: o.status == PreorderStatus.delivered
            ? Money.fromCents(o.effectiveTotalCents)
            : null,
      );

  @override
  Future<bool> acknowledgeOrder(String orderNumber) async {
    // TODO: Conectar con provider de backend
    final order = _store.preorderByNumber(orderNumber);
    if (order == null) return false;
    order.status = PreorderStatus.acknowledged;
    _store.changed();
    return true;
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
  Future<OrderQuote?> quotePreorder({
    required String restaurantId,
    String? soupId,
    String? mainId,
    String? breakfastId,
    required bool takeaway,
    List<({String platoId, int quantity})> cartaItems = const [],
  }) async {
    await _simulateNetwork();
    final restaurant = await getRestaurantById(restaurantId);
    final carta = cartaItems.isEmpty
        ? const <PublicCartaItem>[]
        : await getRestaurantCarta(restaurantId);
    final cartaById = {for (final item in carta) item.id: item};
    final hasLunch = (soupId ?? '').isNotEmpty ||
        (mainId ?? '').isNotEmpty ||
        (breakfastId ?? '').isNotEmpty;
    final hasPlan = hasLunch &&
        (restaurantId == 'r1' || restaurantId == 'r2') &&
        (_store.remainingLunchesByRest[restaurantId] ?? 0) > 0;
    final baseCents = Money.toCents(restaurant?.singleLunchPrice ?? 3.00);
    final surchargeCents =
        takeaway ? Money.toCents(restaurant?.takeawaySurcharge ?? 0.25) : 0;

    final lines = <OrderQuoteLine>[];
    var subtotal = 0;
    var recargo = 0;
    var cubierto = 0;

    if (hasLunch) {
      subtotal += baseCents;
      recargo += surchargeCents;
      final planCov = hasPlan ? baseCents : 0;
      cubierto += planCov;
      lines.add(
        OrderQuoteLine(
          ref: hasPlan ? 'almuerzo#1' : 'almuerzo',
          tipo: 'ALMUERZO',
          nombre: 'Almuerzo',
          cantidad: 1,
          precioUnitarioCentavos: baseCents,
          subtotalCentavos: baseCents,
          recargoCentavos: surchargeCents,
          fuente: hasPlan ? 'PLAN' : 'CAJA',
          cubiertoPorPlanCentavos: planCov,
          porCobrarCentavos: (baseCents - planCov) + surchargeCents,
        ),
      );
    }

    for (var i = 0; i < cartaItems.length; i++) {
      final entry = cartaItems[i];
      final item = cartaById[entry.platoId];
      if (item == null || entry.quantity <= 0) continue;
      final sub = item.priceCents * entry.quantity;
      final itemRec =
          (takeaway && item.category.toUpperCase() == 'A_LA_CARTA')
              ? surchargeCents * entry.quantity
              : 0;
      subtotal += sub;
      recargo += itemRec;
      lines.add(
        OrderQuoteLine(
          ref: 'extra:$i',
          tipo: item.category,
          nombre: item.name,
          platoId: item.id,
          cantidad: entry.quantity,
          precioUnitarioCentavos: item.priceCents,
          subtotalCentavos: sub,
          recargoCentavos: itemRec,
          fuente: 'CAJA',
          cubiertoPorPlanCentavos: 0,
          porCobrarCentavos: sub + itemRec,
        ),
      );
    }

    final total = subtotal + recargo;
    return OrderQuote(
      estimada: true,
      subtotalCentavos: subtotal,
      recargoCentavos: recargo,
      totalCentavos: total,
      cubiertoPorPlanCentavos: cubierto,
      saldoPorCobrarCentavos: total - cubierto,
      lineas: lines,
    );
  }

  @override
  Future<ActiveOrder> preorder({
    required String restaurantId,
    String? soupId,
    String? mainId,
    String? breakfastId,
    String? offerId,
    required bool takeaway,
    String? estimatedArrival,
    List<({String platoId, int quantity})> cartaItems = const [],
  }) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    final restaurant = await getRestaurantById(restaurantId);
    final carta = cartaItems.isEmpty
        ? const <PublicCartaItem>[]
        : await getRestaurantCarta(restaurantId);
    var cartaCents = 0;
    final cartaLabels = <String>[];
    for (final line in cartaItems) {
      final item = carta.where((c) => c.id == line.platoId).firstOrNull;
      if (item == null || line.quantity <= 0) continue;
      if (item.isSoldOut) {
        throw ApiException(status: 409, code: 'PLATO_AGOTADO');
      }
      cartaCents += item.priceCents * line.quantity;
      cartaLabels.add(line.quantity > 1 ? '${line.quantity}x ${item.name}' : item.name);
    }
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

    final number = _store.nextOrderNumber();
    final breakfast = nameOf(breakfastId);
    final offerItem = offerId == null ? null : restaurant?.offers.where((o) => o.id == offerId).firstOrNull;
    final offer = offerItem?.title ?? '';
    final soup = nameOf(soupId);
    final main = nameOf(mainId);
    final price = offerItem?.price ?? restaurant?.singleLunchPrice ?? 3.00;
    final surcharge = restaurant?.takeawaySurcharge ?? 0.25;
    final baseCents = Money.toCents(price);
    final surchargeCents = Money.toCents(surcharge);
    final hasPlan = (restaurantId == 'r1' || restaurantId == 'r2') &&
        (_store.remainingLunchesByRest[restaurantId] ?? 0) > 0;
    final hasLunch = (soupId ?? '').isNotEmpty ||
        (mainId ?? '').isNotEmpty ||
        (breakfastId ?? '').isNotEmpty ||
        offerId != null;
    final lunchCents = hasLunch ? baseCents + (takeaway ? surchargeCents : 0) : 0;
    // Con plan, el almuerzo sale del cupo y solo la carta se paga en el local.
    final totalCents = (hasPlan && hasLunch ? 0 : lunchCents) + cartaCents;
    final now = DateTime.now();
    final resolvedEta = (estimatedArrival != null &&
            estimatedArrival.isNotEmpty &&
            estimatedArrival != 'En 15 min')
        ? estimatedArrival
        : () {
            final t = EcuadorTime.now().add(const Duration(minutes: 15));
            return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
          }();
    final record = DemoPreorder(
      number: number,
      restaurantId: restaurantId,
      restaurantName: restaurant?.name ?? 'Restaurante',
      dinerUserId: DemoStore.dinerUserId,
      dinerName: _hostName,
      detail: [...parts, ...cartaLabels].join(' · '),
      planCreditsUsed: hasPlan && hasLunch ? 1 : 0,
      cashToCollectCents: hasPlan ? cartaCents : 0,
      cashItems: cartaLabels,
      soup: soup.isEmpty ? null : soup,
      main: main.isNotEmpty ? main : (breakfast.isNotEmpty ? breakfast : (offer.isEmpty ? null : offer)),
      takeaway: takeaway,
      takeawaySurcharge: surcharge,
      singleLunchPrice: price,
      basePriceCents: baseCents,
      takeawaySurchargeCents: surchargeCents,
      totalCents: totalCents,
      estimatedArrivalLabel: resolvedEta,
      hasPlan: hasPlan,
      // Con plan prepagado no se cobra nada en caja.
      amount: Money.fromCents(totalCents),
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
    );
    if (offerId != null) {
      final stored = _store.flashOffers.where((o) => o.id == offerId).firstOrNull;
      if (stored != null) {
        if (!stored.isLiveAt(now)) {
          throw ApiException(status: 409, code: 'OFERTA_AGOTADA');
        }
        stored.slotsLeft -= 1;
      } else if (offerItem == null || !offerItem.isActiveFlashAt(now)) {
        throw ApiException(status: 409, code: 'OFERTA_AGOTADA');
      } else {
        _offerTaken[offerId] = (_offerTaken[offerId] ?? 0) + 1;
      }
    }
    _store.preorders.add(record);
    _store.changed();
    return _toActiveOrder(record);
  }

  @override
  Future<bool> cancelPreorder(String orderNumber) async {
    // TODO: Conectar con provider de backend
    await _simulateNetwork();
    _store.preorderByNumber(orderNumber)?.status = PreorderStatus.cancelled;
    _store.changed();
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
    PlanTemplate(id: 'p-quincenal', restaurantId: 'r1', type: 'Quincenal', name: 'Plan quincenal', lunches: 15, priceCents: 4200, validityDays: 18),
    PlanTemplate(id: 'p-mensual', restaurantId: 'r1', type: 'Mensual', name: 'Plan mensual ejecutivo', lunches: 20, priceCents: 5500, validityDays: 35),
    PlanTemplate(id: 'p-r2-semanal', restaurantId: 'r2', type: 'Semanal', name: 'Semanal Verde', lunches: 5, priceCents: 1600, validityDays: 7),
    PlanTemplate(id: 'p-r2-mensual', restaurantId: 'r2', type: 'Mensual', name: 'Mensual Saludable', lunches: 20, priceCents: 6000, validityDays: 35),
    PlanTemplate(id: 'p-r3-quincenal', restaurantId: 'r3', type: 'Quincenal', name: 'Quincenal Manaba', lunches: 15, priceCents: 4800, validityDays: 18),
    PlanTemplate(id: 'p-r3-mensual', restaurantId: 'r3', type: 'Mensual', name: 'Mensual Costeño', lunches: 20, priceCents: 6500, validityDays: 35),
    PlanTemplate(id: 'p-r4-mensual', restaurantId: 'r4', type: 'Mensual', name: 'Mensual USFQ', lunches: 20, priceCents: 6800, validityDays: 35),
  ];

  /// Fin simulado de cada oferta flash mock (estable durante la sesión).
  static final Map<String, DateTime> _mockOfferEnds = {};

  /// Cupos ya pedidos de las ofertas fijas del mock (las de Caja viven en DemoStore).
  static final Map<String, int> _offerTaken = {};

  static RestaurantOffer _withTaken(RestaurantOffer o) {
    final taken = _offerTaken[o.id] ?? 0;
    return taken > 0 ? o.withSlotsLeft(o.slotsLeft - taken) : o;
  }

  static DateTime _mockOfferEndsAt(String offerId) {
    final minutes = 20 + (offerId.hashCode.abs() % 40);
    return _mockOfferEnds.putIfAbsent(
      offerId,
      () => DateTime.now().add(Duration(minutes: minutes)),
    );
  }

  static const List<Restaurant> _allRestaurants = [
    Restaurant(
      id: 'r1',
      name: 'La Cuchara de San Blas',
      description: 'Comida casera tradicional frente a la PUCE',
      featuredDish: 'Comida casera tradicional frente a la PUCE',
      address: 'Av. 12 de Octubre N24-110 y La Católica',
      zone: 'Frente a la PUCE',
      distanceKm: 0.2,
      latitude: -0.2092,
      longitude: -78.4897,
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
      latitude: -0.2128,
      longitude: -78.4863,
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
      latitude: -0.2030,
      longitude: -78.4925,
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
      latitude: -0.1980,
      longitude: -78.4350,
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
      offers: [
        RestaurantOffer(
          id: 'of-r4-1',
          restaurantId: 'r4',
          title: 'Lomo saltado con jugo',
          badge: 'Flash · Quedan 8 cupos',
          price: 2.99,
          originalPrice: 3.75,
          slotsLeft: 8,
        ),
      ],
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
      latitude: -0.2450,
      longitude: -78.5210,
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
