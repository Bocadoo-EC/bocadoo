import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/walking_route_service.dart';
import '../domain/commercial_zones.dart';
import 'customer_controller.dart';
import 'social_widgets.dart';

enum _Phase { locating, choosing, map }

/// Radios de búsqueda en metros; `null` = todos.
const _ranges = <(String, int?)>[('100 m', 100), ('200 m', 200), ('500 m', 500), ('1 km', 1000), ('Todos', null)];

String _distance(int m) => m < 1000 ? '$m m' : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

String _occupancy(String o) => switch (o) {
      'LLENO' => 'Lleno',
      'MOVIDO' => 'Movido',
      _ => 'Libre',
    };

/// C11 · Mapa de restaurantes. Ubicación con GPS o por zona comercial, radio de
/// búsqueda y ruta a pie dibujada dentro de la app.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  final _routes = WalkingRouteService();
  bool _mapReady = false;

  _Phase _phase = _Phase.locating;
  String? _locationNotice;
  LatLng _me = quitoZones.first.point;
  String _place = quitoZones.first.name;
  int? _range = 500;

  Restaurant? _selected;
  WalkingRoute? _route;
  Restaurant? _routeTo;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _phase = _Phase.locating;
      _locationNotice = null;
    });
    final (outcome, position) = await LocationService.current();
    if (!mounted || _phase != _Phase.locating) return;
    if (outcome == LocationOutcome.granted && position != null) {
      setState(() {
        _me = position;
        _place = 'Tu ubicación actual';
        _clearSelection();
        _phase = _Phase.map;
      });
      _recenter();
      return;
    }
    setState(() {
      _phase = _Phase.choosing;
      _locationNotice = switch (outcome) {
        LocationOutcome.serviceOff => 'La ubicación del teléfono está apagada. Elige una zona para ubicarte en el mapa.',
        LocationOutcome.denied => 'No diste permiso de ubicación. Elige una zona para ubicarte en el mapa.',
        _ => 'No pudimos obtener tu ubicación. Elige una zona para ubicarte en el mapa.',
      };
    });
  }

  void _chooseZone(CommercialZone zone) {
    setState(() {
      _me = zone.point;
      _place = zone.name;
      _clearSelection();
      _phase = _Phase.map;
    });
    _recenter();
  }

  void _clearSelection() {
    _selected = null;
    _route = null;
    _routeTo = null;
  }

  double get _zoom => switch (_range) {
        100 || 200 => 17,
        500 => 16,
        1000 => 15,
        _ => 13,
      };

  void _recenter() {
    if (_mapReady) _map.move(_me, _zoom);
  }

  Future<void> _showRoute(Restaurant r) async {
    final to = LatLng(r.latitude!, r.longitude!);
    setState(() => _routing = true);
    final route = await _routes.route(_me, to);
    if (!mounted) return;
    setState(() {
      _routing = false;
      _route = route;
      _routeTo = r;
      _selected = null;
    });
    if (_mapReady) {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(route.points),
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 260),
        maxZoom: 17,
      ));
    }
  }

  void _openRestaurant(Restaurant r) => context.go('/customer/restaurants/${r.id}');

  void _acceptArea() {
    ref.read(customerControllerProvider).applySearchArea(
          center: _me,
          label: _place,
          radiusMeters: _range,
        );
    _back();
  }

  void _back() => context.canPop() ? context.pop() : context.go('/customer/restaurants');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final controller = ref.watch(customerControllerProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Header(
            place: _phase == _Phase.map ? _place : 'Quito',
            onBack: _back,
            onZones: _phase == _Phase.map ? () => setState(() => _phase = _Phase.choosing) : null,
          ),
          Expanded(
            child: switch (_phase) {
              _Phase.locating => _Locating(onSkip: () => setState(() => _phase = _Phase.choosing)),
              _Phase.choosing => _ZonePicker(
                  notice: _locationNotice,
                  selected: _place,
                  onUseGps: _locate,
                  onZone: _chooseZone,
                ),
              _Phase.map => ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final s = controller.state;
                    if (s.restaurants.isEmpty) return const SocialLoading('Cargando restaurantes');
                    return _buildMap(context, s.restaurants);
                  },
                ),
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildMap(BuildContext context, List<Restaurant> all) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final placed = [
      for (final r in all)
        if (r.hasLocation) (r, LocationService.meters(_me, LatLng(r.latitude!, r.longitude!))),
    ];
    final visible = [for (final p in placed) if (_range == null || p.$2 <= _range!) p];
    final nearest = placed.isEmpty ? null : placed.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
    final farAway = nearest != null && nearest > 20000;

    Color occupancyColor(String o) => switch (o) {
          'LLENO' => b.danger,
          'MOVIDO' => colors.primary,
          _ => b.success,
        };

    return Stack(children: [
      Positioned.fill(
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _me,
            initialZoom: _zoom,
            onMapReady: () {
              _mapReady = true;
              _map.move(_me, _zoom);
            },
            onTap: (_, _) => setState(() => _selected = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'ec.bocadoo.bocadoo',
            ),
            if (_range != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: _me,
                  radius: _range!.toDouble(),
                  useRadiusInMeter: true,
                  color: colors.primary.withValues(alpha: 0.10),
                  borderColor: colors.primary.withValues(alpha: 0.6),
                  borderStrokeWidth: 1.5,
                ),
              ]),
            if (_route != null)
              PolylineLayer(polylines: [
                Polyline(
                  points: _route!.points,
                  strokeWidth: 5,
                  color: colors.primary,
                  pattern: _route!.approximate
                      ? StrokePattern.dashed(segments: const [10, 10])
                      : const StrokePattern.solid(),
                ),
              ]),
            MarkerLayer(markers: [
              for (final (r, _) in visible)
                Marker(
                  point: LatLng(r.latitude!, r.longitude!),
                  width: 170,
                  height: 46,
                  alignment: Alignment.topCenter,
                  child: _RestaurantPin(
                    name: r.name,
                    occupancyColor: occupancyColor(r.occupancy),
                    selected: _selected?.id == r.id || _routeTo?.id == r.id,
                    onTap: () => setState(() {
                      _selected = r;
                    }),
                  ),
                ),
              Marker(point: _me, width: 40, height: 40, child: const _MePin()),
            ]),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution('OpenStreetMap')],
            ),
          ],
        ),
      ),
      Positioned(
        top: 10,
        left: 12,
        right: 12,
        child: _RangeBar(
          selected: _range,
          onSelect: (v) {
            setState(() => _range = v);
            _recenter();
          },
        ),
      ),
      Positioned(
        right: 12,
        bottom: _selected != null || _route != null ? 250 : 156,
        child: FloatingActionButton.small(
          heroTag: 'map-recenter',
          tooltip: 'Centrar en mi ubicación',
          backgroundColor: colors.surface,
          foregroundColor: colors.primary,
          onPressed: _recenter,
          child: const Icon(Icons.my_location_rounded),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: _route != null && _routeTo != null
            ? _RouteCard(
                restaurant: _routeTo!,
                route: _route!,
                onClose: () => setState(() {
                  _route = null;
                  _routeTo = null;
                }),
                onOpen: () => _openRestaurant(_routeTo!),
              )
            : _selected != null
                ? _SelectedCard(
                    restaurant: _selected!,
                    meters: LocationService.meters(_me, LatLng(_selected!.latitude!, _selected!.longitude!)),
                    routing: _routing,
                    occupancyColor: occupancyColor(_selected!.occupancy),
                    onClose: () => setState(() => _selected = null),
                    onRoute: () => _showRoute(_selected!),
                    onMenu: () => _openRestaurant(_selected!),
                  )
                : _HintCard(
                    count: visible.length,
                    farAway: farAway,
                    range: _range,
                    onShowAll: () {
                      setState(() => _range = null);
                      _recenter();
                    },
                    onZones: () => setState(() => _phase = _Phase.choosing),
                    onAccept: _acceptArea,
                  ),
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.place, required this.onBack, this.onZones});

  final String place;
  final VoidCallback onBack;
  final VoidCallback? onZones;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
      child: Row(children: [
        IconButton.filledTonal(tooltip: 'Volver', onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mapa de restaurantes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
            Row(children: [
              Icon(Icons.location_on_outlined, size: 15, color: colors.primary),
              const SizedBox(width: 3),
              Expanded(
                child: Text(place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
              ),
            ]),
          ]),
        ),
        if (onZones != null)
          FilledButton.tonalIcon(
            style: compactButtonStyle(context),
            onPressed: onZones,
            icon: const Icon(Icons.place_outlined, size: 18),
            label: const Text('Zonas'),
          ),
      ]),
    );
  }
}

class _Locating extends StatelessWidget {
  const _Locating({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: colors.primary,
            child: Icon(Icons.navigation_rounded, size: 34, color: colors.onPrimary),
          ),
          const SizedBox(height: 16),
          Text('Buscando tu ubicación',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 6),
          Text('Permite el acceso a la ubicación para ver los restaurantes cerca de ti.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          TextButton(onPressed: onSkip, child: const Text('Elegir zona sin GPS')),
        ]),
      ),
    );
  }
}

class _ZonePicker extends StatelessWidget {
  const _ZonePicker({required this.notice, required this.selected, required this.onUseGps, required this.onZone});

  final String? notice;
  final String selected;
  final VoidCallback onUseGps;
  final ValueChanged<CommercialZone> onZone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.place_outlined, size: 20, color: colors.primary),
            const SizedBox(width: 6),
            Text('Zonas comerciales',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ]),
          const SizedBox(height: 6),
          Text(notice ?? 'Cambia tu ubicación eligiendo una zona o usa el GPS del teléfono.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onUseGps,
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Usar mi ubicación'),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      const SocialLabel('Ciudad'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (city, enabled) in supportedCities)
          SocialBadge(
            label: enabled ? city : '$city · Próximamente',
            background: enabled ? colors.primary : colors.surfaceContainerHighest,
            foreground: enabled ? colors.onPrimary : colors.onSurfaceVariant,
          ),
      ]),
      const SizedBox(height: 16),
      const SocialLabel('Zonas de Quito'),
      const SizedBox(height: 8),
      for (final z in quitoZones) ...[
        _ZoneTile(zone: z, selected: z.name == selected, onTap: () => onZone(z)),
        const SizedBox(height: 8),
      ],
    ]);
  }
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile({required this.zone, required this.selected, required this.onTap});

  final CommercialZone zone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? colors.primary : colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? colors.primary : colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.place_rounded, size: 18, color: selected ? colors.onPrimary : colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(zone.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
                Text(zone.description,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.selected, required this.onSelect});

  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.radar_rounded, size: 18, color: colors.primary),
        ),
        for (final (label, value) in _ranges)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: selected == value,
                label: 'Radio $label',
                child: Material(
                  color: selected == value ? colors.primary : colors.surface.withValues(alpha: 0),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onSelect(value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: selected == value ? colors.onPrimary : colors.onSurfaceVariant,
                          )),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _MePin extends StatelessWidget {
  const _MePin();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Semantics(
      label: 'Tu ubicación',
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: colors.primary.withValues(alpha: 0.25)),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary,
            border: Border.all(color: colors.surface, width: 3),
          ),
        ),
      ]),
    );
  }
}

class _RestaurantPin extends StatelessWidget {
  const _RestaurantPin({required this.name, required this.occupancyColor, required this.selected, required this.onTap});

  final String name;
  final Color occupancyColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final bg = selected ? colors.primary : colors.surface;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.primary, width: 2),
              boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.restaurant_rounded, size: 14, color: selected ? fg : colors.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: fg)),
              ),
              const SizedBox(width: 5),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: occupancyColor),
              ),
            ]),
          ),
          Icon(Icons.arrow_drop_down_rounded, size: 18, color: colors.primary),
        ]),
      ),
    );
  }
}

BoxDecoration _floatingCard(BuildContext context) {
  final colors = context.colorScheme;
  return BoxDecoration(
    color: colors.surface,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
    boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6))],
  );
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.count,
    required this.farAway,
    required this.range,
    required this.onShowAll,
    required this.onZones,
    required this.onAccept,
  });

  final int count;
  final bool farAway;
  final int? range;
  final VoidCallback onShowAll;
  final VoidCallback onZones;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final (String text, String? action, VoidCallback? onAction) = farAway
        ? ('Estás lejos de los locales de Bocadoo. Elige una zona de Quito.', 'Elegir zona', onZones)
        : count == 0
            ? ('No hay locales en este radio.', 'Ver todos', onShowAll)
            : (count == 1 ? '1 local en este radio.' : '$count locales en este radio.', null, null);
    final acceptLabel = range == null
        ? 'Aceptar (todos los locales)'
        : 'Aceptar (${_distance(range!)})';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: _floatingCard(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.touch_app_outlined, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurface)),
            ),
            if (action != null)
              FilledButton.tonal(style: compactButtonStyle(context), onPressed: onAction, child: Text(action)),
          ]),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: onAccept,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(acceptLabel),
          ),
        ],
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({
    required this.restaurant,
    required this.meters,
    required this.routing,
    required this.occupancyColor,
    required this.onClose,
    required this.onRoute,
    required this.onMenu,
  });

  final Restaurant restaurant;
  final int meters;
  final bool routing;
  final Color occupancyColor;
  final VoidCallback onClose;
  final VoidCallback onRoute;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final minutes = LocationService.walkingMinutes(meters);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      decoration: _floatingCard(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Restaurante seleccionado',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
          ),
          IconButton(tooltip: 'Cerrar', onPressed: onClose, icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant)),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(restaurant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.directions_walk_rounded, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('A ${_distance(meters)} · $minutes min a pie',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(children: [
                Icon(Icons.restaurant_menu_rounded, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(restaurant.featuredDish,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
                ),
                const SizedBox(width: 6),
                SocialBadge(
                  label: _occupancy(restaurant.occupancy),
                  background: occupancyColor.withValues(alpha: 0.15),
                  foreground: occupancyColor,
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: routing ? null : onRoute,
                  icon: routing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.route_rounded, size: 18),
                  label: const Text('Ver ruta'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onMenu,
                  icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                  label: const Text('Ver menú'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.restaurant, required this.route, required this.onClose, required this.onOpen});

  final Restaurant restaurant;
  final WalkingRoute route;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _floatingCard(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colors.primary,
            child: Icon(Icons.directions_walk_rounded, size: 20, color: colors.onPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ruta hacia ${restaurant.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
              Text('${route.minutes} min a pie · ${_distance(route.meters)}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.primary)),
            ]),
          ),
        ]),
        if (route.approximate) ...[
          const SizedBox(height: 6),
          Text('Ruta aproximada en línea recta: no pudimos consultar las calles ahora.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.tonal(onPressed: onClose, child: const Text('Quitar ruta'))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(onPressed: onOpen, child: const Text('Ver ficha y pedir'))),
        ]),
      ]),
    );
  }
}
