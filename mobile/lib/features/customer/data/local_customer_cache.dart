import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/contracts/models.dart';

/// Caché local persistente para el pase del comensal usando [SharedPreferences].
/// Permite mostrar el último [CustomerPass] y su token QR sin conexión a internet.
class LocalCustomerCache {
  static const String _cachedPassKey = 'bocadoo_cached_customer_pass';

  CustomerPass? _memoryFallback;

  /// Guarda el [CustomerPass] en almacenamiento local persistente.
  Future<void> savePass(CustomerPass pass) async {
    _memoryFallback = pass;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(pass.toMap());
      await prefs.setString(_cachedPassKey, encoded);
    } catch (_) {
      // Mantiene respaldo en memoria si SharedPreferences no está disponible (ej. tests).
    }
  }

  /// Recupera el último [CustomerPass] guardado en caché local.
  Future<CustomerPass?> getPass() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachedPassKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final pass = CustomerPass.fromMap(map);
        _memoryFallback = pass;
        return pass;
      }
    } catch (_) {
      // Fallback a memoria si falla la lectura de disco.
    }
    return _memoryFallback;
  }

  /// Limpia el pase guardado en caché.
  Future<void> clear() async {
    _memoryFallback = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedPassKey);
    } catch (_) {}
  }
}

