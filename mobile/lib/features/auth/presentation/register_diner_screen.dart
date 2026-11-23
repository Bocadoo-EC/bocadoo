import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';
import 'google_sign_in_flow.dart';
import 'widgets/diner_location_picker.dart';

enum _PassStrength { none, weak, medium, strong }

class RegisterDinerScreen extends ConsumerStatefulWidget {
  const RegisterDinerScreen({super.key});

  @override
  ConsumerState<RegisterDinerScreen> createState() =>
      _RegisterDinerScreenState();
}

class _RegisterDinerScreenState extends ConsumerState<RegisterDinerScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String _zone = 'Quito';
  LatLng _location = LocationService.fallbackPuce;
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
    if (pass.length < 10) return _PassStrength.weak;
    if (pass.length < 12 || !RegExp(r'\d').hasMatch(pass)) {
      return _PassStrength.medium;
    }
    return _PassStrength.strong;
  }

  static final _nameRegex = RegExp(r'^[a-zA-ZáéíóúüñÁÉÍÓÚÜÑ\s]+$');
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phoneRegex = RegExp(r'^\d{9,10}$');

  String? _nameError(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Por favor ingresa tu nombre y apellido.';
    if (!_nameRegex.hasMatch(v) || v.replaceAll(RegExp(r'\s+'), '').length < 2) {
      return 'Ingresa tu nombre usando solo letras.';
    }
    return null;
  }

  String? _emailError(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Ingresa tu correo electrónico.';
    if (!v.contains('@')) {
      return 'El correo electrónico debe incluir @ (ej: carlos@email.com).';
    }
    if (!_emailRegex.hasMatch(v)) {
      return 'Por favor ingresa un correo electrónico válido.';
    }
    return null;
  }

  String? _phoneError(String raw) {
    final v = raw.trim();
    if (!_phoneRegex.hasMatch(v)) {
      return 'Ingresa un número móvil válido de 9 a 10 dígitos (ej: 0991234567).';
    }
    return null;
  }

  void _validateSingleField(String key) {
    final next = switch (key) {
      'nombre' => _nameError(_nameCtrl.text),
      'email' => _emailError(_emailCtrl.text),
      'phone' => _phoneError(_phoneCtrl.text),
      _ => null,
    };
    setState(() => _errors[key] = next);
  }

  void _onFieldChanged(String key) {
    if (_errors.containsKey(key) && _errors[key] != null) {
      _validateSingleField(key);
    } else {
      setState(() {});
    }
  }

  bool _validate() {
    final errs = <String, String?>{};
    final nameErr = _nameError(_nameCtrl.text);
    if (nameErr != null) errs['nombre'] = nameErr;
    final emailErr = _emailError(_emailCtrl.text);
    if (emailErr != null) errs['email'] = emailErr;
    final phoneErr = _phoneError(_phoneCtrl.text);
    if (phoneErr != null) errs['phone'] = phoneErr;
    if (_passCtrl.text.length < 10) {
      errs['pass'] = 'La contraseña debe tener mínimo 10 caracteres.';
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
    final result = await ref.read(authRepositoryProvider).registerDiner(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          phone: _phoneCtrl.text.trim(),
          zone: _zone,
          lat: _location.latitude,
          lng: _location.longitude,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? 'No pudimos crear tu cuenta. Inténtalo de nuevo.',
          ),
        ),
      );
      return;
    }
    final nombre = _nameCtrl.text.trim().split(' ').first;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('¡Bienvenido $nombre! Elige tu restaurante para activar tu primer plan.'),
      duration: const Duration(seconds: 2),
    ));
    context.go('/auth/bienvenida/comensal', extra: {
      'nombre': nombre,
      'zona': _zone,
      'lat': _location.latitude.toString(),
      'lng': _location.longitude.toString(),
    });
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
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus && _nameCtrl.text.isNotEmpty) {
                    _validateSingleField('nombre');
                  }
                },
                child: TextField(
                  controller: _nameCtrl,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-ZáéíóúüñÁÉÍÓÚÜÑ\s]'),
                    ),
                  ],
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.person_outline_rounded, color: cs.onSurfaceVariant),
                    hintText: 'Ej. Carlos Mejía',
                    errorText: _errors['nombre'],
                    suffixIcon: _nameCtrl.text.trim().isNotEmpty &&
                            _nameError(_nameCtrl.text) == null
                        ? Icon(Icons.check_circle_rounded, color: bColors.success)
                        : null,
                  ),
                  onChanged: (_) => _onFieldChanged('nombre'),
                ),
              ),

              const SizedBox(height: 16),

              _Label('CORREO ELECTRÓNICO'),
              const SizedBox(height: 8),
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus && _emailCtrl.text.isNotEmpty) {
                    _validateSingleField('email');
                  }
                },
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.email],
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
                    hintText: 'carlos@email.com',
                    errorText: _errors['email'],
                    suffixIcon: _emailCtrl.text.trim().isNotEmpty &&
                            _emailError(_emailCtrl.text) == null
                        ? Icon(Icons.check_circle_rounded, color: bColors.success)
                        : null,
                  ),
                  onChanged: (_) => _onFieldChanged('email'),
                ),
              ),

              const SizedBox(height: 16),

              _Label('TELÉFONO MÓVIL (ECUADOR)'),
              const SizedBox(height: 8),
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus && _phoneCtrl.text.isNotEmpty) {
                    _validateSingleField('phone');
                  }
                },
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.phone_outlined, color: cs.onSurfaceVariant),
                    hintText: '0991234567',
                    errorText: _errors['phone'],
                    suffixIcon: _phoneCtrl.text.trim().isNotEmpty &&
                            _phoneError(_phoneCtrl.text) == null
                        ? Icon(Icons.check_circle_rounded, color: bColors.success)
                        : null,
                  ),
                  onChanged: (_) => _onFieldChanged('phone'),
                ),
              ),

              const SizedBox(height: 16),

              _Label('TU UBICACIÓN PARA ALMORZAR'),
              const SizedBox(height: 8),
              DinerLocationPicker(
                initialLocation: _location,
                onLocationResolved: (point, zoneLabel) {
                  setState(() {
                    _location = point;
                    _zone = zoneLabel;
                  });
                },
              ),

              const SizedBox(height: 16),

              _Label('CONTRASEÑA'),
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
