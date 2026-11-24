import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/events_service.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/config/zones.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/utils/formatters.dart';

class AuthResult {
  const AuthResult._({
    required this.ok,
    this.errorMessage,
    this.errorCode,
    this.hasRestaurant = false,
    this.fieldErrors = const {},
  });

  final bool ok;
  final String? errorMessage;
  final String? errorCode;
  final bool hasRestaurant;
  final Map<String, String> fieldErrors;

  factory AuthResult.success({bool hasRestaurant = false}) => AuthResult._(
        ok: true,
        hasRestaurant: hasRestaurant,
      );

  factory AuthResult.failure(
    String message, {
    String? errorCode,
    Map<String, String> fieldErrors = const {},
  }) =>
      AuthResult._(
        ok: false,
        errorMessage: message,
        errorCode: errorCode,
        fieldErrors: fieldErrors,
      );
}

class SuggestedPlanInput {
  const SuggestedPlanInput({
    required this.tipo,
    required this.nombre,
    required this.almuerzos,
    required this.precioCentavos,
    required this.vigenciaDias,
  });

  /// `'SEMANAL' | 'QUINCENAL' | 'MENSUAL'`.
  final String tipo;
  final String nombre;
  final int almuerzos;
  final int precioCentavos;
  final int vigenciaDias;
}

abstract class IAuthRepository {
  Future<void> warmUpHealth();

  Future<AuthResult> login({
    required String identifier,
    required String password,
    required AppRole expectedRole,
  });

  Future<AuthResult> registerDiner({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? zone,
    double? lat,
    double? lng,
  });

  Future<AuthResult> registerOwner({
    required String restaurantName,
    required String ownerName,
    String? ruc,
    required String email,
    required String whatsapp,
    String? address,
    double? lat,
    double? lng,
    String? zone,
    required double looseLunchPrice,
    int? tablesCount,
    int? seats,
    int? takeawaySurchargeCents,
    required String password,
  });

  Future<MeInfo> me();

  Future<void> saveSuggestedPlans(List<SuggestedPlanInput> plans);

  Future<void> updateOnboardingCapacity({
    required int seats,
    required bool askTableOnCheckout,
  });

  /// Devuelve `true` si el local quedó `ACTIVO`, o `false` si permaneció en `BORRADOR`.
  Future<bool> completeOwnerOnboarding();

  Future<void> logout();

  Future<void> logoutAll();

  Future<AuthResult> signInWithGoogle({required String role});

  Future<bool> requestPasswordReset(String email);
}

class MockAuthRepository implements IAuthRepository {
  @override
  Future<void> warmUpHealth() async {}

  @override
  Future<AuthResult> login({
    required String identifier,
    required String password,
    required AppRole expectedRole,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return AuthResult.success(hasRestaurant: expectedRole == AppRole.owner);
  }

  @override
  Future<AuthResult> registerDiner({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? zone,
    double? lat,
    double? lng,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    return AuthResult.success();
  }

  @override
  Future<AuthResult> registerOwner({
    required String restaurantName,
    required String ownerName,
    String? ruc,
    required String email,
    required String whatsapp,
    String? address,
    double? lat,
    double? lng,
    String? zone,
    required double looseLunchPrice,
    int? tablesCount,
    int? seats,
    int? takeawaySurchargeCents,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return AuthResult.success(hasRestaurant: true);
  }

  @override
  Future<MeInfo> me() async {
    return const MeInfo(
      userId: 'mock-user',
      name: 'Usuario',
      restaurants: [],
    );
  }

  @override
  Future<void> saveSuggestedPlans(List<SuggestedPlanInput> plans) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Future<void> updateOnboardingCapacity({
    required int seats,
    required bool askTableOnCheckout,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Future<bool> completeOwnerOnboarding() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return true;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> logoutAll() async {}

  @override
  Future<AuthResult> signInWithGoogle({required String role}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return AuthResult.success(hasRestaurant: role == 'owner');
  }

  @override
  Future<bool> requestPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return true;
  }
}

class ApiAuthRepository implements IAuthRepository {
  ApiAuthRepository(this._session);

  final SessionNotifier _session;

  ApiClient get _api => _session.api;

  String _roleLabel(AppRole r) => switch (r) {
        AppRole.diner => 'comensal',
        AppRole.owner => 'dueno',
        AppRole.cashier => 'cajero',
      };

  @override
  Future<void> warmUpHealth() async {
    try {
      await _api.getMap(
        '/health',
        auth: false,
        receiveTimeout: ApiConfig.warmUpTimeout,
      );
    } catch (_) {
      // El calentamiento de Render nunca bloquea ni falla la pantalla.
    }
  }

  @override
  Future<AuthResult> login({
    required String identifier,
    required String password,
    required AppRole expectedRole,
  }) async {
    try {
      final tokenData = await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/auth/login',
          body: {
            'identificador': identifier.trim(),
            'password': password,
          },
          auth: false,
        ),
      );
      if (tokenData == null) {
        return AuthResult.failure('No pudimos iniciar sesión. Inténtalo de nuevo.');
      }
      final meInfo = await _session.onLogin(
        accessToken: tokenData['accessToken'] as String,
        refreshToken: tokenData['refreshToken'] as String,
        expiresInSeconds: (tokenData['expiresIn'] as num).toInt(),
        expectedRole: expectedRole,
      );
      eventsService.resetSession();
      eventsService.track(
        'auth.login_ok',
        props: {
          'rol_esperado': _roleLabel(expectedRole),
          'rol_activo': _session.isCashierAccount
              ? 'cajero'
              : (meInfo.restaurants.isNotEmpty ? 'dueno' : 'comensal'),
          'tiene_restaurante': meInfo.restaurants.isNotEmpty,
        },
      );
      return AuthResult.success(hasRestaurant: meInfo.restaurants.isNotEmpty);
    } on ApiException catch (e) {
      eventsService.track(
        'auth.login_error',
        props: {
          'rol_esperado': _roleLabel(expectedRole),
          'status': ?e.status,
          'code': e.code,
        },
      );
      if (e.status == 400 || e.status == 401) {
        return AuthResult.failure('Correo o contraseña incorrectos.');
      }
      return AuthResult.failure(e.userMessage);
    }
  }

  @override
  Future<AuthResult> registerDiner({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? zone,
    double? lat,
    double? lng,
  }) async {
    try {
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/auth/register',
          body: {
            'nombre': name.trim(),
            'correo': email.trim(),
            'password': password,
            'aceptaTerminos': true,
          },
          auth: false,
        ),
      );

      final loginResult = await login(
        identifier: email,
        password: password,
        expectedRole: AppRole.diner,
      );
      if (!loginResult.ok) return loginResult;

      await _session.profile.saveDinerProfile(
        phone: phone != null ? Phone.toLocal(Phone.toE164(phone)) : null,
        zone: zone,
        lat: lat,
        lng: lng,
      );

      eventsService.track(
        'auth.registro_comensal',
        props: {'tiene_zona': zone != null && zone.isNotEmpty},
      );
      if (zone != null || lat != null || lng != null) {
        eventsService.track(
          'registro.ubicacion',
          props: {
            'zona': ?zone,
            'lat': ?lat,
            'lng': ?lng,
          },
        );
      }
      return AuthResult.success(hasRestaurant: loginResult.hasRestaurant);
    } on ApiException catch (e) {
      if (e.status == 409 || e.code == 'CONFLICT') {
        return AuthResult.failure(
          'Ya existe una cuenta con ese correo. Entra o recupera tu contraseña.',
        );
      }
      return AuthResult.failure(e.userMessage);
    }
  }

  @override
  Future<AuthResult> registerOwner({
    required String restaurantName,
    required String ownerName,
    String? ruc,
    required String email,
    required String whatsapp,
    String? address,
    double? lat,
    double? lng,
    String? zone,
    required double looseLunchPrice,
    int? tablesCount,
    int? seats,
    int? takeawaySurchargeCents,
    required String password,
  }) async {
    try {
      final knownZoneId = resolveKnownZoneId(zone);
      final trimmedPhone = whatsapp.trim();
      final e164Phone = Phone.toE164(trimmedPhone);
      final phoneToSend = e164Phone.isNotEmpty ? e164Phone : trimmedPhone;
      final cleanCedulaRuc = ruc?.trim() ?? '';
      final roundedLat =
          lat != null ? double.parse(lat.toStringAsFixed(6)) : null;
      final roundedLng =
          lng != null ? double.parse(lng.toStringAsFixed(6)) : null;

      final restauranteBody = <String, dynamic>{
        'nombre': restaurantName.trim(),
        'ciudadId': 1,
        if (cleanCedulaRuc.isNotEmpty) 'cedulaRuc': cleanCedulaRuc,
        if (phoneToSend.isNotEmpty) 'telefono': phoneToSend,
        if (address != null && address.trim().isNotEmpty)
          'direccion': address.trim(),
        'latitud': ?roundedLat,
        'longitud': ?roundedLng,
        'zonaId': ?knownZoneId,
        if (tablesCount != null && tablesCount > 0) 'mesas': tablesCount,
        if (seats != null && seats > 0) 'puestos': seats,
        'precioSueltoCentavos': Money.toCents(looseLunchPrice),
        if (takeawaySurchargeCents != null && takeawaySurchargeCents >= 0)
          'recargoParaLlevarCentavos': takeawaySurchargeCents,
      };

      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/auth/register-owner',
          body: {
            'nombre': ownerName.trim(),
            'correo': email.trim(),
            'password': password,
            'aceptaTerminos': true,
            'restaurante': restauranteBody,
          },
          auth: false,
        ),
      );

      final loginResult = await login(
        identifier: email,
        password: password,
        expectedRole: AppRole.owner,
      );
      if (!loginResult.ok) return loginResult;

      // No persistimos la cédula/RUC en claro en cliente; se muestra solo la versión enmascarada del servidor.
      await _session.profile.saveOwnerRuc(null);
      await _session.profile.saveDinerProfile(zone: zone, lat: lat, lng: lng);

      final patchBody = <String, dynamic>{
        if (phoneToSend.isNotEmpty) 'telefono': phoneToSend,
        if (address != null && address.trim().isNotEmpty)
          'direccion': address.trim(),
        'latitud': ?roundedLat,
        'longitud': ?roundedLng,
        'zonaId': ?knownZoneId,
        if (cleanCedulaRuc.isNotEmpty) 'cedulaRuc': cleanCedulaRuc,
        if (tablesCount != null && tablesCount > 0) 'mesas': tablesCount,
        if (seats != null && seats > 0) 'puestos': seats,
        'precioSueltoCentavos': Money.toCents(looseLunchPrice),
        if (takeawaySurchargeCents != null && takeawaySurchargeCents >= 0)
          'recargoParaLlevarCentavos': takeawaySurchargeCents,
      };

      try {
        await guard(
          () => _api.send<Map<String, dynamic>>(
            'PATCH',
            '${ApiConfig.v1}/restaurante',
            body: patchBody,
            restaurant: true,
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AuthRepo] PATCH /v1/restaurante post-registro falló: $e');
        }
      }

      eventsService.track(
        'auth.registro_dueno',
        props: {
          'tiene_ubicacion': lat != null && lng != null,
          'precio_centavos': Money.toCents(looseLunchPrice),
        },
      );
      return AuthResult.success(hasRestaurant: true);
    } on ApiException catch (e) {
      final codeUpper = e.code.toUpperCase();
      final titleUpper = e.title.toUpperCase();
      final detailUpper = e.detail.toUpperCase();
      final combinedUpper = '$codeUpper $titleUpper $detailUpper';
      final isDuplicateEmail = e.status == 409 ||
          codeUpper == 'CONFLICT' ||
          combinedUpper.contains('EMAIL_YA_EXISTE') ||
          combinedUpper.contains('CORREO_YA_EXISTE') ||
          combinedUpper.contains('CORREO_DUPLICADO') ||
          ((combinedUpper.contains('EMAIL') ||
                  combinedUpper.contains('CORREO')) &&
              (combinedUpper.contains('EXISTE') ||
                  combinedUpper.contains('REGISTRAD') ||
                  combinedUpper.contains('DUPLICAD') ||
                  combinedUpper.contains('CONFLICT') ||
                  combinedUpper.contains('EN USO')));
      if (isDuplicateEmail) {
        const duplicateMsg =
            'Este correo ya está registrado. Utiliza otro correo para crear tu cuenta.';
        return AuthResult.failure(
          duplicateMsg,
          errorCode: e.code,
          fieldErrors: {
            ...e.fieldErrors,
            'correo': duplicateMsg,
          },
        );
      }
      final detail = e.detail.trim();
      final msg = detail.isNotEmpty ? detail : e.userMessage;
      return AuthResult.failure(
        msg,
        errorCode: e.code,
        fieldErrors: e.fieldErrors,
      );
    }
  }

  @override
  Future<MeInfo> me() => _session.fetchMe();

  @override
  Future<void> saveSuggestedPlans(List<SuggestedPlanInput> plans) async {
    for (final plan in plans) {
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/planes',
          restaurant: true,
          body: {
            'tipo': plan.tipo,
            'nombre': plan.nombre,
            'almuerzos': plan.almuerzos,
            'precioCentavos': plan.precioCentavos,
            'vigenciaDias': plan.vigenciaDias,
            'diasValidos': [1, 2, 3, 4, 5],
            'incluye': ['Sopa', 'Segundo', 'Jugo'],
            'visibleEnMarketplace': true,
          },
        ),
      );
    }
  }

  @override
  Future<void> updateOnboardingCapacity({
    required int seats,
    required bool askTableOnCheckout,
  }) async {
    await guard(
      () => _api.send<Map<String, dynamic>>(
        'PATCH',
        '${ApiConfig.v1}/restaurante',
        restaurant: true,
        body: {
          'puestos': seats,
          'anotarMesa': askTableOnCheckout,
        },
      ),
    );
  }

  @override
  Future<bool> completeOwnerOnboarding() async {
    // TODO(product): B-06 agregar editor de horarios si Carlos lo aprueba.
    final existing = await guard(
      () => _api.getList('${ApiConfig.v1}/restaurante/horarios', restaurant: true),
    );
    if (existing.isEmpty) {
      await guard(
        () => _api.send<List<dynamic>>(
          'PUT',
          '${ApiConfig.v1}/restaurante/horarios',
          restaurant: true,
          body: {
            'horarios': [
              for (var day = 1; day <= 5; day++)
                {'diaSemana': day, 'abre': '12:00', 'cierra': '15:30'},
            ],
          },
        ),
      );
    }

    try {
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/restaurante/activar',
          restaurant: true,
        ),
      );
      return true;
    } on ApiException {
      return false;
    }
  }

  @override
  Future<void> logout() => _session.logout();

  @override
  Future<void> logoutAll() => _session.logoutAll();

  @override
  Future<AuthResult> signInWithGoogle({required String role}) async {
    // TODO(backend): B-01 conectar POST /v1/auth/google y paquete google_sign_in.
    return AuthResult.failure(
      'El acceso con Google estará disponible pronto. Entra con tu correo.',
    );
  }

  @override
  Future<bool> requestPasswordReset(String email) async {
    // TODO(backend): B-03 conectar POST /v1/auth/forgot cuando esté disponible.
    return false;
  }
}

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  if (AppMode.useMock) {
    return MockAuthRepository();
  }
  return ApiAuthRepository(ref.watch(sessionProvider));
});
