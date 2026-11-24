import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';

import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _cardRadius = 12.0;

/// Valores que precarga cada tipo de plan.
OwnerPlanTemplate _preset(PlanKind kind) => switch (kind) {
      PlanKind.semanal => const OwnerPlanTemplate(
          id: '', name: 'Plan semanal', lunches: 5, price: 15, validityDays: 7, kind: PlanKind.semanal, quota: 20),
      PlanKind.quincenal => const OwnerPlanTemplate(
          id: '', name: 'Plan quincenal', lunches: 15, price: 42, validityDays: 15, kind: PlanKind.quincenal, quota: 30),
      PlanKind.mensual => const OwnerPlanTemplate(
          id: '', name: 'Plan mensual ejecutivo', lunches: 20, price: 55, validityDays: 30, kind: PlanKind.mensual),
      PlanKind.libre => const OwnerPlanTemplate(
          id: '',
          name: 'Plan libre 10',
          lunches: 10,
          price: 32,
          validityDays: 60,
          kind: PlanKind.libre,
          days: [1, 2, 3, 4, 5, 6, 7]),
    };

/// O9 · Crear o editar plan. Con [planId] edita uno existente.
class PlanEditorSheet extends ConsumerStatefulWidget {
  const PlanEditorSheet({super.key, this.planId});

  final String? planId;

  @override
  ConsumerState<PlanEditorSheet> createState() => _PlanEditorSheetState();
}

class _PlanEditorSheetState extends ConsumerState<PlanEditorSheet> {
  final _name = TextEditingController();
  final _priceController = TextEditingController();
  OwnerPlanTemplate _plan = _preset(PlanKind.mensual);
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  String? _priceError;

  bool get _editing => widget.planId != null;

  @override
  void dispose() {
    _name.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _load(List<OwnerPlanTemplate> plans) {
    if (_loaded) return;
    _loaded = true;
    final existing = plans.where((p) => p.id == widget.planId).firstOrNull;
    if (existing != null) {
      _plan = existing.copyWith(coverage: PlanCoverage.almuerzo);
    }
    _name.text = _plan.name;
    _priceController.text = _plan.price.toStringAsFixed(2);
  }

  void _update(OwnerPlanTemplate next) => setState(() => _plan = next);

  void _applyKind(PlanKind kind) {
    final p = _preset(kind);
    _name.text = p.name;
    _priceController.text = p.price.toStringAsFixed(2);
    _priceError = null;
    _update(_plan.copyWith(
      kind: kind,
      coverage: PlanCoverage.almuerzo,
      name: p.name,
      lunches: p.lunches,
      price: p.price,
      validityDays: p.validityDays,
      quota: p.quota,
      days: p.days,
    ));
  }

  double? _parsePrice(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed <= 0) return null;
    return (parsed * 100).round() / 100;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final parsedPrice = _parsePrice(_priceController.text);
    if (name.isEmpty || parsedPrice == null) {
      setState(() {
        _error = name.isEmpty ? 'Escribe el nombre del plan.' : null;
        _priceError =
            parsedPrice == null ? 'Ingresa un precio mayor a \$0.00.' : null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _priceError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final saved = await ref.read(ownerCashRepositoryProvider).savePlanTemplate(
            ref.read(ownerRestaurantIdProvider),
            _plan.copyWith(
              name: name,
              price: parsedPrice,
              coverage: PlanCoverage.almuerzo,
            ),
          );
      if (!mounted) return;
      container
        ..invalidate(planTemplatesProvider)
        ..invalidate(planClientCountsProvider);
      navigator.pop(true);
      showInfoSnackBar(messenger, '${saved.name} (${OwnerFormat.money(saved.price)}) guardado');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInfoSnackBar(messenger, e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInfoSnackBar(messenger, 'No se pudo guardar el plan. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final plans = ref.watch(planTemplatesProvider);
    if (_editing && !plans.hasValue) {
      return const SizedBox(height: 240, child: OwnerLoadingView('Cargando plan'));
    }
    _load(plans.value ?? const []);
    final p = _plan;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OwnerBackHeader(
            title: _editing ? 'Editar plan' : 'Nuevo plan',
            onBack: () => Navigator.of(context).pop(),
            eyebrow: Text(ref.watch(ownerRestaurantNameProvider),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurfaceVariant)),
            trailing: !_editing
                ? null
                : p.active
                    ? OwnerBadge(label: 'Activo', background: b.successContainer, foreground: b.success)
                    : OwnerBadge(
                        label: 'Inactivo',
                        background: colors.surfaceContainerHighest,
                        foreground: colors.onSurfaceVariant,
                      ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: b.heroGradient, borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Vista previa para comensales',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: b.imageForeground.withValues(alpha: 0.85))),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name.text.trim().isEmpty ? 'Plan ${p.lunches} almuerzos' : _name.text.trim(),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: b.imageForeground)),
                    const SizedBox(height: 2),
                    Text('${p.lunches} almuerzos · vigencia ${p.validityDays} días',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: b.imageForeground.withValues(alpha: 0.85))),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(OwnerFormat.money(p.price),
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1, color: b.imageForeground)),
                  const SizedBox(height: 2),
                  Text('${OwnerFormat.money(p.perLunch)} c/u',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: b.imageForeground.withValues(alpha: 0.85))),
                ]),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          const OwnerSectionLabel('Nombre del plan'),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Ej. Plan mensual ejecutivo',
              fillColor: colors.surface,
              suffixIcon: const Icon(Icons.edit_outlined),
              errorText: _error,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_cardRadius),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_cardRadius),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          const OwnerSectionLabel('Tipo de plan'),
          const SizedBox(height: 6),
          _CleanPlanKindBar(
            index: p.kind.index,
            onChanged: (i) => _applyKind(PlanKind.values[i]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _Stepper(
                label: 'Almuerzos',
                value: '${p.lunches}',
                onMinus: p.lunches > 1 ? () => _update(p.copyWith(lunches: p.lunches - 1)) : null,
                onPlus: () => _update(p.copyWith(lunches: p.lunches + 1)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stepper(
                label: 'Vigencia (días)',
                value: '${p.validityDays}',
                onMinus: p.validityDays > 1 ? () => _update(p.copyWith(validityDays: p.validityDays - 1)) : null,
                onPlus: () => _update(p.copyWith(validityDays: p.validityDays + 1)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(_cardRadius),
                  border: Border.all(
                    color: _priceError != null ? colors.error : colors.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Precio del plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        prefixStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurfaceVariant,
                        ),
                        hintText: '15.00',
                        isDense: true,
                        filled: true,
                        fillColor: colors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.primary, width: 1.5),
                        ),
                      ),
                      onChanged: (raw) {
                        final parsed = _parsePrice(raw);
                        setState(() {
                          _priceError = null;
                          if (parsed != null) {
                            _plan = _plan.copyWith(price: parsed);
                          }
                        });
                      },
                    ),
                    if (_priceError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _priceError!,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stepper(
                label: 'Cupos disponibles',
                value: '${p.quota}',
                onMinus: p.quota > 5 ? () => _update(p.copyWith(quota: p.quota - 5)) : null,
                onPlus: () => _update(p.copyWith(quota: p.quota + 5)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const OwnerSectionLabel('Días de consumo'),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var d = 1; d <= 7; d++)
              _DayCircle(
                letter: _dayLetters[d - 1],
                selected: p.days.contains(d),
                onTap: () {
                  final days = List.of(p.days);
                  if (days.contains(d)) {
                    if (days.length > 1) days.remove(d);
                  } else {
                    days
                      ..add(d)
                      ..sort();
                  }
                  _update(p.copyWith(days: days));
                },
              ),
          ]),
          const SizedBox(height: 16),
          const OwnerSectionLabel('El almuerzo incluye'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final item in PlanCoverage.almuerzo.includeOptions)
              _IncludeChip(
                label: item,
                included: p.includes.contains(item),
                onTap: () {
                  final next = List.of(p.includes);
                  if (!next.remove(item)) next.add(item);
                  _update(p.copyWith(includes: next));
                },
              ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(_cardRadius),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Visible para los comensales',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
                  Text('Los clientes podrán verlo y comprarlo desde la app',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
                ]),
              ),
              Switch(value: p.visible, onChanged: (v) => _update(p.copyWith(visible: v))),
            ]),
          ),
          const SizedBox(height: 20),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Guardar plan'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gratis para publicar. Bocadoo cobra un porcentaje solo con cada almuerzo servido.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CleanPlanKindBar extends StatelessWidget {
  const _CleanPlanKindBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _labels = ['Semanal', 'Quincenal', 'Mensual', 'Libre'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: Material(
                color: i == index
                    ? colors.onSurface.withValues(alpha: 0.08)
                    : colors.surface.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onChanged(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Text(
                      _labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == index ? FontWeight.w900 : FontWeight.w700,
                        color: i == index ? colors.onSurface : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onMinus, required this.onPlus});

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
        const SizedBox(height: 6),
        Row(children: [
          IconButton.outlined(
            tooltip: 'Menos',
            style: IconButton.styleFrom(
              side: BorderSide(color: colors.outlineVariant),
              foregroundColor: colors.onSurface,
            ),
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Expanded(
            child: Text(value,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          IconButton.outlined(
            tooltip: 'Más',
            style: IconButton.styleFrom(
              side: BorderSide(color: colors.outlineVariant),
              foregroundColor: colors.onSurface,
            ),
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ]),
      ]),
    );
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({required this.letter, required this.selected, required this.onTap});

  final String letter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: selected ? colors.primary : colors.surface,
      shape: CircleBorder(side: BorderSide(color: selected ? colors.primary : colors.outlineVariant)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(letter,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: selected ? colors.onPrimary : colors.onSurfaceVariant,
                )),
          ),
        ),
      ),
    );
  }
}

class _IncludeChip extends StatelessWidget {
  const _IncludeChip({required this.label, required this.included, required this.onTap});

  final String label;
  final bool included;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        side: BorderSide(
          color: included ? colors.onSurface : colors.outlineVariant,
          width: included ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(included ? Icons.check_rounded : Icons.add_rounded,
                size: 14, color: included ? colors.onSurface : colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: included ? colors.onSurface : colors.onSurfaceVariant,
                )),
          ]),
        ),
      ),
    );
  }
}
