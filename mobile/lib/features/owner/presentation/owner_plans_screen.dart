import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import 'add_client_sheet.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

/// O8 · Planes y clientes.
class OwnerPlansScreen extends ConsumerStatefulWidget {
  const OwnerPlansScreen({super.key});

  @override
  ConsumerState<OwnerPlansScreen> createState() => _OwnerPlansScreenState();
}

class _OwnerPlansScreenState extends ConsumerState<OwnerPlansScreen> {
  bool _clients = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _sell(String clientName) async {
    await context.push('/owner/vender-plan', extra: clientName);
    if (!mounted) return;
    ref
      ..invalidate(ownerClientsProvider)
      ..invalidate(planClientCountsProvider);
  }

  /// O8 · Agregar cliente (hoja). Si pide vender plan, abre O3 enseguida.
  Future<void> _addClient() async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await context.push<AddedClient>('/owner/clientes/nuevo');
    if (!mounted || added == null) return;
    ref.invalidate(ownerClientsProvider);
    if (added.sellPlan) {
      await _sell(added.client.name);
      return;
    }
    showInfoSnackBar(messenger, '${added.client.name} agregado a tus clientes');
  }

  Future<void> _togglePlan(OwnerPlanTemplate plan, bool active) async {
    await ref
        .read(ownerCashRepositoryProvider)
        .setPlanActive(ref.read(ownerRestaurantIdProvider), plan.id, active: active);
    if (mounted) ref.invalidate(planTemplatesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final clients = ref.watch(ownerClientsProvider);
    final q = _search.text.trim().toLowerCase();
    final filtered = [
      for (final c in clients.value ?? const <OwnerClient>[])
        if (q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q)) c,
    ];

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ref.watch(ownerRestaurantNameProvider),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
                    Text(_clients ? 'Clientes' : 'Mis planes',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: colors.onSurface)),
                  ]),
                ),
                if (_clients) ...[
                  Text('${filtered.length} comensales',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Agregar cliente',
                    onPressed: _addClient,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ] else
                  IconButton.filledTonal(
                    tooltip: 'Nuevo plan',
                    onPressed: () => context.push('/owner/planes/nuevo'),
                    icon: const Icon(Icons.add_rounded),
                  ),
              ]),
              const SizedBox(height: 10),
              OwnerSegmented(
                labels: const ['Planes', 'Clientes'],
                index: _clients ? 1 : 0,
                onChanged: (i) => setState(() => _clients = i == 1),
              ),
              if (_clients) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o teléfono',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      borderSide: BorderSide(color: colors.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      borderSide: BorderSide(color: colors.primary, width: 2),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          Expanded(child: _clients ? _clientsBody(clients, filtered) : _plansBody()),
        ]),
      ),
    );
  }

  Widget _plansBody() {
    final colors = context.colorScheme;
    final counts = ref.watch(planClientCountsProvider).value ?? const <String, int>{};
    return ref.watch(planTemplatesProvider).when(
          loading: () => const OwnerLoadingView('Cargando planes'),
          error: (_, _) => OwnerErrorView(
            title: 'Error al cargar planes',
            message: 'Revisa tu conexión e inténtalo de nuevo.',
            onRetry: () => ref.invalidate(planTemplatesProvider),
          ),
          data: (plans) => plans.isEmpty
              ? _Empty(
                  icon: Icons.inventory_2_outlined,
                  title: 'Sin planes configurados',
                  message: 'Crea tu primer paquete de almuerzos.',
                  action: ElevatedButton.icon(
                    onPressed: () => context.push('/owner/planes/nuevo'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear plan'),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
                  for (final p in plans) ...[
                    _PlanCard(
                      plan: p,
                      clients: counts[p.id] ?? 0,
                      onEdit: () => context.push('/owner/planes/${p.id}/editar'),
                      onToggle: (v) => _togglePlan(p, v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text('Toca la cantidad de un plan para editarlo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
                ]),
        );
  }

  Widget _clientsBody(AsyncValue<List<OwnerClient>> clients, List<OwnerClient> filtered) {
    final query = _search.text.trim();
    if (clients.isLoading && !clients.hasValue) return const OwnerLoadingView('Cargando clientes');
    if (clients.hasError && !clients.hasValue) {
      return OwnerErrorView(
        title: 'Error al cargar clientes',
        message: 'Revisa tu conexión e inténtalo de nuevo.',
        onRetry: () => ref.invalidate(ownerClientsProvider),
      );
    }
    if (filtered.isEmpty) {
      return query.isEmpty
          ? _Empty(
              icon: Icons.group_outlined,
              title: 'Sin clientes registrados',
              message: 'Agrega a tu primer cliente para venderle un plan.',
              action: ElevatedButton.icon(
                onPressed: _addClient,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Agregar cliente'),
              ),
            )
          : _Empty(
              icon: Icons.person_search_outlined,
              title: 'No se encontró "$query"',
              message: '¿Cliente nuevo? Regístralo al instante para venderle el plan.',
              action: ElevatedButton.icon(
                onPressed: () => _sell(query),
                icon: const Icon(Icons.add_rounded),
                label: Text('Vender plan a "$query"', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      for (final c in filtered) ...[
        _ClientCard(client: c, onSell: () => _sell(c.name)),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.clients, required this.onEdit, required this.onToggle});

  final OwnerPlanTemplate plan;
  final int clients;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tag = plan.name.replaceFirst(RegExp(r'^plan\s*', caseSensitive: false), '');
    final tagLabel = tag.isEmpty ? plan.name : '${tag[0].toUpperCase()}${tag.substring(1)}';

    Widget column(String label, String value, [String? extra]) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface)),
            if (extra != null)
              Text(extra, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.primary)),
          ]),
        );

    return Opacity(
      opacity: plan.active ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: plan.active ? colors.surface : Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Flexible(
              child: OwnerBadge(
                label: tagLabel,
                background: colors.primaryContainer,
                foreground: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 6),
            OwnerBadge(
              label: plan.coverage.label,
              background: Theme.of(context).scaffoldBackgroundColor,
              foreground: colors.onSurfaceVariant,
            ),
            const Spacer(),
            Semantics(
              label: 'Estado de ${plan.name}',
              child: Switch(value: plan.active, onChanged: onToggle),
            ),
          ]),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(
                  child: Text('${plan.lunches} ${plan.coverage.unit}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
                ),
                Icon(Icons.edit_outlined, size: 20, color: colors.primary),
              ]),
            ),
          ),
          Divider(height: 16, color: colors.outlineVariant),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            column('Precio', OwnerFormat.money(plan.price), '${OwnerFormat.money(plan.perLunch)} c/u'),
            column('Vigencia', '${plan.validityDays} días'),
            column('Clientes', '$clients'),
          ]),
        ]),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onSell});

  final OwnerClient client;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(client.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
            if (client.phone.isNotEmpty)
              Text(client.phone,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            const SizedBox(height: 6),
            OwnerBadge(
              label: client.habitualPlan ?? 'Sin plan',
              background: colors.primaryContainer,
              foreground: colors.onPrimaryContainer,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        OwnerSmallButton(label: 'Vender plan', onPressed: onSell),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icon, size: 48, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}
