import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/customer/data/local_customer_cache.dart';
import '../../features/owner/data/resolved_orders_store.dart';
import '../config/app_mode.dart';
import '../network/api_client.dart';
import '../network/api_config.dart';
import '../network/api_exception.dart';
import '../network/token_store.dart';

enum AppRole { diner, owner, cashier }

class MeRestaurant {
  const MeRestaurant({required this.id, required this.name, required this.rol});

  final String id;
  final String name;

  /// `'DUENO'` o `'CAJERO'`.
  final String rol;

  factory MeRestaurant.fromJson(Map<String, dynamic> json) {
    return MeRestaurant(
      id: (json['id'] ?? '').toString(),
      name: (json['nombre'] ?? '').toString(),
      rol: (json['rol'] ?? '').toString(),
    );
  }
}

class MeInfo {
  const MeInfo({
    required this.userId,
    required this.name,
    this.email,
    required this.restaurants,
  });

  final String userId;
  final String name;
  final String? email;
  final List<MeRestaurant> restaurants;

  factory MeInfo.fromJson(Map<String, dynamic> json) {
    final usuario = json['usuario'] is Map
        ? json['usuario'] as Map
        : const <dynamic, dynamic>{};
    final rawRestaurants = json['restaurantes'] is List
        ? json['restaurantes'] as List
        : const <dynamic>[];
    final rawEmail = (usuario['correo'] ?? usuario['email'])?.toString().trim();
    return MeInfo(
      userId: (usuario['id'] ?? '').toString(),
      name: (usuario['nombre'] ?? '').toString(),
      email: (rawEmail != null && rawEmail.isNotEmpty) ? rawEmail : null,
      restaurants: rawRestaurants
          .whereType<Map>()
          .map((e) => MeRestaurant.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Almacenamiento local complementario para perfil capturado en registro
/// mientras el backend incorpora esos campos (brechas B-02 y B-05).
class LocalProfileStore {
  static const String _kOwnerUserId = 'perfil_user_id';
  static const String _kPhone = 'perfil_telefono';
  static const String _kZone = 'perfil_zona';
  static const String _kLat = 'perfil_lat';
  static const String _kLng = 'perfil_lng';
  static const String _kRuc = 'perfil_ruc';

  Future<void> saveDinerProfile({
    String? userId,
    String? phone,
    String? zone,
    double? lat,
    double? lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId.isNotEmpty) {
      await prefs.setString(_kOwnerUserId, userId);
    }
    if (phone != null) await prefs.setString(_kPhone, phone);
    if (zone != null) await prefs.setString(_kZone, zone);
    if (lat != null) await prefs.setDouble(_kLat, lat);
    if (lng != null) await prefs.setDouble(_kLng, lng);
  }

  Future<void> saveOwnerRuc(String? ruc, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId.isNotEmpty) {
      await prefs.setString(_kOwnerUserId, userId);
    }
    if (ruc == null || ruc.trim().isEmpty) {
      await prefs.remove(_kRuc);
    } else {
      await prefs.setString(_kRuc, ruc.trim());
    }
  }

  /// Devuelve `true` únicamente si el perfil almacenado pertenece exactamente al [currentUserId].
  Future<bool> belongsToUser(String? currentUserId) async {
    if (currentUserId == null || currentUserId.isEmpty) return false;
    final stored = (await SharedPreferences.getInstance()).getString(
      _kOwnerUserId,
    );
    return stored != null && stored.isNotEmpty && stored == currentUserId;
  }

  Future<String?> getPhone() async =>
      (await SharedPreferences.getInstance()).getString(_kPhone);

  Future<String?> getZone() async =>
      (await SharedPreferences.getInstance()).getString(_kZone);

  Future<double?> getLat() async =>
      (await SharedPreferences.getInstance()).getDouble(_kLat);

  Future<double?> getLng() async =>
      (await SharedPreferences.getInstance()).getDouble(_kLng);

  Future<String?> getRuc() async =>
      (await SharedPreferences.getInstance()).getString(_kRuc);

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_kOwnerUserId),
      prefs.remove(_kPhone),
      prefs.remove(_kZone),
      prefs.remove(_kLat),
      prefs.remove(_kLng),
      prefs.remove(_kRuc),
    ]);
  }
}

/// Estado global de sesión autenticada para el enrutador y repositorios.
class SessionNotifier extends ChangeNotifier {
  final TokenStore tokens = TokenStore();
  final LocalProfileStore profile = LocalProfileStore();

  late final ApiClient api = ApiClient(
    tokens: tokens,
    onSessionExpired: expire,
  );

  bool isAuthenticated = false;
  bool isInitialized = false;
  String? userId;
  String? userName;
  String? userEmail;
  List<MeRestaurant> restaurants = const [];
  String? activeRestaurantId;
  AppRole? preferredEntryRole;
  String? expiredMessage;

  static const _businessPrefPrefixes = <String>[
    'resolved_orders_',
    'owner_manual_occupancy_',
    'bocadoo_weekly_summary_',
    'bocadoo_local_logo_',
    'owner_onboarding_done_',
    'pedido_visto_',
  ];
  static const _businessPrefExactKeys = <String>{
    'bocadoo-owner-role',
    'bocadoo_cached_customer_pass',
    'bocadoo_pending_plan_requests',
    'perfil_user_id',
    'perfil_telefono',
    'perfil_zona',
    'perfil_lat',
    'perfil_lng',
    'perfil_ruc',
  };

  bool get hasRestaurant => restaurants.isNotEmpty;

  MeRestaurant? get activeRestaurant =>
      restaurants.where((r) => r.id == activeRestaurantId).firstOrNull;

  /// Cuenta cajero real en backend: restringida en dispositivo a modo Caja.
  bool get isCashierAccount {
    final role = activeRestaurant?.rol.trim().toUpperCase() ?? '';
    return role == 'CAJERO' || role == 'STAFF';
  }

  Future<MeInfo> fetchMe() async {
    final data = await guard(() => api.getMap('${ApiConfig.v1}/auth/me'));
    return MeInfo.fromJson(data);
  }

  /// Restaura la sesión en segundo plano al abrir la app sin bloquear el primer frame.
  Future<void> loadFromStorage() async {
    if (AppMode.useMock) {
      isInitialized = true;
      return;
    }

    try {
      final refreshToken = await tokens.refresh;
      if (refreshToken == null || refreshToken.isEmpty) {
        return;
      }
      final me = await fetchMe();
      final savedRestaurantId = await tokens.restaurantId;
      String? resolvedRestaurantId;
      if (me.restaurants.isNotEmpty) {
        if (savedRestaurantId != null &&
            me.restaurants.any((r) => r.id == savedRestaurantId)) {
          resolvedRestaurantId = savedRestaurantId;
        } else {
          resolvedRestaurantId = me.restaurants.first.id;
          await tokens.setRestaurant(resolvedRestaurantId);
        }
      } else {
        await tokens.setRestaurant(null);
      }

      userId = me.userId;
      userName = me.name;
      userEmail = me.email;
      restaurants = me.restaurants;
      activeRestaurantId = resolvedRestaurantId;
      api.syncSessionHeaders(
        accessToken: await tokens.access,
        restaurantId: resolvedRestaurantId,
      );
      isAuthenticated = true;
      expiredMessage = null;
      notifyListeners();
    } on ApiException {
      // Si el refresh falló por 400/401, el interceptor ya limpió tokens y llamó expire().
      // Si fue un fallo de red o arranque en frío de Render, se conservan los tokens
      // y el usuario puede entrar manualmente.
    } catch (_) {
      // No bloquear el arranque ante errores inesperados de almacenamiento local.
    } finally {
      isInitialized = true;
    }
  }

  /// Limpia tokens, Dio y cachés persistentes antes/después de cambiar de cuenta
  /// o cuando un login falla (`401`).
  Future<void> resetAllCachesAndSession({bool notify = true}) async {
    final wasAuthenticated = isAuthenticated;
    api.resetSessionHeaders();
    await _clearAllStores();
    _resetLocalState();
    if (notify || wasAuthenticated) {
      notifyListeners();
    }
  }

  /// Persiste tokens tras login, limpia cualquier rastro previo, consulta
  /// `/v1/auth/me` y valida `/v1/restaurante` para dueño antes de autenticar.
  Future<MeInfo> onLogin({
    required String accessToken,
    required String refreshToken,
    required int expiresInSeconds,
    AppRole? expectedRole,
    String? loginEmail,
  }) async {
    // 1. Limpieza preventiva total antes de guardar la nueva sesión.
    api.resetSessionHeaders();
    await _clearAllStores();
    _resetLocalState();

    try {
      await tokens.saveTokens(
        access: accessToken,
        refresh: refreshToken,
        expiresInSeconds: expiresInSeconds,
      );
      api.syncSessionHeaders(accessToken: accessToken);

      final me = await fetchMe();

      if (expectedRole == AppRole.owner && me.restaurants.isEmpty) {
        try {
          await api.send<void>(
            'POST',
            '${ApiConfig.v1}/auth/logout',
            body: {'refreshToken': refreshToken},
            auth: false,
          );
        } catch (_) {
          // Mejor esfuerzo al revocar token temporal antes de limpiar.
        }
        await _clearAllStores();
        _resetLocalState();
        notifyListeners();
        throw ApiException(
          code: 'SIN_RESTAURANTE',
          overrideMessage: 'Esta cuenta no tiene un restaurante. Regístrate como dueño o entra como comensal.',
        );
      }

      String? resolvedRestaurantId;
      List<MeRestaurant> resolvedRestaurants = me.restaurants;
      if (me.restaurants.isNotEmpty) {
        resolvedRestaurantId = me.restaurants.first.id;
        await tokens.setRestaurant(resolvedRestaurantId);
        api.syncSessionHeaders(
          accessToken: accessToken,
          restaurantId: resolvedRestaurantId,
        );

        // 2. Consulta obligatoria de GET /v1/restaurante con el nuevo JWT antes de entrar.
        if (expectedRole == AppRole.owner) {
          final isCashierFromMe = me.restaurants.any((r) {
            final rol = r.rol.trim().toUpperCase();
            return rol == 'CAJERO' || rol == 'STAFF';
          });
          try {
            final restData = await guard(
              () => api.getMap('${ApiConfig.v1}/restaurante', restaurant: true),
            );
            final serverName = (restData['nombre'] ?? '').toString().trim();
            final serverId = (restData['id'] ?? '').toString().trim();
            final effectiveId = serverId.isNotEmpty
                ? serverId
                : resolvedRestaurantId;
            if (effectiveId != resolvedRestaurantId) {
              resolvedRestaurantId = effectiveId;
              await tokens.setRestaurant(resolvedRestaurantId);
              api.syncSessionHeaders(
                accessToken: accessToken,
                restaurantId: resolvedRestaurantId,
              );
            }
            if (serverName.isNotEmpty) {
              resolvedRestaurants = [
                for (final r in me.restaurants)
                  if (r.id == resolvedRestaurantId ||
                      r.id == me.restaurants.first.id)
                    MeRestaurant(id: effectiveId, name: serverName, rol: r.rol)
                  else
                    r,
              ];
            }
          } on ApiException catch (e) {
            if (!isCashierFromMe || e.status != 403) rethrow;
          }
        }
      } else {
        await tokens.setRestaurant(null);
      }

      userId = me.userId;
      userName = me.name;
      userEmail = me.email ?? loginEmail;
      restaurants = resolvedRestaurants;
      activeRestaurantId = resolvedRestaurantId;
      preferredEntryRole = expectedRole;
      isAuthenticated = true;
      expiredMessage = null;
      notifyListeners();
      return MeInfo(
        userId: me.userId,
        name: me.name,
        email: me.email ?? loginEmail,
        restaurants: resolvedRestaurants,
      );
    } catch (_) {
      await _clearAllStores();
      _resetLocalState();
      notifyListeners();
      rethrow;
    }
  }

  void clearExpiredMessage() {
    expiredMessage = null;
  }

  void expire() {
    api.resetSessionHeaders();
    isAuthenticated = false;
    userId = null;
    userName = null;
    userEmail = null;
    restaurants = const [];
    activeRestaurantId = null;
    preferredEntryRole = null;
    expiredMessage = 'Tu sesión venció. Entra de nuevo.';
    notifyListeners();
  }

  Future<void> logout() async {
    final refreshToken = await tokens.refresh;
    if (!AppMode.useMock && refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await api.send<void>(
          'POST',
          '${ApiConfig.v1}/auth/logout',
          body: {'refreshToken': refreshToken},
          auth: false,
        );
      } catch (_) {
        // Incluso sin red debemos limpiar la sesión local.
      }
    }
    api.resetSessionHeaders();
    await _clearAllStores();
    _resetLocalState();
    notifyListeners();
  }

  Future<void> logoutAll() async {
    if (!AppMode.useMock) {
      await guard(
        () => api.send<void>('POST', '${ApiConfig.v1}/auth/logout-all'),
      );
    }
    api.resetSessionHeaders();
    await _clearAllStores();
    _resetLocalState();
    notifyListeners();
  }

  Future<void> _clearAllStores() async {
    await tokens.clear();
    await profile.clear();
    await LocalCustomerCache().clear();
    await ResolvedOrdersStore.instance.clearAll();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        final isBusinessKey =
            _businessPrefExactKeys.contains(key) ||
            _businessPrefPrefixes.any(key.startsWith);
        if (isBusinessKey) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }

  void _resetLocalState() {
    isAuthenticated = false;
    userId = null;
    userName = null;
    userEmail = null;
    restaurants = const [];
    activeRestaurantId = null;
    preferredEntryRole = null;
    expiredMessage = null;
  }
}

final SessionNotifier sessionNotifier = SessionNotifier();

final sessionProvider = Provider<SessionNotifier>((ref) => sessionNotifier);
