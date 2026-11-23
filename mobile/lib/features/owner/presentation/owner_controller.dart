import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/utils/formatters.dart';
import '../../customer/presentation/widgets/menu_carta_sync.dart';
import '../../customer/presentation/widgets/restaurant_status_sync.dart';
import '../../group_orders/presentation/group_order_simulation_provider.dart';
import '../data/api_owner_repo.dart';
import '../data/mock_owner_repo.dart';
import '../data/repositories/owner_repository.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/daily_menu.dart';
import '../domain/models/extras_models.dart';
import '../domain/models/menu_models.dart';
import '../domain/models/metrics_models.dart';
import '../domain/repositories/i_owner_repository.dart';

/// Un solo mock compartido para que escaneo, caja, menú y cierre vean los
/// mismos datos offline (`BOCADOO_USE_MOCK=true`).
final _sharedMock = MockOwnerRepository();
final _sharedOwnerRepository = OwnerRepository(delegate: _sharedMock);

/// Instancia única de [ApiOwnerRepository] vinculada al restaurante activo en sesión.
final apiOwnerRepositoryProvider = Provider<ApiOwnerRepository>((ref) {
  ref.watch(ownerRestaurantIdProvider);
  final repo = ApiOwnerRepository(
    api: ref.watch(apiClientProvider),
    session: ref.watch(sessionProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final ownerRepositoryProvider = Provider<IOwnerRepository>(
  (ref) => AppMode.useMock
      ? _sharedOwnerRepository
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerMenuRepositoryProvider = Provider<IOwnerMenuRepository>(
  (ref) => AppMode.useMock
      ? _sharedOwnerRepository
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerCashRepositoryProvider = Provider<IOwnerCashRepository>(
  (ref) => AppMode.useMock
      ? _sharedMock
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerCatalogRepositoryProvider = Provider<IOwnerCatalogRepository>(
  (ref) => AppMode.useMock
      ? _sharedOwnerRepository
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerMetricsRepositoryProvider = Provider<IOwnerMetricsRepository>(
  (ref) => AppMode.useMock
      ? _sharedMock
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerOrdersRepositoryProvider = Provider<IOwnerOrdersRepository>(
  (ref) => AppMode.useMock
      ? _sharedMock
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerTablesRepositoryProvider = Provider<IOwnerTablesRepository>(
  (ref) => AppMode.useMock
      ? _sharedMock
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerFeedbackRepositoryProvider = Provider<IOwnerFeedbackRepository>(
  (ref) => AppMode.useMock
      ? _sharedMock
      : ref.watch(apiOwnerRepositoryProvider),
);

final ownerSettingsRepositoryProvider = Provider<IOwnerSettingsRepository>(
  (ref) => AppMode.useMock
      ? _sharedMock
      : ref.watch(apiOwnerRepositoryProvider),
);

void _scheduleOrdersPoll(Ref ref, {Duration interval = const Duration(seconds: 8)}) {
  if (AppMode.useMock) return;
  final timer = Timer.periodic(interval, (_) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(timer.cancel);
}

/// O12 · Preórdenes por cobrar y entregar.
final activeOrdersProvider = FutureProvider.autoDispose<List<OwnerOrder>>((ref) {
  _scheduleOrdersPoll(ref);
  return ref
      .read(ownerOrdersRepositoryProvider)
      .getActiveOrders(ref.read(ownerRestaurantIdProvider));
});

/// Mesas con amigos por cobrar (banner de Caja / Pedidos en camino).
final pendingTablesProvider =
    FutureProvider.autoDispose<List<PendingTable>>((ref) async {
  _scheduleOrdersPoll(ref, interval: const Duration(seconds: 4));

  final sim = GroupOrderSimulationStore.instance;
  void onSimChanged() => ref.invalidateSelf();
  sim.addListener(onSimChanged);
  ref.onDispose(() => sim.removeListener(onSimChanged));

  final restaurantId = ref.read(ownerRestaurantIdProvider);
  final simTables = sim.ownerTablesFor(restaurantId);

  List<PendingTable> repoTables = const <PendingTable>[];
  if (ApiCapabilities.ownerPendingTablesList) {
    try {
      repoTables = await ref
          .read(ownerTablesRepositoryProvider)
          .getPendingTables(restaurantId);
    } catch (_) {
      if (simTables.isEmpty) rethrow;
    }
  }

  if (simTables.isEmpty) return repoTables;
  final merged = <String, PendingTable>{
    for (final t in repoTables) t.id: t,
    for (final t in simTables) t.id: t,
  };
  return merged.values.toList();
});

/// O15 · Opiniones.
final opinionsProvider = FutureProvider.autoDispose<List<OwnerOpinion>>((ref) {
  return ref.read(ownerFeedbackRepositoryProvider).getOpinions(ref.read(ownerRestaurantIdProvider));
});

/// O16 · Datos y logo del local.
final localInfoProvider = FutureProvider.autoDispose<LocalInfo>((ref) {
  return ref.read(ownerSettingsRepositoryProvider).getLocalInfo(ref.read(ownerRestaurantIdProvider));
});

const _roleStorageKey = 'bocadoo-owner-role';

/// Rol de este dispositivo (O16). Se guarda en el teléfono.
final ownerRoleProvider = NotifierProvider<OwnerRoleNotifier, OwnerRole>(OwnerRoleNotifier.new);

class OwnerRoleNotifier extends Notifier<OwnerRole> {
  bool _changed = false;

  @override
  OwnerRole build() {
    final session = ref.watch(sessionProvider);
    void onSession() => ref.invalidateSelf();
    session.addListener(onSession);
    ref.onDispose(() => session.removeListener(onSession));

    if (!AppMode.useMock && session.isCashierAccount) {
      return OwnerRole.cashier;
    }
    _load();
    return OwnerRole.owner;
  }

  Future<void> _load() async {
    if (!ApiCapabilities.canSwitchToOwner) {
      state = OwnerRole.cashier;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_roleStorageKey);
      if (_changed || raw == null) return;
      state = raw == 'cashier' ? OwnerRole.cashier : OwnerRole.owner;
    } catch (_) {
      // Sin almacenamiento (pruebas): queda como dueño.
    }
  }

  Future<void> set(OwnerRole role) async {
    if (!ApiCapabilities.canSwitchToOwner && role == OwnerRole.owner) {
      return;
    }
    _changed = true;
    state = role;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_roleStorageKey, role == OwnerRole.cashier ? 'cashier' : 'owner');
    } catch (_) {
      // Se mantiene solo en memoria.
    }
  }
}

/// Restaurante activo de la caja actual (lee la sesión real cuando `!AppMode.useMock`).
final ownerRestaurantIdProvider = Provider<String>((ref) {
  if (AppMode.useMock) return 'rest-001';
  final session = ref.watch(sessionProvider);
  void onSession() => ref.invalidateSelf();
  session.addListener(onSession);
  ref.onDispose(() => session.removeListener(onSession));
  return session.activeRestaurantId ?? '';
});

/// Nombre del local activo (lee la sesión real cuando `!AppMode.useMock`).
final ownerRestaurantNameProvider = Provider<String>((ref) {
  if (AppMode.useMock) return 'La Cuchara de San Blas';
  final session = ref.watch(sessionProvider);
  void onSession() => ref.invalidateSelf();
  session.addListener(onSession);
  ref.onDispose(() => session.removeListener(onSession));
  return session.activeRestaurant?.name ?? 'Mi Restaurante';
});

final catalogDishesProvider = FutureProvider.autoDispose<List<CatalogDish>>((ref) {
  return ref.read(ownerCatalogRepositoryProvider).getDishes(ref.read(ownerRestaurantIdProvider));
});

final planClientCountsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.read(ownerCashRepositoryProvider).getPlanClientCounts(ref.read(ownerRestaurantIdProvider));
});

final metricsProvider = FutureProvider.autoDispose.family<OwnerMetrics, MetricsPeriod>((ref, period) {
  return ref
      .read(ownerMetricsRepositoryProvider)
      .getMetrics(ref.read(ownerRestaurantIdProvider), period: period);
});

/// Solicitudes de plan enviadas por comensales pendientes de cobro en caja (P-01).
final planRequestsProvider = FutureProvider.autoDispose<List<OwnerPlanRequest>>((ref) {
  if (AppMode.useMock) return Future.value(const []);
  return ref.read(apiOwnerRepositoryProvider).getPlanRequests();
});

/// Estado paginado por cursor para `GET /v1/caja/movimientos?fecha=YYYY-MM-DD`.
@immutable
class CajaMovementsState {
  const CajaMovementsState({
    required this.selectedDate,
    this.items = const [],
    this.nextCursor,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.warningMessage,
  });

  final String selectedDate;
  final List<CajaMovement> items;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final String? warningMessage;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  /// Total recaudado en caja: suma únicamente movimientos `VENTA`
  /// con `pagoEstado == CONFIRMADO` y `!revertido`.
  int get totalCollectedCents =>
      items.fold<int>(0, (sum, m) => sum + m.cashCollectedCents);

  CajaMovementsState copyWith({
    String? selectedDate,
    List<CajaMovement>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    String? warningMessage,
    bool clearWarning = false,
  }) {
    return CajaMovementsState(
      selectedDate: selectedDate ?? this.selectedDate,
      items: items ?? this.items,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      warningMessage:
          clearWarning ? null : (warningMessage ?? this.warningMessage),
    );
  }
}

final cajaMovementsProvider =
    NotifierProvider.autoDispose<CajaMovementsNotifier, CajaMovementsState>(
  CajaMovementsNotifier.new,
);

class CajaMovementsNotifier extends Notifier<CajaMovementsState> {
  static const int _pageSize = 20;

  @override
  CajaMovementsState build() {
    ref.watch(ownerRestaurantIdProvider);
    ref.watch(ownerRoleProvider);
    final today = EcuadorTime.today();
    Future.microtask(() => loadDate(today));
    return CajaMovementsState(selectedDate: today, isLoading: true);
  }

  Future<void> loadDate(String fecha, {bool silent = false}) async {
    final today = EcuadorTime.today();
    final isOwner = ref.read(ownerRoleProvider) == OwnerRole.owner;
    var targetDate = fecha;
    String? roleWarning;
    if (!isOwner && targetDate != today) {
      targetDate = today;
      roleWarning = 'Solo el dueño puede consultar movimientos de otras fechas.';
    }

    if (!silent) {
      state = state.copyWith(
        selectedDate: targetDate,
        isLoading: state.items.isEmpty,
        isLoadingMore: false,
        clearError: true,
        warningMessage: roleWarning,
        clearWarning: roleWarning == null,
      );
    }

    final rid = ref.read(ownerRestaurantIdProvider);
    try {
      final page = await ref.read(ownerCashRepositoryProvider).getCajaMovements(
            rid,
            fecha: targetDate,
            limit: _pageSize,
          );
      state = CajaMovementsState(
        selectedDate: targetDate,
        items: page.items,
        nextCursor: page.nextCursor,
        isLoading: false,
        warningMessage: roleWarning,
      );
    } on ApiException catch (e) {
      if (e.code == 'CAJERO_SOLO_HOY' || e.status == 403) {
        final msg = e.userMessage;
        state = state.copyWith(
          selectedDate: today,
          isLoading: false,
          clearError: true,
          warningMessage: msg,
        );
        if (targetDate != today) {
          await loadDate(today, silent: true);
        }
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.userMessage,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No se pudieron cargar los movimientos.',
      );
    }
  }

  Future<void> refresh() => loadDate(state.selectedDate, silent: true);

  Future<void> selectDate(DateTime date) {
    final ymd =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return loadDate(ymd);
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || cursor.isEmpty || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    final rid = ref.read(ownerRestaurantIdProvider);
    try {
      final page = await ref.read(ownerCashRepositoryProvider).getCajaMovements(
            rid,
            fecha: state.selectedDate,
            cursor: cursor,
            limit: _pageSize,
          );
      final seen = {for (final m in state.items) '${m.tipo.name}:${m.id}'};
      final merged = [
        ...state.items,
        for (final m in page.items)
          if (seen.add('${m.tipo.name}:${m.id}')) m,
      ];
      state = state.copyWith(
        items: merged,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        isLoadingMore: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: e.userMessage,
      );
    } catch (_) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: 'No se pudieron cargar más movimientos.',
      );
    }
  }
}

/// Resumen del turno. Se recarga con `ref.invalidate`.
final dailySummaryProvider =
    FutureProvider.autoDispose<TransactionSummary>((ref) {
  return ref
      .read(ownerRepositoryProvider)
      .getDailyClosingSummary(ref.read(ownerRestaurantIdProvider));
});

final lunchPriceProvider = FutureProvider.autoDispose<double>((ref) {
  return ref.read(ownerCashRepositoryProvider).getSingleLunchPrice(ref.read(ownerRestaurantIdProvider));
});

final ownerClientsProvider = FutureProvider.autoDispose<List<OwnerClient>>((ref) {
  return ref.read(ownerCashRepositoryProvider).getClients(ref.read(ownerRestaurantIdProvider));
});

final planTemplatesProvider = FutureProvider.autoDispose<List<OwnerPlanTemplate>>((ref) {
  return ref.read(ownerCashRepositoryProvider).getPlanTemplates(ref.read(ownerRestaurantIdProvider));
});

final catalogProvider = FutureProvider.autoDispose<List<CatalogItem>>((ref) {
  return ref.read(ownerCashRepositoryProvider).getCatalog(ref.read(ownerRestaurantIdProvider));
});

final posMenuProvider = FutureProvider.autoDispose<DailyMenu?>((ref) {
  return ref.read(ownerMenuRepositoryProvider).getTodayMenu(ref.read(ownerRestaurantIdProvider));
});

/// Disponibilidad reactiva del menú publicado de hoy (`SIN_PUBLICAR`, `DISPONIBLE`, `AGOTADO_TOTAL`).
final menuAvailabilityProvider =
    Provider.autoDispose<MenuAvailabilityState>((ref) {
  final menu = ref.watch(posMenuProvider).value;
  if (menu == null) return MenuAvailabilityState.sinPublicar;
  return menu.availabilityState;
});

/// `true` cuando el menú de hoy está publicado y tiene al menos un plato disponible.
final isTodayMenuPublishedProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(menuAvailabilityProvider) ==
      MenuAvailabilityState.disponible;
});

/// Ofertas vigentes del local: N flash (un plato cada una) + promo programada.
final activeOffersProvider = FutureProvider.autoDispose<List<FlashOffer>>((ref) {
  return ref.read(ownerCashRepositoryProvider).getActiveOffers(ref.read(ownerRestaurantIdProvider));
});

final ordersOnTheWayProvider = FutureProvider.autoDispose<int>((ref) {
  _scheduleOrdersPoll(ref, interval: const Duration(seconds: 15));
  return ref.read(ownerCashRepositoryProvider).getOrdersOnTheWayCount(ref.read(ownerRestaurantIdProvider));
});

final shiftClosedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.read(ownerCashRepositoryProvider).isShiftClosed(ref.read(ownerRestaurantIdProvider));
});

/// Estado manual del semáforo en Caja y temporizador local de `LLENO`.
@immutable
class ManualOccupancyState {
  const ManualOccupancyState({
    this.manual = ManualOccupancyStatus.libre,
    this.fullUntil,
    this.concurridoUntil,
    this.tick = 0,
  });

  final ManualOccupancyStatus manual;
  final DateTime? fullUntil;
  final DateTime? concurridoUntil;
  final int tick;
}

final manualOccupancyProvider =
    NotifierProvider<ManualOccupancyNotifier, ManualOccupancyState>(
  ManualOccupancyNotifier.new,
);

/// Fuente de verdad única en Dueño del estado público efectivo del restaurante.
/// Jerarquía: 1) `CERRADO` manual; 2) `AGOTADO_HOY` si menú sin disponibles; 3) semáforo manual.
final ownerPublicStatusProvider =
    Provider.autoDispose<RestaurantPublicStatus>((ref) {
  final menuAvail = ref.watch(menuAvailabilityProvider);
  final manualState = ref.watch(manualOccupancyProvider);
  return resolveRestaurantPublicStatus(
    menuAvailability: menuAvail,
    manual: manualState.manual,
    isOpen: manualState.manual != ManualOccupancyStatus.cerrado,
    fullUntil: manualState.fullUntil,
    concurridoUntil: manualState.concurridoUntil,
  );
});

/// Compatibilidad: fecha límite mientras el local está marcado `LLENO`.
final busyUntilProvider = Provider<DateTime?>(
  (ref) => ref.watch(manualOccupancyProvider).fullUntil,
);

class ManualOccupancyNotifier extends Notifier<ManualOccupancyState> {
  static const busyDuration = Duration(minutes: 20);
  static const extendDuration = Duration(minutes: 15);
  Timer? _timer;
  bool _loadedFromApi = false;
  bool _disposed = false;

  @override
  ManualOccupancyState build() {
    ref.watch(ownerRestaurantIdProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });
    if (!AppMode.useMock && !_loadedFromApi) {
      _loadedFromApi = true;
      Future.microtask(_loadInitial);
    }
    return const ManualOccupancyState();
  }

  Future<void> _loadInitial() async {
    final repo = ref.read(apiOwnerRepositoryProvider);
    final snap = await repo.fetchManualOccupancyState();
    if (_disposed) return;
    if (!snap.isOpen || snap.manual == ManualOccupancyStatus.cerrado) {
      _timer?.cancel();
      _timer = null;
      state = const ManualOccupancyState(manual: ManualOccupancyStatus.cerrado);
      return;
    }
    if (snap.manual == ManualOccupancyStatus.lleno) {
      state = ManualOccupancyState(
        manual: ManualOccupancyStatus.lleno,
        fullUntil: snap.fullUntil,
      );
      if (snap.fullUntil != null) {
        _startTimer();
      } else {
        _timer?.cancel();
        _timer = null;
      }
      return;
    }
    if (snap.manual == ManualOccupancyStatus.concurrido) {
      state = ManualOccupancyState(
        manual: ManualOccupancyStatus.concurrido,
        concurridoUntil: snap.concurridoUntil,
      );
      if (snap.concurridoUntil != null) {
        _startTimer();
      } else {
        _timer?.cancel();
        _timer = null;
      }
      return;
    }
    _timer?.cancel();
    _timer = null;
    state = const ManualOccupancyState(manual: ManualOccupancyStatus.libre);
  }

  Future<void> refreshFromServer() async {
    if (AppMode.useMock || _disposed) return;
    try {
      await _loadInitial();
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_disposed) return;
      final until = switch (state.manual) {
        ManualOccupancyStatus.lleno => state.fullUntil,
        ManualOccupancyStatus.concurrido => state.concurridoUntil,
        _ => null,
      };
      if (until == null) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      if (!until.isAfter(DateTime.now())) {
        _timer?.cancel();
        _timer = null;
        if (!AppMode.useMock) {
          unawaited(refreshFromServer());
        } else {
          unawaited(setStatus(ManualOccupancyStatus.libre));
        }
        return;
      }
      state = ManualOccupancyState(
        manual: state.manual,
        fullUntil: state.fullUntil,
        concurridoUntil: state.concurridoUntil,
        tick: state.tick + 1,
      );
    });
  }

  Future<String?> setStatus(ManualOccupancyStatus next) async {
    final prev = state;
    final rid = ref.read(ownerRestaurantIdProvider);
    final cashRepo = ref.read(ownerCashRepositoryProvider);

    if (next == ManualOccupancyStatus.lleno ||
        next == ManualOccupancyStatus.concurrido) {
      final until = DateTime.now().add(busyDuration);
      final syncedUntil = await cashRepo.setManualOccupancy(
        rid,
        status: next,
        fullUntil: until,
      );
      if (_disposed) return null;
      final apiErr = !AppMode.useMock && cashRepo is ApiOwnerRepository
          ? cashRepo.consumeLastError()
          : null;
      if (syncedUntil == null || (apiErr != null && apiErr.isNotEmpty)) {
        state = prev;
        return (apiErr != null && apiErr.isNotEmpty)
            ? apiErr
            : (next == ManualOccupancyStatus.lleno
                ? 'No se pudo marcar como Lleno en el servidor.'
                : 'No se pudo marcar como Concurrido en el servidor.');
      }
      final confirmedUntil =
          syncedUntil.isAfter(DateTime.now()) ? syncedUntil : until;
      state = ManualOccupancyState(
        manual: next,
        fullUntil: next == ManualOccupancyStatus.lleno ? confirmedUntil : null,
        concurridoUntil:
            next == ManualOccupancyStatus.concurrido ? confirmedUntil : null,
        tick: prev.tick + 1,
      );
      RestaurantStatusLiveSync.instance.notifyStatusChanged(
        restaurantId: rid,
        status: next,
        until: confirmedUntil,
      );
      _startTimer();
      return null;
    }

    await cashRepo.setManualOccupancy(
      rid,
      status: next,
    );
    if (_disposed) return null;
    final apiErr = !AppMode.useMock && cashRepo is ApiOwnerRepository
        ? cashRepo.consumeLastError()
        : null;
    if (apiErr != null && apiErr.isNotEmpty) {
      state = prev;
      return apiErr;
    }
    _timer?.cancel();
    _timer = null;
    state = ManualOccupancyState(manual: next, tick: prev.tick + 1);
    RestaurantStatusLiveSync.instance.notifyStatusChanged(
      restaurantId: rid,
      status: next,
    );
    return null;
  }

  Future<String?> extendFull15Min() async {
    final prev = state;
    final rid = ref.read(ownerRestaurantIdProvider);
    final cashRepo = ref.read(ownerCashRepositoryProvider);
    final base = (prev.fullUntil != null && prev.fullUntil!.isAfter(DateTime.now()))
        ? prev.fullUntil!
        : DateTime.now();
    final extendedUntil = base.add(extendDuration);
    final synced = await cashRepo.setManualOccupancy(
      rid,
      status: ManualOccupancyStatus.lleno,
      fullUntil: extendedUntil,
    );
    if (_disposed) return null;
    final apiErr = !AppMode.useMock && cashRepo is ApiOwnerRepository
        ? cashRepo.consumeLastError()
        : null;
    if (synced == null || (apiErr != null && apiErr.isNotEmpty)) {
      state = prev;
      return (apiErr != null && apiErr.isNotEmpty)
          ? apiErr
          : 'No se pudo extender el tiempo de Lleno.';
    }
    final confirmedUntil =
        synced.isAfter(DateTime.now()) ? synced : extendedUntil;
    state = ManualOccupancyState(
      manual: ManualOccupancyStatus.lleno,
      fullUntil: confirmedUntil,
      tick: prev.tick + 1,
    );
    _startTimer();
    return null;
  }
}

final ownerControllerProvider =
    NotifierProvider<OwnerController, OwnerState>(OwnerController.new);

/// Estado del escaneo del Dueño.
@immutable
sealed class OwnerState {
  const OwnerState();
}

/// En espera: no hay un escaneo en curso ni resultado que mostrar.
class OwnerIdle extends OwnerState {
  const OwnerIdle();
}

/// Cámara activa; [isProcessing] es `true` mientras se valida el código.
class OwnerScanning extends OwnerState {
  const OwnerScanning({this.isProcessing = false});

  final bool isProcessing;
}

/// Pase válido. [redeemed] es `true` cuando el almuerzo ya se descontó.
class OwnerSuccess extends OwnerState {
  const OwnerSuccess(this.result, {this.redeemed = false});

  final ScanResult result;
  final bool redeemed;
}

/// El QR no es un pase: es una mesa (`BCD-MESA-…`) o una preorden
/// (`BCD-ORD-…`). Caja abre [location] al cerrar el escáner.
class OwnerRedirect extends OwnerState {
  const OwnerRedirect(this.location);

  final String location;
}

/// Pase rechazado (con [result]) o error inesperado (solo [message]).
class OwnerError extends OwnerState {
  const OwnerError(this.message, {this.result});

  final String message;
  final ScanResult? result;
}

/// Escanear → validar → descontar (con deshacer de 10 s, como el prototipo).
class OwnerController extends Notifier<OwnerState> {
  /// Evita procesar las múltiples detecciones que emite la cámara por QR.
  bool _busy = false;
  String? _lastNetworkRetryCode;

  IOwnerRepository get _repo => ref.read(ownerRepositoryProvider);

  @override
  OwnerState build() => const OwnerIdle();

  void startScanning() {
    if (_busy) return;
    state = const OwnerScanning();
  }

  void reset() {
    if (_busy) return;
    state = const OwnerIdle();
  }

  /// Prefijos de los QR que no son pases (escáner universal de Caja).
  static const tablePrefix = 'BCD-MESA-';
  static const orderPrefix = 'BCD-ORD-';

  /// Reintenta el último escaneo fallido por red reutilizando el mismo `Idempotency-Key`.
  Future<void> retryLastCode() async {
    final code = _lastNetworkRetryCode;
    if (code == null || code.isEmpty || _busy) return;
    state = const OwnerIdle();
    await onCodeDetected(code);
  }

  /// Valida un QR leído por la cámara o ingresado a mano. Reconoce todos los
  /// formatos: código corto de 6 caracteres, pase de plan (`BCD1.`), mesa
  /// (`BCD-MESA-`), preorden (`BCD-ORD-`, UUID o `#N`).
  Future<void> onCodeDetected(String rawPayload) async {
    if (_busy || state is OwnerSuccess || state is OwnerError || state is OwnerRedirect) return;
    if (rawPayload.trim().isEmpty) return;

    _busy = true;
    _lastNetworkRetryCode = null;
    state = const OwnerScanning(isProcessing: true);
    try {
      final trimmed = rawPayload.trim();
      final upper = trimmed.toUpperCase();
      final couldBeOrder = !trimmed.startsWith('BCD1.') &&
          !upper.startsWith(BocadooQrParser.planPrefix) &&
          !upper.startsWith('BCD-MESA-') &&
          !upper.startsWith('MESA-');
      if (couldBeOrder) {
        final orderCheck = await ref
            .read(ownerOrdersRepositoryProvider)
            .verifyOrderQrCode(
              rawPayload,
              ref.read(ownerRestaurantIdProvider),
            );
        if (orderCheck.isValid &&
            orderCheck.order != null &&
            !orderCheck.order!.paidByPlan) {
          state = OwnerRedirect('/owner/pedidos?cobrar=${orderCheck.order!.number}');
          return;
        }
      }

      final result = await _repo.validateQrCode(rawPayload);
      final passId = result.passId;
      if (!result.isValid || passId == null) {
        if (result.title == 'Menú no publicado') {
          ref.invalidate(posMenuProvider);
        }
        state = OwnerError(result.supportingLine, result: result);
        return;
      }
      final ok = await _repo.confirmRedeem(passId);
      state = ok
          ? OwnerSuccess(result, redeemed: true)
          : OwnerError('No se pudo registrar el almuerzo.', result: result);
    } on ApiException catch (e) {
      if (e.code == 'MENU_NO_PUBLICADO') {
        ref.invalidate(posMenuProvider);
        const result = ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Menú no publicado',
          supportingLine:
              'No se puede escanear QR sin haber publicado el menú de hoy',
          actionRequired: 'PUBLISH_MENU',
        );
        state = OwnerError(result.supportingLine, result: result);
      } else if (e.isNetwork || e.status == 504) {
        _lastNetworkRetryCode = rawPayload;
        final result = ScanResult(
          isValid: false,
          outcome: 'ROJO',
          title: 'Sin conexión',
          supportingLine: e.userMessage,
          actionRequired: 'RETRY_NETWORK',
        );
        state = OwnerError(e.userMessage, result: result);
      } else {
        state = OwnerError(e.userMessage);
      }
    } catch (e) {
      state = OwnerError('No se pudo validar el código: $e');
    } finally {
      _busy = false;
    }
  }

  /// Registra invitados extras sobre un lote de canje sin bloquear la UI.
  Future<bool> commitExtraGuests({
    required String passId,
    required int extraGuests,
    String? batchRedemptionId,
  }) async {
    if (extraGuests <= 0) return true;
    final ok = await ref.read(ownerCashRepositoryProvider).commitExtraGuests(
          passId: passId,
          extraGuests: extraGuests,
          batchRedemptionId: batchRedemptionId,
        );
    ref.invalidate(dailySummaryProvider);
    return ok;
  }

  /// Revierte el lote completo de canje (`1` titular + `invitadosExtras`).
  Future<bool> undoBatchRedemption(
    String batchRedemptionId, {
    String? fallbackPassId,
  }) async {
    final ok = await ref.read(ownerCashRepositoryProvider).undoBatchRedemption(
          batchRedemptionId,
          fallbackPassId: fallbackPassId,
        );
    if (ok) {
      if (state is OwnerSuccess) state = const OwnerIdle();
      ref.invalidate(dailySummaryProvider);
    }
    return ok;
  }

  /// Revierte el último descuento del pase mostrado.
  Future<bool> undoRedeem() async {
    final current = state;
    final result = current is OwnerSuccess ? current.result : null;
    final passId = result?.passId;
    if (passId == null) return false;
    final batchId = result?.batchRedemptionId;
    final ok = batchId != null && batchId.isNotEmpty
        ? await undoBatchRedemption(batchId, fallbackPassId: passId)
        : await ref.read(ownerCashRepositoryProvider).undoRedeem(passId);
    if (ok) {
      state = const OwnerIdle();
      ref.invalidate(dailySummaryProvider);
    }
    return ok;
  }
}

/// Precios fijos del menú ejecutivo (Ajustes -> Menú de hoy -> POS).
@immutable
class ExecutivePrices {
  const ExecutivePrices({
    this.lunch = 3.00,
    this.soloSecond = 2.50,
    this.soloSoup = 1.50,
    this.takeawaySurcharge = 0.25,
  });

  final double lunch;
  final double soloSecond;
  final double soloSoup;
  final double takeawaySurcharge;

  ExecutivePrices copyWith({
    double? lunch,
    double? soloSecond,
    double? soloSoup,
    double? takeawaySurcharge,
  }) {
    return ExecutivePrices(
      lunch: lunch ?? this.lunch,
      soloSecond: soloSecond ?? this.soloSecond,
      soloSoup: soloSoup ?? this.soloSoup,
      takeawaySurcharge: takeawaySurcharge ?? this.takeawaySurcharge,
    );
  }
}

class ExecutivePricesNotifier extends Notifier<ExecutivePrices> {
  double? _lunchOverride;
  double _soloSecond = 2.50;
  double _soloSoup = 1.50;
  double _takeawaySurcharge = 0.25;

  @override
  ExecutivePrices build() {
    final serverLunch = ref.watch(lunchPriceProvider).value;
    final lunch = _lunchOverride ??
        (serverLunch != null && serverLunch > 0 ? serverLunch : 3.00);
    return ExecutivePrices(
      lunch: lunch,
      soloSecond: _soloSecond,
      soloSoup: _soloSoup,
      takeawaySurcharge: _takeawaySurcharge,
    );
  }

  void setPrices({
    required double lunch,
    required double soloSecond,
    required double soloSoup,
    required double takeawaySurcharge,
  }) {
    _lunchOverride = lunch;
    _soloSecond = soloSecond;
    _soloSoup = soloSoup;
    _takeawaySurcharge = takeawaySurcharge;
    state = ExecutivePrices(
      lunch: lunch,
      soloSecond: soloSecond,
      soloSoup: soloSoup,
      takeawaySurcharge: takeawaySurcharge,
    );
  }
}

final executivePricesProvider =
    NotifierProvider<ExecutivePricesNotifier, ExecutivePrices>(
  ExecutivePricesNotifier.new,
);

/// Categorías del catálogo fijo permanente (`Carta y Bebidas`).
enum PermanentCatalogGroup { carta, bebidas, extras }

@immutable
class PermanentCatalogItem {
  const PermanentCatalogItem({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.group,
    this.available = true,
    this.description = '',
    this.isDessert = false,
  });

  final String id;
  final String name;
  final int priceCents;
  final PermanentCatalogGroup group;
  final bool available;
  final String description;
  final bool isDessert;

  PermanentCatalogItem copyWith({
    String? id,
    String? name,
    int? priceCents,
    PermanentCatalogGroup? group,
    bool? available,
    String? description,
    bool? isDessert,
  }) {
    return PermanentCatalogItem(
      id: id ?? this.id,
      name: name ?? this.name,
      priceCents: priceCents ?? this.priceCents,
      group: group ?? this.group,
      available: available ?? this.available,
      description: description ?? this.description,
      isDessert: isDessert ?? this.isDessert,
    );
  }
}

@immutable
class PermanentCatalogState {
  const PermanentCatalogState({
    this.items = const [],
    this.dirty = false,
  });

  final List<PermanentCatalogItem> items;
  final bool dirty;
}

class PermanentCatalogNotifier extends Notifier<PermanentCatalogState> {
  static const _defaultItems = <PermanentCatalogItem>[
    PermanentCatalogItem(
      id: 'perm_carta_churrasco',
      name: 'Churrasco',
      priceCents: 550,
      group: PermanentCatalogGroup.carta,
      description: 'Carne, huevo, papas fritas y ensalada',
    ),
    PermanentCatalogItem(
      id: 'perm_carta_seco',
      name: 'Seco de pollo',
      priceCents: 450,
      group: PermanentCatalogGroup.carta,
      description: 'Con arroz amarillo y maduro',
    ),
    PermanentCatalogItem(
      id: 'perm_carta_lomo',
      name: 'Lomo saltado',
      priceCents: 500,
      group: PermanentCatalogGroup.carta,
      description: 'Res salteada con cebolla, tomate y papas',
    ),
    PermanentCatalogItem(
      id: 'perm_beb_cola',
      name: 'Cola personal',
      priceCents: 75,
      group: PermanentCatalogGroup.bebidas,
      description: '350 ml',
    ),
    PermanentCatalogItem(
      id: 'perm_beb_agua',
      name: 'Agua sin gas',
      priceCents: 60,
      group: PermanentCatalogGroup.bebidas,
      description: '500 ml',
    ),
    PermanentCatalogItem(
      id: 'perm_beb_jarra',
      name: 'Jarra de jugo',
      priceCents: 250,
      group: PermanentCatalogGroup.bebidas,
      description: 'Jugo natural para compartir',
    ),
    PermanentCatalogItem(
      id: 'perm_ext_flan',
      name: 'Flan de coco',
      priceCents: 100,
      group: PermanentCatalogGroup.extras,
      isDessert: true,
    ),
    PermanentCatalogItem(
      id: 'perm_ext_tres_leches',
      name: 'Porción tres leches',
      priceCents: 150,
      group: PermanentCatalogGroup.extras,
      isDessert: true,
    ),
    PermanentCatalogItem(
      id: 'perm_ext_aguacate',
      name: 'Porción de aguacate',
      priceCents: 75,
      group: PermanentCatalogGroup.extras,
    ),
    PermanentCatalogItem(
      id: 'perm_ext_huevo',
      name: 'Huevo frito',
      priceCents: 50,
      group: PermanentCatalogGroup.extras,
    ),
    PermanentCatalogItem(
      id: 'perm_ext_arroz',
      name: 'Porción de arroz',
      priceCents: 50,
      group: PermanentCatalogGroup.extras,
    ),
  ];

  final Map<String, int> _priceOverrides = {};
  final Map<String, bool> _availableOverrides = {};
  final List<PermanentCatalogItem> _addedItems = [];
  final Set<String> _removedIds = {};
  bool _dirty = false;
  int _seq = 1;

  @override
  PermanentCatalogState build() {
    final posCatalog = ref.watch(catalogProvider).value ?? const <CatalogItem>[];
    final dishes = ref.watch(catalogDishesProvider).value ?? const <CatalogDish>[];
    final todayMenu = ref.watch(posMenuProvider).value;

    final lunchJuices = <String>{
      if (todayMenu != null)
        for (final c in todayMenu.courses)
          if (c.category == 'Jugo') c.name.trim().toLowerCase(),
    };

    final merged = <PermanentCatalogItem>[];
    final seenNames = <String>{};

    void addCandidate(PermanentCatalogItem raw) {
      if (_removedIds.contains(raw.id)) return;
      final norm = '${raw.group.name}|${raw.name.trim().toLowerCase()}';
      if (!seenNames.add(norm)) return;
      merged.add(
        raw.copyWith(
          priceCents: _priceOverrides[raw.id] ?? raw.priceCents,
          available: _availableOverrides[raw.id] ?? raw.available,
        ),
      );
    }

    final archivedIds = <String>{
      for (final d in dishes)
        if (d.archived) d.id,
    };
    final soldOutById = <String, bool>{
      for (final d in dishes) d.id: d.soldOut || d.archived,
    };

    for (final item in posCatalog) {
      if (archivedIds.contains(item.id)) continue;
      final group = switch (item.category) {
        PosCategory.carta => PermanentCatalogGroup.carta,
        PosCategory.bebidas => PermanentCatalogGroup.bebidas,
        PosCategory.extras => PermanentCatalogGroup.extras,
        PosCategory.almuerzos || PosCategory.desayunos => null,
      };
      if (group == null) continue;
      final normName = item.name.trim().toLowerCase();
      if (group == PermanentCatalogGroup.bebidas &&
          (lunchJuices.contains(normName) ||
              normName.contains('vaso de jugo') ||
              normName.contains('jugo incluido'))) {
        continue;
      }
      addCandidate(
        PermanentCatalogItem(
          id: item.id,
          name: item.name,
          priceCents: Money.toCents(item.price),
          group: group,
          available: !(soldOutById[item.id] ?? false),
          description: item.description,
          isDessert: item.isDessert,
        ),
      );
    }

    for (final d in dishes) {
      if (d.kind != DishKind.carta || d.archived) continue;
      addCandidate(
        PermanentCatalogItem(
          id: d.id,
          name: d.name,
          priceCents: Money.toCents(d.price ?? 4.50),
          group: PermanentCatalogGroup.carta,
          available: !d.archived && !d.soldOut,
          description: d.description,
        ),
      );
    }

    for (final added in _addedItems) {
      addCandidate(added);
    }

    if (AppMode.useMock) {
      for (final g in PermanentCatalogGroup.values) {
        if (merged.where((e) => e.group == g).isEmpty) {
          for (final def in _defaultItems.where((d) => d.group == g)) {
            addCandidate(def);
          }
        }
      }
    }

    return PermanentCatalogState(items: merged, dirty: _dirty);
  }

  Future<String?> addItem({
    required String name,
    required int priceCents,
    required PermanentCatalogGroup group,
    bool available = true,
    bool isDessert = false,
    String description = '',
  }) async {
    final rid = ref.read(ownerRestaurantIdProvider);
    if (!AppMode.useMock) {
      final repo = ref.read(ownerCatalogRepositoryProvider);
      final (String categoria, String seccion, List<String> etiquetas) =
          switch (group) {
        PermanentCatalogGroup.carta => ('A_LA_CARTA', 'FUERTE', const <String>[]),
        PermanentCatalogGroup.bebidas => ('BEBIDA', 'BEBIDA', const <String>[]),
        PermanentCatalogGroup.extras => (
            'EXTRA',
            isDessert ? 'POSTRE' : 'ADICIONAL',
            [isDessert ? 'POSTRE' : 'EXTRA'],
          ),
      };
      final created = await repo.addPermanentDish(
        rid,
        name: name.trim(),
        priceCents: priceCents,
        categoria: categoria,
        seccion: seccion,
        etiquetas: etiquetas,
        description: description.trim(),
      );
      if (created == null) {
        if (repo is ApiOwnerRepository) {
          return repo.consumeLastError() ??
              'No se pudo publicar el plato en el catálogo.';
        }
        return 'No se pudo publicar el plato en el catálogo.';
      }
      if (!available) {
        await repo.setCatalogDishSoldOut(rid, created.id, soldOut: true);
      }
      final newItem = PermanentCatalogItem(
        id: created.id,
        name: created.name,
        priceCents: Money.toCents(created.price ?? (priceCents / 100.0)),
        group: group,
        available: available,
        description: created.description,
        isDessert: isDessert,
      );
      _addedItems.add(newItem);
      state = PermanentCatalogState(
        items: [...state.items, newItem],
        dirty: _dirty,
      );
      ref.invalidate(catalogProvider);
      ref.invalidate(catalogDishesProvider);
      MenuAndCartaLiveSync.instance.notifyUpdated(rid);
      return null;
    }

    final item = PermanentCatalogItem(
      id: 'local_${group.name}_${_seq++}',
      name: name.trim(),
      priceCents: priceCents,
      group: group,
      available: available,
      description: description.trim(),
      isDessert: isDessert,
    );
    _addedItems.add(item);
    _dirty = true;
    state = PermanentCatalogState(
      items: [...state.items, item],
      dirty: true,
    );
    MenuAndCartaLiveSync.instance.notifyUpdated(rid);
    return null;
  }

  Future<String?> updatePrice(String id, int priceCents) async {
    final prevOverride = _priceOverrides[id];
    final prevState = state;
    final isLocalOnly = id.startsWith('perm_') || id.startsWith('local_');

    _priceOverrides[id] = priceCents;
    for (var i = 0; i < _addedItems.length; i++) {
      if (_addedItems[i].id == id) {
        _addedItems[i] = _addedItems[i].copyWith(priceCents: priceCents);
      }
    }
    if (isLocalOnly) _dirty = true;
    state = PermanentCatalogState(
      items: [
        for (final item in state.items)
          item.id == id ? item.copyWith(priceCents: priceCents) : item,
      ],
      dirty: _dirty,
    );

    if (AppMode.useMock || isLocalOnly) return null;

    final rid = ref.read(ownerRestaurantIdProvider);
    final repo = ref.read(ownerCatalogRepositoryProvider);
    final ok = await repo.updateCatalogDishPrice(
      rid,
      id,
      priceCents: priceCents,
    );
    if (ok) {
      ref.invalidate(catalogProvider);
      ref.invalidate(catalogDishesProvider);
      MenuAndCartaLiveSync.instance.notifyUpdated(rid);
      return null;
    }

    if (prevOverride == null) {
      _priceOverrides.remove(id);
    } else {
      _priceOverrides[id] = prevOverride;
    }
    state = prevState;
    if (repo is ApiOwnerRepository) {
      return repo.consumeLastError() ?? 'No se pudo actualizar el precio.';
    }
    return 'No se pudo actualizar el precio.';
  }

  /// Alterna `Disponible / Agotado` conectando con `PATCH /v1/menu/platos/{id}/agotado`.
  /// Devuelve `null` si tuvo éxito o un mensaje de error si hubo rollback (p. ej. `403`).
  Future<String?> setAvailable(String id, bool available) async {
    final prevOverride = _availableOverrides[id];
    final prevState = state;
    final isLocalOnly = id.startsWith('perm_') || id.startsWith('local_');

    _availableOverrides[id] = available;
    for (var i = 0; i < _addedItems.length; i++) {
      if (_addedItems[i].id == id) {
        _addedItems[i] = _addedItems[i].copyWith(available: available);
      }
    }
    if (isLocalOnly) _dirty = true;
    state = PermanentCatalogState(
      items: [
        for (final item in state.items)
          item.id == id ? item.copyWith(available: available) : item,
      ],
      dirty: _dirty,
    );

    if (isLocalOnly) return null;

    final rid = ref.read(ownerRestaurantIdProvider);
    final repo = ref.read(ownerCatalogRepositoryProvider);
    final ok = await repo.setCatalogDishSoldOut(
      rid,
      id,
      soldOut: !available,
    );
    if (ok) {
      MenuAndCartaLiveSync.instance.notifyUpdated(rid);
      return null;
    }

    // Rollback optimista si el servidor rechazó el cambio (p. ej. 403 o red).
    if (prevOverride == null) {
      _availableOverrides.remove(id);
    } else {
      _availableOverrides[id] = prevOverride;
    }
    state = prevState;
    if (repo is ApiOwnerRepository) {
      return repo.consumeLastError() ??
          'No se pudo actualizar la disponibilidad del plato.';
    }
    return 'No se pudo actualizar la disponibilidad del plato.';
  }

  /// Da de baja definitiva un ítem de `Carta y Bebidas` (`activo: false`)
  /// y sincroniza el POS sin afectar pedidos históricos.
  Future<String?> removeItem(String id) async {
    final prevState = state;
    final isLocalOnly = id.startsWith('perm_') || id.startsWith('local_');
    final rid = ref.read(ownerRestaurantIdProvider);

    _removedIds.add(id);
    _addedItems.removeWhere((item) => item.id == id);
    state = PermanentCatalogState(
      items: [
        for (final item in state.items)
          if (item.id != id) item,
      ],
      dirty: _dirty,
    );

    if (AppMode.useMock || isLocalOnly) {
      MenuAndCartaLiveSync.instance.notifyUpdated(rid);
      return null;
    }

    try {
      await ref
          .read(ownerCatalogRepositoryProvider)
          .setDishArchived(rid, id, archived: true);
      ref.invalidate(catalogProvider);
      ref.invalidate(catalogDishesProvider);
      MenuAndCartaLiveSync.instance.notifyUpdated(rid);
      return null;
    } on ApiException catch (e) {
      _removedIds.remove(id);
      state = prevState;
      final detail = e.detail.trim();
      return detail.isNotEmpty ? detail : e.userMessage;
    } catch (_) {
      _removedIds.remove(id);
      state = prevState;
      return 'No se pudo eliminar el ítem.';
    }
  }

  void saveChanges() {
    _dirty = false;
    state = PermanentCatalogState(items: state.items, dirty: false);
    MenuAndCartaLiveSync.instance.notifyUpdated(ref.read(ownerRestaurantIdProvider));
  }
}

final permanentCatalogProvider =
    NotifierProvider<PermanentCatalogNotifier, PermanentCatalogState>(
  PermanentCatalogNotifier.new,
);
