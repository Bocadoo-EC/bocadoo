import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';
import 'widgets/individual_menu_accordion.dart';
import 'widgets/restaurant_preorder_widgets.dart';

/// C3 · Ficha del local: flujo progresivo en 2 pasos (1: acordeón de platos,
/// 2: modalidad de consumo y hora estimada).
class RestaurantSheet extends ConsumerStatefulWidget {
  final String restaurantId;

  const RestaurantSheet({super.key, required this.restaurantId});

  @override
  ConsumerState<RestaurantSheet> createState() => _RestaurantSheetState();
}

class _RestaurantSheetState extends ConsumerState<RestaurantSheet> {
  IndividualPreorderState _draft = const IndividualPreorderState();
  bool _sending = false;

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
    return (
      const TimeOfDay(hour: 11, minute: 30),
      const TimeOfDay(hour: 15, minute: 30),
    );
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
          content: Text(
            'Elige una hora dentro del horario de atención (${r.schedule}).',
          ),
        ),
      );
      return;
    }
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _draft = _draft.copyWith(
        customArrival: formatted,
        selectedArrival: formatted,
      );
    });
  }

  String _resolveArrivalHhmm(IndividualPreorderState draft) {
    if (draft.selectedArrival != 'En 15 min') return draft.selectedArrival;
    final target = EcuadorTime.now().add(const Duration(minutes: 15));
    final hh = target.hour.toString().padLeft(2, '0');
    final mm = target.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _order(
    CustomerController controller,
    Restaurant r,
    IndividualPreorderState draft,
  ) async {
    setState(() => _sending = true);
    final resolvedSoupId =
        draft.soupId == kIndividualNoSoupId ? null : draft.soupId;
    final ok = await controller.preorder(
      restaurant: r,
      soupId: draft.breakfastMode ? null : resolvedSoupId,
      mainId: draft.breakfastMode ? null : draft.mainId,
      breakfastId: draft.breakfastMode ? draft.breakfastId : null,
      // Salón lleno: el pedido siempre es para llevar.
      takeaway: draft.takeaway ||
          ref.read(restaurantPublicStatusProvider(r.id)).isFull,
      estimatedArrival: _resolveArrivalHhmm(draft),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      context.pop();
      return;
    }
    final error = controller.lastActionError;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
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
    final colors = context.colorScheme;
    final arrivalOptions = _availableArrivalOptions();
    final draft = _draft.sanitizeFor(r, arrivalOptions);
    final hasBreakfasts = r.breakfasts.isNotEmpty;
    final breakfastMode = hasBreakfasts && draft.breakfastMode;
    final hasActiveOrder = s.activeOrder != null;
    final chosenBreakfast = r.breakfasts
        .where((b) => b.id == draft.breakfastId && !b.isSoldOut)
        .firstOrNull;
    final publicStatus = ref.watch(restaurantPublicStatusProvider(r.id));
    // Lleno = solo para llevar: se fuerza la modalidad y se bloquea "comer aquí".
    final forceTakeaway = publicStatus.isFull;
    final takeaway = forceTakeaway || draft.takeaway;
    final isClosed = publicStatus.isClosed;
    final menuSoldOutAll = publicStatus.isSoldOutToday ||
        (breakfastMode
            ? r.breakfasts.every((b) => b.isSoldOut)
            : r.isMenuSoldOutToday);

    final activePass = s.passFor(r.id);
    final hasPlanHere = activePass != null &&
        activePass.remainingLunches > 0 &&
        !activePass.isExpired;
    final baseCents = breakfastMode
        ? Money.toCents(chosenBreakfast?.price ?? r.singleLunchPrice)
        : Money.toCents(r.singleLunchPrice);
    final surchargeCents = takeaway ? Money.toCents(r.takeawaySurcharge) : 0;
    final totalCents = hasPlanHere ? 0 : baseCents + surchargeCents;

    final step1Ready = draft.isStepOneComplete(r);
    final canContinue = !isClosed &&
        !hasActiveOrder &&
        !_sending &&
        r.hasMenu &&
        !menuSoldOutAll &&
        step1Ready;
    final canOrder = canContinue && draft.step == 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PreorderModalHeader(
          restaurantName: r.name,
          step: draft.step,
          totalSteps: 2,
          subtitle: draft.step == 1 ? 'Arma tu almuerzo' : 'Modalidad y hora',
          onBack: draft.step == 2 && !_sending
              ? () => setState(() => _draft = draft.copyWith(step: 1))
              : null,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              );
            },
            child: draft.step == 1
                ? _buildStepOne(
                    s: s,
                    r: r,
                    draft: draft,
                    publicStatus: publicStatus,
                    hasPlanHere: hasPlanHere || r.hasPlan,
                    hasBreakfasts: hasBreakfasts,
                    breakfastMode: breakfastMode,
                    isClosed: isClosed,
                  )
                : _buildStepTwo(
                    colors: colors,
                    r: r,
                    draft: draft,
                    arrivalOptions: arrivalOptions,
                    forceTakeaway: forceTakeaway,
                    takeaway: takeaway,
                  ),
          ),
        ),
        if (r.hasMenu)
          _buildBottomBar(
            colors: colors,
            r: r,
            draft: draft,
            controller: controller,
            isClosed: isClosed,
            hasActiveOrder: hasActiveOrder,
            menuSoldOutAll: menuSoldOutAll,
            breakfastMode: breakfastMode,
            hasPlanHere: hasPlanHere,
            remainingLunches: activePass?.remainingLunches ?? 0,
            baseCents: baseCents,
            totalCents: totalCents,
            canContinue: canContinue,
            canOrder: canOrder,
          ),
      ],
    );
  }

  Widget _buildStepOne({
    required CustomerUiState s,
    required Restaurant r,
    required IndividualPreorderState draft,
    required RestaurantPublicStatus publicStatus,
    required bool hasPlanHere,
    required bool hasBreakfasts,
    required bool breakfastMode,
    required bool isClosed,
  }) {
    final colors = context.colorScheme;
    return ListView(
      key: const ValueKey(1),
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
        CleanRestaurantPlanCard(
          restaurant: r,
          publicStatus: publicStatus,
          hasPlanHere: hasPlanHere,
          onTable: _openTable,
        ),
        const SizedBox(height: 16),
        if (!r.hasMenu)
          _CenteredStatus(
            text: isClosed
                ? 'Este restaurante está cerrado por hoy'
                : 'Sin menú publicado hoy',
          )
        else ...[
          if (hasBreakfasts) ...[
            _ModeTabs(
              breakfast: breakfastMode,
              onChanged: (v) => setState(
                () => _draft = draft.copyWith(breakfastMode: v, step: 1),
              ),
            ),
            const SizedBox(height: 16),
          ],
          IndividualMenuAccordion(
            restaurant: r,
            breakfastMode: breakfastMode,
            soupId: draft.soupId,
            mainId: draft.mainId,
            breakfastId: draft.breakfastId,
            selectedDrink: draft.drinkName,
            selectedDessert: draft.dessertName,
            onSelectSoup: (id) =>
                setState(() => _draft = draft.copyWith(soupId: id)),
            onSelectMain: (id) =>
                setState(() => _draft = draft.copyWith(mainId: id)),
            onSelectBreakfast: (id) =>
                setState(() => _draft = draft.copyWith(breakfastId: id)),
            onSelectDrink: (name) =>
                setState(() => _draft = draft.copyWith(drinkName: name)),
            onSelectDessert: (name) =>
                setState(() => _draft = draft.copyWith(dessertName: name)),
          ),
        ],
      ],
    );
  }

  Widget _buildStepTwo({
    required ColorScheme colors,
    required Restaurant r,
    required IndividualPreorderState draft,
    required List<String> arrivalOptions,
    required bool forceTakeaway,
    required bool takeaway,
  }) {
    return ListView(
      key: const ValueKey(2),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        SelectedDishSummaryTile(
          summary: draft.summaryLine(r),
          onEdit: () => setState(() => _draft = draft.copyWith(step: 1)),
        ),
        const SizedBox(height: 18),
        if (forceTakeaway) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.bocadooColors.dangerContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: context.bocadooColors.onDangerContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este local tiene el salón lleno por los próximos '
                    'minutos. Puedes ordenar solo para llevar y retirar '
                    'rápido en caja.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.bocadooColors.onDangerContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Modalidad de consumo',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ChoiceButton(
                label: 'Para comer aquí',
                icon: Icons.restaurant_rounded,
                selected: !takeaway,
                onTap: forceTakeaway
                    ? null
                    : () => setState(
                          () => _draft = draft.copyWith(takeaway: false),
                        ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChoiceButton(
                label: 'Para llevar (+${formatMoney(r.takeawaySurcharge)})',
                icon: Icons.takeout_dining_outlined,
                selected: takeaway,
                onTap: () => setState(
                  () => _draft = draft.copyWith(takeaway: true),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Hora estimada de consumo',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final opt in arrivalOptions)
              ChoiceChip(
                label: Text(opt),
                selected: draft.selectedArrival == opt,
                onSelected: (_) => setState(
                  () => _draft = draft.copyWith(selectedArrival: opt),
                ),
              ),
            ChoiceChip(
              label: Text(draft.customArrival ?? '+'),
              selected: draft.customArrival != null &&
                  draft.selectedArrival == draft.customArrival,
              onSelected: (_) => _pickCustomTime(r),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar({
    required ColorScheme colors,
    required Restaurant r,
    required IndividualPreorderState draft,
    required CustomerController controller,
    required bool isClosed,
    required bool hasActiveOrder,
    required bool menuSoldOutAll,
    required bool breakfastMode,
    required bool hasPlanHere,
    required int remainingLunches,
    required int baseCents,
    required int totalCents,
    required bool canContinue,
    required bool canOrder,
  }) {
    final stepOneCtaLabel = hasActiveOrder
        ? 'Ya tienes un pedido en camino'
        : menuSoldOutAll
            ? 'Menú agotado por hoy'
            : hasPlanHere
                ? 'Continuar · Con Plan (\$0,00)'
                : 'Continuar · ${formatCents(baseCents)}';

    final stepTwoCtaLabel = hasActiveOrder
        ? 'Ya tienes un pedido en camino'
        : menuSoldOutAll
            ? 'Menú agotado por hoy'
            : breakfastMode
                ? (hasPlanHere
                    ? 'Preordenar desayuno con Plan (\$0,00)'
                    : 'Preordenar desayuno · ${formatCents(totalCents)}')
                : (hasPlanHere
                    ? 'Preordenar almuerzo con Plan (\$0,00)'
                    : 'Preordenar almuerzo · ${formatCents(totalCents)}');

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: isClosed
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_clock_outlined,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Este restaurante está cerrado por hoy',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (draft.step == 2 && hasPlanHere)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
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
                              'Cubierto por tu Plan (Quedan $remainingLunches almuerzos)',
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
                  if (draft.step == 1)
                    ElevatedButton(
                      onPressed: canContinue
                          ? () => setState(() => _draft = draft.copyWith(step: 2))
                          : null,
                      child: Text(stepOneCtaLabel),
                    )
                  else
                    ElevatedButton(
                      onPressed: canOrder
                          ? () => _order(controller, r, draft)
                          : null,
                      child: _sending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colors.onPrimary,
                              ),
                            )
                          : Text(stepTwoCtaLabel),
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

class _ChoiceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;

  /// `null` deshabilita la opción (opacidad 0.5, no seleccionable).
  final VoidCallback? onTap;

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
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
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
