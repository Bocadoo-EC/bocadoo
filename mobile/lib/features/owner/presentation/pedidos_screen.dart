import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/models/extras_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

String _ago(DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'Ahora';
  if (m < 60) return 'Hace $m min';
  return 'Hace ${m ~/ 60} h';
}

/// "Locro de papa con queso" → "Locro de papa".
String _short(String? dish) {
  if (dish == null) return '';
  final i = dish.indexOf(' con ');
  return i > 0 ? dish.substring(0, i) : dish;
}

/// O12 · Pedidos en camino: preórdenes por cobrar (solo efectivo) y entregar.
/// [chargeNumber] abre directo la hoja de cobro (QR `BCD-ORD-…` del escáner).
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
    ref.invalidate(dailySummaryProvider);
  }

  void _maybeOpenFromScanner(List<OwnerOrder> orders) {
    final number = widget.chargeNumber;
    if (_autoHandled || number == null) return;
    _autoHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final order = orders.where((o) => o.number == number).firstOrNull;
      if (order == null) {
        showInfoSnackBar(ScaffoldMessenger.of(context), 'No hay un pedido #$number por entregar.');
        return;
      }
      _act(order);
    });
  }

  /// Qué hace el botón principal de la tarjeta según el pedido:
  /// con plan sin validar → validar su QR; con plan validado → entregar;
  /// en efectivo → cobrar y entregar.
  Future<void> _act(OwnerOrder order) {
    if (order.paidByPlan && !order.validated) return _validate(order);
    if (order.paidByPlan) return _deliver(order);
    return _charge(order);
  }

  Future<bool?> _openSheet(Widget child) => showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => child,
      );

  Future<void> _validate(OwnerOrder order) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await _openSheet(_ValidateOrderSheet(order: order)) != true || !mounted) return;
    final repo = ref.read(ownerOrdersRepositoryProvider);
    final restaurantId = ref.read(ownerRestaurantIdProvider);
    final ok = await repo.validateOrder(restaurantId, order.number);
    if (!mounted) return;
    _refresh();
    if (!ok) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      showInfoSnackBar(
        messenger,
        apiErr ?? 'No se pudo validar el pedido #${order.number}. Revisa el plan de ${order.dinerName}.',
      );
      return;
    }
    showUndoSnackBar(
      messenger,
      label: 'Pedido #${order.number} validado con el plan de ${order.dinerName.split(' ').first}',
      onUndo: () async {
        await repo.undoValidate(restaurantId, order.number);
        if (mounted) _refresh();
      },
    );
  }

  Future<void> _charge(OwnerOrder order) async {
    if (await _openSheet(_ChargeOrderSheet(order: order)) != true || !mounted) return;
    await _deliver(order);
  }

  Future<void> _deliver(OwnerOrder order) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ownerOrdersRepositoryProvider);
    final restaurantId = ref.read(ownerRestaurantIdProvider);
    final ok = await repo.deliverOrder(restaurantId, order.number);
    if (!mounted) return;
    _refresh();
    if (!ok) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      showInfoSnackBar(messenger, apiErr ?? 'No se pudo entregar el pedido #${order.number}');
      return;
    }
    showUndoSnackBar(
      messenger,
      label: 'Pedido #${order.number} entregado',
      onUndo: () async {
        await repo.undoDeliver(restaurantId, order.number);
        if (mounted) _refresh();
      },
    );
  }

  void _back() => context.go('/owner/caja');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final orders = ref.watch(activeOrdersProvider);
    final count = orders.value?.length ?? 0;

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
                if (list.isEmpty) return _Empty(onBack: _back);
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _OrderCard(order: list[i], onAction: () => _act(list[i])),
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onAction});

  final OwnerOrder order;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
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
          Text(_ago(order.createdAt),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
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
              if (order.takeaway) TextSpan(children: [const TextSpan(text: '\n'), line('Modalidad', 'Para llevar')]),
              if (order.paidByPlan) TextSpan(children: [const TextSpan(text: '\n'), line('Pago', 'Plan prepagado')]),
            ]),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: colors.onSurface),
          ),
        ),
        const SizedBox(height: 12),
        if (!order.paidByPlan)
          // En efectivo: se cobra y se entrega.
          Row(children: [
            Icon(Icons.payments_outlined, size: 18, color: colors.onSurface),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${OwnerFormat.money(order.amount)} en efectivo',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
            ),
            OwnerSmallButton(label: 'Cobrar y entregar', icon: Icons.check_circle_outline_rounded, onPressed: onAction),
          ])
        else
          // Con plan: se valida su QR y luego se entrega. No se cobra nada.
          Row(children: [
            Expanded(
              child: Text('QR: ${order.qrCode}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
            if (order.validated) ...[
              OwnerBadge(label: 'Validado', background: b.successContainer, foreground: b.onSuccessContainer),
              const SizedBox(width: 8),
              OwnerSmallButton(label: 'Entregar', icon: Icons.check_circle_outline_rounded, onPressed: onAction),
            ] else
              OwnerSmallButton(label: 'Validar QR', icon: Icons.qr_code_scanner_rounded, onPressed: onAction),
          ]),
      ]),
    );
  }
}

/// Hoja "Validar pedido #N": un pedido cubierto por plan se valida con su QR y
/// descuenta 1 almuerzo del plan del comensal. No se cobra nada.
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
              child: Text('Validar pedido #${order.number}',
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
              Text(order.qrCode,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.primary)),
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
            label: const Text('Validar con su plan'),
          ),
        ]),
      ),
    );
  }
}

/// Hoja "Cobrar pedido #N": las preórdenes se cobran solo en efectivo.
class _ChargeOrderSheet extends StatelessWidget {
  const _ChargeOrderSheet({required this.order});

  final OwnerOrder order;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final dishes = [_short(order.soup), _short(order.main)].where((d) => d.isNotEmpty).join(' + ');
    final amount = OwnerFormat.money(order.amount);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('Cobrar pedido #${order.number}',
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              dishes.isEmpty ? order.dinerName : '${order.dinerName} · $dishes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.onSurface),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.primary, width: 1.5),
            ),
            child: Row(children: [
              Icon(Icons.payments_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Efectivo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
              ),
              Text(amount, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: colors.onSurface)),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Las preórdenes se cobran solo en efectivo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: Text('Cobré $amount · Entregar'),
          ),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onBack});

  final VoidCallback onBack;

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
          Text('Todos los almuerzos fueron despachados.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onBack, child: const Text('Volver a caja')),
        ]),
      ),
    );
  }
}
