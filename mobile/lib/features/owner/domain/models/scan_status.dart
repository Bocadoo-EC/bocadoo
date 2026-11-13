import '../../../../core/contracts/models.dart';

/// Estados exactos devueltos por la API de validación/canje de QR (`bck-bocadoo`).
enum ApiScanStatus {
  ok('OK'),
  okAdvertencia('OK_ADVERTENCIA'),
  duplicado('DUPLICADO'),
  sinPlan('SIN_PLAN'),
  sinSaldo('SIN_SALDO'),
  vencido('VENCIDO'),
  diaNoValido('DIA_NO_VALIDO'),
  otroLocal('OTRO_LOCAL'),
  qrExpirado('QR_EXPIRADO');

  final String apiValue;
  const ApiScanStatus(this.apiValue);

  static ApiScanStatus fromApi(String? value) {
    final normalized = value?.trim().toUpperCase();
    for (final status in ApiScanStatus.values) {
      if (status.apiValue == normalized) return status;
    }
    return ApiScanStatus.qrExpirado;
  }

  bool get isValid => this == ok || this == okAdvertencia;

  /// Mapeo al semáforo visual de [ScanResult.outcome].
  String get outcome {
    return switch (this) {
      ApiScanStatus.ok => 'VERDE',
      ApiScanStatus.okAdvertencia => 'ADVERTENCIA',
      ApiScanStatus.duplicado => 'GRIS',
      ApiScanStatus.sinPlan ||
      ApiScanStatus.sinSaldo ||
      ApiScanStatus.vencido ||
      ApiScanStatus.diaNoValido ||
      ApiScanStatus.otroLocal ||
      ApiScanStatus.qrExpirado =>
        'ROJO',
    };
  }

  String get defaultTitle {
    return switch (this) {
      ApiScanStatus.ok => 'Validado',
      ApiScanStatus.okAdvertencia => 'Último almuerzo',
      ApiScanStatus.duplicado => 'Ya validado',
      ApiScanStatus.sinPlan => 'Sin plan',
      ApiScanStatus.sinSaldo => 'Sin almuerzos',
      ApiScanStatus.vencido => 'Vencido',
      ApiScanStatus.diaNoValido => 'Día no válido',
      ApiScanStatus.otroLocal => 'Es de otro local',
      ApiScanStatus.qrExpirado => 'Código vencido',
    };
  }

  String get defaultSupportingLine {
    return switch (this) {
      ApiScanStatus.ok => 'Pase listo para validar en caja.',
      ApiScanStatus.okAdvertencia => 'Recuérdale renovar su paquete hoy.',
      ApiScanStatus.duplicado => 'Este pase ya se validó hace un momento.',
      ApiScanStatus.sinPlan => 'Este comensal no tiene un plan activo.',
      ApiScanStatus.sinSaldo => 'Ya usó todos los almuerzos de su plan.',
      ApiScanStatus.vencido => 'El plazo del paquete ya terminó.',
      ApiScanStatus.diaNoValido => 'Este plan no aplica el día de hoy.',
      ApiScanStatus.otroLocal => 'Este pase pertenece a otro restaurante.',
      ApiScanStatus.qrExpirado => 'Pide al comensal abrir su app.',
    };
  }

  String get defaultActionRequired {
    return switch (this) {
      ApiScanStatus.sinPlan ||
      ApiScanStatus.sinSaldo ||
      ApiScanStatus.vencido =>
        'VENDER_PLAN',
      ApiScanStatus.diaNoValido ||
      ApiScanStatus.otroLocal ||
      ApiScanStatus.qrExpirado =>
        'COBRAR_SUELTO',
      ApiScanStatus.ok ||
      ApiScanStatus.okAdvertencia ||
      ApiScanStatus.duplicado =>
        'NINGUNA',
    };
  }
}

/// Mapea la respuesta JSON de la API de escaneo a [ScanResult].
class ScanResultMapper {
  ScanResultMapper._();

  static ScanResult fromApiJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? json['code']) as String?;
    final apiStatus = ApiScanStatus.fromApi(rawStatus);
    final student = json['student'] as Map<String, dynamic>?;
    final pass = json['pass'] as Map<String, dynamic>?;

    final redeemedAtRaw = (json['redeemedAt'] ?? json['redeemed_at']) as String?;

    return ScanResult(
      isValid: (json['isValid'] as bool?) ?? apiStatus.isValid,
      outcome: (json['outcome'] as String?) ?? apiStatus.outcome,
      apiStatus: apiStatus.apiValue,
      title: (json['title'] as String?) ?? apiStatus.defaultTitle,
      supportingLine: (json['supportingLine'] ??
              json['supporting_line'] ??
              json['message']) as String? ??
          apiStatus.defaultSupportingLine,
      studentName: (json['studentName'] ??
          json['student_name'] ??
          student?['fullName'] ??
          student?['name']) as String?,
      studentCareer: (json['studentCareer'] ??
          json['student_career'] ??
          student?['career']) as String?,
      studentAvatar: (json['studentAvatar'] ??
          json['student_avatar'] ??
          student?['avatarUrl']) as String?,
      passId: (json['passId'] ?? json['pass_id'] ?? pass?['id']) as String?,
      totalLunches: (json['totalLunches'] ??
          json['total_lunches'] ??
          pass?['totalLunches']) as int?,
      remainingLunches: (json['remainingLunches'] ??
          json['remaining_lunches'] ??
          pass?['remainingLunches']) as int?,
      redemptionId:
          (json['redemptionId'] ?? json['redemption_id']) as String?,
      redeemedAt:
          redeemedAtRaw != null ? DateTime.tryParse(redeemedAtRaw) : null,
      actionRequired: (json['actionRequired'] ??
              json['action_required']) as String? ??
          apiStatus.defaultActionRequired,
    );
  }
}

