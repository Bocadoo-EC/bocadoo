import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';
import 'widgets/flash_offers_section.dart';
import 'widgets/quick_access_category_row.dart';

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
  CustomerController? _controllerRef;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controllerRef = ref.read(customerControllerProvider);
      _controllerRef?.setRestaurantsVisible(true);
    });
  }

  @override
  void dispose() {
    _controllerRef?.setRestaurantsVisible(false);
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
    final flashOffers = controller.state.activeZoneFlashOffers();

    return RefreshIndicator(
      onRefresh: () => controller.refreshRestaurants(forceHydrate: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (s.isOffline) ...[
            const _OfflineBadge(text: 'Sin conexión · Locales guardados'),
            const SizedBox(height: 16),
          ],
          QuickAccessCategoryRow(
            activeFilters: s.filters,
            onToggle: controller.toggleFilter,
          ),
          const SizedBox(height: 16),
          // Sin ofertas activas no ocupa espacio: "Cerca de ti" sube directo.
          if (!searching)
            FlashOffersSection(
              offers: flashOffers,
              onOrder: (_, _) => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text('Reclamo de oferta pendiente de integración de pago'),
                ),
              ),
              onSeeAll: () => context.push('/customer/ofertas-flash'),
            ),
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
                publicStatus: ref.watch(restaurantPublicStatusProvider(r.id)),
                hasUserActivePlan: () {
                  final pass = s.passFor(r.id);
                  return pass != null &&
                      !pass.isExpired &&
                      pass.remainingLunches > 0;
                }(),
                isDailyMenuUnpublished:
                    s.todayMenuAvailabilityByRest[r.id] ==
                        MenuAvailabilityState.sinPublicar ||
                    (AppMode.useMock && r.todayMenu.isEmpty),
                onUnpublishedTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text(
                        'Este restaurante aún no ha publicado su menú de hoy',
                      ),
                    ),
                  );
                },
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
      ]),
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
  final RestaurantPublicStatus publicStatus;
  final bool hasUserActivePlan;
  final bool isDailyMenuUnpublished;
  final VoidCallback onUnpublishedTap;
  final VoidCallback onOpen;
  final VoidCallback onTable;
  final ValueChanged<RestaurantOffer> onReserve;

  const _RestaurantCard({
    required this.restaurant,
    required this.publicStatus,
    this.hasUserActivePlan = false,
    this.isDailyMenuUnpublished = false,
    required this.onUnpublishedTap,
    required this.onOpen,
    required this.onTable,
    required this.onReserve,
  });

  static const _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final r = restaurant;
    final isMenuSoldOut = publicStatus.isSoldOutToday;
    final isClosed = publicStatus.isClosed;
    final isFull = publicStatus.isFull;
    final canGroupOrder = !isMenuSoldOut && !isClosed && !isDailyMenuUnpublished;
    final canOpenMenu = !isDailyMenuUnpublished;
    final bannerCover = CoverImage(url: rLogoOrImage(r), name: r.name);

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpenMenu ? onOpen : onUnpublishedTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 112,
            child: Stack(fit: StackFit.expand, children: [
              isClosed
                  ? ColorFiltered(
                      colorFilter: _grayscaleFilter,
                      child: bannerCover,
                    )
                  : bannerCover,
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
                  OccupancyChip(status: publicStatus),
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
              if (!isMenuSoldOut && !isClosed)
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
                if (hasUserActivePlan) ...[
                  const SizedBox(width: 4),
                  const _Tag(icon: Icons.confirmation_number_outlined, label: 'Plan activo'),
                ],
              ]),
              if (isDailyMenuUnpublished) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: b.walletAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: b.onWalletAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Menú del día no publicado',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: b.onWalletAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isFull && !isDailyMenuUnpublished) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: b.dangerContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: b.danger, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Salón lleno · Solo para llevar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: b.onDangerContainer,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.outlineVariant),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: isDailyMenuUnpublished
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onUnpublishedTap,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.45,
                              child: PillAction(
                                label: isFull
                                    ? 'Pedido grupal (Para llevar)'
                                    : 'Pedido grupal',
                                icon: Icons.group_add_outlined,
                                tonal: false,
                                onPressed: null,
                              ),
                            ),
                          ),
                        )
                      : PillAction(
                          label: isFull
                              ? 'Pedido grupal (Para llevar)'
                              : 'Pedido grupal',
                          icon: Icons.group_add_outlined,
                          tonal: false,
                          onPressed: canGroupOrder ? onTable : null,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: isDailyMenuUnpublished
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onUnpublishedTap,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.45,
                              child: PillAction(
                                label: 'Ver menú',
                                icon: Icons.arrow_forward,
                                trailingIcon: true,
                                onPressed: null,
                              ),
                            ),
                          ),
                        )
                      : PillAction(
                          label: isFull ? 'Pedir para llevar' : 'Ver menú',
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
