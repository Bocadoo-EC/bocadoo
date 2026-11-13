import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/repositories/i_plan_repository.dart';
import 'customer_bottom_nav.dart';
import 'customer_controller.dart';
import 'plan_checkout_provider.dart';

/// Pantalla de Perfil, Ajustes e Historial con reclamos para el Comensal.
class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  ConsumerState<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  final Map<String, HistoryClaimType> _submittedClaims = {};
  final Set<String> _submittingRecordIds = {};

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final uiState = controller.state;
        final pass = uiState.pass;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Ajustes'),
            actions: [
              IconButton(
                tooltip: 'Cerrar sesión',
                onPressed: () => context.go('/login'),
                icon: Icon(Icons.logout_rounded, color: colors.onSurface),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              // 1. Datos del Comensal
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: colors.primaryContainer,
                        child: Text(
                          _initials(pass?.studentName ?? 'Carlos Mejía'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pass?.studentName ?? 'Carlos Mejía',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              pass?.studentCareer ?? 'Ing. de Sistemas · PUCE',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (pass != null) ...[
                              const SizedBox(height: 6),
                              StatusChip(
                                label: 'Te quedan ${pass.remainingLunches}',
                                variant: pass.remainingLunches > 0
                                    ? BocadooStatusVariant.validated
                                    : BocadooStatusVariant.danger,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Apariencia (ThemeToggle: Sistema / Claro / Oscuro)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Apariencia',
                        style: theme.textTheme.titleMedium,
                      ),
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
              const SizedBox(height: 20),

              // 3. Historial de almuerzos con reclamos ("No fui yo" / "Devolver")
              Text(
                'Historial',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (uiState.history.isEmpty)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Aún no tienes almuerzos registrados.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final record in uiState.history) ...[
                  _HistoryClaimCard(
                    record: record,
                    submittedClaim: _submittedClaims[record.id],
                    isSubmitting: _submittingRecordIds.contains(record.id),
                    onClaim: (type) => _submitClaim(record, type),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
          bottomNavigationBar: const CustomerBottomNav(currentIndex: 2),
        );
      },
    );
  }

  Future<void> _submitClaim(
    ConsumptionRecord record,
    HistoryClaimType claimType,
  ) async {
    setState(() => _submittingRecordIds.add(record.id));
    try {
      await ref.read(planRepositoryProvider).submitHistoryClaim(
            recordId: record.id,
            claimType: claimType,
          );
      if (!mounted) return;
      setState(() {
        _submittedClaims[record.id] = claimType;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reporte "${claimType.label}" enviado.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingRecordIds.remove(record.id));
      }
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'B';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _HistoryClaimCard extends StatelessWidget {
  final ConsumptionRecord record;
  final HistoryClaimType? submittedClaim;
  final bool isSubmitting;
  final ValueChanged<HistoryClaimType> onClaim;

  const _HistoryClaimCard({
    required this.record,
    required this.submittedClaim,
    required this.isSubmitting,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.restaurantName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                StatusChip(
                  label: record.status,
                  variant: BocadooStatusVariant.validated,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              record.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatDate(record.date),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (submittedClaim != null)
              StatusChip(
                label: 'Reportado: ${submittedClaim!.label}',
                variant: BocadooStatusVariant.neutral,
                icon: Icons.check_circle_outline_rounded,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSubmitting
                          ? null
                          : () => onClaim(HistoryClaimType.notMe),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.buttonRadius),
                        ),
                      ),
                      child: const Text('No fui yo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSubmitting
                          ? null
                          : () => onClaim(HistoryClaimType.refund),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.buttonRadius),
                        ),
                      ),
                      child: const Text('Devolver'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final hour = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} · $hour:$min';
  }
}

