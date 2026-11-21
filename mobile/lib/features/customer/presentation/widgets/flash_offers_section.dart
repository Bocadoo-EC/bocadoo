import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';

/// Módulo adaptativo de Ofertas Flash de "Dónde comer".
///
/// - 0 ofertas activas: no renderiza nada.
/// - 1 oferta: tarjeta compacta con cronómetro regresivo.
/// - 2 o más: encabezado "Ofertas flash del día (N)" + carrusel horizontal.
///
/// Un único `Timer.periodic(1s)` alimenta el cronómetro de cada tarjeta (cada
/// una calcula su propio tiempo restante). Al llegar a 00:00 la oferta se
/// quita sola de la lista, sin esperar a un refresco de red.
class FlashOffersSection extends StatefulWidget {
  const FlashOffersSection({
    super.key,
    required this.offers,
    required this.onOpenRestaurant,
  });

  /// Ofertas flash candidatas; el widget descarta las que ya vencieron.
  final List<(Restaurant, RestaurantOffer)> offers;
  final ValueChanged<Restaurant> onOpenRestaurant;

  @override
  State<FlashOffersSection> createState() => _FlashOffersSectionState();
}

class _FlashOffersSectionState extends State<FlashOffersSection> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant FlashOffersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _now = DateTime.now();
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// El ticker solo corre mientras haya alguna oferta con hora de fin.
  void _syncTicker() {
    final needsTicker = widget.offers.any((e) => e.$2.endsAt != null);
    if (needsTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!needsTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = [
      for (final e in widget.offers)
        if (e.$2.isActiveFlashAt(_now)) e,
    ];
    if (live.isEmpty) return const SizedBox.shrink();

    if (live.length == 1) {
      final (r, o) = live.first;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _FlashOfferCard(
          restaurant: r,
          offer: o,
          now: _now,
          onTap: () => widget.onOpenRestaurant(r),
        ),
      );
    }

    final colors = context.colorScheme;
    final cardWidth =
        (MediaQuery.sizeOf(context).width * 0.8).clamp(240.0, 320.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Ofertas flash del día (${live.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: live.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final (r, o) = live[i];
                return SizedBox(
                  width: cardWidth,
                  child: _FlashOfferCard(
                    key: ValueKey(o.id),
                    restaurant: r,
                    offer: o,
                    now: _now,
                    onTap: () => widget.onOpenRestaurant(r),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRemaining(Duration d) {
  final safe = d.isNegative ? Duration.zero : d;
  final mm = safe.inMinutes.toString().padLeft(2, '0');
  final ss = (safe.inSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

class _FlashOfferCard extends StatelessWidget {
  const _FlashOfferCard({
    super.key,
    required this.restaurant,
    required this.offer,
    required this.now,
    required this.onTap,
  });

  final Restaurant restaurant;
  final RestaurantOffer offer;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final endsAt = offer.endsAt;
    final price = offer.price;

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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 108),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: 13, color: colors.onPrimary),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    price == null
                        ? offer.title
                        : '${offer.title} · ${formatMoney(price)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (restaurant.hasLocation)
                        Flexible(
                          child: Text(
                            restaurant.formattedDistance,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (endsAt != null) ...[
                        Icon(Icons.timer_outlined,
                            size: 14, color: colors.primary),
                        const SizedBox(width: 3),
                        Text(
                          'Termina en ${_formatRemaining(endsAt.difference(now))}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
