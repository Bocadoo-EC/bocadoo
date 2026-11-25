import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/contracts/models.dart';

/// Caché local persistente para el pase del comensal usando [SharedPreferences].
/// Permite mostrar el último [CustomerPass] y su token QR sin conexión a internet.
class LocalCustomerCache {
  static const String _cachedPassKey = 'bocadoo_cached_customer_pass';
  static const String _pendingPlansKey = 'bocadoo_pending_plan_requests';

  CustomerPass? _memoryFallback;
  List<Map<String, dynamic>> _pendingMemoryFallback = const [];

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

  /// Limpia toda la caché local de comensal (pase y solicitudes pendientes).
  Future<void> clear() async {
    _memoryFallback = null;
    _pendingMemoryFallback = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_cachedPassKey),
        prefs.remove(_pendingPlansKey),
      ]);
    } catch (_) {}
  }

  /// Guarda las solicitudes de plan pendientes de aprobación en caja.
  Future<void> savePendingPlanRequests(List<Map<String, dynamic>> items) async {
    _pendingMemoryFallback = items;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (items.isEmpty) {
        await prefs.remove(_pendingPlansKey);
      } else {
        await prefs.setString(_pendingPlansKey, jsonEncode(items));
      }
    } catch (_) {}
  }

  /// Recupera las solicitudes de plan pendientes guardadas en `SharedPreferences`.
  Future<List<Map<String, dynamic>>> getPendingPlanRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingPlansKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final parsed = [
            for (final item in decoded.whereType<Map>())
              Map<String, dynamic>.from(item),
          ];
          _pendingMemoryFallback = parsed;
          return parsed;
        }
      }
    } catch (_) {}
    return _pendingMemoryFallback;
  }
}

