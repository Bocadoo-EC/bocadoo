import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre un enlace en la app externa (WhatsApp, navegador). Avisa si no se pudo.
Future<void> openExternal(BuildContext context, Uri uri, {String failMessage = 'No se pudo abrir el enlace'}) async {
  final messenger = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(failMessage)));
  }
}

/// Enlace de WhatsApp con mensaje. Sin [phone] deja elegir el contacto.
Uri whatsAppUri(String text, {String? phone}) =>
    Uri.parse('https://wa.me/${phone ?? ''}?text=${Uri.encodeComponent(text)}');

/// Celular ecuatoriano ("0991234567") a formato internacional ("593991234567").
String toInternationalPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.startsWith('0') ? '593${digits.substring(1)}' : digits;
}
