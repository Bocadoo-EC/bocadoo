/// Conversiones monetarias entre centavos enteros del backend y dólares en UI.
class Money {
  Money._();

  static double fromCents(int cents) => cents / 100.0;
  static int toCents(double dollars) => (dollars * 100).round();
}

/// Normalización de teléfonos ecuatorianos entre formato local (`09...`) y E.164 (`+593...`).
class Phone {
  Phone._();

  static String toE164(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('0')) return '+593${digits.substring(1)}';
    if (digits.startsWith('593')) return '+$digits';
    return '+$digits';
  }

  static String toLocal(String? e164) {
    if (e164 == null || e164.isEmpty) return '';
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('593') ? '0${digits.substring(3)}' : digits;
  }
}

/// Utilidades de fecha y hora para Ecuador (`America/Guayaquil`, UTC-5 todo el año).
class EcuadorTime {
  EcuadorTime._();

  static DateTime now() =>
      DateTime.now().toUtc().subtract(const Duration(hours: 5));

  /// Devuelve la fecha local de Ecuador en formato `AAAA-MM-DD`.
  static String today() {
    final n = now();
    return '${n.year}-${_two(n.month)}-${_two(n.day)}';
  }

  /// Convierte una hora local `'HH:mm'` de hoy a instante UTC.
  static DateTime todayAtUtc(String hhmm) {
    final parts = hhmm.split(':');
    final n = now();
    return DateTime.utc(
      n.year,
      n.month,
      n.day,
      int.parse(parts[0]) + 5,
      int.parse(parts[1]),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
