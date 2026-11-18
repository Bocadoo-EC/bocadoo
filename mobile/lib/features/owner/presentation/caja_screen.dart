import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/extras_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';
import 'scan_result_screen.dart';

/// O1 · Caja: pantalla de entrada del dueño después del login.
class CajaScreen extends ConsumerStatefulWidget {
  const CajaScreen({super.key});

  @override
  ConsumerState<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends ConsumerState<CajaScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresca la cuenta regresiva de "Lleno (Nm)" y solicitudes de plan entrantes.
    _ticker = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      ref.invalidate(planRequestsProvider);
      ref.invalidate(ordersOnTheWayProvider);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(dailySummaryProvider);
    final colors = context.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Header(lunchesToday: summary.value?.lunchesRedeemedToday ?? 0),
          const _OrdersStrip(),
          Expanded(
            child: summary.when(
              loading: () => const _CajaLoading(),
              error: (e, _) => _CajaError(onRetry: () => ref.invalidate(dailySummaryProvider)),
              data: (s) => _CajaBody(summary: s),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.lunchesToday});

  final int lunchesToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final busyUntil = ref.watch(busyUntilProvider);
    final now = DateTime.now();
    final busy = busyUntil != null && busyUntil.isAfter(now);
    final minutesLeft = busy ? (busyUntil.difference(now).inSeconds / 60).ceil() : 0;
    final movido = lunchesToday >= 10;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
      child: Row(children: [
        Text('Caja', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: colors.onSurface)),
        const SizedBox(width: 8),
        if (!busy)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: movido ? colors.primaryContainer : b.successContainer,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
            child: Text(
              movido ? 'Movido' : 'Libre',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: movido ? colors.onPrimaryContainer : b.success,
              ),
            ),
          ),
        const Spacer(),
        Material(
          color: busy ? b.danger : colors.primaryContainer,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => ref.read(busyUntilProvider.notifier).toggle(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: busy ? b.dangerForeground : colors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  busy ? 'Lleno (${minutesLeft}m)' : 'Marcar lleno',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: busy ? b.dangerForeground : colors.onPrimaryContainer,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _OrdersStrip extends ConsumerWidget {
  const _OrdersStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    ref.listen<AsyncValue<int>>(ordersOnTheWayProvider, (prev, next) {
      final prevCount = prev?.value;
      final nextCount = next.value;
      if (prevCount != null && nextCount != null && nextCount > prevCount) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.alert);
      }
    });
    final count = ref.watch(ordersOnTheWayProvider).value ?? 0;
    return Material(
      color: colors.primaryContainer,
      child: InkWell(
        onTap: () => context.push('/owner/pedidos'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(Icons.schedule_rounded, size: 18, color: colors.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$count en camino',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: Text('Ver',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onPrimary)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CajaBody extends ConsumerWidget {
  const _CajaBody({required this.summary});

  final TransactionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final offer = ref.watch(activeOfferProvider).value;
    final tables = ref.watch(pendingTablesProvider).value ?? const <PendingTable>[];
    final planRequests =
        ref.watch(planRequestsProvider).value ?? const <OwnerPlanRequest>[];
    final isOwner = ref.watch(ownerRoleProvider) == OwnerRole.owner;
    final charges = summary.transactions.take(20).toList();
    final total = summary.transactions.fold<double>(0, (sum, t) => sum + t.amount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (planRequests.isNotEmpty) ...[
          _PlanRequestsSection(requests: planRequests),
          const SizedBox(height: 12),
        ],
        for (final t in tables) ...[
          _TableBanner(
            table: t,
            onTap: () async {
              await context.push('/owner/cobrar-mesa/${t.id}');
              ref.invalidate(pendingTablesProvider);
              ref.invalidate(dailySummaryProvider);
            },
          ),
          const SizedBox(height: 10),
        ],
        _ScanCard(onTap: () => openScannerFlow(context, ref)),
        if (offer != null) ...[
          const SizedBox(height: 12),
          _OfferBanner(
            text: '${offer.slots} cupos a ${OwnerFormat.money(offer.price)}',
            onTap: () => context.push('/owner/oferta-flash'),
          ),
        ],
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => context.push('/owner/registrar-consumo'),
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text(
            'Cobro suelto (POS)',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _QuickTile(
              icon: Icons.group_outlined,
              label: 'Vender plan',
              onTap: () => context.push('/owner/vender-plan'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickTile(
              icon: Icons.bolt_rounded,
              label: 'Oferta flash',
              highlighted: true,
              onTap: () => context.push('/owner/oferta-flash'),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _QuickTile(
                icon: Icons.receipt_outlined,
                label: 'Cuadre caja',
                onTap: () => context.push('/owner/cash-closing'),
              ),
            ),
          ],
        ]),
        if (isOwner) ...[
          const SizedBox(height: 12),
          _NumbersCard(onTap: () => context.go('/owner/metricas')),
        ],
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: OwnerSectionLabel('Cobros de hoy')),
          Text(OwnerFormat.money(total),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onSurface)),
        ]),
        const SizedBox(height: 6),
        if (charges.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('Aún sin cobros',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          )
        else
          for (final t in charges) _ChargeRow(item: t),
      ],
    );
  }
}

/// "Mesa #M1234 · 3 comensales · 13:00" con "Cobrar" (abre O5).
class _TableBanner extends StatelessWidget {
  const _TableBanner({required this.table, required this.onTap});

  final PendingTable table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.primary),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(children: [
            Icon(Icons.groups_rounded, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mesa #${table.id} · ${table.members} comensales',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onPrimaryContainer)),
                Text('${table.hostName} · ${table.time}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onPrimaryContainer)),
              ]),
            ),
            OwnerSmallButton(label: 'Cobrar', onPressed: onTap),
          ]),
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Semantics(
      button: true,
      label: 'Escanear pase de comensal',
      child: DashedBorderBox(
        color: colors.primary,
        fill: Theme.of(context).scaffoldBackgroundColor,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: onTap,
          child: SizedBox(
            height: 230,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(18)),
                child: Icon(Icons.qr_code_2_rounded, size: 40, color: colors.onPrimary),
              ),
              const SizedBox(height: 12),
              Text('Escanear QR',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
              const SizedBox(height: 2),
              Text('Plan, preorden o mesa: se reconoce solo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: colors.primary,
          child: Icon(Icons.bolt_rounded, size: 16, color: colors.onPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Oferta flash activa',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onSurface)),
            Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.primary)),
          ]),
        ),
        TextButton(onPressed: onTap, child: const Text('Ver')),
      ]),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.onTap, this.highlighted = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: highlighted ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: highlighted ? colors.primaryContainer : colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: highlighted ? FontWeight.w900 : FontWeight.w700,
                color: highlighted ? colors.onPrimaryContainer : colors.onSurface,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NumbersCard extends StatelessWidget {
  const _NumbersCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.bar_chart_rounded, size: 20, color: colors.onPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tus números',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onSecondaryContainer)),
                Text('Hoy, dinero y clientes por renovar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            ),
            Text('Ver', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.primary)),
            Icon(Icons.arrow_forward_rounded, size: 16, color: colors.primary),
          ]),
        ),
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  const _ChargeRow({required this.item});

  final TransactionItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            item.amount > 0
                ? '${item.customerName} · ${item.paymentMethod}'
                : item.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.amount > 0 ? OwnerFormat.money(item.amount) : 'Canje de plan (\$0,00)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.onSurface),
        ),
      ]),
    );
  }
}

class _CajaLoading extends StatelessWidget {
  const _CajaLoading();

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 12),
      Text('Cargando caja',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.colorScheme.onSurface)),
    ]);
  }
}

class _CajaError extends StatelessWidget {
  const _CajaError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: b.dangerContainer,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.error_outline_rounded, size: 36, color: b.onDangerContainer),
            const SizedBox(height: 8),
            Text('Error en caja',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: b.onDangerContainer)),
            const SizedBox(height: 4),
            Text('No se pudo cargar el turno.',
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

class _PlanRequestsSection extends ConsumerStatefulWidget {
  const _PlanRequestsSection({required this.requests});

  final List<OwnerPlanRequest> requests;

  @override
  ConsumerState<_PlanRequestsSection> createState() => _PlanRequestsSectionState();
}

class _PlanRequestsSectionState extends ConsumerState<_PlanRequestsSection> {
  String? _busyId;

  Future<void> _charge(OwnerPlanRequest req) async {
    final method = await showModalBottomSheet<OwnerPayMethod>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final colors = ctx.colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cobrar plan · ${req.clientName}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
                const SizedBox(height: 4),
                Text('${req.planName} (${req.lunches} almuerzos) · ${OwnerFormat.money(req.price)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
                const SizedBox(height: 16),
                for (final m in OwnerPayMethod.values) ...[
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(m),
                    child: Text('Cobrar con ${m.label}'),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (method == null || !mounted) return;
    setState(() => _busyId = req.id);
    final repo = ref.read(apiOwnerRepositoryProvider);
    final ok = await repo.chargePlanRequest(req.id, method: method);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (ok) {
      ref.invalidate(planRequestsProvider);
      ref.invalidate(dailySummaryProvider);
      ref.invalidate(ownerClientsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan ${req.planName} activado para ${req.clientName}.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(repo.consumeLastError() ?? 'No se pudo cobrar la solicitud.')),
      );
    }
  }

  Future<void> _reject(OwnerPlanRequest req) async {
    setState(() => _busyId = req.id);
    final repo = ref.read(apiOwnerRepositoryProvider);
    final ok = await repo.rejectPlanRequest(req.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (ok) {
      ref.invalidate(planRequestsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Solicitud de ${req.clientName} rechazada.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(repo.consumeLastError() ?? 'No se pudo rechazar la solicitud.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.notifications_active_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Solicitudes de plan (${widget.requests.length})',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          for (final req in widget.requests) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(req.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
                  ),
                  Text(OwnerFormat.money(req.price),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.primary)),
                ]),
                const SizedBox(height: 2),
                Text('${req.planName} · ${req.lunches} almuerzos',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busyId == req.id ? null : () => _reject(req),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busyId == req.id ? null : () => _charge(req),
                      child: const Text('Cobrar'),
                    ),
                  ),
                ]),
              ]),
            ),
            if (req != widget.requests.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
