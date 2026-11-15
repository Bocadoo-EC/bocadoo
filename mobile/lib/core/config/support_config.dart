/// Contacto de soporte de Bocadoo. No hay número fijo en el código: se define
/// al compilar, por ejemplo:
///
/// ```
/// flutter run --dart-define=BOCADOO_SUPPORT_WHATSAPP=5939XXXXXXXX
/// flutter run --dart-define=BOCADOO_SUPPORT_URL=https://bocadoo.ec/ayuda
/// ```
///
/// Si no se define ninguno, los botones de ayuda se muestran desactivados.
class SupportConfig {
  const SupportConfig._();

  /// WhatsApp de soporte en formato internacional sin "+".
  static const String whatsApp = String.fromEnvironment('BOCADOO_SUPPORT_WHATSAPP');

  /// Página de ayuda (se usa si no hay WhatsApp).
  static const String url = String.fromEnvironment('BOCADOO_SUPPORT_URL');

  static bool get isConfigured => whatsApp.isNotEmpty || url.isNotEmpty;

  /// Enlace de soporte con un mensaje inicial, o `null` si no está configurado.
  static Uri? link(String message) {
    if (whatsApp.isNotEmpty) {
      return Uri.parse('https://wa.me/$whatsApp?text=${Uri.encodeComponent(message)}');
    }
    if (url.isNotEmpty) return Uri.tryParse(url);
    return null;
  }
}
