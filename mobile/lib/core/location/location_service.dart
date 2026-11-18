import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Resultado de pedir la ubicación del dispositivo.
enum LocationOutcome { granted, denied, serviceOff, failed }

/// Ubicación del dispositivo con `geolocator` (C11 Mapa y A5 Registro dueño).
class LocationService {
  const LocationService._();

  /// Coordenadas de respaldo en Quito / PUCE cuando no hay GPS disponible
  /// o el emulador devuelve ubicación por defecto `(0,0)` / fuera de región.
  static const LatLng fallbackPuce = LatLng(-0.2096, -78.4912);

  static bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return !(lat.abs() < 0.0001 && lng.abs() < 0.0001);
  }

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
      if (!isValidCoordinate(p.latitude, p.longitude)) {
        return (LocationOutcome.failed, null);
      }
      return (LocationOutcome.granted, LatLng(p.latitude, p.longitude));
    } catch (_) {
      return (LocationOutcome.failed, null);
    }
  }

  /// Obtiene la ubicación real con `geolocator` y aplica fallback seguro a
  /// Quito/PUCE (`-0.2096, -78.4912`) si el GPS está apagado, denegado o
  /// el emulador reporta `(0.0, 0.0)` / ubicación simulada fuera de Ecuador.
  static Future<(LocationOutcome, LatLng)> resolveWithFallback() async {
    final (outcome, pos) = await current();
    if (outcome == LocationOutcome.granted && pos != null) {
      if (kDebugMode) {
        final distToQuito = meters(pos, fallbackPuce);
        if (distToQuito > 1000000) {
          return (outcome, fallbackPuce);
        }
      }
      return (outcome, pos);
    }
    return (outcome, fallbackPuce);
  }

  /// Distancia en metros (Haversine vía `Geolocator.distanceBetween`).
  static int meters(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude).round();

  /// Minutos a pie a 80 m/min (como el prototipo), mínimo 1.
  static int walkingMinutes(int meters) => (meters / 80).round().clamp(1, 9999);
}
