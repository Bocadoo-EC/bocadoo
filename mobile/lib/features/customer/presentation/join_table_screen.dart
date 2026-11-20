import 'package:material_ui/material_ui.dart';

import '../../group_orders/presentation/guest_group_order_screen.dart';

/// C7 · Unirme a mesa: delega en [GuestGroupOrderScreen].
class JoinTableScreen extends StatelessWidget {
  const JoinTableScreen({super.key, required this.tableId});

  final String tableId;

  @override
  Widget build(BuildContext context) {
    return GuestGroupOrderScreen(tableId: tableId);
  }
}
