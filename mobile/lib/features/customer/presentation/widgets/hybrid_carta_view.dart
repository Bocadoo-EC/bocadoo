import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';
import 'hybrid_extras_section.dart';
import 'hybrid_order_state.dart';

/// Pestaña `Carta`: lista platos fuertes a la carta con descripción, precio USD
/// y selector `- 1 +`, seguida de la sección compartida `Extras`.
class HybridCartaView extends StatelessWidget {
  const HybridCartaView({
    super.key,
    required this.restaurant,
    required this.cartaItems,
    required this.isLoading,
    required this.orderState,
    required this.onAdd,
    required this.onDecrement,
  });

  final Restaurant restaurant;
  final List<PublicCartaItem> cartaItems;
  final bool isLoading;
  final HybridOrderState orderState;
  final ValueChanged<PublicCartaItem> onAdd;
  final ValueChanged<String> onDecrement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final mains = cartaItems
        .where((i) => i.category.toUpperCase() == 'A_LA_CARTA')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLoading && cartaItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (mains.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              'Este local aún no ha publicado platos fuertes a la carta.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          Text(
            'Platos a la carta',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in mains)
            _CartaDishCard(
              item: item,
              quantity: orderState.quantityOf(item.id),
              onAdd: () => onAdd(item),
              onDecrement: () => onDecrement(item.id),
            ),
        ],
        const SizedBox(height: 16),
        HybridExtrasSection(
          restaurant: restaurant,
          cartaItems: cartaItems,
          orderState: orderState,
          showIncluded: false,
          onAdd: onAdd,
          onDecrement: onDecrement,
        ),
      ],
    );
  }
}

class _CartaDishCard extends StatelessWidget {
  const _CartaDishCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onDecrement,
  });

  final PublicCartaItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final active = quantity > 0 && !item.isSoldOut;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active
              ? colors.primaryContainer.withValues(alpha: 0.25)
              : Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
              Opacity(
                opacity: item.isSoldOut ? 0.45 : 1,
                child: CoverImage(
                  url: item.imageUrl,
                  name: item.name,
                  width: 52,
                  height: 52,
                  radius: 12,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: item.isSoldOut
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                      decoration:
                          item.isSoldOut ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    formatCents(item.priceCents),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (item.isSoldOut)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: b.dangerContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Text(
                  'Agotado',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: b.onDangerContainer,
                  ),
                ),
              )
            else
              HybridQtyControl(
                quantity: quantity,
                onAdd: onAdd,
                onDecrement: onDecrement,
              ),
          ],
        ),
      ),
    );
  }
}
