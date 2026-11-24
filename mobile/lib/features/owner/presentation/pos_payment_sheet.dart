import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/extras_models.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

/// Formatea centavos en dólares con coma decimal (`4200` → `$42,00`).
String formatPosCents(int cents) =>
    '\$${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';

/// Parsea texto decimal en centavos (`"42.50"` o `"42,50"` → `4250`).
int? parsePosCents(String text) {
  final clean = text.trim().replaceAll(',', '.');
  if (clean.isEmpty) return null;
  final n = double.tryParse(clean);
  return n == null || n < 0 ? null : (n * 100).round();
}

/// Calcula denominaciones rápidas de billetes mayores al total (`$45`, `$50`, etc.).
List<int> quickBillsForPosCents(int totalCents) {
  if (totalCents <= 0) return const [];
  if (totalCents <= 2000) {
    return [5, 10, 20].where((v) => v * 100 >= totalCents).toList();
  }
  const candidates = [25, 30, 35, 40, 45, 50, 60, 80, 100, 150, 200];
  return candidates.where((v) => v * 100 > totalCents).take(2).toList();
}

/// Controles reutilizables de método de pago del POS (`Efectivo`, `Transferencia`, `Deuna`),
/// monto recibido con vuelto en vivo y número de referencia obligatorio en pagos digitales.
class OwnerPosPaymentControls extends StatelessWidget {
  const OwnerPosPaymentControls({
    super.key,
    required this.method,
    required this.effectiveTotalCents,
    required this.cashController,
    required this.onMethodChanged,
    required this.onCashChanged,
    this.referenceController,
    this.onReferenceChanged,
    this.requireCashAmount = false,
    this.requireReferenceOnDigital = false,
    this.referenceTouched = false,
    this.enabled = true,
  });

  final OwnerPayMethod method;
  final int effectiveTotalCents;
  final TextEditingController cashController;
  final ValueChanged<OwnerPayMethod> onMethodChanged;
  final VoidCallback onCashChanged;
  final TextEditingController? referenceController;
  final VoidCallback? onReferenceChanged;
  final bool requireCashAmount;
  final bool requireReferenceOnDigital;
  final bool referenceTouched;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final isCash = method == OwnerPayMethod.efectivo && effectiveTotalCents > 0;
    final isDigital =
        (method == OwnerPayMethod.transferencia ||
            method == OwnerPayMethod.deuna) &&
        effectiveTotalCents > 0;

    final receivedCents = isCash ? parsePosCents(cashController.text) : null;
    final invalid =
        isCash && cashController.text.trim().isNotEmpty && receivedCents == null;
    final shortfall =
        isCash && receivedCents != null && receivedCents < effectiveTotalCents;
    final changeCents =
        receivedCents == null ? 0 : receivedCents - effectiveTotalCents;
    final bills = quickBillsForPosCents(effectiveTotalCents);

    final refText = referenceController?.text.trim() ?? '';
    final showRefError =
        isDigital && requireReferenceOnDigital && referenceTouched && refText.isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (effectiveTotalCents > 0) ...[
          const OwnerSectionLabel('Método de pago'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (m, icon) in const [
                (OwnerPayMethod.efectivo, Icons.payments_outlined),
                (
                  OwnerPayMethod.transferencia,
                  Icons.account_balance_outlined
                ),
                (OwnerPayMethod.deuna, Icons.bolt_rounded),
              ]) ...[
                if (m != OwnerPayMethod.efectivo) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: method == m
                        ? colors.primary
                        : Theme.of(context).scaffoldBackgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: method == m
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: enabled ? () => onMethodChanged(m) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: method == m
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.shortLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: method == m
                                    ? colors.onPrimary
                                    : colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (isCash) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: cashController,
                  enabled: enabled,
                  onChanged: (_) => onCashChanged(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '\$ ',
                    labelText: requireCashAmount ? 'Monto recibido (\$)' : null,
                    hintText: requireCashAmount
                        ? (effectiveTotalCents / 100).toStringAsFixed(2)
                        : 'Efectivo recibido (opcional)',
                    errorText: invalid
                        ? 'Monto inválido'
                        : (shortfall
                              ? 'Faltan ${formatPosCents(effectiveTotalCents - receivedCents)}'
                              : null),
                  ),
                ),
              ),
              if (receivedCents != null &&
                  !shortfall &&
                  (changeCents > 0 || requireCashAmount)) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: b.successContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    requireCashAmount
                        ? 'Cambio / Vuelto: ${formatPosCents(changeCents)}'
                        : 'Vuelto ${formatPosCents(changeCents)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: b.success,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in bills)
                ActionChip(
                  label: Text('\$$v'),
                  onPressed: enabled
                      ? () {
                          cashController.text = '$v';
                          onCashChanged();
                        }
                      : null,
                ),
              ActionChip(
                label: Text(requireCashAmount ? 'Monto exacto' : 'Exacto'),
                onPressed: enabled
                    ? () {
                        if (requireCashAmount) {
                          cashController.text =
                              (effectiveTotalCents / 100).toStringAsFixed(2);
                        } else {
                          cashController.clear();
                        }
                        onCashChanged();
                      }
                    : null,
              ),
            ],
          ),
        ],
        if (isDigital &&
            requireReferenceOnDigital &&
            referenceController != null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: referenceController,
            enabled: enabled,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onReferenceChanged?.call(),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              labelText: 'N.º de referencia / comprobante',
              hintText: method == OwnerPayMethod.deuna
                  ? 'Ej. Código Deuna'
                  : 'Ej. N.º de transferencia',
              prefixIcon: const Icon(Icons.receipt_long_outlined, size: 18),
              errorText: showRefError
                  ? 'Ingresa el N.º de referencia o comprobante.'
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// Modal reutilizable de cobro para **Solicitudes de plan** usando el mismo cierre de POS.
class OwnerPlanChargeSheet extends StatefulWidget {
  const OwnerPlanChargeSheet({
    super.key,
    required this.request,
    required this.onConfirm,
  });

  final OwnerPlanRequest request;
  final Future<String?> Function(
    OwnerPayMethod method,
    String? reference,
  ) onConfirm;

  @override
  State<OwnerPlanChargeSheet> createState() => _OwnerPlanChargeSheetState();
}

class _OwnerPlanChargeSheetState extends State<OwnerPlanChargeSheet> {
  OwnerPayMethod _method = OwnerPayMethod.efectivo;
  final TextEditingController _cash = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  bool _referenceTouched = false;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _cash.dispose();
    _reference.dispose();
    super.dispose();
  }

  int get _totalCents => Money.toCents(widget.request.price);

  bool get _canConfirm {
    if (_isSubmitting) return false;
    if (_method == OwnerPayMethod.efectivo) {
      final received = parsePosCents(_cash.text);
      return received != null && received >= _totalCents;
    }
    return _reference.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_method != OwnerPayMethod.efectivo &&
        _reference.text.trim().isEmpty) {
      setState(() => _referenceTouched = true);
      return;
    }
    if (!_canConfirm) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final refText =
        _method == OwnerPayMethod.efectivo ? null : _reference.text.trim();
    final err = await widget.onConfirm(_method, refText);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _submitError = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final req = widget.request;
    final concept =
        '${req.planName} (${req.lunches} almuerzos) · ${req.clientName}';
    final totalFormatted = OwnerFormat.money(req.price);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cobrar plan',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Cerrar',
                    onPressed:
                        _isSubmitting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Concepto',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          totalFormatted,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      concept,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              OwnerPosPaymentControls(
                method: _method,
                effectiveTotalCents: _totalCents,
                cashController: _cash,
                referenceController: _reference,
                requireCashAmount: true,
                requireReferenceOnDigital: true,
                referenceTouched: _referenceTouched,
                enabled: !_isSubmitting,
                onMethodChanged: (m) => setState(() {
                  _method = m;
                  _submitError = null;
                  if (m != OwnerPayMethod.efectivo) {
                    _cash.clear();
                  } else {
                    _referenceTouched = false;
                  }
                }),
                onCashChanged: () => setState(() => _submitError = null),
                onReferenceChanged: () => setState(() {
                  _referenceTouched = true;
                  _submitError = null;
                }),
              ),
              if (_submitError != null && _submitError!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: b.dangerContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _submitError!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: b.onDangerContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _canConfirm ? _submit : null,
                icon: _isSubmitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  _isSubmitting
                      ? 'Confirmando…'
                      : 'Confirmar cobro · $totalFormatted',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
