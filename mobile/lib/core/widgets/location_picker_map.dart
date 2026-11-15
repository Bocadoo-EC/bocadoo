import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../location/location_service.dart';
import '../theme/app_theme.dart';

/// Mapa para fijar una ubicación exacta (registro de comensal). Se toca el
/// mapa para mover el pin, o se usa "Mi GPS" (geolocator). Las zonas de Quito
/// llevan el pin a su centro.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    required this.zones,
    required this.selectedZone,
    required this.onZoneSelected,
    required this.onLocationChanged,
    this.height = 220,
  });

  /// Zona → centro. Las zonas se pintan como chips sobre el mapa.
  final Map<String, LatLng> zones;
  final String selectedZone;
  final ValueChanged<String> onZoneSelected;

  /// Se llama cada vez que cambia el pin (toque, GPS o zona).
  final ValueChanged<LatLng> onLocationChanged;
  final double height;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  final _controller = MapController();
  late LatLng _pin = widget.zones[widget.selectedZone] ?? widget.zones.values.first;
  bool _locating = false;
  bool _fromGps = false;

  @override
  void didUpdateWidget(LocationPickerMap old) {
    super.didUpdateWidget(old);
    // Elegir otra zona desde los chips mueve el pin a su centro.
    if (old.selectedZone != widget.selectedZone) {
      final c = widget.zones[widget.selectedZone];
      if (c != null) _setPin(c, zoom: 15, fromGps: false, notify: false);
    }
  }

  void _setPin(LatLng p, {double? zoom, required bool fromGps, bool notify = true}) {
    setState(() {
      _pin = p;
      _fromGps = fromGps;
    });
    _controller.move(p, zoom ?? _controller.camera.zoom);
    if (notify) widget.onLocationChanged(p);
  }

  Future<void> _useGps() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    final (outcome, position) = await LocationService.current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (outcome == LocationOutcome.granted && position != null) {
      _setPin(position, zoom: 16, fromGps: true);
      return;
    }
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(switch (outcome) {
        LocationOutcome.serviceOff => 'La ubicación del teléfono está apagada. Fija el pin en el mapa.',
        LocationOutcome.denied => 'No diste permiso de ubicación. Fija el pin en el mapa.',
        _ => 'No pudimos obtener tu ubicación. Fija el pin en el mapa.',
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final label = _fromGps
        ? 'Ubicación del GPS fijada'
        : '${_pin.latitude.toStringAsFixed(4)}, ${_pin.longitude.toStringAsFixed(4)}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
        child: SizedBox(
          height: widget.height,
          child: Stack(children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _pin,
                initialZoom: 14,
                onTap: (_, point) => _setPin(point, fromGps: false),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ec.bocadoo.bocadoo',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: _pin,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on_rounded, size: 44, color: colors.primary),
                  ),
                ]),
                const RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [TextSourceAttribution('OpenStreetMap')],
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: FilledButton.tonalIcon(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                onPressed: _locating ? null : _useGps,
                icon: _locating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.gps_fixed_rounded, size: 18),
                label: const Text('Mi GPS'),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.push_pin_outlined, size: 16, color: colors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Pin fijado · $label',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
        ),
      ]),
      const SizedBox(height: 2),
      Text('Toca el mapa para mover el pin a tu ubicación exacta.',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
    ]);
  }
}
