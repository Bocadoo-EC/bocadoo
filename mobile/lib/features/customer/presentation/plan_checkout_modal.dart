import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/models/plan_option.dart';
import 'plan_checkout_provider.dart';

/// Modal de adquisición o renovación de paquetes (5, 10 o 20 almuerzos).
class PlanCheckoutModal extends ConsumerStatefulWidget {
  final String restaurantId;
  final String restaurantName;
  final bool isRenewal;

  const PlanCheckoutModal({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.isRenewal = false,
  });

  /// Abre el modal inferior de selección y pago en caja.
  static Future<void> show(
    BuildContext context, {
    required String restaurantId,
    required String restaurantName,
    bool isRenewal = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => PlanCheckoutModal(
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        isRenewal: isRenewal,
      ),
    );
  }

  @override
  ConsumerState<PlanCheckoutModal> createState() => _PlanCheckoutModalState();
}

class _PlanCheckoutModalState extends ConsumerState<PlanCheckoutModal> {
  String? _selectedPlanId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final optionsAsync = ref.watch(planOptionsProvider(widget.restaurantId));
    final checkoutState = ref.watch(planCheckoutProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isRenewal ? 'Renovar' : 'Elige tu plan',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.restaurantName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          optionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No pudimos cargar los paquetes.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            data: (options) {
              final selected = _resolveSelection(options);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final option in options) ...[
                    _PlanOptionCard(
                      option: option,
                      isSelected: option.id == selected.id,
                      onTap: checkoutState.isLoading
                          ? null
                          : () => setState(() => _selectedPlanId = option.id),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (checkoutState.hasError) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Intenta de nuevo en un momento.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 8),
                  BocadooButton(
                    label: 'Quiero este',
                    icon: Icons.check_circle_outline_rounded,
                    isLoading: checkoutState.isLoading,
                    onPressed: () => _onConfirm(selected),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  PlanOption _resolveSelection(List<PlanOption> options) {
    if (_selectedPlanId != null) {
      for (final item in options) {
        if (item.id == _selectedPlanId) return item;
      }
    }
    for (final item in options) {
      if (item.isPopular) return item;
    }
    return options.first;
  }

  Future<void> _onConfirm(PlanOption option) async {
    final updatedPass =
        await ref.read(planCheckoutProvider.notifier).confirmPlan(
              option: option,
              restaurantId: widget.restaurantId,
              restaurantName: widget.restaurantName,
            );
    if (!mounted || updatedPass == null) return;

    await _showSuccessDialog(option);
    if (!mounted) return;
    ref.read(planCheckoutProvider.notifier).reset();
    Navigator.of(context).pop();
    context.go('/customer/pase');
  }

  Future<void> _showSuccessDialog(PlanOption option) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: bColor.successContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.storefront_rounded,
            color: bColor.success,
            size: 28,
          ),
        ),
        title: Text(
          'Paga en caja',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Muestra tu pase en caja para activar.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${option.lunchesCount} almuerzos',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    PlanOption.formatEcuadorMoney(option.price),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          BocadooButton(
            label: 'Ver mi pase',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  final PlanOption option;
  final bool isSelected;
  final VoidCallback? onTap;

  const _PlanOptionCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final savingsLabel = option.savingsLabel;

    return Material(
      color: isSelected ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: isSelected ? colors.primary : colors.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${option.lunchesCount} almuerzos',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isSelected
                                ? colors.onPrimaryContainer
                                : colors.onSurface,
                          ),
                        ),
                        if (savingsLabel != null) ...[
                          const SizedBox(width: 8),
                          StatusChip(
                            label: savingsLabel,
                            variant: BocadooStatusVariant.offer,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${PlanOption.formatEcuadorMoney(option.unitPrice)} por almuerzo · ${option.validityDays} días',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                PlanOption.formatEcuadorMoney(option.price),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isSelected ? colors.onPrimaryContainer : colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

