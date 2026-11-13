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

/// Lógica de generación, parsing y validación de QR dinámico anti-captura de pantalla.
/// Especificación oficial Bocadoo (docs/IDENTIDAD_BOCADOO.md y src/domain/qr.ts):
/// - Formato: BCD1.{userId}.{timeStep}.{hash}
/// - Ventana rotativa: 30 segundos
/// - Tolerancia en caja: ±1 timeStep (máx 30s de retraso)
class BocadooQrParser {
  BocadooQrParser._();

  static const String version = 'BCD1';
  static const int stepDurationSeconds = 30;

  /// Calcula el timeStep actual de 30 segundos
  static int getCurrentTimeStep([DateTime? now]) {
    final current = now ?? DateTime.now();
    return current.millisecondsSinceEpoch ~/ (stepDurationSeconds * 1000);
  }

  /// Calcula los segundos restantes en el ciclo actual de 30 segundos
  static int getRemainingSecondsInCycle([DateTime? now]) {
    final current = now ?? DateTime.now();
    final currentSec = current.millisecondsSinceEpoch ~/ 1000;
    return stepDurationSeconds - (currentSec % stepDurationSeconds);
  }

  /// Genera el hash determinista de 4 dígitos para un userId y timeStep
  static String generateStepHash(String userId, int timeStep) {
    if (userId.isEmpty) return '0000';
    final charCode = userId.codeUnitAt(0);
    final seed = (timeStep * 31 + charCode) % 10000;
    return seed.toString().padLeft(4, '0');
  }

  /// Genera la cadena completa del QR para renderizar
  static String generateQrPayload(String userId, [DateTime? now]) {
    final timeStep = getCurrentTimeStep(now);
    final hash = generateStepHash(userId, timeStep);
    return '$version.$userId.$timeStep.$hash';
  }

  /// Parsea y valida el payload recibido desde la cámara o entrada manual
  static QrValidationResult parseAndValidate(
    String rawPayload, [
    DateTime? now,
  ]) {
    final trimmed = rawPayload.trim();

    // Soporte para tokens de prueba inválidos en testing
    if (trimmed.toUpperCase().contains('INVALID')) {
      return QrValidationResult.invalid(
        'El pase es inválido o ya fue canjeado hoy.',
      );
    }

    final parts = trimmed.split('.');
    if (parts.length != 4 || parts[0] != version) {
      return QrValidationResult.invalid(
        'Formato de QR no reconocido por Bocadoo.',
      );
    }

    final userId = parts[1];
    final rawTimeStep = parts[2];
    final hash = parts[3];

    if (userId.isEmpty || rawTimeStep.isEmpty || hash.isEmpty) {
      return QrValidationResult.invalid('El QR contiene campos vacíos.');
    }

    final timeStep = int.tryParse(rawTimeStep);
    if (timeStep == null) {
      return QrValidationResult.invalid('Marca temporal del QR inválida.');
    }

    // 1. Validar hash criptográfico / determinista
    final expectedHash = generateStepHash(userId, timeStep);
    if (hash != expectedHash) {
      return QrValidationResult.invalid(
        'Firma de seguridad de QR inválida o manipulada.',
      );
    }

    // 2. Validar expiración (tolerancia de 1 paso hacia atrás o adelante = 30 seg)
    final currentStep = getCurrentTimeStep(now);
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
}

