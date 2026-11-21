import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';
import 'flash_offer_card.dart';

/// Módulo adaptativo de Ofertas Flash de "Dónde comer" (cada oferta = 1 plato).
///
/// - 0 ofertas activas: no ocupa espacio.
/// - 1 oferta: tarjeta del plato con precio tachado, cupos, cronómetro y
///   "Pedir ya →".
/// - 2 o más: tarjeta resumen compacta con "Ver todas →" hacia la pantalla
///   de Ofertas Flash.
///
/// Un único `Timer.periodic(1s)` alimenta los cronómetros. Al llegar a 00:00 o
/// a 0 cupos la oferta sale sola de la lista, sin esperar un refresco de red.
class FlashOffersSection extends StatefulWidget {
  const FlashOffersSection({
    super.key,
    required this.offers,
    required this.onOrder,
    required this.onSeeAll,
  });

  /// Ofertas flash candidatas; el widget descarta las que ya vencieron.
  final List<(Restaurant, RestaurantOffer)> offers;
  final void Function(Restaurant, RestaurantOffer) onOrder;
  final VoidCallback onSeeAll;

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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: live.length == 1
          ? FlashOfferCard(
              restaurant: live.first.$1,
              offer: live.first.$2,
              now: _now,
              ctaLabel: 'Reclamar oferta',
              onTap: () => widget.onOrder(live.first.$1, live.first.$2),
            )
          : _FlashSummaryCard(
              offers: [for (final e in live) e.$2],
              now: _now,
              onSeeAll: widget.onSeeAll,
            ),
    );
  }
}

/// Tarjeta resumen (≥ 2 ofertas): precio mínimo y próximo vencimiento.
class _FlashSummaryCard extends StatelessWidget {
  const _FlashSummaryCard({
    required this.offers,
    required this.now,
    required this.onSeeAll,
  });

  final List<RestaurantOffer> offers;
  final DateTime now;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;

    final prices = [for (final o in offers) ?o.price];
    final minPrice = prices.isEmpty ? null : prices.reduce((a, c) => a < c ? a : c);
    final remainings = [for (final o in offers) ?o.endsAt?.difference(now)];
    final soonest = remainings.isEmpty
        ? null
        : remainings.reduce((a, c) => a < c ? a : c);

    final parts = [
      if (minPrice != null) 'Almuerzos desde ${formatMoney(minPrice)}',
      if (soonest != null) 'Próxima vence en ${formatFlashRemaining(soonest)}',
    ];

    return Semantics(
      button: true,
      label: '${offers.length} ofertas flash activas ahora. Ver todas',
      child: Material(
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
            onTap: onSeeAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(Icons.bolt_rounded, size: 20, color: colors.primary),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              '${offers.length} Ofertas Flash activas en tu zona',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w900,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ]),
                        if (parts.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            parts.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Ver todas →',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
