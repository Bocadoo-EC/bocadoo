import 'package:latlong2/latlong.dart';

/// Zona comercial para ubicarse sin GPS (C11, datos del prototipo).
class CommercialZone {
  const CommercialZone(this.id, this.name, this.description, this.lat, this.lng);

  final String id;
  final String name;
  final String description;
  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);
}

/// Ciudades: solo Quito está activa.
const supportedCities = [('Quito', true), ('Guayaquil', false), ('Cuenca', false)];

const quitoZones = [
  CommercialZone('puce', 'Frente a la PUCE', 'Av. 12 de Octubre y La Católica · Zona universitaria', -0.2105, -78.4920),
  CommercialZone('floresta', 'La Floresta', 'Madrid, Coruña y Redondel · Distrito gastronómico', -0.2085, -78.4870),
  CommercialZone('mariscal', 'La Mariscal', 'Plaza Foch, Amazonas y Colón · Zona comercial', -0.2030, -78.4925),
  CommercialZone('centro', 'Centro Histórico', 'San Blas, Plaza del Teatro y Plaza Grande', -0.2200, -78.5080),
  CommercialZone('cumbaya', 'Cumbayá / USFQ', 'Parque Central, Vía Interoceánica y USFQ', -0.1980, -78.4350),
  CommercialZone('inaquito', 'Iñaquito / La Carolina', 'Av. Amazonas, CCI y Parque La Carolina', -0.1800, -78.4840),
  CommercialZone('epn', 'EPN / Salesiana', 'Ladrón de Guevara y Politécnica Nacional', -0.2120, -78.4890),
  CommercialZone('villaflora', 'Villaflora', 'Av. Rodrigo de Chávez y 5 de Junio · Sur de Quito', -0.2450, -78.5210),
];
