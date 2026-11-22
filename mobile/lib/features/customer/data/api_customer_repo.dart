import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/analytics/events_service.dart';
import '../../../core/config/support_config.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/deferred_commit.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/utils/formatters.dart';
import 'local_customer_cache.dart';
import 'pase_events_stream.dart';

/// Implementación real de [ICustomerRepository] conectada a la API v1 de Bocadoo.
class ApiCustomerRepository implements ICustomerRepository {
  ApiCustomerRepository({
    required ApiClient apiClient,
    this._session,
    LocalCustomerCache? passCache,
    LocalProfileStore? profileStore,
    DeferredCommit? deferredCommit,
  })  : _api = apiClient,
        _passCache = passCache ?? LocalCustomerCache(),
        _profileStore = profileStore ?? LocalProfileStore(),
        _deferredCommit = deferredCommit ??
            DeferredCommit(delay: const Duration(seconds: 11));

  final ApiClient _api;
  final SessionNotifier? _session;
  final LocalCustomerCache _passCache;
  final LocalProfileStore _profileStore;
  final DeferredCommit _deferredCommit;
  final IdempotencyStore _idempotency = IdempotencyStore();

  final Map<String, Restaurant> _restaurantCache = {};
  final Map<String, bool> _todayMenuPublishedByRest = {};
  final Map<String, MenuAvailabilityState> _todayMenuAvailabilityByRest = {};
  final Map<String, String> _slugById = {};
  final Map<String, String> _restaurantByPassId = {};
  final Map<String, List<PlanTemplate>> _plansByRestaurantCache = {};
  final Map<String, PlanTemplate> _planCache = {};
  final Map<String, List<String>> _planIncludesByName = {};
  final Map<String, String> _orderIdByNumber = {};
  final Map<String, String> _estimatedArrivalByOrderNumber = {};
  final Map<String, ({int partySize, bool takeaway})> _tablePrefsById = {};

  /// Último estado conocido de publicación del menú de hoy por `restaurantId`.
  bool? cachedTodayMenuPublished(String restaurantId) =>
      _todayMenuPublishedByRest[restaurantId];

  /// Último estado de disponibilidad del menú de hoy (`sinPublicar` / `disponible` / `agotadoTotal`).
  MenuAvailabilityState? cachedTodayMenuAvailability(String restaurantId) =>
      _todayMenuAvailabilityByRest[restaurantId];

  List<Map<String, dynamic>>? _sellosCache;
  DateTime? _sellosCacheAt;
  LatLng? _cachedUserPosition;
  bool _positionResolved = false;
  String? _pendingPlanId;

  // ---------------------------------------------------------------------------
  // C1 · Pase, QR rotativo y caché offline
  // ---------------------------------------------------------------------------

  @override
  Future<List<CustomerPass>> getActivePasses({String? userId}) async {
    final data = await guard(() => _api.getMap('${ApiConfig.v1}/pase'));
    final usuario = _asMap(data['usuario']);
    final codigo = _asMap(data['codigo']);
    final locales = _asListOfMaps(data['locales']);

    final uid = (usuario['id'] ?? _session?.userId ?? userId ?? '').toString();
    final studentName =
        (usuario['nombre'] ?? _session?.userName ?? 'Comensal').toString();
    final qrToken = (codigo['codigo'] ?? '').toString();
    final qrExpiresAt = _parseQrExpiry(codigo);

    final passes = <CustomerPass>[];
    for (final local in locales) {
      final rest = _asMap(local['restaurante']);
      final restId = (rest['id'] ?? '').toString();
      final restName = (rest['nombre'] ?? '').toString();
      final slug = (rest['slug'] ?? '').toString();
      if (restId.isNotEmpty && slug.isNotEmpty) {
        _slugById[restId] = slug;
      }
      var menuReadyForLocal = true;
      if (restId.isNotEmpty && local['menuHoyPublicado'] is bool) {
        final published = local['menuHoyPublicado'] as bool;
        menuReadyForLocal = published;
        _todayMenuPublishedByRest[restId] = published;
        if (!published) {
          _todayMenuAvailabilityByRest[restId] =
              MenuAvailabilityState.sinPublicar;
        } else if (_todayMenuAvailabilityByRest[restId] ==
                MenuAvailabilityState.sinPublicar ||
            !_todayMenuAvailabilityByRest.containsKey(restId)) {
          _todayMenuAvailabilityByRest[restId] =
              MenuAvailabilityState.disponible;
        }
      }
      final cachedAvail = _todayMenuAvailabilityByRest[restId];
      final allowQrForLocal =
          menuReadyForLocal && cachedAvail != MenuAvailabilityState.agotadoTotal;

      final planes = _asListOfMaps(local['planes']);
      if (planes.isEmpty) continue;

      final localRemaining = _asInt(local['almuerzosDisponibles']);
      final hasPerPlanRemaining =
          planes.any((p) => p['almuerzosRestantes'] != null);

      if (hasPerPlanRemaining) {
        for (final plan in planes) {
          final passId = (plan['id'] ?? '').toString();
          if (passId.isNotEmpty && restId.isNotEmpty) {
            _restaurantByPassId[passId] = restId;
          }
          final remaining = _asInt(plan['almuerzosRestantes']) ?? 0;
          final rawTotal = _asInt(plan['almuerzosTotales']) ?? remaining;
          final safeTotal = rawTotal >= remaining ? rawTotal : remaining;
          final daysLeft = _asInt(plan['diasParaVencer']);
          final expiresAt =
              _parseEndOfDayEcuador(plan['venceEl']?.toString()) ??
                  DateTime.now().add(Duration(days: daysLeft ?? 0));

          final status = _computePassStatus(
            remaining: remaining,
            daysLeft: daysLeft,
            expiresAt: expiresAt,
          );

          passes.add(CustomerPass(
            id: passId,
            userId: uid,
            studentName: studentName,
            planName: (plan['nombre'] ?? 'Plan de almuerzos').toString(),
            totalLunches: safeTotal > 0 ? safeTotal : remaining,
            remainingLunches: remaining,
            expiresAt: expiresAt,
            status: status,
            qrToken: allowQrForLocal ? qrToken : '',
            qrExpiresAt: allowQrForLocal ? qrExpiresAt : null,
            restaurantId: restId,
            restaurantName: restName,
            avatarUrl: rest['logoUrl']?.toString(),
          ));
        }
      } else {
        final first = planes.first;
        final passId = (first['id'] ?? '').toString();
        if (passId.isNotEmpty && restId.isNotEmpty) {
          _restaurantByPassId[passId] = restId;
        }
        final remaining = localRemaining ?? 0;
        final sumTotals = planes.fold<int>(
          0,
          (sum, p) => sum + (_asInt(p['almuerzosTotales']) ?? 0),
        );
        final safeTotal = sumTotals >= remaining ? sumTotals : remaining;
        final daysLeft = _asInt(first['diasParaVencer']);
        final expiresAt =
            _parseEndOfDayEcuador(first['venceEl']?.toString()) ??
                DateTime.now().add(Duration(days: daysLeft ?? 0));

        final status = _computePassStatus(
          remaining: remaining,
          daysLeft: daysLeft,
          expiresAt: expiresAt,
        );

        passes.add(CustomerPass(
          id: passId,
          userId: uid,
          studentName: studentName,
          planName: (first['nombre'] ?? 'Plan de almuerzos').toString(),
          totalLunches: safeTotal > 0 ? safeTotal : remaining,
          remainingLunches: remaining,
          expiresAt: expiresAt,
          status: status,
          qrToken: allowQrForLocal ? qrToken : '',
          qrExpiresAt: allowQrForLocal ? qrExpiresAt : null,
          restaurantId: restId,
          restaurantName: restName,
          avatarUrl: rest['logoUrl']?.toString(),
        ));
      }
    }

    if (passes.isNotEmpty && passes.first.qrToken.isNotEmpty) {
      await saveCachedPass(passes.first);
    } else {
      await _passCache.clear();
    }
    return passes;
  }

  DateTime? _parseQrExpiry(Map<dynamic, dynamic> map) {
    final rawExp = map['expiraEn']?.toString();
    if (rawExp != null && rawExp.trim().isNotEmpty) {
      final dt = DateTime.tryParse(rawExp.trim())?.toLocal();
      if (dt != null) return dt;
    }
    final secs = _asInt(map['validoSegundos']);
    if (secs != null && secs > 0) {
      return DateTime.now().add(Duration(seconds: secs));
    }
    return null;
  }

  @override
  Future<CustomerPass> getActivePass({String? userId}) async {
    final passes = await getActivePasses(userId: userId);
    if (passes.isNotEmpty) return passes.first;
    final cached = await getCachedPass();
    if (cached != null) return cached;
    throw ApiException(status: 404, code: 'PASE_NO_ENCONTRADO');
  }

  /// Pide un token QR firmado fresco a `GET /v1/pase/codigo` junto a su `expiraEn`.
  Future<({String token, DateTime expiresAt})> fetchQrTokenWithExpiry(
    String passId,
  ) async {
    final restId = _restaurantByPassId[passId];
    final data = await guard(
      () => _api.getMap(
        '${ApiConfig.v1}/pase/codigo',
        query: {
          if (restId != null && restId.isNotEmpty) 'restaurante': restId,
        },
      ),
    );
    eventsService.track('comensal.qr_generado', restaurantId: restId);
    final raw = (data['codigo'] ?? '').toString();
    if (raw.isEmpty) {
      throw ApiException(status: 500, code: 'ERROR_INTERNO');
    }
    final expiresAt =
        _parseQrExpiry(data) ?? DateTime.now().add(const Duration(seconds: 30));
    return (token: raw, expiresAt: expiresAt);
  }

  @override
  Future<String> refreshQrToken(String passId) async {
    final res = await fetchQrTokenWithExpiry(passId);
    return res.token;
  }

  Future<void> clearCachedPass() => _passCache.clear();

  @override
  Future<CustomerPass?> getCachedPass() async {
    final pass = await _passCache.getPass();
    final sessionUid = _session?.userId;
    if (pass != null &&
        sessionUid != null &&
        sessionUid.isNotEmpty &&
        pass.userId.isNotEmpty &&
        pass.userId != sessionUid) {
      await _passCache.clear();
      return null;
    }
    if (pass != null && pass.id.isNotEmpty && pass.restaurantId.isNotEmpty) {
      _restaurantByPassId[pass.id] = pass.restaurantId;
    }
    if (pass != null &&
        pass.qrExpiresAt != null &&
        !pass.qrExpiresAt!.isAfter(DateTime.now())) {
      return pass.copyWith(qrToken: '', clearQrExpiresAt: true);
    }
    return pass;
  }

  @override
  Future<void> saveCachedPass(CustomerPass pass) {
    if (pass.id.isNotEmpty && pass.restaurantId.isNotEmpty) {
      _restaurantByPassId[pass.id] = pass.restaurantId;
    }
    return _passCache.savePass(pass);
  }

  /// Abre el stream SSE `GET /v1/pase/eventos` autenticado con Bearer.
  Future<Stream<PaseSseEvent>> connectPaseEvents({
    CancelToken? cancelToken,
  }) async {
    final response = await guard(
      () => _api.openSseStream(
        '${ApiConfig.v1}/pase/eventos',
        cancelToken: cancelToken,
      ),
    );
    final body = response.data;
    if (body == null) {
      return const Stream<PaseSseEvent>.empty();
    }
    return parsePaseSseStream(body.stream);
  }

  /// Renueva el par de tokens (`POST /v1/auth/refresh`) cuando SSE emite `TOKEN_VENCIDO`.
  Future<bool> refreshAuthSession() => _api.refreshSession();

  // ---------------------------------------------------------------------------
  // C1 · Sellos y mesa activa
  // ---------------------------------------------------------------------------

  @override
  Future<StampCard?> getStampCard(String restaurantId) async {
    final now = DateTime.now();
    final cacheValid = _sellosCache != null &&
        _sellosCacheAt != null &&
        now.difference(_sellosCacheAt!) < const Duration(seconds: 3);

    final list = cacheValid
        ? _sellosCache!
        : _asListOfMaps(
            await guard(() => _api.getList('${ApiConfig.v1}/mis/sellos')),
          );
    _sellosCache = list;
    _sellosCacheAt = now;

    for (final item in list) {
      final rest = _asMap(item['restaurante']);
      if ((rest['id'] ?? '').toString() != restaurantId) continue;
      final active = item['activa'] == true;
      final rewards = _asInt(item['premiosDisponibles']) ?? 0;
      if (!active && rewards <= 0) return null;
      final cardName = (item['nombre'] ?? '').toString().trim();
      return StampCard(
        restaurantId: restaurantId,
        name: cardName.isEmpty ? 'Tarjeta de sellos' : cardName,
        current: _asInt(item['sellos']) ?? 0,
        goal: (_asInt(item['meta']) ?? 10).clamp(1, 100),
        reward: (item['premio'] ?? 'Almuerzo gratis').toString(),
        rewardsAvailable: rewards,
      );
    }
    return null;
  }

  @override
  Future<bool> claimReward(String restaurantId) async {
    // El cajero valida el premio directamente al escanear el pase en caja (E3).
    return false;
  }

  @override
  Future<ActiveTable?> getActiveTable() async {
    final list = _asListOfMaps(
      await guard(() => _api.getList('${ApiConfig.v1}/mis/mesas')),
    );
    for (final item in list) {
      final estado = (item['estado'] ?? '').toString();
      if (estado == 'FINALIZADA' || estado == 'CANCELADA') continue;
      final id = (item['id'] ?? '').toString();
      final rest = _asMap(item['restaurante']);
      final miembros = _asListOfMaps(item['miembros']);
      final hora = DateTime.tryParse((item['horaLlegada'] ?? '').toString());
      return ActiveTable(
        id: id,
        restaurantName: (rest['nombre'] ?? '').toString(),
        time: _formatEcuadorTime(hora),
        membersCount: miembros.length,
        url: 'BCD-MESA-$id',
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // C1 / C4 · Actividad e historial de consumos
  // ---------------------------------------------------------------------------

  @override
  Future<List<ActivityItem>> getRecentActivity() async {
    final data = await guard(
      () => _api.getMap(
        '${ApiConfig.v1}/mis/consumos',
        query: const {'limit': 20},
      ),
    );
    final items = _asListOfMaps(data['items']);
    return [
      for (final item in items) _mapConsumoToActivity(item),
    ];
  }

  @override
  Future<List<ConsumptionRecord>> getConsumptionHistory(String passId) async {
    final restId = _restaurantByPassId[passId];
    final data = await guard(
      () => _api.getMap(
        '${ApiConfig.v1}/mis/consumos',
        query: {
          'limit': 50,
          if (restId != null && restId.isNotEmpty) 'restaurante': restId,
        },
      ),
    );
    final items = _asListOfMaps(data['items']);
    return [
      for (final item in items) _mapConsumoToRecord(item, passId),
    ];
  }

  // ---------------------------------------------------------------------------
  // C2 / C3 / C11 · Restaurantes, menús, planes y ofertas
  // ---------------------------------------------------------------------------

  @override
  Future<List<Restaurant>> getRestaurants({
    String? query,
    String? category,
  }) async {
    final posFuture = _resolveUserPosition().timeout(
      const Duration(seconds: 3),
      onTimeout: () => _cachedUserPosition,
    );
    final allRaw = <Map<String, dynamic>>[];
    String? cursor;
    var pages = 0;

    do {
      final res = await guard(
        () => _api.getMap(
          '${ApiConfig.v1}/restaurantes',
          auth: false,
          query: {
            'limit': 50,
            if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          },
        ),
      );
      allRaw.addAll(_asListOfMaps(res['items']));
      cursor = res['nextCursor']?.toString();
      pages++;
    } while (cursor != null && cursor.isNotEmpty && pages < 10);

    final userPos = await posFuture;

    final mapped = <Restaurant>[];
    for (final item in allRaw) {
      final r = _mapCardToRestaurant(item, userPos);
      mapped.add(r);
    }

    mapped.sort((a, b) {
      if (a.hasLocation != b.hasLocation) {
        return a.hasLocation ? -1 : 1;
      }
      return a.resolvedMeters.compareTo(b.resolvedMeters);
    });

    if (category != null && category.isNotEmpty && category != 'Todos') {
      final target = category.toLowerCase();
      final filtered = mapped
          .where((r) => r.categories.any((c) => c.toLowerCase() == target))
          .toList();
      eventsService.track(
        'comensal.vitrina_consultada',
        props: {
          'con_busqueda': query != null && query.trim().isNotEmpty,
          'filtro': target,
          'total': filtered.length,
        },
      );
      return filtered;
    }
    eventsService.track(
      'comensal.vitrina_consultada',
      props: {
        'con_busqueda': query != null && query.trim().isNotEmpty,
        'total': mapped.length,
      },
    );
    return mapped;
  }

  @override
  Future<Restaurant?> getRestaurantById(String id) async {
    var slug = _slugById[id];
    if (slug == null || slug.isEmpty) {
      await getRestaurants();
      slug = _slugById[id] ?? id;
    }

    try {
      final results = await Future.wait([
        guard(
          () => _api.getMap(
            '${ApiConfig.v1}/restaurantes/$slug',
            auth: false,
          ),
        ),
        _fetchOffersSafe(slug),
      ]);

      final detail = results[0] as Map<String, dynamic>;
      final offersRaw = results[1] as List<Map<String, dynamic>>;
      final userPos = await _resolveUserPosition();
      final mapped = _mapDetailToRestaurant(detail, offersRaw, userPos);
      eventsService.track(
        'comensal.restaurante_visto',
        restaurantId: mapped.id,
        props: {
          'tiene_menu': mapped.todayMenu.isNotEmpty,
          'tiene_planes': mapped.hasPlan,
          'ofertas': mapped.offers.length,
        },
      );
      return mapped;
    } on ApiException catch (e) {
      if (e.status == 404 || e.code == 'RESTAURANTE_NO_ENCONTRADO') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<List<MenuItem>> getTodayMenu(String restaurantId) async {
    final detail = await getRestaurantById(restaurantId);
    return detail?.todayMenu ?? const [];
  }

  static int _cartaCategoryRank(String categoria) => switch (categoria.toUpperCase()) {
        'A_LA_CARTA' => 0,
        'BEBIDA' => 1,
        'EXTRA' => 2,
        _ => 3,
      };

  @override
  Future<List<PublicCartaItem>> getRestaurantCarta(String restaurantId) async {
    var slug = _slugById[restaurantId];
    if (slug == null || slug.isEmpty) {
      await getRestaurants();
      slug = _slugById[restaurantId] ?? restaurantId;
    }

    try {
      final raw = await guard(
        () => _api.send<dynamic>(
          'GET',
          '${ApiConfig.v1}/restaurantes/$slug/carta',
          auth: false,
        ),
      );
      final List<Map<String, dynamic>> rawItems;
      if (raw is List) {
        rawItems = _asListOfMaps(raw);
      } else if (raw is Map) {
        final map = _asMap(raw);
        if (map['items'] is List) {
          rawItems = _asListOfMaps(map['items']);
        } else if (map['carta'] is List) {
          rawItems = _asListOfMaps(map['carta']);
        } else if (map['platos'] is List) {
          rawItems = _asListOfMaps(map['platos']);
        } else {
          rawItems = const [];
        }
      } else {
        rawItems = const [];
      }

      final parsed = <PublicCartaItem>[];
      for (final item in rawItems) {
        final id = (item['id'] ?? '').toString();
        final name = (item['nombre'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final categoria =
            (item['categoria'] ?? 'A_LA_CARTA').toString().toUpperCase();
        parsed.add(
          PublicCartaItem(
            id: id,
            name: name,
            category: categoria,
            priceCents: _asInt(item['precioCentavos']) ?? 0,
            order: _asInt(item['orden']) ?? 0,
            isSoldOut: item['agotado'] == true,
            description: (item['descripcion'] ?? '').toString().trim(),
            imageUrl: item['fotoUrl']?.toString(),
          ),
        );
      }
      parsed.sort((a, b) {
        final rankCmp =
            _cartaCategoryRank(a.category).compareTo(_cartaCategoryRank(b.category));
        if (rankCmp != 0) return rankCmp;
        final ordCmp = a.order.compareTo(b.order);
        if (ordCmp != 0) return ordCmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return parsed;
    } on ApiException catch (e) {
      if (e.status == 404) return const [];
      rethrow;
    }
  }

  @override
  Future<List<PlanTemplate>> getPlanTemplates(String restaurantId) async {
    final detail = await getRestaurantById(restaurantId);
    if (detail == null) return const [];
    return _plansByRestaurantCache[detail.id] ?? const [];
  }

  @override
  Future<PlanTemplate?> getPlanTemplateById(String planId) async {
    final cached = _planCache[planId];
    if (cached != null) return cached;

    if (_restaurantCache.isEmpty) {
      await getRestaurants();
    }
    for (final id in _restaurantCache.keys.toList()) {
      await getRestaurantById(id);
      final found = _planCache[planId];
      if (found != null) return found;
    }
    return null;
  }

  @override
  Future<bool> requestPlan(String planId) async {
    final plan = await getPlanTemplateById(planId);
    if (plan == null) {
      throw ApiException(status: 404, code: 'ERROR_INTERNO');
    }
    var slug = _slugById[plan.restaurantId];
    if (slug == null || slug.isEmpty) {
      await getRestaurantById(plan.restaurantId);
      slug = _slugById[plan.restaurantId];
    }
    if (slug == null || slug.isEmpty) {
      throw ApiException(status: 404, code: 'RESTAURANTE_NO_ENCONTRADO');
    }

    if (_deferredCommit.isPending &&
        _pendingPlanId != null &&
        _pendingPlanId != planId) {
      await _deferredCommit.flush();
    }

    final targetSlug = slug;
    final intent = 'solicitud-plan:$targetSlug:$planId';
    _pendingPlanId = planId;
    _deferredCommit.schedule(() async {
      _pendingPlanId = null;
      final key = _idempotency.keyFor(intent);
      await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/restaurantes/$targetSlug/solicitudes-plan',
          body: {'planId': planId},
          idempotencyKey: key,
        ),
      );
      _idempotency.done(intent);
      eventsService.track(
        'comensal.plan_solicitado',
        restaurantId: plan.restaurantId,
        props: {'almuerzos': plan.lunches},
      );
    });
    return true;
  }

  @override
  Future<bool> cancelPlanRequest(String planId) async {
    if (_pendingPlanId != planId) return false;
    _pendingPlanId = null;
    final cancelled = _deferredCommit.cancel();
    if (cancelled) {
      eventsService.track('comensal.plan_deshecho');
    }
    return cancelled;
  }

  // ---------------------------------------------------------------------------
  // C8 · Ciclo de vida de pedidos / preórdenes
  // ---------------------------------------------------------------------------

  @override
  Future<ActiveOrder?> getActiveOrder() async {
    final data = await guard(
      () => _api.getMap(
        '${ApiConfig.v1}/mis/pedidos',
        query: const {'limit': 5},
      ),
    );
    final items = _asListOfMaps(data['items']);
    if (items.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    for (final item in items) {
      final estado = (item['estado'] ?? '').toString().toUpperCase();
      if (estado == 'EXPIRADA' ||
          estado == 'CANCELADA' ||
          estado == 'RECHAZADA' ||
          estado == 'FINALIZADA' ||
          estado == 'ENTREGADA') {
        continue;
      }

      final id = (item['id'] ?? '').toString();
      final numero = (item['numero'] ?? '').toString();
      if (id.isNotEmpty && numero.isNotEmpty) {
        _orderIdByNumber[numero] = id;
      }

      if (estado == 'SERVIDA') {
        final seenById = id.isNotEmpty && prefs.getBool('pedido_visto_$id') == true;
        final seenByNumber =
            numero.isNotEmpty && prefs.getBool('pedido_visto_$numero') == true;
        if (seenById || seenByNumber) continue;
        final createdRaw = item['creadoEn']?.toString();
        final created = createdRaw != null ? DateTime.tryParse(createdRaw) : null;
        if (created != null &&
            EcuadorTime.now().difference(created.toUtc().subtract(const Duration(hours: 5))).inHours >= 12) {
          continue;
        }
      }

      return _mapPedidoToActiveOrder(item);
    }
    return null;
  }

  @override
  Future<ActiveOrder> preorder({
    required String restaurantId,
    String? soupId,
    String? mainId,
    String? breakfastId,
    String? offerId,
    required bool takeaway,
    String? estimatedArrival,
  }) async {
    final platos = <String>[
      if (soupId != null && soupId.isNotEmpty) soupId,
      if (mainId != null && mainId.isNotEmpty) mainId,
    ];
    final extras = <Map<String, dynamic>>[
      if (platos.isEmpty && breakfastId != null && breakfastId.isNotEmpty)
        {'plato': breakfastId, 'cantidad': 1},
    ];

    if (platos.isEmpty && extras.isEmpty) {
      throw ApiException(
        status: 422,
        code: 'PEDIDO_VACIO',
        overrideMessage: offerId != null
            ? 'Las promociones se solicitan directamente en caja.'
            : null,
      );
    }

    final body = <String, dynamic>{
      'restaurante': restaurantId,
      'paraLlevar': takeaway,
      if (platos.isNotEmpty) 'almuerzo': {'platos': platos},
      if (extras.isNotEmpty) 'extras': extras,
    };

    final intent =
        'crear-pedido:$restaurantId:${platos.join(",")}:${breakfastId ?? ""}:$takeaway';
    final key = _idempotency.keyFor(intent);
    final res = await guard(
      () => _api.send<Map<String, dynamic>>(
        'POST',
        '${ApiConfig.v1}/mis/pedidos',
        body: body,
        idempotencyKey: key,
      ),
    );
    _idempotency.done(intent);
    final mapped = _mapPedidoToActiveOrder(res ?? const {});
    final eta = (estimatedArrival != null &&
            estimatedArrival.isNotEmpty &&
            estimatedArrival != 'En 15 min')
        ? estimatedArrival
        : (mapped.estimatedArrivalLabel ??
            _formatEcuadorTime(DateTime.now().toUtc().add(const Duration(minutes: 15))));
    if (mapped.orderNumber.isNotEmpty) {
      _estimatedArrivalByOrderNumber[mapped.orderNumber] = eta;
    }
    final order = ActiveOrder(
      id: mapped.id,
      restaurantId: mapped.restaurantId ?? restaurantId,
      orderNumber: mapped.orderNumber,
      status: mapped.status,
      restaurantName: mapped.restaurantName,
      qrPayload: mapped.qrPayload,
      detail: mapped.detail,
      soup: mapped.soup,
      main: mapped.main,
      takeaway: mapped.takeaway,
      takeawaySurcharge: mapped.takeawaySurcharge,
      singleLunchPrice: mapped.singleLunchPrice,
      basePriceCents: mapped.basePriceCents,
      takeawaySurchargeCents: mapped.takeawaySurchargeCents,
      totalCents: mapped.totalCents,
      estimatedArrivalLabel: eta,
      hasPlan: mapped.hasPlan,
      expiresAt: mapped.expiresAt,
      paidAmount: mapped.paidAmount,
    );
    eventsService.track(
      'comensal.preorden_creada',
      restaurantId: restaurantId,
      props: {'para_llevar': takeaway, 'por_plan': order.hasPlan},
    );
    return order;
  }

  @override
  Future<bool> cancelPreorder(String orderNumber) async {
    var uuid = _orderIdByNumber[orderNumber];
    if (uuid == null || uuid.isEmpty) {
      await getActiveOrder();
      uuid = _orderIdByNumber[orderNumber];
    }
    if (uuid == null || uuid.isEmpty) return false;

    await guard(
      () => _api.send<Map<String, dynamic>>(
        'POST',
        '${ApiConfig.v1}/mis/pedidos/$uuid/cancelar',
      ),
    );
    eventsService.track('comensal.preorden_cancelada');
    return true;
  }

  @override
  Future<bool> acknowledgeOrder(String orderNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final uuid = _orderIdByNumber[orderNumber];
    if (uuid != null && uuid.isNotEmpty) {
      await prefs.setBool('pedido_visto_$uuid', true);
    }
    if (orderNumber.isNotEmpty) {
      await prefs.setBool('pedido_visto_$orderNumber', true);
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // C6 · Perfil
  // ---------------------------------------------------------------------------

  @override
  Future<CustomerProfile> getProfile() async {
    MeInfo me;
    try {
      final meMap = await guard(() => _api.getMap('${ApiConfig.v1}/auth/me'));
      me = MeInfo.fromJson(meMap);
    } catch (_) {
      me = MeInfo(
        userId: _session?.userId ?? '',
        name: _session?.userName ?? 'Comensal',
        restaurants: _session?.restaurants ?? const [],
      );
    }

    String? habitualPlanName;
    String? habitualRestId;
    List<String> habitualIncludes = const [];

    try {
      final pase = await guard(() => _api.getMap('${ApiConfig.v1}/pase'));
      final locales = _asListOfMaps(pase['locales']);
      for (final local in locales) {
        final planes = _asListOfMaps(local['planes']);
        if (planes.isEmpty) continue;
        final rest = _asMap(local['restaurante']);
        habitualRestId = (rest['id'] ?? '').toString();
        final slug = (rest['slug'] ?? '').toString();
        if (habitualRestId.isNotEmpty && slug.isNotEmpty) {
          _slugById[habitualRestId] = slug;
        }
        habitualPlanName = (planes.first['nombre'] ?? '').toString();
        break;
      }
    } catch (_) {
      // Si no tiene pase activo o falla, se conserva perfil básico.
    }

    if (habitualRestId != null &&
        habitualRestId.isNotEmpty &&
        !_plansByRestaurantCache.containsKey(habitualRestId)) {
      try {
        await getRestaurantById(habitualRestId);
      } catch (_) {}
    }

    if (habitualPlanName != null && habitualPlanName.isNotEmpty) {
      habitualIncludes = _planIncludesByName[habitualPlanName] ?? const [];
    }

    final storedPhone = await _profileStore.getPhone();
    final formattedPhone = storedPhone != null && storedPhone.trim().isNotEmpty
        ? Phone.toLocal(storedPhone)
        : '';

    return CustomerProfile(
      name: me.name.isNotEmpty ? me.name : (_session?.userName ?? 'Comensal'),
      phone: formattedPhone.isEmpty ? 'Sin teléfono registrado' : formattedPhone,
      habitualPlanName:
          (habitualPlanName != null && habitualPlanName.isNotEmpty)
              ? habitualPlanName
              : null,
      habitualPlanIncludes: habitualIncludes,
      supportWhatsApp: SupportConfig.whatsApp,
    );
  }

  // ---------------------------------------------------------------------------
  // C10 · Opiniones ("¿Qué tal hoy?")
  // ---------------------------------------------------------------------------

  @override
  Future<PendingFeedback?> getPendingFeedback() async {
    final list = _asListOfMaps(
      await guard(
        () => _api.getList('${ApiConfig.v1}/mis/opiniones/pendientes'),
      ),
    );
    if (list.isEmpty) return null;
    final first = list.first;
    final consumo = _asMap(first['consumo']);
    final rest = _asMap(consumo['restaurante']);
    final id = (consumo['id'] ?? '').toString();
    if (id.isEmpty) return null;

    return PendingFeedback(
      redemptionId: id,
      restaurantId: (rest['id'] ?? '').toString(),
      restaurantName: (rest['nombre'] ?? '').toString(),
      validatedAt: DateTime.tryParse((consumo['fecha'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  @override
  Future<bool> submitFeedback(
    String redemptionId, {
    required String tag,
    String? note,
  }) async {
    const tagMap = <String, String>{
      'Rico': 'RICO',
      'Rápido': 'RAPIDO',
      'Porción': 'BUENA_PORCION',
    };
    final apiTag = tagMap[tag] ?? tag.toUpperCase().replaceAll(' ', '_');
    final intent = 'opinion:$redemptionId';
    final key = _idempotency.keyFor(intent);
    try {
      await guard(
        () => _api.send<dynamic>(
          'POST',
          '${ApiConfig.v1}/mis/consumos/$redemptionId/opinion',
          body: {
            'etiquetas': [apiTag],
            if (note != null && note.trim().isNotEmpty) 'comentario': note.trim(),
          },
          idempotencyKey: key,
        ),
      );
      _idempotency.done(intent);
      eventsService.track(
        'comensal.opinion_enviada',
        props: {
          'etiqueta': apiTag,
          'con_nota': note != null && note.trim().isNotEmpty,
        },
      );
      return true;
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 409) {
        _idempotency.done(intent);
      }
      rethrow;
    }
  }

  @override
  Future<bool> dismissFeedback(String redemptionId) async {
    final intent = 'opinion-descartar:$redemptionId';
    final key = _idempotency.keyFor(intent);
    try {
      await guard(
        () => _api.send<dynamic>(
          'POST',
          '${ApiConfig.v1}/mis/consumos/$redemptionId/opinion/descartar',
          idempotencyKey: key,
        ),
      );
      _idempotency.done(intent);
      eventsService.track('comensal.opinion_descartada');
      return true;
    } on ApiException catch (e) {
      if (e.status == 404 ||
          e.status == 409 ||
          e.code == 'OPINION_YA_ENVIADA' ||
          e.code == 'OPINION_VENCIDA' ||
          e.code == 'CONSUMO_REVERTIDO') {
        _idempotency.done(intent);
        return true;
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // C7 / C9 · Mesas compartidas (Fase 5)
  // ---------------------------------------------------------------------------

  @override
  Future<SharedTable> openSharedTable({
    required String restaurantId,
    required String time,
    int partySize = 2,
    bool takeaway = false,
    TableMode mode = TableMode.eachOwn,
  }) async {
    final normalizedPartySize = partySize < 2 ? 2 : partySize;
    final nowUtc = DateTime.now().toUtc();
    var arrivalUtc = EcuadorTime.todayAtUtc(time);
    if (!arrivalUtc.isAfter(nowUtc)) {
      arrivalUtc = nowUtc.add(const Duration(minutes: 15));
    } else if (arrivalUtc.difference(nowUtc) > const Duration(hours: 11)) {
      arrivalUtc = nowUtc.add(const Duration(hours: 11));
    }

    final apiMode = mode == TableMode.hostPays ? 'INVITO_YO' : 'CADA_UNO';
    final intent =
        'mesa-open:$restaurantId:$time:$apiMode:$takeaway:$normalizedPartySize';
    final key = _idempotency.keyFor(intent);
    try {
      final res = await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/mis/mesas',
          body: {
            'restaurante': restaurantId,
            'horaLlegada': arrivalUtc.toIso8601String(),
            'modo': apiMode,
            'paraLlevar': takeaway,
          },
          idempotencyKey: key,
        ),
      );
      _idempotency.done(intent);
      final rawId = (res?['id'] ?? '').toString();
      if (rawId.isNotEmpty) {
        _tablePrefsById[rawId] = (
          partySize: normalizedPartySize,
          takeaway: takeaway,
        );
      }
      final table = await _mapMesaResponseToSharedTable(
        res ?? const {},
        overridePartySize: normalizedPartySize,
        overrideTakeaway: takeaway,
      );
      eventsService.track(
        'comensal.mesa_abierta',
        restaurantId: restaurantId,
        props: {
          'hora': table.time,
          'personas': table.effectivePartySize,
          'para_llevar': table.takeaway,
        },
      );
      return table;
    } on ApiException catch (e) {
      if (e.status == 400 || e.status == 404 || e.status == 409) {
        _idempotency.done(intent);
      }
      rethrow;
    }
  }

  @override
  Future<SharedTable?> getSharedTable(String tableId) async {
    try {
      final res = await guard(
        () => _api.getMap('${ApiConfig.v1}/mis/mesas/$tableId'),
      );
      final estado = (res['estado'] ?? '').toString();
      if (estado == 'FINALIZADA' || estado == 'CANCELADA') {
        return null;
      }
      return await _mapMesaResponseToSharedTable(res);
    } on ApiException catch (e) {
      if (e.status != 404 && e.status != 403 && e.code != 'MESA_NO_ENCONTRADA') {
        rethrow;
      }
    }

    // Si aún no es miembro o llegó por enlace profundo, consulta la invitación pública.
    try {
      final inv = await guard(
        () => _api.getMap(
          '${ApiConfig.v1}/mesas/invitacion/$tableId',
          auth: false,
        ),
      );
      final estado = (inv['estado'] ?? '').toString();
      final motivo = inv['motivo']?.toString();
      if (estado == 'FINALIZADA' ||
          estado == 'CANCELADA' ||
          motivo == 'MESA_CERRADA' ||
          motivo == 'MESA_VENCIDA') {
        return null;
      }
      if (motivo == 'YA_ERES_MIEMBRO') {
        try {
          final mine = await guard(
            () => _api.getMap('${ApiConfig.v1}/mis/mesas/$tableId'),
          );
          return await _mapMesaResponseToSharedTable(mine);
        } on ApiException {
          // Si falló la vista privada, continúa con el detalle de invitación.
        }
      }
      return await _mapInvitacionToSharedTable(inv);
    } on ApiException catch (e) {
      if (e.status == 404 || e.code == 'MESA_NO_ENCONTRADA') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<SharedTable> setTableMode(String tableId, TableMode mode) async {
    // TODO(backend): B-12a — No existe PATCH /v1/mis/mesas/{id} para cambiar el modo tras crear la mesa.
    throw ApiException(
      status: 501,
      code: 'MODO_MESA_NO_EDITABLE',
      overrideMessage:
          'Cambiar quién paga después de abrir la mesa no está disponible todavía.',
    );
  }

  @override
  Future<SharedTable> notifyKitchen(String tableId) async {
    // TODO(backend): B-12b — No existe endpoint para marcar "en camino" / "avisar a cocina" post-creación.
    throw ApiException(
      status: 501,
      code: 'AVISAR_COCINA_NO_DISPONIBLE',
      overrideMessage: 'Avisar a cocina aún no está disponible.',
    );
  }

  @override
  Future<SharedTable> joinTable(
    String tableId, {
    required String name,
    required String soup,
    required String main,
    required bool takeaway,
  }) async {
    // TODO(backend): B-12c — POST /v1/mesas/invitacion/{id}/unirse solo acepta { paraLlevar } (sin selección de platos ni nombre libre).
    final intent = 'mesa-join:$tableId:$takeaway';
    final key = _idempotency.keyFor(intent);
    try {
      final res = await guard(
        () => _api.send<Map<String, dynamic>>(
          'POST',
          '${ApiConfig.v1}/mesas/invitacion/$tableId/unirse',
          body: {'paraLlevar': takeaway},
          idempotencyKey: key,
        ),
      );
      _idempotency.done(intent);
      final table = await _mapMesaResponseToSharedTable(res ?? const {});
      eventsService.track(
        'comensal.mesa_unida',
        restaurantId: table.restaurantId,
        props: {'para_llevar': takeaway, 'miembros': table.members.length},
      );
      return table;
    } on ApiException catch (e) {
      if (e.status == 400 || e.status == 404 || e.status == 409) {
        _idempotency.done(intent);
      }
      rethrow;
    }
  }

  @override
  Future<SharedTable> updateTableSelection(
    String tableId, {
    required List<String> lunchDishIds,
    List<({String dishId, int quantity})> extras = const [],
  }) async {
    final cleanLunchIds = lunchDishIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final extrasBody = [
      for (final e in extras)
        if (e.dishId.trim().isNotEmpty && e.quantity > 0)
          {
            'platoId': e.dishId.trim(),
            'cantidad': e.quantity,
          },
    ];
    final res = await guard(
      () => _api.send<Map<String, dynamic>>(
        'PUT',
        '${ApiConfig.v1}/mis/mesas/$tableId/seleccion',
        body: {
          'almuerzo': {
            'platos': cleanLunchIds,
          },
          'extras': extrasBody,
        },
      ),
    );
    if (res != null && (res['id'] ?? '').toString().isNotEmpty) {
      return _mapMesaResponseToSharedTable(res);
    }
    final refreshed = await getSharedTable(tableId);
    if (refreshed != null) return refreshed;
    throw ApiException(status: 404, code: 'MESA_NO_ENCONTRADA');
  }

  /// Cancela una mesa compartida abierta (solo anfitrión, antes de validar en caja).
  @override
  Future<void> cancelSharedTable(String tableId) async {
    await guard(
      () => _api.send<Map<String, dynamic>>(
        'POST',
        '${ApiConfig.v1}/mis/mesas/$tableId/cancelar',
      ),
    );
    _tablePrefsById.remove(tableId);
    eventsService.track('comensal.mesa_cancelada');
  }

  Future<SharedTable> _mapMesaResponseToSharedTable(
    Map<String, dynamic> json, {
    int? overridePartySize,
    bool? overrideTakeaway,
  }) async {
    final id = (json['id'] ?? '').toString();
    final invitacion = (json['invitacion'] ?? id).toString();
    final rest = _asMap(json['restaurante']);
    final restId = (rest['id'] ?? '').toString();
    final restSlug = (rest['slug'] ?? '').toString();
    if (restId.isNotEmpty && restSlug.isNotEmpty) {
      _slugById[restId] = restSlug;
    }
    final cachedRest = await _resolveRestaurantForTable(restId, restSlug);

    final anfitrion = _asMap(json['anfitrion']);
    final hostName = (anfitrion['nombre'] ?? '').toString();
    final hora = DateTime.tryParse((json['horaLlegada'] ?? '').toString());
    final modoRaw = (json['modo'] ?? 'CADA_UNO').toString().toUpperCase();
    final estado = (json['estado'] ?? 'ABIERTA').toString().toUpperCase();

    final members = <TableMember>[];
    for (final raw in _asListOfMaps(json['miembros'])) {
      final nombre = (raw['nombre'] ?? '').toString();
      final selection = _parseMemberSelection(raw['seleccion']);
      members.add(TableMember(
        id: raw['soyYo'] == true ? 'self' : nombre,
        name: nombre,
        isHost: raw['esAnfitrion'] == true,
        takeaway: raw['paraLlevar'] == true,
        soup: selection?.soup,
        main: selection?.main,
        selection: selection,
      ));
    }

    final savedPrefs = _tablePrefsById[id];
    final inferredParty = _asInt(json['personas']) ??
        overridePartySize ??
        savedPrefs?.partySize ??
        members.length;
    final partySize = inferredParty < 2 ? 2 : inferredParty;
    final takeaway = overrideTakeaway ??
        (json['paraLlevar'] == true) ||
        members.any((m) => m.takeaway) ||
        (savedPrefs?.takeaway ?? false);

    return _buildSharedTable(
      id: id,
      invitacion: invitacion,
      restaurantId: restId,
      restaurantName: (rest['nombre'] ?? cachedRest?.name ?? '').toString(),
      hostName: hostName,
      time: _formatEcuadorTime(hora),
      mode: modoRaw == 'INVITO_YO' ? TableMode.hostPays : TableMode.eachOwn,
      members: members,
      onTheWay: estado == 'EN_CAMINO' || estado == 'EN_MESA' || estado == 'EN_PREPARACION',
      status: estado,
      scheduledAt: hora?.toUtc(),
      partySize: partySize,
      takeaway: takeaway,
      restaurant: cachedRest,
    );
  }

  /// Parsea `miembros[].seleccion` respetando estrictamente `null` (nunca infiere platos ajenos).
  TableMemberSelection? _parseMemberSelection(Object? raw) {
    if (raw == null || raw is! Map) return null;
    final map = _asMap(raw);
    String? soup;
    String? main;
    final lunchIds = <String>[];
    final lunchNames = <String>[];

    void consumeLunchList(List list) {
      for (final entry in list) {
        if (entry is Map) {
          final p = _asMap(entry);
          final id = (p['id'] ?? p['platoId'] ?? '').toString().trim();
          final name = (p['nombre'] ?? '').toString().trim();
          final sec = (p['seccion'] ?? '').toString().toUpperCase();
          if (id.isNotEmpty) lunchIds.add(id);
          if (name.isNotEmpty) {
            lunchNames.add(name);
            if (sec == 'SOPA') {
              soup ??= name;
            } else if (sec == 'FUERTE' || sec == 'SEGUNDO' || sec == 'PLATO_FUERTE') {
              main ??= name;
            } else {
              if (main != null) {
                soup ??= name;
              }
              main ??= name;
            }
          }
        } else if (entry is String && entry.trim().isNotEmpty) {
          final val = entry.trim();
          lunchIds.add(val);
        }
      }
    }

    final almuerzo = map['almuerzo'];
    if (almuerzo is Map) {
      final aMap = _asMap(almuerzo);
      if (aMap['platos'] is List) {
        consumeLunchList(aMap['platos'] as List);
      }
      final sRaw = aMap['sopa']?.toString().trim();
      final mRaw = (aMap['segundo'] ?? aMap['fuerte'])?.toString().trim();
      if (sRaw != null && sRaw.isNotEmpty) soup ??= sRaw;
      if (mRaw != null && mRaw.isNotEmpty) main ??= mRaw;
    } else if (almuerzo is List) {
      consumeLunchList(almuerzo);
    }

    final extras = <TableSelectionExtra>[];
    if (map['extras'] is List) {
      for (final entry in map['extras'] as List) {
        if (entry is Map) {
          final ex = _asMap(entry);
          final platoMap = ex['plato'] is Map ? _asMap(ex['plato']) : const <String, dynamic>{};
          final dishId = (ex['platoId'] ?? platoMap['id'] ?? ex['id'] ?? '').toString().trim();
          final name = (ex['nombre'] ?? platoMap['nombre'] ?? '').toString().trim();
          final qty = _asInt(ex['cantidad']) ?? 1;
          if (name.isNotEmpty || dishId.isNotEmpty) {
            extras.add(
              TableSelectionExtra(
                dishId: dishId,
                name: name.isNotEmpty ? name : dishId,
                quantity: qty < 1 ? 1 : qty,
              ),
            );
          }
        } else if (entry is String && entry.trim().isNotEmpty) {
          extras.add(
            TableSelectionExtra(
              dishId: entry.trim(),
              name: entry.trim(),
              quantity: 1,
            ),
          );
        }
      }
    }

    return TableMemberSelection(
      lunchDishes: lunchNames.isNotEmpty ? lunchNames : lunchIds,
      soup: soup,
      main: main,
      extras: extras,
    );
  }

  Future<SharedTable> _mapInvitacionToSharedTable(
    Map<String, dynamic> json,
  ) async {
    final id = (json['id'] ?? '').toString();
    final rest = _asMap(json['restaurante']);
    final restId = (rest['id'] ?? '').toString();
    final restSlug = (rest['slug'] ?? '').toString();
    if (restId.isNotEmpty && restSlug.isNotEmpty) {
      _slugById[restId] = restSlug;
    }
    final cachedRest = await _resolveRestaurantForTable(restId, restSlug);

    final anfitrion = _asMap(json['anfitrion']);
    final hostName = (anfitrion['nombre'] ?? '').toString();
    final hora = DateTime.tryParse((json['horaLlegada'] ?? '').toString());
    final modoRaw = (json['modo'] ?? 'CADA_UNO').toString().toUpperCase();
    final estado = (json['estado'] ?? 'ABIERTA').toString().toUpperCase();
    final count = (_asInt(json['personas']) ?? 1).clamp(1, 50);

    final members = <TableMember>[
      TableMember(id: 'host', name: hostName, isHost: true),
      for (var i = 1; i < count; i++)
        TableMember(id: 'guest-$i', name: 'Acompañante $i', isHost: false),
    ];

    final savedPrefs = _tablePrefsById[id];
    final partySize = count > 2 ? count : (savedPrefs?.partySize ?? 2);
    final takeaway = (json['paraLlevar'] == true) || (savedPrefs?.takeaway ?? false);

    return _buildSharedTable(
      id: id,
      invitacion: id,
      restaurantId: restId,
      restaurantName: (rest['nombre'] ?? cachedRest?.name ?? '').toString(),
      hostName: hostName,
      time: _formatEcuadorTime(hora),
      mode: modoRaw == 'INVITO_YO' ? TableMode.hostPays : TableMode.eachOwn,
      members: members,
      onTheWay: estado == 'EN_CAMINO' || estado == 'EN_MESA' || estado == 'EN_PREPARACION',
      status: estado,
      scheduledAt: hora?.toUtc(),
      partySize: partySize,
      takeaway: takeaway,
      restaurant: cachedRest,
    );
  }

  SharedTable _buildSharedTable({
    required String id,
    required String invitacion,
    required String restaurantId,
    required String restaurantName,
    required String hostName,
    required String time,
    required TableMode mode,
    required List<TableMember> members,
    required bool onTheWay,
    required String status,
    DateTime? scheduledAt,
    required int partySize,
    required bool takeaway,
    Restaurant? restaurant,
  }) {
    final soups = restaurant?.todayMenu
            .where((m) => m.category == 'Sopa' && !m.isSoldOut)
            .map((m) => m.name)
            .toList() ??
        const <String>[];
    final mains = restaurant?.todayMenu
            .where((m) => m.category == 'Plato Fuerte' && !m.isSoldOut)
            .map(
              (m) => TableDish(
                id: m.id,
                name: m.name,
                price: m.price ?? restaurant.singleLunchPrice,
                imageUrl: m.imageUrl,
                isVeggie: m.isVeggie,
              ),
            )
            .toList() ??
        const <TableDish>[];

    return SharedTable(
      id: id,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      hostName: hostName,
      time: time,
      qrPayload: 'BCD-MESA-$id',
      shareUrl: 'bocadoo://mesa/$invitacion',
      mode: mode,
      members: members,
      onTheWay: onTheWay,
      status: status,
      scheduledAt: scheduledAt,
      partySize: partySize < 2 ? 2 : partySize,
      takeaway: takeaway,
      occupancyLabel: _mapOccupancyLabel(restaurant?.occupancy),
      soups: soups,
      mains: mains,
      takeawaySurcharge: restaurant?.takeawaySurcharge ?? 0.25,
    );
  }

  Future<Restaurant?> _resolveRestaurantForTable(
    String restaurantId,
    String slug,
  ) async {
    final cached = _restaurantCache[restaurantId];
    if (cached != null && cached.todayMenu.isNotEmpty) return cached;
    final resolvedSlug = slug.isNotEmpty ? slug : (_slugById[restaurantId] ?? '');
    if (resolvedSlug.isEmpty) return cached;
    try {
      final results = await Future.wait([
        guard(
          () => _api.getMap(
            '${ApiConfig.v1}/restaurantes/$resolvedSlug',
            auth: false,
          ),
        ),
        _fetchOffersSafe(resolvedSlug),
      ]);
      final detail = results[0] as Map<String, dynamic>;
      final offersRaw = results[1] as List<Map<String, dynamic>>;
      return _mapDetailToRestaurant(detail, offersRaw, null);
    } catch (_) {
      return cached;
    }
  }

  String _mapOccupancyLabel(String? occupancy) => switch (occupancy) {
        'LLENO' => 'Lleno',
        'MOVIDO' => 'Con gente',
        _ => 'Tranquilo',
      };

  // ---------------------------------------------------------------------------
  // Mapeos internos y helpers
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _fetchOffersSafe(String slug) async {
    try {
      final res = await guard(
        () => _api.getMap(
          '${ApiConfig.v1}/restaurantes/$slug/ofertas',
          auth: false,
        ),
      );
      return _asListOfMaps(res['items']);
    } catch (_) {
      return const [];
    }
  }

  Future<LatLng?> _resolveUserPosition() async {
    if (_positionResolved && _cachedUserPosition != null) {
      return _cachedUserPosition;
    }
    _positionResolved = true;

    final savedLat = await _profileStore.getLat();
    final savedLng = await _profileStore.getLng();
    if (LocationService.isValidCoordinate(savedLat, savedLng)) {
      final saved = LatLng(savedLat!, savedLng!);
      if (LocationService.meters(saved, LocationService.fallbackPuce) <= 1000000) {
        _cachedUserPosition = saved;
        return _cachedUserPosition;
      }
    }

    final (_, current) = await LocationService.resolveWithFallback();
    _cachedUserPosition = current;
    return _cachedUserPosition;
  }

  Restaurant _mapCardToRestaurant(
    Map<String, dynamic> json,
    LatLng? userPos,
  ) {
    final id = (json['id'] ?? '').toString();
    final slug = (json['slug'] ?? '').toString();
    if (id.isNotEmpty && slug.isNotEmpty) {
      _slugById[id] = slug;
    }

    final prev = _restaurantCache[id];
    final rawLat = _asDouble(json['latitud']);
    final rawLng = _asDouble(json['longitud']);
    final validRestCoords = LocationService.isValidCoordinate(rawLat, rawLng);
    final lat = validRestCoords ? rawLat : null;
    final lng = validRestCoords ? rawLng : null;
    final distanceMeters = _computeDistanceMeters(userPos, lat, lng);
    final distanceKm = distanceMeters != null
        ? (distanceMeters / 100.0).round() / 10.0
        : 99.0;

    final tags = _asStringList(json['etiquetas']);
    final categories = <String>{
      'Todos',
      for (final t in tags) _capitalizeTag(t),
    }.toList();
    final zona = _asMap(json['zona']);
    final logoUrl = json['logoUrl']?.toString();
    final desc = (json['descripcionCorta'] ?? '').toString().trim();
    final ocupacion =
        json['ocupacion'] is Map ? _asMap(json['ocupacion']) : const <String, dynamic>{};
    final nivelRaw = ocupacion['nivel']?.toString().toUpperCase();
    final estadoRaw = (json['estado'] ?? 'ACTIVO').toString().toUpperCase();
    final isPausedFromServer =
        estadoRaw == 'PAUSADO' || estadoRaw == 'CERRADO';
    final isOpenFromServer = !isPausedFromServer && nivelRaw != 'CERRADO';
    final openNow = json['abiertoAhora'] is bool
        ? json['abiertoAhora'] as bool
        : isOpenFromServer;
    final menuSoldOut = json['menuAgotado'] == true;
    final mappedOccupancy = !isOpenFromServer
        ? 'CERRADO'
        : (ocupacion['lleno'] == true ? 'LLENO' : _mapOccupancy(nivelRaw));
    final fullRaw = ocupacion['llenoHasta'] ??
        ocupacion['hasta'] ??
        json['llenoManualHasta'];
    final fullUntil = fullRaw is String && fullRaw.isNotEmpty
        ? DateTime.tryParse(fullRaw)?.toLocal()
        : null;
    final singlePrice =
        Money.fromCents(_asInt(json['precioSueltoCentavos']) ?? 300);
    final rawRecargo = _asInt(json['recargoParaLlevarCentavos']);
    final seats = _asInt(json['puestos']) ?? prev?.seats;

    final mapped = Restaurant(
      id: id,
      slug: slug.isEmpty ? prev?.slug : slug,
      name: (json['nombre'] ?? '').toString(),
      description: desc,
      address: (json['direccion'] ?? '').toString(),
      zone: (zona['nombre'] ?? '').toString(),
      distanceKm: distanceKm,
      distanceMeters: distanceMeters,
      imageUrl: logoUrl ?? '',
      logoUrl: logoUrl,
      singleLunchPrice: singlePrice,
      planLunchPrice: prev?.planLunchPrice,
      occupancy: mappedOccupancy,
      isOpen: isOpenFromServer,
      status: estadoRaw,
      openNow: openNow,
      menuSoldOut: menuSoldOut,
      categories: categories,
      todayMenu: prev?.todayMenu ?? const [],
      featuredDish: (prev != null && prev.featuredDish.isNotEmpty)
          ? prev.featuredDish
          : (desc.isNotEmpty ? desc : 'Menú del día'),
      hasPlan: prev?.hasPlan ?? false,
      offers: prev?.offers ?? const [],
      schedule: prev?.schedule ?? '11:30 - 15:30',
      tags: tags,
      juice: prev?.juice ?? '',
      dessert: prev?.dessert ?? '',
      takeawaySurcharge: rawRecargo != null
          ? Money.fromCents(rawRecargo)
          : (prev?.takeawaySurcharge ?? 0.25),
      latitude: lat,
      longitude: lng,
      fullUntil: fullUntil,
      seats: seats,
    );

    if (menuSoldOut) {
      _todayMenuAvailabilityByRest[id] = MenuAvailabilityState.agotadoTotal;
      _todayMenuPublishedByRest[id] = false;
    }
    _restaurantCache[id] = mapped;
    return mapped;
  }

  Restaurant _mapDetailToRestaurant(
    Map<String, dynamic> json,
    List<Map<String, dynamic>> offersRaw,
    LatLng? userPos,
  ) {
    final base = _mapCardToRestaurant(json, userPos);

    final menuHoy = _asMap(json['menuHoy']);
    final published = menuHoy['publicado'] == true;
    final menuItems = <MenuItem>[];
    if (published) {
      for (final sec in _asListOfMaps(menuHoy['secciones'])) {
        final section = (sec['seccion'] ?? '').toString().toUpperCase();
        for (final plato in _asListOfMaps(sec['platos'])) {
          final tags = _asStringList(plato['etiquetas'])
              .map((t) => t.toLowerCase())
              .toList();
          final category = _mapMenuCategory(section, tags, plato['precioCentavos']);
          if (category == null) continue;
          final priceCents = _asInt(plato['precioCentavos']);
          menuItems.add(MenuItem(
            id: (plato['id'] ?? '').toString(),
            name: (plato['nombre'] ?? '').toString(),
            category: category,
            price: priceCents == null ? null : Money.fromCents(priceCents),
            isSoldOut: plato['agotado'] == true,
            imageUrl: plato['fotoUrl']?.toString(),
            isVeggie: tags.any((t) => t.contains('veg')),
          ));
        }
      }
    }

    final planesRaw = _asListOfMaps(json['planes']);
    final plans = <PlanTemplate>[];
    double? bestPerLunch;
    for (final p in planesRaw) {
      final lunches = (_asInt(p['almuerzos']) ?? 1).clamp(1, 500);
      final priceCents = _asInt(p['precioCentavos']) ?? 0;
      final tpl = PlanTemplate(
        id: (p['id'] ?? '').toString(),
        restaurantId: base.id,
        type: _capitalizeTag((p['tipo'] ?? 'Mensual').toString()),
        name: (p['nombre'] ?? '').toString(),
        lunches: lunches,
        priceCents: priceCents,
        validityDays: _asInt(p['vigenciaDias']) ?? 30,
      );
      plans.add(tpl);
      _planCache[tpl.id] = tpl;
      _planIncludesByName[tpl.name] = _asStringList(p['incluye']);
      final unitDollars = Money.fromCents((priceCents / lunches).round());
      if (bestPerLunch == null || unitDollars < bestPerLunch) {
        bestPerLunch = unitDollars;
      }
    }
    _plansByRestaurantCache[base.id] = plans;

    final offers = <RestaurantOffer>[];
    for (final o in offersRaw) {
      final estado = (o['estado'] ?? '').toString();
      if (estado == 'CERRADA' || estado == 'EXPIRADA') continue;
      final discount = _asInt(o['descuentoPorcentaje']) ?? 0;
      final title = (o['titulo'] ?? '').toString();
      final stockLeft = _asInt(o['stockRestante']) ?? 0;
      offers.add(RestaurantOffer(
        id: (o['id'] ?? '').toString(),
        restaurantId: base.id,
        title: title,
        badge: discount > 0 ? '-$discount% · $title' : title,
        price: _asInt(o['precioCentavos']) != null
            ? Money.fromCents(_asInt(o['precioCentavos'])!)
            : null,
        originalPrice: _asInt(o['precioOriginalCentavos']) != null
            ? Money.fromCents(_asInt(o['precioOriginalCentavos'])!)
            : null,
        slotsLeft: stockLeft,
        availableNow: estado == 'VIGENTE' && stockLeft > 0,
        appliesToday: estado == 'VIGENTE',
        reservable: false,
        endsAt: DateTime.tryParse((o['expiraEn'] ?? '').toString()),
      ));
    }

    final horarios = _asListOfMaps(json['horarios']);
    final schedule = _formatTodaySchedule(horarios);

    final mains = menuItems.where((m) => m.category == 'Plato Fuerte').toList();
    final soups = menuItems.where((m) => m.category == 'Sopa').toList();
    final drinks = menuItems.where((m) => m.category == 'Bebida').toList();
    final desserts = menuItems.where((m) => m.category == 'Postre').toList();

    final featuredMain = mains.where((m) => !m.isSoldOut).firstOrNull ??
        mains.firstOrNull ??
        soups.where((m) => !m.isSoldOut).firstOrNull ??
        soups.firstOrNull;

    final detailed = Restaurant(
      id: base.id,
      slug: base.slug,
      name: base.name,
      description: base.description,
      address: base.address,
      zone: base.zone,
      rating: base.rating,
      distanceKm: base.distanceKm,
      distanceMeters: base.distanceMeters,
      imageUrl: base.imageUrl,
      logoUrl: base.logoUrl,
      singleLunchPrice: base.singleLunchPrice,
      planLunchPrice: bestPerLunch ?? base.planLunchPrice,
      occupancy: base.occupancy,
      isOpen: base.isOpen,
      status: base.status,
      openNow: base.openNow,
      menuSoldOut: base.menuSoldOut,
      categories: base.categories,
      todayMenu: menuItems,
      featuredDish: featuredMain?.name ?? base.featuredDish,
      hasPlan: plans.isNotEmpty,
      offers: offers,
      schedule: schedule,
      tags: base.tags,
      juice: drinks.where((m) => !m.isSoldOut).firstOrNull?.name ??
          drinks.firstOrNull?.name ??
          '',
      dessert: desserts.where((m) => !m.isSoldOut).firstOrNull?.name ??
          desserts.firstOrNull?.name ??
          '',
      takeawaySurcharge: base.takeawaySurcharge,
      latitude: base.latitude,
      longitude: base.longitude,
      fullUntil: base.fullUntil,
      seats: base.seats,
    );

    final availability = base.menuSoldOut
        ? MenuAvailabilityState.agotadoTotal
        : ((!published || menuItems.isEmpty)
            ? MenuAvailabilityState.sinPublicar
            : detailed.menuAvailabilityState);
    _todayMenuAvailabilityByRest[base.id] = availability;
    _todayMenuPublishedByRest[base.id] =
        availability == MenuAvailabilityState.disponible;
    _restaurantCache[base.id] = detailed;
    return detailed;
  }

  ActiveOrder _mapPedidoToActiveOrder(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final numero = (json['numero'] ?? '').toString();
    if (id.isNotEmpty && numero.isNotEmpty) {
      _orderIdByNumber[numero] = id;
    }

    final rest = _asMap(json['restaurante']);
    final restId = (rest['id'] ?? '').toString();
    final cachedRest = _restaurantCache[restId];

    final almuerzo = json['almuerzo'] is Map
        ? _asMap(json['almuerzo'])
        : null;
    final platos = almuerzo != null
        ? _asListOfMaps(almuerzo['platos'])
        : const <Map<String, dynamic>>[];

    String? soup;
    String? main;
    final parts = <String>[];
    for (final p in platos) {
      final name = (p['nombre'] ?? '').toString();
      final sec = (p['seccion'] ?? '').toString().toUpperCase();
      if (sec == 'SOPA' && soup == null) soup = name;
      if (sec == 'FUERTE' && main == null) main = name;
      if (name.isNotEmpty) parts.add(name);
    }

    final extras = _asListOfMaps(json['extras']);
    for (final e in extras) {
      final name = (e['nombre'] ?? '').toString();
      if (name.isNotEmpty) parts.add(name);
    }

    final estado = (json['estado'] ?? 'EN_CAMINO').toString().toUpperCase();
    final status = switch (estado) {
      'CANJEADA' => 'LISTO',
      'SERVIDA' || 'ENTREGADA' || 'FINALIZADA' => 'ENTREGADO',
      _ => 'PREPARANDO',
    };

    final takeaway = json['paraLlevar'] == true;
    final hasPlan = almuerzo?['cubiertoPorPlan'] == true;
    final recargoCents = _asInt(json['recargoLlevarCentavos']) ??
        Money.toCents(cachedRest?.takeawaySurcharge ?? 0.25);
    final rawBaseCents = _asInt(almuerzo?['precioCentavos']) ?? 0;
    final baseCents = rawBaseCents > 0
        ? rawBaseCents
        : Money.toCents(cachedRest?.singleLunchPrice ?? 3.00);
    final rawTotalCents = _asInt(json['totalCentavos']) ?? 0;
    final expectedNoPlanCents =
        baseCents + (takeaway ? recargoCents : 0);
    final resolvedTotalCents = hasPlan
        ? 0
        : (rawTotalCents >= expectedNoPlanCents
            ? rawTotalCents
            : expectedNoPlanCents);

    final orderNum = numero.isEmpty ? id : numero;
    final rawEta = json['horaEstimada'] ?? json['horaLlegada'];
    final etaDt = rawEta != null ? DateTime.tryParse(rawEta.toString()) : null;
    final createdDt = DateTime.tryParse((json['creadoEn'] ?? '').toString());
    final etaLabel = _estimatedArrivalByOrderNumber[orderNum] ??
        (etaDt != null
            ? _formatEcuadorTime(etaDt)
            : (createdDt != null
                ? _formatEcuadorTime(createdDt.toUtc().add(const Duration(minutes: 15)))
                : null));

    return ActiveOrder(
      id: id.isEmpty ? null : id,
      restaurantId: restId.isEmpty ? null : restId,
      orderNumber: orderNum,
      status: status,
      restaurantName: (rest['nombre'] ?? '').toString(),
      qrPayload: (json['qr'] ?? id).toString(),
      detail: parts.join(' · '),
      soup: soup,
      main: main,
      takeaway: takeaway,
      takeawaySurcharge: Money.fromCents(recargoCents),
      singleLunchPrice: Money.fromCents(baseCents),
      basePriceCents: baseCents,
      takeawaySurchargeCents: recargoCents,
      totalCents: resolvedTotalCents,
      estimatedArrivalLabel: etaLabel,
      hasPlan: hasPlan,
      expiresAt: DateTime.tryParse((json['venceEn'] ?? '').toString()),
      paidAmount:
          status == 'ENTREGADO' ? Money.fromCents(resolvedTotalCents) : null,
    );
  }

  ActivityItem _mapConsumoToActivity(Map<String, dynamic> item) {
    final rest = _asMap(item['restaurante']);
    final plan = _asMap(item['plan']);
    final reverted = item['revertido'] == true;
    final takeaway = item['paraLlevar'] == true;
    final dt = DateTime.tryParse((item['fecha'] ?? '').toString());
    final when = _formatEcuadorDateShort(
      dt,
      fallbackDate: item['fechaLocal']?.toString(),
    );
    final planName = (plan['nombre'] ?? 'Almuerzo').toString();
    final detail = '$when · $planName${takeaway ? ' · Para llevar' : ''}';

    return ActivityItem(
      id: (item['id'] ?? '').toString(),
      name: (rest['nombre'] ?? '').toString(),
      detail: detail,
      value: reverted ? '+1 devuelto' : '-1 almuerzo',
      positive: reverted,
      kind: 'lunch',
    );
  }

  ConsumptionRecord _mapConsumoToRecord(
    Map<String, dynamic> item,
    String passId,
  ) {
    final rest = _asMap(item['restaurante']);
    final plan = _asMap(item['plan']);
    final reverted = item['revertido'] == true;
    final takeaway = item['paraLlevar'] == true;
    final planName = (plan['nombre'] ?? 'Almuerzo').toString();

    return ConsumptionRecord(
      id: (item['id'] ?? '').toString(),
      passId: (plan['id'] ?? passId).toString(),
      restaurantName: (rest['nombre'] ?? '').toString(),
      restaurantId: (rest['id'] ?? '').toString(),
      date: DateTime.tryParse((item['fecha'] ?? '').toString()) ?? DateTime.now(),
      description: '$planName${takeaway ? ' · Para llevar' : ''}',
      lunchesUsed: 1,
      remainingAfter: 0,
      status: reverted ? 'Anulado' : 'Validado',
    );
  }

  String _computePassStatus({
    required int remaining,
    required int? daysLeft,
    required DateTime expiresAt,
  }) {
    if (remaining <= 0) return 'AGOTADO';
    final effectiveDays =
        daysLeft ?? expiresAt.difference(DateTime.now()).inDays;
    if (effectiveDays < 0 || DateTime.now().isAfter(expiresAt)) {
      return 'VENCIDO';
    }
    if (remaining <= 3 || effectiveDays <= 3) return 'POR_VENCER';
    return 'ACTIVO';
  }

  DateTime? _parseEndOfDayEcuador(String? ymd) {
    if (ymd == null || ymd.isEmpty) return null;
    return DateTime.tryParse('${ymd.trim()}T23:59:59-05:00');
  }

  int? _computeDistanceMeters(LatLng? userPos, double? lat, double? lng) {
    if (!LocationService.isValidCoordinate(lat, lng)) return null;
    final origin = userPos ?? LocationService.fallbackPuce;
    return LocationService.meters(origin, LatLng(lat!, lng!));
  }

  String _mapOccupancy(String? nivel) => switch (nivel?.toUpperCase()) {
        'CERRADO' => 'CERRADO',
        'LLENO' => 'LLENO',
        'MODERADO' || 'MOVIDO' || 'CONCURRIDO' => 'MOVIDO',
        _ => 'LIBRE',
      };

  String? _mapMenuCategory(
    String section,
    List<String> lowerTags,
    Object? precioCentavos,
  ) {
    return switch (section) {
      'SOPA' => 'Sopa',
      'FUERTE' || 'SEGUNDO' || 'PLATO_FUERTE' => 'Plato Fuerte',
      'BEBIDA' || 'JUGO' => 'Bebida',
      'POSTRE' => 'Postre',
      'ADICIONAL' =>
        (lowerTags.contains('desayuno') && precioCentavos != null)
            ? 'Desayuno'
            : null,
      _ => null,
    };
  }

  String _formatTodaySchedule(List<Map<String, dynamic>> horarios) {
    if (horarios.isEmpty) return '11:30 - 15:30';
    final todayIso = EcuadorTime.now().weekday;
    final match = horarios.where((h) => _asInt(h['diaSemana']) == todayIso).firstOrNull ??
        horarios.first;
    final open = (match['abre'] ?? '11:30').toString();
    final close = (match['cierra'] ?? '15:30').toString();
    return '$open - $close';
  }

  String _formatEcuadorTime(DateTime? utc) {
    if (utc == null) return '12:30';
    final ec = utc.toUtc().subtract(const Duration(hours: 5));
    return '${ec.hour.toString().padLeft(2, '0')}:${ec.minute.toString().padLeft(2, '0')}';
  }

  String _formatEcuadorDateShort(DateTime? utc, {String? fallbackDate}) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    if (utc != null) {
      final ec = utc.toUtc().subtract(const Duration(hours: 5));
      final nowEc = EcuadorTime.now();
      final isToday =
          ec.year == nowEc.year && ec.month == nowEc.month && ec.day == nowEc.day;
      final hm =
          '${ec.hour.toString().padLeft(2, '0')}:${ec.minute.toString().padLeft(2, '0')}';
      if (isToday) return 'Hoy, $hm';
      return '${ec.day} ${months[ec.month - 1]}, $hm';
    }
    return fallbackDate ?? '';
  }

  String _capitalizeTag(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return '';
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  List<Map<String, dynamic>> _asListOfMaps(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(_asMap).toList();
  }

  List<String> _asStringList(Object? value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
