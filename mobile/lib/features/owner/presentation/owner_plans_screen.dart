import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import 'owner_bottom_nav.dart';
import 'sell_plan_modal.dart';

class _OwnerPlanPackage {
  final String id;
  final String name;
  final int lunches;
  final double totalPrice;
  final double savings;

  const _OwnerPlanPackage({
    required this.id,
    required this.name,
    required this.lunches,
    required this.totalPrice,
    required this.savings,
  });
}

/// Pantalla de Planes y Ofertas del Local para el Dueño.
class OwnerPlansScreen extends ConsumerStatefulWidget {
  const OwnerPlansScreen({super.key});

  @override
  ConsumerState<OwnerPlansScreen> createState() => _OwnerPlansScreenState();
}

class _OwnerPlansScreenState extends ConsumerState<OwnerPlansScreen> {
  final List<_OwnerPlanPackage> _packages = [
    const _OwnerPlanPackage(
      id: 'p5',
      name: 'Paquete Semanal',
      lunches: 5,
      totalPrice: 14.50,
      savings: 0.50,
    ),
    const _OwnerPlanPackage(
      id: 'p10',
      name: 'Paquete Quincenal',
      lunches: 10,
      totalPrice: 28.00,
      savings: 2.00,
    ),
    const _OwnerPlanPackage(
      id: 'p20',
      name: 'Paquete Mensual',
      lunches: 20,
      totalPrice: 55.00,
      savings: 5.00,
    ),
  ];

  bool _flashActive = false;
  int _flashSlots = 5;
  String _flashTitle = 'Almuerzo de cierre';
  double _flashPrice = 2.25;

  String _money(double value) =>
      '\$${value.toStringAsFixed(2).replaceAll('.', ',')}';

  void _openFlashOfferModal() {
    final titleCtrl = TextEditingController(text: _flashTitle);
    final slotsCtrl = TextEditingController(text: '$_flashSlots');
    final priceCtrl = TextEditingController(
      text: _flashPrice.toStringAsFixed(2).replaceAll('.', ','),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Publicar oferta flash de hoy',
                style: Theme.of(sheetCtx).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Liquida los almuerzos que te quedan antes del cierre.',
                style: Theme.of(sheetCtx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: slotsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cupos'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio (USD)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              BocadooButton(
                label: 'Publicar oferta flash',
                icon: Icons.bolt_rounded,
                onPressed: () {
                  final slots = int.tryParse(slotsCtrl.text.trim()) ?? 5;
                  final price = double.tryParse(
                        priceCtrl.text.trim().replaceAll(',', '.'),
                      ) ??
                      2.25;
                  setState(() {
                    _flashActive = true;
                    _flashTitle = titleCtrl.text.trim().isEmpty
                        ? 'Almuerzo de cierre'
                        : titleCtrl.text.trim();
                    _flashSlots = slots.clamp(1, 50);
                    _flashPrice = price;
                  });
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      titleCtrl.dispose();
      slotsCtrl.dispose();
      priceCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Planes del local'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => showSellPlanModal(context),
            icon: const Icon(Icons.add_card_rounded, size: 20),
            label: const Text('Vender en caja'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _flashActive
                  ? bColor.successContainer
                  : colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: _flashActive
                          ? bColor.onSuccessContainer
                          : colors.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _flashActive
                            ? '$_flashTitle · $_flashSlots cupos a ${_money(_flashPrice)}'
                            : 'Oferta flash de hoy',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _flashActive
                              ? bColor.onSuccessContainer
                              : colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _flashActive
                      ? 'Visible ahora en Dónde comer para comensales cercanos.'
                      : 'Publica cupos con descuento para evitar sobrantes al final del día.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _flashActive
                        ? bColor.onSuccessContainer
                        : colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _openFlashOfferModal,
                      child: Text(_flashActive ? 'Editar oferta' : 'Publicar'),
                    ),
                    if (_flashActive) ...[
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => setState(() => _flashActive = false),
                        child: const Text('Retirar'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          Text(
            'Paquetes disponibles',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          for (final pkg in _packages) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pkg.name,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${pkg.lunches} almuerzos · ${_money(pkg.totalPrice / pkg.lunches)} c/u',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(pkg.totalPrice),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ahorra ${_money(pkg.savings)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: bColor.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
      bottomNavigationBar: const OwnerBottomNav(currentRoute: '/owner/plans'),
    );
  }
}

