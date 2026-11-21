import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'widgets/flash_offer_card.dart';

enum _FlashSort { cheapest, endingSoon }

/// Ofertas Flash del día: todas las ofertas activas (un plato cada una) con
/// dos órdenes: menor precio y por terminar pronto.
class FlashOffersScreen extends ConsumerStatefulWidget {
  const FlashOffersScreen({super.key});

  @override
  ConsumerState<FlashOffersScreen> createState() => _FlashOffersScreenState();
}

class _FlashOffersScreenState extends ConsumerState<FlashOffersScreen> {
  static const _refreshEvery = Duration(seconds: 10);

  Timer? _ticker;
  Timer? _refresher;
  DateTime _now = DateTime.now();
  _FlashSort _sort = _FlashSort.endingSoon;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // Los cupos bajan en el servidor: se relee la lista sin loaders.
    _refresher = Timer.periodic(_refreshEvery, (_) {
      if (!mounted) return;
      unawaited(
        ref.read(customerControllerProvider).refreshRestaurants(forceHydrate: true),
      );
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refresher?.cancel();
    super.dispose();
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go('/customer/restaurants');

  List<(Restaurant, RestaurantOffer)> _sorted(
    List<(Restaurant, RestaurantOffer)> offers,
  ) {
    final list = [...offers];
    int byPrice((Restaurant, RestaurantOffer) a, (Restaurant, RestaurantOffer) b) =>
        (a.$2.price ?? double.infinity).compareTo(b.$2.price ?? double.infinity);
    int byEnd((Restaurant, RestaurantOffer) a, (Restaurant, RestaurantOffer) b) {
      final ea = a.$2.endsAt;
      final eb = b.$2.endsAt;
      if (ea == null && eb == null) return 0;
      if (ea == null) return 1;
      if (eb == null) return -1;
      return ea.compareTo(eb);
    }

    list.sort(
      _sort == _FlashSort.cheapest
          ? (a, b) {
              final c = byPrice(a, b);
              return c != 0 ? c : byEnd(a, b);
            }
          : (a, b) {
              final c = byEnd(a, b);
              return c != 0 ? c : byPrice(a, b);
            },
    );
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final controller = ref.watch(customerControllerProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Ofertas Flash del día'),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final offers = _sorted(controller.state.activeZoneFlashOffers(_now));
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Cupos limitados · Válido hoy',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _SortChip(
                      icon: Icons.payments_outlined,
                      label: '💵 Por precio',
                      selected: _sort == _FlashSort.cheapest,
                      onTap: () => setState(() => _sort = _FlashSort.cheapest),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SortChip(
                      icon: Icons.timer_outlined,
                      label: '⏱️ Por tiempo disponible',
                      selected: _sort == _FlashSort.endingSoon,
                      onTap: () => setState(() => _sort = _FlashSort.endingSoon),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                if (offers.isEmpty)
                  _EmptyOffers(onBack: _back)
                else
                  for (final (r, o) in offers) ...[
                    FlashOfferCard(
                      key: ValueKey(o.id),
                      restaurant: r,
                      offer: o,
                      now: _now,
                      showAvatar: true,
                      ctaLabel: 'Reclamar oferta',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text('Reclamo de oferta pendiente de integración de pago'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          side: BorderSide(
            color: selected ? colors.primary : colors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: selected ? fg : colors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyOffers extends StatelessWidget {
  const _EmptyOffers({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Icon(Icons.bolt_rounded, size: 40, color: colors.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'Ya no hay ofertas flash activas',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          'Vuelve más tarde: los locales publican nuevas ofertas durante el día.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onBack, child: const Text('Volver a Dónde comer')),
      ]),
    );
  }
}
