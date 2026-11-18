import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';

String? rLogoOrImage(Restaurant r) =>
    r.imageUrl.isNotEmpty ? r.imageUrl : r.logoUrl;

const _limitNotice = 'Límite: tienes una orden activa pendiente.';

/// C2 · Dónde comer: buscador, filtros combinables y locales cercanos.
class RestaurantsScreen extends ConsumerStatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  ConsumerState<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends ConsumerState<RestaurantsScreen> {
  late final TextEditingController _search =
      TextEditingController(text: ref.read(customerControllerProvider).state.searchQuery);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openRestaurant(Restaurant r) {
    ref.invalidate(restaurantDetailProvider(r.id));
    context.push('/customer/restaurants/${r.id}');
  }

  Future<void> _reserve(CustomerController controller, RestaurantOffer offer) async {
    final ok = await controller.reserveOffer(offer);
    if (!ok && mounted) {
      final msg = controller.lastActionError ?? _limitNotice;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.state;
        return SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Header(controller: controller, search: _search, state: s),
            Expanded(child: _buildBody(context, controller, s)),
          ]),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, CustomerController controller, CustomerUiState s) {
    if (s.restaurants.isEmpty && (s.isLoading || s.status == CustomerStatus.initial)) {
      return Semantics(
        label: 'Buscando restaurantes',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SkeletonBox(height: 220, radius: 24),
            SizedBox(height: 16),
            SkeletonBox(height: 220, radius: 24),
            SizedBox(height: 16),
            SkeletonBox(height: 220, radius: 24),
          ],
        ),
      );
    }
    if (s.restaurants.isEmpty && s.isError) {
      return CustomerErrorView(
        title: 'Error al buscar',
        message: 'No pudimos cargar los restaurantes disponibles.',
        onRetry: controller.loadDashboard,
      );
    }

    final colors = context.colorScheme;
    final searching = s.searchQuery.trim().isNotEmpty;
    final filtered = s.filteredRestaurants;
    final planRestaurants = s.restaurants.where((r) => r.hasPlan).toList();
    final todayOffers = [
      for (final r in s.restaurants)
        for (final o in r.offers.where((o) => o.appliesToday)) (r, o),
    ];

    return RefreshIndicator(
      onRefresh: () => controller.loadDashboard(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (s.isOffline) ...[
            const _OfflineBadge(text: 'Sin conexión · Locales guardados'),
            const SizedBox(height: 16),
          ],
          if (!searching) ...[
            const _TableHero(),
            const SizedBox(height: 20),
          ],
          if (planRestaurants.isNotEmpty && !searching && !s.filters.contains(RestaurantFilter.offers)) ...[
            _SectionTitle('Tu plan'),
            const SizedBox(height: 8),
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: planRestaurants.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _PlanAvatar(
                  restaurant: planRestaurants[i],
                  onTap: () => _openRestaurant(planRestaurants[i]),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (todayOffers.isNotEmpty && !s.filters.contains(RestaurantFilter.withPlan)) ...[
            Row(children: [
              Icon(Icons.bolt_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 4),
              _SectionTitle('Ofertas hoy'),
            ]),
            const SizedBox(height: 8),
            for (final (r, o) in todayOffers) ...[
              _OfferTile(
                restaurant: r,
                offer: o,
                onTap: () => _openRestaurant(r),
                onReserve: () => _reserve(controller, o),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],
          Row(children: [
            Expanded(child: _SectionTitle('Cerca de ti')),
            Text(
              '${filtered.length} locales',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
            ),
          ]),
          if (s.searchCenter != null && s.searchRadiusMeters != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: Icon(Icons.radar_rounded, size: 16, color: colors.primary),
                label: Text(
                  '${s.searchZoneLabel ?? 'Zona'} · ${s.searchRadiusMeters! < 1000 ? '${s.searchRadiusMeters} m' : '${(s.searchRadiusMeters! / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.primary),
                ),
                onDeleted: controller.clearSearchArea,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            _NoResults(onClear: () {
              _search.clear();
              controller.clearFilters();
            })
          else
            for (final r in filtered) ...[
              _RestaurantCard(
                restaurant: r,
                occupancy: ref.watch(restaurantOccupancyProvider(r.id)),
                onOpen: () => _openRestaurant(r),
                onTable: () => context.push('/customer/mesa?restaurantId=${r.id}'),
                onReserve: (o) => _reserve(controller, o),
              ),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CustomerController controller;
  final TextEditingController search;
  final CustomerUiState state;

  const _Header({required this.controller, required this.search, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Dónde comer',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          Material(
            color: colors.primaryContainer,
            shape: StadiumBorder(side: BorderSide(color: colors.primary.withValues(alpha: 0.25))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => context.push('/customer/mapa'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Icon(Icons.location_on_outlined, size: 15, color: colors.primary),
                  const SizedBox(width: 3),
                  Text('Lugares cercanos',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          onChanged: controller.setSearchQuery,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Buscar restaurante o plato',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            prefixIcon: Icon(Icons.search_rounded, color: colors.onSurfaceVariant),
            suffixIcon: state.searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
                    onPressed: () {
                      search.clear();
                      controller.setSearchQuery('');
                    },
                  ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              borderSide: BorderSide(color: colors.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (final (i, f) in const [
            ('Cerca', RestaurantFilter.near),
            ('Con plan', RestaurantFilter.withPlan),
            ('Libre', RestaurantFilter.free),
            ('Ofertas', RestaurantFilter.offers),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _FilterChip(
                label: f.$1,
                selected: state.filters.contains(f.$2),
                onTap: () => controller.toggleFilter(f.$2),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Semantics(
      button: true,
      toggled: selected,
      child: Material(
        color: selected ? colors.primary : Theme.of(context).scaffoldBackgroundColor,
        shape: StadiumBorder(side: BorderSide(color: selected ? colors.primary : colors.outlineVariant)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.colorScheme.onSurface),
      );
}

class _OfflineBadge extends StatelessWidget {
  final String text;
  const _OfflineBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.wifi_off_rounded, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
      ]),
    );
  }
}

class _TableHero extends StatelessWidget {
  const _TableHero();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final fg = b.imageForeground;
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: b.heroGradient),
        child: InkWell(
          onTap: () => context.push('/customer/mesa'),
          child: Stack(children: [
            Positioned(
              right: -32,
              top: -32,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(color: fg.withValues(alpha: 0.15), shape: BoxShape.circle),
              ),
            ),
            Positioned(
              right: 64,
              bottom: -40,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: fg.withValues(alpha: 0.10), shape: BoxShape.circle),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('Nuevo · Mesa con amigos',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colors.onSurface)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '¡Almuerza en grupo y ganen juntos!',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.15, color: fg),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Crea una mesa, comparte tu QR y coordinen el almuerzo en 1 toque.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.qr_code_2_rounded, size: 15, color: colors.onSurface),
                        const SizedBox(width: 6),
                        Text('Crear mesa',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.onSurface)),
                        const SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 15, color: colors.onSurface),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.group_outlined, size: 28, color: colors.onSurface),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PlanAvatar extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;

  const _PlanAvatar({required this.restaurant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 84,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            CoverImage(
              url: rLogoOrImage(restaurant),
              name: restaurant.name,
              width: 56,
              height: 56,
              radius: 16,
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Icon(Icons.confirmation_number_outlined, size: 10, color: colors.onPrimary),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            restaurant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onSurface),
          ),
        ]),
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  final Restaurant restaurant;
  final RestaurantOffer offer;
  final VoidCallback onTap;
  final VoidCallback onReserve;

  const _OfferTile({required this.restaurant, required this.offer, required this.onTap, required this.onReserve});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Theme.of(context).scaffoldBackgroundColor, colors.primaryContainer]),
          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CoverImage(
                url: rLogoOrImage(restaurant),
                name: restaurant.name,
                width: 48,
                height: 48,
                radius: 16,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(restaurant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
                  _OfferBadge(text: offer.badge),
                  Text(offer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurface)),
                  if (offer.price != null)
                    Text.rich(TextSpan(children: [
                      TextSpan(
                        text: formatMoney(offer.price!),
                        style: TextStyle(fontWeight: FontWeight.w900, color: colors.onSurface),
                      ),
                      if (offer.originalPrice != null)
                        TextSpan(
                          text: '  ${formatMoney(offer.originalPrice!)}',
                          style: const TextStyle(decoration: TextDecoration.lineThrough),
                        ),
                    ]), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(width: 8),
              offer.reservable
                  ? PillAction(
                      label: offer.availableNow ? 'Reservar' : 'Fuera de horario',
                      onPressed: offer.availableNow ? onReserve : null,
                    )
                  : PillAction(label: 'Ver', onPressed: onTap),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OfferBadge extends StatelessWidget {
  final String text;
  const _OfferBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Row(children: [
      Icon(Icons.bolt_rounded, size: 14, color: colors.primary),
      const SizedBox(width: 2),
      Flexible(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
      ),
    ]);
  }
}

class _RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final String occupancy;
  final VoidCallback onOpen;
  final VoidCallback onTable;
  final ValueChanged<RestaurantOffer> onReserve;

  const _RestaurantCard({
    required this.restaurant,
    required this.occupancy,
    required this.onOpen,
    required this.onTable,
    required this.onReserve,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final r = restaurant;

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 112,
            child: Stack(fit: StackFit.expand, children: [
              CoverImage(url: rLogoOrImage(r), name: r.name),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      colors.scrim.withValues(alpha: 0.6),
                      colors.scrim.withValues(alpha: 0),
                      colors.scrim.withValues(alpha: 0.2),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(children: [
                  OccupancyChip(occupancy: occupancy),
                  const Spacer(),
                  if (r.hasLocation)
                    DistancePill(text: r.formattedDistance),
                ]),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: b.imageForeground),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Hoy: ${r.featuredDish}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface),
              ),
              for (final o in r.offers.take(2)) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Expanded(child: _OfferBadge(text: o.badge)),
                    if (o.reservable)
                      PillAction(
                        label: o.availableNow ? 'Reservar' : 'Fuera de horario',
                        tonal: false,
                        onPressed: o.availableNow ? () => onReserve(o) : null,
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: formatMoney(r.singleLunchPrice),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.primary),
                      ),
                      TextSpan(text: '  (Desde ${formatMoney(r.planLunchPrice ?? r.singleLunchPrice)} con plan)'),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
                  ),
                ),
                if (r.hasBreakfastToday) const _Tag(icon: Icons.wb_sunny_outlined, label: 'Desayunos'),
                if (r.hasPlan) ...[
                  const SizedBox(width: 4),
                  const _Tag(icon: Icons.confirmation_number_outlined, label: 'Plan activo'),
                ],
              ]),
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.outlineVariant),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: PillAction(
                    label: 'Armar mesa',
                    icon: Icons.group_add_outlined,
                    tonal: false,
                    onPressed: onTable,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillAction(
                    label: 'Ver menú',
                    icon: Icons.arrow_forward,
                    trailingIcon: true,
                    onPressed: onOpen,
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Tag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: colors.primary),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colors.primary)),
      ]),
    );
  }
}

class _NoResults extends StatelessWidget {
  final VoidCallback onClear;
  const _NoResults({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, shape: BoxShape.circle),
          child: Icon(Icons.search_rounded, size: 26, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Text('Sin resultados', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.onSurface)),
        const SizedBox(height: 4),
        Text('Intenta cambiar los filtros de búsqueda.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onClear,
          style: ElevatedButton.styleFrom(minimumSize: const Size(160, 48)),
          child: const Text('Limpiar filtros'),
        ),
      ]),
    );
  }
}
