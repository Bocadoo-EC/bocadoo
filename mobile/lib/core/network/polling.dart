import 'dart:async';

import 'package:flutter/widgets.dart';

/// Temporizador periódico consciente del ciclo de vida de la app.
///
/// Pausa automáticamente las consultas cuando la app pasa a segundo plano
/// y las reanuda al volver a primer plano.
class LifecyclePollingController with WidgetsBindingObserver {
  LifecyclePollingController({
    required this.interval,
    required this.onTick,
  });

  final Duration interval;
  final FutureOr<void> Function() onTick;

  Timer? _timer;
  bool _running = false;
  bool _paused = false;
  bool _observing = false;

  bool get isRunning => _running;

  void start() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _running = true;
    _paused = false;
    _scheduleTimer();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  void _scheduleTimer() {
    _timer?.cancel();
    if (!_running || _paused) return;
    _timer = Timer.periodic(interval, (_) {
      if (_running && !_paused) {
        onTick();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.resumed) {
      if (_paused) {
        _paused = false;
        onTick();
        _scheduleTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _paused = true;
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() => stop();
}
