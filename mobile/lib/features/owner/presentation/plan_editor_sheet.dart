import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';

import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Valores que precarga cada tipo de plan.
OwnerPlanTemplate _preset(PlanKind kind) => switch (kind) {
      PlanKind.semanal => const OwnerPlanTemplate(
          id: '', name: 'Plan semanal', lunches: 5, price: 15, validityDays: 7, kind: PlanKind.semanal, quota: 20),
      PlanKind.quincenal => const OwnerPlanTemplate(
          id: '', name: 'Plan quincenal', lunches: 10, price: 28, validityDays: 15, kind: PlanKind.quincenal, quota: 30),
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
  OwnerPlanTemplate _plan = _preset(PlanKind.mensual);
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.planId != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _load(List<OwnerPlanTemplate> plans) {
    if (_loaded) return;
    _loaded = true;
    final existing = plans.where((p) => p.id == widget.planId).firstOrNull;
    if (existing != null) _plan = existing;
    _name.text = _plan.name;
  }

  void _update(OwnerPlanTemplate next) => setState(() => _plan = next);

  void _applyKind(PlanKind kind) {
    final p = _preset(kind);
    _name.text = p.name;
    _update(_plan.copyWith(
      kind: kind,
      name: p.name,
      lunches: p.lunches,
      price: p.price,
      validityDays: p.validityDays,
      quota: p.quota,
      days: p.days,
    ));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del plan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final saved = await ref
        .read(ownerCashRepositoryProvider)
        .savePlanTemplate(ref.read(ownerRestaurantIdProvider), _plan.copyWith(name: name));
    if (!mounted) return;
    container
      ..invalidate(planTemplatesProvider)
      ..invalidate(planClientCountsProvider);
    navigator.pop(true);
    showInfoSnackBar(messenger, '${saved.name} (${OwnerFormat.money(saved.price)}) guardado');
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
    final unit = p.coverage.unit;
    final unitTitle = '${unit[0].toUpperCase()}${unit.substring(1)}';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OwnerBackHeader(
            title: _editing ? 'Editar plan' : 'Nuevo plan',
            onBack: () => Navigator.of(context).pop(),
            eyebrow: Text(ref.watch(ownerRestaurantNameProvider),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurfaceVariant)),
            trailing: !_editing
                ? OwnerBadge(label: 'Borrador', background: colors.primaryContainer, foreground: colors.onPrimaryContainer)
                : p.active
                    ? OwnerBadge(label: 'Activo', background: b.successContainer, foreground: b.success)
                    : OwnerBadge(
                        label: 'Inactivo',
                        background: Theme.of(context).scaffoldBackgroundColor,
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
                    Text(_name.text.trim().isEmpty ? 'Plan ${p.lunches} $unit' : _name.text.trim(),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: b.imageForeground)),
                    const SizedBox(height: 2),
                    Text('${p.lunches} $unit · vigencia ${p.validityDays} días',
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
              suffixIcon: const Icon(Icons.edit_outlined),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          const OwnerSectionLabel('Tipo de plan'),
          const SizedBox(height: 6),
          OwnerSegmented(
            labels: const ['Semanal', 'Quincenal', 'Mensual', 'Libre'],
            index: p.kind.index,
            filledSelected: true,
            onChanged: (i) => _applyKind(PlanKind.values[i]),
          ),
          const SizedBox(height: 16),
          const OwnerSectionLabel('Qué cubre el plan'),
          const SizedBox(height: 6),
          OwnerSegmented(
            labels: [for (final c in PlanCoverage.values) c.label],
            index: p.coverage.index,
            filledSelected: true,
            onChanged: (i) {
              final c = PlanCoverage.values[i];
              _update(p.copyWith(coverage: c, includes: c.defaultIncludes));
            },
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _Stepper(
                label: unitTitle,
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
          Row(children: [
            Expanded(
              child: _Stepper(
                label: 'Precio del plan',
                value: OwnerFormat.money(p.price),
                onMinus: p.price > 1 ? () => _update(p.copyWith(price: p.price - 1)) : null,
                onPlus: () => _update(p.copyWith(price: p.price + 1)),
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
          OwnerSectionLabel(switch (p.coverage) {
            PlanCoverage.almuerzo => 'El almuerzo incluye',
            PlanCoverage.desayuno => 'El desayuno incluye',
            PlanCoverage.mixto => 'El combo incluye',
          }),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final item in p.coverage.includeOptions)
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
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Visible en el marketplace',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
                  Text('Los comensales pueden comprarlo en la app',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
                ]),
              ),
              Switch(value: p.visible, onChanged: (v) => _update(p.copyWith(visible: v))),
            ]),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Guardar plan'),
          ),
          const SizedBox(height: 8),
          Text(
            'Gratis para publicar. Bocadoo cobra un porcentaje solo con cada almuerzo servido.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
          ),
        ]),
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
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
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
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          IconButton.filledTonal(
            tooltip: 'Más',
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
      color: selected ? colors.primary : Theme.of(context).scaffoldBackgroundColor,
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
      color: included ? colors.primaryContainer : Theme.of(context).scaffoldBackgroundColor,
      shape: StadiumBorder(side: BorderSide(color: included ? colors.primaryContainer : colors.outlineVariant)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(included ? Icons.check_rounded : Icons.add_rounded,
                size: 14, color: included ? colors.primary : colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: included ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                )),
          ]),
        ),
      ),
    );
  }
}
