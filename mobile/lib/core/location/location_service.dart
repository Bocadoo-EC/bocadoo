import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Resultado de pedir la ubicación del dispositivo.
enum LocationOutcome { granted, denied, serviceOff, failed }

/// Ubicación del dispositivo con `geolocator` (C11 Mapa y A5 Registro dueño).
class LocationService {
  const LocationService._();

  /// Pide permiso si hace falta y devuelve la posición actual.
  static Future<(LocationOutcome, LatLng?)> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (LocationOutcome.serviceOff, null);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return (LocationOutcome.denied, null);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return (LocationOutcome.granted, LatLng(p.latitude, p.longitude));
    } catch (_) {
      return (LocationOutcome.failed, null);
    }
  }

  /// Distancia en metros (Haversine de `latlong2`).
  static int meters(LatLng a, LatLng b) => const Distance().as(LengthUnit.Meter, a, b).round();

  /// Minutos a pie a 80 m/min (como el prototipo), mínimo 1.
  static int walkingMinutes(int meters) => (meters / 80).round().clamp(1, 9999);
}
