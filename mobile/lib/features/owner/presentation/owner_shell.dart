import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bottom_nav_bar.dart';
import '../domain/models/daily_menu.dart';
import '../domain/models/extras_models.dart';
import '../domain/models/menu_models.dart';
import 'owner_controller.dart';

const _ownerTabs = [
  (
    '/owner/menu',
    BocadooNavItem(
      label: 'Menú',
      icon: Icons.restaurant_outlined,
      selectedIcon: Icons.restaurant_rounded,
    ),
  ),
  (
    '/owner/planes',
    BocadooNavItem(
      label: 'Planes',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
    ),
  ),
  (
    '/owner/caja',
    BocadooNavItem(
      label: 'Caja',
      icon: Icons.qr_code_scanner_rounded,
      selectedIcon: Icons.qr_code_scanner_rounded,
    ),
  ),
  (
    '/owner/metricas',
    BocadooNavItem(
      label: 'Métricas',
      icon: Icons.bar_chart_rounded,
      selectedIcon: Icons.bar_chart_rounded,
    ),
  ),
  (
    '/owner/settings',
    BocadooNavItem(
      label: 'Ajustes',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ),
];

/// Barra del cajero o ayudante (como el prototipo): Caja, Pedidos y Turno.
const _cashierTabs = [
  (
    '/owner/caja',
    BocadooNavItem(
      label: 'Caja',
      icon: Icons.qr_code_2_rounded,
      selectedIcon: Icons.qr_code_2_rounded,
    ),
  ),
  (
    '/owner/pedidos',
    BocadooNavItem(
      label: 'Pedidos',
      icon: Icons.schedule_outlined,
      selectedIcon: Icons.schedule_rounded,
    ),
  ),
  (
    '/owner/settings',
    BocadooNavItem(
      label: 'Turno',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ),
];

/// Marco común del dueño. El POS, el cierre y los pedidos cuelgan de Caja. La
/// barra cambia según el rol del dispositivo (O16).
class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends ConsumerState<OwnerShell> {
  String? _checkedRestaurantId;

  void _maybeShowOnboarding({
    required String restaurantId,
    required DailyMenu? todayMenu,
    required List<CatalogDish> dishes,
    required PermanentCatalogState permanentState,
  }) {
    final rid = restaurantId.trim();
    if (rid.isEmpty || _checkedRestaurantId == rid) return;
    _checkedRestaurantId = rid;

    final hasPublishedMenu = todayMenu?.isPublished == true;
    final hasTodayCourses = todayMenu != null && todayMenu.courses.isNotEmpty;
    final isBrandNew =
        !hasPublishedMenu &&
        !hasTodayCourses &&
        dishes.isEmpty &&
        permanentState.items.isEmpty;
    if (!isBrandNew) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'owner_onboarding_done_$rid';
      if (prefs.getBool(key) == true || !mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _OwnerOnboardingDialog(),
      );
      await prefs.setBool(key, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCashier = ref.watch(ownerRoleProvider) == OwnerRole.cashier;
    if (!isCashier) {
      final rid = ref.watch(ownerRestaurantIdProvider);
      final posMenuAsync = ref.watch(posMenuProvider);
      final dishesAsync = ref.watch(catalogDishesProvider);
      final permanentState = ref.watch(permanentCatalogProvider);
      if (posMenuAsync.hasValue &&
          !posMenuAsync.isLoading &&
          dishesAsync.hasValue &&
          !dishesAsync.isLoading) {
        _maybeShowOnboarding(
          restaurantId: rid,
          todayMenu: posMenuAsync.value,
          dishes: dishesAsync.value ?? const <CatalogDish>[],
          permanentState: permanentState,
        );
      }
    }

    final tabs = isCashier ? _cashierTabs : _ownerTabs;
    final rawIndex = tabs.indexWhere((t) => widget.location.startsWith(t.$1));
    final fallbackIndex = isCashier ? 0 : 2; // Caja al centro para Dueño
    final currentIndex = rawIndex < 0 ? fallbackIndex : rawIndex;

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: isCashier
          ? BocadooBottomNavBar(
              currentIndex: currentIndex,
              items: [for (final t in tabs) t.$2],
              onTap: (i) => context.go(tabs[i].$1),
            )
          : _OwnerCenterBottomBar(
              currentIndex: currentIndex,
              items: [for (final t in tabs) t.$2],
              onTap: (i) => context.go(tabs[i].$1),
            ),
    );
  }
}

/// Barra inferior del Dueño con `Caja` en el centro (posición 3 de 5) como
/// acción principal destacada en el morado de marca de Bocadoo.
class _OwnerCenterBottomBar extends StatelessWidget {
  const _OwnerCenterBottomBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<BocadooNavItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bColors = context.bocadooColors;

    return Material(
      color: bColors.surfaceNav,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 70),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: i == 2
                          ? _CenterCajaTab(
                              selected: currentIndex == i,
                              label: items[i].label,
                              onTap: () => onTap(i),
                            )
                          : _StandardNavTab(
                              item: items[i],
                              selected: currentIndex == i,
                              onTap: () => onTap(i),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterCajaTab extends StatelessWidget {
  const _CenterCajaTab({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.lightPrimary,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: cs.primaryContainer, width: 2.5)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.lightPrimary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: AppColors.lightOnPrimary,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StandardNavTab extends StatelessWidget {
  const _StandardNavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BocadooNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? cs.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 22,
                color: fg,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStepData {
  const _OnboardingStepData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// Guía de bienvenida de 4 pasos exclusiva para dueños de restaurantes nuevos
/// (0 platos y sin menú publicado, controlada por `owner_onboarding_done_<id>`).
class _OwnerOnboardingDialog extends StatefulWidget {
  const _OwnerOnboardingDialog();

  @override
  State<_OwnerOnboardingDialog> createState() => _OwnerOnboardingDialogState();
}

class _OwnerOnboardingDialogState extends State<_OwnerOnboardingDialog> {
  static const _steps = <_OnboardingStepData>[
    _OnboardingStepData(
      icon: Icons.restaurant_menu_rounded,
      title: '1. Carga tu menú del día',
      description:
          'En Menú agrega tus sopas, segundos, bebidas y postres disponibles y toca Publicar menú de hoy para que los comensales los vean.',
    ),
    _OnboardingStepData(
      icon: Icons.inventory_2_rounded,
      title: '2. Configura tus planes',
      description:
          'En Planes crea paquetes prepagados (ej. 10 o 20 almuerzos) para fidelizar clientes y asegurar ingresos por adelantado.',
    ),
    _OnboardingStepData(
      icon: Icons.qr_code_scanner_rounded,
      title: '3. Tu Caja es el centro de todo',
      description:
          'Destaca el botón central morado Caja: ahí escanearás códigos QR, entregarás pedidos en camino y registrarás ventas rápidas.',
    ),
    _OnboardingStepData(
      icon: Icons.bar_chart_rounded,
      title: '4. Controla tus métricas y cierre',
      description:
          'En Métricas y Ajustes podrás revisar tus ingresos del día, hacer cierre de caja y editar horarios o precios cuando quieras.',
    ),
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final step = _steps[_index];
    final isLast = _index == _steps.length - 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    ),
                    child: Text(
                      '${_index + 1} de ${_steps.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Omitir guía'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(step.icon, size: 34, color: cs.primary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                step.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                step.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? cs.primary : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (isLast) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => _index += 1);
                  }
                },
                child: Text(isLast ? '¡Empezar ahora!' : 'Siguiente'),
              ),
            ],
          ),
        ),
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
