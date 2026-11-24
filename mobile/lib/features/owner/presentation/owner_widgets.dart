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

/// Control de segmentos en cápsula (Hoy/Mis platos, Planes/Clientes, pestañas).
/// [filledSelected] pinta el segmento activo en morado (pestañas de Métricas).
class OwnerSegmented extends StatelessWidget {
  const OwnerSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.icons,
    this.filledSelected = false,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int index;
  final ValueChanged<int> onChanged;
  final bool filledSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: filledSelected ? colors.secondaryContainer : Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: filledSelected ? null : Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Material(
              color: i == index ? (filledSelected ? colors.primary : colors.surface) : colors.surface.withValues(alpha: 0),
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (icons != null) ...[
                      Icon(icons![i],
                          size: 16,
                          color: i == index
                              ? (filledSelected ? colors.onPrimary : colors.primary)
                              : colors.onSurface),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: i == index
                              ? (filledSelected ? colors.onPrimary : colors.primary)
                              : (filledSelected ? colors.onSurface : colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Botón secundario compacto para filas (los botones del tema ocupan todo el ancho).
class OwnerSmallButton extends StatelessWidget {
  const OwnerSmallButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tonal = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      side: tonal ? null : WidgetStatePropertyAll(BorderSide(color: context.colorScheme.outlineVariant)),
    );
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (tonal) {
      return icon == null
          ? FilledButton.tonal(onPressed: onPressed, style: style, child: text)
          : FilledButton.tonalIcon(onPressed: onPressed, style: style, icon: Icon(icon, size: 16), label: text);
    }
    return icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: text)
        : OutlinedButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 16), label: text);
  }
}

/// Badge de estado en mayúscula inicial (Borrador / Publicado / Activo).
class OwnerBadge extends StatelessWidget {
  const OwnerBadge({super.key, required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.buttonRadius)),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: foreground),
      ),
    );
  }
}

/// Error de carga con "Reintentar" (REGLAS_UX §6).
class OwnerErrorView extends StatelessWidget {
  const OwnerErrorView({super.key, required this.title, required this.message, required this.onRetry});

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: b.dangerContainer, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.error_outline_rounded, size: 36, color: b.onDangerContainer),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: b.onDangerContainer)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.onDangerContainer)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ]),
        ),
      ),
    );
  }
}

/// Carga con texto, centrada.
class OwnerLoadingView extends StatelessWidget {
  const OwnerLoadingView(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.colorScheme.onSurface)),
      ]),
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
