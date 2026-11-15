import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../data/mock_customer_repo.dart';

enum CustomerStatus { initial, loading, success, error }

/// Qué QR muestra Mi Pase. El orden es la prioridad por defecto.
enum QrMode { preorden, mesa, plan }

/// Filtros de Dónde comer. Se combinan entre sí (Y).
enum RestaurantFilter { near, withPlan, free, offers }

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
  final String? plansRestaurantId;
  final List<PlanTemplate> planTemplates;
  final bool isLoadingPlans;
  final UndoNotice? undo;
  final String? errorMessage;
  final bool isOffline;

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
    this.plansRestaurantId,
    this.planTemplates = const [],
    this.isLoadingPlans = false,
    this.undo,
    this.errorMessage,
    this.isOffline = false,
  });

  bool get isLoading => status == CustomerStatus.loading;
  bool get isError => status == CustomerStatus.error;

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
        QrMode.plan => currentPass?.qrToken ?? '',
      };

  List<Restaurant> get filteredRestaurants {
    final q = searchQuery.trim().toLowerCase();
    return restaurants.where((r) {
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
      if (filters.contains(RestaurantFilter.withPlan) && !r.hasPlan) {
        return false;
      }
      if (filters.contains(RestaurantFilter.free) && r.occupancy != 'LIBRE') {
        return false;
      }
      if (filters.contains(RestaurantFilter.offers) && !r.hasOffer) {
        return false;
      }
      return true;
    }).toList();
  }

  CustomerPass? passFor(String restaurantId) {
    for (final p in passes) {
      if (p.restaurantId == restaurantId) return p;
    }
    return null;
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
    ActiveOrder? activeOrder,
    bool clearActiveOrder = false,
    bool clearPendingFeedback = false,
    List<ActivityItem>? recentActivity,
    List<Restaurant>? restaurants,
    String? searchQuery,
    Set<RestaurantFilter>? filters,
    String? plansRestaurantId,
    List<PlanTemplate>? planTemplates,
    bool? isLoadingPlans,
    UndoNotice? undo,
    bool clearUndo = false,
    String? errorMessage,
    bool? isOffline,
  }) {
    return CustomerUiState(
      status: status ?? this.status,
      passes: passes ?? this.passes,
      passIndex: passIndex ?? this.passIndex,
      selectedQrMode: selectedQrMode ?? this.selectedQrMode,
      stampCards: stampCards ?? this.stampCards,
      activeTable: activeTable ?? this.activeTable,
      activeOrder: clearActiveOrder ? null : activeOrder ?? this.activeOrder,
      pendingFeedback: clearPendingFeedback ? null : pendingFeedback,
      recentActivity: recentActivity ?? this.recentActivity,
      restaurants: restaurants ?? this.restaurants,
      searchQuery: searchQuery ?? this.searchQuery,
      filters: filters ?? this.filters,
      plansRestaurantId: plansRestaurantId ?? this.plansRestaurantId,
      planTemplates: planTemplates ?? this.planTemplates,
      isLoadingPlans: isLoadingPlans ?? this.isLoadingPlans,
      undo: clearUndo ? null : undo ?? this.undo,
      errorMessage: errorMessage,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

/// Estado del módulo Comensal compartido por Mi Pase, Dónde comer y Planes.
class CustomerController extends ChangeNotifier {
  final ICustomerRepository _repository;
  CustomerUiState _state = const CustomerUiState();
  Timer? _undoTimer;
  Future<void> Function()? _undoAction;

  CustomerController({ICustomerRepository? repository})
      : _repository = repository ?? MockCustomerRepository();

  CustomerUiState get state => _state;

  void _emit(CustomerUiState next) {
    _state = next;
    notifyListeners();
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

      final passes = await _repository.getActivePasses();
      final restaurants = await _repository.getRestaurants();
      final table = await _repository.getActiveTable();
      final order = await _repository.getActiveOrder();
      final activity = await _repository.getRecentActivity();
      final feedback = await _repository.getPendingFeedback();
      final stamps = <String, StampCard>{};
      for (final p in passes) {
        final card = await _repository.getStampCard(p.restaurantId);
        if (card != null) stamps[p.restaurantId] = card;
      }

      _emit(CustomerUiState(
        status: CustomerStatus.success,
        passes: passes,
        passIndex: _state.passIndex.clamp(0, passes.isEmpty ? 0 : passes.length - 1),
        selectedQrMode: _state.selectedQrMode,
        stampCards: stamps,
        activeTable: table,
        activeOrder: order,
        pendingFeedback: feedback,
        recentActivity: activity,
        restaurants: restaurants,
        searchQuery: _state.searchQuery,
        filters: _state.filters,
        plansRestaurantId: _state.plansRestaurantId,
        planTemplates: _state.planTemplates,
        undo: _state.undo,
      ));
      if (_state.plansRestaurantId == null && restaurants.isNotEmpty) {
        await selectPlansRestaurant(restaurants.first.id);
      }
    } catch (e) {
      if (_state.passes.isNotEmpty) {
        _emit(_state.copyWith(status: CustomerStatus.success, isOffline: true));
      } else {
        _emit(_state.copyWith(
          status: CustomerStatus.error,
          isOffline: false,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ));
      }
    }
  }

  /// Vuelve a leer lo que puede cambiar desde la caja (pedido entregado,
  /// mesa cobrada) sin mostrar carga. Lo llama el marco al entrar.
  Future<void> refreshLive() async {
    if (_state.status != CustomerStatus.success) return;
    try {
      final order = await _repository.getActiveOrder();
      final table = await _repository.getActiveTable();
      _emit(_state.copyWith(
        activeOrder: order,
        clearActiveOrder: order == null,
        activeTable: table,
      ));
    } catch (_) {
      // Se conserva lo que ya se mostraba.
    }
  }

  /// El comensal cerró el aviso "Entregado": el pedido deja de mostrarse.
  Future<void> acknowledgeDelivery() async {
    final order = _state.activeOrder;
    if (order == null || !order.isDelivered) return;
    _emit(_state.copyWith(clearActiveOrder: true));
    await _repository.acknowledgeOrder(order.orderNumber);
  }

  /// Regenera el QR rotativo del plan en pantalla (anti-captura).
  Future<void> refreshQr() async {
    final pass = _state.currentPass;
    if (pass == null) return;
    try {
      final token = await _repository.refreshQrToken(pass.id);
      final updated = [
        for (final p in _state.passes) p.id == pass.id ? p.copyWith(qrToken: token) : p,
      ];
      await _repository.saveCachedPass(updated[_state.passIndex]);
      _emit(_state.copyWith(passes: updated));
    } catch (_) {
      // Se conserva el QR anterior hasta el siguiente ciclo.
    }
  }

  void selectQrMode(QrMode mode) => _emit(_state.copyWith(selectedQrMode: mode));

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
    if (!next.remove(filter)) next.add(filter);
    _emit(_state.copyWith(filters: next));
  }

  void clearFilters() => _emit(_state.copyWith(searchQuery: '', filters: {}));

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

  /// Preorden desde la ficha del local (C3) o directa desde la tarjeta (C2).
  Future<bool> preorder({
    required Restaurant restaurant,
    String? soupId,
    String? mainId,
    String? breakfastId,
    String? offerId,
    bool takeaway = false,
  }) async {
    if (_state.activeOrder != null && !_state.activeOrder!.isDelivered) return false;
    final order = await _repository.preorder(
      restaurantId: restaurant.id,
      soupId: soupId,
      mainId: mainId,
      breakfastId: breakfastId,
      offerId: offerId,
      takeaway: takeaway,
    );
    _emit(_state.copyWith(activeOrder: order, selectedQrMode: QrMode.preorden));
    _startUndo('Pedido enviado · Deshacer', () async {
      await _repository.cancelPreorder(order.orderNumber);
      _emit(_state.copyWith(clearActiveOrder: true));
    });
    return true;
  }

  /// "Pedir" en la tarjeta de Dónde comer: primera sopa y segundo disponibles.
  Future<bool> quickOrder(Restaurant restaurant) {
    final soup = restaurant.soups.where((m) => !m.isSoldOut).firstOrNull;
    final main = restaurant.mains.where((m) => !m.isSoldOut).firstOrNull;
    return preorder(restaurant: restaurant, soupId: soup?.id, mainId: main?.id);
  }

  Future<bool> reserveOffer(RestaurantOffer offer) async {
    final restaurant = _state.restaurantById(offer.restaurantId);
    if (restaurant == null) return false;
    return preorder(restaurant: restaurant, offerId: offer.id);
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
    final ok = await _repository.requestPlan(plan.id);
    if (!ok) return false;
    _startUndo('Plan solicitado · Deshacer', () async {
      await _repository.cancelPlanRequest(plan.id);
    });
    return true;
  }

  /// C9 actualiza la mesa que muestra Mi Pase (QR de mesa y conteo).
  void syncTable(SharedTable table) {
    _emit(_state.copyWith(
      activeTable: ActiveTable(
        id: table.id,
        restaurantName: table.restaurantName,
        time: table.time,
        membersCount: table.members.length,
        url: table.qrPayload,
      ),
    ));
  }

  /// C10: una etiqueta de un toque. La tarjeta se oculta al enviar.
  Future<bool> submitFeedback(String tag) async {
    final f = _state.pendingFeedback;
    if (f == null) return false;
    _emit(_state.copyWith(clearPendingFeedback: true));
    return _repository.submitFeedback(f.redemptionId, tag: tag);
  }

  Future<void> dismissFeedback() async {
    final f = _state.pendingFeedback;
    if (f == null) return;
    _emit(_state.copyWith(clearPendingFeedback: true));
    await _repository.dismissFeedback(f.redemptionId);
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

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }
}

final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
  return MockCustomerRepository();
});

final customerControllerProvider = Provider<CustomerController>((ref) {
  final controller = CustomerController(repository: ref.watch(customerRepositoryProvider));
  controller.loadDashboard();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Local y menú para la ficha (C3), también cuando se abre por ruta directa.
final restaurantDetailProvider =
    FutureProvider.autoDispose.family<Restaurant?, String>((ref, id) {
  return ref.watch(customerRepositoryProvider).getRestaurantById(id);
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
