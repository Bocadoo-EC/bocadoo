import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/demo/demo_store.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/polling.dart';
import '../../../core/session/session_notifier.dart';
import '../data/api_customer_repo.dart';
import '../data/mock_customer_repo.dart';
import '../data/pase_events_stream.dart';
import '../../group_orders/presentation/group_order_models.dart';
import '../../group_orders/presentation/group_order_simulation_provider.dart';
import 'widgets/flash_offers_sync.dart';
import 'widgets/menu_carta_sync.dart';
import 'widgets/restaurant_status_sync.dart';

enum CustomerStatus { initial, loading, success, error }

/// Qué QR muestra Mi Pase. El orden es la prioridad por defecto.
enum QrMode { preorden, mesa, plan }

/// Filtros de Dónde comer.
///
/// `near` es un filtro de zona (Planes/Mapa) que se combina con todo. Los
/// accesos rápidos ([fastService], [available], [withPlan], [offers]) son
/// excluyentes entre sí: tocar uno activo lo desactiva.
enum RestaurantFilter { near, fastService, available, withPlan, offers }

/// Filtros de acceso rápido de Dónde comer (excluyentes entre sí).
const quickAccessFilters = {
  RestaurantFilter.fastService,
  RestaurantFilter.available,
  RestaurantFilter.withPlan,
  RestaurantFilter.offers,
};

/// Banner de deshacer visible durante unos segundos.
@immutable
class UndoNotice {
  final String label;
  final int secondsLeft;

  const UndoNotice(this.label, this.secondsLeft);
}

@immutable
class CustomerUiState {
  final CustomerStatus status;
  final List<CustomerPass> passes;
  final int passIndex;
  final QrMode? selectedQrMode;
  final Map<String, StampCard> stampCards;
  final ActiveTable? activeTable;
  final ActiveOrder? activeOrder;
  final PendingFeedback? pendingFeedback;
  final List<ActivityItem> recentActivity;
  final List<Restaurant> restaurants;
  final String searchQuery;
  final Set<RestaurantFilter> filters;
  final LatLng? searchCenter;
  final String? searchZoneLabel;
  final int? searchRadiusMeters;
  final String? plansRestaurantId;
  final List<PlanTemplate> planTemplates;
  final bool isLoadingPlans;
  final UndoNotice? undo;
  final String? consumptionNotice;
  final int redemptionCelebrationTick;
  final String? redemptionCelebrationTitle;
  final String? redemptionCelebrationSubtitle;
  final String? errorMessage;
  final bool isOffline;
  final Map<String, bool> todayMenuPublishedByRest;
  final Map<String, MenuAvailabilityState> todayMenuAvailabilityByRest;

  const CustomerUiState({
    this.status = CustomerStatus.initial,
    this.passes = const [],
    this.passIndex = 0,
    this.selectedQrMode,
    this.stampCards = const {},
    this.activeTable,
    this.activeOrder,
    this.pendingFeedback,
    this.recentActivity = const [],
    this.restaurants = const [],
    this.searchQuery = '',
    this.filters = const {},
    this.searchCenter,
    this.searchZoneLabel,
    this.searchRadiusMeters,
    this.plansRestaurantId,
    this.planTemplates = const [],
    this.isLoadingPlans = false,
    this.undo,
    this.consumptionNotice,
    this.redemptionCelebrationTick = 0,
    this.redemptionCelebrationTitle,
    this.redemptionCelebrationSubtitle,
    this.errorMessage,
    this.isOffline = false,
    this.todayMenuPublishedByRest = const {},
    this.todayMenuAvailabilityByRest = const {},
  });

  bool get isLoading => status == CustomerStatus.loading;
  bool get isError => status == CustomerStatus.error;

  MenuAvailabilityState menuAvailabilityFor(String restaurantId) {
    if (todayMenuAvailabilityByRest.containsKey(restaurantId)) {
      return todayMenuAvailabilityByRest[restaurantId]!;
    }
    final rest = restaurantById(restaurantId);
    if (rest != null && rest.todayMenu.isNotEmpty) {
      return rest.menuAvailabilityState;
    }
    if (todayMenuPublishedByRest[restaurantId] == true) {
      return MenuAvailabilityState.disponible;
    }
    return MenuAvailabilityState.sinPublicar;
  }

  bool hasPublishedTodayMenu(String restaurantId) =>
      menuAvailabilityFor(restaurantId) == MenuAvailabilityState.disponible;

  CustomerPass? get currentPass =>
      passes.isEmpty ? null : passes[passIndex.clamp(0, passes.length - 1)];

  List<QrMode> get availableQrModes => [
        if (activeOrder != null) QrMode.preorden,
        if (activeTable != null) QrMode.mesa,
        if (passes.isNotEmpty) QrMode.plan,
      ];

  QrMode get qrMode {
    final modes = availableQrModes;
    if (selectedQrMode != null && modes.contains(selectedQrMode)) {
      return selectedQrMode!;
    }
    return modes.isEmpty ? QrMode.plan : modes.first;
  }

  String get qrValue => switch (qrMode) {
        QrMode.preorden => activeOrder?.qrPayload ?? '',
        QrMode.mesa => activeTable?.url ?? '',
        QrMode.plan => '',
      };

  /// Estado público efectivo del local (aforo, agotado, cerrado) para el feed.
  RestaurantPublicStatus publicStatusFor(Restaurant r) {
    var menuAvail = menuAvailabilityFor(r.id);
    if (r.isMenuSoldOutToday) menuAvail = MenuAvailabilityState.agotadoTotal;
    return resolveRestaurantPublicStatus(
      menuAvailability: menuAvail,
      manual: parseManualOccupancy(r.occupancy),
      isOpen: r.isOpen,
      fullUntil: r.fullUntil,
      ignoreClock: true,
    );
  }

  /// `true` si el local publicó su menú del día (aunque esté agotado).
  bool hasPublishedMenu(Restaurant r) =>
      menuAvailabilityFor(r.id) != MenuAvailabilityState.sinPublicar &&
      !(AppMode.useMock && r.todayMenu.isEmpty);

  /// El comensal tiene un plan prepagado activo en este local.
  bool userHasActivePlan(Restaurant r) => r.hasPlan || passFor(r.id) != null;

  /// Local con menú publicado, no agotado y abierto.
  bool _isOrderable(Restaurant r) {
    final st = publicStatusFor(r);
    return hasPublishedMenu(r) && !st.isSoldOutToday && !st.isClosed;
  }

  /// Prioridad de orden: Libre → Medio → Lleno → agotado / sin menú / cerrado.
  int _rankFor(Restaurant r) {
    if (!_isOrderable(r)) return 3;
    return switch (publicStatusFor(r).effective) {
      RestaurantEffectiveStatus.libre => 0,
      RestaurantEffectiveStatus.concurrido => 1,
      RestaurantEffectiveStatus.lleno => 2,
      _ => 3,
    };
  }

  /// Ofertas flash activas de todos los locales (con cupos y sin vencer).
  bool _isOfferDishSoldOut(Restaurant r, RestaurantOffer o) {
    if (r.todayMenu.isEmpty) return false;
    final soldOutNames = <String>{
      for (final m in r.todayMenu)
        if (m.isSoldOut) m.name.trim().toLowerCase(),
    };
    if (soldOutNames.isEmpty) return false;
    final parts = o.title.split(' + ').map((p) => p.trim().toLowerCase());
    return parts.any(soldOutNames.contains) ||
        soldOutNames.contains(o.title.trim().toLowerCase());
  }

  List<(Restaurant, RestaurantOffer)> activeFlashOffers([DateTime? at]) {
    final now = at ?? DateTime.now();
    return [
      for (final r in restaurants)
        if (!publicStatusFor(r).isSoldOutToday && !publicStatusFor(r).isClosed)
          for (final o in r.offers)
            if (o.isActiveFlashAt(now) && !_isOfferDishSoldOut(r, o)) (r, o),
    ];
  }

  /// Ofertas flash activas filtradas por la dirección/zona activa del comensal.
  List<(Restaurant, RestaurantOffer)> activeZoneFlashOffers([DateTime? at]) {
    final now = at ?? DateTime.now();
    return [
      for (final r in restaurants)
        if (_matchesActiveZone(r) &&
            !publicStatusFor(r).isSoldOutToday &&
            !publicStatusFor(r).isClosed)
          for (final o in r.offers)
            if (o.isActiveFlashAt(now) && !_isOfferDishSoldOut(r, o)) (r, o),
    ];
  }

  bool _matchesActiveZone(Restaurant r) {
    if (filters.contains(RestaurantFilter.near) && r.distanceKm >= 1.0) {
      return false;
    }
    if (searchCenter != null && searchRadiusMeters != null) {
      if (!r.hasLocation) return false;
      final meters = LocationService.meters(
        searchCenter!,
        LatLng(r.latitude!, r.longitude!),
      );
      if (meters > searchRadiusMeters!) return false;
    }
    return true;
  }

  List<Restaurant> get filteredRestaurants {
    final q = searchQuery.trim().toLowerCase();
    final now = DateTime.now();
    final matches = restaurants.where((r) {
      if (q.isNotEmpty) {
        final matchesText = r.name.toLowerCase().contains(q) ||
            r.featuredDish.toLowerCase().contains(q) ||
            r.zone.toLowerCase().contains(q) ||
            r.todayMenu.any(
              (m) => !m.isSoldOut && m.name.toLowerCase().contains(q),
            ) ||
            r.offers.any((o) => o.title.toLowerCase().contains(q));
        if (!matchesText) return false;
      }
      if (filters.contains(RestaurantFilter.near) && r.distanceKm >= 1.0) {
        return false;
      }
      if (searchCenter != null && searchRadiusMeters != null) {
        if (!r.hasLocation) return false;
        final meters = LocationService.meters(
          searchCenter!,
          LatLng(r.latitude!, r.longitude!),
        );
        if (meters > searchRadiusMeters!) return false;
      }
      // Atención rápida: Libre/Medio, o Lleno solo si el usuario tiene plan.
      if (filters.contains(RestaurantFilter.fastService)) {
        if (!_isOrderable(r)) return false;
        final effective = publicStatusFor(r).effective;
        final openSeats = effective == RestaurantEffectiveStatus.libre ||
            effective == RestaurantEffectiveStatus.concurrido;
        final vipFull = effective == RestaurantEffectiveStatus.lleno &&
            userHasActivePlan(r);
        if (!openSeats && !vipFull) return false;
      }
      // Disponibles: menú publicado y no agotado (Libre, Medio y Lleno).
      if (filters.contains(RestaurantFilter.available) && !_isOrderable(r)) {
        return false;
      }
      // Con mi plan: sin importar el aforo.
      if (filters.contains(RestaurantFilter.withPlan) && !userHasActivePlan(r)) {
        return false;
      }
      // Ofertas: al menos una flash vigente o una oferta semanal.
      if (filters.contains(RestaurantFilter.offers) &&
          !r.offers.any((o) => o.isLiveAt(now))) {
        return false;
      }
      return true;
    }).toList();

    // Orden estable por aforo (conserva el orden de cercanía dentro de cada grupo).
    final indexed = [for (var i = 0; i < matches.length; i++) (i, matches[i])]
      ..sort((a, b) {
        final byRank = _rankFor(a.$2).compareTo(_rankFor(b.$2));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  CustomerPass? passFor(String restaurantId) {
    CustomerPass? fallback;
    for (final p in passes) {
      if (p.restaurantId != restaurantId) continue;
      if (p.remainingLunches > 0 && !p.isExpired) return p;
      fallback ??= p;
    }
    return fallback;
  }

  Restaurant? restaurantById(String id) {
    for (final r in restaurants) {
      if (r.id == id) return r;
    }
    return null;
  }

  CustomerUiState copyWith({
    CustomerStatus? status,
    List<CustomerPass>? passes,
    int? passIndex,
    QrMode? selectedQrMode,
    Map<String, StampCard>? stampCards,
    ActiveTable? activeTable,
    bool clearActiveTable = false,
    ActiveOrder? activeOrder,
    bool clearActiveOrder = false,
    bool clearPendingFeedback = false,
    List<ActivityItem>? recentActivity,
    List<Restaurant>? restaurants,
    String? searchQuery,
    Set<RestaurantFilter>? filters,
    LatLng? searchCenter,
    String? searchZoneLabel,
    int? searchRadiusMeters,
    bool clearSearchArea = false,
    String? plansRestaurantId,
    List<PlanTemplate>? planTemplates,
    bool? isLoadingPlans,
    UndoNotice? undo,
    bool clearUndo = false,
    String? consumptionNotice,
    bool clearConsumptionNotice = false,
    int? redemptionCelebrationTick,
    String? redemptionCelebrationTitle,
    String? redemptionCelebrationSubtitle,
    String? errorMessage,
    bool? isOffline,
    Map<String, bool>? todayMenuPublishedByRest,
    Map<String, MenuAvailabilityState>? todayMenuAvailabilityByRest,
  }) {
    return CustomerUiState(
      status: status ?? this.status,
      passes: passes ?? this.passes,
      passIndex: passIndex ?? this.passIndex,
      selectedQrMode: selectedQrMode ?? this.selectedQrMode,
      stampCards: stampCards ?? this.stampCards,
      activeTable: clearActiveTable ? null : activeTable ?? this.activeTable,
      activeOrder: clearActiveOrder ? null : activeOrder ?? this.activeOrder,
      pendingFeedback: clearPendingFeedback ? null : pendingFeedback,
      recentActivity: recentActivity ?? this.recentActivity,
      restaurants: restaurants ?? this.restaurants,
      searchQuery: searchQuery ?? this.searchQuery,
      filters: filters ?? this.filters,
      searchCenter: clearSearchArea ? null : (searchCenter ?? this.searchCenter),
      searchZoneLabel:
          clearSearchArea ? null : (searchZoneLabel ?? this.searchZoneLabel),
      searchRadiusMeters:
          clearSearchArea ? null : (searchRadiusMeters ?? this.searchRadiusMeters),
      plansRestaurantId: plansRestaurantId ?? this.plansRestaurantId,
      planTemplates: planTemplates ?? this.planTemplates,
      isLoadingPlans: isLoadingPlans ?? this.isLoadingPlans,
      undo: clearUndo ? null : undo ?? this.undo,
      consumptionNotice: clearConsumptionNotice
          ? null
          : consumptionNotice ?? this.consumptionNotice,
      redemptionCelebrationTick:
          redemptionCelebrationTick ?? this.redemptionCelebrationTick,
      redemptionCelebrationTitle:
          redemptionCelebrationTitle ?? this.redemptionCelebrationTitle,
      redemptionCelebrationSubtitle:
          redemptionCelebrationSubtitle ?? this.redemptionCelebrationSubtitle,
      errorMessage: errorMessage,
      isOffline: isOffline ?? this.isOffline,
      todayMenuPublishedByRest:
          todayMenuPublishedByRest ?? this.todayMenuPublishedByRest,
      todayMenuAvailabilityByRest:
          todayMenuAvailabilityByRest ?? this.todayMenuAvailabilityByRest,
    );
  }
}

/// Estado del módulo Comensal compartido por Mi Pase, Dónde comer y Planes.
class CustomerController extends ChangeNotifier {
  final ICustomerRepository _repository;
  CustomerUiState _state = const CustomerUiState();
  Timer? _undoTimer;
  Future<void> Function()? _undoAction;
  LifecyclePollingController? _orderPoller;
  LifecyclePollingController? _restaurantsPoller;
  bool _disposed = false;
  bool _paseVisible = false;
  bool _restaurantsVisible = false;
  bool _refreshingRestaurants = false;
  bool _ssePausedByReplacement = false;
  CancelToken? _sseCancelToken;
  StreamSubscription<PaseSseEvent>? _sseSub;
  Timer? _sseReconnectTimer;
  Timer? _sseFallbackPoller;
  int _sseRetryAttempt = 0;

  /// Último mensaje de error en una acción (preorden o solicitud de plan).
  String? lastActionError;

  /// Código de error de máquina del último fallo (`LOCAL_LLENO_SOLO_LLEVAR`, `RESTAURANTE_PAUSADO`, etc.).
  String? lastActionErrorCode;

  /// `true` si el último fallo fue `409 Conflict` (un ítem se agotó justo ahora).
  bool lastActionConflict = false;

  CustomerController({ICustomerRepository? repository})
      : _repository = repository ?? MockCustomerRepository() {
    if (AppMode.useMock) {
      DemoStore.instance.addListener(_onDemoStoreChanged);
    }
    FlashOffersLiveSync.instance.addListener(_onFlashOfferLiveSync);
    RestaurantStatusLiveSync.instance.addListener(_onRestaurantStatusLiveSync);
    MenuAndCartaLiveSync.instance.addListener(_onMenuCartaLiveSync);
  }

  void _onMenuCartaLiveSync() {
    if (_disposed) return;
    final rid = MenuAndCartaLiveSync.instance.lastRestaurantId;
    if (rid == null || rid.isEmpty) return;
    if (!AppMode.useMock) {
      unawaited(_hydrateSingleRestaurant(rid));
    }
  }

  void _onRestaurantStatusLiveSync() {
    if (_disposed) return;
    final sync = RestaurantStatusLiveSync.instance;
    final rid = sync.lastRestaurantId;
    final status = sync.lastStatus;
    if (rid == null || rid.isEmpty || status == null) return;

    final occ = switch (status) {
      ManualOccupancyStatus.libre => 'LIBRE',
      ManualOccupancyStatus.concurrido => 'MOVIDO',
      ManualOccupancyStatus.lleno => 'LLENO',
      ManualOccupancyStatus.cerrado => 'CERRADO',
    };
    final isOpen = status != ManualOccupancyStatus.cerrado;
    final until = status == ManualOccupancyStatus.lleno ? sync.lastUntil : null;

    final updatedList = <Restaurant>[
      for (final r in _state.restaurants)
        if (r.id == rid)
          r.copyWith(
            occupancy: occ,
            isOpen: isOpen,
            openNow: isOpen,
            status: isOpen ? 'ACTIVO' : 'PAUSADO',
            fullUntil: until,
            clearFullUntil: until == null,
          )
        else
          r,
    ];
    _emit(_state.copyWith(restaurants: updatedList));
    if (!AppMode.useMock) {
      unawaited(_hydrateSingleRestaurant(rid));
    }
  }

  void _onFlashOfferLiveSync() {
    if (_disposed) return;
    final sync = FlashOffersLiveSync.instance;
    final rid = sync.lastRestaurantId;
    if (rid == null || rid.isEmpty) return;
    final offer = sync.lastOffer;
    if (offer != null) {
      final updatedList = <Restaurant>[
        for (final r in _state.restaurants)
          if (r.id == rid)
            r.copyWith(
              offers: sync.lastRemoved
                  ? r.offers.where((o) => o.id != offer.id).toList()
                  : [
                      offer,
                      for (final o in r.offers)
                        if (o.id != offer.id) o,
                    ],
            )
          else
            r,
      ];
      _emit(_state.copyWith(restaurants: updatedList));
    }
    if (!AppMode.useMock) {
      unawaited(_hydrateSingleRestaurant(rid));
    }
  }

  Future<void> _hydrateSingleRestaurant(String rid) async {
    try {
      final detail = await _repository.getRestaurantById(rid);
      if (detail == null || _disposed) return;
      syncRestaurantSummary(detail);
    } catch (_) {}
  }

  CustomerUiState get state => _state;

  void _emit(CustomerUiState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// Activa o pausa la sincronización asíncrona cada 25 s y al volver de
  /// segundo plano mientras la pestaña **Restaurantes** está visible.
  void setRestaurantsVisible(bool visible) {
    _restaurantsVisible = visible;
    if (visible) {
      _restaurantsPoller ??= LifecyclePollingController(
        interval: const Duration(seconds: 5),
        onTick: () => refreshRestaurants(forceHydrate: true),
      );
      if (!_restaurantsPoller!.isRunning) {
        try {
          _restaurantsPoller!.start();
        } catch (_) {}
      }
      if (_state.status == CustomerStatus.success) {
        unawaited(refreshRestaurants());
      }
    } else {
      _restaurantsPoller?.stop();
    }
  }

  /// Refresco silencioso en segundo plano para `GET /v1/restaurantes` + menú
  /// sin mostrar loaders bloqueantes ni perder scroll o filtros activos.
  Future<void> refreshRestaurants({bool forceHydrate = false}) async {
    if (_disposed || _refreshingRestaurants) return;
    _refreshingRestaurants = true;
    try {
      final freshCards = await _repository.getRestaurants();
      if (_disposed) return;
      final prevById = {for (final r in _state.restaurants) r.id: r};
      final merged = <Restaurant>[
        for (final card in freshCards)
          () {
            final prev = prevById[card.id];
            if (prev == null) return card;
            return card.copyWith(
              planLunchPrice: card.planLunchPrice ?? prev.planLunchPrice,
              todayMenu: card.todayMenu.isNotEmpty ? card.todayMenu : prev.todayMenu,
              // En mock el feed es la fuente completa: una oferta cerrada o
              // pausada por el Dueño debe desaparecer también si queda vacía.
              offers: AppMode.useMock || card.offers.isNotEmpty
                  ? card.offers
                  : prev.offers,
            );
          }(),
      ];

      final nextAvail = Map<String, MenuAvailabilityState>.from(
        _state.todayMenuAvailabilityByRest,
      );
      final nextPub = Map<String, bool>.from(_state.todayMenuPublishedByRest);
      for (final r in merged) {
        if (r.todayMenu.isNotEmpty) {
          final avail = r.menuAvailabilityState;
          nextAvail[r.id] = avail;
          nextPub[r.id] = avail == MenuAvailabilityState.disponible;
        }
      }

      _emit(_state.copyWith(
        restaurants: merged,
        isOffline: false,
        todayMenuAvailabilityByRest: nextAvail,
        todayMenuPublishedByRest: nextPub,
      ));
      if (!AppMode.useMock && (_restaurantsVisible || forceHydrate)) {
        unawaited(_hydrateRestaurants(merged, force: true));
      }
    } catch (_) {
      // Mantiene el último estado mostrado y reintenta en el siguiente ciclo.
    } finally {
      _refreshingRestaurants = false;
    }
  }

  void _onDemoStoreChanged() {
    if (_disposed || !AppMode.useMock) return;
    final store = DemoStore.instance;
    final nextMenuMap = Map<String, bool>.from(_state.todayMenuPublishedByRest)
      ..addAll(store.menuPublishedByRest);
    final nextAvailMap = Map<String, MenuAvailabilityState>.from(
      _state.todayMenuAvailabilityByRest,
    );
    for (final e in store.menuPublishedByRest.entries) {
      nextAvailMap[e.key] = store.menuAvailabilityByRest[e.key] ??
          (e.value
              ? MenuAvailabilityState.disponible
              : MenuAvailabilityState.sinPublicar);
    }
    for (final e in store.menuAvailabilityByRest.entries) {
      nextAvailMap[e.key] = e.value;
      nextMenuMap[e.key] = e.value == MenuAvailabilityState.disponible;
    }
    final updatedPasses = [
      for (final p in _state.passes)
        p.copyWith(
          remainingLunches:
              store.remainingLunchesByRest[p.restaurantId] ?? p.remainingLunches,
        ),
    ];
    _emit(_state.copyWith(
      passes: updatedPasses,
      todayMenuPublishedByRest: nextMenuMap,
      todayMenuAvailabilityByRest: nextAvailMap,
    ));
    unawaited(_refreshMockRestaurants());
  }

  Future<void> _refreshMockRestaurants() async {
    if (_disposed || !AppMode.useMock) return;
    try {
      final restaurants = await _repository.getRestaurants();
      if (_disposed) return;
      final nextAvail = Map<String, MenuAvailabilityState>.from(
        _state.todayMenuAvailabilityByRest,
      );
      final nextPub = Map<String, bool>.from(_state.todayMenuPublishedByRest);
      for (final r in restaurants) {
        final avail = r.menuAvailabilityState;
        nextAvail[r.id] = avail;
        nextPub[r.id] = avail == MenuAvailabilityState.disponible;
      }
      _emit(_state.copyWith(
        restaurants: restaurants,
        todayMenuAvailabilityByRest: nextAvail,
        todayMenuPublishedByRest: nextPub,
      ));
    } catch (_) {}
  }

  Future<
      ({
        Map<String, bool> published,
        Map<String, MenuAvailabilityState> availability,
      })> _resolveMenuStatesForPasses(
    List<CustomerPass> passes,
    List<Restaurant> restaurants,
  ) async {
    final pubMap = Map<String, bool>.from(_state.todayMenuPublishedByRest);
    final availMap =
        Map<String, MenuAvailabilityState>.from(_state.todayMenuAvailabilityByRest);
    if (AppMode.useMock) {
      final store = DemoStore.instance;
      for (final e in store.menuPublishedByRest.entries) {
        pubMap[e.key] = e.value;
        availMap[e.key] = store.menuAvailabilityByRest[e.key] ??
            (e.value
                ? MenuAvailabilityState.disponible
                : MenuAvailabilityState.sinPublicar);
      }
      for (final e in store.menuAvailabilityByRest.entries) {
        availMap[e.key] = e.value;
        pubMap[e.key] = e.value == MenuAvailabilityState.disponible;
      }
      return (published: pubMap, availability: availMap);
    }

    final repo = _repository;
    final ids = <String>{
      for (final p in passes)
        if (p.restaurantId.isNotEmpty) p.restaurantId,
    };
    if (ids.isEmpty) return (published: pubMap, availability: availMap);

    await Future.wait([
      for (final rid in ids)
        () async {
          try {
            final detail = await _repository.getRestaurantById(rid);
            if (detail != null) {
              if (repo is ApiCustomerRepository) {
                final avail = repo.cachedTodayMenuAvailability(rid) ??
                    detail.menuAvailabilityState;
                availMap[rid] = avail;
                pubMap[rid] = repo.cachedTodayMenuPublished(rid) ??
                    (avail == MenuAvailabilityState.disponible);
              } else {
                final avail = detail.menuAvailabilityState;
                availMap[rid] = avail;
                pubMap[rid] = avail == MenuAvailabilityState.disponible;
              }
            }
          } catch (_) {
            if (repo is ApiCustomerRepository) {
              final cachedAvail = repo.cachedTodayMenuAvailability(rid);
              if (cachedAvail != null) {
                availMap[rid] = cachedAvail;
                pubMap[rid] = cachedAvail == MenuAvailabilityState.disponible;
              } else {
                final cached = repo.cachedTodayMenuPublished(rid);
                if (cached != null) pubMap[rid] = cached;
              }
            }
          }
        }(),
    ]);
    return (published: pubMap, availability: availMap);
  }

  Future<void> loadDashboard({bool silent = false}) async {
    if (!silent) {
      _emit(_state.copyWith(status: CustomerStatus.loading));
    }

    try {
      final cached = await _repository.getCachedPass();
      if (cached != null && _state.passes.isEmpty) {
        _emit(_state.copyWith(passes: [cached]));
      }

      // Dispara en paralelo los recursos principales; los secundarios no tumban la carga.
      final passesFuture = _repository.getActivePasses();
      final restaurantsFuture = _repository.getRestaurants();
      final tableFuture = _repository
          .getActiveTable()
          .then<ActiveTable?>((v) => v, onError: (_) => _state.activeTable);
      final orderFuture = _repository
          .getActiveOrder()
          .then<ActiveOrder?>((v) => v, onError: (_) => _state.activeOrder);
      final activityFuture = _repository
          .getRecentActivity()
          .then<List<ActivityItem>>(
            (v) => v,
            onError: (_) => _state.recentActivity,
          );
      final feedbackFuture = _repository
          .getPendingFeedback()
          .then<PendingFeedback?>(
            (v) => v,
            onError: (_) => _state.pendingFeedback,
          );

      final passes = await passesFuture;
      final restaurants = await restaurantsFuture;
      final table = await tableFuture;
      final order = await orderFuture;
      final activity = await activityFuture;
      final feedback = await feedbackFuture;
      final effectiveTable = _pruneExpiredCollectingTable(table);

      final stamps = <String, StampCard>{};
      final menuStatesFuture = _resolveMenuStatesForPasses(passes, restaurants);
      await Future.wait([
        for (final p in passes)
          _repository.getStampCard(p.restaurantId).then((card) {
            if (card != null) stamps[p.restaurantId] = card;
          }, onError: (_) {}),
      ]);
      final menuStates = await menuStatesFuture;

      _emit(CustomerUiState(
        status: CustomerStatus.success,
        passes: passes,
        passIndex: _state.passIndex.clamp(0, passes.isEmpty ? 0 : passes.length - 1),
        selectedQrMode: _state.selectedQrMode,
        stampCards: stamps,
        activeTable: effectiveTable,
        activeOrder: order,
        pendingFeedback: feedback,
        recentActivity: activity,
        restaurants: restaurants,
        searchQuery: _state.searchQuery,
        filters: _state.filters,
        searchCenter: _state.searchCenter,
        searchZoneLabel: _state.searchZoneLabel,
        searchRadiusMeters: _state.searchRadiusMeters,
        plansRestaurantId: _state.plansRestaurantId,
        planTemplates: _state.planTemplates,
        undo: _state.undo,
        todayMenuPublishedByRest: menuStates.published,
        todayMenuAvailabilityByRest: menuStates.availability,
      ));
      if (restaurants.isNotEmpty) {
        final targetId = _state.plansRestaurantId != null &&
                restaurants.any((r) => r.id == _state.plansRestaurantId)
            ? _state.plansRestaurantId!
            : restaurants.first.id;
        unawaited(selectPlansRestaurant(targetId));
      }
      _syncOrderPolling(
        order,
        table: table,
        passes: passes,
        menuPublishedByRest: menuStates.published,
      );
      unawaited(_hydrateRestaurants(restaurants, force: silent));
    } catch (e) {
      if (_state.passes.isNotEmpty) {
        _emit(_state.copyWith(status: CustomerStatus.success, isOffline: true));
      } else {
        final msg = e is ApiException
            ? e.userMessage
            : e.toString().replaceFirst('Exception: ', '');
        _emit(_state.copyWith(
          status: CustomerStatus.error,
          isOffline: false,
          errorMessage: msg,
        ));
      }
    }
  }

  /// Vuelve a leer lo que puede cambiar desde la caja (pedido entregado,
  /// mesa cobrada o publicación del menú del día) sin mostrar carga.
  Future<void> refreshLive() async {
    if (_state.status != CustomerStatus.success) return;
    try {
      final previousOrder = _state.activeOrder;
      final previousTable = _state.activeTable;
      final order = await _repository.getActiveOrder();
      final table = await _repository.getActiveTable();
      final orderJustFinished = (previousOrder != null && order == null) ||
          (order != null &&
              order.isDelivered &&
              !(previousOrder?.isDelivered ?? false));
      final tableJustFinished = previousTable != null && table == null;

      List<CustomerPass>? updatedPasses;
      List<ActivityItem>? updatedActivity;
      if (orderJustFinished || tableJustFinished) {
        try {
          updatedPasses = await _repository.getActivePasses();
          updatedActivity = await _repository.getRecentActivity();
        } catch (_) {}
      }

      final activePasses = updatedPasses ?? _state.passes;
      final nextMenuStates = await _resolveMenuStatesForPasses(
        activePasses,
        _state.restaurants,
      );

      String? notice;
      String? celebrationTitle;
      String? celebrationSubtitle;
      var celebrationTick = _state.redemptionCelebrationTick;
      if (orderJustFinished && previousOrder != null) {
        notice = previousOrder.hasPlan
            ? 'Almuerzo confirmado en ${previousOrder.restaurantName} (-1 de tu plan).'
            : 'Pedido #${previousOrder.orderNumber} confirmado en ${previousOrder.restaurantName}.';
        celebrationTick += 1;
        celebrationTitle = '¡Orden aprobada!';
        celebrationSubtitle = previousOrder.hasPlan
            ? (previousOrder.cashToCollectCents > 0
                ? '${previousOrder.restaurantName} · -1 cupo de tu plan + adicionales confirmados'
                : '${previousOrder.restaurantName} · Descontado 1 almuerzo de tu plan')
            : '${previousOrder.restaurantName} · Pedido #${previousOrder.orderNumber} confirmado';
      }

      final effectiveTable = _pruneExpiredCollectingTable(table);
      _emit(_state.copyWith(
        passes: activePasses,
        recentActivity: updatedActivity,
        activeOrder: order,
        clearActiveOrder: order == null,
        activeTable: effectiveTable,
        clearActiveTable: effectiveTable == null,
        consumptionNotice: notice,
        redemptionCelebrationTick: celebrationTick,
        redemptionCelebrationTitle: celebrationTitle,
        redemptionCelebrationSubtitle: celebrationSubtitle,
        todayMenuPublishedByRest: nextMenuStates.published,
        todayMenuAvailabilityByRest: nextMenuStates.availability,
      ));
      _syncOrderPolling(
        order,
        table: table,
        passes: activePasses,
        menuPublishedByRest: nextMenuStates.published,
      );
    } catch (_) {
      // Se conserva lo que ya se mostraba.
    }
  }

  /// El comensal cerró el aviso "Entregado": el pedido deja de mostrarse.
  Future<void> acknowledgeDelivery() async {
    final order = _state.activeOrder;
    if (order == null || !order.isDelivered) return;
    _emit(_state.copyWith(clearActiveOrder: true));
    _syncOrderPolling(
      null,
      table: _state.activeTable,
      passes: _state.passes,
      menuPublishedByRest: _state.todayMenuPublishedByRest,
    );
    await _repository.acknowledgeOrder(order.orderNumber);
  }

  /// Controla el stream SSE (`GET /v1/pase/eventos`) y el refresco inicial
  /// del saldo mientras la pantalla Pase esté visible y en primer plano.
  void onPaseVisibilityChanged(
    bool visible, {
    bool resumedFromBackground = false,
  }) {
    _paseVisible = visible;
    if (!visible) {
      _disconnectPaseSse(keepFallback: false);
      return;
    }
    if (resumedFromBackground) {
      _ssePausedByReplacement = false;
    }
    unawaited(_refreshBalanceOnce());
    if (!AppMode.useMock && !_ssePausedByReplacement) {
      unawaited(_connectPaseSse());
    }
  }

  /// Refresca el saldo una vez al abrir Pase (devoluciones por reclamo no emiten SSE).
  Future<void> _refreshBalanceOnce() async {
    if (_disposed || _state.status == CustomerStatus.initial) return;
    try {
      final passes = await _repository.getActivePasses();
      if (_disposed || !_paseVisible) return;
      final nextMenuStates = await _resolveMenuStatesForPasses(
        passes,
        _state.restaurants,
      );
      _emit(_state.copyWith(
        passes: passes,
        todayMenuPublishedByRest: nextMenuStates.published,
        todayMenuAvailabilityByRest: nextMenuStates.availability,
      ));
    } catch (_) {}
  }

  Future<void> _connectPaseSse() async {
    if (_disposed || !_paseVisible || _ssePausedByReplacement || AppMode.useMock) {
      return;
    }
    final repo = _repository;
    if (repo is! ApiCustomerRepository) {
      _startSseFallbackPolling();
      return;
    }

    _disconnectPaseSse(keepFallback: false);
    final cancelToken = CancelToken();
    _sseCancelToken = cancelToken;

    try {
      final stream = await repo.connectPaseEvents(cancelToken: cancelToken);
      if (_disposed || !_paseVisible || cancelToken.isCancelled) return;
      _sseRetryAttempt = 0;
      _sseFallbackPoller?.cancel();
      _sseFallbackPoller = null;

      _sseSub = stream.listen(
        _handlePaseSseEvent,
        onError: (Object error) {
          if (cancelToken.isCancelled || _disposed || !_paseVisible) return;
          _scheduleSseReconnectOrFallback(error: error);
        },
        onDone: () {
          if (cancelToken.isCancelled || _disposed || !_paseVisible) return;
          if (!_ssePausedByReplacement) {
            _scheduleSseReconnectOrFallback();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (cancelToken.isCancelled || _disposed || !_paseVisible) return;
      _scheduleSseReconnectOrFallback(error: e);
    }
  }

  void _handlePaseSseEvent(PaseSseEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case PaseEventType.latido:
        return;
      case PaseEventType.canjeRegistrado:
        _applyBalanceFromEvent(
          restauranteNombre: event.restauranteNombre,
          saldoRestante: event.saldoRestante,
        );
        final restName = event.restauranteNombre?.trim();
        final plato = event.platoNombre?.trim();
        final subtitleParts = <String>[
          if (restName != null && restName.isNotEmpty) restName,
          if (plato != null && plato.isNotEmpty) plato,
          if (event.saldoRestante != null)
            'Te quedan ${event.saldoRestante} almuerzos',
        ];
        _emit(_state.copyWith(
          consumptionNotice: subtitleParts.isNotEmpty
              ? 'Almuerzo canjeado · ${subtitleParts.join(' · ')}'
              : 'Almuerzo canjeado',
          redemptionCelebrationTick: _state.redemptionCelebrationTick + 1,
          redemptionCelebrationTitle: 'Almuerzo canjeado',
          redemptionCelebrationSubtitle:
              subtitleParts.isNotEmpty ? subtitleParts.join(' · ') : null,
        ));
      case PaseEventType.canjeRevertido:
        _applyBalanceFromEvent(
          restauranteNombre: event.restauranteNombre,
          saldoRestante: event.saldoRestante,
        );
        final restName = event.restauranteNombre?.trim();
        _emit(_state.copyWith(
          consumptionNotice: restName != null && restName.isNotEmpty
              ? 'Canje revertido en $restName · Saldo: ${event.saldoRestante ?? ''}'
              : 'Canje revertido en caja',
        ));
      case PaseEventType.fin:
        switch (event.finReason) {
          case PaseFinReason.tokenVencido:
            _disconnectPaseSse(keepFallback: false);
            unawaited(_refreshTokenAndReconnectSse());
          case PaseFinReason.reemplazada:
            // Máximo 2 conexiones: no reconectar sola hasta volver a primer plano.
            _ssePausedByReplacement = true;
            _disconnectPaseSse(keepFallback: false);
          case PaseFinReason.apagado:
          case PaseFinReason.unknown:
            _disconnectPaseSse(keepFallback: true);
            _scheduleSseReconnectOrFallback(
              explicitDelay: event.retryDelay ?? const Duration(seconds: 5),
            );
        }
      case PaseEventType.unknown:
        return;
    }
  }

  void _applyBalanceFromEvent({
    required String? restauranteNombre,
    required int? saldoRestante,
  }) {
    if (saldoRestante == null || _state.passes.isEmpty) return;
    final targetName = (restauranteNombre ?? '').trim().toLowerCase();
    var matched = false;
    final updated = <CustomerPass>[];
    for (var i = 0; i < _state.passes.length; i++) {
      final pass = _state.passes[i];
      final sameName = targetName.isNotEmpty &&
          pass.restaurantName.trim().toLowerCase() == targetName;
      if (sameName ||
          (targetName.isEmpty && i == _state.passIndex)) {
        matched = true;
        updated.add(pass.copyWith(remainingLunches: saldoRestante));
      } else {
        updated.add(pass);
      }
    }
    if (!matched && _state.currentPass != null) {
      final idx = _state.passIndex.clamp(0, _state.passes.length - 1);
      updated[idx] = updated[idx].copyWith(remainingLunches: saldoRestante);
    }
    _emit(_state.copyWith(passes: updated));
    if (updated.isNotEmpty) {
      final idx = _state.passIndex.clamp(0, updated.length - 1);
      unawaited(_repository.saveCachedPass(updated[idx]));
    }
  }

  Future<void> _refreshTokenAndReconnectSse() async {
    final repo = _repository;
    if (repo is! ApiCustomerRepository || _disposed || !_paseVisible) return;
    final refreshed = await repo.refreshAuthSession();
    if (refreshed && !_disposed && _paseVisible && !_ssePausedByReplacement) {
      await _connectPaseSse();
    } else if (!_disposed && _paseVisible) {
      _startSseFallbackPolling();
    }
  }

  void _scheduleSseReconnectOrFallback({
    Object? error,
    Duration? explicitDelay,
  }) {
    if (_disposed || !_paseVisible || _ssePausedByReplacement) return;
    _startSseFallbackPolling();
    _sseReconnectTimer?.cancel();

    final isSaturated =
        error is ApiException && error.code == 'EVENTOS_SATURADO';
    final delay = explicitDelay ??
        Duration(
          seconds: isSaturated
              ? (10 * (_sseRetryAttempt + 1)).clamp(10, 60)
              : const [5, 10, 20, 30][_sseRetryAttempt.clamp(0, 3)],
        );
    _sseRetryAttempt++;
    _sseReconnectTimer = Timer(delay, () {
      if (!_disposed && _paseVisible && !_ssePausedByReplacement) {
        unawaited(_connectPaseSse());
      }
    });
  }

  void _startSseFallbackPolling() {
    if (_disposed || !_paseVisible || _sseFallbackPoller != null) return;
    _sseFallbackPoller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed || !_paseVisible) {
        _sseFallbackPoller?.cancel();
        _sseFallbackPoller = null;
        return;
      }
      unawaited(_refreshBalanceOnce());
    });
  }

  void _disconnectPaseSse({required bool keepFallback}) {
    _sseCancelToken?.cancel();
    _sseCancelToken = null;
    _sseSub?.cancel();
    _sseSub = null;
    _sseReconnectTimer?.cancel();
    _sseReconnectTimer = null;
    if (!keepFallback) {
      _sseFallbackPoller?.cancel();
      _sseFallbackPoller = null;
    }
  }

  void selectQrMode(QrMode mode) => _emit(_state.copyWith(selectedQrMode: mode));

  void selectPass(int index) {
    if (_state.passes.isEmpty) return;
    final idx = index.clamp(0, _state.passes.length - 1);
    _emit(_state.copyWith(passIndex: idx, selectedQrMode: QrMode.plan));
  }

  void clearConsumptionNotice() =>
      _emit(_state.copyWith(clearConsumptionNotice: true));

  void syncRestaurantSummary(Restaurant detail) {
    final avail = detail.menuAvailabilityState;
    final nextMenuMap = Map<String, bool>.from(_state.todayMenuPublishedByRest)
      ..[detail.id] = avail == MenuAvailabilityState.disponible;
    final nextAvailMap = Map<String, MenuAvailabilityState>.from(
      _state.todayMenuAvailabilityByRest,
    )..[detail.id] = avail;
    final idx = _state.restaurants.indexWhere((r) => r.id == detail.id);
    if (idx < 0) {
      _emit(_state.copyWith(
        passes: _state.passes,
        todayMenuPublishedByRest: nextMenuMap,
        todayMenuAvailabilityByRest: nextAvailMap,
      ));
    } else {
      final next = List<Restaurant>.from(_state.restaurants);
      next[idx] = detail;
      _emit(_state.copyWith(
        passes: _state.passes,
        restaurants: next,
        todayMenuPublishedByRest: nextMenuMap,
        todayMenuAvailabilityByRest: nextAvailMap,
      ));
    }
  }

  void nextPass() {
    if (_state.passes.length < 2) return;
    _emit(_state.copyWith(passIndex: (_state.passIndex + 1) % _state.passes.length));
  }

  void previousPass() {
    final n = _state.passes.length;
    if (n < 2) return;
    _emit(_state.copyWith(passIndex: (_state.passIndex - 1 + n) % n));
  }

  void setSearchQuery(String query) => _emit(_state.copyWith(searchQuery: query));

  void toggleFilter(RestaurantFilter filter) {
    final next = {..._state.filters};
    if (!next.remove(filter)) {
      // Los accesos rápidos son excluyentes: activar uno apaga los demás.
      if (quickAccessFilters.contains(filter)) {
        next.removeAll(quickAccessFilters);
      }
      next.add(filter);
    }
    _emit(_state.copyWith(filters: next));
  }

  void clearFilters() => _emit(_state.copyWith(
        searchQuery: '',
        filters: {},
        clearSearchArea: true,
      ));

  void applySearchArea({
    required LatLng center,
    required String label,
    required int? radiusMeters,
  }) {
    if (radiusMeters == null) {
      _emit(_state.copyWith(clearSearchArea: true));
      return;
    }
    _emit(_state.copyWith(
      searchCenter: center,
      searchZoneLabel: label,
      searchRadiusMeters: radiusMeters,
    ));
  }

  void clearSearchArea() => _emit(_state.copyWith(clearSearchArea: true));

  Future<bool> claimReward(String restaurantId) async {
    final ok = await _repository.claimReward(restaurantId);
    if (!ok) return false;
    final card = await _repository.getStampCard(restaurantId);
    if (card != null) {
      _emit(_state.copyWith(stampCards: {..._state.stampCards, restaurantId: card}));
    }
    _startUndo('Premio reclamado', () async {
      // TODO: Conectar con provider de backend (revertir premio reclamado)
    });
    return true;
  }

  /// Cotiza la selección actual contra `POST /v1/mis/pedidos/cotizar` sin crear orden.
  Future<OrderQuote?> quotePreorder({
    required Restaurant restaurant,
    String? soupId,
    String? mainId,
    String? breakfastId,
    bool takeaway = false,
    List<({String platoId, int quantity})> cartaItems = const [],
  }) async {
    if (_state.activeOrder != null && !_state.activeOrder!.isDelivered) {
      return null;
    }
    try {
      return await _repository.quotePreorder(
        restaurantId: restaurant.id,
        soupId: soupId,
        mainId: mainId,
        breakfastId: breakfastId,
        takeaway: takeaway,
        cartaItems: cartaItems,
      );
    } catch (_) {
      return null;
    }
  }

  /// Preorden desde la ficha del local (C3) o directa desde la tarjeta (C2).
  Future<bool> preorder({
    required Restaurant restaurant,
    String? soupId,
    String? mainId,
    String? breakfastId,
    String? offerId,
    bool takeaway = false,
    String? estimatedArrival,
    List<({String platoId, int quantity})> cartaItems = const [],
  }) async {
    lastActionError = null;
    lastActionErrorCode = null;
    lastActionConflict = false;
    if (_state.activeOrder != null && !_state.activeOrder!.isDelivered) {
      final latest = await _repository.getActiveOrder();
      if (latest != null && !latest.isDelivered) {
        _emit(_state.copyWith(activeOrder: latest));
        lastActionError = 'Ya tienes una orden activa pendiente.';
        return false;
      }
      _emit(_state.copyWith(clearActiveOrder: true));
    }
    try {
      final order = await _repository.preorder(
        restaurantId: restaurant.id,
        soupId: soupId,
        mainId: mainId,
        breakfastId: breakfastId,
        offerId: offerId,
        takeaway: takeaway,
        estimatedArrival: estimatedArrival,
        cartaItems: cartaItems,
      );
      final matchingPassIdx =
          _state.passes.indexWhere((p) => p.restaurantId == restaurant.id);
      _emit(_state.copyWith(
        activeOrder: order,
        selectedQrMode: QrMode.preorden,
        passIndex: matchingPassIdx >= 0 ? matchingPassIdx : _state.passIndex,
      ));
      _syncOrderPolling(order);
      if (order.hasPlan) {
        unawaited(loadDashboard(silent: true));
      }
      _startUndo('Pedido enviado · Deshacer', () async {
        try {
          await _repository.cancelPreorder(order.orderNumber);
          _emit(_state.copyWith(clearActiveOrder: true));
          _syncOrderPolling(null);
        } catch (_) {
          await refreshLive();
        }
      });
      return true;
    } on ApiException catch (e) {
      lastActionConflict = e.status == 409;
      // 409: un ítem se agotó; la selección se conserva para que el usuario la ajuste.
      lastActionError = lastActionConflict
          ? 'Se agotó un ítem de tu pedido. Ajusta tu selección e inténtalo de nuevo.'
          : e.userMessage;
      lastActionErrorCode = e.code;
      if (e.code == 'RESTAURANTE_PAUSADO' ||
          e.code == 'MENU_NO_PUBLICADO' ||
          e.code == 'LOCAL_LLENO_SOLO_LLEVAR') {
        unawaited(refreshRestaurants(forceHydrate: true));
      }
      return false;
    } catch (_) {
      lastActionError = 'No pudimos enviar tu pedido. Inténtalo de nuevo.';
      lastActionErrorCode = null;
      return false;
    }
  }

  Future<bool> reserveOffer(
    RestaurantOffer offer, {
    bool takeaway = false,
    String? estimatedArrival,
  }) async {
    final restaurant = _state.restaurantById(offer.restaurantId);
    if (restaurant == null) return false;
    final ok = await preorder(
      restaurant: restaurant,
      offerId: offer.id,
      takeaway: takeaway,
      estimatedArrival: estimatedArrival,
    );
    // Los cupos cambiaron: el feed se relee para que la oferta baje o salga.
    if (ok) unawaited(refreshRestaurants());
    return ok;
  }

  Future<void> selectPlansRestaurant(String restaurantId) async {
    _emit(_state.copyWith(plansRestaurantId: restaurantId, isLoadingPlans: true));
    try {
      final plans = await _repository.getPlanTemplates(restaurantId);
      if (_state.plansRestaurantId != restaurantId) return;
      _emit(_state.copyWith(planTemplates: plans, isLoadingPlans: false));
    } catch (_) {
      _emit(_state.copyWith(planTemplates: const [], isLoadingPlans: false));
    }
  }

  Future<bool> requestPlan(PlanTemplate plan) async {
    lastActionError = null;
    try {
      final ok = await _repository.requestPlan(plan.id);
      if (!ok) return false;
      _startUndo('Plan solicitado · Deshacer', () async {
        await _repository.cancelPlanRequest(plan.id);
      });
      return true;
    } on ApiException catch (e) {
      lastActionError = e.userMessage;
      return false;
    } catch (_) {
      lastActionError = 'No pudimos enviar la solicitud. Inténtalo de nuevo.';
      return false;
    }
  }

  /// C9 actualiza la mesa que muestra Mi Pase (QR de mesa y conteo).
  void syncTable(SharedTable table) {
    final activeTable = ActiveTable(
      id: table.id,
      restaurantName: table.restaurantName,
      time: table.time,
      membersCount: table.members.length,
      url: table.qrPayload,
    );
    _emit(_state.copyWith(activeTable: activeTable));
    _syncOrderPolling(_state.activeOrder, table: activeTable);
  }

  ActiveTable? _pruneExpiredCollectingTable(ActiveTable? table) {
    if (table == null) return null;
    final sim = GroupOrderSimulationStore.instance.sessionById(table.id);
    if (sim != null) {
      if (sim.status == GroupOrderStatus.cancelled ||
          sim.status == GroupOrderStatus.expired) {
        return null;
      }
      if (sim.status == GroupOrderStatus.collecting &&
          DateTime.now().isAfter(sim.estimatedConsumptionTime)) {
        GroupOrderSimulationStore.instance.markExpired(table.id);
        unawaited(_repository.cancelSharedTable(table.id).catchError((_) {}));
        return null;
      }
      return table;
    }

    // Tras reinicio de app: si solo quedó el anfitrión y ya pasó la hora límite, liberar.
    final parts = table.time.split(':');
    if (parts.length == 2 && table.membersCount <= 1) {
      final h = int.tryParse(parts[0].trim());
      final m = int.tryParse(parts[1].trim());
      if (h != null && m != null) {
        final now = DateTime.now();
        final limit = DateTime(now.year, now.month, now.day, h, m);
        if (now.isAfter(limit.add(const Duration(minutes: 5)))) {
          unawaited(_repository.cancelSharedTable(table.id).catchError((_) {}));
          return null;
        }
      }
    }
    return table;
  }

  Future<bool> cancelSharedTable(String tableId) async {
    lastActionError = null;
    try {
      await _repository.cancelSharedTable(tableId);
      GroupOrderSimulationStore.instance.markCancelled(tableId);
      _emit(_state.copyWith(clearActiveTable: true));
      _syncOrderPolling(
        _state.activeOrder,
        table: null,
        passes: _state.passes,
        menuPublishedByRest: _state.todayMenuPublishedByRest,
      );
      return true;
    } on ApiException catch (e) {
      lastActionError = e.userMessage;
      return false;
    } catch (_) {
      lastActionError = 'No pudimos cancelar la mesa. Inténtalo de nuevo.';
      return false;
    }
  }

  /// C10: una etiqueta de un toque. La tarjeta se oculta al enviar.
  Future<bool> submitFeedback(String tag) async {
    final f = _state.pendingFeedback;
    if (f == null) return false;
    lastActionError = null;
    _emit(_state.copyWith(clearPendingFeedback: true));
    try {
      return await _repository.submitFeedback(f.redemptionId, tag: tag);
    } on ApiException catch (e) {
      lastActionError = e.userMessage;
      return false;
    } catch (_) {
      lastActionError = 'No pudimos enviar tu calificación. Inténtalo más tarde.';
      return false;
    }
  }

  Future<void> dismissFeedback() async {
    final f = _state.pendingFeedback;
    if (f == null) return;
    _emit(_state.copyWith(clearPendingFeedback: true));
    try {
      await _repository.dismissFeedback(f.redemptionId);
    } catch (_) {}
  }

  Future<void> undo() async {
    final action = _undoAction;
    _clearUndo();
    if (action != null) await action();
  }

  void _startUndo(String label, Future<void> Function() action) {
    _undoTimer?.cancel();
    _undoAction = action;
    _emit(_state.copyWith(undo: UndoNotice(label, 10)));
    _undoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _state.undo;
      if (current == null || current.secondsLeft <= 1) {
        _clearUndo();
      } else {
        _emit(_state.copyWith(undo: UndoNotice(current.label, current.secondsLeft - 1)));
      }
    });
  }

  void _clearUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    _undoAction = null;
    _emit(_state.copyWith(clearUndo: true));
  }

  void _syncOrderPolling(
    ActiveOrder? order, {
    ActiveTable? table,
    List<CustomerPass>? passes,
    Map<String, bool>? menuPublishedByRest,
  }) {
    final activePasses = passes ?? _state.passes;
    final menuMap = menuPublishedByRest ?? _state.todayMenuPublishedByRest;
    final hasUnpublishedPass = !AppMode.useMock &&
        activePasses.any(
          (p) => p.remainingLunches > 0 && !(menuMap[p.restaurantId] ?? false),
        );
    final shouldPoll =
        (order != null && !order.isDelivered) || table != null || hasUnpublishedPass;
    if (shouldPoll) {
      _orderPoller ??= LifecyclePollingController(
        interval: const Duration(seconds: 8),
        onTick: refreshLive,
      );
      if (!_orderPoller!.isRunning) {
        try {
          _orderPoller!.start();
        } catch (_) {
          // En pruebas unitarias sin WidgetsBinding inicializado se omite el ciclo.
        }
      }
    } else {
      _orderPoller?.stop();
    }
  }

  Future<void> _hydrateRestaurants(
    List<Restaurant> base, {
    bool force = false,
  }) async {
    if (base.isEmpty) return;
    final byId = <String, Restaurant>{};
    final nextMenuMap = Map<String, bool>.from(_state.todayMenuPublishedByRest);
    final nextAvailMap = Map<String, MenuAvailabilityState>.from(
      _state.todayMenuAvailabilityByRest,
    );
    var changed = false;
    var fetched = 0;
    final prioritized = <Restaurant>[
      ...base.where(_state._matchesActiveZone),
      ...base.where((r) => !_state._matchesActiveZone(r)),
    ];
    for (var i = 0; i < prioritized.length && fetched < 12; i++) {
      if (_disposed) return;
      if (!force && prioritized[i].hasMenu) continue;
      fetched++;
      try {
        final detail = await _repository.getRestaurantById(prioritized[i].id);
        if (detail != null && !_disposed) {
          byId[detail.id] = detail;
          final avail = detail.menuAvailabilityState;
          nextAvailMap[detail.id] = avail;
          nextMenuMap[detail.id] = avail == MenuAvailabilityState.disponible;
          changed = true;
        }
      } catch (_) {}
    }
    if (changed && !_disposed) {
      final merged = [
        for (final r in _state.restaurants) byId[r.id] ?? r,
      ];
      _emit(_state.copyWith(
        restaurants: merged,
        todayMenuPublishedByRest: nextMenuMap,
        todayMenuAvailabilityByRest: nextAvailMap,
      ));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    FlashOffersLiveSync.instance.removeListener(_onFlashOfferLiveSync);
    RestaurantStatusLiveSync.instance.removeListener(_onRestaurantStatusLiveSync);
    MenuAndCartaLiveSync.instance.removeListener(_onMenuCartaLiveSync);
    if (AppMode.useMock) {
      DemoStore.instance.removeListener(_onDemoStoreChanged);
    }
    _undoTimer?.cancel();
    _orderPoller?.dispose();
    _restaurantsPoller?.dispose();
    _disconnectPaseSse(keepFallback: false);
    super.dispose();
  }
}

final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
  if (AppMode.useMock) return MockCustomerRepository();
  return ApiCustomerRepository(
    apiClient: ref.watch(apiClientProvider),
    session: ref.watch(sessionProvider),
  );
});

final customerControllerProvider = Provider<CustomerController>((ref) {
  final controller = CustomerController(repository: ref.watch(customerRepositoryProvider));
  controller.loadDashboard();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Local y menú para la ficha (C3), también cuando se abre por ruta directa.
final restaurantDetailProvider =
    FutureProvider.autoDispose.family<Restaurant?, String>((ref, id) async {
  final sync = MenuAndCartaLiveSync.instance;
  void onSync() {
    final target = sync.lastRestaurantId;
    if (target == null || target.isEmpty || target == id) {
      ref.invalidateSelf();
    }
  }

  sync.addListener(onSync);
  ref.onDispose(() => sync.removeListener(onSync));

  final detail = await ref.watch(customerRepositoryProvider).getRestaurantById(id);
  if (detail != null) {
    ref.read(customerControllerProvider).syncRestaurantSummary(detail);
  }
  return detail;
});

/// Carta fija pública del restaurante (`GET /v1/restaurantes/{slug}/carta`, Entrega C).
/// Solo lectura: no habilita cobro de platos a la carta en `POST /v1/mis/pedidos`.
final restaurantCartaProvider =
    FutureProvider.autoDispose.family<List<PublicCartaItem>, String>((ref, id) async {
  final sync = MenuAndCartaLiveSync.instance;
  void onSync() {
    final target = sync.lastRestaurantId;
    if (target == null || target.isEmpty || target == id) {
      ref.invalidateSelf();
    }
  }

  sync.addListener(onSync);
  ref.onDispose(() => sync.removeListener(onSync));

  return ref.watch(customerRepositoryProvider).getRestaurantCarta(id);
});

/// Fuente única de verdad en Comensal del estado público efectivo del local
/// (`libre`, `concurrido`, `lleno` con timer, `agotadoHoy` o `cerrado`), compartida
/// entre la tarjeta del Marketplace (`DondeComer`) y `RestaurantSheet`.
final restaurantPublicStatusProvider =
    Provider.family<RestaurantPublicStatus, String>((ref, restaurantId) {
  final controller = ref.watch(customerControllerProvider);
  void onChanged() => ref.invalidateSelf();
  controller.addListener(onChanged);
  ref.onDispose(() => controller.removeListener(onChanged));

  final s = controller.state;
  final fromList = s.restaurantById(restaurantId);
  var menuAvail = s.menuAvailabilityFor(restaurantId);
  if (fromList != null && fromList.isMenuSoldOutToday) {
    menuAvail = MenuAvailabilityState.agotadoTotal;
  }
  final isOpen = (fromList?.isOpen ?? true) && !(fromList?.isPaused ?? false);
  return resolveRestaurantPublicStatus(
    menuAvailability: menuAvail,
    manual: parseManualOccupancy(fromList?.occupancy),
    isOpen: isOpen,
    fullUntil: fromList?.fullUntil,
    ignoreClock: true,
  );
});

/// Compatibilidad: código legado de ocupación (`LIBRE`, `MOVIDO`, `LLENO`).
final restaurantOccupancyProvider =
    Provider.family<String, String>((ref, restaurantId) {
  return ref.watch(restaurantPublicStatusProvider(restaurantId)).legacyOccupancy;
});

/// Plan y su local para el detalle del plan (C5).
final planDetailProvider = FutureProvider.autoDispose
    .family<(PlanTemplate, Restaurant)?, String>((ref, planId) async {
  final repo = ref.watch(customerRepositoryProvider);
  final plan = await repo.getPlanTemplateById(planId);
  if (plan == null) return null;
  final restaurant = await repo.getRestaurantById(plan.restaurantId);
  if (restaurant == null) return null;
  return (plan, restaurant);
});
