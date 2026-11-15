/// Catálogo temporal de zonas conocidas en el backend (`ciudadId = 1`, Quito).
///
/// Verificado en vivo: `'Frente a la PUCE' -> 1`.
/// TODO(backend): B-04 completar IDs cuando el backend entregue `GET /v1/zonas?ciudadId=1`
/// o la tabla id <-> nombre para La Floresta, La Mariscal, Centro Histórico,
/// Cumbayá, UDLA Granados, EPN / Salesiana y Villaflora.
const Map<String, int> kKnownZoneIds = {
  'Frente a la PUCE': 1,
};

/// Devuelve el `zonaId` del backend si la zona ya está confirmada, o `null` para omitirla.
int? resolveKnownZoneId(String? zoneName) {
  if (zoneName == null) return null;
  return kKnownZoneIds[zoneName];
}
