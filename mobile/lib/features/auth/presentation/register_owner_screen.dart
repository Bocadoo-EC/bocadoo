import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ec_validators.dart';
import '../../../core/widgets/owner_location_picker.dart';
import '../data/auth_repository.dart';
import 'google_sign_in_flow.dart';

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
  final _priceCtrl = TextEditingController();
  final _tablesCtrl = TextEditingController();
  final _seatsCtrl = TextEditingController();
  final _takeawaySurchargeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _restaurantFocus = FocusNode();
  final _ownerFocus = FocusNode();
  final _rucFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _whatsappFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _surchargeFocus = FocusNode();
  final _tablesFocus = FocusNode();
  final _seatsFocus = FocusNode();
  final _passFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _emailFieldKey = GlobalKey();

  final _mapController = MapController();

  LatLng _mapCenter = LocationService.fallbackPuce;
  bool _locationConfirmed = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _terms = false;
  bool _loading = false;

  final _touched = <String>{};
  final _errors = <String, String?>{};
  String? _duplicateEmailValue;

  @override
  void initState() {
    super.initState();
    _attachBlurValidation(_restaurantFocus, 'restaurant');
    _attachBlurValidation(_ownerFocus, 'owner');
    _attachBlurValidation(_rucFocus, 'ruc');
    _attachBlurValidation(_emailFocus, 'email');
    _attachBlurValidation(_whatsappFocus, 'whatsapp');
    _attachBlurValidation(_priceFocus, 'price');
    _attachBlurValidation(_surchargeFocus, 'takeaway');
    _attachBlurValidation(_tablesFocus, 'mesas');
    _attachBlurValidation(_seatsFocus, 'puestos');
    _attachBlurValidation(_passFocus, 'pass');
    _attachBlurValidation(_confirmFocus, 'confirm');
  }

  void _attachBlurValidation(FocusNode node, String key) {
    node.addListener(() {
      if (!node.hasFocus && mounted) {
        _touched.add(key);
        setState(() {
          _errors[key] = _validateField(key);
        });
      }
    });
  }

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

    _restaurantFocus.dispose();
    _ownerFocus.dispose();
    _rucFocus.dispose();
    _emailFocus.dispose();
    _whatsappFocus.dispose();
    _priceFocus.dispose();
    _surchargeFocus.dispose();
    _tablesFocus.dispose();
    _seatsFocus.dispose();
    _passFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Validadores
  // ---------------------------------------------------------------------------

  bool get _passHasMinLength => _passCtrl.text.length >= 10;
  bool get _passHasUpper => RegExp(r'[A-ZÁÉÍÓÚÜÑ]').hasMatch(_passCtrl.text);
  bool get _passHasDigit => RegExp(r'\d').hasMatch(_passCtrl.text);
  bool get _passHasSymbol => RegExp(
        r'[!@#\$%&*._\-]|[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9\s]',
      ).hasMatch(_passCtrl.text);

  String? _validatePass(String raw) {
    if (raw.isEmpty) return 'Este campo es obligatorio.';
    if (!_passHasMinLength ||
        !_passHasUpper ||
        !_passHasDigit ||
        !_passHasSymbol) {
      return 'La contraseña debe cumplir todos los requisitos.';
    }
    return null;
  }

  String? _validateConfirm(String raw) {
    if (raw.isEmpty) return 'Este campo es obligatorio.';
    if (raw != _passCtrl.text) return 'Las contraseñas no coinciden.';
    return null;
  }

  String? _validateField(String key) => switch (key) {
        'restaurant' =>
          EcValidators.validateRestaurantName(_restaurantCtrl.text),
        'owner' => EcValidators.validatePersonName(_ownerNameCtrl.text),
        'ruc' => EcValidators.validateCedulaRuc(_rucCtrl.text),
        'email' => EcValidators.validateEmail(
            _emailCtrl.text,
            duplicateEmailValue: _duplicateEmailValue,
          ),
        'whatsapp' =>
          EcValidators.validateEcuadorCellPhone(_whatsappCtrl.text),
        'price' => EcValidators.validateLunchPrice(_priceCtrl.text),
        'takeaway' => EcValidators.validateTakeawaySurcharge(
            _takeawaySurchargeCtrl.text,
          ),
        'mesas' => EcValidators.validateOptionalPositiveInt(_tablesCtrl.text),
        'puestos' => EcValidators.validateOptionalPositiveInt(_seatsCtrl.text),
        'pass' => _validatePass(_passCtrl.text),
        'confirm' => _validateConfirm(_confirmCtrl.text),
        _ => null,
      };

  bool _isFieldValidVisual(String key, String raw) =>
      raw.trim().isNotEmpty && _validateField(key) == null;

  InputDecoration _fieldDecoration({
    required String key,
    required String rawValue,
    required String hintText,
    IconData? prefixIcon,
    String? prefixText,
    Widget? suffixIcon,
    int errorMaxLines = 3,
  }) {
    final cs = context.colorScheme;
    final b = context.bocadooColors;
    final error = _errors[key];
    final valid = error == null && _isFieldValidVisual(key, rawValue);
    final validEnabledBorder = valid
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            borderSide: BorderSide(color: b.success, width: 1.5),
          )
        : null;
    final validFocusedBorder = valid
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            borderSide: BorderSide(color: b.success, width: 2),
          )
        : null;

    return InputDecoration(
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: valid ? b.success : cs.onSurfaceVariant)
          : null,
      prefixText: prefixText,
      hintText: hintText,
      error: error == null
          ? null
          : Text(
              error,
              softWrap: true,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.error,
              ),
            ),
      errorMaxLines: errorMaxLines,
      enabledBorder: validEnabledBorder,
      focusedBorder: validFocusedBorder,
      suffixIcon: suffixIcon ??
          (valid
              ? Icon(Icons.check_circle_rounded, color: b.success, size: 20)
              : null),
    );
  }

  void _onFieldChanged(String key) {
    setState(() {
      if (key == 'email' &&
          _duplicateEmailValue != null &&
          _emailCtrl.text.trim().toLowerCase() != _duplicateEmailValue) {
        _duplicateEmailValue = null;
        _errors['email'] = _validateField('email');
      } else if (_touched.contains(key) || _errors[key] != null) {
        _errors[key] = _validateField(key);
      }
      if (key == 'pass' &&
          (_touched.contains('confirm') || _errors['confirm'] != null)) {
        _errors['confirm'] = _validateConfirm(_confirmCtrl.text);
      }
    });
  }

  bool get _isFormValid =>
      _terms &&
      _locationConfirmed &&
      EcValidators.validateRestaurantName(_restaurantCtrl.text) == null &&
      EcValidators.validatePersonName(_ownerNameCtrl.text) == null &&
      EcValidators.validateCedulaRuc(_rucCtrl.text) == null &&
      EcValidators.validateEmail(
            _emailCtrl.text,
            duplicateEmailValue: _duplicateEmailValue,
          ) ==
          null &&
      EcValidators.validateEcuadorCellPhone(_whatsappCtrl.text) == null &&
      EcValidators.validateLunchPrice(_priceCtrl.text) == null &&
      EcValidators.validateTakeawaySurcharge(_takeawaySurchargeCtrl.text) ==
          null &&
      EcValidators.validateOptionalPositiveInt(_tablesCtrl.text) == null &&
      EcValidators.validateOptionalPositiveInt(_seatsCtrl.text) == null &&
      _validatePass(_passCtrl.text) == null &&
      _validateConfirm(_confirmCtrl.text) == null;

  bool _validateAll() {
    const keys = [
      'restaurant',
      'owner',
      'ruc',
      'email',
      'whatsapp',
      'price',
      'takeaway',
      'mesas',
      'puestos',
      'pass',
      'confirm',
    ];
    final errs = <String, String?>{};
    for (final k in keys) {
      final e = _validateField(k);
      if (e != null) errs[k] = e;
    }
    if (!_terms) {
      errs['terms'] =
          'Debes aceptar el acuerdo comercial para restaurantes aliados.';
    }
    setState(() {
      _touched.addAll(keys);
      _errors
        ..clear()
        ..addAll(errs);
    });
    return errs.isEmpty && _locationConfirmed;
  }

  // ---------------------------------------------------------------------------
  // Envío de registro
  // ---------------------------------------------------------------------------

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!_validateAll()) return;
    setState(() => _loading = true);

    var center = _mapCenter;
    try {
      center = _mapController.camera.center;
    } catch (_) {}

    // Garantiza una dirección textual no vacía para completar `perfilCompleto`.
    var resolvedAddress = _searchCtrl.text.trim();
    if (resolvedAddress.isEmpty) {
      resolvedAddress = await OwnerGeocoder.reverseGeocode(center);
      if (!mounted) return;
      _searchCtrl.text = resolvedAddress;
    }

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
          whatsapp:
              _whatsappCtrl.text.replaceAll(RegExp(r'[\s\-()]'), '').trim(),
          address: resolvedAddress,
          lat: center.latitude,
          lng: center.longitude,
          looseLunchPrice: price,
          tablesCount: tablesCount,
          seats: seats,
          takeawaySurchargeCents: takeawaySurchargeCents,
          password: _passCtrl.text,
        );
    if (!mounted) return;
    var isDuplicateEmail = false;
    setState(() {
      _loading = false;
      if (!result.ok) {
        if (result.fieldErrors.isNotEmpty) {
          _applyServerFieldErrors(result.fieldErrors);
        }
        final codeUpper = (result.errorCode ?? '').toUpperCase();
        final errUpper = (result.errorMessage ?? '').toUpperCase();
        final combinedUpper = '$codeUpper $errUpper';
        isDuplicateEmail = codeUpper == 'CONFLICT' ||
            combinedUpper.contains('EMAIL_YA_EXISTE') ||
            combinedUpper.contains('CORREO_YA_EXISTE') ||
            combinedUpper.contains('CORREO_DUPLICADO') ||
            combinedUpper.contains('YA ESTÁ REGISTRADO') ||
            combinedUpper.contains('YA EXISTE UNA CUENTA CON ESE CORREO') ||
            ((combinedUpper.contains('EMAIL') ||
                    combinedUpper.contains('CORREO')) &&
                (combinedUpper.contains('EXISTE') ||
                    combinedUpper.contains('DUPLICAD') ||
                    combinedUpper.contains('CONFLICT') ||
                    combinedUpper.contains('REGISTRAD'))) ||
            _errors['email'] != null;
        if (isDuplicateEmail) {
          const dupMsg =
              'Este correo ya está registrado. Utiliza otro correo para crear tu cuenta.';
          _duplicateEmailValue = _emailCtrl.text.trim().toLowerCase();
          _errors['email'] = dupMsg;
        }
      }
    });
    if (!result.ok) {
      if (isDuplicateEmail) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final ctx = _emailFieldKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              alignment: 0.25,
            );
          }
          _emailFocus.requestFocus();
        });
        return;
      }
      final rawMsg = result.errorMessage ??
          'No pudimos completar el registro por un problema técnico. Por favor, inténtalo de nuevo.';
      final looksTechnical = EcValidators.isTechnicalErrorMessage(rawMsg);
      if (looksTechnical) {
        debugPrint('[RegisterOwner] error técnico ocultado: $rawMsg');
      }
      final friendlyMsg =
          (result.errorCode ?? '').toUpperCase() == 'REGISTRO_CERRADO'
              ? 'El registro de dueños está cerrado por ahora.'
              : (looksTechnical
                  ? 'No pudimos completar el registro por un problema técnico. Por favor, inténtalo de nuevo.'
                  : rawMsg);
      if ((result.errorCode ?? '').toUpperCase() == 'REGISTRO_CERRADO') {
        setState(() {});
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyMsg)),
      );
      return;
    }
    // D4: pasar precio a A7 para calcular planes
    context.go('/auth/bienvenida/dueno', extra: price);
  }

  void _applyServerFieldErrors(Map<String, String> fieldErrors) {
    for (final entry in fieldErrors.entries) {
      final key = entry.key.toLowerCase();
      final msg = entry.value;
      if (key.contains('cedularuc') ||
          key.contains('ruc') ||
          key.contains('cedula')) {
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
    final b = context.bocadooColors;

    return ValueListenableBuilder<bool>(
      valueListenable: ownerRegistrationClosedNotifier,
      builder: (context, registrationClosed, _) {
        if (registrationClosed) {
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                        onPressed: () => context.pop(),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 56,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'El registro de dueños está cerrado por ahora',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Solo cuentas autorizadas de Dueño o Cajero pueden ingresar desde Terminal Restaurante.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Volver a iniciar sesión'),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                    onPressed: () => context.pop(),
                  ),
                ),

                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.store_mall_directory_outlined,
                          size: 15,
                          color: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Registro de negocio afiliado',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'Registra tu Restaurante',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cobra por adelantado, fideliza comensales y valida con QR sin papel ni enredos.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),

                const SizedBox(height: 24),

                const _Label('NOMBRE DEL RESTAURANTE / LOCAL', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _restaurantCtrl,
                  focusNode: _restaurantFocus,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _onFieldChanged('restaurant'),
                  onEditingComplete: () => _ownerFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'restaurant',
                    rawValue: _restaurantCtrl.text,
                    prefixIcon: Icons.store_mall_directory_outlined,
                    hintText: 'Ej. La Cuchara de San Blas',
                  ),
                ),

                const SizedBox(height: 16),

                const _Label('NOMBRE DEL DUEÑO O ADMINISTRADOR', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _ownerNameCtrl,
                  focusNode: _ownerFocus,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _onFieldChanged('owner'),
                  onEditingComplete: () => _rucFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'owner',
                    rawValue: _ownerNameCtrl.text,
                    prefixIcon: Icons.person_outline_rounded,
                    hintText: 'Ej. María Toapanta',
                  ),
                ),

                const SizedBox(height: 16),

                const _Label('RUC O CÉDULA', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _rucCtrl,
                  focusNode: _rucFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(13),
                  ],
                  onChanged: (_) => _onFieldChanged('ruc'),
                  onEditingComplete: () => _emailFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'ruc',
                    rawValue: _rucCtrl.text,
                    prefixIcon: Icons.badge_outlined,
                    hintText: 'Ej. 1710034065001',
                  ),
                ),

                const SizedBox(height: 16),

                KeyedSubtree(
                  key: _emailFieldKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Label('CORREO COMERCIAL', required: true),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _onFieldChanged('email'),
                        onEditingComplete: () => _whatsappFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'email',
                          rawValue: _emailCtrl.text,
                          prefixIcon: Icons.email_outlined,
                          hintText: 'contacto@local.ec',
                          errorMaxLines: 3,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                const _Label('NÚMERO DE CELULAR', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _whatsappCtrl,
                  focusNode: _whatsappFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) => _onFieldChanged('whatsapp'),
                  onEditingComplete: () => _priceFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'whatsapp',
                    rawValue: _whatsappCtrl.text,
                    prefixIcon: Icons.phone_outlined,
                    hintText: 'Ej. 0987654321',
                    errorMaxLines: 3,
                  ),
                ),

                const SizedBox(height: 20),

                const _Label('UBICACIÓN DE TU RESTAURANTE', required: true),
                const SizedBox(height: 8),

                OwnerLocationPicker(
                  addressController: _searchCtrl,
                  mapController: _mapController,
                  center: _mapCenter,
                  locationConfirmed: _locationConfirmed,
                  errorText: _errors['address'],
                  onAddressChanged: (_) {
                    if (_errors['address'] != null) {
                      setState(() => _errors.remove('address'));
                    }
                  },
                  onLocationChanged: (point, {required bool confirmed}) {
                    final needsUpdate =
                        !_locationConfirmed && confirmed ||
                        point.latitude != _mapCenter.latitude ||
                        point.longitude != _mapCenter.longitude;
                    _mapCenter = point;
                    if (!_locationConfirmed && confirmed) {
                      setState(() => _locationConfirmed = true);
                    } else if (needsUpdate && mounted) {
                      setState(() {});
                    }
                  },
                ),

                const SizedBox(height: 20),

                const Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _Label('ALMUERZO EJECUTIVO (\$)', required: true),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _Label('RECARGO LLEVAR (\$)', required: true),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        focusNode: _priceFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => _onFieldChanged('price'),
                        onEditingComplete: () => _surchargeFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'price',
                          rawValue: _priceCtrl.text,
                          prefixText: '\$ ',
                          hintText: 'Ej. 3.50',
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _takeawaySurchargeCtrl,
                        focusNode: _surchargeFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => _onFieldChanged('takeaway'),
                        onEditingComplete: () => _tablesFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'takeaway',
                          rawValue: _takeawaySurchargeCtrl.text,
                          prefixText: '\$ ',
                          hintText: 'Ej. 0.25',
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                const Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: _Label('MESAS (OPCIONAL)')),
                    SizedBox(width: 12),
                    Expanded(child: _Label('SILLAS (OPCIONAL)')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tablesCtrl,
                        focusNode: _tablesFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _onFieldChanged('mesas'),
                        onEditingComplete: () => _seatsFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'mesas',
                          rawValue: _tablesCtrl.text,
                          prefixIcon: Icons.table_restaurant_outlined,
                          hintText: 'Ej. 10',
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _seatsCtrl,
                        focusNode: _seatsFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _onFieldChanged('puestos'),
                        onEditingComplete: () => _passFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'puestos',
                          rawValue: _seatsCtrl.text,
                          prefixIcon: Icons.chair_alt_outlined,
                          hintText: 'Ej. 40',
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                const _Label('CONTRASEÑA DE ADMINISTRADOR', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _onFieldChanged('pass'),
                  onEditingComplete: () => _confirmFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'pass',
                    rawValue: _passCtrl.text,
                    prefixIcon: Icons.lock_outline_rounded,
                    hintText: 'Mínimo 10 caracteres',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _PasswordRuleChip(
                      label: 'Mín. 10 caracteres',
                      met: _passHasMinLength,
                      successColor: b.success,
                    ),
                    _PasswordRuleChip(
                      label: '1 mayúscula',
                      met: _passHasUpper,
                      successColor: b.success,
                    ),
                    _PasswordRuleChip(
                      label: '1 número',
                      met: _passHasDigit,
                      successColor: b.success,
                    ),
                    _PasswordRuleChip(
                      label: '1 símbolo (!@#\$%&*._-)',
                      met: _passHasSymbol,
                      successColor: b.success,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                const _Label('CONFIRMAR CONTRASEÑA', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmCtrl,
                  focusNode: _confirmFocus,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _onFieldChanged('confirm'),
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  decoration: _fieldDecoration(
                    key: 'confirm',
                    rawValue: _confirmCtrl.text,
                    prefixIcon: Icons.lock_outline_rounded,
                    hintText: 'Repite la contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _terms,
                      onChanged: (v) => setState(() {
                        _terms = v ?? false;
                        if (_terms) _errors.remove('terms');
                      }),
                      activeColor: cs.primary,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _terms = !_terms;
                          if (_terms) _errors.remove('terms');
                        }),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      'Acepto el acuerdo comercial para restaurantes aliados de ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Bocadoo Ecuador.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_errors['terms'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _errors['terms']!,
                      style: TextStyle(fontSize: 12, color: cs.error),
                    ),
                  ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: (_loading || !_isFormValid) ? null : _register,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_loading) ...[
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Registrando restaurante...',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        const Icon(Icons.storefront_rounded, size: 20),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Registrar mi restaurante',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => continueWithGoogle(context, role: 'owner'),
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                  label: const Text('Continuar con Google'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(
                color: cs.error,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

class _PasswordRuleChip extends StatelessWidget {
  const _PasswordRuleChip({
    required this.label,
    required this.met,
    required this.successColor,
  });

  final String label;
  final bool met;
  final Color successColor;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final fg = met ? successColor : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: fg,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: met ? FontWeight.w700 : FontWeight.w500,
            color: fg,
          ),
        ),
      ],
    );
  }
}
