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

void _scheduleOrdersPoll(Ref ref) {
  if (AppMode.useMock) return;
  final timer = Timer.periodic(const Duration(seconds: 8), (_) {
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

/// Mesas con amigos por cobrar (banner de Caja).
final pendingTablesProvider = FutureProvider.autoDispose<List<PendingTable>>((ref) {
  if (!ApiCapabilities.ownerPendingTablesList) return Future.value(const []);
  return ref
      .read(ownerTablesRepositoryProvider)
      .getPendingTables(ref.read(ownerRestaurantIdProvider));
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

final activeOfferProvider = FutureProvider.autoDispose<FlashOffer?>((ref) {
  return ref.read(ownerCashRepositoryProvider).getActiveOffer(ref.read(ownerRestaurantIdProvider));
});

final ordersOnTheWayProvider = FutureProvider.autoDispose<int>((ref) {
  _scheduleOrdersPoll(ref);
  return ref.read(ownerCashRepositoryProvider).getOrdersOnTheWayCount(ref.read(ownerRestaurantIdProvider));
});

final shiftClosedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.read(ownerCashRepositoryProvider).isShiftClosed(ref.read(ownerRestaurantIdProvider));
});

/// Hora hasta la que el local está marcado lleno a mano (`null` = no marcado).
final busyUntilProvider = NotifierProvider<BusyUntilNotifier, DateTime?>(BusyUntilNotifier.new);

class BusyUntilNotifier extends Notifier<DateTime?> {
  static const busyDuration = Duration(minutes: 20);
  bool _loadedFromApi = false;

  @override
  DateTime? build() {
    ref.watch(ownerRestaurantIdProvider);
    if (!AppMode.useMock && !_loadedFromApi) {
      _loadedFromApi = true;
      Future.microtask(_loadInitial);
    }
    return null;
  }

  Future<void> _loadInitial() async {
    final until = await ref.read(apiOwnerRepositoryProvider).fetchManualBusyUntil();
    if (until != null) {
      state = until;
    }
  }

  bool get isBusy => state != null && state!.isAfter(DateTime.now());

  Future<void> toggle() async {
    final prev = state;
    final busy = !isBusy;
    state = busy ? DateTime.now().add(busyDuration) : null;
    final ok = await ref
        .read(ownerCashRepositoryProvider)
        .setManualBusy(ref.read(ownerRestaurantIdProvider), busy: busy);
    if (!ok) {
      state = prev;
    }
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
  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Valida un QR leído por la cámara o ingresado a mano. Reconoce todos los
  /// formatos: pase de plan (`BCD1.`), mesa (`BCD-MESA-`), preorden (`BCD-ORD-`,
  /// UUID o `#N`).
  Future<void> onCodeDetected(String rawPayload) async {
    if (_busy || state is OwnerSuccess || state is OwnerError || state is OwnerRedirect) return;
    final code = rawPayload.trim();
    if (code.isEmpty) return;

    final upper = code.toUpperCase();
    if (upper.startsWith(tablePrefix) && code.length > tablePrefix.length) {
      state = OwnerRedirect(
        '/owner/cobrar-mesa/${code.substring(tablePrefix.length).trim()}',
      );
      return;
    }
    if (upper.startsWith(orderPrefix) && code.length > orderPrefix.length) {
      state = OwnerRedirect(
        '/owner/pedidos?cobrar=${code.substring(orderPrefix.length).trim()}',
      );
      return;
    }

    _busy = true;
    state = const OwnerScanning(isProcessing: true);
    try {
      if (!AppMode.useMock) {
        final apiRepo = ref.read(apiOwnerRepositoryProvider);
        if (_uuidRegex.hasMatch(code)) {
          final order = await apiRepo.resolveOrderById(code);
          if (order != null) {
            state = OwnerRedirect('/owner/pedidos?cobrar=${order.number}');
          } else {
            state = OwnerError(
              apiRepo.consumeLastError() ?? 'No encontramos ese pedido.',
            );
          }
          return;
        }
        if (code.startsWith('#') && code.length > 1) {
          final numQuery = code.substring(1).trim();
          final order = await apiRepo.resolveOrderByNumber(numQuery);
          if (order != null) {
            state = OwnerRedirect('/owner/pedidos?cobrar=${order.number}');
          } else {
            state = const OwnerError('No encontramos ese pedido activo.');
          }
          return;
        }
      }

      final result = await _repo.validateQrCode(code);
      final passId = result.passId;
      if (!result.isValid || passId == null) {
        state = OwnerError(result.supportingLine, result: result);
        return;
      }
      final ok = await _repo.confirmRedeem(passId);
      state = ok
          ? OwnerSuccess(result, redeemed: true)
          : OwnerError('No se pudo registrar el almuerzo.', result: result);
    } on ApiException catch (e) {
      state = OwnerError(e.userMessage);
    } catch (e) {
      state = OwnerError('No se pudo validar el código: $e');
    } finally {
      _busy = false;
    }
  }

  /// Revierte el último descuento del pase mostrado.
  Future<bool> undoRedeem() async {
    final current = state;
    final passId = current is OwnerSuccess ? current.result.passId : null;
    if (passId == null) return false;
    final ok = await ref.read(ownerCashRepositoryProvider).undoRedeem(passId);
    if (ok) state = const OwnerIdle();
    return ok;
  }
}
