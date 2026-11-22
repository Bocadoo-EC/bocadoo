import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
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

/// "Locro de papa con queso" → "Locro de papa".
String _short(String? dish) {
  if (dish == null) return '';
  final i = dish.indexOf(' con ');
  return i > 0 ? dish.substring(0, i) : dish;
}

/// O12 · Pedidos en camino: preórdenes por cobrar (Efectivo / Transfer. / Deuna) y entregar.
/// [chargeNumber] abre directo el modal Confirmar cobro (QR `BCD-ORD-…` del escáner).
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
    unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
  }

  void _maybeOpenFromScanner(List<OwnerOrder> orders) {
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
      _openDirectConfirmForOrder(order);
    });
  }

  Future<void> _openDirectConfirmForOrder(OwnerOrder order) async {
    if (order.paidByPlan) {
      if (!order.validated) {
        final ok = await _openSheet<bool>(_ValidateOrderSheet(order: order));
        if (ok != true || !mounted) return;
      }
      await _confirmOrder(order);
      return;
    }
    await _openPosChargeSheet(order);
  }

  /// Flujo principal de tarjeta:
  /// - Con plan: confirma canje y entrega.
  /// - Sin plan ("Cobrar y entregar"): abre directo el escáner QR pasando el
  ///   pedido esperado y, al validar el QR, abre el modal Confirmar cobro estilo POS.
  Future<void> _act(OwnerOrder order) async {
    if (order.paidByPlan) {
      await _openDirectConfirmForOrder(order);
      return;
    }

    final verifiedOrder = await context.push<OwnerOrder?>(
      '/owner/scanner',
      extra: order,
    );
    if (!mounted || verifiedOrder == null) return;
    await _openPosChargeSheet(verifiedOrder);
  }

  Future<void> _openPosChargeSheet(OwnerOrder order) async {
    final payment = await _openSheet<({OwnerPayMethod method, int changeCents})>(
      _OrderConfirmChargeSheet(order: order),
    );
    if (payment == null || !mounted) return;
    await _confirmOrder(
      order,
      paymentMethod: payment.method,
      changeCents: payment.changeCents,
    );
  }

  Future<void> _confirmOrder(
    OwnerOrder order, {
    OwnerPayMethod paymentMethod = OwnerPayMethod.efectivo,
    int changeCents = 0,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ownerOrdersRepositoryProvider);
    final restaurantId = ref.read(ownerRestaurantIdProvider);
    final res = await repo.confirmAndRedeemOrder(
      order.number,
      restaurantId,
      paymentMethod: paymentMethod,
    );
    if (!mounted) return;
    _refresh();
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

    if (order.paidByPlan) {
      showInfoSnackBar(messenger, '${res.title} · ${res.supportingLine}');
      return;
    }

    final totalText = OwnerFormat.money(
      Money.fromCents(order.effectiveTotalCents),
    );
    final changeText = changeCents > 0
        ? ' · Cambio ${OwnerFormat.money(Money.fromCents(changeCents))}'
        : '';
    showInfoSnackBar(
      messenger,
      'Pedido #${order.number} cobrado ($totalText · ${paymentMethod.label})$changeText y entregado',
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
    final tables = ref.watch(pendingTablesProvider).value ?? const <PendingTable>[];
    final lunchesToday =
        ref.watch(dailySummaryProvider).value?.lunchesRedeemedToday ?? 0;
    final count = (orders.value?.length ?? 0) + tables.length;

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
            child: orders.when(
              skipLoadingOnReload: true,
              loading: () => const OwnerLoadingView('Cargando pedidos'),
              error: (_, _) => OwnerErrorView(
                title: 'Error al cargar pedidos',
                message: 'No se pudieron sincronizar los pedidos.',
                onRetry: _refresh,
              ),
              data: (list) {
                _maybeOpenFromScanner(list);
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
                      return _OrderCard(order: order, onAction: () => _act(order));
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
  const _OrderCard({required this.order, required this.onAction});

  final OwnerOrder order;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final arrival = _arrivalLabel(order);
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
              const TextSpan(text: '\n'),
              line(
                'Modalidad',
                order.takeaway
                    ? 'Para llevar (+${OwnerFormat.money(Money.fromCents(order.takeawaySurchargeCents))})'
                    : 'En local',
              ),
              const TextSpan(text: '\n'),
              line('Llegada est.', arrival),
              if (!order.paidByPlan) ...[
                const TextSpan(text: '\n'),
                line('Pago', 'Pago por confirmar en caja'),
              ],
            ]),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: colors.onSurface),
          ),
        ),
        const SizedBox(height: 12),
        if (!order.paidByPlan)
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
                      'Por cobrar · ${OwnerFormat.money(Money.fromCents(order.effectiveTotalCents))}',
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
          // Preorden con Plan (Prepagado): sin cobro en caja, se canjea y entrega.
          LayoutBuilder(
            builder: (context, constraints) {
              final badge = OwnerBadge(
                label: '🎫 Plan activo (Prepagado)',
                background: b.successContainer,
                foreground: b.onSuccessContainer,
              );
              final actionBtn = OwnerSmallButton(
                label: 'Canjear y entregar',
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

/// Hoja "Canjear pedido #N": un pedido cubierto por plan descuenta 1 almuerzo
/// mediante `POST /v1/caja/pedidos/{id}/canjear` y se entrega. No se cobra nada.
class _ValidateOrderSheet extends StatelessWidget {
  const _ValidateOrderSheet({required this.order});

  final OwnerOrder order;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final dishes = [_short(order.soup), _short(order.main)].where((d) => d.isNotEmpty).join(' + ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('Canjear pedido #${order.number}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
            ),
            IconButton.filledTonal(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colors.primary,
                child: Icon(Icons.qr_code_2_rounded, size: 32, color: colors.onPrimary),
              ),
              const SizedBox(height: 10),
              Text(order.dinerName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface)),
              if (dishes.isNotEmpty)
                Text(dishes, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('Llega ${_arrivalLabel(order)} · Plan activo (Prepagado)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Se descuenta 1 almuerzo de su plan. No se cobra nada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Canjear y entregar'),
          ),
        ]),
      ),
    );
  }
}

/// Modal POS "Confirmar cobro" abierto al validar el QR de una preorden sin plan.
/// Reutiliza el patrón de acordeón + 3 métodos + bloque de vuelto de caja POS.
class _OrderConfirmChargeSheet extends StatefulWidget {
  const _OrderConfirmChargeSheet({required this.order});

  final OwnerOrder order;

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
    final totalCents = order.effectiveTotalCents;
    final arrival = _arrivalLabel(order);
    final dishesParts = [
      if (order.soup != null && order.soup!.trim().isNotEmpty) order.soup!.trim(),
      if (order.main != null && order.main!.trim().isNotEmpty) order.main!.trim(),
    ];
    final dishesSummary =
        dishesParts.isNotEmpty ? dishesParts.join(' · ') : 'Almuerzo del día';
    final modalityLabel = order.takeaway ? 'Para llevar' : 'En local';

    final isCash = _method == OwnerPayMethod.efectivo && totalCents > 0;
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Confirmar cobro',
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
                                  totalFormatted,
                                  style: TextStyle(
                                    fontSize: 24,
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
                            const SizedBox(height: 4),
                            Text(
                              '$dishesSummary · $modalityLabel',
                              maxLines: _expanded ? 3 : 2,
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
              const OwnerSectionLabel('Método de pago'),
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
                      child: Material(
                        color: _method == m
                            ? colors.primary
                            : Theme.of(context).scaffoldBackgroundColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: _method == m
                                ? colors.primary
                                : colors.outlineVariant,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() {
                            _method = m;
                            if (m != OwnerPayMethod.efectivo) _cash.clear();
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 20,
                                  color: _method == m
                                      ? colors.onPrimary
                                      : colors.onSurface,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m.shortLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: _method == m
                                        ? colors.onPrimary
                                        : colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                  'Confirmar cobro y entrega · $totalFormatted',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
