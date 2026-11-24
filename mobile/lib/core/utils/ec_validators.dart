/// Validadores reutilizables para formularios de negocio en Ecuador
/// (Registro de dueño y edición de local en Ajustes).
class EcValidators {
  EcValidators._();

  static String? validateRestaurantName(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Este campo es obligatorio.';
    if (!RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(v)) {
      return 'Ingresa un nombre válido con letras.';
    }
    return null;
  }

  static String? validatePersonName(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Este campo es obligatorio.';
    if (RegExp(r'\d').hasMatch(v)) {
      return 'El nombre no debe contener números.';
    }
    if (!RegExp(r'^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s]+$').hasMatch(v)) {
      return 'Usa solo letras, espacios y tildes.';
    }
    if (v.replaceAll(RegExp(r'\s+'), '').length < 2) {
      return 'Ingresa un nombre válido.';
    }
    return null;
  }

  /// Validación oficial ecuatoriana de Cédula (10 dígitos) y RUC (13 dígitos
  /// terminado en `001`), usando módulo 10 y módulo 11.
  static String? validateCedulaRuc(String raw, {bool required = true}) {
    final v = raw.trim();
    if (v.isEmpty) {
      return required ? 'Este campo es obligatorio.' : null;
    }
    if (!RegExp(r'^\d+$').hasMatch(v)) {
      return 'Solo se permiten dígitos numéricos.';
    }
    if (v.length != 10 && v.length != 13) {
      return 'Debe tener 10 dígitos (Cédula) o 13 dígitos (RUC).';
    }

    final prov = int.parse(v.substring(0, 2));
    if ((prov < 1 || prov > 24) && prov != 30) {
      return 'Código de provincia inválido';
    }

    if (v.length == 13 && !v.endsWith('001')) {
      return 'El RUC debe terminar en 001';
    }

    final digits = [for (var i = 0; i < v.length; i++) int.parse(v[i])];
    final d3 = digits[2];

    if (v.length == 10 || d3 < 6) {
      if (v.length == 10 && d3 >= 6) {
        return 'Número de cédula/RUC inválido';
      }
      const coeff = [2, 1, 2, 1, 2, 1, 2, 1, 2];
      var sum = 0;
      for (var i = 0; i < 9; i++) {
        var prod = digits[i] * coeff[i];
        if (prod >= 10) prod -= 9;
        sum += prod;
      }
      final check = (10 - (sum % 10)) % 10;
      return check == digits[9] ? null : 'Número de cédula/RUC inválido';
    }

    if (d3 == 6) {
      const coeff = [3, 2, 7, 6, 5, 4, 3, 2];
      var sum = 0;
      for (var i = 0; i < 8; i++) {
        sum += digits[i] * coeff[i];
      }
      final rem = sum % 11;
      final check = rem == 0 ? 0 : 11 - rem;
      return check == digits[8] ? null : 'Número de cédula/RUC inválido';
    }

    if (d3 == 9) {
      const coeff = [4, 3, 2, 7, 6, 5, 4, 3, 2];
      var sum = 0;
      for (var i = 0; i < 9; i++) {
        sum += digits[i] * coeff[i];
      }
      final rem = sum % 11;
      final check = rem == 0 ? 0 : 11 - rem;
      return check == digits[9] ? null : 'Número de cédula/RUC inválido';
    }

    return 'Número de cédula/RUC inválido';
  }

  static String? validateEmail(String raw, {String? duplicateEmailValue}) {
    final v = raw.trim();
    if (v.isEmpty) return 'Este campo es obligatorio.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v)) {
      return 'Ingresa un correo comercial válido.';
    }
    if (duplicateEmailValue != null &&
        v.toLowerCase() == duplicateEmailValue) {
      return 'Este correo ya está registrado. Utiliza otro correo para crear tu cuenta.';
    }
    return null;
  }

  static String? validateEcuadorCellPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.isEmpty) return 'Este campo es obligatorio.';
    if (!RegExp(r'^09\d{8}$').hasMatch(digits)) {
      return 'Ingresa un celular ecuatoriano válido (09xxxxxxxx).';
    }
    return null;
  }

  static String? validateLunchPrice(String raw) {
    final v = raw.trim().replaceAll(',', '.');
    if (v.isEmpty) return 'Este campo es obligatorio.';
    final price = double.tryParse(v);
    if (price == null || price <= 0 || price > 100) {
      return 'Ingresa el precio del almuerzo (mayor a \$0,00).';
    }
    return null;
  }

  static String? validateTakeawaySurcharge(String raw) {
    final v = raw.trim().replaceAll(',', '.');
    if (v.isEmpty) return 'Este campo es obligatorio.';
    final surcharge = double.tryParse(v);
    if (surcharge == null || surcharge < 0 || surcharge > 20) {
      return 'Ingresa un valor válido (ej. 0.00 o 0.25).';
    }
    return null;
  }

  static String? validateOptionalPositiveInt(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final parsed = int.tryParse(v);
    if (parsed == null || parsed <= 0) {
      return 'Debe ser mayor a 0.';
    }
    return null;
  }

  static bool isTechnicalErrorMessage(String raw, {int? status}) {
    if (status != null && status >= 500) return true;
    final lower = raw.toLowerCase();
    if (lower.isEmpty) return false;
    return lower.contains('should not exist') ||
        lower.contains('must be') ||
        lower.contains('must not be') ||
        lower.contains('property ') ||
        lower.contains('internal server error') ||
        lower.contains('validation failed') ||
        lower.contains('stack') ||
        lower.contains('exception') ||
        lower.contains('queryfailederror') ||
        lower.contains('typeorm') ||
        lower.contains('prisma') ||
        lower.contains('postgres') ||
        lower.contains('unexpected token') ||
        RegExp(r'\bat\s+[a-z0-9_.$]+\s*\(', caseSensitive: false).hasMatch(raw);
  }
}
