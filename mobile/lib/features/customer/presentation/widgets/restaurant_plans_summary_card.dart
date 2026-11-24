import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';

/// FASE 1 · Tarjeta única por restaurante en "Planes de almuerzo".
/// Agrupa todos los planes del local con precio mínimo por comida,
/// opciones disponibles, chips de inclusión y acceso directo al catálogo.
class RestaurantPlansSummaryCard extends StatelessWidget {
  const RestaurantPlansSummaryCard({
    super.key,
    required this.restaurant,
    required this.plans,
    required this.includes,
    required this.onViewPlans,
    this.distanceLabel,
    this.activePass,
  });

  final Restaurant restaurant;
  final List<PlanTemplate> plans;
  final List<String> includes;
  final VoidCallback onViewPlans;
  final String? distanceLabel;
  final CustomerPass? activePass;

  String _formatOptionsSummary() {
    final counts = plans.map((p) => p.lunches).toSet().toList()..sort();
    if (counts.isEmpty) return 'Planes disponibles';
    final hasNonLunch = plans.any((p) => p.category != 'ALMUERZO');
    final unit = hasNonLunch ? 'comidas' : 'almuerzos';
    if (counts.length == 1) return '${counts.first} $unit';
    if (counts.length == 2) return '${counts[0]} o ${counts[1]} $unit';
    final head = counts.sublist(0, counts.length - 1).join(', ');
    return '$head o ${counts.last} $unit';
  }

  int _minPerLunchCents() {
    if (plans.isEmpty) {
      return ((restaurant.planLunchPrice ?? restaurant.singleLunchPrice) * 100)
          .round();
    }
    var minCents = plans.first.perLunchCents;
    for (final p in plans.skip(1)) {
      if (p.perLunchCents < minCents) minCents = p.perLunchCents;
    }
    return minCents;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final textTheme = Theme.of(context).textTheme;

    final minPerMeal = _minPerLunchCents();
    final optionsLabel = _formatOptionsSummary();
    final shortLocation = restaurant.address.trim().isNotEmpty
        ? restaurant.address.trim()
        : (restaurant.zone.trim().isNotEmpty
            ? restaurant.zone.trim()
            : restaurant.schedule);
    final hasActivePass = activePass != null &&
        activePass!.remainingLunches > 0 &&
        !activePass!.isExpired;
    final hasLogo =
        restaurant.logoUrl != null && restaurant.logoUrl!.trim().isNotEmpty;

    Widget avatarFallback() => Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: b.heroGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            monogram(restaurant.name),
            style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: b.imageForeground,
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasActivePass
              ? colors.primary.withValues(alpha: 0.45)
              : colors.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onViewPlans,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera: Avatar + Nombre + Distancia + Ubicación corta
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: hasLogo
                          ? Image.network(
                              restaurant.logoUrl!,
                              width: 48,
                              height: 48,
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  restaurant.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (textTheme.titleMedium ??
                                          const TextStyle())
                                      .copyWith(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              if (distanceLabel != null &&
                                  distanceLabel!.trim().isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: colors.outlineVariant,
                                    ),
                                  ),
                                  child: Text(
                                    distanceLabel!,
                                    style: (textTheme.labelSmall ??
                                            const TextStyle())
                                        .copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13.5,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  shortLocation,
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
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Resumen escaneable calculado en frontend
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.36),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Planes desde ${formatCents(minPerMeal)}/almuerzo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (textTheme.titleSmall ?? const TextStyle())
                                      .copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Opciones: $optionsLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: (textTheme.bodySmall ?? const TextStyle())
                                  .copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasActivePass) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: b.successContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${activePass!.remainingLunches} disp.',
                            style: (textTheme.labelSmall ?? const TextStyle())
                                .copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: b.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (includes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.restaurant_menu_rounded,
                              size: 13,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              includes.join(' + '),
                              style: (textTheme.labelSmall ?? const TextStyle())
                                  .copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_2_rounded,
                              size: 13,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'QR en caja',
                              style: (textTheme.labelSmall ?? const TextStyle())
                                  .copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // CTA principal: Ver planes →
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${plans.length} ${plans.length == 1 ? 'plan disponible' : 'planes disponibles'}',
                      style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: onViewPlans,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ver planes',
                            style: (textTheme.labelLarge ?? const TextStyle())
                                .copyWith(
                              color: colors.onPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
