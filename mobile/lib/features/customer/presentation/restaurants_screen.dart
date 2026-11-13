import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';

/// Catálogo de restaurantes afiliados, filtros y detalle del Menú del Día.
class RestaurantsScreen extends ConsumerStatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  ConsumerState<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends ConsumerState<RestaurantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _activeFilter = 'Todos';

  static const List<String> _filterOptions = [
    'Todos',
    'Ejecutivo',
    'Veggie',
    'Económico',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Restaurant> _applyEconomicFilter(List<Restaurant> source) {
    if (_activeFilter != 'Económico') return source;
    final query = _searchController.text.trim().toLowerCase();
    return source.where((r) {
      final matchesPrice = r.singleLunchPrice <= 3.25;
      final matchesQuery = query.isEmpty ||
          r.name.toLowerCase().contains(query) ||
          r.zone.toLowerCase().contains(query) ||
          r.description.toLowerCase().contains(query);
      return matchesPrice && matchesQuery;
    }).toList();
  }

  void _onSearchChanged(String query) {
    final controller = ref.read(customerControllerProvider);
    final repoCategory = _activeFilter == 'Económico' ? 'Todos' : _activeFilter;
    controller.filterRestaurants(query, category: repoCategory);
    setState(() {});
  }

  void _onFilterSelected(String filter) {
    setState(() {
      _activeFilter = filter;
    });
    final controller = ref.read(customerControllerProvider);
    final repoCategory = filter == 'Económico' ? 'Todos' : filter;
    controller.filterRestaurants(_searchController.text, category: repoCategory);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final uiState = controller.state;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final displayList = _activeFilter == 'Económico'
            ? _applyEconomicFilter(uiState.restaurants)
            : uiState.filteredRestaurants;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Volver al pase',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.go('/customer/pase'),
            ),
            title: const Text('Dónde comer'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton.icon(
                  onPressed: () => context.go('/customer/pase'),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Mi pase'),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Buscador y chips de filtro rápido
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Buscar restaurante o zona...',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: colors.onSurfaceVariant,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: colors.onSurfaceVariant,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _filterOptions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final option = _filterOptions[index];
                          final selected = _activeFilter == option;
                          return ChoiceChip(
                            label: Text(option),
                            selected: selected,
                            onSelected: (_) => _onFilterSelected(option),
                            selectedColor: colors.primaryContainer,
                            backgroundColor: colors.surface,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                            side: BorderSide(
                              color: selected
                                  ? colors.primary
                                  : colors.outlineVariant,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.buttonRadius),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Lista de restaurantes
              Expanded(
                child: _buildBody(context, controller, uiState, displayList),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    CustomerController controller,
    CustomerUiState uiState,
    List<Restaurant> displayList,
  ) {
    final colors = Theme.of(context).colorScheme;

    if (uiState.isLoading && uiState.restaurants.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (uiState.isError && uiState.restaurants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: colors.error),
              const SizedBox(height: 12),
              Text(
                'Error al cargar locales',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                uiState.errorMessage ?? 'No pudimos obtener los restaurantes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => controller.loadDashboard(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (displayList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 36,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Sin resultados',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Intenta cambiar los filtros o la búsqueda.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.loadDashboard(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        itemCount: displayList.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final restaurant = displayList[index];
          return _RestaurantCard(
            restaurant: restaurant,
            onTap: () {
              controller.selectRestaurant(restaurant);
              _showMenuBottomSheet(context, restaurant);
            },
          );
        },
      ),
    );
  }

  void _showMenuBottomSheet(BuildContext context, Restaurant restaurant) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;

    final soups =
        restaurant.todayMenu.where((m) => m.category == 'Sopa').toList();
    final mains = restaurant.todayMenu
        .where((m) => m.category == 'Plato Fuerte')
        .toList();
    final drinks =
        restaurant.todayMenu.where((m) => m.category == 'Bebida').toList();
    final desserts =
        restaurant.todayMenu.where((m) => m.category == 'Postre').toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hoy en ${restaurant.name}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${restaurant.zone} · ${restaurant.address}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            // Resumen de precios (Plan vs Suelto)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Con tu plan',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            _formatMoney(
                              restaurant.planLunchPrice ??
                                  restaurant.singleLunchPrice,
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Almuerzo suelto',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.onSecondaryContainer,
                            ),
                          ),
                          Text(
                            _formatMoney(restaurant.singleLunchPrice),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  if (soups.isNotEmpty)
                    _MenuCategorySection(
                      title: 'Sopa',
                      icon: Icons.soup_kitchen_rounded,
                      items: soups,
                      bColor: bColor,
                    ),
                  if (mains.isNotEmpty)
                    _MenuCategorySection(
                      title: 'Fuerte',
                      icon: Icons.dinner_dining_rounded,
                      items: mains,
                      bColor: bColor,
                    ),
                  if (drinks.isNotEmpty)
                    _MenuCategorySection(
                      title: 'Bebida',
                      icon: Icons.local_drink_rounded,
                      items: drinks,
                      bColor: bColor,
                    ),
                  if (desserts.isNotEmpty)
                    _MenuCategorySection(
                      title: 'Postre',
                      icon: Icons.icecream_rounded,
                      items: desserts,
                      bColor: bColor,
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      context.go('/customer/pase');
                    },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Mostrar mi pase en caja'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMoney(double amount) {
    return '\$${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

class _RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;

  const _RestaurantCard({
    required this.restaurant,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen superior + badges de estado y ocupación
            SizedBox(
              height: 148,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    restaurant.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: colors.primaryContainer,
                      child: Icon(
                        Icons.restaurant_rounded,
                        size: 48,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: restaurant.isOpen
                            ? bColor.successContainer
                            : colors.errorContainer,
                        borderRadius:
                            BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Text(
                        restaurant.isOpen ? 'Abierto' : 'Cerrado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: restaurant.isOpen
                              ? bColor.success
                              : colors.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.92),
                        borderRadius:
                            BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_alt_rounded,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            restaurant.occupancy,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        restaurant.rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    restaurant.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.near_me_rounded,
                        size: 15,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${restaurant.distanceKm.toStringAsFixed(1)} km · ${restaurant.zone}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Plan \$${(restaurant.planLunchPrice ?? restaurant.singleLunchPrice).toStringAsFixed(2).replaceAll('.', ',')}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCategorySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<MenuItem> items;
  final BocadooColors bColor;

  const _MenuCategorySection({
    required this.title,
    required this.icon,
    required this.items,
    required this.bColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .scaffoldBackgroundColor
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: item.isSoldOut
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                            decoration: item.isSoldOut
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (item.isVeggie)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Opción veggie',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: bColor.success,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item.isSoldOut)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius:
                            BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Text(
                        'Agotado',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: colors.onErrorContainer,
                        ),
                      ),
                    )
                  else if (item.price != null)
                    Text(
                      '\$${item.price!.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

