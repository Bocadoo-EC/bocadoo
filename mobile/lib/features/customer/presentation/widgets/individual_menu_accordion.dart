import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';

/// Identificador sentinela cuando el usuario elige no llevar sopa.
const kIndividualNoSoupId = '__no_soup__';

enum _AccordionSection { soup, main, drink, dessert, breakfast }

/// Acordeón secuencial auto-colapsable para el pedido individual del comensal.
///
/// Replica el patrón de Pedido Grupal:
/// - Al elegir una opción `Requerido`, colapsa la sección tras 200 ms, muestra
///   el plato elegido con check morado en la cabecera y abre la siguiente
///   sección pendiente.
/// - Si bebida o postre son fijos, se muestran colapsados con badge `Incluido`.
class IndividualMenuAccordion extends StatefulWidget {
  const IndividualMenuAccordion({
    super.key,
    required this.restaurant,
    required this.breakfastMode,
    required this.soupId,
    required this.mainId,
    required this.breakfastId,
    required this.selectedDrink,
    required this.selectedDessert,
    required this.onSelectSoup,
    required this.onSelectMain,
    required this.onSelectBreakfast,
    required this.onSelectDrink,
    required this.onSelectDessert,
  });

  final Restaurant restaurant;
  final bool breakfastMode;
  final String? soupId;
  final String? mainId;
  final String? breakfastId;
  final String? selectedDrink;
  final String? selectedDessert;
  final ValueChanged<String> onSelectSoup;
  final ValueChanged<String> onSelectMain;
  final ValueChanged<String> onSelectBreakfast;
  final ValueChanged<String> onSelectDrink;
  final ValueChanged<String> onSelectDessert;

  @override
  State<IndividualMenuAccordion> createState() => _IndividualMenuAccordionState();
}

class _IndividualMenuAccordionState extends State<IndividualMenuAccordion> {
  static const _collapseDelay = Duration(milliseconds: 200);
  static const _animation = Duration(milliseconds: 200);

  final Set<_AccordionSection> _expanded = {};
  final Map<_AccordionSection, Timer> _timers = {};

  List<MenuItem> get _soups => widget.restaurant.soups;
  List<MenuItem> get _mains => widget.restaurant.mains;
  List<MenuItem> get _breakfasts => widget.restaurant.breakfasts;

  List<MenuItem> get _drinks => widget.restaurant.todayMenu
      .where((m) => m.category == 'Bebida' && !m.isSoldOut)
      .toList();

  List<MenuItem> get _desserts => widget.restaurant.todayMenu
      .where((m) => m.category == 'Postre' && !m.isSoldOut)
      .toList();

  bool get _hasDrinkSection =>
      _drinks.isNotEmpty || widget.restaurant.juice.trim().isNotEmpty;

  bool get _hasDessertSection =>
      _desserts.isNotEmpty || widget.restaurant.dessert.trim().isNotEmpty;

  bool get _isDrinkSelectable => _drinks.length > 1;
  bool get _isDessertSelectable => _desserts.length > 1;

  List<_AccordionSection> get _visibleSections {
    if (widget.breakfastMode) {
      return [if (_breakfasts.isNotEmpty) _AccordionSection.breakfast];
    }
    return [
      if (_soups.isNotEmpty) _AccordionSection.soup,
      if (_mains.isNotEmpty) _AccordionSection.main,
      if (_hasDrinkSection) _AccordionSection.drink,
      if (_hasDessertSection) _AccordionSection.dessert,
    ];
  }

  bool _isSectionRequired(_AccordionSection s) => switch (s) {
        _AccordionSection.soup => _soups.isNotEmpty,
        _AccordionSection.main => _mains.isNotEmpty,
        _AccordionSection.drink => _isDrinkSelectable,
        _AccordionSection.dessert => false,
        _AccordionSection.breakfast => _breakfasts.isNotEmpty,
      };

  bool _isSectionSelectable(_AccordionSection s) => switch (s) {
        _AccordionSection.soup => true,
        _AccordionSection.main => true,
        _AccordionSection.drink => _isDrinkSelectable,
        _AccordionSection.dessert => _isDessertSelectable,
        _AccordionSection.breakfast => true,
      };

  String? _selectedLabelOf(_AccordionSection s) {
    switch (s) {
      case _AccordionSection.soup:
        if (widget.soupId == null) return null;
        if (widget.soupId == kIndividualNoSoupId) return 'Sin sopa';
        return _soups.where((m) => m.id == widget.soupId).firstOrNull?.name;
      case _AccordionSection.main:
        if (widget.mainId == null) return null;
        return _mains.where((m) => m.id == widget.mainId).firstOrNull?.name;
      case _AccordionSection.drink:
        if (_isDrinkSelectable) return widget.selectedDrink;
        return _drinks.firstOrNull?.name ?? widget.restaurant.juice.trim();
      case _AccordionSection.dessert:
        if (_isDessertSelectable) return widget.selectedDessert;
        return _desserts.firstOrNull?.name ?? widget.restaurant.dessert.trim();
      case _AccordionSection.breakfast:
        if (widget.breakfastId == null) return null;
        return _breakfasts
            .where((m) => m.id == widget.breakfastId)
            .firstOrNull
            ?.name;
    }
  }

  @override
  void initState() {
    super.initState();
    _expandFirstPending();
  }

  @override
  void didUpdateWidget(covariant IndividualMenuAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.breakfastMode != widget.breakfastMode ||
        oldWidget.restaurant.id != widget.restaurant.id) {
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
      _expanded.clear();
      _expandFirstPending();
    }
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _expandFirstPending() {
    for (final s in _visibleSections) {
      if (_isSectionRequired(s) && _selectedLabelOf(s) == null) {
        _expanded.add(s);
        return;
      }
    }
  }

  String _titleOf(_AccordionSection s) {
    switch (s) {
      case _AccordionSection.soup:
        return '1. Sopa';
      case _AccordionSection.main:
        return _soups.isEmpty ? '1. Segundo / Opción Fit' : '2. Segundo / Opción Fit';
      case _AccordionSection.drink:
        final idx = (_soups.isEmpty ? 0 : 1) + (_mains.isEmpty ? 0 : 1) + 1;
        return '$idx. Bebida';
      case _AccordionSection.dessert:
        final idx = (_soups.isEmpty ? 0 : 1) +
            (_mains.isEmpty ? 0 : 1) +
            (_hasDrinkSection ? 1 : 0) +
            1;
        return '$idx. Postre';
      case _AccordionSection.breakfast:
        return '1. Desayuno a elegir';
    }
  }

  String _badgeOf(_AccordionSection s) {
    if (!_isSectionSelectable(s)) return 'Incluido';
    return _isSectionRequired(s) ? 'Requerido' : 'Opcional';
  }

  String _hintOf(_AccordionSection s) =>
      _isSectionRequired(s) ? 'Elige 1' : 'Elige 1 (opcional)';

  void _toggle(_AccordionSection s) {
    if (!_isSectionSelectable(s)) return;
    _timers.remove(s)?.cancel();
    setState(() {
      if (!_expanded.remove(s)) _expanded.add(s);
    });
  }

  void _handlePick(_AccordionSection s, String idOrLabel) {
    switch (s) {
      case _AccordionSection.soup:
        widget.onSelectSoup(idOrLabel);
      case _AccordionSection.main:
        widget.onSelectMain(idOrLabel);
      case _AccordionSection.drink:
        widget.onSelectDrink(idOrLabel);
      case _AccordionSection.dessert:
        widget.onSelectDessert(idOrLabel);
      case _AccordionSection.breakfast:
        widget.onSelectBreakfast(idOrLabel);
    }

    _timers.remove(s)?.cancel();
    _timers[s] = Timer(_collapseDelay, () {
      if (!mounted) return;
      setState(() {
        _expanded.remove(s);
        final sections = _visibleSections;
        final currentIndex = sections.indexOf(s);
        for (var i = currentIndex + 1; i < sections.length; i++) {
          final next = sections[i];
          if (_isSectionSelectable(next) &&
              _isSectionRequired(next) &&
              _selectedLabelOf(next) == null) {
            _expanded.add(next);
            break;
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final sections = _visibleSections;
    if (sections.isEmpty) return const SizedBox.shrink();

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
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: colors.outlineVariant),
            _buildSection(context, sections[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, _AccordionSection s) {
    final colors = context.colorScheme;
    final selectable = _isSectionSelectable(s);
    final expanded = selectable && _expanded.contains(s);
    final selectedLabel = _selectedLabelOf(s);
    final badge = _badgeOf(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccordionHeader(
          title: _titleOf(s),
          hint: _hintOf(s),
          selectedLabel: selectedLabel,
          badge: badge,
          selectable: selectable,
          expanded: expanded,
          onTap: selectable ? () => _toggle(s) : null,
        ),
        if (selectable)
          AnimatedSize(
            duration: _animation,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildRows(context, colors, s),
                  )
                : const SizedBox(width: double.infinity),
          ),
      ],
    );
  }

  List<Widget> _buildRows(
    BuildContext context,
    ColorScheme colors,
    _AccordionSection s,
  ) {
    final divider = Divider(height: 1, thickness: 1, color: colors.outlineVariant);
    switch (s) {
      case _AccordionSection.soup:
        return [
          for (final soup in _soups) ...[
            divider,
            _MenuRadioRow(
              item: soup,
              selected: widget.soupId == soup.id,
              onTap: soup.isSoldOut ? null : () => _handlePick(s, soup.id),
            ),
          ],
          divider,
          _PlainRadioRow(
            label: 'Sin sopa',
            selected: widget.soupId == kIndividualNoSoupId,
            onTap: () => _handlePick(s, kIndividualNoSoupId),
          ),
        ];
      case _AccordionSection.main:
        return [
          for (final main in _mains) ...[
            divider,
            _MenuRadioRow(
              item: main,
              showPhoto: true,
              selected: widget.mainId == main.id,
              onTap: main.isSoldOut ? null : () => _handlePick(s, main.id),
            ),
          ],
        ];
      case _AccordionSection.drink:
        return [
          for (final d in _drinks) ...[
            divider,
            _PlainRadioRow(
              label: d.name,
              selected: widget.selectedDrink == d.name,
              onTap: () => _handlePick(s, d.name),
            ),
          ],
        ];
      case _AccordionSection.dessert:
        return [
          for (final d in _desserts) ...[
            divider,
            _PlainRadioRow(
              label: d.name,
              selected: widget.selectedDessert == d.name,
              onTap: () => _handlePick(s, d.name),
            ),
          ],
        ];
      case _AccordionSection.breakfast:
        return [
          for (final b in _breakfasts) ...[
            divider,
            _MenuRadioRow(
              item: b,
              showPrice: true,
              selected: widget.breakfastId == b.id,
              onTap: b.isSoldOut ? null : () => _handlePick(s, b.id),
            ),
          ],
        ];
    }
  }
}

class _AccordionHeader extends StatelessWidget {
  const _AccordionHeader({
    required this.title,
    required this.hint,
    required this.selectedLabel,
    required this.badge,
    required this.selectable,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String hint;
  final String? selectedLabel;
  final String badge;
  final bool selectable;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final showCheck = !expanded && selectedLabel != null && selectedLabel!.isNotEmpty;

    return Semantics(
      button: selectable,
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: selectable
                      ? colors.surfaceContainerHighest
                      : colors.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selectable ? colors.onSurface : colors.onPrimaryContainer,
                  ),
                ),
              ),
              if (selectable) ...[
                const SizedBox(width: 2),
                Icon(
                  expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 24,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRadioRow extends StatelessWidget {
  const _MenuRadioRow({
    required this.item,
    required this.selected,
    required this.onTap,
    this.showPhoto = false,
    this.showPrice = false,
  });

  final MenuItem item;
  final bool selected;
  final bool showPhoto;
  final bool showPrice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final soldOut = item.isSoldOut;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected && !soldOut,
      label: item.name,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showPhoto && item.imageUrl != null) ...[
                  Opacity(
                    opacity: soldOut ? 0.45 : 1,
                    child: CoverImage(
                      url: item.imageUrl,
                      name: item.name,
                      width: 40,
                      height: 40,
                      radius: 10,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Opacity(
                    opacity: soldOut ? 0.55 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      selected ? FontWeight.w600 : FontWeight.w400,
                                  color: colors.onSurface,
                                  decoration: soldOut
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (item.isVeggie &&
                                item.category == 'Plato Fuerte') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: b.successContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Veggie',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: b.success,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (showPrice && item.price != null)
                          Text(
                            formatMoney(item.price!),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (soldOut)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                  _RadioDot(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainRadioRow extends StatelessWidget {
  const _PlainRadioRow({
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
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _RadioDot(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final ring = selected ? colors.primary : colors.onSurfaceVariant;

    return AnimatedContainer(
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
        decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
      ),
    );
  }
}
