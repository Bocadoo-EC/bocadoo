import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/models/extras_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

String _short(String? dish) {
  if (dish == null) return '';
  final i = dish.indexOf(' con ');
  return i > 0 ? dish.substring(0, i) : dish;
}

/// O5 · Cobrar mesa: un toque cobra a toda la mesa con amigos. Descuenta los
/// planes, cobra a los que pagan suelto y reparte los sellos.
class CobrarMesaSheet extends ConsumerStatefulWidget {
  const CobrarMesaSheet({super.key, required this.tableId});

  final String tableId;

  @override
  ConsumerState<CobrarMesaSheet> createState() => _CobrarMesaSheetState();
}

class _CobrarMesaSheetState extends ConsumerState<CobrarMesaSheet> {
  TablePreview? _preview;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;

  _TablesApi get _repo => _TablesApi(ref);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final p = await _repo.preview(widget.tableId);
      if (mounted) setState(() => _preview = p);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setMode(TableMode mode) async {
    setState(() => _busy = true);
    final p = await _repo.setMode(widget.tableId, mode);
    if (mounted) {
      setState(() {
        _preview = p;
        _busy = false;
      });
    }
  }

  Future<void> _charge() async {
    final p = _preview;
    if (p == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final chargeId = await _repo.charge(widget.tableId);
    if (!mounted) return;
    if (chargeId == null) {
      setState(() => _busy = false);
      showInfoSnackBar(messenger, 'No se pudo cobrar la mesa');
      return;
    }
    void refresh() {
      container.invalidate(pendingTablesProvider);
      container.invalidate(dailySummaryProvider);
    }

    refresh();
    navigator.pop(true);
    final cash = p.totalCash;
    showUndoSnackBar(
      messenger,
      label: cash > 0
          ? 'Mesa #${p.tableId} cobrada · ${OwnerFormat.money(cash)} en caja'
          : 'Mesa #${p.tableId} validada con planes',
      onUndo: () async {
        await container.read(ownerTablesRepositoryProvider).undoTableCharge(chargeId);
        refresh();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final p = _preview;

    Widget body;
    if (_loading && p == null) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: OwnerLoadingView('Cargando mesa'));
    } else if (_failed || p == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: OwnerErrorView(
          title: 'Error al cargar la mesa',
          message: 'No se pudo obtener la mesa.',
          onRetry: _load,
        ),
      );
    } else {
      body = _content(context, p);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.groups_rounded, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p == null || p.lines.isEmpty
                      ? 'Mesa #${widget.tableId.toUpperCase()}'
                      : 'Mesa #${p.tableId} · ${p.lines.length} comensales',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: colors.onSurface),
                ),
                if (p != null && p.hostName.isNotEmpty)
                  Text('Anfitrión: ${p.hostName} · ${p.time}',
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
          body,
        ]),
      ),
    );
  }

  Widget _content(BuildContext context, TablePreview p) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final notFound = p.lines.isEmpty;
    final cash = p.totalCash;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!notFound) ...[
        const OwnerSectionLabel('Modo de cobro'),
        const SizedBox(height: 8),
        IgnorePointer(
          ignoring: _busy || p.settled || !ApiCapabilities.sharedTableModeChange,
          child: Opacity(
            opacity: ApiCapabilities.sharedTableModeChange ? 1.0 : 0.72,
            child: OwnerSegmented(
              labels: const ['Cada quien lo suyo', 'Yo invito la mesa'],
              icons: const [Icons.person_outline_rounded, Icons.volunteer_activism_outlined],
              index: p.mode == TableMode.hostPays ? 1 : 0,
              onChanged: (i) => _setMode(i == 1 ? TableMode.hostPays : TableMode.eachOwn),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (p.error != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: b.dangerContainer, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, color: b.onDangerContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(p.error!,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: b.onDangerContainer)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      if (!notFound) ...[
        const OwnerSectionLabel('Integrantes'),
        const SizedBox(height: 8),
        for (final line in p.lines) ...[
          _MemberRow(line: line),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.payments_outlined, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('En caja (efectivo)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onSurface)),
              ),
              Text(OwnerFormat.money(cash),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
            ]),
            if (p.stamps.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.loyalty_outlined, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sellos: ${p.stamps.map((s) => '${s.$1} +${s.$2}').join(' · ')}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                  ),
                ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 16),
      ],
      if (notFound)
        FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver a caja'))
      else
        ElevatedButton.icon(
          onPressed: p.canCharge && !_busy ? _charge : null,
          icon: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
                )
              : const Icon(Icons.groups_rounded),
          label: Text(cash > 0 ? 'Cobrar mesa · ${OwnerFormat.money(cash)} en caja' : 'Validar mesa con planes'),
        ),
    ]);
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.line});

  final TableChargeLine line;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final (String label, Color bg, Color fg) = switch (line.via) {
      TableChargeVia.plan => ('Plan prepagado', b.successContainer, b.onSuccessContainer),
      TableChargeVia.hostPlan => ('Plan del anfitrión', b.successContainer, b.onSuccessContainer),
      TableChargeVia.cash => ('Paga suelto · ${OwnerFormat.money(line.amount)}', colors.primaryContainer, colors.onPrimaryContainer),
    };
    final dishes = [_short(line.soup), _short(line.main)].where((d) => d.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: line.isHost ? colors.primary : colors.primaryContainer,
          child: Text(
            line.name.isEmpty ? '?' : line.name[0].toUpperCase(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: line.isHost ? colors.onPrimary : colors.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(line.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
              ),
              if (line.isHost) ...[
                const SizedBox(width: 6),
                Text('Anfitrión', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
              ],
            ]),
            if (dishes.isNotEmpty)
              Text(dishes,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            if (line.takeaway)
              Row(children: [
                Icon(Icons.shopping_bag_outlined, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('Para llevar',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.buttonRadius)),
              child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Atajo para llamar al repositorio de mesas con el local actual.
class _TablesApi {
  _TablesApi(this._ref);

  final WidgetRef _ref;

  String get _restaurantId => _ref.read(ownerRestaurantIdProvider);

  Future<TablePreview> preview(String id) =>
      _ref.read(ownerTablesRepositoryProvider).previewTable(_restaurantId, id);

  Future<TablePreview> setMode(String id, TableMode mode) =>
      _ref.read(ownerTablesRepositoryProvider).setTableMode(_restaurantId, id, mode);

  Future<String?> charge(String id) => _ref.read(ownerTablesRepositoryProvider).chargeTable(_restaurantId, id);
}
