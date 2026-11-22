import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/utils/formatters.dart';
import 'individual_menu_accordion.dart';

/// Pestañas de armado de orden en Paso 1.
enum RestaurantOrderTab { menuDelDia, carta }

/// Desglose financiero inmutable de pago mixto (Split-Tender).
@immutable
sealed class HybridTenderSummary {
  const HybridTenderSummary();

  int get planCreditsUsed;
  int get cashToCollectCents;
}

final class HybridPlanOnlyTender extends HybridTenderSummary {
  const HybridPlanOnlyTender(this.planCreditsUsed);

  @override
  final int planCreditsUsed;

  @override
  int get cashToCollectCents => 0;
}

final class HybridMixedTender extends HybridTenderSummary {
  const HybridMixedTender({
    required this.planCreditsUsed,
    required this.cashToCollectCents,
  });

  @override
  final int planCreditsUsed;

  @override
  final int cashToCollectCents;
}

final class HybridCashOnlyTender extends HybridTenderSummary {
  const HybridCashOnlyTender(this.cashToCollectCents);

  @override
  int get planCreditsUsed => 0;

  @override
  final int cashToCollectCents;
}

/// Ítem individual de Carta o Extra dentro del carrito híbrido.
@immutable
class HybridCartaLine {
  const HybridCartaLine({
    required this.item,
    required this.quantity,
  });

  final PublicCartaItem item;
  final int quantity;

  int get subtotalCents => item.priceCents * quantity;

  HybridCartaLine copyWith({
    PublicCartaItem? item,
    int? quantity,
  }) {
    return HybridCartaLine(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
    );
  }
}

/// Estado inmutable completo del carrito híbrido (Plan + Carta + Extras).
@immutable
class HybridOrderState {
  const HybridOrderState({
    this.step = 1,
    this.activeTab = RestaurantOrderTab.menuDelDia,
    this.soupId,
    this.mainId,
    this.drinkName,
    this.dessertName,
    this.breakfastId,
    this.breakfastMode = false,
    this.cartaLines = const <String, HybridCartaLine>{},
    this.takeaway = false,
    this.selectedArrival = 'En 15 min',
    this.customArrival,
  });

  final int step;
  final RestaurantOrderTab activeTab;
  final String? soupId;
  final String? mainId;
  final String? drinkName;
  final String? dessertName;
  final String? breakfastId;
  final bool breakfastMode;
  final Map<String, HybridCartaLine> cartaLines;
  final bool takeaway;
  final String selectedArrival;
  final String? customArrival;

  List<HybridCartaLine> get addonsList => [
        for (final line in cartaLines.values)
          if (line.quantity > 0) line,
      ];

  bool get hasAddons => cartaLines.values.any((l) => l.quantity > 0);

  int get addonsTotalCents =>
      cartaLines.values.fold<int>(0, (sum, l) => sum + l.subtotalCents);

  int quantityOf(String itemId) => cartaLines[itemId]?.quantity ?? 0;

  bool isLunchReady(Restaurant r) {
    if (breakfastMode) {
      return breakfastId != null &&
          r.breakfasts.any((b) => b.id == breakfastId && !b.isSoldOut);
    }
    final hasAnyLunchCourse = r.soups.isNotEmpty || r.mains.isNotEmpty;
    if (!hasAnyLunchCourse) return false;
    final hasValidSoup = r.soups.isEmpty ||
        soupId == kIndividualNoSoupId ||
        (soupId != null && r.soups.any((s) => s.id == soupId && !s.isSoldOut));
    final hasValidMain = r.mains.isEmpty ||
        (mainId != null && r.mains.any((m) => m.id == mainId && !m.isSoldOut));
    return hasValidSoup && hasValidMain;
  }

  bool hasPartialLunch(Restaurant r) {
    if (breakfastMode) return false;
    final pickedAny = soupId != null || mainId != null;
    return pickedAny && !isLunchReady(r);
  }

  bool canContinue(Restaurant r) {
    if (isLunchReady(r)) return true;
    return hasAddons && !hasPartialLunch(r);
  }

  HybridTenderSummary resolveTender({
    required Restaurant r,
    required bool hasPlanHere,
    required bool takeaway,
  }) {
    final lunchIncluded = isLunchReady(r);
    final addonsCents = addonsTotalCents;
    final chosenBreakfast = breakfastMode
        ? r.breakfasts
            .where((b) => b.id == breakfastId && !b.isSoldOut)
            .firstOrNull
        : null;
    final lunchBaseCents = lunchIncluded
        ? Money.toCents(
            breakfastMode
                ? (chosenBreakfast?.price ?? r.singleLunchPrice)
                : r.singleLunchPrice,
          )
        : 0;
    final surchargeCents = takeaway ? Money.toCents(r.takeawaySurcharge) : 0;

    if (lunchIncluded && hasPlanHere) {
      if (addonsCents == 0) {
        return const HybridPlanOnlyTender(1);
      }
      return HybridMixedTender(
        planCreditsUsed: 1,
        cashToCollectCents: addonsCents,
      );
    }

    return HybridCashOnlyTender(lunchBaseCents + surchargeCents + addonsCents);
  }

  String lunchSummaryLine(Restaurant r) {
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

  HybridOrderState copyWith({
    int? step,
    RestaurantOrderTab? activeTab,
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
    Map<String, HybridCartaLine>? cartaLines,
    bool? takeaway,
    String? selectedArrival,
    String? customArrival,
  }) {
    return HybridOrderState(
      step: step ?? this.step,
      activeTab: activeTab ?? this.activeTab,
      soupId: clearSoupId ? null : (soupId ?? this.soupId),
      mainId: clearMainId ? null : (mainId ?? this.mainId),
      drinkName: clearDrinkName ? null : (drinkName ?? this.drinkName),
      dessertName: clearDessertName ? null : (dessertName ?? this.dessertName),
      breakfastId: clearBreakfastId ? null : (breakfastId ?? this.breakfastId),
      breakfastMode: breakfastMode ?? this.breakfastMode,
      cartaLines: cartaLines ?? this.cartaLines,
      takeaway: takeaway ?? this.takeaway,
      selectedArrival: selectedArrival ?? this.selectedArrival,
      customArrival: customArrival ?? this.customArrival,
    );
  }
}

/// Controlador Riverpod inmutable del carrito híbrido por restaurante.
class HybridOrderNotifier extends Notifier<HybridOrderState> {
  HybridOrderNotifier(this.restaurantId);

  final String restaurantId;

  @override
  HybridOrderState build() => const HybridOrderState();

  void setTab(RestaurantOrderTab tab) {
    state = state.copyWith(activeTab: tab);
  }

  void setStep(int step) {
    state = state.copyWith(step: step);
  }

  void setBreakfastMode(bool value) {
    state = state.copyWith(breakfastMode: value, step: 1);
  }

  void selectSoup(String id) {
    state = state.copyWith(soupId: id);
  }

  void selectMain(String id) {
    state = state.copyWith(mainId: id);
  }

  void selectBreakfast(String id) {
    state = state.copyWith(breakfastId: id);
  }

  void selectDrink(String name) {
    state = state.copyWith(drinkName: name);
  }

  void selectDessert(String name) {
    state = state.copyWith(dessertName: name);
  }

  void clearLunchSelection() {
    final next = state.copyWith(
      clearSoupId: true,
      clearMainId: true,
      clearBreakfastId: true,
      clearDrinkName: true,
      clearDessertName: true,
    );
    state = next.hasAddons ? next : next.copyWith(step: 1);
  }

  void incrementItem(PublicCartaItem item) {
    if (item.isSoldOut) return;
    final nextLines = Map<String, HybridCartaLine>.from(state.cartaLines);
    final existing = nextLines[item.id];
    nextLines[item.id] = existing == null
        ? HybridCartaLine(item: item, quantity: 1)
        : existing.copyWith(quantity: existing.quantity + 1);
    state = state.copyWith(cartaLines: Map.unmodifiable(nextLines));
  }

  void decrementItem(String itemId, {Restaurant? restaurant}) {
    final existing = state.cartaLines[itemId];
    if (existing == null) return;
    final nextLines = Map<String, HybridCartaLine>.from(state.cartaLines);
    if (existing.quantity <= 1) {
      nextLines.remove(itemId);
    } else {
      nextLines[itemId] = existing.copyWith(quantity: existing.quantity - 1);
    }
    var next = state.copyWith(cartaLines: Map.unmodifiable(nextLines));
    if (restaurant != null && next.step == 2 && !next.canContinue(restaurant)) {
      next = next.copyWith(step: 1);
    }
    state = next;
  }

  void removeItem(String itemId, {Restaurant? restaurant}) {
    if (!state.cartaLines.containsKey(itemId)) return;
    final nextLines = Map<String, HybridCartaLine>.from(state.cartaLines)
      ..remove(itemId);
    var next = state.copyWith(cartaLines: Map.unmodifiable(nextLines));
    if (restaurant != null && next.step == 2 && !next.canContinue(restaurant)) {
      next = next.copyWith(step: 1);
    }
    state = next;
  }

  void setTakeaway(bool value) {
    state = state.copyWith(takeaway: value);
  }

  void setArrival(String arrival, {bool isCustom = false}) {
    state = state.copyWith(
      selectedArrival: arrival,
      customArrival: isCustom ? arrival : state.customArrival,
    );
  }

  HybridOrderState sanitizeView(
    Restaurant r,
    List<String> validArrivals,
  ) {
    var nextSoup = state.soupId;
    if (nextSoup != null &&
        nextSoup != kIndividualNoSoupId &&
        !r.soups.any((s) => s.id == nextSoup && !s.isSoldOut)) {
      nextSoup = null;
    }
    var nextMain = state.mainId;
    if (nextMain != null &&
        !r.mains.any((m) => m.id == nextMain && !m.isSoldOut)) {
      nextMain = null;
    }
    var nextBreakfast = state.breakfastId;
    if (nextBreakfast != null &&
        !r.breakfasts.any((b) => b.id == nextBreakfast && !b.isSoldOut)) {
      nextBreakfast = null;
    }
    var nextArrival = state.selectedArrival;
    if (nextArrival != state.customArrival &&
        !validArrivals.contains(nextArrival)) {
      nextArrival = 'En 15 min';
    }
    final sanitized = state.copyWith(
      soupId: nextSoup,
      clearSoupId: nextSoup == null,
      mainId: nextMain,
      clearMainId: nextMain == null,
      breakfastId: nextBreakfast,
      clearBreakfastId: nextBreakfast == null,
      selectedArrival: nextArrival,
    );
    if (sanitized.step == 2 && !sanitized.canContinue(r)) {
      return sanitized.copyWith(step: 1);
    }
    return sanitized;
  }
}

final hybridOrderProvider = NotifierProvider.autoDispose
    .family<HybridOrderNotifier, HybridOrderState, String>(
  HybridOrderNotifier.new,
);
