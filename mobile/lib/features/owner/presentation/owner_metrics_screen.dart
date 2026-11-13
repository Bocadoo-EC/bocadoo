import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import 'owner_bottom_nav.dart';
import 'owner_controller.dart';
import 'owner_format.dart';

enum _MetricsTab { hoy, dinero, clientes }

/// Pantalla de Métricas del Dueño (Hoy / Dinero / Clientes) conectada a
/// [dailySummaryProvider], con acceso directo a Cierre de caja.
class OwnerMetricsScreen extends ConsumerStatefulWidget {
  const OwnerMetricsScreen({super.key});

  @override
  ConsumerState<OwnerMetricsScreen> createState() => _OwnerMetricsScreenState();
}

class _OwnerMetricsScreenState extends ConsumerState<OwnerMetricsScreen> {
  _MetricsTab _tab = _MetricsTab.hoy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summaryAsync = ref.watch(dailySummaryProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Métricas del local'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/owner/cash-closing'),
            icon: const Icon(Icons.point_of_sale_rounded, size: 20),
            label: const Text('Cierre'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  _MetricsPill(
                    label: 'Hoy',
                    selected: _tab == _MetricsTab.hoy,
                    onTap: () => setState(() => _tab = _MetricsTab.hoy),
                  ),
                  _MetricsPill(
                    label: 'Dinero',
                    selected: _tab == _MetricsTab.dinero,
                    onTap: () => setState(() => _tab = _MetricsTab.dinero),
                  ),
                  _MetricsPill(
                    label: 'Clientes',
                    selected: _tab == _MetricsTab.clientes,
                    onTap: () => setState(() => _tab = _MetricsTab.clientes),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: summaryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No pudimos cargar los datos de hoy.'),
                      const SizedBox(height: 12),
                      BocadooButton(
                        label: 'Reintentar',
                        onPressed: () => ref.invalidate(dailySummaryProvider),
                      ),
                    ],
                  ),
                ),
              ),
              data: (summary) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(dailySummaryProvider);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    if (_tab == _MetricsTab.hoy) ...[
                      _TodayTab(summary: summary),
                    ] else if (_tab == _MetricsTab.dinero) ...[
                      _MoneyTab(summary: summary),
                    ] else ...[
                      _ClientsTab(summary: summary),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius:
                            BorderRadius.circular(AppTheme.cardRadius),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Arqueo de caja',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Cuadra el efectivo del turno al terminar el servicio.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () =>
                                context.push('/owner/cash-closing'),
                            child: const Text('Cierre de caja'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          const OwnerBottomNav(currentRoute: '/owner/metrics'),
    );
  }
}

class _TodayTab extends StatelessWidget {
  final TransactionSummary summary;

  const _TodayTab({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Almuerzos hoy',
                value: '${summary.lunchesRedeemedToday}',
                icon: Icons.restaurant_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Planes vendidos',
                value: '${summary.plansSoldToday}',
                icon: Icons.confirmation_number_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MetricCard(
          label: 'Total esperado en caja',
          value: OwnerFormat.money(summary.cashExpected),
          icon: Icons.payments_rounded,
        ),
      ],
    );
  }
}

class _MoneyTab extends StatelessWidget {
  final TransactionSummary summary;

  const _MoneyTab({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricCard(
          label: 'Efectivo en caja',
          value: OwnerFormat.money(summary.cashExpected),
          icon: Icons.account_balance_wallet_rounded,
        ),
        const SizedBox(height: 16),
        Text(
          'Movimientos de hoy',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (summary.transactions.isEmpty)
          Text(
            'Sin movimientos registrados hoy.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else
          for (final item in summary.transactions) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.customerName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.type} · ${item.paymentMethod}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    item.amount > 0
                        ? OwnerFormat.money(item.amount)
                        : 'Plan',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _ClientsTab extends StatelessWidget {
  final TransactionSummary summary;

  const _ClientsTab({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricCard(
          label: 'Comensales atendidos hoy',
          value: '${summary.lunchesRedeemedToday}',
          icon: Icons.groups_rounded,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seguimiento de planes',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Los comensales con 2 almuerzos o menos aparecen marcados con aviso en tu caja para ofrecerles renovar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MetricsPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Expanded(
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

