import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/widgets.dart';

/// Barra de navegación inferior compartida por las pantallas del Comensal.
class CustomerBottomNav extends StatelessWidget {
  final int currentIndex;

  const CustomerBottomNav({
    super.key,
    required this.currentIndex,
  });

  static const List<BocadooNavItem> _items = [
    BocadooNavItem(
      label: 'Mi Pase',
      icon: Icons.qr_code_2_outlined,
      selectedIcon: Icons.qr_code_2_rounded,
    ),
    BocadooNavItem(
      label: 'Dónde comer',
      icon: Icons.restaurant_outlined,
      selectedIcon: Icons.restaurant_rounded,
    ),
    BocadooNavItem(
      label: 'Planes',
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number_rounded,
    ),
    BocadooNavItem(
      label: 'Yo',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return BocadooBottomNavBar(
      currentIndex: currentIndex,
      items: _items,
      onTap: (index) {
        if (index == currentIndex) return;
        switch (index) {
          case 0:
            context.go('/customer/pase');
          case 1:
            context.go('/customer/restaurants');
          case 2:
            context.go('/customer/plans');
          case 3:
            context.go('/customer/profile');
        }
      },
    );
  }
}

