import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/location/location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../customer_controller.dart';

/// Opciones de radio de búsqueda en metros.
const _locationRangeOptions = <(String label, int? meters)>[
  ('500 m', 500),
  ('1 km', 1000),
  ('2 km', 2000),
  ('5 km', 5000),
];

enum _ModalLocationSource { gps, searched, manual }

class _StreetOption {
  const _StreetOption({
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

/// Dispara el modal obligatorio de ubicación al entrar a `Restaurantes` o `Planes`
/// si aún no hay ubicación confirmada en la sesión, evitando bucles al cambiar de tab.
Future<void> ensureCustomerLocationPrompt(
  BuildContext context,
  CustomerController controller,
) async {
  if (!context.mounted) return;
  if (controller.state.hasConfiguredLocation || controller.isLocationPromptOpen) {
    return;
  }
  controller.setLocationPromptOpen(true);
  try {
    await showLocationSetupSheet(
      context,
      controller,
      mandatory: true,
    );
  } finally {
    controller.setLocationPromptOpen(false);
  }
}

/// Abre el modal de ubicación (`"¿Dónde vas a almorzar?"`) con mapa interactivo.
Future<void> showLocationSetupSheet(
  BuildContext context,
  CustomerController controller, {
  bool? mandatory,
}) {
  final isMandatory = mandatory ?? !controller.state.hasConfiguredLocation;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: !isMandatory,
    enableDrag: !isMandatory,
    showDragHandle: !isMandatory,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _LocationSetupSheet(
      controller: controller,
      isMandatory: isMandatory,
    ),
  );
}

class _LocationSetupSheet extends StatefulWidget {
  const _LocationSetupSheet({
    required this.controller,
    required this.isMandatory,
  });

  final CustomerController controller;
  final bool isMandatory;

  @override
  State<_LocationSetupSheet> createState() => _LocationSetupSheetState();
}

class _LocationSetupSheetState extends State<_LocationSetupSheet> {
  static const List<_StreetOption> _localQuitoStreets = [
    _StreetOption(
      title: 'Av. 12 de Octubre y Veintimilla',
      subtitle: 'Frente a la PUCE · Quito',
      zoneLabel: 'Frente a la PUCE',
      point: LatLng(-0.2105, -78.4912),
    ),
    _StreetOption(
      title: 'Calle Toledo y Madrid',
      subtitle: 'La Floresta · Quito',
      zoneLabel: 'La Floresta',
      point: LatLng(-0.2061, -78.4820),
    ),
    _StreetOption(
      title: 'Av. Amazonas y Patria',
      subtitle: 'La Mariscal / El Ejido · Quito',
      zoneLabel: 'La Mariscal',
      point: LatLng(-0.2068, -78.4947),
    ),
    _StreetOption(
      title: 'Av. de los Shyris y Naciones Unidas',
      subtitle: 'La Carolina · Quito',
      zoneLabel: 'La Carolina',
      point: LatLng(-0.1774, -78.4816),
    ),
    _StreetOption(
      title: 'Av. 6 de Diciembre y Colón',
      subtitle: 'Mariscal Sucre · Quito',
      zoneLabel: 'La Mariscal',
      point: LatLng(-0.2007, -78.4889),
    ),
    _StreetOption(
      title: 'Av. González Suárez',
      subtitle: 'González Suárez · Quito',
      zoneLabel: 'González Suárez',
      point: LatLng(-0.2004, -78.4774),
    ),
    _StreetOption(
      title: 'Ladrón de Guevara y Andalucía',
      subtitle: 'EPN / Salesiana · Quito',
      zoneLabel: 'EPN / Salesiana',
      point: LatLng(-0.2116, -78.4887),
    ),
    _StreetOption(
      title: 'Calle García Moreno y Chile',
      subtitle: 'Centro Histórico · Quito',
      zoneLabel: 'Centro Histórico',
      point: LatLng(-0.2200, -78.5120),
    ),
    _StreetOption(
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

  late LatLng _pin;
  late int? _selectedRadius;
  late bool _hasPickedLocation;
  late _ModalLocationSource _source;
  late String _addressTitle;
  late String _zoneLabel;

  bool _locating = false;
  bool _searching = false;
  String? _gpsError;
  List<_StreetOption> _suggestions = const [];
  String? _searchError;
  Timer? _debounce;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.state;
    _hasPickedLocation = s.hasConfiguredLocation;
    _pin = s.searchCenter ?? LocationService.fallbackPuce;
    _selectedRadius =
        (s.hasConfiguredLocation ? s.searchRadiusMeters : null) ?? 1000;
    _zoneLabel = s.searchZoneLabel ?? 'Zona elegida';
    _addressTitle = s.searchZoneLabel ?? 'Ubicación seleccionada';
    _source = s.searchZoneLabel == 'Tu ubicación actual'
        ? _ModalLocationSource.gps
        : _ModalLocationSource.manual;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dio.close();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  static String _nearestZone(LatLng point) {
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

  void _closeSheetOrBackToPase() {
    _searchFocus.unfocus();
    final router = GoRouter.of(context);
    final nav = Navigator.of(context);
    final mustRedirectToPase =
        widget.isMandatory && !widget.controller.state.hasConfiguredLocation;
    nav.pop();
    if (mustRedirectToPase) {
      router.go('/customer/pase');
    }
  }

  Future<void> _detectGps() async {
    _searchFocus.unfocus();
    setState(() {
      _locating = true;
      _gpsError = null;
    });

    final (outcome, pos) = await LocationService.current();
    if (!mounted) return;

    if (outcome == LocationOutcome.granted && pos != null) {
      setState(() {
        _locating = false;
        _hasPickedLocation = true;
        _pin = pos;
        _source = _ModalLocationSource.gps;
        _addressTitle = 'Ubicación actual detectada';
        _zoneLabel = 'Tu ubicación actual';
        _suggestions = const [];
        _searchError = null;
      });
      _mapCtrl.move(pos, 16.0);
      unawaited(_reverseGeocode(pos, keepGpsLabel: true));
      return;
    }

    setState(() {
      _locating = false;
      _gpsError = switch (outcome) {
        LocationOutcome.serviceOff =>
          'Activa el GPS de tu teléfono o busca tu calle arriba.',
        LocationOutcome.denied =>
          'Permiso de ubicación denegado. Busca tu calle o toca el mapa.',
        _ =>
          'No pudimos detectar tu GPS. Busca tu calle o toca el mapa.',
      };
    });

    if (outcome == LocationOutcome.serviceOff) {
      await Geolocator.openLocationSettings();
    } else if (outcome == LocationOutcome.denied) {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
    }
  }

  Future<void> _reverseGeocode(
    LatLng point, {
    bool keepGpsLabel = false,
  }) async {
    final fallbackZone = _nearestZone(point);
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

      final streetText = road.isNotEmpty
          ? (house.isNotEmpty ? '$road $house' : road)
          : (sector.isNotEmpty ? sector : fallbackZone);
      final formatted = sector.isNotEmpty && streetText != sector
          ? '$streetText · $sector'
          : streetText;

      setState(() {
        _addressTitle = formatted;
        _zoneLabel = keepGpsLabel
            ? 'Tu ubicación actual'
            : (road.isNotEmpty ? road : (sector.isNotEmpty ? sector : fallbackZone));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (!keepGpsLabel) {
          _addressTitle = 'Sector $fallbackZone';
          _zoneLabel = fallbackZone;
        }
      });
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
      setState(() {
        _suggestions = _filterLocal(query);
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () {
      if (mounted) _performSearch(query);
    });
  }

  List<_StreetOption> _filterLocal(String query) {
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

    final localMatches = _filterLocal(query);
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

      final items = <_StreetOption>[];
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
          _StreetOption(
            title: title,
            subtitle: subtitle,
            zoneLabel: title,
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

  void _selectSuggestion(_StreetOption s) {
    _searchFocus.unfocus();
    _searchCtrl.text = s.title;
    setState(() {
      _hasPickedLocation = true;
      _pin = s.point;
      _source = _ModalLocationSource.searched;
      _addressTitle = s.title;
      _zoneLabel = s.zoneLabel;
      _suggestions = const [];
      _searchError = null;
      _gpsError = null;
    });
    _mapCtrl.move(s.point, 16.2);
  }

  void _onMapTap(LatLng point) {
    _searchFocus.unfocus();
    final fallbackZone = _nearestZone(point);
    setState(() {
      _hasPickedLocation = true;
      _pin = point;
      _source = _ModalLocationSource.manual;
      _addressTitle = fallbackZone;
      _zoneLabel = fallbackZone;
      _suggestions = const [];
      _gpsError = null;
    });
    _mapCtrl.move(point, _mapCtrl.camera.zoom);
    unawaited(_reverseGeocode(point));
  }

  void _zoomBy(double delta) {
    final next = (_mapCtrl.camera.zoom + delta).clamp(10.5, 18.5);
    _mapCtrl.move(_pin, next);
  }

  double _zoomForRadius(int? meters) => switch (meters) {
        500 => 15.2,
        1000 => 14.2,
        2000 => 13.2,
        5000 => 11.8,
        _ => 13.0,
      };

  void _selectRadius(int? meters) {
    setState(() => _selectedRadius = meters);
    _mapCtrl.move(_pin, _zoomForRadius(meters));
  }

  String _rangeCtaLabel() {
    if (_selectedRadius == null) return 'Aplicar ubicación (Todas)';
    final m = _selectedRadius!;
    if (m < 1000) return 'Aplicar ubicación ($m m)';
    final km = m % 1000 == 0
        ? '${m ~/ 1000}'
        : (m / 1000).toStringAsFixed(1).replaceAll('.', ',');
    return 'Aplicar ubicación ($km km)';
  }

  void _apply() {
    if (!_hasPickedLocation) return;
    _searchFocus.unfocus();
    widget.controller.applySearchArea(
      center: _pin,
      label: _zoneLabel,
      radiusMeters: _selectedRadius,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final textTheme = Theme.of(context).textTheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !widget.isMandatory,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.isMandatory) {
          _closeSheetOrBackToPase();
        }
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.90,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Cabecera Compacta
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    widget.isMandatory ? 16 : 2,
                    16,
                    10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: b.heroGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 20,
                          color: b.imageForeground,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '¿Dónde vas a almorzar?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (textTheme.titleLarge ?? const TextStyle())
                              .copyWith(
                            fontSize: 18.5,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Cerrar',
                        onPressed: _closeSheetOrBackToPase,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),

                // Cuerpo desplazable sin overflow ante teclado
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 2. Selector de Rango Máximo de Búsqueda
                        Text(
                          'Rango máximo de búsqueda',
                          style: (textTheme.titleSmall ?? const TextStyle())
                              .copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final opt in _locationRangeOptions)
                              ChoiceChip(
                                label: Text(opt.$1),
                                selected: _selectedRadius == opt.$2,
                                onSelected: (_) => _selectRadius(opt.$2),
                              ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // 3. Buscador + Mapa Interactivo Directo
                        TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          textInputAction: TextInputAction.search,
                          onChanged: _onSearchChanged,
                          onSubmitted: _performSearch,
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: colors.primary,
                            ),
                            hintText:
                                'Buscar calle o sector (ej. Av. 12 de Octu...)',
                            suffixIcon: _searching
                                ? Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.primary,
                                      ),
                                    ),
                                  )
                                : (_searchCtrl.text.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Limpiar búsqueda',
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: colors.onSurfaceVariant,
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
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (var i = 0; i < _suggestions.length; i++) ...[
                                  if (i > 0)
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: colors.outlineVariant,
                                    ),
                                  ListTile(
                                    dense: true,
                                    leading: Icon(
                                      Icons.location_on_outlined,
                                      size: 19,
                                      color: colors.primary,
                                    ),
                                    title: Text(
                                      _suggestions[i].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: (textTheme.bodyMedium ??
                                              const TextStyle())
                                          .copyWith(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                    subtitle: _suggestions[i].subtitle.isNotEmpty
                                        ? Text(
                                            _suggestions[i].subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: (textTheme.bodySmall ??
                                                    const TextStyle())
                                                .copyWith(
                                              fontSize: 11.5,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          )
                                        : null,
                                    onTap: () =>
                                        _selectSuggestion(_suggestions[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ] else if (_searchError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _searchError!,
                            style: (textTheme.bodySmall ?? const TextStyle())
                                .copyWith(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],

                        if (_gpsError != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colors.errorContainer
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _gpsError!,
                              style: (textTheme.bodySmall ?? const TextStyle())
                                  .copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Mapa interactivo embebido
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            height: 204,
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapCtrl,
                                  options: MapOptions(
                                    initialCenter: _pin,
                                    initialZoom: _zoomForRadius(_selectedRadius),
                                    onTap: (_, point) => _onMapTap(point),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'ec.bocadoo.bocadoo',
                                    ),
                                    if (_selectedRadius != null)
                                      CircleLayer(
                                        circles: [
                                          CircleMarker(
                                            point: _pin,
                                            radius: _selectedRadius!.toDouble(),
                                            useRadiusInMeter: true,
                                            color: colors.primary
                                                .withValues(alpha: 0.12),
                                            borderColor: colors.primary
                                                .withValues(alpha: 0.65),
                                            borderStrokeWidth: 1.8,
                                          ),
                                        ],
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
                                            color: colors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const RichAttributionWidget(
                                      alignment: AttributionAlignment.bottomLeft,
                                      attributions: [
                                        TextSourceAttribution('OpenStreetMap'),
                                      ],
                                    ),
                                  ],
                                ),

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
                                        color:
                                            colors.surface.withValues(alpha: 0.94),
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.buttonRadius,
                                        ),
                                        border: Border.all(
                                          color: colors.outlineVariant,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: colors.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Detectando...',
                                            style: (textTheme.labelSmall ??
                                                    const TextStyle())
                                                .copyWith(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: colors.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                // Botón flotante Mi GPS
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: FilledButton.tonalIcon(
                                    style: const ButtonStyle(
                                      minimumSize:
                                          WidgetStatePropertyAll(Size(0, 40)),
                                      padding: WidgetStatePropertyAll(
                                        EdgeInsets.symmetric(horizontal: 13),
                                      ),
                                      textStyle: WidgetStatePropertyAll(
                                        TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    onPressed: _locating ? null : _detectGps,
                                    icon: const Icon(
                                      Icons.gps_fixed_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Mi GPS'),
                                  ),
                                ),

                                // Controles + / -
                                Positioned(
                                  right: 10,
                                  bottom: 10,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _ModalZoomBtn(
                                        icon: Icons.add_rounded,
                                        tooltip: 'Acercar',
                                        onPressed: () => _zoomBy(1.0),
                                      ),
                                      const SizedBox(height: 6),
                                      _ModalZoomBtn(
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

                        const SizedBox(height: 12),

                        // 4. Slot Dinámico Único (2 estados mutuamente excluyentes)
                        if (!_hasPickedLocation)
                          OutlinedButton.icon(
                            onPressed: _locating ? null : _detectGps,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              side: BorderSide(
                                color: colors.primary.withValues(alpha: 0.45),
                              ),
                              backgroundColor: colors.primaryContainer
                                  .withValues(alpha: 0.25),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: _locating
                                ? SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.primary,
                                    ),
                                  )
                                : Icon(
                                    Icons.my_location_rounded,
                                    size: 19,
                                    color: colors.primary,
                                  ),
                            label: Text(
                              'Usar mi ubicación actual',
                              style: (textTheme.labelLarge ?? const TextStyle())
                                  .copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.outlineVariant),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.shadow.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(
                                    Icons.pin_drop_rounded,
                                    size: 19,
                                    color: colors.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: b.successContainer,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _source ==
                                                      _ModalLocationSource.gps
                                                  ? Icons.gps_fixed_rounded
                                                  : Icons.check_circle_rounded,
                                              size: 12,
                                              color: b.onSuccessContainer,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _source ==
                                                      _ModalLocationSource.gps
                                                  ? 'GPS actual'
                                                  : 'Ubicación seleccionada',
                                              style: (textTheme.labelSmall ??
                                                      const TextStyle())
                                                  .copyWith(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: b.onSuccessContainer,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        _addressTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: (textTheme.titleSmall ??
                                                const TextStyle())
                                            .copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_pin.latitude.toStringAsFixed(4)}, ${_pin.longitude.toStringAsFixed(4)} · Toca el mapa para mover el pin',
                                        style: (textTheme.bodySmall ??
                                                const TextStyle())
                                            .copyWith(
                                          fontSize: 11.5,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // 5. Botón Principal Inferior
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: FilledButton.icon(
                    onPressed: _hasPickedLocation ? _apply : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: Text(
                      _rangeCtaLabel(),
                      style:
                          (textTheme.labelLarge ?? const TextStyle()).copyWith(
                        color: _hasPickedLocation
                            ? colors.onPrimary
                            : colors.onSurface.withValues(alpha: 0.38),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalZoomBtn extends StatelessWidget {
  const _ModalZoomBtn({
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
            child: Icon(icon, size: 19, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}
