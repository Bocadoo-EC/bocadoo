import 'package:flutter/foundation.dart';

import '../../../../core/contracts/models.dart';

/// Bus reactivo ligero para sincronizar publicaciones/cierres de Ofertas Flash
/// entre el módulo Dueño y el módulo Comensal en tiempo real.
class FlashOffersLiveSync extends ChangeNotifier {
  FlashOffersLiveSync._();

  static final FlashOffersLiveSync instance = FlashOffersLiveSync._();

  String? _lastRestaurantId;
  RestaurantOffer? _lastOffer;
  bool _lastRemoved = false;

  String? get lastRestaurantId => _lastRestaurantId;
  RestaurantOffer? get lastOffer => _lastOffer;
  bool get lastRemoved => _lastRemoved;

  void notifyPublished({
    required String restaurantId,
    RestaurantOffer? offer,
  }) {
    _lastRestaurantId = restaurantId;
    _lastOffer = offer;
    _lastRemoved = false;
    notifyListeners();
  }

  void notifyRemoved({
    required String restaurantId,
    String? offerId,
  }) {
    _lastRestaurantId = restaurantId;
    _lastOffer = offerId != null
        ? RestaurantOffer(
            id: offerId,
            restaurantId: restaurantId,
            title: '',
            badge: '',
            slotsLeft: 0,
            availableNow: false,
          )
        : null;
    _lastRemoved = true;
    notifyListeners();
  }
}
