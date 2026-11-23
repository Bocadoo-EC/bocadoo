import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/location/location_service.dart';
import '../../../../core/theme/app_theme.dart';

enum _LocationSource { initial, gps, searched, manual }

class _StreetSuggestion {
  const _StreetSuggestion({
    required this.title,
    required this.subtitle,
    required this.zoneLabel,
    required this.point,
  });

  final String title;
  final String subtitle;
  final String zoneLabel;
  final LatLng point;
}

/// Mapa interactivo para registro de comensal:
/// - Solicita permiso de ubicación y detecta el GPS automáticamente al abrir.
/// - Permite buscar direcciones por calles/avenidas (Nominatim + respaldo local Quito).
/// - Permite tocar el mapa para ajustar el pin con precisión.
class DinerLocationPicker extends StatefulWidget {
  const DinerLocationPicker({
    super.key,
    required this.initialLocation,
    required this.onLocationResolved,
  });

  final LatLng initialLocation;
  final void Function(LatLng point, String zoneLabel) onLocationResolved;

  @override
  State<DinerLocationPicker> createState() => _DinerLocationPickerState();
}

class _DinerLocationPickerState extends State<DinerLocationPicker> {
  static const List<_StreetSuggestion> _localQuitoStreets = [
    _StreetSuggestion(
      title: 'Av. 12 de Octubre y Veintimilla',
      subtitle: 'Frente a la PUCE · Quito',
      zoneLabel: 'Frente a la PUCE',
      point: LatLng(-0.2105, -78.4912),
    ),
    _StreetSuggestion(
      title: 'Calle Toledo y Madrid',
      subtitle: 'La Floresta · Quito',
      zoneLabel: 'La Floresta',
      point: LatLng(-0.2061, -78.4820),
    ),
    _StreetSuggestion(
      title: 'Av. Amazonas y Patria',
      subtitle: 'La Mariscal / El Ejido · Quito',
      zoneLabel: 'La Mariscal',
      point: LatLng(-0.2068, -78.4947),
    ),
    _StreetSuggestion(
      title: 'Av. de los Shyris y Naciones Unidas',
      subtitle: 'La Carolina · Quito',
      zoneLabel: 'La Carolina',
      point: LatLng(-0.1774, -78.4816),
    ),
    _StreetSuggestion(
      title: 'Av. 6 de Diciembre y Colón',
      subtitle: 'Mariscal Sucre · Quito',
      zoneLabel: 'La Mariscal',
      point: LatLng(-0.2007, -78.4889),
    ),
    _StreetSuggestion(
      title: 'Av. González Suárez',
      subtitle: 'González Suárez · Quito',
      zoneLabel: 'González Suárez',
      point: LatLng(-0.2004, -78.4774),
    ),
    _StreetSuggestion(
      title: 'Av. Granados y Eloy Alfaro',
      subtitle: 'UDLA Granados · Quito',
      zoneLabel: 'UDLA Granados',
      point: LatLng(-0.1890, -78.4680),
    ),
    _StreetSuggestion(
      title: 'Ladrón de Guevara y Andalucía',
      subtitle: 'EPN / Salesiana · Quito',
      zoneLabel: 'EPN / Salesiana',
      point: LatLng(-0.2116, -78.4887),
    ),
    _StreetSuggestion(
      title: 'Calle García Moreno y Chile',
      subtitle: 'Centro Histórico · Quito',
      zoneLabel: 'Centro Histórico',
      point: LatLng(-0.2200, -78.5120),
    ),
    _StreetSuggestion(
      title: 'Av. Interoceánica y Siena',
      subtitle: 'Cumbayá · Quito',
      zoneLabel: 'Cumbayá',
      point: LatLng(-0.1920, -78.4320),
    ),
  ];

  final _mapCtrl = MapController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 7),
      headers: const {
        'User-Agent': 'BocadooEcuador/1.0 (ec.bocadoo.bocadoo)',
        'Accept-Language': 'es',
      },
    ),
  );

  late LatLng _pin = widget.initialLocation;
  _LocationSource _source = _LocationSource.initial;
  String _addressTitle = 'Quito · Toca el mapa o busca tu calle';

  bool _locating = false;
  bool _searching = false;
  LocationOutcome? _permissionOutcome;
  List<_StreetSuggestion> _suggestions = const [];
  String? _searchError;
  Timer? _debounce;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _detectGps(autoOnInit: true);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dio.close();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  static String _nearestQuitoZone(LatLng point) {
    var best = _localQuitoStreets.first;
    var bestDist = LocationService.meters(point, best.point);
    for (final candidate in _localQuitoStreets.skip(1)) {
      final d = LocationService.meters(point, candidate.point);
      if (d < bestDist) {
        bestDist = d;
        best = candidate;
      }
    }
    return best.zoneLabel;
  }

  Future<void> _detectGps({bool autoOnInit = false}) async {
    setState(() {
      _locating = true;
      _permissionOutcome = null;
    });

    final (outcome, pos) = await LocationService.current();
    if (!mounted) return;

    if (outcome == LocationOutcome.granted && pos != null) {
      final fallbackZone = _nearestQuitoZone(pos);
      setState(() {
        _locating = false;
        _pin = pos;
        _source = _LocationSource.gps;
        _addressTitle = 'Ubicación actual detectada';
        _permissionOutcome = LocationOutcome.granted;
      });
      _mapCtrl.move(pos, 16.2);
      widget.onLocationResolved(pos, fallbackZone);
      unawaited(_reverseGeocode(pos));
      return;
    }

    setState(() {
      _locating = false;
      _permissionOutcome = outcome;
    });

    if (!autoOnInit) {
      if (outcome == LocationOutcome.serviceOff) {
        await Geolocator.openLocationSettings();
      } else if (outcome == LocationOutcome.denied) {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
        }
      }
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    final fallbackZone = _nearestQuitoZone(point);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': point.latitude.toStringAsFixed(6),
          'lon': point.longitude.toStringAsFixed(6),
          'addressdetails': 1,
          'zoom': 17,
        },
      );
      if (!mounted) return;
      // Solo actualiza si el pin sigue en ese punto.
      if (LocationService.meters(_pin, point) > 25) return;
      final data = res.data;
      if (data == null) return;
      final addr = data['address'] is Map
          ? Map<String, dynamic>.from(data['address'] as Map)
          : const <String, dynamic>{};
      final road = (addr['road'] ?? addr['pedestrian'] ?? '').toString().trim();
      final house = (addr['house_number'] ?? '').toString().trim();
      final sector = (addr['neighbourhood'] ??
              addr['suburb'] ??
              addr['quarter'] ??
              addr['city_district'] ??
              '')
          .toString()
          .trim();

      final resolvedZone = sector.isNotEmpty ? sector : fallbackZone;
      final streetText = road.isNotEmpty
          ? (house.isNotEmpty ? '$road $house' : road)
          : (sector.isNotEmpty ? sector : fallbackZone);
      final formatted = sector.isNotEmpty && streetText != sector
          ? '$streetText · $sector'
          : streetText;

      setState(() {
        _addressTitle = formatted;
      });
      widget.onLocationResolved(point, resolvedZone);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_source == _LocationSource.manual) {
          _addressTitle = 'Sector $fallbackZone';
        }
      });
      widget.onLocationResolved(point, fallbackZone);
    }
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    if (query.length < 3) {
      final local = _filterLocalSuggestions(query);
      setState(() {
        _suggestions = local;
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () {
      if (mounted) _performSearch(query);
    });
  }

  List<_StreetSuggestion> _filterLocalSuggestions(String query) {
    final q = query.toLowerCase();
    return _localQuitoStreets
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.subtitle.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _performSearch(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    final token = ++_searchToken;
    setState(() {
      _searching = true;
      _searchError = null;
    });

    final localMatches = _filterLocalSuggestions(query);
    try {
      final res = await _dio.get<List<dynamic>>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': '$query, Quito, Ecuador',
          'format': 'jsonv2',
          'addressdetails': 1,
          'limit': 5,
          'countrycodes': 'ec',
          'viewbox': '-78.65,-0.02,-78.30,-0.40',
        },
      );
      if (!mounted || token != _searchToken) return;

      final items = <_StreetSuggestion>[];
      final seen = <String>{};
      final rawList = res.data ?? const [];
      for (final rawItem in rawList.whereType<Map>()) {
        final item = Map<String, dynamic>.from(rawItem);
        final lat = double.tryParse((item['lat'] ?? '').toString());
        final lon = double.tryParse((item['lon'] ?? '').toString());
        if (lat == null || lon == null) continue;
        final addr = item['address'] is Map
            ? Map<String, dynamic>.from(item['address'] as Map)
            : const <String, dynamic>{};
        final road = (addr['road'] ??
                addr['pedestrian'] ??
                addr['neighbourhood'] ??
                item['name'] ??
                '')
            .toString()
            .trim();
        final sector = (addr['neighbourhood'] ??
                addr['suburb'] ??
                addr['quarter'] ??
                addr['city_district'] ??
                addr['city'] ??
                'Quito')
            .toString()
            .trim();
        final displayParts = (item['display_name'] ?? '')
            .toString()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final title = road.isNotEmpty
            ? road
            : (displayParts.isNotEmpty ? displayParts.first : query);
        final subtitle = sector.isNotEmpty
            ? '$sector · Quito'
            : displayParts.skip(1).take(2).join(', ');
        final key = '${title.toLowerCase()}|${subtitle.toLowerCase()}';
        if (!seen.add(key)) continue;
        final point = LatLng(lat, lon);
        items.add(
          _StreetSuggestion(
            title: title,
            subtitle: subtitle,
            zoneLabel: sector.isNotEmpty ? sector : _nearestQuitoZone(point),
            point: point,
          ),
        );
      }

      for (final local in localMatches) {
        final key = '${local.title.toLowerCase()}|${local.subtitle.toLowerCase()}';
        if (items.length < 5 && seen.add(key)) {
          items.add(local);
        }
      }

      setState(() {
        _searching = false;
        _suggestions = items;
        _searchError = items.isEmpty
            ? 'No encontramos esa calle. Prueba con otro nombre o toca el mapa.'
            : null;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searching = false;
        _suggestions = localMatches;
        _searchError = localMatches.isEmpty
            ? 'No pudimos buscar en línea. Toca el mapa para fijar tu pin.'
            : null;
      });
    }
  }

  void _selectSuggestion(_StreetSuggestion s) {
    _searchFocus.unfocus();
    _searchCtrl.text = s.title;
    setState(() {
      _pin = s.point;
      _source = _LocationSource.searched;
      _addressTitle = s.subtitle.isNotEmpty ? '${s.title} · ${s.zoneLabel}' : s.title;
      _suggestions = const [];
      _searchError = null;
    });
    _mapCtrl.move(s.point, 16.5);
    widget.onLocationResolved(s.point, s.zoneLabel);
  }

  void _onMapTap(LatLng point) {
    _searchFocus.unfocus();
    final fallbackZone = _nearestQuitoZone(point);
    setState(() {
      _pin = point;
      _source = _LocationSource.manual;
      _addressTitle = 'Pin ajustado · $fallbackZone';
      _suggestions = const [];
    });
    _mapCtrl.move(point, _mapCtrl.camera.zoom);
    widget.onLocationResolved(point, fallbackZone);
    unawaited(_reverseGeocode(point));
  }

  void _zoomBy(double delta) {
    final next = (_mapCtrl.camera.zoom + delta).clamp(11.0, 18.5);
    _mapCtrl.move(_pin, next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final bColors = context.bocadooColors;

    final (badgeText, badgeBg, badgeFg, badgeIcon) = switch (_source) {
      _LocationSource.gps => (
          'GPS actual',
          bColors.successContainer,
          bColors.onSuccessContainer,
          Icons.gps_fixed_rounded,
        ),
      _LocationSource.searched => (
          'Calle buscada',
          cs.primaryContainer,
          cs.onPrimaryContainer,
          Icons.signpost_rounded,
        ),
      _LocationSource.manual => (
          'Pin manual',
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          Icons.push_pin_rounded,
        ),
      _LocationSource.initial => (
          'Por confirmar',
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          Icons.explore_outlined,
        ),
    };

    final showPermissionBanner = _permissionOutcome == LocationOutcome.denied ||
        _permissionOutcome == LocationOutcome.serviceOff ||
        _permissionOutcome == LocationOutcome.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Buscador de calles / avenidas
        TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          onSubmitted: _performSearch,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, color: cs.primary),
            hintText: 'Buscar calle o sector (ej. Av. 12 de Octubre)',
            suffixIcon: _searching
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  )
                : (_searchCtrl.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: Icon(
                          Icons.close_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _suggestions = const [];
                            _searchError = null;
                          });
                        },
                      )
                    : null),
          ),
        ),

        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _suggestions.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: cs.primary,
                    ),
                    title: Text(
                      _suggestions[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: _suggestions[i].subtitle.isNotEmpty
                        ? Text(
                            _suggestions[i].subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        : null,
                    onTap: () => _selectSuggestion(_suggestions[i]),
                  ),
                ],
              ],
            ),
          ),
        ] else if (_searchError != null) ...[
          const SizedBox(height: 6),
          Text(
            _searchError!,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],

        if (showPermissionBanner) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  _permissionOutcome == LocationOutcome.serviceOff
                      ? Icons.location_off_rounded
                      : Icons.my_location_rounded,
                  size: 18,
                  color: cs.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _permissionOutcome == LocationOutcome.serviceOff
                        ? 'Enciende el GPS o busca tu calle arriba.'
                        : 'Activa el permiso de ubicación para ubicarte al instante.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _locating ? null : () => _detectGps(),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(
                    _permissionOutcome == LocationOutcome.serviceOff
                        ? 'Activar'
                        : 'Permitir',
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 10),

        // Mapa interactivo
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 236,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 14.5,
                    onTap: (_, point) => _onMapTap(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'ec.bocadoo.bocadoo',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _pin,
                          width: 46,
                          height: 46,
                          alignment: Alignment.topCenter,
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 46,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    const RichAttributionWidget(
                      alignment: AttributionAlignment.bottomLeft,
                      attributions: [TextSourceAttribution('OpenStreetMap')],
                    ),
                  ],
                ),

                // Indicador de detección automática de GPS
                if (_locating)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(
                          AppTheme.buttonRadius,
                        ),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Detectando ubicación...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Botón Mi GPS
                Positioned(
                  top: 10,
                  right: 10,
                  child: FilledButton.tonalIcon(
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(0, 42)),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 14),
                      ),
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    onPressed: _locating ? null : () => _detectGps(),
                    icon: const Icon(Icons.gps_fixed_rounded, size: 17),
                    label: const Text('Mi GPS'),
                  ),
                ),

                // Controles de zoom + / -
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapZoomButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Acercar',
                        onPressed: () => _zoomBy(1.0),
                      ),
                      const SizedBox(height: 6),
                      _MapZoomButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Alejar',
                        onPressed: () => _zoomBy(-1.0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Tarjeta resumen de ubicación seleccionada
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.pin_drop_rounded,
                  size: 18,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(
                              AppTheme.buttonRadius,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(badgeIcon, size: 12, color: badgeFg),
                              const SizedBox(width: 4),
                              Text(
                                badgeText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: badgeFg,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _addressTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_pin.latitude.toStringAsFixed(4)}, ${_pin.longitude.toStringAsFixed(4)} · Toca el mapa para mover el pin',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapZoomButton extends StatelessWidget {
  const _MapZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}
