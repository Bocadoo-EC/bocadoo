import 'package:flutter/foundation.dart';

/// Payload estructurado extraído de un código QR Bocadoo
@immutable
class QrPassPayload {
  final String version;
  final String userId;
  final int timeStep;
  final String hash;
  final String rawPayload;

  const QrPassPayload({
    required this.version,
    required this.userId,
    required this.timeStep,
    required this.hash,
    required this.rawPayload,
  });
}

/// Resultado de validación del parser de QR
@immutable
class QrValidationResult {
  final bool isValid;
  final bool isExpired;
  final bool isInvalidFormat;
  final String? userId;
  final int? timeStep;
  final String? errorMessage;
  final QrPassPayload? payload;

  const QrValidationResult({
    required this.isValid,
    this.isExpired = false,
    this.isInvalidFormat = false,
    this.userId,
    this.timeStep,
    this.errorMessage,
    this.payload,
  });

  factory QrValidationResult.valid(QrPassPayload payload) {
    return QrValidationResult(
      isValid: true,
      userId: payload.userId,
      timeStep: payload.timeStep,
      payload: payload,
    );
  }

  factory QrValidationResult.expired(String userId, int timeStep) {
    return QrValidationResult(
      isValid: false,
      isExpired: true,
      userId: userId,
      timeStep: timeStep,
      errorMessage: 'Código QR expirado. Pide al comensal actualizar su pase.',
    );
  }

  factory QrValidationResult.invalid(String reason) {
    return QrValidationResult(
      isValid: false,
      isInvalidFormat: true,
      errorMessage: reason,
    );
  }
}

/// Lógica de generación, parsing y validación de código corto de 6 caracteres
/// y QR dinámico anti-captura de pantalla.
///
/// Usa un alfabeto de 32 caracteres en mayúsculas sin ambiguos (`O`/`0`/`I`/`1` excluidos).
class BocadooQrParser {
  BocadooQrParser._();

  static const String version = 'BCD1';
  static const String planPrefix = 'PLN-';
  static const String orderPrefix = 'ORD-';
  static const int stepDurationSeconds = 30;
  static const int shortCodeLength = 6;
  static const String shortAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static final RegExp _shortCodeRegex = RegExp(r'^[A-Z0-9]{6}$');

  static final Set<String> _knownUsers = {
    'u1',
    'u2',
    'u3',
    'u4',
    'u5',
    'u6',
  };

  static final Map<String, ({String userId, int timeStep})> _passCodeMeta = {};
  static final Map<String, String> _shortToRaw = {};
  static final Map<String, String> _orderByShortCode = {};
  static final Map<String, String> _tableByShortCode = {};
  static final Map<String, String> _restaurantByCode = {};

  /// Calcula el timeStep actual de 30 segundos.
  static int getCurrentTimeStep([DateTime? now]) {
    final current = now ?? DateTime.now();
    return current.millisecondsSinceEpoch ~/ (stepDurationSeconds * 1000);
  }

  /// Calcula los segundos restantes en el ciclo actual de 30 segundos.
  static int getRemainingSecondsInCycle([DateTime? now]) {
    final current = now ?? DateTime.now();
    final currentSec = current.millisecondsSinceEpoch ~/ 1000;
    return stepDurationSeconds - (currentSec % stepDurationSeconds);
  }

  /// Quita el prefijo `PLN-` si está presente.
  static String stripPlanPrefix(String raw) {
    final trimmed = raw.trim();
    if (trimmed.toUpperCase().startsWith(planPrefix)) {
      return trimmed.substring(planPrefix.length).trim();
    }
    return trimmed;
  }

  /// Limpia un texto ingresado por teclado dejándolo en mayúsculas sin espacios ni puntos.
  static String sanitizeManualInput(String raw) {
    var upper = raw.trim().toUpperCase();
    if (upper.startsWith(planPrefix)) {
      upper = upper.substring(planPrefix.length);
    } else if (upper.startsWith(orderPrefix)) {
      upper = upper.substring(orderPrefix.length);
    }
    final cleaned = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length > 6 ? cleaned.substring(0, 6) : cleaned;
  }

  /// Convierte cualquier semilla o token largo en un código determinista de
  /// 6 caracteres alfanuméricos en mayúsculas sin `O`/`0`/`I`/`1`.
  static String toShortCode(String rawSeed, {String? restaurantId}) {
    final trimmed = stripPlanPrefix(rawSeed);
    if (trimmed.isEmpty) return 'A7K9P2';

    final upper = trimmed.toUpperCase();
    if (_shortCodeRegex.hasMatch(upper) &&
        !upper.contains('0') &&
        !upper.contains('1') &&
        !upper.contains('I') &&
        !upper.contains('O')) {
      if (restaurantId != null && restaurantId.isNotEmpty) {
        _restaurantByCode[upper] = restaurantId;
        _restaurantByCode['$planPrefix$upper'] = restaurantId;
      }
      return upper;
    }

    final code = _hashToSixChars(trimmed);
    _shortToRaw[code] = trimmed;
    _shortToRaw['$planPrefix$code'] = trimmed;
    if (restaurantId != null && restaurantId.isNotEmpty) {
      _restaurantByCode[code] = restaurantId;
      _restaurantByCode['$planPrefix$code'] = restaurantId;
      _restaurantByCode[trimmed] = restaurantId;
    }
    return code;
  }

  /// Genera el código de pase de plan en formato estricto `PLN-XXXXXX`.
  static String generatePlanCode(String rawSeed, {String? restaurantId}) {
    final code = toShortCode(rawSeed, restaurantId: restaurantId);
    return '$planPrefix$code';
  }

  /// Genera y registra el código de preorden en formato estricto `ORD-XXXXXX`.
  static String generateOrderCode(
    String orderNumber, {
    String? orderId,
    String? restaurantId,
  }) {
    final numClean = orderNumber.trim();
    final seed = (orderId != null && orderId.trim().isNotEmpty)
        ? 'ORD:${orderId.trim()}'
        : 'ORD:$numClean';
    final code = _hashToSixChars(seed);
    _orderByShortCode[code] = numClean;
    _orderByShortCode['$orderPrefix$code'] = numClean;
    // También registra la variante basada en número para resolución cruzada entre dispositivos.
    final byNumCode = _hashToSixChars('ORD:$numClean');
    _orderByShortCode[byNumCode] = numClean;
    _orderByShortCode['$orderPrefix$byNumCode'] = numClean;
    if (restaurantId != null && restaurantId.isNotEmpty) {
      _restaurantByCode[code] = restaurantId;
      _restaurantByCode['$orderPrefix$code'] = restaurantId;
      _restaurantByCode[byNumCode] = restaurantId;
      _restaurantByCode['$orderPrefix$byNumCode'] = restaurantId;
    }
    return '$orderPrefix$byNumCode';
  }

  /// Genera y registra el código corto de 6 caracteres para una mesa compartida.
  static String generateTableCode(String tableId, {String? restaurantId}) {
    final cleanId = tableId.trim();
    final code = _hashToSixChars('MESA:${cleanId.toUpperCase()}');
    _tableByShortCode[code] = cleanId;
    if (restaurantId != null && restaurantId.isNotEmpty) {
      _restaurantByCode[code] = restaurantId;
    }
    return code;
  }

  static String? resolveRawPayload(String input) {
    final upper = input.trim().toUpperCase();
    final short = sanitizeManualInput(input);
    return _shortToRaw[upper] ??
        _shortToRaw[short] ??
        _shortToRaw['$planPrefix$short'];
  }

  static String? resolveOrderNumber(String input) {
    final upper = input.trim().toUpperCase();
    if (upper.startsWith(planPrefix)) return null;
    final direct = _orderByShortCode[upper];
    if (direct != null) return direct;
    final short = sanitizeManualInput(upper);
    final byShort = _orderByShortCode[short];
    if (byShort != null) return byShort;
    // Comprueba números de orden habituales (1..999) de forma determinista.
    for (var n = 1; n <= 999; n++) {
      if (_hashToSixChars('ORD:$n') == short) {
        return '$n';
      }
    }
    return null;
  }

  static String? resolveTableId(String input) {
    final upper = input.trim().toUpperCase();
    final direct = _tableByShortCode[upper];
    if (direct != null) return direct;
    for (var n = 1200; n <= 1500; n++) {
      final candidate = 'M$n';
      if (_hashToSixChars('MESA:$candidate') == upper) {
        return candidate;
      }
    }
    return null;
  }

  static String? restaurantForCode(String code) =>
      _restaurantByCode[code.trim().toUpperCase()] ??
      _restaurantByCode[sanitizeManualInput(code)] ??
      _restaurantByCode[code.trim()];

  /// Genera el hash determinista de 4 dígitos para un userId y timeStep.
  static String generateStepHash(String userId, int timeStep) {
    if (userId.isEmpty) return '0000';
    final charCode = userId.codeUnitAt(0);
    final seed = (timeStep * 31 + charCode) % 10000;
    return seed.toString().padLeft(4, '0');
  }

  /// Genera el código de pase en formato `PLN-XXXXXX` en mayúsculas.
  static String generateQrPayload(
    String userId, [
    DateTime? now,
    String? restaurantId,
  ]) {
    final cleanUser = userId.trim().isEmpty ? 'u1' : userId.trim();
    _knownUsers.add(cleanUser);
    final timeStep = getCurrentTimeStep(now);
    final code = _hashToSixChars('PASS:$cleanUser:$timeStep');
    final prefixed = '$planPrefix$code';
    _passCodeMeta[code] = (userId: cleanUser, timeStep: timeStep);
    _passCodeMeta[prefixed] = (userId: cleanUser, timeStep: timeStep);
    if (restaurantId != null && restaurantId.isNotEmpty) {
      _restaurantByCode[code] = restaurantId;
      _restaurantByCode[prefixed] = restaurantId;
    }
    return prefixed;
  }

  /// Parsea y valida el payload recibido desde la cámara o entrada manual (6 caracteres o BCD1).
  static QrValidationResult parseAndValidate(
    String rawPayload, [
    DateTime? now,
  ]) {
    final trimmed = rawPayload.trim();
    if (trimmed.isEmpty) {
      return QrValidationResult.invalid('Escribe el código de 6 caracteres.');
    }

    final upper = trimmed.toUpperCase();
    if (upper.contains('INVALID') || upper == 'XXXXXX') {
      return QrValidationResult.invalid(
        'El código no es válido.',
      );
    }

    final currentStep = getCurrentTimeStep(now);

    // 1. Validación directa de código corto de 6 caracteres (o PLN-XXXXXX)
    final normalizedShort = upper.startsWith(planPrefix)
        ? upper.substring(planPrefix.length)
        : upper;
    if (_shortCodeRegex.hasMatch(normalizedShort)) {
      // Ventana vigente (±1 paso de 30s)
      for (final delta in const [0, -1, 1]) {
        final step = currentStep + delta;
        for (final user in _knownUsers) {
          if (_hashToSixChars('PASS:$user:$step') == normalizedShort) {
            final hash = generateStepHash(user, step);
            return QrValidationResult.valid(
              QrPassPayload(
                version: version,
                userId: user,
                timeStep: step,
                hash: hash,
                rawPayload: upper,
              ),
            );
          }
        }
      }

      // Comprobar si es un código corto expirado (en metadatos o ventana previa de 20 min)
      final meta = _passCodeMeta[upper];
      if (meta != null) {
        final diff = (currentStep - meta.timeStep).abs();
        if (diff <= 1) {
          final hash = generateStepHash(meta.userId, meta.timeStep);
          return QrValidationResult.valid(
            QrPassPayload(
              version: version,
              userId: meta.userId,
              timeStep: meta.timeStep,
              hash: hash,
              rawPayload: upper,
            ),
          );
        }
        return QrValidationResult.expired(meta.userId, meta.timeStep);
      }

      for (var delta = 2; delta <= 40; delta++) {
        final step = currentStep - delta;
        for (final user in _knownUsers) {
          if (_hashToSixChars('PASS:$user:$step') == upper) {
            return QrValidationResult.expired(user, step);
          }
        }
      }

      return QrValidationResult.invalid(
        'Código de 6 caracteres no reconocido.',
      );
    }

    // 2. Retrocompatibilidad con formato estructurado BCD1.{userId}.{timeStep}.{hash}
    final parts = trimmed.split('.');
    if (parts.length != 4 || parts[0] != version) {
      return QrValidationResult.invalid(
        'Formato de código no reconocido por Bocadoo.',
      );
    }

    final userId = parts[1];
    final rawTimeStep = parts[2];
    final hash = parts[3];

    if (userId.isEmpty || rawTimeStep.isEmpty || hash.isEmpty) {
      return QrValidationResult.invalid('El código contiene campos vacíos.');
    }

    final timeStep = int.tryParse(rawTimeStep);
    if (timeStep == null) {
      return QrValidationResult.invalid('Marca temporal del código inválida.');
    }

    final expectedHash = generateStepHash(userId, timeStep);
    if (hash != expectedHash) {
      return QrValidationResult.invalid(
        'Firma de seguridad inválida o manipulada.',
      );
    }

    final difference = currentStep - timeStep;
    if (difference > 1 || difference < -1) {
      return QrValidationResult.expired(userId, timeStep);
    }

    final payload = QrPassPayload(
      version: parts[0],
      userId: userId,
      timeStep: timeStep,
      hash: hash,
      rawPayload: trimmed,
    );

    return QrValidationResult.valid(payload);
  }

  static String _hashToSixChars(String input) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (var i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      h1 ^= c;
      h1 = (h1 * 0x01000193) & 0x7fffffff;
      h2 ^= (c + i * 17);
      h2 = (h2 * 0x85ebca6b) & 0x7fffffff;
    }
    final combined = ((h1 & 0x3fffffff) ^ ((h2 & 0x3ff) << 20)) & 0x3fffffff;
    final chars = List<String>.filled(6, 'A');
    var value = combined;
    for (var i = 0; i < 6; i++) {
      final idx = (value ^ (h2 >> (i * 3))) & 31;
      chars[i] = shortAlphabet[idx];
      value >>= 5;
    }
    return chars.join();
  }
}
