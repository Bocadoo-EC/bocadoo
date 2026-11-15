import 'package:dio/dio.dart';

/// Error normalizado desde respuestas RFC 9457 (`application/problem+json`) o fallos de red.
class ApiException implements Exception {
  ApiException({
    this.status,
    required this.code,
    this.detail = '',
    this.requestId,
    this.isNetwork = false,
    this._overrideMessage,
  });

  final int? status;
  final String code;

  /// Detalle interno del backend: solo para depuración, nunca mostrar directo al usuario.
  final String detail;
  final String? requestId;
  final bool isNetwork;
  final String? _overrideMessage;

  factory ApiException.network() => ApiException(
        code: 'SIN_CONEXION',
        isNetwork: true,
      );

  factory ApiException.fromResponse(Response<dynamic> response) {
    final data = response.data is Map ? response.data as Map : const {};
    return ApiException(
      status: response.statusCode,
      code: (data['code'] ?? 'ERROR_INTERNO').toString(),
      detail: (data['detail'] ?? '').toString(),
      requestId: data['requestId']?.toString(),
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
        502 || 503 || 504 =>
          'No pudimos conectar con el servidor. Inténtalo en un momento.',
        _ => 'Algo salió mal de nuestro lado. Inténtalo en un momento.',
      };

  static const _byCode = <String, String>{
    // Sesión y registro
    'UNAUTHORIZED': 'Tu sesión venció. Entra de nuevo.',
    'FORBIDDEN': 'No tienes permiso para hacer esto.',
    'CONFLICT': 'Ya existe un registro con esos datos.',
    'TOO_MANY_REQUESTS': 'Demasiados intentos. Espera un momento.',
    'ERROR_INTERNO': 'Algo salió mal de nuestro lado. Inténtalo en un momento.',
    'SERVICE_UNAVAILABLE':
        'El servidor está despertando. Inténtalo en un momento.',
    'SIN_CONEXION':
        'No tienes conexión. Revisa tu internet e inténtalo de nuevo.',
    'SIN_RESTAURANTE': 'Esta cuenta no tiene un restaurante.',
    // Genéricos de datos
    'CURSOR_INVALIDO':
        'No pudimos cargar más resultados. Actualiza la lista.',
    'FECHA_INVALIDA': 'La fecha no es válida.',
    'RANGO_INVALIDO': 'El rango de fechas no es válido.',
    'RANGO_MUY_LARGO': 'Elige un rango de fechas más corto.',
    'IDEMPOTENCY_KEY_INVALIDA': 'No pudimos enviar esto. Inténtalo de nuevo.',
    'IDEMPOTENCY_KEY_REUTILIZADA':
        'Esta acción ya se envió. Actualiza para ver el resultado.',
    // Restaurantes
    'RESTAURANTE_NO_ENCONTRADO': 'No encontramos ese restaurante.',
    'RESTAURANTE_NO_DISPONIBLE': 'Este restaurante no está disponible ahora.',
    // Pase y almuerzos
    'CONSUMO_NO_ENCONTRADO': 'No encontramos ese almuerzo.',
    'CONSUMO_REVERTIDO': 'Ese almuerzo ya se devolvió a tu plan.',
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
