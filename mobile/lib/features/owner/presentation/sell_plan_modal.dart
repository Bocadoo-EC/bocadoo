import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'owner_controller.dart';
import 'owner_format.dart';

/// Abre el BottomSheet de venta de plan. Devuelve `true` si la venta se
/// registró.
///
/// [studentIdentifier] precarga el campo ID/Cédula (p. ej. desde el resultado
/// de un escaneo); el dueño puede editarlo.
Future<bool?> showSellPlanModal(
  BuildContext context, {
  String? studentIdentifier,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SellPlanModal(initialIdentifier: studentIdentifier),
  );
}

/// Venta rápida de un plan de almuerzos en caja.
class SellPlanModal extends ConsumerStatefulWidget {
  const SellPlanModal({super.key, this.initialIdentifier});

  final String? initialIdentifier;

  @override
  ConsumerState<SellPlanModal> createState() => _SellPlanModalState();
}

class _SellPlanModalState extends ConsumerState<SellPlanModal> {
  /// Mismo valor por defecto que `OwnerStore.defaultLunchPrice`.
  static const double _unitPrice = 3.50;
  static const List<int> _plans = [10, 20, 30];

  late final TextEditingController _id =
      TextEditingController(text: widget.initialIdentifier ?? '');
  int _lunches = 10;
  String _method = 'Efectivo';
  bool _saving = false;
  String? _idError;
  String? _error;

  double get _total => _lunches * _unitPrice;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final identifier = _id.text.trim();
    if (identifier.isEmpty) {
      setState(() => _idError = 'Ingresa el ID o la cédula del estudiante.');
      return;
    }
    setState(() {
      _saving = true;
      _idError = null;
      _error = null;
    });
    try {
      final ok = await ref.read(ownerRepositoryProvider).sellPlan(
            studentIdentifier: identifier,
            lunchCount: _lunches,
            paymentMethod: _method,
            amount: _total,
          );
      if (!mounted) return;
      if (ok) {
        ref.invalidate(dailySummaryProvider);
        Navigator.pop(context, true);
      } else {
        setState(() {
          _saving = false;
          _error = 'No se pudo registrar la venta.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Error al registrar la venta: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vender plan',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _id,
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'ID / Cédula del estudiante',
                prefixIcon: const Icon(Icons.badge_outlined),
                errorText: _idError,
              ),
              onChanged: (_) {
                if (_idError != null) setState(() => _idError = null);
              },
            ),
            const SizedBox(height: 20),
            Text('Plan', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final n in _plans)
                  ButtonSegment(value: n, label: Text('$n almuerzos')),
              ],
              selected: {_lunches},
              onSelectionChanged:
                  _saving ? null : (s) => setState(() => _lunches = s.first),
            ),
            const SizedBox(height: 20),
            Text('Método de pago', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'Efectivo',
                  label: Text('Efectivo'),
                  icon: Icon(Icons.payments_outlined),
                ),
                ButtonSegment(
                  value: 'Transferencia',
                  label: Text('Transferencia'),
                  icon: Icon(Icons.swap_horiz),
                ),
              ],
              selected: {_method},
              onSelectionChanged:
                  _saving ? null : (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total a cobrar',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    OwnerFormat.money(_total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _confirm,
              child: _saving
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Text('Registrar Venta'),
            ),
          ],
        ),
      ),
    );
  }
}
