import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import 'owner_controller.dart';
import 'owner_widgets.dart';

final _phonePattern = RegExp(r'^09\d{8}$');

/// O10 · Pasar cartulina: el cliente que tenía sellos en una cartulina física
/// pasa a un plan digital con los almuerzos que le faltan. No genera cobro.
class CartulinaSheet extends ConsumerStatefulWidget {
  const CartulinaSheet({super.key});

  @override
  ConsumerState<CartulinaSheet> createState() => _CartulinaSheetState();
}

class _CartulinaSheetState extends ConsumerState<CartulinaSheet> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  bool _newClient = false;
  OwnerClient? _client;
  OwnerPlanTemplate? _plan;
  int _used = 0;
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _clientReady => _newClient
      ? _name.text.trim().isNotEmpty && _phonePattern.hasMatch(_phone.text.trim())
      : _client != null;

  bool get _valid => _clientReady && _plan != null && _used < _plan!.lunches;

  String get _clientName => _newClient ? _name.text.trim() : (_client?.name ?? '');

  Future<void> _submit() async {
    final plan = _plan;
    if (!_valid || plan == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final name = _clientName;
    final left = plan.lunches - _used;
    final id = await repo.registerPhysicalCard(
      restaurantId: ref.read(ownerRestaurantIdProvider),
      clientId: _newClient ? null : _client?.id,
      newClientName: _newClient ? name : null,
      phone: _newClient ? _phone.text.trim() : null,
      template: plan,
      used: _used,
    );
    if (!mounted) return;
    if (id == null) {
      setState(() => _saving = false);
      showInfoSnackBar(messenger, 'Error al digitalizar: no se pudo registrar la cartulina.');
      return;
    }
    void refresh() {
      container.invalidate(ownerClientsProvider);
      container.invalidate(planClientCountsProvider);
    }

    refresh();
    navigator.pop(true);
    showUndoSnackBar(
      messenger,
      label: 'Cartulina de $name digitalizada · le ${left == 1 ? 'queda 1 almuerzo' : 'quedan $left almuerzos'}',
      onUndo: () async {
        await repo.undoPhysicalCard(id);
        refresh();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final templates = ref.watch(planTemplatesProvider).value?.where((t) => t.active).toList() ?? const [];
    final plan = _plan;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pasar cartulina',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
                Text('Pasa los sellos físicos a un plan digital',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            ),
            IconButton.filledTonal(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          const OwnerSectionLabel('Cliente'),
          const SizedBox(height: 8),
          OwnerSegmented(
            labels: const ['Ya es cliente', 'Cliente nuevo'],
            icons: const [Icons.search_rounded, Icons.person_add_alt_1_outlined],
            index: _newClient ? 1 : 0,
            onChanged: (i) => setState(() => _newClient = i == 1),
          ),
          const SizedBox(height: 10),
          if (_newClient) ..._newClientFields(context) else _ClientSearch(
            controller: _search,
            selected: _client,
            onSelect: (c) => setState(() => _client = c),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 18),
          const OwnerSectionLabel('Plan de la cartulina'),
          const SizedBox(height: 8),
          if (templates.isEmpty)
            Text('Crea un plan en Planes para poder pasar cartulinas.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in templates)
                OwnerChoice(
                  label: t.name,
                  subtitle: '${t.lunches} ${t.coverage.unit}',
                  selected: plan?.id == t.id,
                  radius: 18,
                  onTap: () => setState(() {
                    _plan = t;
                    _used = _used.clamp(0, t.lunches - 1);
                  }),
                ),
            ]),
          if (plan != null) ...[
            const SizedBox(height: 18),
            const OwnerSectionLabel('Sellos de la cartulina'),
            const SizedBox(height: 8),
            _UsedStepper(
              used: _used,
              total: plan.lunches,
              onChanged: (v) => setState(() => _used = v),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _valid && !_saving ? _submit : null,
            icon: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
                  )
                : const Icon(Icons.style_outlined),
            label: const Text('Digitalizar cartulina'),
          ),
          const SizedBox(height: 6),
          Text('No se cobra nada: el cliente ya pagó su cartulina.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
        ]),
      ),
    );
  }

  List<Widget> _newClientFields(BuildContext context) {
    final phone = _phone.text.trim();
    return [
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Nombre del comensal', prefixIcon: Icon(Icons.person_outline)),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Celular del comensal',
          hintText: '09XXXXXXXX',
          prefixIcon: const Icon(Icons.phone_outlined),
          errorText: phone.length == 10 && !_phonePattern.hasMatch(phone) ? 'Debe empezar con 09' : null,
        ),
      ),
    ];
  }
}

class _ClientSearch extends ConsumerWidget {
  const _ClientSearch({
    required this.controller,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final TextEditingController controller;
  final OwnerClient? selected;
  final ValueChanged<OwnerClient?> onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final current = selected;
    if (current != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.primary),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(current.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
              if (current.phone.isNotEmpty)
                Text(current.phone,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            ]),
          ),
          TextButton(onPressed: () => onSelect(null), child: const Text('Cambiar')),
        ]),
      );
    }

    final q = controller.text.trim().toLowerCase();
    final clients = ref.watch(ownerClientsProvider).value ?? const <OwnerClient>[];
    final matches = clients
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q))
        .take(4)
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        decoration: const InputDecoration(
          hintText: 'Buscar por nombre o celular',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 8),
      if (matches.isEmpty)
        Text('No hay clientes con ese nombre. Usa "Cliente nuevo".',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant))
      else
        for (final c in matches)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: CircleAvatar(
              backgroundColor: colors.primaryContainer,
              child: Text(c.name[0], style: TextStyle(fontWeight: FontWeight.w900, color: colors.onPrimaryContainer)),
            ),
            title: Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            subtitle: Text(c.habitualPlan ?? (c.phone.isEmpty ? 'Sin plan' : c.phone),
                style: const TextStyle(fontSize: 13)),
            onTap: () => onSelect(c),
          ),
    ]);
  }
}

class _UsedStepper extends StatelessWidget {
  const _UsedStepper({required this.used, required this.total, required this.onChanged});

  final int used;
  final int total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final left = total - used;

    Widget stat(String label, int value, {bool highlight = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: highlight ? colors.primaryContainer : colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: highlight ? colors.primary : colors.outlineVariant),
            ),
            child: Column(children: [
              Text('$value',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: highlight ? colors.onPrimaryContainer : colors.onSurface,
                  )),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: highlight ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                  )),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('Almuerzos ya consumidos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onSurface)),
        ),
        IconButton.filledTonal(
          tooltip: 'Uno menos',
          onPressed: used > 0 ? () => onChanged(used - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 40,
          child: Text('$used',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
        ),
        IconButton.filledTonal(
          tooltip: 'Uno más',
          onPressed: used < total - 1 ? () => onChanged(used + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        stat('Consumidos', used),
        const SizedBox(width: 8),
        stat('Le quedan', left, highlight: true),
        const SizedBox(width: 8),
        stat('Del plan', total),
      ]),
    ]);
  }
}
