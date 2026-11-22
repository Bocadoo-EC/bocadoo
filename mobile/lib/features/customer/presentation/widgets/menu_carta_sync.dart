import 'package:flutter/foundation.dart';

/// Bus reactivo ligero para sincronizar en tiempo real los cambios de Menú del
/// Día, Carta y Extras publicados por el Dueño hacia el Comensal.
class MenuAndCartaLiveSync extends ChangeNotifier {
  MenuAndCartaLiveSync._();

  static final MenuAndCartaLiveSync instance = MenuAndCartaLiveSync._();

  String? _lastRestaurantId;

  String? get lastRestaurantId => _lastRestaurantId;

  void notifyUpdated(String restaurantId) {
    _lastRestaurantId = restaurantId;
    notifyListeners();
  }
}
