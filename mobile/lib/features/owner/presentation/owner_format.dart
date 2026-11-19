/// Formatos de presentación del módulo Dueño (sin depender de `intl`).
class OwnerFormat {
  OwnerFormat._();

  /// `3.5` → `$3,50`
  static String money(double value) =>
      '\$${value.toStringAsFixed(2).replaceAll('.', ',')}';

  /// `12:45 PM`
  static String time(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// `13:15` (24h en hora Ecuador UTC-5).
  static String time24(DateTime t) {
    final ec = t.toUtc().subtract(const Duration(hours: 5));
    final hh = ec.hour.toString().padLeft(2, '0');
    final mm = ec.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
