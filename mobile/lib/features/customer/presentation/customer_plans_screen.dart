import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/models/plan_option.dart';
import 'customer_bottom_nav.dart';
import 'customer_controller.dart';
import 'plan_checkout_modal.dart';
import 'plan_checkout_provider.dart';

/// Pantalla dedicada de Planes del Comensal (pestaña 3 de la barra inferior).
/// Permite explorar paquetes de 5, 10 y 20 almuerzos por restaurante, ver el
/// ahorro y adquirir o renovar mediante [PlanCheckoutModal].
class CustomerPlansScreen extends ConsumerStatefulWidget {
  const CustomerPlansScreen({super.key});

  @override
  ConsumerState<CustomerPlansScreen> createState() =>
      _CustomerPlansScreenState();
}

class _CustomerPlansScreenState extends ConsumerState<CustomerPlansScreen> {
  String? _selectedRestaurantId;
  String? _selectedRestaurantName;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final controller = ref.read(customerControllerProvider);
      if (controller.restaurants.isEmpty && !controller.state.isLoading) {
        controller.loadDashboard();
      }
    });
  }

  String _formatMoney(double value) =>
      '\$${value.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final bColor = context.bocadooColors;
        final activePass = controller.pass;
        final restaurants = controller.restaurants;

        final targetRestaurantId = _selectedRestaurantId ??
            activePass?.restaurantId ??
            (restaurants.isNotEmpty ? restaurants.first.id : 'rest-001');
        final targetRestaurantName = _selectedRestaurantName ??
            activePass?.restaurantName ??
            (restaurants.isNotEmpty
                ? restaurants.first.name
                : 'La Cuchara de San Blas');

        final optionsAsync = ref.watch(planOptionsProvider(targetRestaurantId));

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Planes de almuerzos'),
            centerTitle: false,
            automaticallyImplyLeading: false,
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(planOptionsProvider(targetRestaurantId));
              await controller.loadDashboard();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                if (activePass != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tu plan activo',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                activePass.restaurantName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${activePass.remainingLunches} almuerzos disponibles',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => PlanCheckoutModal.show(
                            context,
                            restaurantId: activePass.restaurantId,
                            restaurantName: activePass.restaurantName,
                            isRenewal: true,
                          ),
                          child: const Text('Renovar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  'Elige un local',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (restaurants.isEmpty)
                  Text(
                    targetRestaurantName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: restaurants.map((restaurant) {
                        final selected = restaurant.id == targetRestaurantId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(restaurant.name),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                _selectedRestaurantId = restaurant.id;
                                _selectedRestaurantName = restaurant.name;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 22),
                Text(
                  'Paquetes en $targetRestaurantName',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Elige tu paquete y paga directamente en caja.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                optionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: bColor.dangerContainer,
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'No pudimos cargar los planes ahora.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: bColor.onDangerContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        BocadooButton(
                          label: 'Reintentar',
                          onPressed: () => ref.invalidate(
                            planOptionsProvider(targetRestaurantId),
                          ),
                        ),
                      ],
                    ),
                  ),
                  data: (options) => Column(
                    children: options
                        .map(
                          (option) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _PlanOptionCard(
                              option: option,
                              formatMoney: _formatMoney,
                              onSelect: () => PlanCheckoutModal.show(
                                context,
                                restaurantId: targetRestaurantId,
                                restaurantName: targetRestaurantName,
                                isRenewal: activePass?.restaurantId ==
                                    targetRestaurantId,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: const CustomerBottomNav(currentIndex: 2),
        );
      },
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  final PlanOption option;
  final String Function(double) formatMoney;
  final VoidCallback onSelect;

  const _PlanOptionCard({
    required this.option,
    required this.formatMoney,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;

    final savingsLabel = option.savingsLabel;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: option.isPopular ? colors.primary : colors.outlineVariant,
          width: option.isPopular ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  option.name,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (savingsLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bColor.successContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    savingsLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: bColor.onSuccessContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${option.lunchesCount} almuerzos · ${formatMoney(option.unitPrice)} c/u',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(option.price),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Paga en caja',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onSelect,
                child: const Text('Quiero este'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

