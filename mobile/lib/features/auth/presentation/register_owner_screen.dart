import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
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
  final Dio _geocodeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: const {'User-Agent': 'BocadooApp/1.0 (ec.bocadoo.app)'},
    ),
  );

  LatLng _mapCenter = LocationService.fallbackPuce;
  bool _locationConfirmed = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _terms = false;
  bool _loading = false;
  bool _locating = false;
  bool _searchingAddress = false;

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
    _geocodeDio.close();
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

  String? _validateRestaurant(String raw) {
    final v = raw.trim();
    if (v.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    if (!RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(v)) {
      return 'Ingresa un nombre válido con letras.';
    }
    return null;
  }

  String? _validateOwnerName(String raw) {
    final v = raw.trim();
    if (v.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    if (RegExp(r'\d').hasMatch(v)) {
      return 'El nombre no debe contener números.';
    }
    if (!RegExp(r'^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s]+$').hasMatch(v)) {
      return 'Usa solo letras, espacios y tildes.';
    }
    if (v.replaceAll(RegExp(r'\s+'), '').length < 2) {
      return 'Ingresa un nombre válido.';
    }
    return null;
  }

  /// Validación oficial ecuatoriana de Cédula (10 dígitos) y RUC (13 dígitos).
  String? _validateCedulaRuc(String raw) {
    final v = raw.trim();
    if (v.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    if (!RegExp(r'^\d+$').hasMatch(v)) {
      return 'Solo se permiten dígitos numéricos.';
    }
    if (v.length != 10 && v.length != 13) {
      return 'Debe tener 10 dígitos (Cédula) o 13 dígitos (RUC).';
    }

    final prov = int.parse(v.substring(0, 2));
    if ((prov < 1 || prov > 24) && prov != 30) {
      return 'Código de provincia inválido';
    }

    if (v.length == 13 && !v.endsWith('001')) {
      return 'El RUC debe terminar en 001';
    }

    final digits = [for (var i = 0; i < v.length; i++) int.parse(v[i])];
    final d3 = digits[2];

    if (v.length == 10 || d3 < 6) {
      if (v.length == 10 && d3 >= 6) {
        return 'Número de cédula/RUC inválido';
      }
      const coeff = [2, 1, 2, 1, 2, 1, 2, 1, 2];
      var sum = 0;
      for (var i = 0; i < 9; i++) {
        var prod = digits[i] * coeff[i];
        if (prod >= 10) prod -= 9;
        sum += prod;
      }
      final check = (10 - (sum % 10)) % 10;
      return check == digits[9] ? null : 'Número de cédula/RUC inválido';
    }

    if (d3 == 6) {
      const coeff = [3, 2, 7, 6, 5, 4, 3, 2];
      var sum = 0;
      for (var i = 0; i < 8; i++) {
        sum += digits[i] * coeff[i];
      }
      final rem = sum % 11;
      final check = rem == 0 ? 0 : 11 - rem;
      return check == digits[8] ? null : 'Número de cédula/RUC inválido';
    }

    if (d3 == 9) {
      const coeff = [4, 3, 2, 7, 6, 5, 4, 3, 2];
      var sum = 0;
      for (var i = 0; i < 9; i++) {
        sum += digits[i] * coeff[i];
      }
      final rem = sum % 11;
      final check = rem == 0 ? 0 : 11 - rem;
      return check == digits[9] ? null : 'Número de cédula/RUC inválido';
    }

    return 'Número de cédula/RUC inválido';
  }

  String? _validateEmail(String raw) {
    final v = raw.trim();
    if (v.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v)) {
      return 'Ingresa un correo comercial válido.';
    }
    if (_duplicateEmailValue != null &&
        v.toLowerCase() == _duplicateEmailValue) {
      return 'Este correo ya está registrado. Utiliza otro correo para crear tu cuenta.';
    }
    return null;
  }

  String? _validateWhatsapp(String raw) {
    final digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    if (!RegExp(r'^09\d{8}$').hasMatch(digits)) {
      return 'Ingresa un celular ecuatoriano válido (09xxxxxxxx).';
    }
    return null;
  }

  String? _validatePrice(String raw) {
    final v = raw.trim().replaceAll(',', '.');
    if (v.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    final price = double.tryParse(v);
    if (price == null || price <= 0 || price > 100) {
      return 'Ingresa el precio del almuerzo (mayor a \$0,00).';
    }
    return null;
  }

  String? _validateTakeawaySurcharge(String raw) {
    final v = raw.trim().replaceAll(',', '.');
    if (v.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    final surcharge = double.tryParse(v);
    if (surcharge == null || surcharge < 0 || surcharge > 20) {
      return 'Ingresa un valor válido (ej. 0.00 o 0.25).';
    }
    return null;
  }

  String? _validateOptionalPositiveInt(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final parsed = int.tryParse(v);
    if (parsed == null || parsed <= 0) {
      return 'Debe ser mayor a 0.';
    }
    return null;
  }

  String? _validatePass(String raw) {
    if (raw.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    if (!_passHasMinLength ||
        !_passHasUpper ||
        !_passHasDigit ||
        !_passHasSymbol) {
      return 'La contraseña debe cumplir todos los requisitos.';
    }
    return null;
  }

  String? _validateConfirm(String raw) {
    if (raw.isEmpty) {
      return 'Este campo es obligatorio.';
    }
    if (raw != _passCtrl.text) {
      return 'Las contraseñas no coinciden.';
    }
    return null;
  }

  String? _validateField(String key) => switch (key) {
        'restaurant' => _validateRestaurant(_restaurantCtrl.text),
        'owner' => _validateOwnerName(_ownerNameCtrl.text),
        'ruc' => _validateCedulaRuc(_rucCtrl.text),
        'email' => _validateEmail(_emailCtrl.text),
        'whatsapp' => _validateWhatsapp(_whatsappCtrl.text),
        'price' => _validatePrice(_priceCtrl.text),
        'takeaway' => _validateTakeawaySurcharge(_takeawaySurchargeCtrl.text),
        'mesas' => _validateOptionalPositiveInt(_tablesCtrl.text),
        'puestos' => _validateOptionalPositiveInt(_seatsCtrl.text),
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
        _errors['email'] = _validateEmail(_emailCtrl.text);
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
      _validateRestaurant(_restaurantCtrl.text) == null &&
      _validateOwnerName(_ownerNameCtrl.text) == null &&
      _validateCedulaRuc(_rucCtrl.text) == null &&
      _validateEmail(_emailCtrl.text) == null &&
      _validateWhatsapp(_whatsappCtrl.text) == null &&
      _validatePrice(_priceCtrl.text) == null &&
      _validateTakeawaySurcharge(_takeawaySurchargeCtrl.text) == null &&
      _validateOptionalPositiveInt(_tablesCtrl.text) == null &&
      _validateOptionalPositiveInt(_seatsCtrl.text) == null &&
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
    return errs.isEmpty;
  }

  // ---------------------------------------------------------------------------
  // Ubicación (Geocodificación + Mi GPS con permiso explícito)
  // ---------------------------------------------------------------------------

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    if (query.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Escribe una dirección o sector para buscar en el mapa.'),
        ),
      );
      return;
    }

    setState(() => _searchingAddress = true);
    try {
      final res = await _geocodeDio.get<List<dynamic>>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'limit': 1,
          'countrycodes': 'ec',
        },
      );
      if (!mounted) return;
      final items = res.data ?? const [];
      if (items.isEmpty || items.first is! Map) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No encontramos esa dirección. Mueve el mapa para ubicar el pin.',
            ),
          ),
        );
        return;
      }
      final first = items.first as Map;
      final lat = double.tryParse((first['lat'] ?? '').toString());
      final lon = double.tryParse((first['lon'] ?? '').toString());
      if (!LocationService.isValidCoordinate(lat, lon)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Coordenadas inválidas para esa búsqueda.'),
          ),
        );
        return;
      }
      final target = LatLng(lat!, lon!);
      setState(() {
        _mapCenter = target;
        _locationConfirmed = true;
        _errors.remove('address');
      });
      _mapController.move(target, 16.5);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos buscar la dirección. Verifica tu conexión o mueve el mapa.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _searchingAddress = false);
    }
  }

  /// "Mi GPS": verifica y solicita permisos explícitamente antes de centrar el mapa.
  Future<void> _useGps() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Activa el servicio de ubicación (GPS) del dispositivo.',
            ),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Debes habilitar el permiso de ubicación para usar Mi GPS.',
            ),
          ),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      if (!LocationService.isValidCoordinate(pos.latitude, pos.longitude)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos obtener tus coordenadas GPS. Mueve el mapa manualmente.',
            ),
          ),
        );
        return;
      }
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _mapCenter = target;
        _locationConfirmed = true;
      });
      _mapController.move(target, 16.5);
      messenger.showSnackBar(
        const SnackBar(content: Text('Mapa centrado en tu ubicación GPS.')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos obtener tu ubicación GPS. Mueve el mapa para fijar el pin.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
          whatsapp: _whatsappCtrl.text.replaceAll(RegExp(r'[\s\-()]'), '').trim(),
          address: _searchCtrl.text.trim(),
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
      final rawMsg =
          result.errorMessage ??
          'No pudimos completar el registro por un problema técnico. Por favor, inténtalo de nuevo.';
      final lower = rawMsg.toLowerCase();
      final looksTechnical = lower.contains('should not exist') ||
          lower.contains('must be') ||
          lower.contains('must not be') ||
          lower.contains('property ') ||
          lower.contains('internal server error') ||
          lower.contains('exception') ||
          lower.contains('stack');
      if (looksTechnical) {
        debugPrint('[RegisterOwner] error técnico ocultado: $rawMsg');
      }
      final friendlyMsg =
          (result.errorCode ?? '').toUpperCase() == 'REGISTRO_CERRADO'
              ? 'El registro de restaurantes está cerrado temporalmente.'
              : (looksTechnical
                  ? 'No pudimos completar el registro por un problema técnico. Por favor, inténtalo de nuevo.'
                  : rawMsg);
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
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    ),
                    child: Text(
                      'Paso 1 de 2 · Restaurante',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
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

              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchAddress(),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  hintText: 'Buscar dirección (ej. Av. 12 de Octubre y Patria)',
                  errorText: _errors['address'],
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: 'Buscar dirección',
                    onPressed: _searchingAddress ? null : _searchAddress,
                    icon: _searchingAddress
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : Icon(Icons.arrow_forward_rounded, color: cs.primary),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                child: SizedBox(
                  height: 210,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _mapCenter,
                          initialZoom: 15.0,
                          onTap: (_, point) {
                            _mapController.move(
                              point,
                              _mapController.camera.zoom,
                            );
                            setState(() {
                              _mapCenter = point;
                              _locationConfirmed = true;
                            });
                          },
                          onPositionChanged: (camera, hasGesture) {
                            _mapCenter = camera.center;
                            if (hasGesture && !_locationConfirmed && mounted) {
                              setState(() => _locationConfirmed = true);
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'ec.bocadoo.app',
                          ),
                          const RichAttributionWidget(
                            alignment: AttributionAlignment.bottomLeft,
                            attributions: [
                              TextSourceAttribution('OpenStreetMap'),
                            ],
                          ),
                        ],
                      ),
                      // Pin fijo centrado como referencia sobre el mapa.
                      IgnorePointer(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.translate(
                                offset: const Offset(0, -14),
                                child: Icon(
                                  Icons.location_on_rounded,
                                  size: 42,
                                  color: cs.primary,
                                ),
                              ),
                              Transform.translate(
                                offset: const Offset(0, -18),
                                child: Container(
                                  width: 8,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: cs.scrim.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _locationConfirmed
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: _locationConfirmed ? b.success : cs.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _locationConfirmed
                          ? 'Ubicación fijada (${_mapCenter.latitude.toStringAsFixed(4)}, ${_mapCenter.longitude.toStringAsFixed(4)}).'
                          : 'Fija la ubicación de tu local en el mapa o usa Mi GPS.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _locationConfirmed ? b.success : cs.error,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              OutlinedButton.icon(
                onPressed: _locating ? null : _useGps,
                icon: _locating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.gps_fixed_rounded, size: 18),
                label: Text(_locating ? 'Obteniendo GPS...' : 'Mi GPS'),
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
