import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_controller.dart';
import '../customer_widgets.dart';
import '../plan_detail_sheet.dart';
import 'plan_card.dart';

/// Abre el Modal Emergente 1 con los planes disponibles de un restaurante.
Future<void> showRestaurantPlansSheet(
  BuildContext context, {
  required Restaurant restaurant,
  required List<PlanTemplate> plans,
  String? distanceLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => RestaurantPlansSheet(
      restaurant: restaurant,
      plans: plans,
      distanceLabel: distanceLabel,
    ),
  );
}

/// FASE 2 · Modal Emergente 1: Catálogo comparable de planes del restaurante.
class RestaurantPlansSheet extends ConsumerWidget {
  const RestaurantPlansSheet({
    super.key,
    required this.restaurant,
    required this.plans,
    this.distanceLabel,
  });

  final Restaurant restaurant;
  final List<PlanTemplate> plans;
  final String? distanceLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final textTheme = Theme.of(context).textTheme;
    final controller = ref.watch(customerControllerProvider);

    final sortedPlans = [...plans]
      ..sort((a, bPlan) => a.lunches.compareTo(bPlan.lunches));
    final singleCents = (restaurant.singleLunchPrice * 100).round();
    final hasLogo =
        restaurant.logoUrl != null && restaurant.logoUrl!.trim().isNotEmpty;

    Widget avatarFallback() => Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: b.heroGradient,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            monogram(restaurant.name),
            style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: b.imageForeground,
            ),
          ),
        );

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final activePass = controller.state.passFor(restaurant.id);
        final hasActiveHere = activePass != null &&
            activePass.remainingLunches > 0 &&
            !activePass.isExpired;

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.84,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera del restaurante
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: hasLogo
                            ? Image.network(
                                restaurant.logoUrl!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => avatarFallback(),
                              )
                            : avatarFallback(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              restaurant.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: (textTheme.titleLarge ?? const TextStyle())
                                  .copyWith(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (restaurant.address.trim().isNotEmpty)
                                  restaurant.address.trim()
                                else if (restaurant.zone.trim().isNotEmpty)
                                  restaurant.zone.trim(),
                                if (distanceLabel != null &&
                                    distanceLabel!.trim().isNotEmpty)
                                  distanceLabel!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (textTheme.bodySmall ?? const TextStyle())
                                      .copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Elige el plan que mejor se adapte a tu semana',
                    style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),

                if (hasActiveHere)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: b.successContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: b.success.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 17,
                            color: b.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ya tienes un plan activo aquí (${activePass.remainingLunches} almuerzos restantes).',
                              style: (textTheme.bodySmall ?? const TextStyle())
                                  .copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: b.onSuccessContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                    itemCount: sortedPlans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final plan = sortedPlans[index];
                      return PlanCard(
                        plan: plan,
                        singleLunchPriceCents: singleCents,
                        enabled: !hasActiveHere,
                        showRestaurantHeader: false,
                        onTap: () {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useRootNavigator: true,
                            showDragHandle: true,
                            backgroundColor: colors.surface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                            ),
                            builder: (_) => PlanDetailSheet(planId: plan.id),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
