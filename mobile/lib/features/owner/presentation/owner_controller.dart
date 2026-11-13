import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../data/mock_owner_repo.dart';
import '../data/repositories/remote_owner_repository.dart';

/// Repositorio del Dueño (conmuta entre mock local y API real según
/// [useRemoteApiProvider]).
final ownerRepositoryProvider = Provider<IOwnerRepository>((ref) {
  final useRemote = ref.watch(useRemoteApiProvider);
  if (useRemote) {
    return RemoteOwnerRepository(dio: ref.watch(dioProvider));
  }
  return MockOwnerRepository();
});

/// Restaurante de la caja actual (mock; el backend lo entregará con la sesión).
final ownerRestaurantIdProvider = Provider<String>((ref) => 'rest-001');

/// Resumen de cierre de caja del día. Se recarga con `ref.invalidate`.
final dailySummaryProvider =
    FutureProvider.autoDispose<TransactionSummary>((ref) {
  return ref
      .read(ownerRepositoryProvider)
      .getDailyClosingSummary(ref.read(ownerRestaurantIdProvider));
});

final ownerControllerProvider =
    NotifierProvider<OwnerController, OwnerState>(OwnerController.new);

/// Estado de la pantalla de escaneo / canje del Dueño.
@immutable
sealed class OwnerState {
  const OwnerState();
}

/// En espera: no hay un escaneo en curso ni resultado que mostrar.
class OwnerIdle extends OwnerState {
  const OwnerIdle();
}

/// Cámara activa y/o validando o confirmando un código. [isProcessing] es
/// `true` mientras se espera respuesta del repositorio.
class OwnerScanning extends OwnerState {
  const OwnerScanning({this.isProcessing = false});

  final bool isProcessing;
}

/// QR validado (VERDE o ADVERTENCIA). [redeemed] pasa a `true` cuando el
/// canje ya fue confirmado y descontado.
class OwnerSuccess extends OwnerState {
  const OwnerSuccess(this.result, {this.redeemed = false});

  final ScanResult result;
  final bool redeemed;
}

/// Falla de validación (ROJO / GRIS, con [result]) o error inesperado
/// (solo [message]).
class OwnerError extends OwnerState {
  const OwnerError(this.message, {this.result});

  final String message;
  final ScanResult? result;
}

/// Controlador MVVM del flujo: escanear → validar → confirmar canje.
class OwnerController extends Notifier<OwnerState> {
  /// Evita procesar las múltiples detecciones que emite la cámara por QR.
  bool _busy = false;

  IOwnerRepository get _repo => ref.read(ownerRepositoryProvider);

  @override
  OwnerState build() => const OwnerIdle();

  /// Abre el escáner (desde Idle, o tras un resultado para escanear otro).
  void startScanning() {
    if (_busy) return;
    state = const OwnerScanning();
  }

  /// Cierra el escáner y vuelve a Idle.
  void reset() {
    if (_busy) return;
    state = const OwnerIdle();
  }

  /// Valida un QR leído por la cámara o ingresado manualmente.
  /// Se ignora si ya hay una validación en curso o un resultado visible.
  Future<void> onCodeDetected(String rawPayload) async {
    if (_busy || state is OwnerSuccess || state is OwnerError) return;
    final code = rawPayload.trim();
    if (code.isEmpty) return;

    _busy = true;
    state = const OwnerScanning(isProcessing: true);
    try {
      final result = await _repo.validateQrCode(code);
      state = result.isValid
          ? OwnerSuccess(result)
          : OwnerError(result.supportingLine, result: result);
    } catch (e) {
      state = OwnerError('No se pudo validar el código: $e');
    } finally {
      _busy = false;
    }
  }

  /// Confirma el canje del pase validado y descuenta el almuerzo.
  Future<void> confirmRedeem() async {
    final current = state;
    if (_busy || current is! OwnerSuccess || current.redeemed) return;
    final passId = current.result.passId;
    if (passId == null) {
      state = OwnerError(
        'El resultado no tiene un pase asociado.',
        result: current.result,
      );
      return;
    }

    _busy = true;
    try {
      final ok = await _repo.confirmRedeem(passId);
      state = ok
          ? OwnerSuccess(current.result, redeemed: true)
          : OwnerError(
              'No se pudo confirmar el canje (¿ya se descontó?).',
              result: current.result,
            );
    } catch (e) {
      state = OwnerError('Error al confirmar el canje: $e',
          result: current.result);
    } finally {
      _busy = false;
    }
  }
}
