import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

/// O3 · Vender plan en caja: comensal → plan → método de pago (3 toques).
class SellPlanSheet extends ConsumerStatefulWidget {
  const SellPlanSheet({super.key, this.initialClientName});

  /// Precarga el comensal (p. ej. desde el resultado del escaneo).
  final String? initialClientName;

  @override
  ConsumerState<SellPlanSheet> createState() => _SellPlanSheetState();
}

class _SellPlanSheetState extends ConsumerState<SellPlanSheet> {
  final _search = TextEditingController();
  OwnerClient? _client;
  String? _newName;
  String? _planId;
  OwnerPayMethod _method = OwnerPayMethod.efectivo;
  bool _saving = false;
  bool _prefilled = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _prefill(List<OwnerClient> clients) {
    if (_prefilled) return;
    _prefilled = true;
    final name = widget.initialClientName?.trim();
    if (name == null || name.isEmpty) return;
    final match = clients.where((c) => c.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (match != null) {
      _client = match;
    } else {
      _newName = name;
    }
  }

  Future<void> _confirm(OwnerPlanTemplate plan) async {
    final clientName = _client?.name ?? _newName;
    if (clientName == null) {
      setState(() => _error = 'Selecciona o escribe el nombre del comensal');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final saleId = await repo.sellPlanTemplate(
      restaurantId: ref.read(ownerRestaurantIdProvider),
      clientId: _client?.id,
      newClientName: _client == null ? _newName : null,
      template: plan,
      method: _method,
    );
    if (!mounted) return;
    if (saleId == null) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      setState(() {
        _saving = false;
        _error = apiErr ?? 'No se pudo registrar la venta';
      });
      return;
    }
    container
      ..invalidate(dailySummaryProvider)
      ..invalidate(ownerClientsProvider);
    navigator.pop(true);
    showUndoSnackBar(
      messenger,
      label: 'Plan activado: ${plan.name} para $clientName (${OwnerFormat.money(plan.price)})',
      onUndo: () async {
        final ok = await repo.undoTransaction(saleId);
        container
          ..invalidate(dailySummaryProvider)
          ..invalidate(ownerClientsProvider);
        showInfoSnackBar(messenger, ok ? 'Venta de plan revertida' : 'No se pudo deshacer la venta');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final clientsAsync = ref.watch(ownerClientsProvider);
    final templatesAsync = ref.watch(planTemplatesProvider);
    final clients = clientsAsync.value ?? const <OwnerClient>[];
    if (clientsAsync.hasValue) _prefill(clients);
    final templates = [for (final t in templatesAsync.value ?? const <OwnerPlanTemplate>[]) if (t.active) t];
    final plan = templates.where((t) => t.id == _planId).firstOrNull ?? templates.firstOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Vender plan en caja',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 14),
          const OwnerSectionLabel('1. Comensal'),
          const SizedBox(height: 8),
          if (_client != null || _newName != null)
            _SelectedClient(
              name: _client?.name ?? _newName!,
              isNew: _client == null,
              onClear: () => setState(() {
                _client = null;
                _newName = null;
              }),
            )
          else
            _ClientPicker(
              controller: _search,
              clients: clients,
              loading: clientsAsync.isLoading,
              onChanged: () => setState(() {}),
              onPick: (c) => setState(() {
                _client = c;
                _error = null;
              }),
              onCreate: (name) => setState(() {
                _newName = name;
                _error = null;
              }),
            ),
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: 14),
          const OwnerSectionLabel('2. Seleccionar plan'),
          const SizedBox(height: 8),
          if (templatesAsync.isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 8) / 2;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in templates)
                  SizedBox(
                    width: w,
                    child: _PlanCard(
                      plan: t,
                      selected: t.id == plan?.id,
                      onTap: () => setState(() => _planId = t.id),
                    ),
                  ),
              ]);
            }),
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: 14),
          const OwnerSectionLabel('3. Método de pago'),
          const SizedBox(height: 8),
          Row(children: [
            for (final (m, icon) in const [
              (OwnerPayMethod.efectivo, Icons.payments_outlined),
              (OwnerPayMethod.transferencia, Icons.smartphone_rounded),
              (OwnerPayMethod.deuna, Icons.bolt_rounded),
            ]) ...[
              if (m != OwnerPayMethod.efectivo) const SizedBox(width: 8),
              Expanded(
                child: OwnerChoice(
                  label: m.shortLabel,
                  icon: icon,
                  selected: _method == m,
                  onTap: () => setState(() => _method = m),
                ),
              ),
            ],
          ]),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.bocadooColors.danger)),
          ],
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: (plan == null || _saving || (_client == null && _newName == null))
                ? null
                : () => _confirm(plan),
            icon: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              plan == null ? 'Selecciona un plan' : 'Activar ${plan.name} · ${OwnerFormat.money(plan.price)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ClientPicker extends StatelessWidget {
  const _ClientPicker({
    required this.controller,
    required this.clients,
    required this.loading,
    required this.onChanged,
    required this.onPick,
    required this.onCreate,
  });

  final TextEditingController controller;
  final List<OwnerClient> clients;
  final bool loading;
  final VoidCallback onChanged;
  final ValueChanged<OwnerClient> onPick;
  final ValueChanged<String> onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final query = controller.text.trim();
    final q = query.toLowerCase();
    final shown = q.isEmpty
        ? clients.take(5).toList()
        : clients.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q)).take(6).toList();
    final exact = clients.any((c) => c.name.toLowerCase() == q);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o teléfono…',
          prefixIcon: const Icon(Icons.search_rounded),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            borderSide: BorderSide(color: colors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
        ),
      ),
      if (query.length > 1 && !exact) ...[
        const SizedBox(height: 8),
        DashedBorderBox(
          color: colors.primary,
          radius: 16,
          fill: colors.primaryContainer.withValues(alpha: 0.4),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onCreate(query),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.add_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Registrar y vender a «$query»',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.primary)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Text('1 toque',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onPrimary)),
                ),
              ]),
            ),
          ),
        ),
      ],
      const SizedBox(height: 10),
      Text('Comensales frecuentes:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
      const SizedBox(height: 6),
      if (loading)
        const LinearProgressIndicator()
      else if (shown.isEmpty)
        Text('Sin coincidencias', style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in shown)
            Material(
              color: colors.primaryContainer.withValues(alpha: 0.45),
              shape: StadiumBorder(side: BorderSide(color: colors.primary.withValues(alpha: 0.25))),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onPick(c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.group_outlined, size: 14, color: colors.primary),
                    const SizedBox(width: 5),
                    Text(c.name,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurface)),
                  ]),
                ),
              ),
            ),
        ]),
    ]);
  }
}

class _SelectedClient extends StatelessWidget {
  const _SelectedClient({required this.name, required this.isNew, required this.onClear});

  final String name;
  final bool isNew;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0]).join().toUpperCase();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(12)),
          child: Text(initials,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onPrimary)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onPrimaryContainer)),
            Text(isNew ? 'Nuevo cliente' : 'Cliente registrado',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.primary)),
          ]),
        ),
        IconButton(
          tooltip: 'Cambiar comensal',
          style: IconButton.styleFrom(backgroundColor: colors.surface),
          onPressed: onClear,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  final OwnerPlanTemplate plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    final muted = selected ? colors.onPrimary.withValues(alpha: 0.85) : colors.onSurfaceVariant;
    return Material(
      color: selected ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? colors.primary : colors.primary.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(plan.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: fg)),
              ),
              if (selected) Icon(Icons.check_rounded, size: 16, color: fg),
            ]),
            const SizedBox(height: 6),
            Text('${plan.lunches} almuerzos · ${OwnerFormat.money(plan.perLunch)} c/u',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: muted)),
            Text(OwnerFormat.money(plan.price),
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: fg)),
          ]),
        ),
      ),
    );
  }
}
