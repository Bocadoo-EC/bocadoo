import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/bottom_nav_bar.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';

const _tabs = [
  ('/customer/pase', BocadooNavItem(label: 'Pase', icon: Icons.qr_code_2_rounded, selectedIcon: Icons.qr_code_2_rounded)),
  ('/customer/restaurants', BocadooNavItem(label: 'Restaurantes', icon: Icons.storefront_outlined, selectedIcon: Icons.storefront_rounded)),
  ('/customer/planes', BocadooNavItem(label: 'Planes', icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet_rounded)),
  ('/customer/cuenta', BocadooNavItem(label: 'Yo', icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded)),
];

/// Marco común de Mi Pase, Dónde comer, Planes y Mi cuenta.
class CustomerShell extends ConsumerWidget {
  final String location;
  final Widget child;

  const CustomerShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(customerControllerProvider);
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
