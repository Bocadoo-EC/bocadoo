import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/bottom_nav_bar.dart';

const _tabs = [
  ('/owner/caja', BocadooNavItem(label: 'Caja', icon: Icons.qr_code_2_rounded, selectedIcon: Icons.qr_code_2_rounded)),
  ('/owner/menu', BocadooNavItem(label: 'Menú', icon: Icons.restaurant_outlined, selectedIcon: Icons.restaurant_rounded)),
  ('/owner/planes', BocadooNavItem(label: 'Planes', icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded)),
  ('/owner/metricas', BocadooNavItem(label: 'Métricas', icon: Icons.bar_chart_rounded, selectedIcon: Icons.bar_chart_rounded)),
  ('/owner/settings', BocadooNavItem(label: 'Ajustes', icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded)),
];

/// Marco común del dueño. El POS y el cierre cuelgan de la pestaña Caja.
class OwnerShell extends StatelessWidget {
  const OwnerShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexWhere((t) => location.startsWith(t.$1));
    return Scaffold(
      body: child,
      bottomNavigationBar: BocadooBottomNavBar(
        currentIndex: index < 0 ? 0 : index,
        items: [for (final t in _tabs) t.$2],
        onTap: (i) => context.go(_tabs[i].$1),
      ),
    );
  }
}

/// Muestra una ruta como hoja inferior (O3 Vender plan, O11 Oferta flash).
class OwnerSheetPage<T> extends Page<T> {
  const OwnerSheetPage({required this.child, super.key, super.name});

  final Widget child;

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
