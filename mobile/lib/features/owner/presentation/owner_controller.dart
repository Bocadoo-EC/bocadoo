import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../data/mock_owner_repo.dart';
import '../data/repositories/owner_repository.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/daily_menu.dart';
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

/// Restaurante de la caja actual (mock; el backend lo entregará con la sesión).
final ownerRestaurantIdProvider = Provider<String>((ref) => 'rest-001');

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

  /// Valida un QR leído por la cámara o ingresado a mano y, si el pase es
  /// válido, descuenta el almuerzo.
  Future<void> onCodeDetected(String rawPayload) async {
    if (_busy || state is OwnerSuccess || state is OwnerError) return;
    final code = rawPayload.trim();
    if (code.isEmpty) return;

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
