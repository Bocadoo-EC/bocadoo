import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';
import 'google_sign_in_flow.dart';

// D7: mismas zonas que DINER_ZONES en store.tsx
const _ownerZones = [
  'Frente a la PUCE',
  'La Floresta',
  'La Mariscal',
  'Centro Histórico',
  'Cumbayá',
  'UDLA Granados',
  'EPN / Salesiana',
];

const _zoneCoords = <String, LatLng>{
  'Frente a la PUCE': LatLng(-0.2105, -78.5020),
  'La Floresta': LatLng(-0.2061, -78.4820),
  'La Mariscal': LatLng(-0.2027, -78.4910),
  'Centro Histórico': LatLng(-0.2200, -78.5120),
  'Cumbayá': LatLng(-0.1920, -78.4320),
  'UDLA Granados': LatLng(-0.1890, -78.4680),
  'EPN / Salesiana': LatLng(-0.2130, -78.4950),
};

class RegisterOwnerScreen extends ConsumerStatefulWidget {
  const RegisterOwnerScreen({super.key});

  @override
  ConsumerState<RegisterOwnerScreen> createState() =>
      _RegisterOwnerScreenState();
}

class _RegisterOwnerScreenState extends ConsumerState<RegisterOwnerScreen> {
  final _restaurantCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _rucCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '3.50');
  final _tablesCtrl = TextEditingController();
  final _seatsCtrl = TextEditingController();
  final _takeawaySurchargeCtrl = TextEditingController(text: '0.25');
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _mapController = MapController();
  String _zone = _ownerZones[0]; // Frente a la PUCE por defecto
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _terms = true;
  bool _loading = false;
  final _errors = <String, String?>{};

  @override
  void dispose() {
    _restaurantCtrl.dispose();
    _ownerNameCtrl.dispose();
    _rucCtrl.dispose();
    _emailCtrl.dispose();
    _whatsappCtrl.dispose();
    _searchCtrl.dispose();
    _priceCtrl.dispose();
    _tablesCtrl.dispose();
    _seatsCtrl.dispose();
    _takeawaySurchargeCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// "Mi GPS": centra el mapa en la ubicación del teléfono.
  Future<void> _useGps() async {
    final messenger = ScaffoldMessenger.of(context);
    final (outcome, position) = await LocationService.current();
    if (!mounted) return;
    if (outcome == LocationOutcome.granted && position != null) {
      _mapController.move(position, 16.0);
      messenger.showSnackBar(const SnackBar(content: Text('Mapa centrado en tu ubicación')));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('No pudimos obtener tu ubicación. Elige tu zona.')));
    }
  }

  void _selectZone(String z) {
    setState(() => _zone = z);
    final coord = _zoneCoords[z];
    if (coord != null) {
      _mapController.move(coord, 14.0);
    }
  }

  bool _validate() {
    final errs = <String, String?>{};
    if (_restaurantCtrl.text.trim().isEmpty) {
      errs['restaurant'] = 'Ingresa el nombre de tu restaurante o comedor.';
    }
    if (_ownerNameCtrl.text.trim().isEmpty) {
      errs['owner'] = 'Ingresa el nombre del propietario o administrador.';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailCtrl.text.trim())) {
      errs['email'] = 'Ingresa un correo de contacto válido.';
    }
    if (_whatsappCtrl.text.trim().length < 9) {
      errs['whatsapp'] = 'Ingresa el WhatsApp del restaurante (ej: 0987654321).';
    }
    if (_passCtrl.text.length < 10) {
      errs['pass'] = 'La contraseña debe tener mínimo 10 caracteres.';
    } else if (_passCtrl.text != _confirmCtrl.text) {
      errs['confirm'] = 'Las contraseñas no coinciden.';
    }
    if (!_terms) {
      errs['terms'] = 'Debes aceptar las condiciones de restaurante afiliado.';
    }
    setState(() {
      _errors.clear();
      _errors.addAll(errs);
    });
    return errs.isEmpty;
  }

  Future<void> _register() async {
    if (!_validate()) return;
    setState(() => _loading = true);
    LatLng center = _zoneCoords[_zone] ?? const LatLng(-0.2105, -78.5020);
    try {
      center = _mapController.camera.center;
    } catch (_) {}
    final normalizedPrice = _priceCtrl.text.trim().replaceAll(',', '.');
    final price = double.tryParse(normalizedPrice) ?? 3.50;
    final tablesCount = int.tryParse(_tablesCtrl.text.trim());
    final seats = int.tryParse(_seatsCtrl.text.trim());
    final normalizedSurcharge =
        _takeawaySurchargeCtrl.text.trim().replaceAll(',', '.');
    final parsedSurcharge = double.tryParse(normalizedSurcharge);
    final takeawaySurchargeCents =
        parsedSurcharge != null ? (parsedSurcharge * 100).round() : null;

    final result = await ref.read(authRepositoryProvider).registerOwner(
          restaurantName: _restaurantCtrl.text.trim(),
          ownerName: _ownerNameCtrl.text.trim(),
          ruc: _rucCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          whatsapp: _whatsappCtrl.text.trim(),
          address: _searchCtrl.text.trim(),
          lat: center.latitude,
          lng: center.longitude,
          zone: _zone,
          looseLunchPrice: price,
          tablesCount: tablesCount,
          seats: seats,
          takeawaySurchargeCents: takeawaySurchargeCents,
          password: _passCtrl.text,
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.ok && result.fieldErrors.isNotEmpty) {
        _applyServerFieldErrors(result.fieldErrors);
      }
    });
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? 'No pudimos registrar tu restaurante. Inténtalo de nuevo.',
          ),
        ),
      );
      return;
    }
    // D4: pasar precio a A7 para calcular planes
    context.go('/auth/bienvenida/dueno', extra: price);
  }

  void _applyServerFieldErrors(Map<String, String> fieldErrors) {
    _errors.clear();
    for (final entry in fieldErrors.entries) {
      final key = entry.key.toLowerCase();
      final msg = entry.value;
      if (key.contains('cedularuc') || key.contains('ruc') || key.contains('cedula')) {
        _errors['ruc'] = msg;
      } else if (key.contains('telefono') || key.contains('whatsapp')) {
        _errors['whatsapp'] = msg;
      } else if (key.contains('correo') || key.contains('email')) {
        _errors['email'] = msg;
      } else if (key.contains('password')) {
        _errors['pass'] = msg;
      } else if (key.contains('restaurante.nombre')) {
        _errors['restaurant'] = msg;
      } else if (key.contains('nombre')) {
        _errors['owner'] = msg;
      } else if (key.contains('direccion')) {
        _errors['address'] = msg;
      } else if (key.contains('mesas')) {
        _errors['mesas'] = msg;
      } else if (key.contains('puestos') || key.contains('sillas')) {
        _errors['puestos'] = msg;
      } else if (key.contains('recargoparallevar') || key.contains('recargo')) {
        _errors['takeaway'] = msg;
      } else if (key.contains('preciosuelto') || key.contains('precio')) {
        _errors['price'] = msg;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final center = _zoneCoords[_zone] ?? const LatLng(-0.2105, -78.5020);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                  onPressed: () => context.pop(),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Text(
                    'Paso 1 de 2 · Restaurante',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSecondaryContainer),
                  ),
                ),
              ]),

              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.store_mall_directory_outlined, size: 15, color: cs.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    'Registro de negocio afiliado',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              Text(
                'Registra tu Restaurante',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Cobra por adelantado, fideliza comensales y valida con QR sin papel ni enredos.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),

              const SizedBox(height: 24),

              _Label('NOMBRE DEL RESTAURANTE / LOCAL'),
              const SizedBox(height: 8),
              TextField(
                controller: _restaurantCtrl,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.store_mall_directory_outlined, color: cs.onSurfaceVariant),
                  hintText: 'Ej. La Cuchara de San Blas',
                  errorText: _errors['restaurant'],
                ),
              ),

              const SizedBox(height: 16),

              _Label('NOMBRE DEL DUEÑO O ADMINISTRADOR'),
              const SizedBox(height: 8),
              TextField(
                controller: _ownerNameCtrl,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.person_outline_rounded, color: cs.onSurfaceVariant),
                  hintText: 'Ej. María Toapanta',
                  errorText: _errors['owner'],
                ),
              ),

              const SizedBox(height: 16),

              _Label('RUC O CÉDULA (ECUADOR)'),
              const SizedBox(height: 8),
              TextField(
                controller: _rucCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.badge_outlined, color: cs.onSurfaceVariant),
                  hintText: '1792345678001',
                  errorText: _errors['ruc'],
                ),
              ),

              const SizedBox(height: 16),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Label('CORREO COMERCIAL'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
                        hintText: 'contacto@local.ec',
                        errorText: _errors['email'],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Label('WHATSAPP LOCAL'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _whatsappCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.phone_outlined, color: cs.onSurfaceVariant),
                        hintText: '098 765 4321',
                        errorText: _errors['whatsapp'],
                      ),
                    ),
                  ]),
                ),
              ]),

              const SizedBox(height: 16),

              Row(children: [
                Text(
                  'UBICACIÓN DE TU RESTAURANTE EN QUITO',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  'Google Maps',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary),
                ),
              ]),
              const SizedBox(height: 8),

              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                      hintText: 'Buscar dirección en Quito (ej. Av. 12 de...)',
                      errorText: _errors['address'],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _useGps,
                  icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                  label: const Text('Mi GPS'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(100, 56)),
                ),
              ]),

              const SizedBox(height: 8),

              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                child: SizedBox(
                  height: 200,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 13.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'ec.bocadoo.app',
                      ),
                      MarkerLayer(
                        markers: _zoneCoords.entries.map((e) {
                          final selected = e.key == _zone;
                          return Marker(
                            point: e.value,
                            width: 110,
                            height: 36,
                            child: GestureDetector(
                              onTap: () => _selectZone(e.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: selected ? cs.primary : cs.surface,
                                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                                  border: Border.all(color: cs.primary),
                                ),
                                child: Text(
                                  e.key,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: selected ? cs.onPrimary : cs.primary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Row(children: [
                Icon(Icons.location_on_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 4),
                Text(_zone, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary)),
                Text('  ·  21 restaurantes', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),

              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ownerZones.map((z) {
                  final sel = z == _zone;
                  return GestureDetector(
                    onTap: () => _selectZone(z),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? cs.primary : cs.surface,
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                        border: Border.all(color: sel ? cs.primary : cs.outlineVariant),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.location_on_rounded, size: 13,
                            color: sel ? cs.onPrimary : cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          z,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel ? cs.onPrimary : cs.onSurface,
                          ),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Label('ALMUERZO EJECUTIVO (\$)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        hintText: '3.50',
                        errorText: _errors['price'],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Label('RECARGO LLEVAR (\$)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _takeawaySurchargeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        hintText: '0.25',
                        errorText: _errors['takeaway'],
                      ),
                    ),
                  ]),
                ),
              ]),

              const SizedBox(height: 16),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Label('MESAS (OPCIONAL)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tablesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.table_restaurant_outlined, color: cs.onSurfaceVariant),
                        hintText: 'Ej. 10',
                        errorText: _errors['mesas'],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Label('SILLAS / PUESTOS (OPCIONAL)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _seatsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.chair_alt_outlined, color: cs.onSurfaceVariant),
                        hintText: 'Ej. 40',
                        errorText: _errors['puestos'],
                      ),
                    ),
                  ]),
                ),
              ]),

              const SizedBox(height: 16),

              _Label('CONTRASEÑA DE ADMINISTRADOR'),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
                  hintText: 'Mínimo 10 caracteres',
                  errorText: _errors['pass'],
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _Label('CONFIRMAR CONTRASEÑA'),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
                  hintText: 'Repite la contraseña',
                  errorText: _errors['confirm'],
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Checkbox(
                  value: _terms,
                  onChanged: (v) => setState(() => _terms = v ?? false),
                  activeColor: cs.primary,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                        text: 'Acepto el acuerdo comercial para restaurantes aliados de ',
                        style: TextStyle(fontSize: 13, color: cs.onSurface),
                      ),
                      TextSpan(
                        text: 'Bocadoo Ecuador.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary),
                      ),
                    ])),
                  ),
                ),
              ]),

              if (_errors['terms'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_errors['terms']!, style: TextStyle(fontSize: 12, color: cs.error)),
                ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _loading ? null : _register,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.rocket_launch_rounded, size: 20),
                    ),
                  Text(_loading ? 'Registrando restaurante...' : 'Dar de alta y ver Onboarding'),
                ]),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () => continueWithGoogle(context, role: 'owner'),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Registrar con Google Workspace'),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.onSurfaceVariant),
    );
  }
}
