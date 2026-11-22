import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';

String formatMoney(double amount) => formatCents((amount * 100).round());

String formatCents(int cents) {
  final abs = cents.abs();
  final text = '\$${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
  return cents < 0 ? '-$text' : text;
}

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String formatShortDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';

String monogram(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'B';
  if (parts.length == 1) {
    return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Etiqueta de sección en mayúsculas (SOPA DEL DÍA, ÚLTIMOS MOVIMIENTOS).
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: context.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Foto del local o plato; si falla, muestra el monograma.
class CoverImage extends StatelessWidget {
  final String? url;
  final String name;
  final double? width;
  final double? height;
  final double radius;

  const CoverImage({
    super.key,
    required this.url,
    required this.name,
    this.width,
    this.height,
    this.radius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer,
            colors.primary.withValues(alpha: 0.22),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        monogram(name),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null || url!.isEmpty
          ? fallback
          : Image.network(
              url!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// Chip del estado público unificado sobre la portada de la tarjeta en Marketplace.
class OccupancyChip extends StatelessWidget {
  final RestaurantPublicStatus status;
  const OccupancyChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final mins = status.remainingFullMinutes;
    final (String label, Color dot, Color bg, Color fg) = switch (status.effective) {
      RestaurantEffectiveStatus.libre => (
          'Libre',
          b.success,
          b.successContainer,
          b.onSuccessContainer,
        ),
      RestaurantEffectiveStatus.concurrido => (
          'Concurrido',
          b.onWalletAccent,
          b.walletAccent,
          b.onWalletAccent,
        ),
      RestaurantEffectiveStatus.lleno => (
          mins > 0 ? 'Lleno · ${mins}m' : 'Lleno',
          b.dangerForeground,
          b.danger,
          b.dangerForeground,
        ),
      RestaurantEffectiveStatus.agotadoHoy => (
          'Agotado hoy',
          b.danger,
          b.dangerContainer,
          b.onDangerContainer,
        ),
      RestaurantEffectiveStatus.cerrado => (
          'Cerrado / Pausado',
          colors.onSurface,
          colors.surfaceContainerHighest,
          colors.onSurface,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
        ),
      ]),
    );
  }
}

/// Estado público unificado en la cabecera de la ficha del local.
class OccupancyDetail extends StatelessWidget {
  final RestaurantPublicStatus status;
  const OccupancyDetail({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final mins = status.remainingFullMinutes;
    final (String label, Color dot, Color bg, Color fg) = switch (status.effective) {
      RestaurantEffectiveStatus.libre => (
          'Libre · Llegas y te sientas',
          b.success,
          b.successContainer,
          b.onSuccessContainer,
        ),
      RestaurantEffectiveStatus.concurrido => (
          'Concurrido · Poca espera',
          b.onWalletAccent,
          b.walletAccent,
          b.onWalletAccent,
        ),
      RestaurantEffectiveStatus.lleno => (
          mins > 0 ? 'Lleno · Espera ~$mins min' : 'Lleno · Sin mesas ahora',
          b.dangerForeground,
          b.danger,
          b.dangerForeground,
        ),
      RestaurantEffectiveStatus.agotadoHoy => (
          'Agotado hoy',
          b.danger,
          b.dangerContainer,
          b.onDangerContainer,
        ),
      RestaurantEffectiveStatus.cerrado => (
          'Cerrado / Pausado',
          colors.onSurface,
          colors.surfaceContainerHighest,
          colors.onSurface,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
          ),
        ),
      ]),
    );
  }
}

/// Distancia sobre una foto: "0.2 km · 2 min".
class DistancePill extends StatelessWidget {
  final String text;
  const DistancePill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = context.bocadooColors.imageForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.scrim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_on_outlined, size: 13, color: fg),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// Botón pequeño en cápsula para acciones secundarias dentro de tarjetas.
class PillAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool tonal;
  final bool trailingIcon;

  const PillAction({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tonal = true,
    this.trailingIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final enabled = onPressed != null;
    final iconWidget = icon == null
        ? null
        : Icon(
            icon,
            size: 15,
            color: enabled ? colors.primary : colors.onSurfaceVariant,
          );
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: tonal ? colors.primaryContainer : colors.surface,
        foregroundColor: tonal ? colors.onPrimaryContainer : colors.primary,
        disabledBackgroundColor: colors.outlineVariant.withValues(alpha: 0.5),
        disabledForegroundColor: colors.onSurfaceVariant,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: StadiumBorder(
          side: tonal ? BorderSide.none : BorderSide(color: colors.outlineVariant),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (iconWidget != null && !trailingIcon) ...[iconWidget, const SizedBox(width: 5)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (iconWidget != null && trailingIcon) ...[const SizedBox(width: 5), iconWidget],
      ]),
    );
  }
}

/// Banner flotante "Pedido enviado · Deshacer" con cuenta regresiva.
class UndoBanner extends StatelessWidget {
  final String label;
  final int secondsLeft;
  final VoidCallback onUndo;

  const UndoBanner({
    super.key,
    required this.label,
    required this.secondsLeft,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.inverseSurface,
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
        child: Row(children: [
          Expanded(
            child: Text(
              '$label · ${secondsLeft}s',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onInverseSurface),
            ),
          ),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(foregroundColor: colors.inversePrimary),
            child: const Text('Deshacer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

/// Estado de error con "Reintentar".
class CustomerErrorView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const CustomerErrorView({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: b.dangerContainer,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: b.danger),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.error_outline_rounded, size: 40, color: b.onDangerContainer),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: b.onDangerContainer)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.onDangerContainer)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: b.danger, foregroundColor: b.dangerForeground),
              child: const Text('Reintentar'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Bloque de carga simple con pulso.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({super.key, this.width, required this.height, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
