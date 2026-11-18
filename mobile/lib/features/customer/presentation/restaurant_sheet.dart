import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';

/// C3 · Ficha del local: menú del día y preorden. Se muestra como hoja.
class RestaurantSheet extends ConsumerStatefulWidget {
  final String restaurantId;

  const RestaurantSheet({super.key, required this.restaurantId});

  @override
  ConsumerState<RestaurantSheet> createState() => _RestaurantSheetState();
}

class _RestaurantSheetState extends ConsumerState<RestaurantSheet> {
  String? _soupId;
  String? _mainId;
  String? _breakfastId;
  bool _breakfastMode = false;
  bool _takeaway = false;
  bool _sending = false;
  String _selectedArrival = 'En 15 min';
  String? _customArrival;

  List<String> _availableArrivalOptions() {
    final now = EcuadorTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    return [
      'En 15 min',
      if (nowMinutes < 12 * 60 + 30) '12:30',
      if (nowMinutes < 13 * 60) '13:00',
    ];
  }

  (TimeOfDay, TimeOfDay) _parseLunchRange(String schedule) {
    final matches = RegExp(r'(\d{1,2}):(\d{2})').allMatches(schedule).toList();
    if (matches.length >= 2) {
      final sh = int.tryParse(matches[0].group(1)!) ?? 11;
      final sm = int.tryParse(matches[0].group(2)!) ?? 30;
      final eh = int.tryParse(matches[1].group(1)!) ?? 15;
      final em = int.tryParse(matches[1].group(2)!) ?? 30;
      return (TimeOfDay(hour: sh, minute: sm), TimeOfDay(hour: eh, minute: em));
    }
    return (const TimeOfDay(hour: 11, minute: 30), const TimeOfDay(hour: 15, minute: 30));
  }

  Future<void> _pickCustomTime(Restaurant r) async {
    final (start, end) = _parseLunchRange(r.schedule);
    final initial = TimeOfDay(
      hour: start.hour < 12 ? 12 : start.hour,
      minute: 30,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Hora estimada (${r.schedule})',
    );
    if (picked == null || !mounted) return;
    final pickedMins = picked.hour * 60 + picked.minute;
    final startMins = start.hour * 60 + start.minute;
    final endMins = end.hour * 60 + end.minute;
    if (pickedMins < startMins || pickedMins > endMins) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Elige una hora dentro del horario de atención (${r.schedule}).'),
        ),
      );
      return;
    }
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _customArrival = formatted;
      _selectedArrival = formatted;
    });
  }

  void _applyDefaults(Restaurant r) {
    if (_soupId == null || r.soups.any((m) => m.id == _soupId && m.isSoldOut)) {
      _soupId = r.soups.where((m) => !m.isSoldOut).firstOrNull?.id;
    }
    if (_mainId == null || r.mains.any((m) => m.id == _mainId && m.isSoldOut)) {
      _mainId = r.mains.where((m) => !m.isSoldOut).firstOrNull?.id;
    }
    if (_breakfastId == null ||
        r.breakfasts.any((m) => m.id == _breakfastId && m.isSoldOut)) {
      _breakfastId = r.breakfasts.where((m) => !m.isSoldOut).firstOrNull?.id;
    }
    final options = _availableArrivalOptions();
    if (_selectedArrival != _customArrival && !options.contains(_selectedArrival)) {
      _selectedArrival = 'En 15 min';
    }
  }

  Future<void> _order(CustomerController controller, Restaurant r) async {
    setState(() => _sending = true);
    final ok = await controller.preorder(
      restaurant: r,
      soupId: _breakfastMode ? null : _soupId,
      mainId: _breakfastMode ? null : _mainId,
      breakfastId: _breakfastMode ? _breakfastId : null,
      takeaway: _takeaway,
      estimatedArrival: _selectedArrival,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      context.pop();
      return;
    }
    final error = controller.lastActionError;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _openTable() {
    final router = GoRouter.of(context);
    router.pop();
    router.push('/customer/mesa?restaurantId=${widget.restaurantId}');
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final detail = ref.watch(restaurantDetailProvider(widget.restaurantId));

    return SizedBox(
      height: height,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final s = controller.state;
          final cached = s.restaurantById(widget.restaurantId);
          final loaded = detail.value;
          if (loaded != null) return _content(controller, s, loaded);
          if (cached != null && cached.hasMenu) {
            return _content(controller, s, cached);
          }

          return detail.when(
            loading: () => const _CenteredStatus(
              text: 'Cargando menú del día',
              loading: true,
            ),
            error: (_, _) => cached != null
                ? _content(controller, s, cached)
                : _ErrorMenu(
                    onRetry: () => ref.invalidate(
                      restaurantDetailProvider(widget.restaurantId),
                    ),
                  ),
            data: (r) => r != null
                ? _content(controller, s, r)
                : (cached != null
                      ? _content(controller, s, cached)
                      : const _CenteredStatus(text: 'Sin menú publicado hoy')),
          );
        },
      ),
    );
  }

  Widget _content(
    CustomerController controller,
    CustomerUiState s,
    Restaurant r,
  ) {
    _applyDefaults(r);
    final colors = context.colorScheme;
    final hasBreakfasts = r.breakfasts.isNotEmpty;
    final breakfastMode = hasBreakfasts && _breakfastMode;
    final hasActiveOrder = s.activeOrder != null;
    final chosenBreakfast = r.breakfasts
        .where((b) => b.id == _breakfastId && !b.isSoldOut)
        .firstOrNull;
    final menuSoldOutAll = breakfastMode
        ? r.breakfasts.every((b) => b.isSoldOut)
        : r.isMenuSoldOutToday;
    final canOrder =
        !hasActiveOrder &&
        !_sending &&
        r.hasMenu &&
        !menuSoldOutAll &&
        (!breakfastMode || chosenBreakfast != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (s.isOffline) ...[
                Center(
                  child: Text(
                    'Sin conexión · Menú guardado',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _HeaderCard(
                restaurant: r,
                occupancy: ref.watch(restaurantOccupancyProvider(r.id)),
                hasPlanHere: s.passFor(r.id) != null || r.hasPlan,
                onTable: _openTable,
              ),
              const SizedBox(height: 16),
              if (!r.hasMenu)
                const _CenteredStatus(text: 'Sin menú publicado hoy')
              else ...[
                if (hasBreakfasts) ...[
                  _ModeTabs(
                    breakfast: breakfastMode,
                    onChanged: (v) => setState(() => _breakfastMode = v),
                  ),
                  const SizedBox(height: 16),
                ],
                if (breakfastMode) ...[
                  const SectionLabel('Desayuno a elegir'),
                  const SizedBox(height: 8),
                  for (final b in r.breakfasts)
                    _OptionTile(
                      item: b,
                      selected: b.id == _breakfastId,
                      onTap: () => setState(() => _breakfastId = b.id),
                    ),
                ] else ...[
                  const SectionLabel('Sopa del día'),
                  const SizedBox(height: 8),
                  for (final soup in r.soups)
                    _OptionTile(
                      item: soup,
                      selected: soup.id == _soupId,
                      onTap: () => setState(() => _soupId = soup.id),
                    ),
                  const SizedBox(height: 8),
                  const SectionLabel('Segundo a elegir'),
                  const SizedBox(height: 8),
                  for (final main in r.mains)
                    _OptionTile(
                      item: main,
                      selected: main.id == _mainId,
                      showPhoto: true,
                      onTap: () => setState(() => _mainId = main.id),
                    ),
                  const SizedBox(height: 8),
                  _IncludedBox(juice: r.juice, dessert: r.dessert),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        label: 'Para comer aquí',
                        icon: Icons.restaurant_rounded,
                        selected: !_takeaway,
                        onTap: () => setState(() => _takeaway = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ChoiceButton(
                        label:
                            'Para llevar (+ ${formatMoney(r.takeawaySurcharge)})',
                        icon: Icons.takeout_dining_outlined,
                        selected: _takeaway,
                        onTap: () => setState(() => _takeaway = true),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (r.hasMenu)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hora estimada de consumo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final opt in _availableArrivalOptions())
                      ChoiceChip(
                        label: Text(opt),
                        selected: _selectedArrival == opt,
                        onSelected: (_) => setState(() => _selectedArrival = opt),
                      ),
                    ChoiceChip(
                      label: Text(_customArrival ?? '+'),
                      selected: _customArrival != null &&
                          _selectedArrival == _customArrival,
                      onSelected: (_) => _pickCustomTime(r),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final activePass = s.passFor(r.id);
                    final hasPlanHere = activePass != null &&
                        activePass.remainingLunches > 0 &&
                        !activePass.isExpired;
                    final baseCents = breakfastMode
                        ? Money.toCents(chosenBreakfast?.price ?? r.singleLunchPrice)
                        : Money.toCents(r.singleLunchPrice);
                    final surchargeCents =
                        _takeaway ? Money.toCents(r.takeawaySurcharge) : 0;
                    final totalCents =
                        hasPlanHere ? 0 : baseCents + surchargeCents;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasPlanHere) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: context.bocadooColors.successContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 16,
                                  color: context.bocadooColors.success,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Cubierto por tu Plan (Quedan ${activePass.remainingLunches} almuerzos)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: context.bocadooColors.success,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        ElevatedButton(
                          onPressed:
                              canOrder ? () => _order(controller, r) : null,
                          child: Text(
                            menuSoldOutAll
                                ? 'Menú agotado por hoy'
                                : breakfastMode
                                    ? (hasPlanHere
                                        ? 'Preordenar desayuno con Plan (\$0,00)'
                                        : 'Preordenar desayuno · ${formatCents(totalCents)}')
                                    : (hasPlanHere
                                        ? 'Preordenar almuerzo con Plan (\$0,00)'
                                        : 'Preordenar almuerzo · ${formatCents(totalCents)}'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (hasActiveOrder) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Límite: tienes una orden activa pendiente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.bocadooColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Restaurant restaurant;
  final String occupancy;
  final bool hasPlanHere;
  final VoidCallback onTable;

  const _HeaderCard({
    required this.restaurant,
    required this.occupancy,
    required this.hasPlanHere,
    required this.onTable,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final r = restaurant;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 112,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverImage(
                  url: r.imageUrl.isNotEmpty ? r.imageUrl : r.logoUrl,
                  name: r.name,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [
                        colors.scrim.withValues(alpha: 0.6),
                        colors.scrim.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Row(
                    children: [
                      Flexible(child: OccupancyDetail(occupancy: occupancy)),
                      if (r.hasLocation) ...[
                        const SizedBox(width: 6),
                        DistancePill(
                          text: r.formattedDistance,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
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
                  label: 'Armar mesa',
                  icon: Icons.group_outlined,
                  onPressed: onTable,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  final bool breakfast;
  final ValueChanged<bool> onChanged;

  const _ModeTabs({required this.breakfast, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    Widget tab(String label, IconData icon, bool value) {
      final selected = breakfast == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? colors.surface : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          tab('Almuerzo del día', Icons.soup_kitchen_outlined, false),
          tab('Desayunos de hoy', Icons.wb_sunny_outlined, true),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final MenuItem item;
  final bool selected;
  final bool showPhoto;
  final VoidCallback onTap;

  const _OptionTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.showPhoto = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final soldOut = item.isSoldOut;
    final active = selected && !soldOut;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active
            ? colors.primaryContainer
            : Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: active ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: soldOut ? null : onTap,
          child: Padding(
            padding: EdgeInsets.all(
              showPhoto && item.imageUrl != null ? 10 : 14,
            ),
            child: Row(
              children: [
                if (showPhoto && item.imageUrl != null) ...[
                  Opacity(
                    opacity: soldOut ? 0.5 : 1,
                    child: CoverImage(
                      url: item.imageUrl,
                      name: item.name,
                      width: 44,
                      height: 44,
                      radius: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Opacity(
                    opacity: soldOut ? 0.6 : 1,
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
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
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: b.successContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Veggie',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: b.success,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (item.price != null)
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
                const SizedBox(width: 8),
                if (soldOut)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: b.dangerContainer,
                      borderRadius: BorderRadius.circular(
                        AppTheme.buttonRadius,
                      ),
                    ),
                    child: Text(
                      'Agotado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: b.onDangerContainer,
                      ),
                    ),
                  )
                else if (active)
                  Icon(Icons.check_rounded, size: 18, color: colors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IncludedBox extends StatelessWidget {
  final String juice;
  final String dessert;

  const _IncludedBox({required this.juice, required this.dessert});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    Widget line(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Almuerzo completo incluye:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          if (juice.isNotEmpty) line(Icons.local_drink_outlined, 'Jugo', juice),
          if (dessert.isNotEmpty)
            line(Icons.icecream_outlined, 'Postre', dessert),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  final String text;
  final bool loading;

  const _CenteredStatus({required this.text, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const CircularProgressIndicator()
          else
            Icon(
              Icons.restaurant_rounded,
              size: 40,
              color: colors.onSurfaceVariant,
            ),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorMenu extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorMenu({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return CustomerErrorView(
      title: 'Error al cargar menú',
      message: 'No pudimos cargar el menú del día.',
      onRetry: onRetry,
    );
  }
}
