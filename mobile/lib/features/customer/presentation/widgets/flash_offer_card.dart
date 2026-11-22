import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';

/// Formato humano del tiempo restante: `4h 22m` si >= 1 hora, `45m 12s` si < 1 hora.
String formatFlashRemaining(Duration d) {
  final safe = d.isNegative ? Duration.zero : d;
  final hours = safe.inHours;
  final minutes = safe.inMinutes % 60;
  final seconds = safe.inSeconds % 60;
  if (hours >= 1) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

/// Tarjeta de una oferta flash: **un plato** con precio normal tachado vs.
/// precio de oferta, cupos restantes, cronómetro en vivo y CTA.
///
/// [now] lo entrega quien tiene el ticker, así una sola `Timer.periodic(1s)`
/// alimenta todas las tarjetas visibles.
class FlashOfferCard extends StatelessWidget {
  const FlashOfferCard({
    super.key,
    required this.restaurant,
    required this.offer,
    required this.now,
    required this.ctaLabel,
    required this.onTap,
    this.showAvatar = false,
    this.showCta = true,
  });

  final Restaurant restaurant;
  final RestaurantOffer offer;
  final DateTime now;
  final String ctaLabel;
  final VoidCallback onTap;

  /// Foto (o monograma) del local a la izquierda del nombre.
  final bool showAvatar;

  /// Oculta el botón (p. ej. dentro de la confirmación de orden).
  final bool showCta;

  /// Menos de 5 minutos: el cronómetro pasa a color de urgencia.
  static const _urgentBelow = Duration(minutes: 5);

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final endsAt = offer.endsAt;
    final remaining = endsAt?.difference(now);
    final urgent = remaining != null && remaining < _urgentBelow;
    final price = offer.price;
    final original = offer.originalPrice;
    final slots = offer.slotsLeft;
    final pillBg = colors.surface.withValues(alpha: 0.75);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer,
              b.walletAccent.withValues(alpha: 0.35),
            ],
          ),
          border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bolt_rounded, size: 13, color: colors.onPrimary),
                      const SizedBox(width: 2),
                      Text(
                        'OFERTA FLASH',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: colors.onPrimary,
                        ),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  if (remaining != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: urgent ? b.danger : colors.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          formatFlashRemaining(remaining),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: urgent ? b.danger : colors.primary,
                          ),
                        ),
                      ]),
                    ),
                ]),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  if (showAvatar) ...[
                    CoverImage(
                      url: restaurant.imageUrl.isNotEmpty ? restaurant.imageUrl : restaurant.logoUrl,
                      name: restaurant.name,
                      width: 48,
                      height: 48,
                      radius: 14,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        restaurant.hasLocation
                            ? '${restaurant.name} · ${restaurant.formattedDistance}'
                            : restaurant.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: colors.onSurface,
                        ),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (original != null && price != null && original > price)
                      Text(
                        formatMoney(original),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.lineThrough,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    if (price != null)
                      Text(
                        formatMoney(price),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: colors.primary,
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        slots == 1 ? 'Queda 1 cupo' : 'Quedan $slots cupos',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (showCta) ...[
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: Text(ctaLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
