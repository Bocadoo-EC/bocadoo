import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart' show formatCents;
import 'social_widgets.dart';

/// C8 · Estado del pedido con línea de tiempo visual (Heurísticas de Nielsen),
/// QR limpio e instrucción única contextual.
class OrderStatusSheet extends ConsumerStatefulWidget {
  const OrderStatusSheet({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderStatusSheet> createState() => _OrderStatusSheetState();
}

class _OrderStatusSheetState extends ConsumerState<OrderStatusSheet> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = ref.watch(customerControllerProvider);
    final order = controller.state.activeOrder;
    final found = order != null && order.orderNumber == widget.orderId;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * (found ? 0.88 : 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Tu pedido',
              style: (textTheme.headlineMedium ?? const TextStyle()).copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: found
                ? _content(order)
                : SocialEmpty(
                    icon: Icons.schedule_rounded,
                    title: 'Sin pedidos hoy',
                    message: 'Elige un local para almorzar.',
                    actionLabel: 'Ver locales',
                    onAction: () {
                      final router = GoRouter.of(context);
                      router.pop();
                      router.go('/customer/restaurants');
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _content(ActiveOrder order) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final textTheme = Theme.of(context).textTheme;
    final left = order.expiresAt?.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    final countdown = left == null || expired
        ? null
        : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';

    final isReady = order.status == 'LISTO' || order.status == 'ENTREGADO';
    final currentStep = isReady ? 2 : 1; // 0: Recibida, 1: En cocina, 2: Lista/En caja
    final cashToPay = order.cashToCollectCents > 0
        ? order.cashToCollectCents
        : order.effectiveTotalCents;

    final String contextualRule;
    final IconData contextualIcon;
    final Color contextualBg;
    final Color contextualFg;
    if (order.hasPlan && order.cashToCollectCents <= 0) {
      contextualIcon = Icons.verified_rounded;
      contextualBg = b.successContainer.withValues(alpha: 0.72);
      contextualFg = b.onSuccessContainer;
      contextualRule =
          'Presenta este QR en caja para descontar 1 almuerzo de tu plan (\$0,00 a pagar).';
    } else if (order.hasPlan && order.cashToCollectCents > 0) {
      contextualIcon = Icons.payments_outlined;
      contextualBg = colors.primaryContainer.withValues(alpha: 0.65);
      contextualFg = colors.onPrimaryContainer;
      contextualRule =
          'Presenta este QR en caja para descontar 1 almuerzo de tu plan y pagar ${formatCents(order.cashToCollectCents)} adicionales.';
    } else {
      contextualIcon = Icons.payments_outlined;
      contextualBg = colors.primaryContainer.withValues(alpha: 0.65);
      contextualFg = colors.onPrimaryContainer;
      contextualRule =
          'Presenta este QR en caja y cancela ${formatCents(cashToPay)} en efectivo o transferencia.';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // Tarjeta superior: cabecera + línea de tiempo + resumen compacto
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: colors.outlineVariant),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).scaffoldBackgroundColor,
                colors.primaryContainer.withValues(alpha: 0.55),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SocialBadge(
                    label: 'Orden #${order.orderNumber}',
                    background: colors.primary,
                    foreground: colors.onPrimary,
                  ),
                  const Spacer(),
                  SocialBadge(
                    label: expired
                        ? 'Vencida'
                        : (countdown == null ? 'Activa' : 'Vence en $countdown'),
                    icon: Icons.schedule_rounded,
                    background: colors.surface,
                    foreground: expired ? b.danger : colors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                order.restaurantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (textTheme.titleLarge ?? const TextStyle()).copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              _OrderStatusTimeline(
                currentStep: currentStep,
                isDoneFinal: order.isDelivered,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.soup != null && order.soup!.trim().isNotEmpty)
                      _SummaryRow(
                        icon: Icons.soup_kitchen_outlined,
                        label: 'Sopa',
                        value: order.soup!,
                      ),
                    if (order.main != null && order.main!.trim().isNotEmpty)
                      _SummaryRow(
                        icon: Icons.dinner_dining_outlined,
                        label: 'Segundo',
                        value: order.main!,
                      ),
                    if ((order.soup == null || order.soup!.trim().isEmpty) &&
                        (order.main == null || order.main!.trim().isEmpty) &&
                        order.detail.trim().isNotEmpty)
                      _SummaryRow(
                        icon: Icons.restaurant_menu_rounded,
                        label: 'Pedido',
                        value: order.detail,
                      ),
                    _SummaryRow(
                      icon: order.takeaway
                          ? Icons.takeout_dining_outlined
                          : Icons.restaurant_rounded,
                      label: 'Modalidad',
                      value: order.takeaway
                          ? 'Para llevar (+${formatCents(order.effectiveSurchargeCents)})'
                          : 'Para comer en el local',
                    ),
                    if (order.estimatedArrivalLabel != null &&
                        order.estimatedArrivalLabel!.trim().isNotEmpty)
                      _SummaryRow(
                        icon: Icons.access_time_rounded,
                        label: 'Hora estimada',
                        value: order.estimatedArrivalLabel!,
                      ),
                    _SummaryRow(
                      icon: order.hasPlan
                          ? Icons.confirmation_number_outlined
                          : Icons.payments_outlined,
                      label: 'Total en caja',
                      value: order.hasPlan
                          ? (order.cashToCollectCents > 0
                              ? '1 cupo + ${formatCents(order.cashToCollectCents)}'
                              : 'Plan Activo (\$0,00)')
                          : formatCents(cashToPay),
                      highlightValue: true,
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Tarjeta central QR limpia (sin píldora duplicada #X)
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              Text(
                'Muestra este QR en la caja al llegar',
                textAlign: TextAlign.center,
                style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: b.qrBackground,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: SocialQr(
                  value: AppMode.useMock
                      ? BocadooQrParser.generateOrderCode(
                          order.orderNumber,
                          orderId: order.id,
                        )
                      : order.qrPayload,
                  size: 162,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Única instrucción contextual (máximo 2 líneas, cero ruido visual)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: contextualBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (order.hasPlan && order.cashToCollectCents <= 0
                      ? b.success
                      : colors.primary)
                  .withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(contextualIcon, size: 22, color: contextualFg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  contextualRule,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: contextualFg,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        ElevatedButton(
          onPressed: () => context.pop(),
          child: const Text('Listo, voy al restaurante'),
        ),
      ],
    );
  }
}

class _OrderStatusTimeline extends StatelessWidget {
  const _OrderStatusTimeline({
    required this.currentStep,
    required this.isDoneFinal,
  });

  /// 0 = Recibida, 1 = En cocina, 2 = Lista / En caja.
  final int currentStep;
  final bool isDoneFinal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final textTheme = Theme.of(context).textTheme;

    const labels = ['Recibida', 'En cocina', 'Lista / En caja'];

    Widget buildNode(int index) {
      final isCompleted = index < currentStep || (index == 2 && isDoneFinal);
      final isActive = index == currentStep && !isDoneFinal;
      final bg = isCompleted
          ? b.success
          : (isActive ? colors.primary : colors.surface);
      final borderColor = isCompleted
          ? b.success
          : (isActive ? colors.primary : colors.outlineVariant);
      final fg = (isCompleted || isActive) ? colors.onPrimary : colors.onSurfaceVariant;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: isActive ? 2 : 1.5),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.28),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: isCompleted
              ? Icon(Icons.check_rounded, size: 16, color: fg)
              : (isActive
                  ? Icon(
                      index == 1
                          ? Icons.soup_kitchen_rounded
                          : Icons.notifications_active_rounded,
                      size: 14,
                      color: fg,
                    )
                  : Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        shape: BoxShape.circle,
                      ),
                    )),
        ),
      );
    }

    Widget buildTrack(bool filled) => Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: filled ? b.success : colors.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              buildNode(0),
              buildTrack(currentStep >= 1),
              buildNode(1),
              buildTrack(currentStep >= 2),
              buildNode(2),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(3, (i) {
            final isActive = i == currentStep && !isDoneFinal;
            final isDone = i < currentStep || (i == 2 && isDoneFinal);
            return Expanded(
              child: Text(
                labels[i],
                textAlign: i == 0
                    ? TextAlign.left
                    : (i == 2 ? TextAlign.right : TextAlign.center),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (textTheme.labelMedium ?? const TextStyle()).copyWith(
                  fontSize: 11.5,
                  fontWeight: (isActive || isDone) ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? colors.primary
                      : (isDone ? b.success : colors.onSurfaceVariant),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlightValue = false,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlightValue;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: colors.primary),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                fontSize: 13.5,
                fontWeight: highlightValue ? FontWeight.w800 : FontWeight.w700,
                color: highlightValue ? colors.primary : colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
