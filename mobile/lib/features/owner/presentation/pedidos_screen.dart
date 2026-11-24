import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/resolved_orders_store.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/extras_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

String _arrivalLabel(OwnerOrder order) {
  final raw = order.estimatedArrivalLabel?.trim();
  if (raw != null && raw.isNotEmpty && raw != 'En 15 min') {
    return raw;
  }
  final target =
      order.estimatedArrival ?? order.createdAt.add(const Duration(minutes: 15));
  return OwnerFormat.time24(target);
}

/// O12 · Pedidos en camino: preórdenes por cobrar o canjear (Efectivo / Transfer. / Deuna) y entregar.
/// [chargeNumber] abre directo el modal POS (QR `BCD-ORD-…` del escáner).
class PedidosScreen extends ConsumerStatefulWidget {
  const PedidosScreen({super.key, this.chargeNumber});

  final String? chargeNumber;

  @override
  ConsumerState<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends ConsumerState<PedidosScreen> {
  bool _autoHandled = false;

  void _refresh() {
    ref.invalidate(activeOrdersProvider);
    ref.invalidate(ordersOnTheWayProvider);
    ref.invalidate(pendingTablesProvider);
    ref.invalidate(dailySummaryProvider);
    ref.invalidate(ownerClientsProvider);
    unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
    unawaited(
      ref.read(cajaLiveSyncProvider.notifier).syncNow(includeMovements: true),
    );
  }

  OwnerClient? _resolveActivePlanClient(
    List<OwnerClient> clients,
    OwnerOrder order,
  ) {
    final activeClients = clients.where((c) => c.activeLunches > 0).toList();
    if (activeClients.isEmpty) return null;
    if (!AppMode.useMock) {
      final clientId =
          ref.read(apiOwnerRepositoryProvider).clientIdForOrder(order.number);
      if (clientId != null && clientId.isNotEmpty) {
        final byId = activeClients.where((c) => c.id == clientId).firstOrNull;
        if (byId != null) return byId;
      }
    }
    final normalizedName = order.dinerName.trim().toLowerCase();
    if (normalizedName.isEmpty) return null;
    final byName = activeClients
        .where((c) => c.name.trim().toLowerCase() == normalizedName)
        .toList();
    if (byName.length == 1) return byName.first;
    return null;
  }

  void _maybeOpenFromScanner(
    List<OwnerOrder> orders,
    List<OwnerClient> clients,
  ) {
    final number = widget.chargeNumber;
    if (_autoHandled || number == null) return;
    _autoHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final order = orders.where((o) => o.number == number).firstOrNull;
      if (order == null) {
        showInfoSnackBar(
          ScaffoldMessenger.of(context),
          'No hay un pedido #$number por entregar.',
        );
        return;
      }
      _openPosChargeSheet(
        order,
        planOverrideClient: _resolveActivePlanClient(clients, order),
      );
    });
  }

  /// Flujo unificado de tarjeta (`Cobrar y entregar` y `Descontar 1 almuerzo`):
  /// navega directo al escáner QR pasando el pedido esperado y luego abre el modal POS.
  Future<void> _act(OwnerOrder order, {OwnerClient? planOverrideClient}) async {
    final verifiedOrder = await context.push<OwnerOrder?>(
      '/owner/scanner',
      extra: order,
    );
    if (!mounted || verifiedOrder == null) return;
    final clients =
        ref.read(ownerClientsProvider).value ?? const <OwnerClient>[];
    final resolvedClient =
        planOverrideClient ?? _resolveActivePlanClient(clients, verifiedOrder);
    await _openPosChargeSheet(
      verifiedOrder,
      planOverrideClient: resolvedClient,
    );
  }

  Future<void> _openPosChargeSheet(
    OwnerOrder order, {
    OwnerClient? planOverrideClient,
  }) async {
    final overrideLunches = !order.paidByPlan &&
            planOverrideClient != null &&
            planOverrideClient.activeLunches > 0
        ? planOverrideClient.activeLunches
        : null;
    final payment = await _openSheet<({OwnerPayMethod method, int changeCents})>(
      _OrderConfirmChargeSheet(
        order: order,
        planOverrideLunches: overrideLunches,
      ),
    );
    if (payment == null || !mounted) return;
    await _confirmOrder(
      order,
      planOverrideClient: planOverrideClient,
      paymentMethod: payment.method,
      changeCents: payment.changeCents,
    );
  }

  Future<void> _handleSaldoCambioDialog(
    OwnerOrder order,
    OwnerPayMethod paymentMethod,
  ) async {
    final apiRepo = ref.read(apiOwnerRepositoryProvider);
    final conflict = apiRepo.consumeSaldoCambioConflict();
    if (!mounted || conflict == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final restaurantId = ref.read(ownerRestaurantIdProvider);
    final newSaldoFormatted =
        OwnerFormat.money(Money.fromCents(conflict.newBalanceCents));

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('El saldo de #${order.number} cambió'),
        content: Text(
          conflict.coveredByPlan && conflict.newBalanceCents == 0
              ? 'El comensal (${order.dinerName}) ya tiene un plan activo que cubre el almuerzo ($newSaldoFormatted por cobrar). ¿Deseas confirmar el canje con el nuevo saldo o marcarlo como ya cubierto hoy?'
              : 'El saldo recalculado en caja ahora es $newSaldoFormatted. ¿Deseas confirmar con este nuevo saldo o marcar la preorden como ya cubierta hoy?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('already_covered'),
            child: const Text('Ya cobrado / cubierto'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('confirm'),
            child: Text(
              conflict.newBalanceCents == 0
                  ? 'Confirmar (\$0,00)'
                  : 'Confirmar $newSaldoFormatted',
            ),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'cancel') return;

    if (choice == 'already_covered') {
      await ResolvedOrdersStore.instance.markResolved(
        id: order.id,
        number: order.number,
      );
      if (!mounted) return;
      _refresh();
      showInfoSnackBar(
        messenger,
        'Pedido #${order.number} marcado como resuelto hoy.',
      );
      return;
    }

    final retryRes = await apiRepo.confirmRedeemWithExpectedBalance(
      conflict.orderId,
      conflict.orderNumber,
      restaurantId,
      saldoEsperadoCentavos: conflict.newBalanceCents,
      paymentMethod: paymentMethod,
    );
    if (!mounted) return;
    _refresh();
    if (retryRes.actionRequired == 'CONFIRM_SALDO_CAMBIO') {
      await _handleSaldoCambioDialog(order, paymentMethod);
      return;
    }
    showInfoSnackBar(
      messenger,
      retryRes.supportingLine.isNotEmpty
          ? '${retryRes.title} · ${retryRes.supportingLine}'
          : retryRes.title,
    );
  }

  Future<void> _confirmOrder(
    OwnerOrder order, {
    OwnerClient? planOverrideClient,
    OwnerPayMethod paymentMethod = OwnerPayMethod.efectivo,
    int changeCents = 0,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ownerOrdersRepositoryProvider);
    final restaurantId = ref.read(ownerRestaurantIdProvider);
    final usePlanPriority = !order.paidByPlan &&
        planOverrideClient != null &&
        planOverrideClient.activeLunches > 0 &&
        !AppMode.useMock;
    final res = usePlanPriority
        ? await ref
            .read(apiOwnerRepositoryProvider)
            .confirmOrderWithPlanPriority(
              order.number,
              restaurantId,
              clientId: planOverrideClient.id,
              paymentMethod: paymentMethod,
            )
        : await repo.confirmAndRedeemOrder(
            order.number,
            restaurantId,
            paymentMethod: paymentMethod,
          );
    if (!mounted) return;
    _refresh();
    if (res.actionRequired == 'CONFIRM_SALDO_CAMBIO' && !AppMode.useMock) {
      await _handleSaldoCambioDialog(order, paymentMethod);
      return;
    }
    if (res.isValid && res.actionRequired == 'ALREADY_COVERED') {
      showInfoSnackBar(
        messenger,
        'Pedido #${order.number} ya estaba cubierto hoy y salió de la lista.',
      );
      return;
    }
    if (!res.isValid) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      showInfoSnackBar(
        messenger,
        res.supportingLine.isNotEmpty
            ? res.supportingLine
            : (apiErr ?? 'No se pudo completar el pedido #${order.number}.'),
      );
      return;
    }

    if ((order.paidByPlan && order.cashToCollectCents <= 0) || usePlanPriority) {
      showInfoSnackBar(messenger, '${res.title} · ${res.supportingLine}');
      return;
    }

    final totalText = OwnerFormat.money(
      Money.fromCents(order.effectiveBalanceToCollectCents),
    );
    final changeText = changeCents > 0
        ? ' · Cambio ${OwnerFormat.money(Money.fromCents(changeCents))}'
        : '';
    showInfoSnackBar(
      messenger,
      order.paidByPlan
          ? 'Plan canjeado y diferencia cobrada ($totalText · ${paymentMethod.label})$changeText'
          : 'Pedido #${order.number} cobrado ($totalText · ${paymentMethod.label})$changeText y entregado',
    );
  }

  Future<T?> _openSheet<T>(Widget child) => showModalBottomSheet<T>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => child,
      );

  void _back() => context.go('/owner/caja');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final orders = ref.watch(activeOrdersProvider);
    final movements = ref.watch(cajaMovementsProvider).items;
    final visibleOrdersAsync = orders.whenData(
      (list) => ResolvedOrdersStore.instance.filterOrdersSync(
        list,
        movements: movements,
      ),
    );
    final clients =
        ref.watch(ownerClientsProvider).value ?? const <OwnerClient>[];
    final tables = ref.watch(pendingTablesProvider).value ?? const <PendingTable>[];
    final lunchesToday =
        ref.watch(dailySummaryProvider).value?.lunchesRedeemedToday ?? 0;
    final count = (visibleOrdersAsync.value?.length ?? 0) + tables.length;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
            child: OwnerBackHeader(
              title: 'Pedidos en camino',
              onBack: _back,
              trailing: OwnerBadge(
                label: count == 1 ? '1 activo' : '$count activos',
                background: colors.primaryContainer,
                foreground: colors.onPrimaryContainer,
              ),
            ),
          ),
          Expanded(
            child: visibleOrdersAsync.when(
              skipLoadingOnReload: true,
              loading: () => const OwnerLoadingView('Cargando pedidos'),
              error: (_, _) => OwnerErrorView(
                title: 'Error al cargar pedidos',
                message: 'No se pudieron sincronizar los pedidos.',
                onRetry: _refresh,
              ),
              data: (list) {
                _maybeOpenFromScanner(list, clients);
                if (list.isEmpty && tables.isEmpty) {
                  return _Empty(
                    onBack: _back,
                    hasDispatchedToday: lunchesToday > 0,
                  );
                }
                final totalItems = tables.length + list.length;
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: totalItems,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      if (i < tables.length) {
                        final t = tables[i];
                        return _TableOrderCard(
                          table: t,
                          onAction: () async {
                            await context.push('/owner/cobrar-mesa/${t.id}');
                            if (mounted) _refresh();
                          },
                        );
                      }
                      final order = list[i - tables.length];
                      final matchedClient =
                          _resolveActivePlanClient(clients, order);
                      final planLunches = !order.paidByPlan &&
                              matchedClient != null &&
                              matchedClient.activeLunches > 0
                          ? matchedClient.activeLunches
                          : null;
                      return _OrderCard(
                        order: order,
                        planOverrideLunches: planLunches,
                        onAction: () => _act(
                          order,
                          planOverrideClient: matchedClient,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _TableOrderCard extends StatelessWidget {
  const _TableOrderCard({required this.table, required this.onAction});

  final PendingTable table;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final modalityText = table.takeawayCount > 0
        ? 'Para llevar (+${OwnerFormat.money(Money.fromCents(table.takeawaySurchargeCents))})'
        : 'En local';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  table.hostName.startsWith('Mesa ')
                      ? '👥 ${table.hostName} · #${table.shortId} (${table.members} pers.)'
                      : '👥 Mesa #${table.shortId} · ${table.hostName} (${table.members} pers.)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 15, color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Llega ${table.time}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (table.isCollecting) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OwnerBadge(
                label:
                    'Esperando invitados (${table.confirmedCount ?? table.members}/${table.members} listos)',
                background: colors.secondaryContainer,
                foreground: colors.onSecondaryContainer,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Modalidad: ',
                        style: TextStyle(fontWeight: FontWeight.w800, color: colors.primary),
                      ),
                      TextSpan(text: modalityText),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                if (table.memberDishes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final m in table.memberDishes) ...[
                    Builder(
                      builder: (_) {
                        final chosen = [m.soup, m.main]
                            .where((s) => s != null && s.trim().isNotEmpty)
                            .join(' + ');
                        final extrasText = m.extras.isNotEmpty
                            ? 'Extras: ${m.extras.join(', ')}'
                            : '';
                        final combined = [
                          if (chosen.isNotEmpty) chosen,
                          if (extrasText.isNotEmpty) extrasText,
                        ].join(' · ');
                        final dishText =
                            combined.isNotEmpty ? combined : 'Sin selección aún';
                        final extraTag = m.takeaway ? ' (Para llevar)' : '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '• ${m.memberName}: $dishText$extraTag',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OwnerBadge(
                label: '${table.planCount} con Plan · ${table.cashCount} pagan en caja',
                background: table.cashCount == 0
                    ? b.successContainer
                    : colors.secondaryContainer,
                foreground: table.cashCount == 0
                    ? b.onSuccessContainer
                    : colors.onSecondaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.point_of_sale_rounded, size: 18),
            label: const Text('Cobrar mesa'),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onAction,
    this.planOverrideLunches,
  });

  final OwnerOrder order;
  final VoidCallback onAction;
  final int? planOverrideLunches;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final arrival = _arrivalLabel(order);
    final isPlan = order.hasPlanLineInQuote ||
        order.paidByPlan ||
        (planOverrideLunches != null && planOverrideLunches! > 0);
    TextSpan line(String label, String value) => TextSpan(children: [
          TextSpan(text: '$label: ', style: TextStyle(fontWeight: FontWeight.w800, color: colors.primary)),
          TextSpan(text: value),
        ]);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
            child: Text('#${order.number}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onPrimaryContainer)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(order.dinerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          Icon(Icons.schedule_rounded, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'Llega $arrival',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text.rich(
            TextSpan(children: [
              if (order.soup != null) line('Sopa', order.soup!),
              if (order.soup != null && order.main != null) const TextSpan(text: '\n'),
              if (order.main != null) line('Segundo', order.main!),
              if (order.drink != null) ...[
                if (order.soup != null || order.main != null) const TextSpan(text: '\n'),
                line('Jugo', order.drink!),
              ],
              if (order.cashItems.isNotEmpty) ...[
                if (order.soup != null || order.main != null || order.drink != null)
                  const TextSpan(text: '\n'),
                line('Carta / Extras', order.cashItems.join(', ')),
              ],
              const TextSpan(text: '\n'),
              line(
                'Modalidad',
                order.takeaway
                    ? 'Para llevar (+${OwnerFormat.money(Money.fromCents(order.takeawaySurchargeCents))})'
                    : 'En local',
              ),
              const TextSpan(text: '\n'),
              line('Llegada est.', arrival),
              if (!isPlan) ...[
                const TextSpan(text: '\n'),
                line('Pago', 'Pago por confirmar en caja'),
              ] else if (order.paidByPlan && order.cashToCollectCents > 0) ...[
                const TextSpan(text: '\n'),
                line(
                  'Saldo por cobrar',
                  OwnerFormat.money(Money.fromCents(order.cashToCollectCents)),
                ),
              ] else ...[
                const TextSpan(text: '\n'),
                line('Cobertura', '1 almuerzo del plan activo'),
              ],
            ]),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: colors.onSurface),
          ),
        ),
        const SizedBox(height: 12),
        if (!isPlan)
          // Preorden sin plan: abre escáner QR -> modal POS Confirmar cobro.
          LayoutBuilder(
            builder: (context, constraints) {
              final labelRow = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.payments_outlined, size: 18, color: colors.onSurface),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Por cobrar · ${OwnerFormat.money(Money.fromCents(order.effectiveBalanceToCollectCents))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              );
              final actionBtn = OwnerSmallButton(
                label: 'Cobrar y entregar',
                icon: Icons.qr_code_scanner_rounded,
                onPressed: onAction,
              );
              if (constraints.maxWidth < 330) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labelRow,
                    const SizedBox(height: 10),
                    actionBtn,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: labelRow),
                  const SizedBox(width: 8),
                  actionBtn,
                ],
              );
            },
          )
        else
          // Preorden cubierta por plan activo: descuenta 1 almuerzo del plan y entrega.
          LayoutBuilder(
            builder: (context, constraints) {
              final badge = OwnerBadge(
                label: (planOverrideLunches != null && !order.hasPlanLineInQuote)
                    ? 'Plan activo · Cubierto por plan ($planOverrideLunches disp.)'
                    : 'Plan activo · Cubierto por plan',
                background: b.successContainer,
                foreground: b.onSuccessContainer,
              );
              final actionBtn = OwnerSmallButton(
                label: 'Descontar 1 almuerzo',
                icon: Icons.qr_code_scanner_rounded,
                onPressed: onAction,
              );
              if (constraints.maxWidth < 330) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: badge),
                    const SizedBox(height: 10),
                    actionBtn,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: badge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  actionBtn,
                ],
              );
            },
          ),
      ]),
    );
  }
}

/// Modal POS unificado ("Descontar 1 almuerzo del plan" para pedidos con plan activo
/// y "Confirmar cobro" para pedidos sin plan) abierto tras validar el QR.
class _OrderConfirmChargeSheet extends StatefulWidget {
  const _OrderConfirmChargeSheet({
    required this.order,
    this.planOverrideLunches,
  });

  final OwnerOrder order;
  final int? planOverrideLunches;

  @override
  State<_OrderConfirmChargeSheet> createState() =>
      _OrderConfirmChargeSheetState();
}

class _OrderConfirmChargeSheetState extends State<_OrderConfirmChargeSheet> {
  OwnerPayMethod _method = OwnerPayMethod.efectivo;
  final TextEditingController _cash = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  static String _fmt(int cents) => OwnerFormat.money(Money.fromCents(cents));

  static int? _parseCents(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final val = double.tryParse(cleaned);
    if (val == null || val < 0) return null;
    return (val * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final order = widget.order;
    final hasPlanOverride =
        !order.paidByPlan &&
        !order.hasPlanLineInQuote &&
        widget.planOverrideLunches != null &&
        widget.planOverrideLunches! > 0;
    final isPlan = order.hasPlanLineInQuote || order.paidByPlan || hasPlanOverride;
    final totalCents = hasPlanOverride
        ? 0
        : order.effectiveBalanceToCollectCents;
    final hasCashToCollect = totalCents > 0;
    final arrival = _arrivalLabel(order);
    final dishesParts = [
      if (order.soup != null && order.soup!.trim().isNotEmpty) order.soup!.trim(),
      if (order.main != null && order.main!.trim().isNotEmpty) order.main!.trim(),
      if (order.drink != null && order.drink!.trim().isNotEmpty) order.drink!.trim(),
      ...order.cashItems,
    ];
    final dishesSummary =
        dishesParts.isNotEmpty ? dishesParts.join(' · ') : 'Almuerzo del día';
    final modalityLabel = order.takeaway ? 'Para llevar' : 'En local';

    final isCash = _method == OwnerPayMethod.efectivo && hasCashToCollect;
    final receivedCents = isCash ? _parseCents(_cash.text) : null;
    final invalid =
        isCash && _cash.text.trim().isNotEmpty && receivedCents == null;
    final shortfall =
        isCash && receivedCents != null && receivedCents < totalCents;
    final changeCents =
        receivedCents == null ? 0 : receivedCents - totalCents;
    final canConfirm = !isCash || (!invalid && !shortfall);
    final bills = [5, 10, 20].where((v) => v * 100 >= totalCents).toList();
    final totalFormatted = _fmt(totalCents);

    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final sysNav = mq.viewPadding.bottom;
    final safeBottom = mq.padding.bottom;
    final navClearance =
        keyboard > 0 ? 0.0 : (sysNav - safeBottom).clamp(0.0, double.infinity);

    final primaryButtonLabel = isPlan
        ? (hasCashToCollect
            ? 'Descontar 1 almuerzo y cobrar · $totalFormatted'
            : 'Descontar 1 almuerzo del plan')
        : 'Confirmar cobro y entrega · $totalFormatted';
    final headlineMetric = isPlan
        ? (hasCashToCollect ? totalFormatted : '1 almuerzo')
        : totalFormatted;

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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isPlan
                            ? 'Descontar 1 almuerzo del plan'
                            : 'Confirmar cobro',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Material(
                  color: colors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${order.dinerName} · Pedido #${order.number}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    headlineMetric,
                                    style: TextStyle(
                                      fontSize: isPlan && !hasCashToCollect
                                          ? 20
                                          : 24,
                                      fontWeight: FontWeight.w900,
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _expanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 22,
                                    color: colors.primary,
                                  ),
                                ],
                              ),
                              if (isPlan) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    OwnerBadge(
                                      label: hasPlanOverride
                                          ? 'Plan activo (${widget.planOverrideLunches} disp.) · 1 almuerzo'
                                          : 'Plan activo · 1 almuerzo',
                                      background: b.successContainer,
                                      foreground: b.onSuccessContainer,
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                '$dishesSummary · $modalityLabel',
                                maxLines: _expanded ? 4 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: Container(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: colors.outlineVariant.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _OrderDetailLine(
                                      label: 'Turno',
                                      value: '#${order.number} · Llega $arrival',
                                    ),
                                    if (order.soup != null &&
                                        order.soup!.trim().isNotEmpty)
                                      _OrderDetailLine(
                                        label: 'Sopa',
                                        value: order.soup!.trim(),
                                      ),
                                    if (order.main != null &&
                                        order.main!.trim().isNotEmpty)
                                      _OrderDetailLine(
                                        label: 'Segundo',
                                        value: order.main!.trim(),
                                      ),
                                    if (order.drink != null &&
                                        order.drink!.trim().isNotEmpty)
                                      _OrderDetailLine(
                                        label: 'Jugo',
                                        value: order.drink!.trim(),
                                      ),
                                    if (order.cashItems.isNotEmpty)
                                      _OrderDetailLine(
                                        label: 'Carta / Extras',
                                        value: order.cashItems.join(', '),
                                      ),
                                    _OrderDetailLine(
                                      label: 'Modalidad',
                                      value: order.takeaway
                                          ? 'Para llevar (+${_fmt(order.takeawaySurchargeCents)})'
                                          : 'En local',
                                    ),
                                    if (isPlan)
                                      _OrderDetailLine(
                                        label: hasCashToCollect
                                            ? 'Saldo por cobrar'
                                            : 'Descuento del plan',
                                        value: hasCashToCollect
                                            ? totalFormatted
                                            : '1 almuerzo del plan',
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        crossFadeState: _expanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 180),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const OwnerSectionLabel('Método de pago'),
                    if (!hasCashToCollect) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '1 almuerzo del plan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: b.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
                        child: Builder(
                          builder: (context) {
                            final selected = hasCashToCollect && _method == m;
                            final bg = !hasCashToCollect
                                ? colors.surfaceContainerHighest.withValues(alpha: 0.45)
                                : (selected
                                    ? colors.primary
                                    : Theme.of(context).scaffoldBackgroundColor);
                            final fg = !hasCashToCollect
                                ? colors.onSurfaceVariant.withValues(alpha: 0.55)
                                : (selected ? colors.onPrimary : colors.onSurface);
                            return Material(
                              color: bg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: selected
                                      ? colors.primary
                                      : colors.outlineVariant.withValues(
                                          alpha: hasCashToCollect ? 1 : 0.6,
                                        ),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: hasCashToCollect
                                    ? () => setState(() {
                                          _method = m;
                                          if (m != OwnerPayMethod.efectivo) {
                                            _cash.clear();
                                          }
                                        })
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 20, color: fg),
                                      const SizedBox(height: 4),
                                      Text(
                                        m.shortLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: fg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                if (isCash) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cash,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
                          decoration: InputDecoration(
                            isDense: true,
                            prefixText: '\$ ',
                            hintText: 'Efectivo recibido (opcional)',
                            errorText: invalid
                                ? 'Monto inválido'
                                : (shortfall
                                    ? 'Faltan ${_fmt(totalCents - receivedCents)}'
                                    : null),
                          ),
                        ),
                      ),
                      if (changeCents > 0) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: b.successContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Cambio ${_fmt(changeCents)}',
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
                    runSpacing: 6,
                    children: [
                      for (final v in bills)
                        ActionChip(
                          label: Text('\$$v'),
                          onPressed: () => setState(() => _cash.text = '$v'),
                        ),
                      ActionChip(
                        label: const Text('Exacto'),
                        onPressed: () => setState(() => _cash.clear()),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: canConfirm
                      ? () => Navigator.of(context).pop((
                            method: _method,
                            changeCents: changeCents > 0 ? changeCents : 0,
                          ))
                      : null,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    primaryButtonLabel,
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

class _OrderDetailLine extends StatelessWidget {
  const _OrderDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onBack, required this.hasDispatchedToday});

  final VoidCallback onBack;
  final bool hasDispatchedToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.schedule_rounded, size: 52, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('Sin pedidos pendientes',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text(
              hasDispatchedToday
                  ? 'Todos los almuerzos fueron despachados.'
                  : 'Aún no hay comensales en camino para el menú de hoy.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onBack, child: const Text('Volver a caja')),
        ]),
      ),
    );
  }
}
