import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_widgets.dart';
import 'individual_menu_accordion.dart';

/// Estado inmutable del flujo progresivo de 2 pasos para orden individual.
@immutable
class IndividualPreorderState {
  const IndividualPreorderState({
    this.step = 1,
    this.soupId,
    this.mainId,
    this.drinkName,
    this.dessertName,
    this.breakfastId,
    this.breakfastMode = false,
    this.takeaway = false,
    this.selectedArrival = 'En 15 min',
    this.customArrival,
  });

  final int step;
  final String? soupId;
  final String? mainId;
  final String? drinkName;
  final String? dessertName;
  final String? breakfastId;
  final bool breakfastMode;
  final bool takeaway;
  final String selectedArrival;
  final String? customArrival;

  bool isStepOneComplete(Restaurant r) {
    if (breakfastMode) {
      return breakfastId != null &&
          r.breakfasts.any((b) => b.id == breakfastId && !b.isSoldOut);
    }
    final hasValidSoup = r.soups.isEmpty ||
        soupId == kIndividualNoSoupId ||
        (soupId != null && r.soups.any((s) => s.id == soupId && !s.isSoldOut));
    final hasValidMain = r.mains.isEmpty ||
        (mainId != null && r.mains.any((m) => m.id == mainId && !m.isSoldOut));
    final drinks = r.todayMenu
        .where((m) => m.category == 'Bebida' && !m.isSoldOut)
        .toList();
    final hasValidDrink = drinks.length <= 1 || drinkName != null;
    final hasAnyCourse = r.soups.isNotEmpty || r.mains.isNotEmpty;
    return hasAnyCourse && hasValidSoup && hasValidMain && hasValidDrink;
  }

  /// Limpia cualquier selección que ya no exista o se haya marcado agotada.
  IndividualPreorderState sanitizeFor(
    Restaurant r,
    List<String> validArrivals,
  ) {
    var nextSoup = soupId;
    if (nextSoup != null &&
        nextSoup != kIndividualNoSoupId &&
        !r.soups.any((s) => s.id == nextSoup && !s.isSoldOut)) {
      nextSoup = null;
    }
    var nextMain = mainId;
    if (nextMain != null &&
        !r.mains.any((m) => m.id == nextMain && !m.isSoldOut)) {
      nextMain = null;
    }
    var nextBreakfast = breakfastId;
    if (nextBreakfast != null &&
        !r.breakfasts.any((b) => b.id == nextBreakfast && !b.isSoldOut)) {
      nextBreakfast = null;
    }
    var nextArrival = selectedArrival;
    if (nextArrival != customArrival && !validArrivals.contains(nextArrival)) {
      nextArrival = 'En 15 min';
    }
    final next = copyWith(
      soupId: nextSoup,
      clearSoupId: nextSoup == null,
      mainId: nextMain,
      clearMainId: nextMain == null,
      breakfastId: nextBreakfast,
      clearBreakfastId: nextBreakfast == null,
      selectedArrival: nextArrival,
    );
    if (next.step == 2 && !next.isStepOneComplete(r)) {
      return next.copyWith(step: 1);
    }
    return next;
  }

  String summaryLine(Restaurant r) {
    if (breakfastMode) {
      return r.breakfasts
              .where((b) => b.id == breakfastId)
              .firstOrNull
              ?.name ??
          'Desayuno seleccionado';
    }
    final parts = <String>[];
    if (soupId != null && soupId != kIndividualNoSoupId) {
      final soup = r.soups.where((s) => s.id == soupId).firstOrNull?.name;
      if (soup != null && soup.isNotEmpty) parts.add(soup);
    }
    if (mainId != null) {
      final main = r.mains.where((m) => m.id == mainId).firstOrNull?.name;
      if (main != null && main.isNotEmpty) parts.add(main);
    }
    final drink = (drinkName != null && drinkName!.isNotEmpty)
        ? drinkName!
        : r.juice.trim();
    if (drink.isNotEmpty) parts.add(drink);
    final dessert = (dessertName != null && dessertName!.isNotEmpty)
        ? dessertName!
        : r.dessert.trim();
    if (dessert.isNotEmpty) parts.add(dessert);
    return parts.isEmpty ? 'Almuerzo del día' : parts.join(' + ');
  }

  IndividualPreorderState copyWith({
    int? step,
    String? soupId,
    bool clearSoupId = false,
    String? mainId,
    bool clearMainId = false,
    String? drinkName,
    bool clearDrinkName = false,
    String? dessertName,
    bool clearDessertName = false,
    String? breakfastId,
    bool clearBreakfastId = false,
    bool? breakfastMode,
    bool? takeaway,
    String? selectedArrival,
    String? customArrival,
  }) {
    return IndividualPreorderState(
      step: step ?? this.step,
      soupId: clearSoupId ? null : (soupId ?? this.soupId),
      mainId: clearMainId ? null : (mainId ?? this.mainId),
      drinkName: clearDrinkName ? null : (drinkName ?? this.drinkName),
      dessertName: clearDessertName ? null : (dessertName ?? this.dessertName),
      breakfastId: clearBreakfastId ? null : (breakfastId ?? this.breakfastId),
      breakfastMode: breakfastMode ?? this.breakfastMode,
      takeaway: takeaway ?? this.takeaway,
      selectedArrival: selectedArrival ?? this.selectedArrival,
      customArrival: customArrival ?? this.customArrival,
    );
  }
}

/// Cabecera superior con nombre, indicador `Paso X de 2`, barra de progreso y
/// botón atrás cuando corresponde al Paso 2.
class PreorderModalHeader extends StatelessWidget {
  const PreorderModalHeader({
    super.key,
    required this.restaurantName,
    required this.step,
    required this.totalSteps,
    required this.subtitle,
    this.onBack,
  });

  final String restaurantName;
  final int step;
  final int totalSteps;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final progress = (step / totalSteps).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Editar plato',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Paso $step de $totalSteps',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: colors.primaryContainer.withValues(alpha: 0.45),
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta limpia de restaurante sin banner redundante, ocupación ni distancia.
class CleanRestaurantPlanCard extends StatelessWidget {
  const CleanRestaurantPlanCard({
    super.key,
    required this.restaurant,
    required this.publicStatus,
    required this.hasPlanHere,
    required this.onTable,
  });

  final Restaurant restaurant;
  final RestaurantPublicStatus publicStatus;
  final bool hasPlanHere;
  final VoidCallback onTable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final r = restaurant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        hasPlanHere
                            ? 'Tienes almuerzos activos aquí'
                            : 'Planes ejecutivos disponibles',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Desde ${formatMoney(r.planLunchPrice ?? r.singleLunchPrice)} con plan · ${formatMoney(r.singleLunchPrice)} suelto',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PillAction(
            label: publicStatus.isFull
                ? 'Pedido grupal (Para llevar)'
                : 'Pedido grupal',
            icon: Icons.group_outlined,
            onPressed: (publicStatus.isSoldOutToday || publicStatus.isClosed)
                ? null
                : onTable,
          ),
        ],
      ),
    );
  }
}

/// Resumen compacto de 1 línea del plato elegido para el Paso 2.
class SelectedDishSummaryTile extends StatelessWidget {
  const SelectedDishSummaryTile({
    super.key,
    required this.summary,
    required this.onEdit,
  });

  final String summary;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Cambiar',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
