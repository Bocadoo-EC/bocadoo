import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart' show formatCents, formatMoney;
import 'social_widgets.dart';

/// C8 · Estado del pedido: QR de la preorden y cómo se valida en caja.
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
    final controller = ref.watch(customerControllerProvider);
    final order = controller.state.activeOrder;
    final found = order != null && order.orderNumber == widget.orderId;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * (found ? 0.9 : 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Tu pedido', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
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
      ]),
    );
  }

  Widget _content(ActiveOrder order) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final left = order.expiresAt?.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    final countdown = left == null || expired
        ? null
        : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final ready = order.status == 'LISTO';
    final muted = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.35, color: colors.onSurfaceVariant);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: colors.outlineVariant),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Theme.of(context).scaffoldBackgroundColor, colors.primaryContainer],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SocialBadge(label: 'Orden #${order.orderNumber}', background: colors.primary, foreground: colors.onPrimary),
            const Spacer(),
            SocialBadge(
              label: expired ? 'Vencida' : (countdown == null ? 'Guardada' : 'Vence en $countdown'),
              icon: Icons.schedule_rounded,
              background: colors.surface,
              foreground: expired ? b.danger : colors.primary,
            ),
          ]),
          const SizedBox(height: 10),
          Text(order.restaurantName,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 2),
          Text(
            ready
                ? 'Listo para retirar · Acércate al mostrador con tu número de orden.'
                : 'En preparación · Tu almuerzo se está sirviendo en la cocina.',
            style: muted,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (order.soup != null) _Line(label: 'Sopa:', value: order.soup!),
              if (order.main != null) _Line(label: 'Segundo:', value: order.main!),
              if (order.soup == null && order.main == null && order.detail.isNotEmpty)
                _Line(label: 'Pedido:', value: order.detail),
              const SizedBox(height: 4),
              Row(children: [
                Icon(order.takeaway ? Icons.takeout_dining_outlined : Icons.restaurant_rounded,
                    size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.takeaway
                        ? 'Modalidad: Para llevar (+ ${formatCents(order.effectiveSurchargeCents)})'
                        : 'Modalidad: Para comer en el local',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              if (order.estimatedArrivalLabel != null && order.estimatedArrivalLabel!.isNotEmpty)
                _Line(label: 'Hora estimada:', value: order.estimatedArrivalLabel!),
              _Line(
                label: 'Total en caja:',
                value: order.hasPlan
                    ? 'Cubierto por tu plan (\$0,00)'
                    : '${formatCents(order.effectiveTotalCents)} en efectivo',
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(children: [
          Text('Muestra este QR en la caja al llegar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.primary)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: b.qrBackground,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: SocialQr(
              value: BocadooQrParser.generateOrderCode(order.orderNumber, orderId: order.id),
              size: 150,
            ),
          ),
          const SizedBox(height: 10),
          SocialBadge(
            label: BocadooQrParser.generateOrderCode(order.orderNumber, orderId: order.id),
            background: colors.primaryContainer,
            foreground: colors.primary,
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('¿Cómo se valida en el restaurante?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 10),
          _Rule(
            icon: Icons.verified_user_outlined,
            color: b.success,
            title: 'Si tienes plan activo:',
            text: 'El cajero escanea tu QR y se descuenta 1 almuerzo de tu saldo. Pagas \$0,00 adicionales.',
            yours: order.hasPlan,
          ),
          const SizedBox(height: 10),
          _Rule(
            icon: Icons.payments_outlined,
            color: colors.primary,
            title: 'Si no tienes plan (cobro suelto):',
            text: 'El cajero escanea tu QR y te cobra el almuerzo suelto '
                '(${formatMoney(order.singleLunchPrice)}) en efectivo o transferencia.',
            yours: !order.hasPlan,
          ),
        ]),
      ),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: () => context.pop(), child: const Text('Listo, voy al restaurante')),
    ]);
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label ', style: TextStyle(fontWeight: FontWeight.w900, color: colors.primary)),
          TextSpan(text: value),
        ]),
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.color, required this.title, required this.text, required this.yours});

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final bool yours;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color)),
            if (yours)
              SocialBadge(label: 'Tu caso', background: colors.primaryContainer, foreground: colors.onPrimaryContainer),
          ]),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.35, color: colors.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}
