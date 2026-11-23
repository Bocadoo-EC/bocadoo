import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';
import 'widgets/hybrid_carta_view.dart';
import 'widgets/hybrid_extras_section.dart';
import 'widgets/hybrid_order_state.dart';
import 'widgets/individual_menu_accordion.dart';
import 'widgets/restaurant_preorder_widgets.dart';

/// C3 · Ficha del local: Carrito Híbrido en 2 pasos (1: Menú del Día / Carta +
/// Extras persistentes, 2: Tu Orden editable + Split-Billing + Modalidad/Hora).
class RestaurantSheet extends ConsumerStatefulWidget {
  final String restaurantId;

  const RestaurantSheet({super.key, required this.restaurantId});

  @override
  ConsumerState<RestaurantSheet> createState() => _RestaurantSheetState();
}

class _RestaurantSheetState extends ConsumerState<RestaurantSheet> {
  bool _sending = false;
  Timer? _quoteTimer;
  String? _requestedQuoteKey;
  String? _resolvedQuoteKey;
  OrderQuote? _liveQuote;

  @override
  void dispose() {
    _quoteTimer?.cancel();
    super.dispose();
  }

  String _buildQuoteKey(Restaurant r, HybridOrderState draft, bool takeaway) {
    final addons = [
      for (final l in draft.addonsList) '${l.item.id}x${l.quantity}',
    ].join(',');
    return '${r.id}|${draft.breakfastMode}|${draft.soupId}|${draft.mainId}|${draft.breakfastId}|$takeaway|$addons';
  }

  void _syncQuote({
    required CustomerController controller,
    required Restaurant r,
    required HybridOrderState draft,
    required bool takeaway,
    required bool enabled,
  }) {
    final key = _buildQuoteKey(r, draft, takeaway);
    if (!enabled) {
      if (_requestedQuoteKey != null || _liveQuote != null) {
        _quoteTimer?.cancel();
        _requestedQuoteKey = null;
        _resolvedQuoteKey = null;
        _liveQuote = null;
      }
      return;
    }
    if (_requestedQuoteKey == key) return;
    _requestedQuoteKey = key;
    _quoteTimer?.cancel();
    _quoteTimer = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted) return;
      final lunchReady = draft.isLunchReady(r);
      final resolvedSoupId =
          draft.soupId == kIndividualNoSoupId ? null : draft.soupId;
      final quote = await controller.quotePreorder(
        restaurant: r,
        soupId: (lunchReady && !draft.breakfastMode) ? resolvedSoupId : null,
        mainId: (lunchReady && !draft.breakfastMode) ? draft.mainId : null,
        breakfastId:
            (lunchReady && draft.breakfastMode) ? draft.breakfastId : null,
        takeaway: takeaway,
        cartaItems: [
          for (final l in draft.addonsList)
            (platoId: l.item.id, quantity: l.quantity.clamp(1, 10)),
        ],
      );
      if (!mounted || _requestedQuoteKey != key) return;
      setState(() {
        _resolvedQuoteKey = key;
        _liveQuote = quote;
      });
    });
  }

  HybridTenderSummary _resolveEffectiveTender({
    required Restaurant r,
    required HybridOrderState draft,
    required bool hasPlanHere,
    required bool takeaway,
    required String quoteKey,
  }) {
    final q = (_resolvedQuoteKey == quoteKey) ? _liveQuote : null;
    if (q != null) {
      final credits = q.planCreditsUsed;
      final cash = q.saldoPorCobrarCentavos;
      if (credits > 0 && cash <= 0) return HybridPlanOnlyTender(credits);
      if (credits > 0) {
        return HybridMixedTender(
          planCreditsUsed: credits,
          cashToCollectCents: cash,
        );
      }
      return HybridCashOnlyTender(cash);
    }
    return draft.resolveTender(
      r: r,
      hasPlanHere: hasPlanHere,
      takeaway: takeaway,
    );
  }

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

  Future<void> _pickCustomTime(
    Restaurant r,
    HybridOrderNotifier notifier,
  ) async {
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
    notifier.setArrival(formatted, isCustom: true);
  }

  String _resolveArrivalHhmm(HybridOrderState draft) {
    if (draft.selectedArrival != 'En 15 min') return draft.selectedArrival;
    final target = EcuadorTime.now().add(const Duration(minutes: 15));
    final hh = target.hour.toString().padLeft(2, '0');
    final mm = target.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _order(
    CustomerController controller,
    Restaurant r,
    HybridOrderState draft,
    HybridTenderSummary tender,
  ) async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final lunchReady = draft.isLunchReady(r);
    final resolvedSoupId =
        draft.soupId == kIndividualNoSoupId ? null : draft.soupId;

    final ok = await controller.preorder(
      restaurant: r,
      soupId: (lunchReady && !draft.breakfastMode) ? resolvedSoupId : null,
      mainId: (lunchReady && !draft.breakfastMode) ? draft.mainId : null,
      breakfastId: (lunchReady && draft.breakfastMode) ? draft.breakfastId : null,
      // Salón lleno: el pedido siempre es para llevar.
      takeaway: draft.takeaway ||
          ref.read(restaurantPublicStatusProvider(r.id)).isFull,
      estimatedArrival: _resolveArrivalHhmm(draft),
      cartaItems: [
        for (final l in draft.addonsList)
          (platoId: l.item.id, quantity: l.quantity.clamp(1, 10)),
      ],
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      if (draft.hasAddons && tender.cashToCollectCents > 0) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Preorden confirmada · Adicionales por pagar en caja: ${formatCents(tender.cashToCollectCents)}',
            ),
          ),
        );
      }
      context.pop();
      return;
    }
    var error = controller.lastActionError;
    if (controller.lastActionConflict) {
      error = await _soldOutMessage(draft) ?? error;
      if (!mounted) return;
    }
    if (error != null && error.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Text(error),
      ));
    }
  }

  /// 409: relee la carta y nombra qué ítems se agotaron; la selección no se borra.
  Future<String?> _soldOutMessage(HybridOrderState draft) async {
    ref.invalidate(restaurantCartaProvider(widget.restaurantId));
    try {
      final fresh = await ref.read(restaurantCartaProvider(widget.restaurantId).future);
      final soldOut = {for (final c in fresh) if (c.isSoldOut) c.id};
      final names = [
        for (final l in draft.addonsList)
          if (soldOut.contains(l.item.id)) l.item.name,
      ];
      if (names.isEmpty) return null;
      return 'Se agotó ${names.join(', ')}. Ajusta tu pedido para continuar.';
    } catch (_) {
      return null;
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
    ref.watch(hybridOrderProvider(widget.restaurantId));
    final notifier = ref.read(hybridOrderProvider(widget.restaurantId).notifier);
    final draft = notifier.sanitizeView(r, arrivalOptions);
    final cartaAsync = ref.watch(restaurantCartaProvider(widget.restaurantId));
    final cartaItems = cartaAsync.value ?? const <PublicCartaItem>[];

    final hasBreakfasts = r.breakfasts.isNotEmpty;
    final breakfastMode = hasBreakfasts && draft.breakfastMode;
    final hasActiveOrder = s.activeOrder != null;
    final publicStatus = ref.watch(restaurantPublicStatusProvider(r.id));
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

    final quoteKey = _buildQuoteKey(r, draft, takeaway);
    final canOrderAnyMenu = r.hasMenu && !menuSoldOutAll;
    final canOrderAddonsOnly = draft.hasAddons && !draft.hasPartialLunch(r);
    final canContinue = !isClosed &&
        !hasActiveOrder &&
        !_sending &&
        (canOrderAnyMenu || cartaItems.isNotEmpty) &&
        draft.canContinue(r) &&
        (draft.isLunchReady(r) ? !menuSoldOutAll : canOrderAddonsOnly);
    final canOrder = canContinue && draft.step == 2;

    _syncQuote(
      controller: controller,
      r: r,
      draft: draft,
      takeaway: takeaway,
      enabled: !isClosed && !hasActiveOrder && draft.canContinue(r),
    );

    final tender = _resolveEffectiveTender(
      r: r,
      draft: draft,
      hasPlanHere: hasPlanHere,
      takeaway: takeaway,
      quoteKey: quoteKey,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PreorderModalHeader(
          restaurantName: r.name,
          step: draft.step,
          totalSteps: 2,
          subtitle: draft.step == 1
              ? (draft.activeTab == RestaurantOrderTab.menuDelDia
                  ? 'Arma tu almuerzo'
                  : 'Arma tu pedido a la carta')
              : 'Confirmar orden',
          onBack: draft.step == 2 && !_sending
              ? () => notifier.setStep(1)
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
                    notifier: notifier,
                    cartaAsync: cartaAsync,
                    cartaItems: cartaItems,
                    publicStatus: publicStatus,
                    hasPlanHere: hasPlanHere,
                    hasBreakfasts: hasBreakfasts,
                    breakfastMode: breakfastMode,
                    isClosed: isClosed,
                  )
                : _buildStepTwo(
                    colors: colors,
                    r: r,
                    draft: draft,
                    notifier: notifier,
                    tender: tender,
                    hasPlanHere: hasPlanHere,
                    remainingLunches: activePass?.remainingLunches ?? 0,
                    arrivalOptions: arrivalOptions,
                    forceTakeaway: forceTakeaway,
                    takeaway: takeaway,
                  ),
          ),
        ),
        if (r.hasMenu || cartaItems.isNotEmpty)
          _buildBottomBar(
            colors: colors,
            r: r,
            draft: draft,
            notifier: notifier,
            tender: tender,
            controller: controller,
            isClosed: isClosed,
            hasActiveOrder: hasActiveOrder,
            menuSoldOutAll: menuSoldOutAll,
            canContinue: canContinue,
            canOrder: canOrder,
          ),
      ],
    );
  }

  Widget _buildStepOne({
    required CustomerUiState s,
    required Restaurant r,
    required HybridOrderState draft,
    required HybridOrderNotifier notifier,
    required AsyncValue<List<PublicCartaItem>> cartaAsync,
    required List<PublicCartaItem> cartaItems,
    required RestaurantPublicStatus publicStatus,
    required bool hasPlanHere,
    required bool hasBreakfasts,
    required bool breakfastMode,
    required bool isClosed,
  }) {
    final colors = context.colorScheme;
    final addonsCount = draft.addonsList.fold<int>(0, (sum, l) => sum + l.quantity);

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
        const SizedBox(height: 12),
        OrderTypeSegmentedBar(
          activeTab: draft.activeTab,
          addonsCount: addonsCount,
          onChanged: notifier.setTab,
        ),
        const SizedBox(height: 16),
        if (draft.activeTab == RestaurantOrderTab.menuDelDia) ...[
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
                onChanged: notifier.setBreakfastMode,
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
              onSelectSoup: notifier.selectSoup,
              onSelectMain: notifier.selectMain,
              onSelectBreakfast: notifier.selectBreakfast,
              onSelectDrink: notifier.selectDrink,
              onSelectDessert: notifier.selectDessert,
            ),
            const SizedBox(height: 18),
            HybridExtrasSection(
              restaurant: r,
              cartaItems: cartaItems,
              orderState: draft,
              showIncluded: true,
              onAdd: notifier.incrementItem,
              onDecrement: (id) => notifier.decrementItem(id, restaurant: r),
              onSelectIncludedDrink: notifier.selectDrink,
              onSelectIncludedDessert: notifier.selectDessert,
            ),
          ],
        ] else ...[
          HybridCartaView(
            restaurant: r,
            cartaItems: cartaItems,
            isLoading: cartaAsync.isLoading,
            orderState: draft,
            onAdd: notifier.incrementItem,
            onDecrement: (id) => notifier.decrementItem(id, restaurant: r),
          ),
        ],
      ],
    );
  }

  Widget _buildStepTwo({
    required ColorScheme colors,
    required Restaurant r,
    required HybridOrderState draft,
    required HybridOrderNotifier notifier,
    required HybridTenderSummary tender,
    required bool hasPlanHere,
    required int remainingLunches,
    required List<String> arrivalOptions,
    required bool forceTakeaway,
    required bool takeaway,
  }) {
    return ListView(
      key: const ValueKey(2),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        EditableHybridOrderCard(
          restaurant: r,
          state: draft,
          hasPlanHere: tender.planCreditsUsed > 0,
          onEditLunch: () {
            notifier.setTab(RestaurantOrderTab.menuDelDia);
            notifier.setStep(1);
          },
          onClearLunch: notifier.clearLunchSelection,
          onIncrementItem: notifier.incrementItem,
          onDecrementItem: (id) => notifier.decrementItem(id, restaurant: r),
          onRemoveItem: (id) => notifier.removeItem(id, restaurant: r),
        ),
        const SizedBox(height: 14),
        SplitBillingSummaryCard(
          tender: tender,
          remainingLunches: remainingLunches,
          hasLunch: draft.isLunchReady(r),
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
                onTap: forceTakeaway ? null : () => notifier.setTakeaway(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChoiceButton(
                label: 'Para llevar (+${formatMoney(r.takeawaySurcharge)})',
                icon: Icons.takeout_dining_outlined,
                selected: takeaway,
                onTap: () => notifier.setTakeaway(true),
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
                onSelected: (_) => notifier.setArrival(opt),
              ),
            ChoiceChip(
              label: Text(draft.customArrival ?? '+'),
              selected: draft.customArrival != null &&
                  draft.selectedArrival == draft.customArrival,
              onSelected: (_) => _pickCustomTime(r, notifier),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar({
    required ColorScheme colors,
    required Restaurant r,
    required HybridOrderState draft,
    required HybridOrderNotifier notifier,
    required HybridTenderSummary tender,
    required CustomerController controller,
    required bool isClosed,
    required bool hasActiveOrder,
    required bool menuSoldOutAll,
    required bool canContinue,
    required bool canOrder,
  }) {
    final String stepOneCtaLabel;
    if (hasActiveOrder) {
      stepOneCtaLabel = 'Ya tienes un pedido en camino';
    } else if (menuSoldOutAll && !draft.hasAddons) {
      stepOneCtaLabel = 'Menú agotado por hoy';
    } else if (!draft.canContinue(r)) {
      stepOneCtaLabel = draft.activeTab == RestaurantOrderTab.carta
          ? 'Elige un plato o extra para continuar'
          : 'Completa los platos requeridos · ${formatMoney(r.singleLunchPrice)}';
    } else {
      stepOneCtaLabel = switch (tender) {
        HybridPlanOnlyTender() => 'Continuar · 1 cupo de plan',
        HybridMixedTender(:final cashToCollectCents) =>
          'Continuar · 1 cupo + ${formatCents(cashToCollectCents)} en local',
        HybridCashOnlyTender(:final cashToCollectCents) =>
          'Continuar · ${formatCents(cashToCollectCents)} en local',
      };
    }

    final stepTwoCtaLabel = hasActiveOrder
        ? 'Ya tienes un pedido en camino'
        : 'Confirmar preorden';

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
                  if (draft.step == 1)
                    ElevatedButton(
                      onPressed: canContinue ? () => notifier.setStep(2) : null,
                      child: Text(stepOneCtaLabel),
                    )
                  else
                    ElevatedButton(
                      onPressed: canOrder
                          ? () => _order(controller, r, draft, tender)
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
