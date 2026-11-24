import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/theme/app_theme.dart';
import '../../group_orders/presentation/group_order_models.dart';
import '../../group_orders/presentation/group_order_simulation_provider.dart';
import '../domain/feedback_rules.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';
import 'feedback_card.dart';
import 'widgets/bocadoo_order_card.dart';

/// C1 · Mi Pase: QR del plan, preorden o mesa, sellos y últimos movimientos.
class PaseScreen extends ConsumerStatefulWidget {
  const PaseScreen({super.key});

  @override
  ConsumerState<PaseScreen> createState() => _PaseScreenState();
}

class _PaseScreenState extends ConsumerState<PaseScreen>
    with WidgetsBindingObserver {
  late final CustomerController _controller;
  int _lastCelebrationTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ref.read(customerControllerProvider);
    _lastCelebrationTick = _controller.state.redemptionCelebrationTick;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.onPaseVisibilityChanged(true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed) {
      _controller.onPaseVisibilityChanged(true, resumedFromBackground: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _controller.onPaseVisibilityChanged(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.onPaseVisibilityChanged(false);
    super.dispose();
  }

  void _showRedemptionAnimation(String title, String? subtitle) {
    if (!mounted) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar confirmación',
      barrierColor: context.colorScheme.scrim.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, _) {
        Future.delayed(const Duration(milliseconds: 3500), () {
          if (ctx.mounted && Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
        });
        final colors = ctx.colorScheme;
        final b = ctx.bocadooColors;
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(28),
              elevation: 8,
              child: Container(
                width: 296,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: b.successContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 46,
                        color: b.success,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (Navigator.of(ctx).canPop()) {
                            Navigator.of(ctx).pop();
                          }
                        },
                        child: const Text('Entendido'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        GroupOrderSimulationStore.instance,
      ]),
      builder: (context, _) {
        final s = controller.state;
        if (s.redemptionCelebrationTick > _lastCelebrationTick) {
          _lastCelebrationTick = s.redemptionCelebrationTick;
          final title = s.redemptionCelebrationTitle ?? 'Almuerzo canjeado';
          final subtitle = s.redemptionCelebrationSubtitle;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showRedemptionAnimation(title, subtitle);
          });
        }
        final hasActiveOrder = s.activeOrder != null;
        final isSingleActiveOrder =
            hasActiveOrder && !s.activeOrder!.hasPlan && !s.activeOrder!.isDelivered;
        final activePasses =
            s.passes.where((p) => p.remainingLunches > 0).toList();
        final hasAnyPassOrLive =
            s.passes.isNotEmpty || hasActiveOrder || s.activeTable != null;
        if (!hasAnyPassOrLive &&
            (s.isLoading || s.status == CustomerStatus.initial)) {
          return const _PaseSkeleton();
        }
        if (!hasAnyPassOrLive && s.isError) {
          return CustomerErrorView(
            title: 'Error al cargar pase',
            message: s.errorMessage ?? 'No pudimos cargar tu pase.',
            onRetry: controller.loadDashboard,
          );
        }
        final stampRestaurantId = s.currentPass?.restaurantId;
        return RefreshIndicator(
          onRefresh: () => controller.loadDashboard(silent: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 12,
              16,
              96,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WalletTopBar(state: s),
                if (s.consumptionNotice != null) ...[
                  const SizedBox(height: 10),
                  _ConsumptionConfirmedBanner(
                    message: s.consumptionNotice!,
                    onDismiss: controller.clearConsumptionNotice,
                  ),
                ],
                const SizedBox(height: 14),
                _WalletDeck(
                  state: s,
                  controller: controller,
                  activePasses: activePasses,
                  showYellowDiscover: !isSingleActiveOrder,
                ),
                if (shouldShowFeedback(
                  s.pendingFeedback,
                  DateTime.now(),
                )) ...[
                  const SizedBox(height: 16),
                  FeedbackCard(controller: controller),
                ],
                if (stampRestaurantId != null)
                  if (s.stampCards[stampRestaurantId]
                      case final card?) ...[
                    const SizedBox(height: 16),
                    _StampSection(card: card, controller: controller),
                  ],
                const SizedBox(height: 16),
                _TableButton(hasTable: s.activeTable != null),
                const SizedBox(height: 20),
                _RecentActivity(items: s.recentActivity),
              ],
            ),
          ),
        );
      },
    );
  }
}

void _showZoomedQr(
  BuildContext context,
  String value,
  String label, {
  String? restaurantId,
  String? badgeOverride,
}) {
  final colors = context.colorScheme;
  final shortCode = BocadooQrParser.toShortCode(value, restaurantId: restaurantId);
  final qrData = AppMode.useMock ? shortCode : value;
  if (!AppMode.useMock && qrData.isEmpty) return;
  final displayCode = badgeOverride ?? shortCode;
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar QR ampliado',
    pageBuilder: (ctx, _, _) => GestureDetector(
      onTap: () => Navigator.of(ctx).pop(),
      child: Material(
        color: colors.surface,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: ctx.bocadooColors.qrBackground,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: _Qr(value: qrData, size: 280),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        displayCode,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Toca en cualquier lugar para cerrar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  tooltip: 'Cerrar QR ampliado',
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WalletTopBar extends StatelessWidget {
  final CustomerUiState state;

  const _WalletTopBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: b.heroGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.wallet_rounded,
            size: 20,
            color: b.imageForeground,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu billetera Bocadoo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
              Text(
                'Mi Pase',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (state.isOffline)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 14, color: colors.primary),
                const SizedBox(width: 4),
                Text(
                  'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConsumptionConfirmedBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ConsumptionConfirmedBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: b.successContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: b.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 20, color: b.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: b.onSuccessContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar aviso',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, size: 18, color: b.onSuccessContainer),
          ),
        ],
      ),
    );
  }
}

class _WalletDeck extends StatelessWidget {
  final CustomerUiState state;
  final CustomerController controller;
  final List<CustomerPass> activePasses;
  final bool showYellowDiscover;

  const _WalletDeck({
    required this.state,
    required this.controller,
    required this.activePasses,
    required this.showYellowDiscover,
  });

  @override
  Widget build(BuildContext context) {
    final mode = state.qrMode;
    final frontPasses = activePasses.isNotEmpty ? activePasses : state.passes;
    final hasAnyCard =
        frontPasses.isNotEmpty || state.activeOrder != null || state.activeTable != null;

    final backCards = <Widget>[];
    if (showYellowDiscover) {
      backCards.add(
        _DiscoverWalletTab(
          onTap: () => context.go('/customer/restaurants'),
        ),
      );
    }

    if (state.activeOrder != null && mode != QrMode.preorden) {
      final ord = state.activeOrder!;
      backCards.add(
        _StackedOrderTab(
          order: ord,
          onTap: () => controller.selectQrMode(QrMode.preorden),
        ),
      );
    }

    if (state.activeTable != null && mode != QrMode.mesa) {
      backCards.add(
        _StackedTableTab(
          table: state.activeTable!,
          onTap: () => controller.selectQrMode(QrMode.mesa),
        ),
      );
    }

    for (final (i, pass) in state.passes.indexed) {
      if (pass.remainingLunches <= 0) continue;
      if (mode == QrMode.plan && i == state.passIndex) continue;
      backCards.add(
        _StackedPlanTab(
          pass: pass,
          tintIndex: i,
          onTap: () => controller.selectPass(i),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (backCards.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < backCards.length; i++)
                Align(
                  alignment: Alignment.topCenter,
                  heightFactor: (hasAnyCard || i < backCards.length - 1) ? 0.78 : 1.0,
                  child: backCards[i],
                ),
            ],
          ),
        if (hasAnyCard)
          _ActiveWalletCard(state: state, controller: controller)
        else
          const _EmptyPlanPrompt(),
      ],
    );
  }
}

class _DiscoverWalletTab extends StatelessWidget {
  final VoidCallback onTap;

  const _DiscoverWalletTab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Material(
      color: b.walletAccent,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Row(
            children: [
              Icon(Icons.explore_rounded, size: 22, color: b.onWalletAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Descubrir restaurantes',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: b.onWalletAccent,
                      ),
                    ),
                    Text(
                      'Explora menús de hoy y arma tu pedido',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: b.onWalletAccent.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: b.onWalletAccent),
            ],
          ),
        ),
      ),
    );
  }
}

class _StackedPlanTab extends StatelessWidget {
  final CustomerPass pass;
  final int tintIndex;
  final VoidCallback onTap;

  const _StackedPlanTab({
    required this.pass,
    required this.tintIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final usePrimaryTint = tintIndex.isEven;
    final bg = usePrimaryTint ? colors.primaryContainer : colors.secondaryContainer;
    final fg = usePrimaryTint ? colors.onPrimaryContainer : colors.onSecondaryContainer;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Row(
            children: [
              Icon(Icons.confirmation_number_rounded, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pass.restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: fg,
                      ),
                    ),
                    Text(
                      '${pass.remainingLunches} de ${pass.totalLunches} disponibles · Vence ${formatShortDate(pass.expiresAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more_rounded, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _StackedOrderTab extends StatelessWidget {
  final ActiveOrder order;
  final VoidCallback onTap;

  const _StackedOrderTab({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Material(
      color: b.successContainer,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: b.success.withValues(alpha: 0.35)),
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: b.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Preorden #${order.orderNumber} · ${order.restaurantName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: b.onSuccessContainer,
                  ),
                ),
              ),
              Icon(Icons.qr_code_2_rounded, size: 18, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _StackedTableTab extends StatelessWidget {
  final ActiveTable table;
  final VoidCallback onTap;

  const _StackedTableTab({required this.table, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colors.outlineVariant),
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Row(
            children: [
              Icon(Icons.groups_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mesa ${table.time} · ${table.restaurantName} (${table.membersCount})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
              ),
              Icon(Icons.qr_code_2_rounded, size: 18, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveWalletCard extends StatelessWidget {
  final CustomerUiState state;
  final CustomerController controller;

  const _ActiveWalletCard({
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final mode = state.qrMode;
    final pass = state.currentPass;
    final order = state.activeOrder;
    final table = state.activeTable;
    final simSession = table != null
        ? (GroupOrderSimulationStore.instance.sessionById(table.id) ??
            GroupOrderSimulationStore.instance.activeSession)
        : null;
    final isMesaCollecting = mode == QrMode.mesa &&
        table != null &&
        simSession != null &&
        simSession.status == GroupOrderStatus.collecting;
    final isMesaConfirmed = mode == QrMode.mesa &&
        table != null &&
        simSession != null &&
        simSession.status == GroupOrderStatus.confirmed;

    final menuAvail = mode == QrMode.plan && pass != null
        ? state.menuAvailabilityFor(pass.restaurantId)
        : MenuAvailabilityState.disponible;

    final String title;
    final BocadooOrderCardType orderType;
    final int? totalCents;
    final int? availableLunches;
    final String? scheduledTime;
    final int extraCashCents;
    final String qrData;
    final bool hasActiveOrderQr;
    final String inactiveQrLabel;
    final String? shortRestaurantId;
    final String? displayCodeOverride;
    final VoidCallback onViewStatus;

    if (mode == QrMode.preorden && order != null) {
      title = order.restaurantName;
      final isFlash = controller.isFlashOfferOrder(order);
      orderType = isFlash
          ? BocadooOrderCardType.flashOffer
          : (order.hasPlan
              ? BocadooOrderCardType.preorderWithPlan
              : BocadooOrderCardType.preorderWithoutPlan);
      final matchingPass = order.restaurantId != null
          ? state.passFor(order.restaurantId!)
          : null;
      availableLunches = order.hasPlan
          ? (matchingPass?.remainingLunches ?? order.planCreditsUsed)
          : null;
      totalCents = order.hasPlan
          ? null
          : (order.cashToCollectCents > 0
              ? order.cashToCollectCents
              : order.effectiveTotalCents);
      extraCashCents = order.hasPlan ? order.cashToCollectCents : 0;
      scheduledTime = order.estimatedArrivalLabel;
      shortRestaurantId = order.restaurantId;
      final shortCode = BocadooQrParser.toShortCode(
        state.qrValue,
        restaurantId: shortRestaurantId,
      );
      qrData = AppMode.useMock ? shortCode : state.qrValue;
      hasActiveOrderQr = AppMode.useMock ? qrData.isNotEmpty : state.qrValue.isNotEmpty;
      inactiveQrLabel = 'Generando QR...';
      displayCodeOverride = !AppMode.useMock ? '#${order.orderNumber}' : null;
      onViewStatus = () => context.push('/customer/pedido/${order.orderNumber}');
    } else if (mode == QrMode.mesa && table != null) {
      title = simSession != null
          ? 'Mesa de ${simSession.hostName}'
          : table.restaurantName;
      orderType = BocadooOrderCardType.groupOrder;
      availableLunches = null;
      totalCents = controller.tableTotalCentsFor(table, state);
      extraCashCents = 0;
      scheduledTime = simSession?.timeHhmm ?? table.time;
      shortRestaurantId = null;
      final shortCode = BocadooQrParser.toShortCode(state.qrValue);
      qrData = isMesaConfirmed
          ? simSession.qrPayload
          : (AppMode.useMock ? shortCode : state.qrValue);
      hasActiveOrderQr = !isMesaCollecting && qrData.isNotEmpty;
      inactiveQrLabel = isMesaCollecting
          ? 'Esperando (${simSession.confirmedCount}/${simSession.totalParticipants})'
          : 'QR pendiente';
      displayCodeOverride = isMesaConfirmed ? 'Mesa #${simSession.shortCode}' : null;
      onViewStatus = () => context.push(
            '/customer/mesa?groupOrderId=${table.id}${simSession != null ? '&restaurantId=${simSession.restaurantId}' : ''}',
          );
    } else if (pass != null) {
      title = pass.restaurantName;
      orderType = BocadooOrderCardType.preorderWithPlan;
      availableLunches = pass.remainingLunches;
      totalCents = null;
      final activeOrderHere = order != null &&
          !order.isDelivered &&
          order.restaurantId == pass.restaurantId
          ? order
          : null;
      extraCashCents = activeOrderHere?.cashToCollectCents ?? 0;
      scheduledTime = activeOrderHere?.estimatedArrivalLabel;
      shortRestaurantId = pass.restaurantId;
      if (activeOrderHere != null) {
        final orderCode = BocadooQrParser.toShortCode(
          activeOrderHere.qrPayload,
          restaurantId: shortRestaurantId,
        );
        qrData = AppMode.useMock ? orderCode : activeOrderHere.qrPayload;
        hasActiveOrderQr = qrData.isNotEmpty;
        displayCodeOverride =
            !AppMode.useMock ? '#${activeOrderHere.orderNumber}' : null;
        inactiveQrLabel = 'Generando QR...';
        onViewStatus =
            () => context.push('/customer/pedido/${activeOrderHere.orderNumber}');
      } else {
        qrData = '';
        hasActiveOrderQr = false;
        displayCodeOverride = null;
        inactiveQrLabel = switch (menuAvail) {
          MenuAvailabilityState.sinPublicar => 'Menú sin publicar',
          MenuAvailabilityState.agotadoTotal => 'Menú agotado hoy',
          MenuAvailabilityState.disponible => 'Se activará al pedir',
        };
        onViewStatus =
            () => context.push('/customer/restaurants/${pass.restaurantId}');
      }
    } else {
      title = 'Bocadoo';
      orderType = BocadooOrderCardType.preorderWithoutPlan;
      availableLunches = null;
      totalCents = 0;
      extraCashCents = 0;
      scheduledTime = null;
      shortRestaurantId = null;
      qrData = '';
      hasActiveOrderQr = false;
      displayCodeOverride = null;
      inactiveQrLabel = 'Se activará al pedir';
      onViewStatus = () => context.go('/customer/restaurants');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BocadooOrderCard(
          restaurantName: title,
          orderType: orderType,
          totalCents: totalCents,
          availableLunches: availableLunches,
          scheduledTime: scheduledTime,
          extraCashCents: extraCashCents,
          qrPayload: qrData,
          hasActiveOrderQr: hasActiveOrderQr,
          inactiveQrLabel: inactiveQrLabel,
          onTapQr: hasActiveOrderQr
              ? () => _showZoomedQr(
                    context,
                    qrData,
                    title,
                    restaurantId: shortRestaurantId,
                    badgeOverride: displayCodeOverride,
                  )
              : null,
          onTapViewStatus: onViewStatus,
        ),
        if (mode == QrMode.plan &&
            pass != null &&
            menuAvail == MenuAvailabilityState.sinPublicar) ...[
          const SizedBox(height: 12),
          _MenuNotPublishedQrBlock(
            restaurantId: pass.restaurantId,
            onRefresh: () => controller.loadDashboard(silent: true),
          ),
        ] else if (mode == QrMode.plan &&
            pass != null &&
            menuAvail == MenuAvailabilityState.agotadoTotal) ...[
          const SizedBox(height: 12),
          _MenuSoldOutQrBlock(
            restaurantId: pass.restaurantId,
            hasReservedOrder: order != null &&
                !order.isDelivered &&
                order.restaurantId == pass.restaurantId,
            onOpenOrderQr: order != null &&
                    !order.isDelivered &&
                    order.restaurantId == pass.restaurantId
                ? () => controller.selectQrMode(QrMode.preorden)
                : null,
            onRefresh: () => controller.loadDashboard(silent: true),
          ),
        ] else if (isMesaCollecting) ...[
          const SizedBox(height: 12),
          _PendingGroupTableBlock(
            confirmedCount: simSession.confirmedCount,
            totalCount: simSession.totalParticipants,
            restaurantName: simSession.restaurantName,
            onOpenMesa: () => context.push(
              '/customer/mesa?groupOrderId=${table.id}&restaurantId=${simSession.restaurantId}',
            ),
            onCancelMesa: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('¿Cancelar pedido grupal?'),
                  content: const Text(
                    'Se cerrará esta mesa compartida sin costo alguno y tus amigos ya no podrán unirse.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Seguir en la mesa'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(
                        'Cancelar pedido',
                        style: TextStyle(color: ctx.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm != true || !context.mounted) return;
              final ok = await controller.cancelSharedTable(table.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    ok
                        ? 'Pedido grupal cancelado'
                        : (controller.lastActionError ??
                            'No se pudo cancelar el pedido grupal'),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _PendingGroupTableBlock extends StatelessWidget {
  const _PendingGroupTableBlock({
    required this.confirmedCount,
    required this.totalCount,
    required this.restaurantName,
    required this.onOpenMesa,
    required this.onCancelMesa,
  });

  final int confirmedCount;
  final int totalCount;
  final String restaurantName;
  final VoidCallback onOpenMesa;
  final VoidCallback onCancelMesa;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: b.walletAccent.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.hourglass_top_rounded,
              size: 28,
              color: b.onWalletAccent,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: b.walletAccent.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
            child: Text(
              'Pendiente de confirmación ($confirmedCount/$totalCount)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: b.onWalletAccent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            restaurantName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'El código QR de la mesa se generará automáticamente cuando todos los invitados confirmen su plato.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onOpenMesa,
            icon: const Icon(Icons.group_outlined, size: 18),
            label: const Text('Ver mesa y compartir'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onCancelMesa,
            icon: Icon(Icons.close_rounded, size: 17, color: colors.error),
            label: Text(
              'Cancelar pedido grupal',
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuNotPublishedQrBlock extends StatelessWidget {
  final String restaurantId;
  final VoidCallback onRefresh;

  const _MenuNotPublishedQrBlock({
    required this.restaurantId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: b.walletAccent.withValues(alpha: 0.28),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.schedule_rounded,
              size: 28,
              color: b.onWalletAccent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '⏳ Menú de hoy aún no disponible',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'El restaurante todavía no ha publicado el menú del día. Tu QR se activará automáticamente en cuanto lo publiquen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Actualizar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: () =>
                      context.push('/customer/restaurants/$restaurantId'),
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text(
                    'Ver local',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuSoldOutQrBlock extends StatelessWidget {
  final String restaurantId;
  final bool hasReservedOrder;
  final VoidCallback? onOpenOrderQr;
  final VoidCallback onRefresh;

  const _MenuSoldOutQrBlock({
    required this.restaurantId,
    required this.hasReservedOrder,
    this.onOpenOrderQr,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: b.dangerContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: b.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: b.dangerContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.no_meals_rounded,
              size: 28,
              color: b.onDangerContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Almuerzos del día agotados en este local',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasReservedOrder
                ? 'Ya no quedan almuerzos disponibles hoy, pero tu preorden reservada sigue lista para canjear en caja.'
                : 'Todos los platos de hoy se agotaron en cocina. Tu saldo sigue intacto para tu próxima visita.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: colors.onSurfaceVariant,
            ),
          ),
          if (hasReservedOrder && onOpenOrderQr != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onOpenOrderQr,
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: const Text('Ver QR de mi preorden'),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Actualizar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: () =>
                      context.push('/customer/restaurants/$restaurantId'),
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text(
                    'Ver local',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyPlanPrompt extends StatelessWidget {
  const _EmptyPlanPrompt();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_offer_rounded,
              size: 28,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Todavía no tienes un plan activo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Elige un paquete semanal o mensual y presenta tu QR en caja para ahorrar en cada comida.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/customer/plans'),
              icon: const Icon(Icons.confirmation_number_outlined),
              label: const Text('Ver planes y ahorrar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Qr extends StatelessWidget {
  final String value;
  final double size;

  const _Qr({required this.value, required this.size});

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return QrImageView(
      data: value.isEmpty ? 'BOCADOO' : value,
      version: QrVersions.auto,
      size: size,
      padding: EdgeInsets.zero,
      backgroundColor: b.qrBackground,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: b.qrForeground),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: b.qrForeground,
      ),
    );
  }
}

class _StampSection extends StatelessWidget {
  final StampCard card;
  final CustomerController controller;

  const _StampSection({required this.card, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final rows = <List<int>>[];
    for (var i = 1; i <= card.goal; i += 5) {
      rows.add([for (var n = i; n < i + 5 && n <= card.goal; n++) n]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        AppTheme.buttonRadius,
                      ),
                    ),
                    child: Text(
                      '${card.current}/${card.goal}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final n in row)
                        _Stamp(number: n, done: n <= card.current),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Premio: ${card.reward}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: colors.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Tus sellos y premios no caducan',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        if (card.rewardsAvailable > 0) ...[
          const SizedBox(height: 12),
          if (ApiCapabilities.claimStampReward)
            ElevatedButton(
              onPressed: () => controller.claimReward(card.restaurantId),
              child: Text(
                card.rewardsAvailable > 1
                    ? 'Reclamar premio (${card.rewardsAvailable} disponibles)'
                    : 'Reclamar premio',
              ),
            )
          else
            Text(
              'Muéstralo en caja.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
        ],
      ],
    );
  }
}

class _Stamp extends StatelessWidget {
  final int number;
  final bool done;

  const _Stamp({required this.number, required this.done});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? colors.primary : colors.surface,
        shape: BoxShape.circle,
        border: done
            ? null
            : Border.all(color: colors.outlineVariant, width: 1.5),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 22, color: colors.onPrimary)
          : Text(
              '$number',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
    );
  }
}

class _TableButton extends StatelessWidget {
  final bool hasTable;

  const _TableButton({required this.hasTable});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return OutlinedButton.icon(
      onPressed: () => context.push('/customer/mesa'),
      style: OutlinedButton.styleFrom(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.onSurface,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      icon: Icon(Icons.group_outlined, size: 18, color: colors.primary),
      label: Text(hasTable ? 'Mi mesa' : 'Pedido grupal'),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  final List<ActivityItem> items;

  const _RecentActivity({required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: SectionLabel('Últimos movimientos'),
        ),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Aún sin movimientos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final t in items.take(5))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      switch (t.kind) {
                        'plan' => Icons.shopping_bag_outlined,
                        'lunch' => Icons.restaurant_rounded,
                        _ => Icons.receipt_long_outlined,
                      },
                      size: 17,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          t.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: t.positive ? b.success : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _PaseSkeleton extends StatelessWidget {
  const _PaseSkeleton();

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    final light = b.imageForeground.withValues(alpha: 0.2);
    return Semantics(
      label: 'Cargando pase',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 300,
            decoration: BoxDecoration(
              gradient: b.heroGradient,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(40),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 16,
              20,
              72,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: light,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 150,
                      height: 14,
                      decoration: BoxDecoration(
                        color: light,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 180,
                  height: 18,
                  decoration: BoxDecoration(
                    color: light,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 130,
                  height: 48,
                  decoration: BoxDecoration(
                    color: light,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -48),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkeletonBox(height: 248, radius: 32),
                  SizedBox(height: 16),
                  SkeletonBox(height: 52, radius: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

