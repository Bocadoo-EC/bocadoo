import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import 'owner_bottom_nav.dart';

enum _OrderStatus { preparing, ready, delivered }

class _OrderItem {
  final String number;
  final String customerName;
  final String detail;
  final _OrderStatus status;

  const _OrderItem({
    required this.number,
    required this.customerName,
    required this.detail,
    required this.status,
  });

  _OrderItem copyWith({_OrderStatus? status}) => _OrderItem(
        number: number,
        customerName: customerName,
        detail: detail,
        status: status ?? this.status,
      );
}

/// Pantalla de Pedidos / Preórdenes en camino para Cajero y Dueño.
class OwnerOrdersScreen extends ConsumerStatefulWidget {
  const OwnerOrdersScreen({super.key});

  @override
  ConsumerState<OwnerOrdersScreen> createState() => _OwnerOrdersScreenState();
}

class _OwnerOrdersScreenState extends ConsumerState<OwnerOrdersScreen> {
  _OrderStatus _filter = _OrderStatus.preparing;

  List<_OrderItem> _orders = const [
    _OrderItem(
      number: 'B-104',
      customerName: 'María José Paredes',
      detail: 'Seco de pollo · Para llevar · 12:45',
      status: _OrderStatus.preparing,
    ),
    _OrderItem(
      number: 'B-103',
      customerName: 'Andrés Salazar',
      detail: 'Locro + Guatita · En mesa · 12:35',
      status: _OrderStatus.ready,
    ),
    _OrderItem(
      number: 'B-101',
      customerName: 'Sofía Vintimilla',
      detail: 'Arroz con pollo · Entregado · 12:15',
      status: _OrderStatus.delivered,
    ),
  ];

  void _advanceStatus(String number) {
    setState(() {
      _orders = _orders.map((order) {
        if (order.number != number) return order;
        final next = order.status == _OrderStatus.preparing
            ? _OrderStatus.ready
            : _OrderStatus.delivered;
        return order.copyWith(status: next);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visible = _orders.where((o) => o.status == _filter).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pedidos del turno'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  _OrderFilterPill(
                    label: 'Preparando',
                    selected: _filter == _OrderStatus.preparing,
                    onTap: () =>
                        setState(() => _filter = _OrderStatus.preparing),
                  ),
                  _OrderFilterPill(
                    label: 'Listos',
                    selected: _filter == _OrderStatus.ready,
                    onTap: () => setState(() => _filter = _OrderStatus.ready),
                  ),
                  _OrderFilterPill(
                    label: 'Entregados',
                    selected: _filter == _OrderStatus.delivered,
                    onTap: () =>
                        setState(() => _filter = _OrderStatus.delivered),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      'No hay pedidos en esta etapa.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = visible[index];
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius:
                              BorderRadius.circular(AppTheme.cardRadius),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    order.number,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: colors.onPrimaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    order.customerName,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              order.detail,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            if (order.status != _OrderStatus.delivered) ...[
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: () => _advanceStatus(order.number),
                                child: Text(
                                  order.status == _OrderStatus.preparing
                                      ? 'Marcar listo'
                                      : 'Confirmar entrega',
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar:
          const OwnerBottomNav(currentRoute: '/owner/orders'),
    );
  }
}

class _OrderFilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OrderFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Expanded(
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

