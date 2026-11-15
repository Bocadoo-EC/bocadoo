import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/location_picker_map.dart';
import 'google_sign_in_flow.dart';

// D7: zonas exactas de store.tsx (DINER_ZONES)
const _dimerZones = [
  'Frente a la PUCE',
  'La Floresta',
  'La Mariscal',
  'Centro Histórico',
  'Cumbayá',
  'UDLA Granados',
  'EPN / Salesiana',
];

/// Centro de cada zona, para ubicar el pin al elegirla.
const _zoneCoords = <String, LatLng>{
  'Frente a la PUCE': LatLng(-0.2105, -78.5020),
  'La Floresta': LatLng(-0.2061, -78.4820),
  'La Mariscal': LatLng(-0.2027, -78.4910),
  'Centro Histórico': LatLng(-0.2200, -78.5120),
  'Cumbayá': LatLng(-0.1920, -78.4320),
  'UDLA Granados': LatLng(-0.1890, -78.4680),
  'EPN / Salesiana': LatLng(-0.2130, -78.4950),
};

enum _PassStrength { none, weak, medium, strong }

class RegisterDinerScreen extends StatefulWidget {
  const RegisterDinerScreen({super.key});

  @override
  State<RegisterDinerScreen> createState() => _RegisterDinerScreenState();
}

class _RegisterDinerScreenState extends State<RegisterDinerScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String _zone = _dimerZones[1]; // La Floresta por defecto (índice 1)
  LatLng _location = _zoneCoords[_dimerZones[1]]!;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _terms = true;
  bool _loading = false;
  final _errors = <String, String?>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  _PassStrength _strength(String pass) {
    if (pass.isEmpty) return _PassStrength.none;
    if (pass.length < 6) return _PassStrength.weak;
    if (pass.length < 9 || !RegExp(r'\d').hasMatch(pass)) return _PassStrength.medium;
    return _PassStrength.strong;
  }

  bool _validate() {
    final errs = <String, String?>{};
    if (_nameCtrl.text.trim().isEmpty) {
      errs['nombre'] = 'Por favor ingresa tu nombre y apellido.';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailCtrl.text.trim())) {
      errs['email'] = 'Por favor ingresa un correo electrónico válido.';
    }
    if (_phoneCtrl.text.trim().length < 9) {
      errs['phone'] = 'Ingresa un número celular ecuatoriano válido (ej: 0991234567).';
    }
    if (_passCtrl.text.length < 6) {
      errs['pass'] = 'La contraseña debe tener mínimo 6 caracteres.';
    } else if (_passCtrl.text != _confirmCtrl.text) {
      errs['confirm'] = 'Las contraseñas no coinciden.';
    }
    if (!_terms) {
      errs['terms'] = 'Debes aceptar los términos de Bocadoo para continuar.';
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
    // TODO: Conectar con provider de backend
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    setState(() => _loading = false);
    final nombre = _nameCtrl.text.trim().split(' ').first;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('¡Bienvenido $nombre! Elige tu restaurante para activar tu primer plan.'),
        duration: const Duration(seconds: 2),
      ));
      // D1: flujo A4 → A6 → C2
      // TODO: Conectar con provider de backend (guardar la ubicación fijada).
      context.go('/auth/bienvenida/comensal', extra: {
        'nombre': nombre,
        'zona': _zone,
        'lat': _location.latitude.toString(),
        'lng': _location.longitude.toString(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final bColors = context.bocadooColors;
    final strength = _strength(_passCtrl.text);

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
                    'Paso 1 de 2 · Comensal',
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
                  Icon(Icons.qr_code_2_rounded, size: 15, color: cs.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    'Tu cuenta para almorzar con QR',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              Text(
                'Crea tu cuenta de comensal',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Dile adiós a las cartulinas. Compra planes de almuerzo y valida con QR en Quito.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),

              const SizedBox(height: 24),

              _Label('NOMBRE COMPLETO'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.person_outline_rounded, color: cs.onSurfaceVariant),
                  hintText: 'Ej. Carlos Mejía',
                  errorText: _errors['nombre'],
                ),
              ),

              const SizedBox(height: 16),

              _Label('CORREO ELECTRÓNICO'),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
                  hintText: 'carlos@email.com',
                  errorText: _errors['email'],
                ),
              ),

              const SizedBox(height: 16),

              _Label('TELÉFONO MÓVIL (ECUADOR)'),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.phone_outlined, color: cs.onSurfaceVariant),
                  hintText: '099 123 4567',
                  errorText: _errors['phone'],
                ),
              ),

              const SizedBox(height: 16),

              _Label('SECTOR PREFERIDO DE ALMUERZO EN QUITO'),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dimerZones.map((z) {
                  final sel = z == _zone;
                  return GestureDetector(
                    onTap: () => setState(() => _zone = z),
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

              const SizedBox(height: 14),

              _Label('TU UBICACIÓN EXACTA'),
              const SizedBox(height: 8),
              LocationPickerMap(
                zones: _zoneCoords,
                selectedZone: _zone,
                onZoneSelected: (z) => setState(() => _zone = z),
                onLocationChanged: (p) => _location = p,
              ),

              const SizedBox(height: 16),

              _Label('CONTRASEÑA'),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
                  hintText: 'Crea una contraseña segura',
                  errorText: _errors['pass'],
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),

              if (_passCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                _PassStrengthBar(strength: strength, bColors: bColors),
              ],

              const SizedBox(height: 16),

              _Label('CONFIRMAR CONTRASEÑA'),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
                  hintText: 'Repite tu contraseña',
                  errorText: _errors['confirm'],
                  suffixIcon: _confirmCtrl.text.isNotEmpty && _confirmCtrl.text == _passCtrl.text
                      ? Icon(Icons.check_circle_rounded, color: bColors.success)
                      : IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                ),
                onChanged: (_) => setState(() {}),
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
                        text: 'Acepto los ',
                        style: TextStyle(fontSize: 13, color: cs.onSurface),
                      ),
                      TextSpan(
                        text: 'Términos de Bocadoo Ecuador',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary),
                      ),
                      TextSpan(
                        text: ' y la política de protección de datos personales.',
                        style: TextStyle(fontSize: 13, color: cs.onSurface),
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
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.store_mall_directory_rounded, size: 20, color: cs.onPrimary),
                    ),
                  Text(_loading ? 'Creando cuenta de comensal...' : 'Crear cuenta y elegir restaurante'),
                ]),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () => continueWithGoogle(context, role: 'customer'),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Registrarme con Google'),
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

class _PassStrengthBar extends StatelessWidget {
  final _PassStrength strength;
  final BocadooColors bColors;

  const _PassStrengthBar({required this.strength, required this.bColors});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final (label, color, segments) = switch (strength) {
      _PassStrength.weak => ('Débil', bColors.danger, 1),
      _PassStrength.medium => ('Media', cs.primary, 2),
      _PassStrength.strong => ('Segura', bColors.success, 3),
      _PassStrength.none => ('', cs.outlineVariant, 0),
    };
    return Row(children: [
      ...List.generate(3, (i) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
              decoration: BoxDecoration(
                color: i < segments ? color : cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )),
      const SizedBox(width: 8),
      Text(
        'Seguridad: $label',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: segments > 0 ? color : cs.onSurfaceVariant,
        ),
      ),
    ]);
  }
}
