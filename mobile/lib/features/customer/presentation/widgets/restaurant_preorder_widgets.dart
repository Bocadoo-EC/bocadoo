import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';
import 'hybrid_extras_section.dart';
import 'hybrid_order_state.dart';

/// Cabecera superior con nombre, indicador `Paso X de 2`, barra de progreso y
/// botón atrás cuando corresponde al Paso 2.
class PreorderModalHeader extends StatelessWidget {
  const PreorderModalHeader({
    super.key,
    required this.restaurantName,
    required this.step,
    required this.totalSteps,
    required this.subtitle,
    this.onBack,
  });

  final String restaurantName;
  final int step;
  final int totalSteps;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final progress = (step / totalSteps).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Volver al paso 1',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Paso $step de $totalSteps',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: colors.primaryContainer.withValues(alpha: 0.45),
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta limpia de restaurante sin banner redundante, ocupación ni distancia.
class CleanRestaurantPlanCard extends StatelessWidget {
  const CleanRestaurantPlanCard({
    super.key,
    required this.restaurant,
    required this.publicStatus,
    required this.hasPlanHere,
    required this.onTable,
  });

  final Restaurant restaurant;
  final RestaurantPublicStatus publicStatus;
  final bool hasPlanHere;
  final VoidCallback onTable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final r = restaurant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        hasPlanHere
                            ? 'Tienes almuerzos activos aquí'
                            : 'Planes ejecutivos disponibles',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Desde ${formatMoney(r.planLunchPrice ?? r.singleLunchPrice)} con plan · ${formatMoney(r.singleLunchPrice)} suelto',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PillAction(
            label: publicStatus.isFull
                ? 'Pedido grupal (Para llevar)'
                : 'Pedido grupal',
            icon: Icons.group_outlined,
            onPressed: (publicStatus.isSoldOutToday || publicStatus.isClosed)
                ? null
                : onTable,
          ),
        ],
      ),
    );
  }
}

/// Navegación superior persistente entre `Menú del Día` y `Carta`.
class OrderTypeSegmentedBar extends StatelessWidget {
  const OrderTypeSegmentedBar({
    super.key,
    required this.activeTab,
    required this.addonsCount,
    required this.onChanged,
  });

  final RestaurantOrderTab activeTab;
  final int addonsCount;
  final ValueChanged<RestaurantOrderTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<RestaurantOrderTab>(
      showSelectedIcon: false,
      segments: [
        const ButtonSegment<RestaurantOrderTab>(
          value: RestaurantOrderTab.menuDelDia,
          icon: Icon(Icons.soup_kitchen_outlined, size: 17),
          label: Text('Menú del Día'),
        ),
        ButtonSegment<RestaurantOrderTab>(
          value: RestaurantOrderTab.carta,
          icon: const Icon(Icons.restaurant_menu_rounded, size: 17),
          label: Text(
            addonsCount > 0 ? 'Carta ($addonsCount)' : 'Carta',
          ),
        ),
      ],
      selected: {activeTab},
      onSelectionChanged: (sel) {
        if (sel.isNotEmpty) onChanged(sel.first);
      },
    );
  }
}

/// Bloque editable `Tu Orden` para el Paso 2 de 2 (reemplaza pantalla de carrito).
class EditableHybridOrderCard extends StatelessWidget {
  const EditableHybridOrderCard({
    super.key,
    required this.restaurant,
    required this.state,
    required this.hasPlanHere,
    required this.onEditLunch,
    required this.onClearLunch,
    required this.onIncrementItem,
    required this.onDecrementItem,
    required this.onRemoveItem,
  });

  final Restaurant restaurant;
  final HybridOrderState state;
  final bool hasPlanHere;
  final VoidCallback onEditLunch;
  final VoidCallback onClearLunch;
  final ValueChanged<PublicCartaItem> onIncrementItem;
  final ValueChanged<String> onDecrementItem;
  final ValueChanged<String> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final hasLunch = state.isLunchReady(restaurant);
    final addons = state.addonsList;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Tu Orden',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (hasLunch) ...[
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onEditLunch,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.breakfastMode
                                ? 'Desayuno del día'
                                : 'Almuerzo del día',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.lunchSummaryLine(restaurant),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasPlanHere
                                ? '1 cupo de plan'
                                : formatMoney(restaurant.singleLunchPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar almuerzo',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEditLunch,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: colors.primary,
                    ),
                  ),
                  if (addons.isNotEmpty)
                    IconButton(
                      tooltip: 'Quitar almuerzo',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClearLunch,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: colors.error,
                      ),
                    ),
                ],
              ),
            ),
          ],
          for (final line in addons) ...[
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatCents(line.item.priceCents)} c/u · Subtotal ${formatCents(line.subtotalCents)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  HybridQtyControl(
                    quantity: line.quantity,
                    onAdd: () => onIncrementItem(line.item),
                    onDecrement: () => onDecrementItem(line.item.id),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onRemoveItem(line.item.id),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Desglose Financiero Transparente (Split-Billing) para el Paso 2.
class SplitBillingSummaryCard extends StatelessWidget {
  const SplitBillingSummaryCard({
    super.key,
    required this.tender,
    required this.remainingLunches,
  });

  final HybridTenderSummary tender;
  final int remainingLunches;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final planCredits = tender.planCreditsUsed;
    final cashCents = tender.cashToCollectCents;
    // Canal preparado para habilitar cobro anticipado con Deuna en Fase 2.
    const paymentChannelNote =
        'Se abona en caja al retirar tu pedido (próximamente pago anticipado con Deuna).';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (planCredits > 0) ...[
            Row(
              children: [
                Icon(Icons.verified_rounded, size: 16, color: b.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Descuento de Plan:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Text(
                  '-$planCredits Almuerzo',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: b.success,
                  ),
                ),
              ],
            ),
            if (remainingLunches > 0)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  'Te quedarán ${(remainingLunches - planCredits).clamp(0, 999)} cupos disponibles en tu plan.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: colors.primary.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total a pagar al llegar al local:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
              Text(
                formatCents(cashCents),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          if (cashCents > 0) ...[
            const SizedBox(height: 6),
            Text(
              paymentChannelNote,
              style: TextStyle(
                fontSize: 11.5,
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
