import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
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
      ref.invalidate(pendingTablesProvider);
      ref.invalidate(posMenuProvider);
      unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
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
          const _Header(),
          const _OrdersStrip(),
          Expanded(
            child: summary.when(
              skipLoadingOnReload: true,
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
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final status = ref.watch(ownerPublicStatusProvider);

    final (Color bg, Color fg, Color dot, String label) = switch (status.effective) {
      RestaurantEffectiveStatus.libre => (
          b.successContainer,
          b.onSuccessContainer,
          b.success,
          'Libre',
        ),
      RestaurantEffectiveStatus.concurrido => (
          b.walletAccent.withValues(alpha: 0.45),
          b.onWalletAccent,
          b.onWalletAccent,
          'Concurrido',
        ),
      RestaurantEffectiveStatus.lleno => (
          b.danger,
          b.dangerForeground,
          b.dangerForeground,
          status.remainingFullMinutes > 0
              ? 'Lleno · ${status.remainingFullMinutes}m'
              : 'Lleno',
        ),
      RestaurantEffectiveStatus.agotadoHoy => (
          b.dangerContainer,
          b.onDangerContainer,
          b.danger,
          'Agotado hoy',
        ),
      RestaurantEffectiveStatus.cerrado => (
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
          b.statusCerradoDot,
          'Cerrado',
        ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
      child: Row(children: [
        Text('Caja', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: colors.onSurface)),
        const Spacer(),
        Material(
          color: bg,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              useRootNavigator: true,
              builder: (_) => const _PublicStatusSheet(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg),
                ),
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PublicStatusSheet extends ConsumerWidget {
  const _PublicStatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final status = ref.watch(ownerPublicStatusProvider);
    final notifier = ref.read(manualOccupancyProvider.notifier);
    final isFullActive = status.manual == ManualOccupancyStatus.lleno &&
        status.remainingFullMinutes > 0;
    final messenger = ScaffoldMessenger.of(context);

    Future<void> selectStatus(Future<String?> Function() action) async {
      Navigator.of(context).pop();
      final err = await action();
      if (err != null && err.isNotEmpty) {
        showInfoSnackBar(messenger, err);
      }
    }

    Widget optionTile({
      required String title,
      required String subtitle,
      required Color dotColor,
      required bool selected,
      required VoidCallback onTap,
      Widget? trailing,
    }) {
      return Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ] else if (selected)
                Icon(Icons.check_circle_rounded, color: colors.primary, size: 20),
            ]),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      bottom: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Disponibilidad del local',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Se refleja al instante en el Marketplace y tu ficha para comensales.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
            if (status.isSoldOutToday) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: b.dangerContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Icon(Icons.no_meals_rounded, size: 18, color: b.onDangerContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Todos los platos del menú de hoy están agotados. El público ve "Agotado hoy" hasta que reactives platos.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: b.onDangerContainer,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            optionTile(
              title: 'Libre',
              subtitle: 'Hay mesas disponibles sin espera.',
              dotColor: b.statusLibreDot,
              selected: status.manual == ManualOccupancyStatus.libre,
              onTap: () => unawaited(
                selectStatus(() => notifier.setStatus(ManualOccupancyStatus.libre)),
              ),
            ),
            const SizedBox(height: 8),
            optionTile(
              title: 'Concurrido',
              subtitle: 'Pocas mesas disponibles o ligera espera.',
              dotColor: b.statusConcurridoDot,
              selected: status.manual == ManualOccupancyStatus.concurrido,
              onTap: () => unawaited(
                selectStatus(
                  () => notifier.setStatus(ManualOccupancyStatus.concurrido),
                ),
              ),
            ),
            const SizedBox(height: 8),
            optionTile(
              title: isFullActive
                  ? 'Lleno · Quedan ${status.remainingFullMinutes} min'
                  : 'Lleno (20 min)',
              subtitle: 'Sin mesas (solo pedidos para llevar; vuelve a Libre en 20 min).',
              dotColor: b.statusLlenoDot,
              selected: status.manual == ManualOccupancyStatus.lleno,
              onTap: () => unawaited(
                selectStatus(() => notifier.setStatus(ManualOccupancyStatus.lleno)),
              ),
              trailing: isFullActive
                  ? FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () => unawaited(
                        selectStatus(notifier.extendFull15Min),
                      ),
                      child: const Text(
                        '+ 15 min',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            optionTile(
              title: 'Cerrado',
              subtitle: 'No recibirás nuevas preórdenes ni pedidos grupales hoy.',
              dotColor: b.statusCerradoDot,
              selected: status.manual == ManualOccupancyStatus.cerrado,
              onTap: () async {
                if (status.manual == ManualOccupancyStatus.cerrado) {
                  Navigator.of(context).pop();
                  return;
                }
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('¿Cerrar el local por hoy?'),
                    content: const Text(
                      'No recibirás nuevas preórdenes ni pedidos grupales.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Cerrar local'),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                await selectStatus(
                  () => notifier.setStatus(ManualOccupancyStatus.cerrado),
                );
              },
            ),
          ],
        ),
      ),
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
    ref.listen<AsyncValue<List<PendingTable>>>(pendingTablesProvider, (prev, next) {
      final prevCount = prev?.value?.length;
      final nextCount = next.value?.length;
      if (prevCount != null && nextCount != null && nextCount > prevCount) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.alert);
      }
    });
    final ordersCount = ref.watch(ordersOnTheWayProvider).value ?? 0;
    final tablesCount = ref.watch(pendingTablesProvider).value?.length ?? 0;
    final count = ordersCount + tablesCount;
    final stripText = tablesCount > 0 && ordersCount > 0
        ? '$ordersCount pedidos · $tablesCount ${tablesCount == 1 ? 'mesa' : 'mesas'} en camino'
        : tablesCount > 0
            ? '$tablesCount ${tablesCount == 1 ? 'mesa grupal' : 'mesas grupales'} en camino'
            : '$count en camino';
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
              child: Text(stripText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    final b = context.bocadooColors;
    final offer = ref.watch(activeOfferProvider).value;
    final tables = ref.watch(pendingTablesProvider).value ?? const <PendingTable>[];
    final planRequests =
        ref.watch(planRequestsProvider).value ?? const <OwnerPlanRequest>[];
    final posMenuAsync = ref.watch(posMenuProvider);
    final menuAvailability = ref.watch(menuAvailabilityProvider);
    final scanLocked =
        posMenuAsync.hasValue && menuAvailability == MenuAvailabilityState.sinPublicar;
    final isOwner = ref.watch(ownerRoleProvider) == OwnerRole.owner;
    final movementsState = ref.watch(cajaMovementsProvider);
    final movementsNotifier = ref.read(cajaMovementsProvider.notifier);
    final todayStr = EcuadorTime.today();
    final isViewingToday = movementsState.selectedDate == todayStr;
    final totalCollected = Money.fromCents(movementsState.totalCollectedCents);

    Future<void> pickDate() async {
      if (!isOwner) return;
      final nowEc = EcuadorTime.now();
      final parsed = DateTime.tryParse(movementsState.selectedDate) ?? nowEc;
      final picked = await showDatePicker(
        context: context,
        initialDate: parsed.isAfter(nowEc) ? nowEc : parsed,
        firstDate: DateTime(2024, 1, 1),
        lastDate: nowEc,
      );
      if (picked != null) {
        await movementsNotifier.selectDate(picked);
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dailySummaryProvider);
        ref.invalidate(ordersOnTheWayProvider);
        ref.invalidate(pendingTablesProvider);
        ref.invalidate(posMenuProvider);
        await Future.wait([
          movementsNotifier.refresh(),
          ref.read(manualOccupancyProvider.notifier).refreshFromServer(),
        ]);
      },
      child: ListView(
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
                unawaited(movementsNotifier.refresh());
              },
            ),
            const SizedBox(height: 10),
          ],
          if (scanLocked) ...[
            _PublishMenuWarningBanner(
              onPublishTap: () => context.go('/owner/menu'),
            ),
            const SizedBox(height: 12),
          ],
          _ScanCard(
            enabled: !scanLocked,
            onTap: scanLocked ? null : () => openScannerFlow(context, ref),
          ),
          if (offer != null) ...[
            const SizedBox(height: 12),
            _OfferBanner(
              text: '${offer.slots} cupos a ${OwnerFormat.money(offer.price)}',
              onTap: () => context.push('/owner/oferta-flash'),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () async {
              await context.push('/owner/registrar-consumo');
              unawaited(movementsNotifier.refresh());
            },
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
                onTap: () async {
                  await context.push('/owner/vender-plan');
                  unawaited(movementsNotifier.refresh());
                },
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
            Expanded(
              child: OwnerSectionLabel(
                isViewingToday
                    ? 'Cobros de hoy'
                    : 'Movimientos · ${movementsState.selectedDate}',
              ),
            ),
            if (isOwner) ...[
              if (!isViewingToday) ...[
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => movementsNotifier.loadDate(todayStr),
                  child: const Text('Hoy'),
                ),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                onTap: pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isViewingToday ? 'Hoy' : movementsState.selectedDate,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ]),
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Solo hoy',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ]),
              ),
            const SizedBox(width: 10),
            Text(
              OwnerFormat.money(totalCollected),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
          ]),
          if (movementsState.warningMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: b.walletAccent.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: b.walletAccent),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 18, color: b.onWalletAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    movementsState.warningMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: b.onWalletAccent,
                    ),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          if (movementsState.isLoading && movementsState.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (movementsState.errorMessage != null &&
              movementsState.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Text(
                  movementsState.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: b.onDangerContainer,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: movementsNotifier.refresh,
                  child: const Text('Reintentar'),
                ),
              ]),
            )
          else if (movementsState.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                isViewingToday ? 'Aún sin movimientos' : 'Sin movimientos en esta fecha',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            for (final m in movementsState.items) _MovementRow(item: m),
            if (movementsState.hasMore) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed:
                    movementsState.isLoadingMore ? null : movementsNotifier.loadMore,
                icon: movementsState.isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  movementsState.isLoadingMore ? 'Cargando…' : 'Cargar más',
                ),
              ),
            ],
          ],
        ],
      ),
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

class _PublishMenuWarningBanner extends StatelessWidget {
  const _PublishMenuWarningBanner({required this.onPublishTap});

  final VoidCallback onPublishTap;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: b.walletAccent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 22, color: b.onWalletAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '⚠️ Publica el Menú de hoy para habilitar el escaneo de QR',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                    color: b.onWalletAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onPublishTap,
              style: FilledButton.styleFrom(
                backgroundColor: b.onWalletAccent,
                foregroundColor: b.walletAccent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
              ),
              child: const Text(
                'Ir a publicar menú →',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onTap, this.enabled = true});

  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: enabled
          ? 'Escanear pase de comensal'
          : 'Escáner bloqueado hasta publicar el menú de hoy',
      child: Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: DashedBorderBox(
          color: enabled ? colors.primary : colors.outlineVariant,
          fill: enabled
              ? Theme.of(context).scaffoldBackgroundColor
              : colors.secondaryContainer.withValues(alpha: 0.35),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              height: 230,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: enabled ? colors.primary : colors.outlineVariant,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    enabled ? Icons.qr_code_2_rounded : Icons.lock_clock_rounded,
                    size: 40,
                    color: enabled ? colors.onPrimary : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Escanear QR',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: enabled ? colors.onSurface : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Plan, preorden o mesa: se reconoce solo'
                      : 'Publica el Menú de hoy para activar el escáner',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ]),
            ),
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

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.item});

  final CajaMovement item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;

    final Widget trailing;
    final String? infoLine;

    switch (item.tipo) {
      case CajaMovementType.venta:
        final countsAsCash = item.cashCollectedCents > 0 ||
            (item.pagoEstado?.toUpperCase() == 'CONFIRMADO' && !item.revertido);
        final amountText = OwnerFormat.money(Money.fromCents(item.montoCentavos ?? 0));
        infoLine = [
          if (item.subtitle != null && item.subtitle!.isNotEmpty) item.subtitle!,
          if (item.metodoPago != null && item.metodoPago!.isNotEmpty && item.subtitle != item.metodoPago)
            item.metodoPago!,
          if (item.timestamp != null) OwnerFormat.time(item.timestamp!),
        ].join(' · ');
        trailing = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              amountText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                decoration: item.revertido ? TextDecoration.lineThrough : null,
                color: countsAsCash ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
            if (item.revertido)
              Text(
                'Revertida',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: b.onDangerContainer,
                ),
              )
            else if (item.pagoEstado?.toUpperCase() != 'CONFIRMADO')
              Text(
                'Pendiente',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        );
      case CajaMovementType.pedido:
        final refCents = item.valorPedidoCentavos ?? 0;
        infoLine = [
          if (item.subtitle != null && item.subtitle!.isNotEmpty) item.subtitle!,
          if (item.timestamp != null) OwnerFormat.time(item.timestamp!),
        ].join(' · ');
        trailing = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: Text(
                'Pedido',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Ref. ${OwnerFormat.money(Money.fromCents(refCents))}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        );
      case CajaMovementType.canjeDirecto:
        final dish = (item.platoNombre != null && item.platoNombre!.isNotEmpty)
            ? item.platoNombre!
            : 'Almuerzo del día (Prepagado)';
        infoLine = [
          dish,
          if (item.planNombre != null && item.planNombre!.isNotEmpty) item.planNombre!,
          if (item.timestamp != null) OwnerFormat.time(item.timestamp!),
        ].join(' · ');
        trailing = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: Text(
                'Prepagado',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '\$0,00',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
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
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  infoLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
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
                for (final m in const [
                  OwnerPayMethod.efectivo,
                  OwnerPayMethod.transferencia,
                  OwnerPayMethod.deuna,
                ]) ...[
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
      unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
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
