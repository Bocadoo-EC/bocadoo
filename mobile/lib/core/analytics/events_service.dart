import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/app_mode.dart';
import '../network/api_client.dart';
import '../network/api_config.dart';
import '../network/api_exception.dart';
import '../network/idempotency.dart';

class _QueuedEvent {
  _QueuedEvent({
    required this.tipo,
    required this.ocurridoEn,
    this.restauranteId,
    this.usuarioId,
    this.propiedades = const {},
  });

  final String tipo;
  final String ocurridoEn;
  final String? restauranteId;
  final String? usuarioId;
  final Map<String, Object> propiedades;

  Map<String, dynamic> toJson({String? fallbackUserId}) {
    final uid = usuarioId ?? fallbackUserId;
    return <String, dynamic>{
      'tipo': tipo,
      'ocurridoEn': ocurridoEn,
      'restauranteId': ?restauranteId,
      'usuarioId': ?uid,
      if (propiedades.isNotEmpty) 'propiedades': propiedades,
    };
  }
}

/// Servicio de monitoreo P-11 conectado a `POST /v1/eventos`.
///
/// Registra ingresos, errores (red/Flutter) y uso por función sin capturar
/// datos personales (sin correos, nombres ni teléfonos) y nunca bloquea ni
/// interrumpe flujos de la app si no hay conexión o el backend responde error.
class EventsService {
  static const String appVersion = '1.0.0+1';
  static const int _maxBatchSize = 50;
  static const int _autoFlushThreshold = 15;
  static const int _maxQueueSize = 200;
  static const Duration _flushInterval = Duration(seconds: 15);

  ApiClient? _api;
  bool Function() _isAuthenticated = () => false;
  String? Function() _getActiveRestaurantId = () => null;
  String? Function() _getUserId = () => null;

  String _sessionId = uuidV4();
  final List<_QueuedEvent> _queue = [];
  final Map<String, DateTime> _recentErrorAt = {};

  Timer? _flushTimer;
  bool _isFlushing = false;
  DateTime? _cooldownUntil;
  Future<void>? _inFlightFlush;
  AppLifecycleListener? _lifecycle;

  void configure({
    required ApiClient api,
    required bool Function() isAuthenticated,
    String? Function()? activeRestaurantId,
    String? Function()? userId,
  }) {
    _api = api;
    _isAuthenticated = isAuthenticated;
    if (activeRestaurantId != null) {
      _getActiveRestaurantId = activeRestaurantId;
    }
    if (userId != null) {
      _getUserId = userId;
    }
  }

  /// Enlaza el ciclo de vida de la app para vaciar eventos al pasar a segundo plano.
  void startLifecycleMonitoring() {
    _lifecycle ??= AppLifecycleListener(
      onPause: () => unawaited(flush()),
      onDetach: () => unawaited(flush()),
    );
  }

  /// Renueva la sesión de analítica (al iniciar o cerrar sesión).
  void resetSession() {
    _sessionId = uuidV4();
    _cooldownUntil = null;
  }

  /// Encola un evento de uso/ingreso siguiendo las reglas de `EventoDto`.
  void track(
    String tipo, {
    String? restaurantId,
    Map<String, Object?>? props,
  }) {
    if (AppMode.useMock) return;

    final cleanType = _sanitizeType(tipo);
    if (cleanType.isEmpty) return;

    final cleanRestId = _cleanOptionalId(
      restaurantId ?? _getActiveRestaurantId(),
    );
    final cleanUid = _cleanOptionalId(_getUserId());
    final cleanProps = _sanitizeProps(props);

    if (_queue.length >= _maxQueueSize) {
      _queue.removeAt(0);
    }
    _queue.add(
      _QueuedEvent(
        tipo: cleanType,
        ocurridoEn: DateTime.now().toUtc().toIso8601String(),
        restauranteId: cleanRestId,
        usuarioId: cleanUid,
        propiedades: cleanProps,
      ),
    );

    if (_isAuthenticated()) {
      if (_queue.length >= _autoFlushThreshold) {
        unawaited(flush());
      } else {
        _scheduleFlush();
      }
    }
  }

  /// Encola un error con deduplicación corta (`5 s`) para evitar ráfagas.
  void trackError(
    String tipo, {
    String? dedupeKey,
    String? restaurantId,
    Map<String, Object?>? props,
  }) {
    if (AppMode.useMock) return;
    final key = dedupeKey ?? tipo;
    final now = DateTime.now();
    final prev = _recentErrorAt[key];
    if (prev != null && now.difference(prev) < const Duration(seconds: 5)) {
      return;
    }
    if (_recentErrorAt.length > 60) {
      _recentErrorAt.clear();
    }
    _recentErrorAt[key] = now;
    track(tipo, restaurantId: restaurantId, props: props);
  }

  /// Registra errores HTTP/red capturados por [ApiClient].
  void trackApiError({
    required String method,
    required String path,
    int? status,
    required String code,
    String? requestId,
  }) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.endsWith('/eventos') || normalizedPath == '/health') {
      return;
    }
    trackError(
      'api.error',
      dedupeKey: '$method:$normalizedPath:$code:$status',
      props: {
        'metodo': method.toUpperCase(),
        'ruta': normalizedPath,
        'status': ?status,
        'code': code,
        'request_id': ?requestId,
      },
    );
  }

  /// Registra vistas de pantalla reportadas por el observador de `GoRouter`.
  void trackScreen(String routeNameOrPath, {String? role}) {
    final cleanRoute = _normalizePath(routeNameOrPath);
    if (cleanRoute.isEmpty) return;
    track(
      'pantalla.vista',
      props: {
        'pantalla': cleanRoute,
        'rol': ?role,
      },
    );
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(_flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  /// Envía los eventos pendientes en lotes de hasta 50 elementos.
  Future<void> flush() async {
    if (AppMode.useMock) {
      _queue.clear();
      _cancelTimer();
      return;
    }
    if (_inFlightFlush != null) {
      return _inFlightFlush!;
    }
    final completer = Completer<void>();
    _inFlightFlush = completer.future;
    try {
      await _drainQueue();
    } finally {
      _inFlightFlush = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _drainQueue() async {
    final api = _api;
    if (_isFlushing || api == null || !_isAuthenticated() || _queue.isEmpty) {
      return;
    }
    final cooldown = _cooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      return;
    }

    _cancelTimer();
    _isFlushing = true;
    try {
      while (_queue.isNotEmpty && _isAuthenticated()) {
        final count = _queue.length > _maxBatchSize
            ? _maxBatchSize
            : _queue.length;
        final batch = _queue.sublist(0, count);
        final currentUid = _cleanOptionalId(_getUserId());
        final payloadEvents = batch
            .map((e) => e.toJson(fallbackUserId: currentUid))
            .toList();

        final batchKey = uuidV4();
        try {
          await guard(
            () => api.send<Map<String, dynamic>>(
              'POST',
              '${ApiConfig.v1}/eventos',
              idempotencyKey: batchKey,
              body: <String, dynamic>{
                'sesionId': _sessionId,
                'plataforma': _platformCode(),
                'versionApp': appVersion,
                'eventos': payloadEvents,
              },
            ),
          );
          _queue.removeRange(0, count);
        } on ApiException catch (e) {
          if (e.status == 429 || e.code == 'EVENTOS_LIMITE_TASA') {
            _cooldownUntil = DateTime.now().add(const Duration(seconds: 60));
            _scheduleFlush();
            break;
          }
          if (e.isNetwork || (e.status != null && e.status! >= 500)) {
            _scheduleFlush();
            break;
          }
          _queue.removeRange(0, count);
        } catch (_) {
          _scheduleFlush();
          break;
        }
      }
    } finally {
      _isFlushing = false;
    }
  }

  void _cancelTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  static String _platformCode() {
    if (kIsWeb) return 'WEB';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';
  }

  static String? _cleanOptionalId(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _sanitizeType(String raw) {
    var s = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '_');
    s = s.replaceAll(RegExp(r'\.{2,}'), '.').replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (s.length > 60) {
      s = s.substring(0, 60).replaceAll(RegExp(r'\.+$'), '');
    }
    return s;
  }

  static Map<String, Object> _sanitizeProps(Map<String, Object?>? props) {
    if (props == null || props.isEmpty) return const {};
    final out = <String, Object>{};
    for (final entry in props.entries) {
      if (out.length >= 20) break;
      final value = entry.value;
      if (value == null) continue;
      final cleanKey = entry.key.trim();
      if (cleanKey.isEmpty) continue;

      final Object normalized;
      if (value is num || value is bool) {
        normalized = value;
      } else {
        final str = value.toString().trim();
        if (str.isEmpty) continue;
        normalized = str.length > 120 ? str.substring(0, 120) : str;
      }

      out[cleanKey] = normalized;
      if (utf8.encode(jsonEncode(out)).length > 900) {
        out.remove(cleanKey);
        break;
      }
    }
    return out;
  }

  static String _normalizePath(String path) {
    final base = path.split('?').first.trim();
    if (base.isEmpty) return '';
    return base
        .replaceAll(
          RegExp(
            r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
          ),
          ':id',
        )
        .replaceAll(RegExp(r'/\d+(?=/|$)'), '/:n');
  }
}

final EventsService eventsService = EventsService();
