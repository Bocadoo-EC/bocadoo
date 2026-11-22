import 'package:flutter/foundation.dart';

import '../../../../core/contracts/models.dart';

/// Bus reactivo ligero para sincronizar cambios de estado del local
/// (Libre / Concurrido / Lleno / Cerrado) entre Dueño y Comensal en tiempo real.
class RestaurantStatusLiveSync extends ChangeNotifier {
  RestaurantStatusLiveSync._();

  static final RestaurantStatusLiveSync instance = RestaurantStatusLiveSync._();

  String? _lastRestaurantId;
  ManualOccupancyStatus? _lastStatus;
  DateTime? _lastUntil;

  String? get lastRestaurantId => _lastRestaurantId;
  ManualOccupancyStatus? get lastStatus => _lastStatus;
  DateTime? get lastUntil => _lastUntil;

  void notifyStatusChanged({
    required String restaurantId,
    required ManualOccupancyStatus status,
    DateTime? until,
  }) {
    _lastRestaurantId = restaurantId;
    _lastStatus = status;
    _lastUntil = until;
    notifyListeners();
  }
}
