import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Descriptor de cada pestaña de [BocadooBottomNavBar].
class BocadooNavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const BocadooNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// Barra de navegación inferior Material 3 adaptada a la identidad Bocadoo:
/// - Fondo `surfaceNav`
/// - Pastilla activa `primaryContainer` con ícono y etiqueta en `onPrimaryContainer`
/// - Pestañas inactivas en `mutedForeground` (`onSurfaceVariant`)
class BocadooBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final List<BocadooNavItem> items;
  final ValueChanged<int> onTap;

  const BocadooBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bColor = context.bocadooColors;

    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: bColor.surfaceNav,
        indicatorColor: colors.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        elevation: 0,
        destinations: items
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

