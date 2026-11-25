import 'dart:async';

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
        final activeOrderRestId = s.activeOrder?.restaurantId;
        final hasActivePlanForOrder = s.activeOrder != null &&
            activeOrderRestId != null &&
            (s.passFor(activeOrderRestId)?.remainingLunches ?? 0) > 0 &&
            !(s.passFor(activeOrderRestId)?.isExpired ?? true);
        final isSingleActiveOrder = hasActiveOrder &&
            !s.activeOrder!.hasPlan &&
            !hasActivePlanForOrder &&
            !s.activeOrder!.isDelivered;
        final activePasses =
            s.passes.where((p) => p.remainingLunches > 0).toList();
        final hasAnyPassOrLive = s.passes.isNotEmpty ||
            hasActiveOrder ||
            s.activeTable != null ||
            s.pendingPlanRequests.isNotEmpty;
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

class _WalletCardData {
  const _WalletCardData({
    required this.keyId,
    required this.chipLabel,
    required this.chipIcon,
    required this.title,
    required this.orderType,
    this.totalCents,
    this.availableLunches,
    this.scheduledTime,
    this.extraCashCents = 0,
    this.qrData = '',
    this.hasActiveOrderQr = false,
    this.inactiveQrLabel = 'Genera un pedido para obtener tu QR',
    this.statusBadgeLabel,
    this.statusBadgeIcon,
    this.metricLabelOverride,
    this.metricValueOverride,
    this.extraPillLabelOverride,
    this.dormantQrIcon,
    this.actionLabel = 'VER ESTADO',
    this.shortRestaurantId,
    this.displayCodeOverride,
    required this.onViewStatus,
    this.onTapInactiveQr,
    this.contextualFooter,
  });

  final String keyId;
  final String chipLabel;
  final IconData chipIcon;
  final String title;
  final BocadooOrderCardType orderType;
  final int? totalCents;
  final int? availableLunches;
  final String? scheduledTime;
  final int extraCashCents;
  final String qrData;
  final bool hasActiveOrderQr;
  final String inactiveQrLabel;
  final String? statusBadgeLabel;
  final IconData? statusBadgeIcon;
  final String? metricLabelOverride;
  final String? metricValueOverride;
  final String? extraPillLabelOverride;
  final IconData? dormantQrIcon;
  final String actionLabel;
  final String? shortRestaurantId;
  final String? displayCodeOverride;
  final VoidCallback onViewStatus;
  final VoidCallback? onTapInactiveQr;
  final Widget? contextualFooter;
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

  List<_WalletCardData> _buildCards(BuildContext context) {
    final cards = <_WalletCardData>[];
    final order = state.activeOrder;
    final table = state.activeTable;
    final frontPasses = activePasses.isNotEmpty
        ? activePasses
        : state.passes
            .where((p) => p.remainingLunches > 0 && !p.isExpired)
            .toList();

    // 1. Preorden activa (Individual, con Plan u Oferta Flash).
    // Regla de prioridad absoluta: si existe un plan activo en el mismo
    // restaurante aunque la preorden se haya creado antes de aprobarse el plan,
    // se fusionan en una sola tarjeta unificada "Preorden con Plan".
    if (order != null && !order.isDelivered) {
      final isFlash = controller.isFlashOfferOrder(order);
      final matchingPass = order.restaurantId != null
          ? state.passFor(order.restaurantId!)
          : null;
      final hasActivePlanHere = matchingPass != null &&
          matchingPass.remainingLunches > 0 &&
          !matchingPass.isExpired;
      final effectiveHasPlan = order.hasPlan || (!isFlash && hasActivePlanHere);
      final orderType = isFlash
          ? BocadooOrderCardType.flashOffer
          : (effectiveHasPlan
              ? BocadooOrderCardType.preorderWithPlan
              : BocadooOrderCardType.preorderWithoutPlan);
      final shortCode = BocadooQrParser.toShortCode(
        order.qrPayload,
        restaurantId: order.restaurantId,
      );
      final qrData = AppMode.useMock ? shortCode : order.qrPayload;
      final orderMenuAvail = order.restaurantId != null
          ? state.menuAvailabilityFor(order.restaurantId!)
          : MenuAvailabilityState.disponible;
      final isOrderMenuPublished =
          orderMenuAvail != MenuAvailabilityState.sinPublicar;
      final hasQr = qrData.isNotEmpty && isOrderMenuPublished;
      final chipLabel = isFlash
          ? 'Flash · ${order.restaurantName}'
          : (effectiveHasPlan
              ? 'Orden c/Plan #${order.orderNumber}'
              : 'Preorden #${order.orderNumber}');
      final chipIcon = isFlash
          ? Icons.bolt_rounded
          : (effectiveHasPlan
              ? Icons.confirmation_number_rounded
              : Icons.receipt_long_rounded);

      cards.add(
        _WalletCardData(
          keyId: 'order:${order.orderNumber}',
          chipLabel: chipLabel,
          chipIcon: chipIcon,
          title: order.restaurantName,
          orderType: orderType,
          totalCents: effectiveHasPlan
              ? null
              : (order.cashToCollectCents > 0
                  ? order.cashToCollectCents
                  : order.effectiveTotalCents),
          availableLunches: effectiveHasPlan
              ? (matchingPass?.remainingLunches ?? order.planCreditsUsed)
              : null,
          scheduledTime: order.estimatedArrivalLabel,
          extraCashCents: effectiveHasPlan ? order.cashToCollectCents : 0,
          qrData: qrData,
          hasActiveOrderQr: hasQr,
          inactiveQrLabel:
              !isOrderMenuPublished ? 'Menú sin publicar' : 'Generando QR...',
          statusBadgeLabel: effectiveHasPlan ? 'Cubierto por tu Plan' : null,
          statusBadgeIcon:
              effectiveHasPlan ? Icons.confirmation_number_rounded : null,
          actionLabel: 'VER ESTADO',
          shortRestaurantId: order.restaurantId,
          displayCodeOverride: !AppMode.useMock ? '#${order.orderNumber}' : null,
          onViewStatus: () => context.push('/customer/pedido/${order.orderNumber}'),
        ),
      );
    }

    // 2. Orden grupal activa (solo si el restaurante ya publicó el menú de hoy)
    if (table != null) {
      final simSession = GroupOrderSimulationStore.instance.sessionById(table.id) ??
          GroupOrderSimulationStore.instance.activeSession;
      final tableRestId = simSession?.restaurantId ??
          state.restaurants
              .where(
                (r) =>
                    r.name.trim().toLowerCase() ==
                    table.restaurantName.trim().toLowerCase(),
              )
              .firstOrNull
              ?.id;
      final tableMenuAvail = tableRestId != null
          ? state.menuAvailabilityFor(tableRestId)
          : MenuAvailabilityState.disponible;
      final isTableMenuPublished =
          tableMenuAvail != MenuAvailabilityState.sinPublicar;

      if (!isTableMenuPublished) {
        unawaited(controller.cancelSharedTable(table.id));
      } else {
        final isMesaCollecting = simSession != null &&
            simSession.status == GroupOrderStatus.collecting;
        final isMesaConfirmed = simSession != null &&
            simSession.status == GroupOrderStatus.confirmed;
        final shortCode = BocadooQrParser.toShortCode(table.url);
        final qrData = isMesaConfirmed
            ? simSession.qrPayload
            : (AppMode.useMock ? shortCode : table.url);
        final title = simSession != null
            ? 'Mesa de ${simSession.hostName}'
            : table.restaurantName;

        cards.add(
          _WalletCardData(
            keyId: 'table:${table.id}',
            chipLabel: 'Mesa grupal',
            chipIcon: Icons.groups_rounded,
            title: title,
            orderType: BocadooOrderCardType.groupOrder,
            totalCents: controller.tableTotalCentsFor(table, state),
            scheduledTime: simSession?.timeHhmm ?? table.time,
            qrData: qrData,
            hasActiveOrderQr:
                isTableMenuPublished && !isMesaCollecting && qrData.isNotEmpty,
            inactiveQrLabel: isMesaCollecting
                ? 'Esperando (${simSession.confirmedCount}/${simSession.totalParticipants})'
                : 'QR pendiente',
            actionLabel: 'VER ESTADO',
            displayCodeOverride:
                isMesaConfirmed ? 'Mesa #${simSession.shortCode}' : null,
            onViewStatus: () => context.push(
              '/customer/mesa?groupOrderId=${table.id}${simSession != null ? '&restaurantId=${simSession.restaurantId}' : ''}',
            ),
            contextualFooter: isMesaCollecting
                ? _PendingGroupTableBlock(
                    confirmedCount: simSession.confirmedCount,
                    totalCount: simSession.totalParticipants,
                    restaurantName: simSession.restaurantName,
                    onOpenMesa: () => context.push(
                      '/customer/mesa?groupOrderId=${table.id}&restaurantId=${simSession.restaurantId}',
                    ),
                    onCancelMesa: () =>
                        _confirmCancelGroupTable(context, controller, table.id),
                  )
                : null,
          ),
        );
      }
    }

    // 3. Planes activos (con QR dormido si aún no tienen orden no-flash en curso hoy)
    final isOrderFlash = order != null && controller.isFlashOfferOrder(order);
    for (final pass in frontPasses) {
      final alreadyShownWithPlanOrder = order != null &&
          !order.isDelivered &&
          !isOrderFlash &&
          order.restaurantId == pass.restaurantId;
      if (alreadyShownWithPlanOrder) continue;

      final menuAvail = state.menuAvailabilityFor(pass.restaurantId);
      final inactiveLabel = switch (menuAvail) {
        MenuAvailabilityState.sinPublicar => 'Menú sin publicar',
        MenuAvailabilityState.agotadoTotal => 'Menú agotado hoy',
        MenuAvailabilityState.disponible => 'Genera un pedido para obtener tu QR',
      };
      void openRest() => context.push('/customer/restaurants/${pass.restaurantId}');

      cards.add(
        _WalletCardData(
          keyId: 'pass:${pass.id}',
          chipLabel: 'Plan · ${pass.restaurantName}',
          chipIcon: Icons.confirmation_number_rounded,
          title: pass.restaurantName,
          orderType: BocadooOrderCardType.preorderWithPlan,
          availableLunches: pass.remainingLunches,
          hasActiveOrderQr: false,
          inactiveQrLabel: inactiveLabel,
          statusBadgeLabel: 'Plan Activo',
          actionLabel: 'PEDIR HOY',
          shortRestaurantId: pass.restaurantId,
          onViewStatus: openRest,
          onTapInactiveQr: openRest,
          contextualFooter: switch (menuAvail) {
            MenuAvailabilityState.sinPublicar => _MenuNotPublishedQrBlock(
                restaurantId: pass.restaurantId,
                onRefresh: () => controller.loadDashboard(silent: true),
              ),
            MenuAvailabilityState.agotadoTotal => _MenuSoldOutQrBlock(
                restaurantId: pass.restaurantId,
                hasReservedOrder: false,
                onOpenOrderQr: null,
                onRefresh: () => controller.loadDashboard(silent: true),
              ),
            MenuAvailabilityState.disponible => null,
          },
        ),
      );
    }

    // 4. Tarjetas temporales de solicitud de plan ("Pendiente de aprobación")
    for (final pending in state.pendingPlanRequests) {
      final hasActiveHere = frontPasses.any(
        (p) => p.restaurantId == pending.plan.restaurantId,
      );
      if (hasActiveHere) continue;

      cards.add(
        _WalletCardData(
          keyId: 'pending:${pending.plan.restaurantId}',
          chipLabel: 'Pendiente · ${pending.restaurant.name}',
          chipIcon: Icons.hourglass_top_rounded,
          title: pending.restaurant.name,
          orderType: BocadooOrderCardType.preorderWithPlan,
          availableLunches: pending.plan.lunches,
          metricLabelOverride: 'Plan solicitado',
          metricValueOverride: '${pending.plan.lunches} almuerzos',
          extraPillLabelOverride: '${formatCents(pending.plan.priceCents)} en caja',
          hasActiveOrderQr: false,
          inactiveQrLabel: 'Esperando aprobación en caja',
          dormantQrIcon: Icons.hourglass_top_rounded,
          statusBadgeLabel: 'Pendiente de aprobación',
          statusBadgeIcon: Icons.hourglass_top_rounded,
          actionLabel: 'VER ESTADO',
          shortRestaurantId: pending.restaurant.id,
          onViewStatus: () =>
              _showPendingPlanStatusSheet(context, controller, pending),
          onTapInactiveQr: () =>
              _showPendingPlanStatusSheet(context, controller, pending),
        ),
      );
    }

    return cards;
  }

  Future<void> _showPendingPlanStatusSheet(
    BuildContext context,
    CustomerController controller,
    PendingPlanRequest pending,
  ) async {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final textTheme = Theme.of(context).textTheme;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: b.walletAccent.withValues(alpha: 0.28),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      color: b.onWalletAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Solicitud pendiente de aprobación',
                          style: (textTheme.titleMedium ?? const TextStyle())
                              .copyWith(
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          pending.restaurant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (textTheme.bodySmall ?? const TextStyle())
                              .copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.36),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pending.plan.name} · ${pending.plan.lunches} almuerzos',
                      style: (textTheme.titleSmall ?? const TextStyle())
                          .copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monto a cancelar en caja: ${formatCents(pending.plan.priceCents)}',
                      style: (textTheme.bodyMedium ?? const TextStyle())
                          .copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tu solicitud ya fue enviada al dueño del restaurante. Cuando realices el pago en caja y la aprueben, esta tarjeta se convertirá automáticamente en tu Plan Activo.',
                      style: (textTheme.bodySmall ?? const TextStyle())
                          .copyWith(
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  controller.refreshLive();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Actualizar estado'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await controller
                      .dismissPendingPlanRequest(pending.plan.restaurantId);
                },
                icon: Icon(Icons.close_rounded, size: 18, color: colors.error),
                label: Text(
                  'Cancelar solicitud',
                  style: TextStyle(color: colors.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancelGroupTable(
    BuildContext context,
    CustomerController controller,
    String tableId,
  ) async {
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
    final ok = await controller.cancelSharedTable(tableId);
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
  }

  @override
  Widget build(BuildContext context) {
    final cards = _buildCards(context);
    final hasAnyCard = cards.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showYellowDiscover)
          Align(
            alignment: Alignment.topCenter,
            heightFactor: hasAnyCard ? 0.78 : 1.0,
            child: _DiscoverWalletTab(
              onTap: () => context.go('/customer/restaurants'),
            ),
          ),
        if (hasAnyCard)
          _WalletCardStack(
            cards: cards,
            focusedCardKey: state.focusedWalletCardKey,
            focusTick: state.walletFocusTick,
          )
        else
          const _EmptyPlanPrompt(),
      ],
    );
  }
}

/// Mazo interactivo tipo Apple Wallet con apilamiento vertical escalonado,
/// toque directo en pestañas traseras y swipe horizontal cíclico sin conflicto con scroll vertical.
class _WalletCardStack extends StatefulWidget {
  const _WalletCardStack({
    required this.cards,
    required this.focusedCardKey,
    required this.focusTick,
  });

  final List<_WalletCardData> cards;
  final String? focusedCardKey;
  final int focusTick;

  @override
  State<_WalletCardStack> createState() => _WalletCardStackState();
}

class _WalletCardStackState extends State<_WalletCardStack>
    with SingleTickerProviderStateMixin {
  static const double _peekOffset = 46.0;
  static const double _cardHeight = 232.0;
  static const int _maxVisibleLayers = 4;

  late final AnimationController _swipeAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<double>? _offsetTween;

  List<String> _orderedKeys = [];
  int _lastHandledTick = -1;
  double _dragOffsetX = 0.0;
  bool _pendingRotate = false;

  @override
  void initState() {
    super.initState();
    _swipeAnim.addListener(() {
      if (!mounted || _offsetTween == null) return;
      setState(() => _dragOffsetX = _offsetTween!.value);
    });
    _swipeAnim.addStatusListener((status) {
      if (status == AnimationStatus.completed && _pendingRotate) {
        _pendingRotate = false;
        if (mounted) {
          setState(() {
            if (_orderedKeys.length > 1) {
              final first = _orderedKeys.removeAt(0);
              _orderedKeys.add(first);
            }
            _dragOffsetX = 0.0;
          });
        }
      }
    });
    _syncOrder(initial: true);
  }

  @override
  void didUpdateWidget(covariant _WalletCardStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOrder(initial: false);
  }

  @override
  void dispose() {
    _swipeAnim.dispose();
    super.dispose();
  }

  void _syncOrder({required bool initial}) {
    final incomingKeys = [for (final c in widget.cards) c.keyId];
    final next = [for (final k in _orderedKeys) if (incomingKeys.contains(k)) k];
    for (final k in incomingKeys) {
      if (!next.contains(k)) {
        if (k == widget.focusedCardKey) {
          next.insert(0, k);
        } else {
          next.add(k);
        }
      }
    }

    if (widget.focusTick != _lastHandledTick || initial) {
      _lastHandledTick = widget.focusTick;
      final fk = widget.focusedCardKey;
      if (fk != null && next.contains(fk)) {
        next.remove(fk);
        next.insert(0, fk);
      }
    }

    _orderedKeys = next;
  }

  void _bringToFront(String keyId) {
    if (_orderedKeys.isEmpty || _orderedKeys.first == keyId) return;
    _swipeAnim.stop();
    _pendingRotate = false;
    setState(() {
      _dragOffsetX = 0.0;
      _orderedKeys.remove(keyId);
      _orderedKeys.insert(0, keyId);
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_orderedKeys.length < 2 || _pendingRotate) return;
    setState(() {
      _dragOffsetX = (_dragOffsetX + details.delta.dx).clamp(-260.0, 260.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_orderedKeys.length < 2 || _pendingRotate) return;
    final vx = details.velocity.pixelsPerSecond.dx;
    final shouldRotate = _dragOffsetX.abs() > 72 || vx.abs() > 420;
    if (shouldRotate) {
      final dir = _dragOffsetX == 0 ? (vx >= 0 ? 1.0 : -1.0) : _dragOffsetX.sign;
      final width = MediaQuery.sizeOf(context).width;
      _pendingRotate = true;
      _offsetTween = Tween<double>(
        begin: _dragOffsetX,
        end: dir * width,
      ).animate(
        CurvedAnimation(parent: _swipeAnim, curve: Curves.easeOutCubic),
      );
      _swipeAnim.forward(from: 0);
    } else {
      _pendingRotate = false;
      _offsetTween = Tween<double>(
        begin: _dragOffsetX,
        end: 0.0,
      ).animate(
        CurvedAnimation(parent: _swipeAnim, curve: Curves.easeOutCubic),
      );
      _swipeAnim.forward(from: 0);
    }
  }

  void _onHorizontalDragCancel() {
    if (_pendingRotate || _dragOffsetX == 0) return;
    _offsetTween = Tween<double>(
      begin: _dragOffsetX,
      end: 0.0,
    ).animate(
      CurvedAnimation(parent: _swipeAnim, curve: Curves.easeOutCubic),
    );
    _swipeAnim.forward(from: 0);
  }

  List<Color> _gradientForDepth(int depth) => switch (depth) {
        0 => const [Color(0xFFBFBBF5), Color(0xFF7B2CBF)],
        1 => const [Color(0xFF9E82DC), Color(0xFF61209E)],
        2 => const [Color(0xFF7C5BC2), Color(0xFF4A148C)],
        _ => const [Color(0xFF6342A8), Color(0xFF380D6E)],
      };

  List<BoxShadow> _shadowForDepth(int depth) => [
        BoxShadow(
          color: const Color(0xFF1F063D).withValues(alpha: depth == 0 ? 0.28 : 0.18),
          blurRadius: depth == 0 ? 22 : 10,
          offset: Offset(0, depth == 0 ? -4 : -2),
        ),
        if (depth == 0)
          BoxShadow(
            color: const Color(0xFF7B2CBF).withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final byKey = {for (final c in widget.cards) c.keyId: c};
    final orderedCards = [
      for (final k in _orderedKeys)
        if (byKey[k] != null) byKey[k]!,
    ];
    if (orderedCards.isEmpty) return const SizedBox.shrink();

    final frontCard = orderedCards.first;
    final visibleCount = orderedCards.length.clamp(1, _maxVisibleLayers);
    final stackHeight = _cardHeight + (visibleCount - 1) * _peekOffset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: stackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Pintamos desde la capa más trasera (depth = visibleCount - 1) hasta el frente (depth = 0).
              for (var depth = visibleCount - 1; depth >= 0; depth--)
                () {
                  final card = orderedCards[depth];
                  final topOffset = (visibleCount - 1 - depth) * _peekOffset;
                  final scale = (1.0 - depth * 0.025).clamp(0.90, 1.0);
                  final isFront = depth == 0;

                  Widget cardWidget = SizedBox(
                    height: _cardHeight,
                    child: BocadooOrderCard(
                      restaurantName: card.title,
                      orderType: card.orderType,
                      totalCents: card.totalCents,
                      availableLunches: card.availableLunches,
                      scheduledTime: card.scheduledTime,
                      extraCashCents: card.extraCashCents,
                      qrPayload: card.qrData,
                      hasActiveOrderQr: card.hasActiveOrderQr,
                      inactiveQrLabel: card.inactiveQrLabel,
                      statusBadgeLabel: card.statusBadgeLabel,
                      statusBadgeIcon: card.statusBadgeIcon,
                      metricLabelOverride: card.metricLabelOverride,
                      metricValueOverride: card.metricValueOverride,
                      extraPillLabelOverride: card.extraPillLabelOverride,
                      dormantQrIcon: card.dormantQrIcon,
                      actionLabel: card.actionLabel,
                      gradientColors: _gradientForDepth(depth),
                      boxShadow: _shadowForDepth(depth),
                      onTapQr: isFront && card.hasActiveOrderQr
                          ? () => _showZoomedQr(
                                context,
                                card.qrData,
                                card.title,
                                restaurantId: card.shortRestaurantId,
                                badgeOverride: card.displayCodeOverride,
                              )
                          : null,
                      onTapInactiveQr: isFront ? card.onTapInactiveQr : null,
                      onTapViewStatus:
                          isFront ? card.onViewStatus : () => _bringToFront(card.keyId),
                    ),
                  );

                  if (isFront) {
                    final screenW = MediaQuery.sizeOf(context).width;
                    final opacity =
                        (1.0 - (_dragOffsetX.abs() / screenW) * 0.45).clamp(0.55, 1.0);
                    cardWidget = GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: _onHorizontalDragUpdate,
                      onHorizontalDragEnd: _onHorizontalDragEnd,
                      onHorizontalDragCancel: _onHorizontalDragCancel,
                      child: Transform.translate(
                        offset: Offset(_dragOffsetX, 0),
                        child: Transform.rotate(
                          angle: _dragOffsetX * 0.0005,
                          child: Opacity(opacity: opacity, child: cardWidget),
                        ),
                      ),
                    );
                  } else {
                    cardWidget = GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _bringToFront(card.keyId),
                      child: AbsorbPointer(child: cardWidget),
                    );
                  }

                  return AnimatedPositioned(
                    key: ValueKey('wallet_layer_${card.keyId}'),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    top: topOffset,
                    left: 0,
                    right: 0,
                    child: AnimatedScale(
                      scale: scale,
                      alignment: Alignment.topCenter,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: cardWidget,
                    ),
                  );
                }(),
            ],
          ),
        ),
        if (widget.cards.length >= 2) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final card in widget.cards)
                GestureDetector(
                  onTap: () => _bringToFront(card.keyId),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: card.keyId == frontCard.keyId ? 24 : 10,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: card.keyId == frontCard.keyId
                          ? colors.primary
                          : colors.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (frontCard.contextualFooter != null) ...[
          const SizedBox(height: 12),
          frontCard.contextualFooter!,
        ],
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

