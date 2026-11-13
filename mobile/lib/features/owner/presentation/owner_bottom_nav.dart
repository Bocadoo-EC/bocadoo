import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/widgets.dart';

/// Barra de navegación inferior para Dueño (5 pestañas) y Cajero (3 pestañas).
class OwnerBottomNav extends ConsumerWidget {
  final String currentRoute;

  const OwnerBottomNav({
    super.key,
    required this.currentRoute,
  });

  static const List<({String route, BocadooNavItem item})> _ownerTabs = [
    (
      route: '/owner/scanner',
      item: BocadooNavItem(
        label: 'Caja',
        icon: Icons.qr_code_scanner_outlined,
        selectedIcon: Icons.qr_code_scanner_rounded,
      ),
    ),
    (
      route: '/owner/menu',
      item: BocadooNavItem(
        label: 'Menú',
        icon: Icons.restaurant_menu_outlined,
        selectedIcon: Icons.restaurant_menu_rounded,
      ),
    ),
    (
      route: '/owner/plans',
      item: BocadooNavItem(
        label: 'Planes',
        icon: Icons.confirmation_number_outlined,
        selectedIcon: Icons.confirmation_number_rounded,
      ),
    ),
    (
      route: '/owner/metrics',
      item: BocadooNavItem(
        label: 'Métricas',
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart_rounded,
      ),
    ),
    (
      route: '/owner/settings',
      item: BocadooNavItem(
        label: 'Ajustes',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ),
  ];

  static const List<({String route, BocadooNavItem item})> _cashierTabs = [
    (
      route: '/owner/scanner',
      item: BocadooNavItem(
        label: 'Caja',
        icon: Icons.qr_code_scanner_outlined,
        selectedIcon: Icons.qr_code_scanner_rounded,
      ),
    ),
    (
      route: '/owner/orders',
      item: BocadooNavItem(
        label: 'Pedidos',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
      ),
    ),
    (
      route: '/owner/settings',
      item: BocadooNavItem(
        label: 'Turno',
        icon: Icons.schedule_outlined,
        selectedIcon: Icons.schedule_rounded,
      ),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider).user?.role ?? AuthRole.owner;
    final tabs = role == AuthRole.cashier ? _cashierTabs : _ownerTabs;
    final currentIndex = tabs
        .indexWhere((tab) => tab.route == currentRoute)
        .clamp(0, tabs.length - 1);

    return BocadooBottomNavBar(
      currentIndex: currentIndex,
      items: tabs.map((t) => t.item).toList(),
      onTap: (index) {
        final target = tabs[index].route;
        if (target == currentRoute) return;
        context.go(target);
      },
    );
  }
}

