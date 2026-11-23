import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../domain/models/cash_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';
import 'scanner_screen.dart';

/// O3 · Vender plan en caja: comensal (búsqueda o QR) → plan → método de pago.
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
  bool _deductToday = false;
  bool _scanningQr = false;
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

  Future<void> _scanDinerQr() async {
    if (_scanningQr || _saving) return;
    final rawQr = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(
          pickCodeOnly: true,
          pickTitle: 'Escanear QR del comensal',
        ),
      ),
    );
    if (rawQr == null || rawQr.trim().isEmpty || !mounted) return;

    setState(() {
      _scanningQr = true;
      _error = null;
    });
    final rid = ref.read(ownerRestaurantIdProvider);
    final repo = ref.read(ownerCashRepositoryProvider);
    final found = await repo.identifyClientByQr(rid, rawQr);
    if (!mounted) return;

    if (found == null) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      setState(() {
        _scanningQr = false;
        _error = apiErr ??
            'No encontramos un comensal con ese QR. Búscalo por nombre o teléfono.';
      });
      return;
    }

    setState(() {
      _scanningQr = false;
      _client = found;
      _newName = null;
      _error = null;
    });
  }

  Future<void> _confirm(OwnerPlanTemplate plan) async {
    final clientName = _client?.name ?? _newName?.trim();
    if (clientName == null || clientName.isEmpty) {
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
      newClientName: _client == null ? clientName : null,
      template: plan,
      method: _method,
      deductToday: _deductToday,
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
    if (_deductToday) {
      unawaited(container.read(cajaMovementsProvider.notifier).refresh());
    }
    navigator.pop(true);
    final todayNote = _deductToday ? ' · -1 almuerzo de hoy' : '';
    showUndoSnackBar(
      messenger,
      label:
          'Plan activado: ${plan.name} para $clientName (${OwnerFormat.money(plan.price)})$todayNote',
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
    final singleLunchPrice = ref.watch(lunchPriceProvider).value ??
        ref.watch(executivePricesProvider).lunch;
    final singleLunchCents = Money.toCents(singleLunchPrice);
    final clients = clientsAsync.value ?? const <OwnerClient>[];
    if (clientsAsync.hasValue) _prefill(clients);
    final templates = [
      for (final t in templatesAsync.value ?? const <OwnerPlanTemplate>[])
        if (t.active) t,
    ];
    final plan = templates.where((t) => t.id == _planId).firstOrNull ??
        templates.firstOrNull;
    final hasClient =
        _client != null || (_newName != null && _newName!.trim().isNotEmpty);
    final canActivate = hasClient && plan != null && !_saving && !_scanningQr;

    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final sysNav = MediaQuery.viewPaddingOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final navClearance =
        keyboard > 0 ? 0.0 : (sysNav - safeBottom).clamp(0.0, double.infinity);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, navClearance + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Vender plan en caja',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                const OwnerSectionLabel('1. Comensal'),
                const SizedBox(height: 8),
                if (hasClient)
                  _SelectedClient(
                    name: _client?.name ?? _newName!,
                    isNew: _client == null,
                    activeLunches: _client?.activeLunches ?? 0,
                    addedLunches: (plan?.lunches ?? 0) - (_deductToday ? 1 : 0),
                    onClear: () => setState(() {
                      _client = null;
                      _newName = null;
                    }),
                  )
                else
                  _ClientPicker(
                    controller: _search,
                    clients: clients,
                    loading: clientsAsync.isLoading || _scanningQr,
                    scanningQr: _scanningQr,
                    onScanQr: _scanDinerQr,
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
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = (c.maxWidth - 8) / 2;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in templates)
                            SizedBox(
                              width: w,
                              child: _PlanCard(
                                plan: t,
                                selected: t.id == plan?.id,
                                singleLunchCents: singleLunchCents,
                                onTap: () => setState(() => _planId = t.id),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Descontar el almuerzo de hoy (-1)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            Text(
                              'Activa el plan y canjea el almuerzo de hoy',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: _deductToday,
                        onChanged: (v) => setState(() => _deductToday = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 14),
                const OwnerSectionLabel('3. Método de pago'),
                const SizedBox(height: 8),
                Row(
                  children: [
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
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.bocadooColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: canActivate ? () => _confirm(plan) : null,
                  icon: _saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colors.onPrimary,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    plan == null
                        ? 'Selecciona un plan'
                        : 'Activar ${plan.name} · ${OwnerFormat.money(plan.price)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientPicker extends StatelessWidget {
  const _ClientPicker({
    required this.controller,
    required this.clients,
    required this.loading,
    required this.scanningQr,
    required this.onScanQr,
    required this.onChanged,
    required this.onPick,
    required this.onCreate,
  });

  final TextEditingController controller;
  final List<OwnerClient> clients;
  final bool loading;
  final bool scanningQr;
  final VoidCallback onScanQr;
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
        : clients
            .where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q))
            .take(6)
            .toList();
    final exact = clients.any((c) => c.name.toLowerCase() == q);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o teléfono…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton.filledTonal(
                tooltip: 'Escanear QR del comensal',
                onPressed: scanningQr ? null : onScanQr,
                icon: scanningQr
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ],
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
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Registrar y vender a «$query»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Text(
                        '1 toque',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Comensales frecuentes:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        if (loading)
          const LinearProgressIndicator()
        else if (shown.isEmpty)
          Text(
            'Sin coincidencias',
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in shown)
                Material(
                  color: colors.primaryContainer.withValues(alpha: 0.45),
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: colors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onPick(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.group_outlined,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            c.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _SelectedClient extends StatelessWidget {
  const _SelectedClient({
    required this.name,
    required this.isNew,
    required this.activeLunches,
    required this.addedLunches,
    required this.onClear,
  });

  final String name;
  final bool isNew;
  final int activeLunches;
  final int addedLunches;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final cleanParts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    final initials =
        cleanParts.isEmpty ? '?' : cleanParts.map((p) => p[0]).join().toUpperCase();
    final nextTotal = (activeLunches + addedLunches).clamp(0, 9999);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: colors.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      isNew ? 'Nuevo cliente' : 'Cliente registrado',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cambiar comensal',
                style: IconButton.styleFrom(backgroundColor: colors.surface),
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          if (!isNew && activeLunches > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: b.successContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.confirmation_number_outlined,
                    size: 15,
                    color: b.onSuccessContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      addedLunches > 0
                          ? 'Plan activo: $activeLunches alm. → Nuevo total: $nextTotal alm.'
                          : 'Tiene $activeLunches ${activeLunches == 1 ? 'almuerzo vigente' : 'almuerzos vigentes'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: b.onSuccessContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.singleLunchCents,
    required this.onTap,
  });

  final OwnerPlanTemplate plan;
  final bool selected;
  final int singleLunchCents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    final muted =
        selected ? colors.onPrimary.withValues(alpha: 0.85) : colors.onSurfaceVariant;
    final unitCents = Money.toCents(plan.perLunch);
    final totalCents = Money.toCents(plan.price);
    final savingsCents =
        (singleLunchCents > 0 && unitCents < singleLunchCents)
            ? (singleLunchCents * plan.lunches) - totalCents
            : 0;
    final badgeBg = selected ? colors.surface : b.successContainer;
    final badgeFg = selected ? b.success : b.onSuccessContainer;

    return Material(
      color: selected
          ? colors.primary
          : colors.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? colors.primary
              : colors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        color: fg,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_rounded, size: 16, color: fg),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${plan.lunches} almuerzos · ${OwnerFormat.money(plan.perLunch)} c/u',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (savingsCents > 0)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Ahorras ${OwnerFormat.money(savingsCents / 100)}',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: badgeFg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 6),
                  Text(
                    OwnerFormat.money(plan.price),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
