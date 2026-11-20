import 'package:material_ui/material_ui.dart';

import '../../group_orders/presentation/group_order_flow_screen.dart';

/// C9 · Pedido grupal: delega en el flujo progresivo de 3 pasos con máquina de estados.
class TableSheet extends StatelessWidget {
  const TableSheet({super.key, this.restaurantId, this.groupOrderId});

  /// Local del pedido grupal. Sin él se usa el del pase o se elige uno.
  final String? restaurantId;

  /// ID de mesa activa para abrir directo en Paso 2 (collecting) o Paso 3 (confirmed).
  final String? groupOrderId;

  @override
  Widget build(BuildContext context) {
    return GroupOrderFlowScreen(
      restaurantId: restaurantId,
      groupOrderId: groupOrderId,
    );
  }
}
