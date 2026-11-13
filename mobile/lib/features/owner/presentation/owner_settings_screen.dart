import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/theme_toggle.dart';
import 'owner_controller.dart';

// ── Providers de ajustes ─────────────────────────────────────────────────────

class _StoreOpenNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool value) => state = value;
}

/// Estado de apertura del local para esta sesión.
final _storeOpenProvider =
    NotifierProvider<_StoreOpenNotifier, bool>(_StoreOpenNotifier.new);

// ── Pantalla ─────────────────────────────────────────────────────────────────

/// Ajustes del Dueño: tema, estado del local y cierre de sesión.
class OwnerSettingsScreen extends ConsumerWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = ref.watch(_storeOpenProvider);
    final theme = Theme.of(context);
    final scheme = context.colorScheme;
    final tokens = context.bocadooColors;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/owner/scanner'),
        ),
        title: const Text('Ajustes'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // ── Apariencia ──────────────────────────────────────────────────
            _SectionLabel(label: 'Apariencia'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tema',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const ThemeToggle(),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Estado del local ─────────────────────────────────────────────
            _SectionLabel(label: 'Local'),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOpen ? 'Abierto' : 'Cerrado',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isOpen
                              ? 'Los comensales pueden ver el menú.'
                              : 'El local no recibe pedidos ahora.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isOpen,
                    activeThumbColor: tokens.success,
                    onChanged: (value) => _toggleStore(ref, context, value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Sesión ───────────────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () => _logout(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.danger,
                side: BorderSide(color: tokens.dangerContainer),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStore(
      WidgetRef ref, BuildContext context, bool isOpen) async {
    ref.read(_storeOpenProvider.notifier).set(isOpen);
    final restaurantId = ref.read(ownerRestaurantIdProvider);
    final repo = ref.read(ownerMenuRepositoryProvider);
    await repo.setStoreOpen(restaurantId, isOpen: isOpen);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOpen ? 'Local abierto.' : 'Local cerrado.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _logout(BuildContext context) {
    // El backend real invalidará la sesión. Por ahora vuelve al login.
    context.go('/login');
  }
}

// ── Etiqueta de sección ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
