import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/utils/formatters.dart';
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
  final sim = GroupOrderSimulationStore.instance;
  void onSimChanged() => ref.invalidateSelf();
  sim.addListener(onSimChanged);
  ref.onDispose(() => sim.removeListener(onSimChanged));

  _scheduleOrdersPoll(ref);
  final repoTables = ApiCapabilities.ownerPendingTablesList
      ? await ref
          .read(ownerTablesRepositoryProvider)
          .getPendingTables(ref.read(ownerRestaurantIdProvider))
      : const <PendingTable>[];

  final simTables = sim.confirmedOwnerTables;
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

final activeOfferProvider = FutureProvider.autoDispose<FlashOffer?>((ref) {
  return ref.read(ownerCashRepositoryProvider).getActiveOffer(ref.read(ownerRestaurantIdProvider));
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
    this.tick = 0,
  });

  final ManualOccupancyStatus manual;
  final DateTime? fullUntil;
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
    final rid = ref.read(ownerRestaurantIdProvider);
    final isOpen = await repo.fetchStoreOpen();
    if (_disposed) return;
    if (!isOpen) {
      state = const ManualOccupancyState(manual: ManualOccupancyStatus.cerrado);
      return;
    }
    final until = await repo.fetchManualBusyUntil();
    if (_disposed) return;
    if (until != null && until.isAfter(DateTime.now())) {
      state = ManualOccupancyState(
        manual: ManualOccupancyStatus.lleno,
        fullUntil: until,
      );
      _startTimer();
      return;
    }
    final pref = await repo.fetchManualOccupancyPreference(rid);
    if (_disposed) return;
    if (pref == ManualOccupancyStatus.concurrido) {
      state = const ManualOccupancyState(manual: ManualOccupancyStatus.concurrido);
    }
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
      final until = state.fullUntil;
      if (state.manual != ManualOccupancyStatus.lleno || until == null) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      if (!until.isAfter(DateTime.now())) {
        _timer?.cancel();
        _timer = null;
        unawaited(setStatus(ManualOccupancyStatus.libre));
        return;
      }
      state = ManualOccupancyState(
        manual: state.manual,
        fullUntil: until,
        tick: state.tick + 1,
      );
    });
  }

  Future<String?> setStatus(ManualOccupancyStatus next) async {
    final prev = state;
    final rid = ref.read(ownerRestaurantIdProvider);
    final cashRepo = ref.read(ownerCashRepositoryProvider);

    if (next == ManualOccupancyStatus.lleno) {
      final until = DateTime.now().add(busyDuration);
      final syncedUntil = await cashRepo.setManualOccupancy(
        rid,
        status: ManualOccupancyStatus.lleno,
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
            : 'No se pudo marcar como Lleno en el servidor.';
      }
      final confirmedUntil =
          syncedUntil.isAfter(DateTime.now()) ? syncedUntil : until;
      state = ManualOccupancyState(
        manual: ManualOccupancyStatus.lleno,
        fullUntil: confirmedUntil,
        tick: prev.tick + 1,
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
