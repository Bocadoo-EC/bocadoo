import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';

export '../../../core/utils/external_links.dart' show openExternal, whatsAppUri;

/// Botón secundario compacto: los botones del tema ocupan todo el ancho.
ButtonStyle compactButtonStyle(BuildContext context) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
    );

/// QR con los colores fijos de lectura (iguales en claro y oscuro).
class SocialQr extends StatelessWidget {
  const SocialQr({super.key, required this.value, required this.size});

  final String value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return QrImageView(
      data: value.isEmpty ? 'BOCADOO' : value,
      version: QrVersions.auto,
      size: size,
      padding: EdgeInsets.zero,
      backgroundColor: b.qrBackground,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: b.qrForeground),
      dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: b.qrForeground),
    );
  }
}

/// Rótulo de sección en mayúscula inicial (REGLAS_UX: sin mayúsculas sostenidas).
class SocialLabel extends StatelessWidget {
  const SocialLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.colorScheme.onSurfaceVariant),
      );
}

/// Badge en cápsula ("Anfitrión", "Veggie", "Mesa activa").
class SocialBadge extends StatelessWidget {
  const SocialBadge({super.key, required this.label, required this.background, required this.foreground, this.icon});

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.buttonRadius)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: foreground)),
        ),
      ]),
    );
  }
}

/// Opción seleccionable. Seleccionada: morado relleno (como el prototipo).
class SocialChoice extends StatelessWidget {
  const SocialChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.radius = 18,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Material(
      color: selected ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: selected ? colors.primary : colors.primary.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? fg : colors.primary),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Carga centrada con texto.
class SocialLoading extends StatelessWidget {
  const SocialLoading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.colorScheme.onSurface)),
        ]),
      ),
    );
  }
}

/// Estado vacío con una acción.
class SocialEmpty extends StatelessWidget {
  const SocialEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icon, size: 52, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
        ]),
      ),
    );
  }
}
