import 'dart:async';

/// Retrasa la ejecución de una mutación irreversible (como confirmar una
/// solicitud de plan) para dar al usuario una ventana real de cancelación ("Deshacer").
class DeferredCommit {
  final Duration delay;
  Timer? _timer;
  Future<void> Function()? _pendingAction;
  Object? _lastError;

  DeferredCommit({this.delay = const Duration(seconds: 11)});

  /// Indica si hay una acción esperando confirmación.
  bool get isPending => _timer?.isActive ?? false;

  /// Programa [action] para ejecutarse tras [delay].
  /// Si ya había una acción pendiente, la reemplaza sin ejecutarla.
  void schedule(
    Future<void> Function() action, {
    void Function(Object error)? onError,
  }) {
    cancel();
    _lastError = null;
    _pendingAction = action;
    _timer = Timer(delay, () async {
      final pending = _pendingAction;
      _pendingAction = null;
      if (pending == null) return;
      try {
        await pending();
      } catch (e) {
        _lastError = e;
        onError?.call(e);
      }
    });
  }

  /// Ejecuta inmediatamente la acción pendiente si aún no se ha disparado.
  Future<void> flush() async {
    final pending = _pendingAction;
    _timer?.cancel();
    _timer = null;
    _pendingAction = null;
    if (pending != null) {
      await pending();
    }
  }

  /// Cancela la acción pendiente si todavía está dentro de la ventana de espera.
  /// Devuelve `true` si existía una acción pendiente que fue cancelada.
  bool cancel() {
    final wasActive = _timer?.isActive ?? false;
    _timer?.cancel();
    _timer = null;
    _pendingAction = null;
    return wasActive;
  }

  /// Devuelve y limpia el último error asíncrono ocurrido al ejecutar el commit.
  Object? consumeError() {
    final err = _lastError;
    _lastError = null;
    return err;
  }

  void dispose() {
    cancel();
  }
}
