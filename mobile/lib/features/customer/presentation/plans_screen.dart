import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';
import 'widgets/plan_card.dart';

typedef _PlanFeedItem = ({
  Restaurant restaurant,
  PlanTemplate plan,
  int? distanceMeters,
});

/// C4 · Planes: feed de planes anclado a la ubicación de Restaurantes con lazy loading.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  static const int _pageSize = 10;

  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _query = '';
  String? _selectedRestaurantId;

  // Caché local de planes por restaurante para paginar sin saturar la API.
  final Map<String, List<PlanTemplate>> _plansByRestaurant = {};
  int _nextRestaurantIndex = 0;
  int _visibleLimit = _pageSize;
  bool _loadingBatch = false;
  bool _initialLoaded = false;
  String _zoneSignature = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAndLoad());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loadingBatch) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _visibleLimit = _pageSize;
      });
    });
  }

  String _signatureFor(CustomerUiState s) {
    final c = s.searchCenter;
    final near = s.filters.contains(RestaurantFilter.near);
    return '${c?.latitude},${c?.longitude}|${s.searchRadiusMeters}|$near|${s.restaurants.length}';
  }

  List<Restaurant> _zoneRestaurants(CustomerUiState s) {
    final center = s.searchCenter;
    final radius = s.searchRadiusMeters;
    final nearOnly = s.filters.contains(RestaurantFilter.near);
    return s.restaurants.where((r) {
      if (center != null && radius != null) {
        if (!r.hasLocation) return false;
        final meters = LocationService.meters(
          center,
          LatLng(r.latitude!, r.longitude!),
        );
        if (meters > radius) return false;
      }
      if (nearOnly && r.distanceKm >= 1.0) {
        return false;
      }
      return true;
    }).toList();
  }

  int? _distanceMetersFor(CustomerUiState s, Restaurant r) {
    if (!r.hasLocation) return null;
    if (s.searchCenter != null) {
      return LocationService.meters(
        s.searchCenter!,
        LatLng(r.latitude!, r.longitude!),
      );
    }
    return (r.distanceKm * 1000).round();
  }

  String? _formatDistance(int? meters) {
    if (meters == null) return null;
    if (meters < 1000) return '$meters m';
    return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  Future<void> _syncAndLoad({bool forceRefresh = false}) async {
    final controller = ref.read(customerControllerProvider);
    final s = controller.state;
    final sig = _signatureFor(s);
    if (!forceRefresh && sig == _zoneSignature && _initialLoaded) return;

    _zoneSignature = sig;
    if (forceRefresh) {
      _plansByRestaurant.clear();
    }
    _nextRestaurantIndex = 0;
    _visibleLimit = _pageSize;

    final zoneRests = _zoneRestaurants(s);
    if (_selectedRestaurantId != null &&
        !zoneRests.any((r) => r.id == _selectedRestaurantId)) {
      _selectedRestaurantId = null;
    }

    await _fetchUntilCount(zoneRests, targetCount: _pageSize);
    if (mounted) {
      setState(() => _initialLoaded = true);
    }
  }

  Future<void> _loadMore() async {
    final s = ref.read(customerControllerProvider).state;
    final zoneRests = _zoneRestaurants(s);
    final currentTotal = _filteredItems(s, zoneRests).length;

    if (_visibleLimit < currentTotal) {
      setState(() => _visibleLimit += _pageSize);
      return;
    }
    if (_nextRestaurantIndex >= zoneRests.length) return;

    final nextTarget = currentTotal + _pageSize;
    await _fetchUntilCount(zoneRests, targetCount: nextTarget);
    if (mounted) {
      setState(() => _visibleLimit = nextTarget);
    }
  }

  Future<void> _fetchUntilCount(
    List<Restaurant> zoneRests, {
    required int targetCount,
  }) async {
    if (_loadingBatch) return;
    if (mounted) setState(() => _loadingBatch = true);

    final repo = ref.read(customerRepositoryProvider);
    var collected = 0;
    for (var i = 0; i < _nextRestaurantIndex && i < zoneRests.length; i++) {
      collected += (_plansByRestaurant[zoneRests[i].id] ?? const []).length;
    }

    const batchSize = 5;
    while (_nextRestaurantIndex < zoneRests.length && collected < targetCount) {
      final batch = <Restaurant>[];
      while (_nextRestaurantIndex < zoneRests.length && batch.length < batchSize) {
        final r = zoneRests[_nextRestaurantIndex];
        _nextRestaurantIndex++;
        if (_plansByRestaurant.containsKey(r.id)) {
          collected += (_plansByRestaurant[r.id] ?? const []).length;
        } else {
          batch.add(r);
        }
      }
      if (batch.isNotEmpty) {
        await Future.wait([
          for (final r in batch)
            repo.getPlanTemplates(r.id).then((plans) {
              _plansByRestaurant[r.id] = plans;
              collected += plans.length;
            }, onError: (_) {
              _plansByRestaurant[r.id] = const [];
            }),
        ]);
        if (mounted) setState(() {});
      }
    }

    if (mounted) setState(() => _loadingBatch = false);
  }

  Future<void> _ensureRestaurantPlans(Restaurant r) async {
    if (_plansByRestaurant.containsKey(r.id)) return;
    if (mounted) setState(() => _loadingBatch = true);
    try {
      final plans = await ref.read(customerRepositoryProvider).getPlanTemplates(r.id);
      _plansByRestaurant[r.id] = plans;
    } catch (_) {
      _plansByRestaurant[r.id] = const [];
    }
    if (mounted) setState(() => _loadingBatch = false);
  }

  List<Restaurant> _topRestaurants(List<Restaurant> zoneRests) {
    final withPlans = <Restaurant>[];
    for (final r in zoneRests) {
      final loadedPlans = _plansByRestaurant[r.id];
      if (loadedPlans != null) {
        if (loadedPlans.isNotEmpty) withPlans.add(r);
      } else if (r.hasPlan) {
        withPlans.add(r);
      }
    }
    return withPlans.isNotEmpty ? withPlans : zoneRests;
  }

  List<_PlanFeedItem> _filteredItems(
    CustomerUiState s,
    List<Restaurant> zoneRests,
  ) {
    final q = _query.toLowerCase();
    final items = <_PlanFeedItem>[];

    for (final r in zoneRests) {
      if (_selectedRestaurantId != null && r.id != _selectedRestaurantId) {
        continue;
      }
      if (q.isNotEmpty &&
          !r.name.toLowerCase().contains(q) &&
          !r.zone.toLowerCase().contains(q)) {
        final plans = _plansByRestaurant[r.id] ?? const <PlanTemplate>[];
        final matchesPlan = plans.any((p) => p.name.toLowerCase().contains(q));
        if (!matchesPlan) continue;
      }
      final plans = _plansByRestaurant[r.id] ?? const <PlanTemplate>[];
      final dist = _distanceMetersFor(s, r);
      for (final p in plans) {
        if (q.isNotEmpty &&
            !r.name.toLowerCase().contains(q) &&
            !r.zone.toLowerCase().contains(q) &&
            !p.name.toLowerCase().contains(q)) {
          continue;
        }
        items.add((restaurant: r, plan: p, distanceMeters: dist));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    final colors = context.colorScheme;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final s = controller.state;
          final currentSig = _signatureFor(s);
          if (currentSig != _zoneSignature && !_loadingBatch) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _syncAndLoad());
          }

          if (s.restaurants.isEmpty &&
              (s.isLoading || s.status == CustomerStatus.initial)) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SkeletonBox(height: 76, radius: 16),
                SizedBox(height: 16),
                SkeletonBox(height: 48, radius: 14),
                SizedBox(height: 16),
                SkeletonBox(height: 140, radius: 16),
              ],
            );
          }

          if (s.restaurants.isEmpty && s.isError) {
            return CustomerErrorView(
              title: 'Error al cargar planes',
              message: 'No pudimos cargar los restaurantes disponibles.',
              onRetry: () async {
                await controller.loadDashboard();
                await _syncAndLoad(forceRefresh: true);
              },
            );
          }

          final zoneRests = _zoneRestaurants(s);
          final topRests = _topRestaurants(zoneRests);
          final allItems = _filteredItems(s, zoneRests);
          final visibleItems = allItems.take(_visibleLimit).toList();
          final hasMoreToFetch =
              _visibleLimit < allItems.length ||
              _nextRestaurantIndex < zoneRests.length;

          final selectedRest = _selectedRestaurantId == null
              ? null
              : zoneRests
                  .where((r) => r.id == _selectedRestaurantId)
                  .firstOrNull;
          final zoneLabel = (s.searchCenter != null && s.searchRadiusMeters != null)
              ? '${s.searchZoneLabel ?? 'Zona elegida'} (${_formatDistance(s.searchRadiusMeters)})'
              : (s.filters.contains(RestaurantFilter.near)
                  ? 'Cerca de ti (< 1 km)'
                  : 'Todas las zonas');

          return RefreshIndicator(
            onRefresh: () async {
              await controller.loadDashboard(silent: true);
              await _syncAndLoad(forceRefresh: true);
            },
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 1. Header Principal
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Planes de almuerzo',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ahorra en cada comida y olvídate del efectivo diario',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Mostrando planes cerca de: $zoneLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Tarjeta Condicional de Plan Activo
                if (s.passes.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _ActivePassesPager(
                        passes: s.passes,
                        restaurants: s.restaurants,
                      ),
                    ),
                  ),

                // 3. Barra de Búsqueda Minimalista
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: SizedBox(
                      height: 48,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        style: TextStyle(fontSize: 14, color: colors.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Buscar restaurante',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).scaffoldBackgroundColor,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: colors.onSurfaceVariant,
                          ),
                          suffixIcon: _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar',
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _debounce?.cancel();
                                    setState(() {
                                      _query = '';
                                      _visibleLimit = _pageSize;
                                    });
                                  },
                                ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colors.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. Accesos Rápidos: "Top restaurantes"
                if (topRests.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Top restaurantes',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 104,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: topRests.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) {
                                final r = topRests[i];
                                final isSelected = _selectedRestaurantId == r.id;
                                return _TopRestaurantTile(
                                  restaurant: r,
                                  selected: isSelected,
                                  onTap: () async {
                                    if (isSelected) {
                                      setState(() {
                                        _selectedRestaurantId = null;
                                        _visibleLimit = _pageSize;
                                      });
                                    } else {
                                      setState(() {
                                        _selectedRestaurantId = r.id;
                                        _visibleLimit = _pageSize;
                                      });
                                      await _ensureRestaurantPlans(r);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Título del Feed de Planes
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          selectedRest != null
                              ? 'Planes en ${selectedRest.name}'
                              : 'Planes disponibles',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        if (selectedRest != null) ...[
                          Builder(
                            builder: (context) {
                              final activeHere = s.passFor(selectedRest.id);
                              final hasActive = activeHere != null &&
                                  activeHere.remainingLunches > 0 &&
                                  !activeHere.isExpired;
                              if (!hasActive) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _ActivePlanNoticeBanner(
                                  remaining: activeHere.remainingLunches,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // 5. Feed de Planes con Lazy Loading (o Empty State)
                if (!_initialLoaded && _loadingBatch)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          SkeletonBox(height: 148, radius: 16),
                          SizedBox(height: 12),
                          SkeletonBox(height: 148, radius: 16),
                        ],
                      ),
                    ),
                  )
                else if (visibleItems.isEmpty && !_loadingBatch)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      child: _EmptyPlansState(query: _query),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: visibleItems.length,
                      itemBuilder: (_, i) {
                        final item = visibleItems[i];
                        final singleCents =
                            (item.restaurant.singleLunchPrice * 100).round();
                        final activeHere = s.passFor(item.restaurant.id);
                        final hasActive = activeHere != null &&
                            activeHere.remainingLunches > 0 &&
                            !activeHere.isExpired;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: PlanCard(
                            plan: item.plan,
                            singleLunchPriceCents: singleCents,
                            enabled: !hasActive,
                            showRestaurantHeader: true,
                            restaurantName: item.restaurant.name,
                            distanceLabel: _formatDistance(item.distanceMeters),
                            onTap: () =>
                                context.push('/customer/planes/${item.plan.id}'),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_loadingBatch && hasMoreToFetch)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SkeletonBox(height: 148, radius: 16),
                      ),
                    ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActivePassesPager extends StatefulWidget {
  const _ActivePassesPager({
    required this.passes,
    required this.restaurants,
  });

  final List<CustomerPass> passes;
  final List<Restaurant> restaurants;

  @override
  State<_ActivePassesPager> createState() => _ActivePassesPagerState();
}

class _ActivePassesPagerState extends State<_ActivePassesPager> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    if (widget.passes.length == 1) {
      return _ActivePassCard(
        pass: widget.passes.first,
        restaurant: widget.restaurants
            .where((r) => r.id == widget.passes.first.restaurantId)
            .firstOrNull,
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 224,
          child: PageView.builder(
            itemCount: widget.passes.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final p = widget.passes[i];
              final rest = widget.restaurants
                  .where((r) => r.id == p.restaurantId)
                  .firstOrNull;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _ActivePassCard(pass: p, restaurant: rest),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.passes.length; i++)
              Container(
                width: i == _index ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _index
                      ? colors.primary
                      : colors.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActivePassCard extends StatelessWidget {
  const _ActivePassCard({required this.pass, required this.restaurant});

  final CustomerPass pass;
  final Restaurant? restaurant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final pct = pass.totalLunches == 0
        ? 0
        : (pass.remainingLunches * 100 / pass.totalLunches).round();
    final progress =
        pass.totalLunches == 0 ? 0.0 : pass.remainingLunches / pass.totalLunches;
    final restName = restaurant?.name ?? pass.restaurantName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: 0.45),
            colors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.primary,
                child: Text(
                  monogram(restName),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: colors.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      pass.planName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: b.successContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Text(
                  'Plan Activo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: b.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${pass.remainingLunches} de ${pass.totalLunches} restantes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: colors.primary,
                ),
              ),
              const Spacer(),
              Text(
                '$pct% disponible',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: colors.outlineVariant.withValues(alpha: 0.6),
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Vence ${formatShortDate(pass.expiresAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => context.go('/customer/pase'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                label: const Text('Ver pase QR'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopRestaurantTile extends StatelessWidget {
  const _TopRestaurantTile({
    required this.restaurant,
    required this.selected,
    required this.onTap,
  });

  final Restaurant restaurant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final hasLogo =
        restaurant.logoUrl != null && restaurant.logoUrl!.trim().isNotEmpty;

    Widget fallbackAvatar() => Center(
          child: CircleAvatar(
            radius: 22,
            backgroundColor: colors.primaryContainer,
            child: Text(
              monogram(restaurant.name),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: colors.primary,
              ),
            ),
          ),
        );

    return SizedBox(
      width: 78,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? colors.primary : colors.outlineVariant,
                  width: selected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: hasLogo
                  ? Image.network(
                      restaurant.logoUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) =>
                          progress == null
                              ? child
                              : const SkeletonBox(height: 68, radius: 16),
                      errorBuilder: (_, _, _) => fallbackAvatar(),
                    )
                  : fallbackAvatar(),
            ),
            const SizedBox(height: 6),
            Text(
              restaurant.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                height: 1.15,
                color: selected ? colors.primary : colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlansState extends StatelessWidget {
  const _EmptyPlansState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final isSearch = query.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            isSearch ? Icons.search_off_rounded : Icons.location_off_outlined,
            size: 30,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            isSearch
                ? "No encontramos planes para '$query' en tu zona actual."
                : 'Aún no hay planes en esta zona',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          if (!isSearch) ...[
            const SizedBox(height: 6),
            Text(
              'Cambia tu ubicación en la pestaña Restaurantes para explorar otras zonas cercanas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivePlanNoticeBanner extends StatelessWidget {
  const _ActivePlanNoticeBanner({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: b.successContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: b.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: b.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ya cuentas con un plan activo en este restaurante ($remaining almuerzos restantes)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
