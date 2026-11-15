import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/location_service.dart';

/// Ruta a pie para dibujar dentro del mapa (C11).
class WalkingRoute {
  const WalkingRoute({required this.points, required this.meters, required this.minutes, required this.approximate});

  final List<LatLng> points;
  final int meters;
  final int minutes;

  /// `true` si no se pudo consultar el servicio de rutas y se dibuja una
  /// línea directa.
  final bool approximate;
}

/// Calcula la ruta peatonal con OSRM sobre OpenStreetMap (perfil a pie del
/// servidor de FOSSGIS). Si falla, devuelve una línea directa.
// TODO: Conectar con provider de backend (servicio de rutas propio o con clave).
class WalkingRouteService {
  WalkingRouteService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'User-Agent': 'ec.bocadoo.bocadoo'},
            ));

  final Dio _dio;

  Future<WalkingRoute> route(LatLng from, LatLng to) async {
    try {
      final url = 'https://routing.openstreetmap.de/routed-foot/route/v1/foot/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
      final res = await _dio.get<Map<String, dynamic>>(url, queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
      });
      final routes = res.data?['routes'] as List<dynamic>?;
      if (routes != null && routes.isNotEmpty) {
        final r = routes.first as Map<String, dynamic>;
        final coords = (r['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>;
        final points = [
          for (final c in coords.cast<List<dynamic>>())
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        ];
        final meters = (r['distance'] as num).round();
        if (points.length >= 2) {
          return WalkingRoute(
            points: points,
            meters: meters,
            minutes: LocationService.walkingMinutes(meters),
            approximate: false,
          );
        }
      }
    } catch (_) {
      // Sin conexión o servicio caído: se usa la línea directa.
    }
    final meters = LocationService.meters(from, to);
    return WalkingRoute(
      points: [from, to],
      meters: meters,
      minutes: LocationService.walkingMinutes(meters),
      approximate: true,
    );
  }
}
