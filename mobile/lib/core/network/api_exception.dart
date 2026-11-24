import 'package:dio/dio.dart';

/// Error normalizado desde respuestas RFC 9457 (`application/problem+json`) o fallos de red.
class ApiException implements Exception {
  ApiException({
    this.status,
    required this.code,
    this.title = '',
    this.detail = '',
    this.requestId,
    this.isNetwork = false,
    this.fieldErrors = const {},
    this._overrideMessage,
  });

  final int? status;
  final String code;
  final String title;

  /// Detalle devuelto en RFC 9457 (`detail` o `message`).
  final String detail;
  final String? requestId;
  final bool isNetwork;

  /// Errores por campo extraídos de respuestas `400 problem+json`.
  final Map<String, String> fieldErrors;
  final String? _overrideMessage;

  factory ApiException.network() =>
      ApiException(code: 'SIN_CONEXION', isNetwork: true);

  static Map<String, String> _parseFieldErrors(Map<dynamic, dynamic> data) {
    final out = <String, String>{};

    void addPair(Object? rawKey, Object? rawVal) {
      final k = rawKey?.toString().trim() ?? '';
      if (k.isEmpty) return;
      String msg = '';
      if (rawVal is List && rawVal.isNotEmpty) {
        msg = rawVal.first.toString().trim();
      } else if (rawVal != null) {
        msg = rawVal.toString().trim();
      }
      if (msg.isNotEmpty) {
        out.putIfAbsent(k, () => msg);
      }
    }

    void parseCollection(Object? raw) {
      if (raw is Map) {
        raw.forEach((k, v) => addPair(k, v));
      } else if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            final field =
                item['field'] ??
                item['campo'] ??
                item['name'] ??
                item['property'] ??
                item['path'];
            final message =
                item['message'] ??
                item['mensaje'] ??
                item['reason'] ??
                item['detail'] ??
                item['error'];
            addPair(field, message);
          }
        }
      }
    }

    parseCollection(data['errors']);
    parseCollection(data['campos']);
    parseCollection(data['fieldErrors']);
    parseCollection(data['invalidParams']);
    parseCollection(data['invalid-params']);
    return out;
  }

  static String _extractDetail(Map<dynamic, dynamic> data) {
    final raw = data['detail'] ?? data['message'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .join('\n');
    }
    return (raw ?? '').toString().trim();
  }

  factory ApiException.fromResponse(Response<dynamic> response) {
    final data = response.data is Map ? response.data as Map : const {};
    return ApiException(
      status: response.statusCode,
      code: (data['code'] ?? 'ERROR_INTERNO').toString(),
      title: (data['title'] ?? data['error'] ?? '').toString().trim(),
      detail: _extractDetail(data),
      requestId: data['requestId']?.toString(),
      fieldErrors: _parseFieldErrors(data),
    );
  }

  String get userMessage => _overrideMessage ?? ErrorMessages.of(this);

  @override
  String toString() =>
      'ApiException(status: $status, code: $code, requestId: $requestId)';
}

/// Traducción estable de códigos RFC 9457 a mensajes claros para Ecuador.
class ErrorMessages {
  ErrorMessages._();

  static String of(ApiException e) {
    if (e.isNetwork) {
      return 'No tienes conexión. Revisa tu internet e inténtalo de nuevo.';
    }
    return _byCode[e.code] ?? _byStatus(e.status);
  }

  static String _byStatus(int? status) => switch (status) {
    400 => 'Revisa los datos e inténtalo de nuevo.',
    401 => 'Tu sesión venció. Entra de nuevo.',
    403 => 'No tienes permiso para hacer esto.',
    404 => 'No encontramos lo que buscabas.',
    409 => 'Esto cambió mientras lo hacías. Actualizamos los datos.',
    422 => 'No pudimos completar esto. Revisa los datos.',
    429 => 'Demasiados intentos. Espera un momento.',
    502 ||
    503 ||
    504 => 'No pudimos conectar con el servidor. Inténtalo en un momento.',
    _ => 'Algo salió mal de nuestro lado. Inténtalo en un momento.',
  };

  static const _byCode = <String, String>{
    // Sesión y registro
    'UNAUTHORIZED': 'Tu sesión venció. Entra de nuevo.',
    'FORBIDDEN': 'No tienes permiso para hacer esto.',
    'CONFLICT': 'Ya existe un registro con esos datos.',
    'REGISTRO_CERRADO': 'El registro de restaurantes está cerrado temporalmente.',
    'TOO_MANY_REQUESTS': 'Demasiados intentos. Espera un momento.',
    'ERROR_INTERNO': 'Algo salió mal de nuestro lado. Inténtalo en un momento.',
    'SERVICE_UNAVAILABLE':
        'El servidor está despertando. Inténtalo en un momento.',
    'SIN_CONEXION':
        'No tienes conexión. Revisa tu internet e inténtalo de nuevo.',
    'SIN_RESTAURANTE': 'Esta cuenta no tiene un restaurante.',
    // Genéricos de datos
    'CURSOR_INVALIDO': 'No pudimos cargar más resultados. Actualiza la lista.',
    'FECHA_INVALIDA': 'La fecha no es válida.',
    'RANGO_INVALIDO': 'El rango de fechas no es válido.',
    'RANGO_MUY_LARGO': 'Elige un rango de fechas más corto.',
    'IDEMPOTENCY_KEY_INVALIDA': 'No pudimos enviar esto. Inténtalo de nuevo.',
    'IDEMPOTENCY_KEY_REUTILIZADA':
        'Esta acción ya se envió. Actualiza para ver el resultado.',
    // Restaurantes
    'RESTAURANTE_NO_ENCONTRADO': 'No encontramos ese restaurante.',
    'RESTAURANTE_NO_DISPONIBLE': 'Este restaurante no está disponible ahora.',
    'RESTAURANTE_PAUSADO': 'Este restaurante está pausado por ahora.',
    'LOCAL_LLENO_SOLO_LLEVAR': 'El salón está lleno ahora. Activa "Para llevar" para continuar con tu pedido.',
    // Pase y almuerzos
    'CAJERO_SOLO_HOY':
        'Solo el dueño puede consultar movimientos de otras fechas.',
    'QR_EXPIRADO': 'El código venció. Pide al comensal que genere y muestre su código actual.',
    'QR_INVALIDO':
        'Este código no pertenece a Bocadoo o no corresponde a este local.',
    'CONSUMO_NO_ENCONTRADO': 'No encontramos ese almuerzo.',
    'CONSUMO_REVERTIDO': 'Ese almuerzo ya se devolvió a tu plan.',
    'EVENTOS_SATURADO':
        'Demasiadas conexiones en tiempo real. Reintentando en un momento.',
    'RECLAMO_VENCIDO': 'Ya pasó el plazo para reclamar este almuerzo.',
    'RECLAMO_YA_EXISTE': 'Ya reclamaste este almuerzo.',
    // Pedidos
    'PEDIDO_VACIO': 'Elige al menos un plato para tu pedido.',
    'ALMUERZO_INVALIDO': 'Elige una sopa y un segundo del menú de hoy.',
    'MENU_NO_PUBLICADO': 'Este local todavía no publicó el menú de hoy.',
    'PEDIDO_ACTIVO': 'Ya tienes un pedido en camino en este local.',
    'PLATO_AGOTADO': 'Uno de los platos se acabó. Elige otro.',
    'PLATO_NO_DISPONIBLE': 'Uno de los platos ya no está disponible.',
    'PLATO_SIN_PRECIO': 'Uno de los platos no se puede pedir por separado.',
    'PEDIDO_NO_ENCONTRADO': 'No encontramos ese pedido.',
    'PEDIDO_EXPIRADO': 'Este pedido venció (pasaron más de 30 minutos).',
    'PEDIDO_CANCELADO': 'Este pedido fue cancelado.',
    'PEDIDO_NO_CANCELABLE': 'Este pedido ya no se puede cancelar.',
    'PEDIDO_NO_CANJEADO': 'Primero valida el pedido y luego entrégalo.',
    // Mesas
    'HORA_LLEGADA_INVALIDA':
        'Elige una hora de llegada de ahora a las próximas 12 horas.',
    'MESA_NO_ENCONTRADA': 'No encontramos esa mesa.',
    'MESA_CERRADA': 'Esta mesa ya cerró.',
    'MESA_VENCIDA': 'Esta mesa ya venció.',
    'MESA_LLENA': 'Esta mesa está llena.',
    'SOLO_ANFITRION': 'Solo el anfitrión puede hacer esto.',
    // Opiniones
    'OPINION_VACIA': 'Elige una etiqueta o escribe una nota.',
    'OPINION_AUN_NO_DISPONIBLE':
        'Podrás calificar este almuerzo en unos minutos.',
    'OPINION_VENCIDA': 'Ya pasó el plazo para calificar este almuerzo.',
    'OPINION_YA_ENVIADA': 'Ya calificaste este almuerzo.',
    'OPINION_NO_ENCONTRADA': 'No encontramos esa opinión.',
    'OPINION_YA_RESPONDIDA': 'Ya respondiste esta opinión.',
    // Sellos
    'TARJETA_NO_CONFIGURADA': 'Este local no tiene tarjeta de sellos.',
    'CLIENTE_NO_ENCONTRADO': 'No encontramos a ese cliente.',
    'SIN_PREMIOS': 'Este cliente todavía no tiene premios disponibles.',
    // Ofertas
    'PLATO_NO_ENCONTRADO': 'No encontramos ese plato.',
    'OFERTA_PRECIO_INVALIDO':
        'El precio de la oferta debe ser menor al precio normal.',
    'OFERTA_NO_ENCONTRADA': 'No encontramos esa oferta.',
    'COMENSAL_NO_ENCONTRADO': 'No encontramos a ese comensal.',
    'OFERTA_AGOTADA': 'Se acabaron los cupos de esta oferta.',
    'STOCK_INSUFICIENTE': 'No quedan tantos cupos en esta oferta.',
    'OFERTA_CERRADA': 'Esta oferta ya se cerró.',
    'OFERTA_EXPIRADA': 'Esta oferta ya terminó.',
    'OFERTA_NO_INICIADA': 'Esta oferta todavía no empieza.',
    'METODO_PAGO_NO_DISPONIBLE': 'Ese método de pago no está disponible.',
    // Analítica
    'EVENTO_USUARIO_AJENO': 'No pudimos enviar esa información.',
    'EVENTO_MUY_GRANDE': 'No pudimos enviar esa información.',
    'EVENTO_FECHA_INVALIDA': 'No pudimos enviar esa información.',
    'EVENTOS_LIMITE_TASA': 'Demasiados envíos. Espera un momento.',
  };
}
