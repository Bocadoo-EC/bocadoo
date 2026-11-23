import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../group_order_models.dart';

/// Selector del menú diario en acordeón con radio buttons.
///
/// Categorías: Sopa (+ "Sin sopa"), Segundo / Opción Fit, Bebida
/// (+ "Sin bebida") y Postre (solo si el restaurante publicó postres).
/// Al elegir una opción la categoría se colapsa sola a los 200 ms; tocar la
/// cabecera permite reabrirla y cambiar la elección.
///
/// Los colores salen del tema (claro/oscuro), sin valores hardcodeados.
class DailyMenuAccordionSelector extends StatefulWidget {
  const DailyMenuAccordionSelector({
    super.key,
    required this.dailyMenu,
    required this.selection,
    required this.onChanged,
    this.enabled = true,
    this.flashMode = false,
    this.soupPriceLabel,
    this.mainPriceLabel,
    this.drinkPriceLabel,
    this.dessertPriceLabel,
  });

  final DailyMenu dailyMenu;
  final GroupOrderDishSelection selection;
  final ValueChanged<GroupOrderDishSelection> onChanged;
  final bool enabled;

  /// Oferta flash del Dueño: sopa y segundo son los principales (hay que elegir
  /// al menos uno), con "Sin segundo" / "Sin postre"; bebida y postre opcionales.
  final bool flashMode;
  final String? soupPriceLabel;
  final String? mainPriceLabel;
  final String? drinkPriceLabel;
  final String? dessertPriceLabel;

  @override
  State<DailyMenuAccordionSelector> createState() =>
      _DailyMenuAccordionSelectorState();
}

enum _Section { soup, main, drink, dessert }

class _Option {
  const _Option(this.value, {this.tag});

  final String value;
  final String? tag;
}

class _DailyMenuAccordionSelectorState
    extends State<DailyMenuAccordionSelector> {
  static const _collapseDelay = Duration(milliseconds: 200);
  static const _animation = Duration(milliseconds: 200);

  final Set<_Section> _expanded = {};
  final Map<_Section, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    // Abre la primera categoría requerida que aún no tiene elección.
    for (final s in _visibleSections) {
      if (_isRequired(s) && _selectedOf(s) == null) {
        _expanded.add(s);
        break;
      }
    }
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  DailyMenu get _menu => widget.dailyMenu;

  List<_Section> get _visibleSections => [
        if (_menu.soups.isNotEmpty) _Section.soup,
        if (_menu.mains.isNotEmpty) _Section.main,
        if (_menu.drinks.isNotEmpty) _Section.drink,
        // Sin postres publicados no se renderiza ni bloquea el avance.
        if (_menu.desserts.isNotEmpty) _Section.dessert,
      ];

  bool _isRequired(_Section s) => widget.flashMode
      ? (s == _Section.soup || s == _Section.main)
      : s != _Section.dessert;

  String _badgeOf(_Section s) => widget.flashMode
      ? (_isRequired(s) ? 'Principal' : 'Opcional')
      : (_isRequired(s) ? 'Requerido' : 'Opcional');

  String _titleOf(_Section s) => switch (s) {
        _Section.soup => '1. Sopa',
        _Section.main =>
          widget.flashMode ? '2. Segundo' : '2. Segundo / Opción Fit',
        _Section.drink => '3. Bebida',
        _Section.dessert => '4. Postre',
      };

  String _hintOf(_Section s) =>
      _isRequired(s) ? 'Elige 1' : 'Elige 1 (opcional)';

  String? _selectedOf(_Section s) => switch (s) {
        _Section.soup => widget.selection.soup,
        _Section.main => widget.selection.main,
        _Section.drink => widget.selection.drink,
        _Section.dessert => widget.selection.dessert,
      };

  List<_Option> _optionsOf(_Section s) => switch (s) {
        _Section.soup => [
            for (final o in _menu.soups) _Option(o),
            const _Option(kNoSoupOption),
          ],
        _Section.main => [
            for (final o in _menu.mains) _Option(o, tag: _menu.mainTags[o]),
            if (widget.flashMode) const _Option(kNoMainOption),
          ],
        _Section.drink => [
            for (final o in _menu.drinks) _Option(o),
            const _Option(kNoDrinkOption),
          ],
        _Section.dessert => [
            for (final o in _menu.desserts) _Option(o),
            if (widget.flashMode) const _Option(kNoDessertOption),
          ],
      };

  void _toggle(_Section s) {
    if (!widget.enabled) return;
    _timers.remove(s)?.cancel();
    setState(() {
      if (!_expanded.remove(s)) _expanded.add(s);
    });
  }

  void _pick(_Section s, String value) {
    if (!widget.enabled) return;
    final sel = widget.selection;
    final next = switch (s) {
      _Section.soup => sel.copyWith(soup: value),
      _Section.main => sel.copyWith(main: value),
      _Section.drink => sel.copyWith(drink: value),
      // El postre es opcional: tocar de nuevo la opción elegida la quita.
      _Section.dessert => sel.dessert == value && !widget.flashMode
          ? sel.copyWith(clearDessert: true)
          : sel.copyWith(dessert: value),
    };
    widget.onChanged(next);

    _timers.remove(s)?.cancel();
    _timers[s] = Timer(_collapseDelay, () {
      if (!mounted) return;
      setState(() => _expanded.remove(s));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final sections = _visibleSections;

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
            if (i > 0) _divider(colors),
            _buildSection(context, sections[i]),
          ],
        ],
      ),
    );
  }

  Widget _divider(ColorScheme colors) =>
      Divider(height: 1, thickness: 1, color: colors.outlineVariant);

  String? _priceLabelOf(_Section s) => switch (s) {
        _Section.soup => widget.soupPriceLabel,
        _Section.main => widget.mainPriceLabel,
        _Section.drink => widget.drinkPriceLabel,
        _Section.dessert => widget.dessertPriceLabel,
      };

  Widget _buildSection(BuildContext context, _Section s) {
    final colors = context.colorScheme;
    final expanded = _expanded.contains(s);
    final selected = _selectedOf(s);
    final options = _optionsOf(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: _titleOf(s),
          priceLabel: _priceLabelOf(s),
          hint: _hintOf(s),
          selectedLabel: selected,
          badge: _badgeOf(s),
          expanded: expanded,
          onTap: widget.enabled ? () => _toggle(s) : null,
        ),
        AnimatedSize(
          duration: _animation,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final o in options) ...[
                      _divider(colors),
                      _OptionRow(
                        label: o.value,
                        tag: o.tag,
                        selected: selected == o.value,
                        onTap: widget.enabled ? () => _pick(s, o.value) : null,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.priceLabel,
    required this.hint,
    required this.selectedLabel,
    required this.badge,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String? priceLabel;
  final String hint;
  final String? selectedLabel;
  final String badge;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    // Colapsada con elección → muestra el plato elegido en color de marca.
    final showSelection = !expanded && selectedLabel != null;
    final displayTitle = (priceLabel != null && priceLabel!.isNotEmpty)
        ? '$title · $priceLabel'
        : title;

    return Semantics(
      button: true,
      expanded: expanded,
      label: '$displayTitle, $badge',
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
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showSelection ? selectedLabel! : hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            showSelection ? FontWeight.w600 : FontWeight.w400,
                        color: showSelection
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RequirementBadge(label: badge),
              const SizedBox(width: 2),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
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

class _RequirementBadge extends StatelessWidget {
  const _RequirementBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tag,
  });

  final String label;
  final String? tag;
  final bool selected;
  final VoidCallback? onTap;

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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
                      if (tag != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tag!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
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
