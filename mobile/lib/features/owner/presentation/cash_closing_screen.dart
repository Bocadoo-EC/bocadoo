import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'sell_plan_modal.dart';

/// Dashboard de caja diaria: métricas, arqueo de efectivo, transacciones del
/// día y cierre de caja.
class CashClosingScreen extends ConsumerStatefulWidget {
  const CashClosingScreen({super.key});

  @override
  ConsumerState<CashClosingScreen> createState() => _CashClosingScreenState();
}

class _CashClosingScreenState extends ConsumerState<CashClosingScreen> {
  final TextEditingController _counted = TextEditingController();
  bool _countedTouched = false;
  bool _closed = false;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  double? get _countedValue =>
      double.tryParse(_counted.text.trim().replaceAll(',', '.'));

  Future<void> _sellPlan() async {
    final sold = await showSellPlanModal(context);
    if (sold == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta registrada.')),
      );
    }
  }

  Future<void> _closeCash(TransactionSummary summary, double counted) async {
    final diff = counted - summary.cashExpected;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar caja?'),
        content: Text(
          diff == 0
              ? 'La caja cuadra: ${OwnerFormat.money(counted)} en cajón.'
              : '${diff < 0 ? 'Faltan' : 'Sobran'} '
                  '${OwnerFormat.money(diff.abs())} respecto a lo esperado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar Caja'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _closed = true);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dailySummaryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/owner/scanner'),
        ),
        title: const Text('Cierre de caja'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(dailySummaryProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(dailySummaryProvider),
          ),
          data: (summary) => _buildContent(context, summary),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TransactionSummary summary) {
    final theme = Theme.of(context);
    final scheme = context.colorScheme;

    // Por defecto, el efectivo contado coincide con el esperado (como el PMV).
    final counted = _countedTouched
        ? (_countedValue ?? 0)
        : summary.cashExpected;
    final diff = counted - summary.cashExpected;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dailySummaryProvider);
        await ref.read(dailySummaryProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _IncomeCard(total: summary.totalIncomeToday),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.restaurant,
                  label: 'Almuerzos validados hoy',
                  value: '${summary.lunchesRedeemedToday}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  icon: Icons.sell_outlined,
                  label: 'Planes vendidos',
                  value: '${summary.plansSoldToday}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CashCountCard(
            expected: summary.cashExpected,
            controller: _counted,
            hintValue: summary.cashExpected,
            enabled: !_closed,
            difference: diff,
            onChanged: () => setState(() => _countedTouched = true),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transacciones de hoy',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: _sellPlan,
                icon: const Icon(Icons.add),
                label: const Text('Vender plan'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (summary.transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 40, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(
                    'Aún no hay movimientos hoy.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            for (final t in summary.transactions) _TransactionTile(item: t),
          const SizedBox(height: 24),
          if (_closed)
            _ClosedBanner(difference: diff)
          else
            ElevatedButton.icon(
              onPressed: (_countedTouched && _countedValue == null)
                  ? null
                  : () => _closeCash(summary, counted),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Cerrar Caja'),
            ),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        children: [
          Text(
            'INGRESOS TOTALES',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            OwnerFormat.money(total),
            style: theme.textTheme.displayMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashCountCard extends StatelessWidget {
  const _CashCountCard({
    required this.expected,
    required this.controller,
    required this.hintValue,
    required this.enabled,
    required this.difference,
    required this.onChanged,
  });

  final double expected;
  final TextEditingController controller;
  final double hintValue;
  final bool enabled;
  final double difference;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.colorScheme;
    final tokens = context.bocadooColors;

    final balanced = difference.abs() < 0.005;
    final (Color bg, Color fg, String label) = balanced
        ? (tokens.successContainer, tokens.onSuccessContainer, 'Caja cuadra')
        : difference > 0
            ? (scheme.primaryContainer, scheme.onPrimaryContainer, 'Sobrante')
            : (tokens.dangerContainer, tokens.onDangerContainer, 'Faltante');

    return Container(
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
            'Arqueo de efectivo',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Esperado en Bocadoo',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                    Text(
                      OwnerFormat.money(expected),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textAlign: TextAlign.end,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Efectivo en cajón',
                    prefixText: r'$ ',
                    hintText: expected.toStringAsFixed(2),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: fg, fontWeight: FontWeight.w700)),
                Text(
                  balanced
                      ? OwnerFormat.money(0)
                      : '${difference > 0 ? '+' : '-'}'
                          '${OwnerFormat.money(difference.abs())}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: fg, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.item});

  final TransactionItem item;

  IconData get _icon => switch (item.type) {
        'Validado' => Icons.restaurant,
        'Venta Plan' => Icons.sell_outlined,
        _ => Icons.payments_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.colorScheme;
    final isRedeem = item.type == 'Validado';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Icon(_icon, size: 20),
      ),
      title: Text(
        item.customerName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${item.type} · ${OwnerFormat.time(item.timestamp)}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isRedeem ? '1 almuerzo' : OwnerFormat.money(item.amount),
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            item.paymentMethod,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.difference});

  final double difference;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.successContainer,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: tokens.onSuccessContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Caja cerrada correctamente',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.onSuccessContainer,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('No se pudo calcular el total del turno.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
