import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';

const _tabs = [
  ('/customer/pase', BocadooNavItem(label: 'Pase', icon: Icons.qr_code_2_rounded, selectedIcon: Icons.qr_code_2_rounded)),
  ('/customer/restaurants', BocadooNavItem(label: 'Restaurantes', icon: Icons.storefront_outlined, selectedIcon: Icons.storefront_rounded)),
  ('/customer/planes', BocadooNavItem(label: 'Planes', icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet_rounded)),
  ('/customer/cuenta', BocadooNavItem(label: 'Yo', icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded)),
];

/// Marco común de Mi Pase, Dónde comer, Planes y Mi cuenta. Al entrar refresca
/// lo que pudo cambiar en caja y avisa si el pedido ya fue entregado.
class CustomerShell extends ConsumerStatefulWidget {
  final String location;
  final Widget child;

  const CustomerShell({super.key, required this.location, required this.child});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  late final CustomerController _controller = ref.read(customerControllerProvider);
  String? _announcedOrder;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_checkDelivered);
    _controller.refreshLive();
  }

  @override
  void dispose() {
    _controller.removeListener(_checkDelivered);
    super.dispose();
  }

  void _checkDelivered() {
    final order = _controller.state.activeOrder;
    if (order == null || !order.isDelivered || _announcedOrder == order.orderNumber) return;
    _announcedOrder = order.orderNumber;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => DeliveredOrderSheet(order: order),
      );
      await _controller.acknowledgeDelivery();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final location = widget.location;
    final child = widget.child;
    final index = _tabs.indexWhere((t) => location.startsWith(t.$1));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(children: [
        Positioned.fill(child: child),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final undo = controller.state.undo;
              if (undo == null) return const SizedBox.shrink();
              return UndoBanner(
                label: undo.label,
                secondsLeft: undo.secondsLeft,
                onUndo: () {
                  final messenger = ScaffoldMessenger.of(context);
                  final wasPlan = undo.label.startsWith('Plan');
                  controller.undo();
                  if (wasPlan) {
                    messenger.showSnackBar(const SnackBar(content: Text('Solicitud de plan cancelada')));
                  }
                },
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: BocadooBottomNavBar(
        currentIndex: index < 0 ? 0 : index,
        items: [for (final t in _tabs) t.$2],
        onTap: (i) => context.go(_tabs[i].$1),
      ),
    );
  }
}

/// "Tu pedido · Entregado": la caja ya cobró y entregó la preorden (O12 → C8).
class DeliveredOrderSheet extends StatelessWidget {
  const DeliveredOrderSheet({super.key, required this.order});

  final ActiveOrder order;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final paid = (order.paidAmount ?? order.singleLunchPrice).toStringAsFixed(2).replaceAll('.', ',');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('Tu pedido',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
            ),
            IconButton.filledTonal(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: b.success,
              child: Icon(Icons.check_rounded, size: 40, color: b.successForeground),
            ),
          ),
          const SizedBox(height: 14),
          Text('Entregado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text(
              order.hasPlan
                  ? 'Buen provecho. Se descontó 1 almuerzo de tu plan.'
                  : 'Buen provecho. Pagaste \$$paid en efectivo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Pedido #${order.orderNumber} · ${order.restaurantName}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Muestra una ruta de go_router como hoja inferior (C3 y C5).
class BottomSheetPage<T> extends Page<T> {
  final Widget child;

  const BottomSheetPage({required this.child, super.key, super.name});

  @override
  Route<T> createRoute(BuildContext context) {
    return ModalBottomSheetRoute<T>(
      settings: this,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => child,
    );
  }
}
