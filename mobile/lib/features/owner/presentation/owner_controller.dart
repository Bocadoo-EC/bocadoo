import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../data/mock_owner_repo.dart';
import '../data/repositories/owner_repository.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/daily_menu.dart';
import '../domain/models/extras_models.dart';
import '../domain/models/menu_models.dart';
import '../domain/models/metrics_models.dart';
import '../domain/repositories/i_owner_repository.dart';

/// Un solo mock compartido para que escaneo, caja, menú y cierre vean los
/// mismos datos. Para el backend real basta con reemplazar estas instancias.
final _sharedMock = MockOwnerRepository();
final _sharedOwnerRepository = OwnerRepository(delegate: _sharedMock);

final ownerRepositoryProvider = Provider<IOwnerRepository>(
  (ref) => _sharedOwnerRepository,
);

final ownerMenuRepositoryProvider = Provider<IOwnerMenuRepository>(
  (ref) => _sharedOwnerRepository,
);

final ownerCashRepositoryProvider = Provider<IOwnerCashRepository>(
  (ref) => _sharedMock,
);

final ownerCatalogRepositoryProvider = Provider<IOwnerCatalogRepository>(
  (ref) => _sharedOwnerRepository,
);

final ownerMetricsRepositoryProvider = Provider<IOwnerMetricsRepository>(
  (ref) => _sharedMock,
);

final ownerOrdersRepositoryProvider = Provider<IOwnerOrdersRepository>((ref) => _sharedMock);

final ownerTablesRepositoryProvider = Provider<IOwnerTablesRepository>((ref) => _sharedMock);

final ownerFeedbackRepositoryProvider = Provider<IOwnerFeedbackRepository>((ref) => _sharedMock);

final ownerSettingsRepositoryProvider = Provider<IOwnerSettingsRepository>((ref) => _sharedMock);

/// O12 · Preórdenes por cobrar y entregar.
final activeOrdersProvider = FutureProvider.autoDispose<List<OwnerOrder>>((ref) {
  return ref.read(ownerOrdersRepositoryProvider).getActiveOrders(ref.read(ownerRestaurantIdProvider));
});

/// Mesas con amigos por cobrar (banner de Caja).
final pendingTablesProvider = FutureProvider.autoDispose<List<PendingTable>>((ref) {
  return ref.read(ownerTablesRepositoryProvider).getPendingTables(ref.read(ownerRestaurantIdProvider));
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
    _load();
    return OwnerRole.owner;
  }

  Future<void> _load() async {
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

/// Restaurante de la caja actual (mock; el backend lo entregará con la sesión).
final ownerRestaurantIdProvider = Provider<String>((ref) => 'rest-001');

/// Nombre del local (mock; el backend lo entregará con la sesión).
final ownerRestaurantNameProvider = Provider<String>((ref) => 'La Cuchara de San Blas');

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
  return ref.read(ownerCashRepositoryProvider).getOrdersOnTheWayCount(ref.read(ownerRestaurantIdProvider));
});

final shiftClosedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.read(ownerCashRepositoryProvider).isShiftClosed(ref.read(ownerRestaurantIdProvider));
});

/// Hora hasta la que el local está marcado lleno a mano (`null` = no marcado).
final busyUntilProvider = NotifierProvider<BusyUntilNotifier, DateTime?>(BusyUntilNotifier.new);

class BusyUntilNotifier extends Notifier<DateTime?> {
  static const busyDuration = Duration(minutes: 20);

  @override
  DateTime? build() => null;

  bool get isBusy => state != null && state!.isAfter(DateTime.now());

  Future<void> toggle() async {
    final busy = !isBusy;
    state = busy ? DateTime.now().add(busyDuration) : null;
    await ref
        .read(ownerCashRepositoryProvider)
        .setManualBusy(ref.read(ownerRestaurantIdProvider), busy: busy);
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

  /// Valida un QR leído por la cámara o ingresado a mano. Reconoce los tres
  /// formatos: pase de plan (descuenta el almuerzo), mesa y preorden.
  Future<void> onCodeDetected(String rawPayload) async {
    if (_busy || state is OwnerSuccess || state is OwnerError || state is OwnerRedirect) return;
    final code = rawPayload.trim();
    if (code.isEmpty) return;

    final upper = code.toUpperCase();
    if (upper.startsWith(tablePrefix) && upper.length > tablePrefix.length) {
      state = OwnerRedirect('/owner/cobrar-mesa/${upper.substring(tablePrefix.length)}');
      return;
    }
    if (upper.startsWith(orderPrefix) && upper.length > orderPrefix.length) {
      state = OwnerRedirect('/owner/pedidos?cobrar=${upper.substring(orderPrefix.length)}');
      return;
    }

    _busy = true;
    state = const OwnerScanning(isProcessing: true);
    try {
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
