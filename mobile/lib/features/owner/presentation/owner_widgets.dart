import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

const _undoWindow = Duration(seconds: 10);

/// Barra de deshacer de 10 s (cobros, ventas, ofertas y cierre).
void showUndoSnackBar(
  ScaffoldMessengerState messenger, {
  required String label,
  required VoidCallback onUndo,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: _undoWindow,
      persist: false,
      content: Text(label),
      action: SnackBarAction(label: 'Deshacer', onPressed: onUndo),
    ));
}

void showInfoSnackBar(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
}

/// Rótulo de sección en mayúscula inicial (REGLAS_UX: sin mayúsculas sostenidas).
class OwnerSectionLabel extends StatelessWidget {
  const OwnerSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: color ?? context.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Opción seleccionable en forma de pastilla o tarjeta (planes, métodos, cupos…).
class OwnerChoice extends StatelessWidget {
  const OwnerChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.subtitle,
    this.radius = AppTheme.buttonRadius,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Material(
      color: selected ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: selected ? colors.primary : colors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
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
            if (subtitle != null)
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? fg.withValues(alpha: 0.85) : colors.onSurfaceVariant,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Contenedor con borde punteado (tarjeta "Escanear QR").
class DashedBorderBox extends StatelessWidget {
  const DashedBorderBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = AppTheme.cardRadius,
    this.fill,
  });

  final Widget child;
  final Color color;
  final Color? fill;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: color, radius: radius, fill: fill),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius, this.fill});

  final Color color;
  final Color? fill;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      Radius.circular(radius),
    );
    if (fill != null) canvas.drawRRect(rrect, Paint()..color = fill!);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 7.0, gap = 5.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius || old.fill != fill;
}

/// Encabezado con botón de volver, usado en POS y Cierre.
class OwnerBackHeader extends StatelessWidget {
  const OwnerBackHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final Widget? eyebrow;
  final Widget? trailing;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Row(children: [
      IconButton.filledTonal(
        tooltip: 'Volver a caja',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          ?eyebrow,
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface),
          ),
        ]),
      ),
      ?trailing,
    ]);
  }
}
