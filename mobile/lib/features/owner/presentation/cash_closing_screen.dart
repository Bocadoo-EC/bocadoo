import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/models/extras_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

/// O13 · Cierre de caja: ventas del turno, desglose por método y cuadre físico.
class CashClosingScreen extends ConsumerStatefulWidget {
  const CashClosingScreen({super.key});

  @override
  ConsumerState<CashClosingScreen> createState() => _CashClosingScreenState();
}

class _CashClosingScreenState extends ConsumerState<CashClosingScreen> {
  final _counted = TextEditingController();
  bool _closing = false;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  double? get _countedValue => double.tryParse(_counted.text.trim().replaceAll(',', '.'));

  Future<void> _close(double counted) async {
    setState(() => _closing = true);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final rid = ref.read(ownerRestaurantIdProvider);
    final ok = await repo.closeShift(rid, countedCash: counted);
    if (!mounted) return;
    setState(() => _closing = false);
    if (!ok) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      showInfoSnackBar(messenger, apiErr ?? 'No se pudo cerrar el turno');
      return;
    }
    container.invalidate(shiftClosedProvider);
    final isOwner = ref.read(ownerRoleProvider) == OwnerRole.owner;
    if (!isOwner) {
      showInfoSnackBar(messenger, 'Turno cerrado correctamente');
      return;
    }
    showUndoSnackBar(messenger, label: 'Turno cerrado correctamente', onUndo: () async {
      final reopened = await repo.reopenShift(rid);
      container.invalidate(shiftClosedProvider);
      if (!reopened && !AppMode.useMock) {
        final reopenErr = container.read(apiOwnerRepositoryProvider).consumeLastError();
        if (reopenErr != null) showInfoSnackBar(messenger, reopenErr);
      }
    });
  }

  void _back() => context.canPop() ? context.pop() : context.go('/owner/caja');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final summary = ref.watch(dailySummaryProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            child: OwnerBackHeader(
              title: 'Cierre de caja',
              onBack: _back,
              trailing: Text('Turno hoy',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: summary.when(
              loading: () => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Calculando ventas',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.onSurface)),
              ]),
              error: (_, _) => _ErrorView(onRetry: () => ref.invalidate(dailySummaryProvider)),
              data: (s) => (s.transactions.isEmpty &&
                      s.totalIncomeToday == 0 &&
                      s.lunchesRedeemedToday == 0)
                  ? const _EmptyView()
                  : _content(s),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _content(TransactionSummary s) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final closed = ref.watch(shiftClosedProvider).value ?? false;
    final transfers = AppMode.useMock
        ? s.transactions
            .where((t) => t.paymentMethod != 'Efectivo' && t.paymentMethod != 'Plan')
            .fold<double>(0, (sum, t) => sum + t.amount)
        : (s.totalIncomeToday - s.cashExpected).clamp(0.0, double.infinity);
    final empty = _counted.text.trim().isEmpty;
    final counted = empty ? s.cashExpected : (_countedValue ?? 0);
    final diff = ((counted - s.cashExpected) * 100).round();
    final (Color bg, Color fg, String label) = diff == 0
        ? (b.successContainer, b.success, 'Caja cuadrada exacta')
        : diff > 0
            ? (colors.primaryContainer, colors.onPrimaryContainer, 'Sobrante en cajón')
            : (b.dangerContainer, b.onDangerContainer, 'Faltante en cajón');

    BoxDecoration card() => BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(gradient: b.heroGradient, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
        child: Column(children: [
          Text('Ventas del turno',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: b.imageForeground.withValues(alpha: 0.85))),
          const SizedBox(height: 6),
          Text(OwnerFormat.money(s.totalIncomeToday),
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1, color: b.imageForeground)),
          const SizedBox(height: 6),
          Text('${s.lunchesRedeemedToday} almuerzos servidos hoy',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: b.imageForeground.withValues(alpha: 0.85))),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: card(),
        child: Column(children: [
          _MethodRow(
            icon: Icons.payments_outlined,
            iconBg: b.successContainer,
            iconFg: b.success,
            label: 'Efectivo en caja',
            value: OwnerFormat.money(s.cashExpected),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          _MethodRow(
            icon: Icons.smartphone_rounded,
            iconBg: colors.primaryContainer,
            iconFg: colors.primary,
            label: 'Transferencias',
            value: OwnerFormat.money(transfers),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const OwnerSectionLabel('Cuadre de caja física'),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Efectivo en Bocadoo',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
                Text(OwnerFormat.money(s.cashExpected),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Efectivo en cajón',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('\$', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.primary)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _counted,
                    enabled: !closed,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: s.cashExpected.toStringAsFixed(2).replaceAll('.', ','),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                        borderSide: BorderSide(color: colors.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                        borderSide: BorderSide(color: colors.primary, width: 2),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                        borderSide: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
            ]),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: fg.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(diff == 0 ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 20, color: fg),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg))),
              Text(
                diff == 0
                    ? OwnerFormat.money(0)
                    : '${diff > 0 ? '+' : '-'}${OwnerFormat.money(diff.abs() / 100)}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: fg),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      if (closed)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: b.successContainer, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, color: b.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Turno cerrado',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: b.onSuccessContainer)),
            ),
          ]),
        )
      else
        ElevatedButton.icon(
          onPressed: _closing || (!empty && _countedValue == null) ? null : () => _close(counted),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Cerrar turno'),
        ),
    ]);
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        CircleAvatar(radius: 16, backgroundColor: iconBg, child: Icon(icon, size: 17, color: iconFg)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.onSurface)),
        ),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: valueColor ?? colors.onSurface)),
      ]),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.payments_outlined, size: 48, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('Caja sin movimientos',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text('Aún no se han registrado cobros hoy.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: b.dangerContainer, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.error_outline_rounded, size: 36, color: b.onDangerContainer),
            const SizedBox(height: 8),
            Text('Error en cierre',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: b.onDangerContainer)),
            const SizedBox(height: 4),
            Text('No se pudo calcular el total del turno.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.onDangerContainer)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ]),
        ),
      ),
    );
  }
}
