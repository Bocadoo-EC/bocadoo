import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import 'owner_bottom_nav.dart';

/// Pantalla de Ajustes del Local (Dueño) o Turno (Cajero).
class OwnerSettingsScreen extends ConsumerStatefulWidget {
  const OwnerSettingsScreen({super.key});

  @override
  ConsumerState<OwnerSettingsScreen> createState() =>
      _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends ConsumerState<OwnerSettingsScreen> {
  bool _storeOpen = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;
    final user = ref.watch(authProvider).user;
    final isCashier = user?.role == AuthRole.cashier;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(isCashier ? 'Mi turno' : 'Ajustes del local'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(
                    Icons.storefront_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCashier ? 'Caja del local' : 'Tu restaurante',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.fullName ?? 'Administrador',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (user?.email != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          user!.email,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (!isCashier) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _storeOpen
                    ? bColor.successContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _storeOpen ? 'Local abierto ahora' : 'Local cerrado',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _storeOpen
                        ? bColor.onSuccessContainer
                        : colors.onSurface,
                  ),
                ),
                subtitle: Text(
                  _storeOpen
                      ? 'Visible para comensales en Dónde comer.'
                      : 'No aparecerás disponible para pedidos hoy.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _storeOpen
                        ? bColor.onSuccessContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
                value: _storeOpen,
                onChanged: (value) => setState(() => _storeOpen = value),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Apariencia', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Elige cómo se ve Bocadoo.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  const Center(child: ThemeToggle()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (!isCashier) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  Icons.point_of_sale_rounded,
                  color: colors.primary,
                ),
                title: const Text('Cierre de caja'),
                subtitle: const Text('Cuadrar efectivo y almuerzos del día'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/owner/cash-closing'),
              ),
            ),
            const SizedBox(height: 20),
          ],

          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
      bottomNavigationBar:
          const OwnerBottomNav(currentRoute: '/owner/settings'),
    );
  }
}

