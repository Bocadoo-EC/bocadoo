import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../customer_controller.dart';

/// Fila de 4 accesos rápidos de "Dónde comer": tarjeta cuadrada redondeada
/// con ícono centrado y etiqueta debajo. Tocar un acceso activo lo desactiva.
///
/// Usa `Expanded` con 10 px de separación, por lo que cabe sin overflow desde
/// 360 px de ancho. Colores solo desde el tema (claro/oscuro).
class QuickAccessCategoryRow extends StatelessWidget {
  const QuickAccessCategoryRow({
    super.key,
    required this.activeFilters,
    required this.onToggle,
  });

  final Set<RestaurantFilter> activeFilters;
  final ValueChanged<RestaurantFilter> onToggle;

  static const _items = <_QuickAccessItem>[
    _QuickAccessItem(
      filter: RestaurantFilter.fastService,
      label: 'Atención rápida',
      icon: Icons.bolt_rounded,
    ),
    _QuickAccessItem(
      filter: RestaurantFilter.available,
      label: 'Disponibles',
      icon: Icons.check_circle_outline_rounded,
    ),
    _QuickAccessItem(
      filter: RestaurantFilter.withPlan,
      label: 'Con mi plan',
      icon: Icons.confirmation_number_outlined,
    ),
    _QuickAccessItem(
      filter: RestaurantFilter.offers,
      label: 'Ofertas',
      icon: Icons.local_offer_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, item) in _items.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _QuickAccessCard(
              item: item,
              active: activeFilters.contains(item.filter),
              onTap: () => onToggle(item.filter),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickAccessItem {
  const _QuickAccessItem({
    required this.filter,
    required this.label,
    required this.icon,
  });

  final RestaurantFilter filter;
  final String label;
  final IconData icon;
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _QuickAccessItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;

    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: active
                    ? Border.all(color: colors.primary, width: 1.5)
                    : null,
              ),
              // TODO: Reemplazar con asset personalizado de Bocadoo
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(item.icon, size: 28, color: colors.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? colors.primary : colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
