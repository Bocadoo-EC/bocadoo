import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Tipos de eventos emitidos por `GET /v1/pase/eventos`.
enum PaseEventType {
  canjeRegistrado,
  canjeRevertido,
  latido,
  fin,
  unknown,
}

/// Motivos de cierre enviados en el evento `FIN`.
enum PaseFinReason {
  tokenVencido,
  reemplazada,
  apagado,
  unknown,
}

/// Evento normalizado recibido desde el stream SSE del pase.
class PaseSseEvent {
  final PaseEventType type;
  final String? consumoId;
  final String? restauranteNombre;
  final int? saldoRestante;
  final String? platoNombre;
  final String? hora;
  final PaseFinReason finReason;
  final Duration? retryDelay;

  const PaseSseEvent({
    required this.type,
    this.consumoId,
    this.restauranteNombre,
    this.saldoRestante,
    this.platoNombre,
    this.hora,
    this.finReason = PaseFinReason.unknown,
    this.retryDelay,
  });

  factory PaseSseEvent.fromSse({
    required String eventName,
    required String dataRaw,
    Duration? retryDelay,
  }) {
    Map<String, dynamic> data = const {};
    if (dataRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(dataRaw);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}
    }

    final rawType = (data['tipo'] ?? eventName).toString().trim().toUpperCase();
    final type = switch (rawType) {
      'CANJE_REGISTRADO' => PaseEventType.canjeRegistrado,
      'CANJE_REVERTIDO' => PaseEventType.canjeRevertido,
      'LATIDO' => PaseEventType.latido,
      'FIN' => PaseEventType.fin,
      _ => PaseEventType.unknown,
    };

    final motivoRaw = (data['motivo'] ?? '').toString().trim().toUpperCase();
    final finReason = switch (motivoRaw) {
      'TOKEN_VENCIDO' => PaseFinReason.tokenVencido,
      'REEMPLAZADA' => PaseFinReason.reemplazada,
      'APAGADO' => PaseFinReason.apagado,
      _ => PaseFinReason.unknown,
    };

    final rawSaldo = data['saldoRestante'];
    final saldoRestante = rawSaldo is int
        ? rawSaldo
        : (rawSaldo is num ? rawSaldo.toInt() : int.tryParse('${rawSaldo ?? ''}'));

    Duration? resolvedRetry = retryDelay;
    final jsonRetry = data['retryMs'] ?? data['retry'];
    if (resolvedRetry == null && jsonRetry != null) {
      final ms = jsonRetry is num ? jsonRetry.toInt() : int.tryParse('$jsonRetry');
      if (ms != null && ms > 0) {
        resolvedRetry = Duration(milliseconds: ms);
      }
    }

    return PaseSseEvent(
      type: type,
      consumoId: data['consumoId']?.toString(),
      restauranteNombre: data['restauranteNombre']?.toString(),
      saldoRestante: saldoRestante,
      platoNombre: data['platoNombre']?.toString(),
      hora: data['hora']?.toString(),
      finReason: finReason,
      retryDelay: resolvedRetry,
    );
  }
}

/// Transforma un stream de bytes HTTP (`text/event-stream`) en eventos [PaseSseEvent].
Stream<PaseSseEvent> parsePaseSseStream(Stream<Uint8List> byteStream) async* {
  final lines = byteStream
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  var eventName = '';
  final dataLines = <String>[];
  Duration? retryDelay;

  await for (final line in lines) {
    if (line.isEmpty) {
      if (eventName.isNotEmpty || dataLines.isNotEmpty) {
        yield PaseSseEvent.fromSse(
          eventName: eventName,
          dataRaw: dataLines.join('\n'),
          retryDelay: retryDelay,
        );
        eventName = '';
        dataLines.clear();
      }
      continue;
    }

    if (line.startsWith(':')) {
      continue;
    }

    final colonIndex = line.indexOf(':');
    final field = colonIndex == -1 ? line : line.substring(0, colonIndex);
    var value = colonIndex == -1 ? '' : line.substring(colonIndex + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    switch (field) {
      case 'event':
        eventName = value;
      case 'data':
        dataLines.add(value);
      case 'retry':
        final ms = int.tryParse(value.trim());
        if (ms != null && ms > 0) {
          retryDelay = Duration(milliseconds: ms);
        }
    }
  }

  if (eventName.isNotEmpty || dataLines.isNotEmpty) {
    yield PaseSseEvent.fromSse(
      eventName: eventName,
      dataRaw: dataLines.join('\n'),
      retryDelay: retryDelay,
    );
  }
}
