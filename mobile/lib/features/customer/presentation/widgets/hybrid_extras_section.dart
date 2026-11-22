import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';
import 'hybrid_order_state.dart';

/// Sección compartida de `Extras` (Bebidas y Postres) para las pestañas
/// `Menú del Día` (`showIncluded: true`, con acordeón `3. Bebida` y `4. Postre`)
/// y `Carta` (`showIncluded: false`, solo ítems con precio USD).
class HybridExtrasSection extends StatelessWidget {
  const HybridExtrasSection({
    super.key,
    required this.restaurant,
    required this.cartaItems,
    required this.orderState,
    required this.showIncluded,
    required this.onAdd,
    required this.onDecrement,
    this.onSelectIncludedDrink,
    this.onSelectIncludedDessert,
  });

  final Restaurant restaurant;
  final List<PublicCartaItem> cartaItems;
  final HybridOrderState orderState;

  /// En `Menú del Día` es `true` (acordeón `3. Bebida` y `4. Postre` con `Incluido`).
  /// En `Carta` es `false` (nada es incluido gratis; solo ítems con precio USD).
  final bool showIncluded;
  final ValueChanged<PublicCartaItem> onAdd;
  final ValueChanged<String> onDecrement;
  final ValueChanged<String>? onSelectIncludedDrink;
  final ValueChanged<String>? onSelectIncludedDessert;

  List<MenuItem> _includedItems(String category, String fallbackName) {
    final fromMenu = restaurant.todayMenu
        .where((m) => m.category == category && !m.isSoldOut)
        .toList();
    if (fromMenu.isNotEmpty) return fromMenu;
    final cleanFallback = fallbackName.trim();
    if (cleanFallback.isEmpty) return const [];
    return [
      MenuItem(
        id: 'included_$category',
        name: cleanFallback,
        category: category,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final paidDrinks = cartaItems
        .where((i) => i.category.toUpperCase() == 'BEBIDA')
        .toList();
    final paidDessertsAndExtras = cartaItems
        .where((i) {
          final cat = i.category.toUpperCase();
          return cat == 'POSTRE' || cat == 'EXTRA';
        })
        .toList();

    final includedDrinks = showIncluded
        ? _includedItems('Bebida', restaurant.juice)
        : const <MenuItem>[];
    final includedDesserts = showIncluded
        ? _includedItems('Postre', restaurant.dessert)
        : const <MenuItem>[];

    final hasDrinks = includedDrinks.isNotEmpty || paidDrinks.isNotEmpty;
    final hasDesserts =
        includedDesserts.isNotEmpty || paidDessertsAndExtras.isNotEmpty;

    if (!hasDrinks && !hasDesserts) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 17,
              color: colors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Extras',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (showIncluded)
          _MenuExtrasAccordion(
            includedDrinks: includedDrinks,
            paidDrinks: paidDrinks,
            includedDesserts: includedDesserts,
            paidDessertsAndExtras: paidDessertsAndExtras,
            orderState: orderState,
            onAdd: onAdd,
            onDecrement: onDecrement,
            onSelectIncludedDrink: onSelectIncludedDrink,
            onSelectIncludedDessert: onSelectIncludedDessert,
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasDrinks) ...[
                  const _SubGroupTitle(
                    icon: Icons.local_drink_outlined,
                    title: 'Bebidas',
                  ),
                  for (final drink in paidDrinks)
                    _PaidAddonRow(
                      item: drink,
                      quantity: orderState.quantityOf(drink.id),
                      onAdd: () => onAdd(drink),
                      onDecrement: () => onDecrement(drink.id),
                    ),
                ],
                if (hasDrinks && hasDesserts)
                  Divider(height: 1, thickness: 1, color: colors.outlineVariant),
                if (hasDesserts) ...[
                  const _SubGroupTitle(
                    icon: Icons.icecream_outlined,
                    title: 'Postres y adicionales',
                  ),
                  for (final extra in paidDessertsAndExtras)
                    _PaidAddonRow(
                      item: extra,
                      quantity: orderState.quantityOf(extra.id),
                      onAdd: () => onAdd(extra),
                      onDecrement: () => onDecrement(extra.id),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

enum _ExtraAccordionGroup { drink, dessert }

class _MenuExtrasAccordion extends StatefulWidget {
  const _MenuExtrasAccordion({
    required this.includedDrinks,
    required this.paidDrinks,
    required this.includedDesserts,
    required this.paidDessertsAndExtras,
    required this.orderState,
    required this.onAdd,
    required this.onDecrement,
    this.onSelectIncludedDrink,
    this.onSelectIncludedDessert,
  });

  final List<MenuItem> includedDrinks;
  final List<PublicCartaItem> paidDrinks;
  final List<MenuItem> includedDesserts;
  final List<PublicCartaItem> paidDessertsAndExtras;
  final HybridOrderState orderState;
  final ValueChanged<PublicCartaItem> onAdd;
  final ValueChanged<String> onDecrement;
  final ValueChanged<String>? onSelectIncludedDrink;
  final ValueChanged<String>? onSelectIncludedDessert;

  @override
  State<_MenuExtrasAccordion> createState() => _MenuExtrasAccordionState();
}

class _MenuExtrasAccordionState extends State<_MenuExtrasAccordion> {
  static const _collapseDelay = Duration(milliseconds: 200);
  static const _animation = Duration(milliseconds: 200);

  final Set<_ExtraAccordionGroup> _expanded = {};
  final Map<_ExtraAccordionGroup, Timer> _timers = {};

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _toggle(_ExtraAccordionGroup g) {
    _timers.remove(g)?.cancel();
    setState(() {
      if (!_expanded.remove(g)) _expanded.add(g);
    });
  }

  void _pickIncluded(_ExtraAccordionGroup g, String name) {
    if (g == _ExtraAccordionGroup.drink) {
      widget.onSelectIncludedDrink?.call(name);
    } else {
      widget.onSelectIncludedDessert?.call(name);
    }
    _timers.remove(g)?.cancel();
    _timers[g] = Timer(_collapseDelay, () {
      if (!mounted) return;
      setState(() => _expanded.remove(g));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final hasDrink =
        widget.includedDrinks.isNotEmpty || widget.paidDrinks.isNotEmpty;
    final hasDessert = widget.includedDesserts.isNotEmpty ||
        widget.paidDessertsAndExtras.isNotEmpty;

    final selectedDrink = widget.orderState.drinkName ??
        (widget.includedDrinks.isNotEmpty
            ? widget.includedDrinks.first.name
            : null);
    final selectedDessert = widget.orderState.dessertName ??
        (widget.includedDesserts.isNotEmpty
            ? widget.includedDesserts.first.name
            : null);

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
          if (hasDrink)
            _buildGroup(
              context: context,
              group: _ExtraAccordionGroup.drink,
              title: '3. Bebida',
              badge: widget.includedDrinks.isNotEmpty ? 'Incluido' : 'Opcional',
              selectedLabel: selectedDrink,
              hint: widget.includedDrinks.length > 1
                  ? 'Elige 1'
                  : 'Opcional adicional',
              includedItems: widget.includedDrinks,
              paidItems: widget.paidDrinks,
            ),
          if (hasDrink && hasDessert)
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          if (hasDessert)
            _buildGroup(
              context: context,
              group: _ExtraAccordionGroup.dessert,
              title: hasDrink ? '4. Postre' : '3. Postre',
              badge:
                  widget.includedDesserts.isNotEmpty ? 'Incluido' : 'Opcional',
              selectedLabel: selectedDessert,
              hint: widget.includedDesserts.length > 1
                  ? 'Elige 1'
                  : 'Opcional adicional',
              includedItems: widget.includedDesserts,
              paidItems: widget.paidDessertsAndExtras,
            ),
        ],
      ),
    );
  }

  Widget _buildGroup({
    required BuildContext context,
    required _ExtraAccordionGroup group,
    required String title,
    required String badge,
    required String? selectedLabel,
    required String hint,
    required List<MenuItem> includedItems,
    required List<PublicCartaItem> paidItems,
  }) {
    final colors = context.colorScheme;
    final expanded = _expanded.contains(group);
    final divider = Divider(height: 1, thickness: 1, color: colors.outlineVariant);

    final paidCount = paidItems.fold<int>(
      0,
      (sum, i) => sum + widget.orderState.quantityOf(i.id),
    );
    final summaryText = [
      if (selectedLabel != null && selectedLabel.isNotEmpty) selectedLabel,
      if (paidCount > 0) '+$paidCount extra${paidCount == 1 ? '' : 's'}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExtrasAccordionHeader(
          title: title,
          hint: hint,
          selectedLabel: summaryText.isEmpty ? null : summaryText,
          badge: badge,
          expanded: expanded,
          onTap: () => _toggle(group),
        ),
        AnimatedSize(
          duration: _animation,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in includedItems) ...[
                      divider,
                      _IncludedRadioRow(
                        label: item.name,
                        selected: selectedLabel == item.name,
                        onTap: () => _pickIncluded(group, item.name),
                      ),
                    ],
                    for (final paid in paidItems) ...[
                      divider,
                      _PaidAddonRow(
                        item: paid,
                        quantity: widget.orderState.quantityOf(paid.id),
                        onAdd: () => widget.onAdd(paid),
                        onDecrement: () => widget.onDecrement(paid.id),
                      ),
                    ],
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _ExtrasAccordionHeader extends StatelessWidget {
  const _ExtrasAccordionHeader({
    required this.title,
    required this.hint,
    required this.selectedLabel,
    required this.badge,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String hint;
  final String? selectedLabel;
  final String badge;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final showCheck =
        !expanded && selectedLabel != null && selectedLabel!.isNotEmpty;

    return Semantics(
      button: true,
      expanded: expanded,
      label: '$title, $badge',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (showCheck)
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              selectedLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 24,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncludedRadioRow extends StatelessWidget {
  const _IncludedRadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final ring = selected ? colors.primary : colors.onSurfaceVariant;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Incluido',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: selected ? 10 : 0,
                    height: selected ? 10 : 0,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubGroupTitle extends StatelessWidget {
  const _SubGroupTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaidAddonRow extends StatelessWidget {
  const _PaidAddonRow({
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: item.isSoldOut
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                    decoration:
                        item.isSoldOut ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '+${formatCents(item.priceCents)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
    );
  }
}

/// Control compacto compartido `+ Agregar` / `- 1 +` para Extras, Carta y Paso 2.
class HybridQtyControl extends StatelessWidget {
  const HybridQtyControl({
    super.key,
    required this.quantity,
    required this.onAdd,
    required this.onDecrement,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    if (quantity <= 0) {
      return Material(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 15, color: colors.onPrimaryContainer),
                const SizedBox(width: 3),
                Text(
                  'Agregar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyIconBtn(
            icon: quantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            onTap: onDecrement,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$quantity',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
          ),
          _QtyIconBtn(
            icon: Icons.add_rounded,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _QtyIconBtn extends StatelessWidget {
  const _QtyIconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: colors.primary),
      ),
    );
  }
}
