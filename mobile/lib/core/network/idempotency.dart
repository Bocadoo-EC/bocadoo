import 'dart:math';

/// Genera un UUID v4 criptográficamente aleatorio sin dependencias externas.
String uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');

  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
      '${hex(4)}${hex(5)}-'
      '${hex(6)}${hex(7)}-'
      '${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}

/// Mantiene una misma `Idempotency-Key` por intención durante 2 minutos
/// para evitar duplicados en reintentos de red o dobles toques.
class IdempotencyStore {
  final Map<String, ({String key, DateTime at})> _keys = {};

  String keyFor(String intent) {
    final existing = _keys[intent];
    if (existing != null &&
        DateTime.now().difference(existing.at) < const Duration(minutes: 2)) {
      return existing.key;
    }
    final key = uuidV4();
    _keys[intent] = (key: key, at: DateTime.now());
    return key;
  }

  /// Libera la clave cuando la operación termina con éxito.
  void done(String intent) => _keys.remove(intent);

  void clear() => _keys.clear();
}
