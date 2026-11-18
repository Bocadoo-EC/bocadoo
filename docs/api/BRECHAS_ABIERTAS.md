# Brechas Abiertas y Decisiones de Producto (`1.0.0-rc.1`)

Este documento consolida las brechas identificadas al integrar la app Flutter de **Bocadoo** con el backend v1 (`https://bck-bocadoo.onrender.com`, OpenAPI `docs/api/openapi.json`) y las pantallas o acciones fuera del alcance actual que requieren aprobación de **Carlos** (UI/Producto) o implementación de **Chucho** (Backend).

> [!NOTE]
> Todas las brechas cuentan hoy con un Plan B funcional en la app y, cuando corresponde, una bandera en [api_capabilities.dart](file:///d:/PersonalJames/UNIVERSIDAD/SEXTO_SEMESTRE/EmprendimientoTecnologico/Bocadoo/bocadoo/mobile/lib/core/config/api_capabilities.dart) para mantener `--dart-define=BOCADOO_USE_MOCK=true` al 100 % sin romper la experiencia en modo API.

---

## 1. Brechas de Backend (`B-01` a `B-29`)

| ID | Qué falta hoy en la API | Pantallas | Plan B implementado en Flutter | Qué pedir a Chucho (Backend) |
|---|---|---|---|---|
| **B-01** | Inicio de sesión con Google | A1, A3, A4, A5 | Botón visible; muestra mensaje `"El acceso con Google estará disponible pronto. Entra con tu correo."` (`ApiCapabilities.googleSignIn = false`). | `POST /v1/auth/google {idToken, rol?, restaurante?}` → `TokenResponseDto` + OAuth Web Client ID. |
| **B-02** | Teléfono, zona y coordenadas en perfil de comensal | A4, C6, C2 | Persistencia local en `LocalProfileStore` (`SharedPreferences`). | Campos opcionales `telefono`, `zonaId`, `latitud`, `longitud` en `RegisterDto` y `PATCH /v1/auth/me`. |
| **B-03** | Recuperar contraseña | A2 | Botón controlado por `ApiCapabilities.forgotPassword = false` con salida a soporte. | `POST /v1/auth/forgot` y `POST /v1/auth/reset`. |
| **B-04** | Catálogo dinámico de zonas | A5, A4 | Lista estática en `zones.dart` (`zonaId: 1` "Frente a la PUCE"). | `GET /v1/zonas?ciudadId=1` con id, nombre y coordenadas centro. |
| **B-05** | Campo RUC en registro/detalle del local | A5 | Guardado local en `LocalProfileStore`. | Campo `ruc` en `RestauranteNuevoDto` y `PATCH /v1/restaurante`. |
| **B-06** | Horarios editables en registro | A7, O16 | Horario por defecto lunes a viernes 12:00–15:30. | Confirmar prioridad de `PUT /v1/restaurante/horarios` con Carlos. |
| **B-07** | Flags `tienePlanes` y `tieneOfertas` en tarjeta pública | C2 | Carga progresiva de detalle público al consultar restaurante. | Agregar `tienePlanes` y `tieneOfertas` en `RestauranteCardResponse`. |
| **B-08** | Reservar oferta flash desde el celular | C3 | `reservable = false`; tarjeta indica `"Pídela en caja."`. | `POST /v1/restaurantes/{slug}/ofertas/{id}/reservar`. |
| **B-09** | Reclamo/canje de premio de sellos desde la app | C1 | Oculto botón `"Reclamar"` en API (`ApiCapabilities.claimStampReward`); muestra `"Muéstralo en caja."`. | Confirmar flujo definitivo en caja vs app. |
| **B-10** | Recargo para llevar en detalle público | C3, C8 | Por defecto `0,25` en cliente; el servidor valida total final en `POST /v1/mis/pedidos`. | Exponer `recargoParaLlevarCentavos` en `RestauranteDetalleResponse`. |
| **B-11** | URL HTTPS compartible para mesas | C9 | Se comparte `bocadoo://mesa/<id>` + código de mesa (`AndroidManifest` + GoRouter). | Página puente `https://bocadoo.ec/mesa/<id>` con fallback a tiendas / esquema `bocadoo://`. |
| **B-12a** | Cambiar modo de cobro de mesa post-creación | C9, O5 | Selector de modo bloqueado en `TableSheet` y `CobrarMesaSheet` (`ApiCapabilities.sharedTableModeChange = false`). | `PATCH /v1/mis/mesas/{id} {modo}`. |
| **B-12b** | Notificar `"Avisar a cocina"` / pasar a `EN_CAMINO` | C9 | Botón oculto en modo API (`ApiCapabilities.sharedTableNotifyKitchen = false`). | `POST /v1/mis/mesas/{id}/en-camino`. |
| **B-12c** | Elegir sopa y plato fuerte al unirse a mesa | C7 | Oculta selector de platos en `JoinTableScreen` (`ApiCapabilities.sharedTableDishChoice = false`); envía solo `{paraLlevar}`. | Campos opcionales `sopaId`, `fuerteId` en `UnirseDto` (`POST /v1/mesas/invitacion/{id}/unirse`). |
| **B-13** | Selector para usuarios con múltiples locales | A1, O* | Toma el primer restaurante devuelto por `GET /v1/auth/me`. | Confirmar regla de negocio; si aplica, diseñar selector de local. |
| **B-14** | Proxy propio de rutas a pie y tiles | C11 | OSRM y OpenStreetMap públicos únicamente para demostración. | Endpoint `GET /v1/rutas` o proveedor productivo con API key. |
| **B-15** | Listado de mesas abiertas para la caja | O1, O5 | `getPendingTables` devuelve `[]`; banner oculto (`ApiCapabilities.ownerPendingTablesList = false`); cobro vía QR `BCD-MESA-<id>`. | `GET /v1/caja/mesas?estado=ABIERTA\|EN_CAMINO`. |
| **B-16** | Endpoint directo para deshacer entrega de pedido | O12 | `DeferredCommit` de `11 s` en `ApiOwnerRepository.deliverOrder` (`undoDeliver` cancela antes del envío). | `POST /v1/caja/pedidos/{id}/deshacer`. |
| **B-17** | Movimientos unificados del día (planes + validaciones + ventas) | O1 | `"Cobros de hoy"` fusiona `GET /v1/caja/ventas` + `GET /v1/caja/pedidos?estado=SERVIDA` + validaciones de la sesión (`POST /v1/caja/validar` con `platoNombre`). | `GET /v1/caja/movimientos?fecha=YYYY-MM-DD` (incluyendo canjes directos `POST /v1/caja/validar` históricos). |
| **B-30** | Validación `MENU_NO_PUBLICADO` (409) y campo `platoNombre` | C1, O1, O2 | Doble guarda en Flutter (`GET /v1/restaurantes/{slug}` `menuHoy.publicado` en Comensal, `GET /v1/menu/{fecha}` en Dueño) + manejo de `409 MENU_NO_PUBLICADO` y `platoNombre`. | Despliegue en Render del PR con `409 MENU_NO_PUBLICADO` en `/v1/pase`, `/v1/pase/codigo`, `/v1/caja/validar` y `platoNombre` en canjes. |
| **B-31** | Canje múltiple con invitados extras (`extraGuests`, `canal: 'MANUAL'`) | O2, O1 | Selector `+`/`-` en `ScanResultDialog`, actualización optimista en `"Cobros de hoy"` y despacho asíncrono con nuevo UUID `Idempotency-Key` + reverso de lote en `undoBatchRedemption`. | Soportar `canal: 'MANUAL'`, `extraGuests`, `batchRedemptionId` en `POST /v1/caja/validar` (omitir bloqueo `DUPLICADO` `< 60 s`) y devolver `consumos[]` para reverso completo. |
| **B-18** | Métricas de almuerzos vencidos y desglose por método en rango | O14 | Tarjeta de vencidos oculta (`ApiCapabilities.expiredLunchesReport = false`); ventas por método calculadas por lotes a `resumen-diario`; mapa de calor con 7 llamadas `horas-pico`. | `GET /v1/reportes/almuerzos-vencidos`, `porMetodo` en `ventas-planes` y `porDiaSemana` en `horas-pico`. |
| **B-19** | Preferencia persistida de resumen semanal por WhatsApp | O14, O16 | Guardado local en `SharedPreferences`. | `PUT /v1/restaurante/resumen-semanal {activo}` + job programado. |
| **B-20** | Ofertas programadas (días y franja horaria) | O11 | Opción oculta con `ApiCapabilities.flashScheduledOffer = false`. | `diasSemana`, `desde`, `hasta` en `PublicarOfertaDto`. |
| **B-21** | Deshacer respuesta / reposición de almuerzo en opiniones | O15 | `DeferredCommit` de `11 s` para responder y ejecutar `migrar-cartulina` (`+1`, `venceEl +30d`). | `POST /v1/opiniones/{id}/deshacer` y `POST /v1/clientes/{id}/almuerzos {cantidad, motivo}`. |
| **B-22** | `clienteId` y `telefono` en bandeja de opiniones | O15 | Enriquecimiento por coincidencia exacta única de nombre contra `GET /v1/clientes` (sin asumir en homónimos). | Incluir `cliente.id` y `cliente.telefono` (y `tienePlanActivo`) en `OpinionBandeja`. |
| **B-23** | Cancelar solicitud de plan ya enviada | C5 | `DeferredCommit` de `11 s` antes de emitir `POST /v1/restaurantes/{slug}/solicitudes-plan`. | `POST /v1/solicitudes-plan/{id}/cancelar`. |
| **B-24** | Reverso de cartulina migrada (`origen: MIGRADA`) | O10 | `undoPhysicalCard` llama `POST /v1/planes-vendidos/{id}/deshacer`; verificar comportamiento real en Render durante pruebas de humo. | Confirmar soporte de `deshacer` sobre planes `MIGRADA`. |
| **B-25** | Nombre del plan activo dentro de lista de clientes | O8 | Muestra `"<n> almuerzos disponibles"`. | Campo `planActual` en `ClienteResponse`. |
| **B-26** | Confirmar si `canjear` / `validar` mesa suman efectivo al cierre | O12, O5 | Verificación previa/posterior contra `efectivoEsperadoCentavos` antes de registrar venta POS espejo en efectivo. | Confirmar comportamiento en `CierreCajaResponse` para evitar lógica compensatoria en cliente. |
| **B-27** | Categoría `DESAYUNO` nativa en platos y `cobertura` explícita en planes | O7, O9, C3 | Etiqueta `desayuno` en `EXTRA`/`ADICIONAL` y codificación en `incluye[]`. | Enum `DESAYUNO` en platos y campo `cobertura` en plantillas de plan. |
| **B-28** | Carga remota de logo del restaurante | O16 | Lectura de `logoUrl` remoto + respaldo local base64 (≤ 60 KB) en `SharedPreferences`. | `POST /v1/restaurante/logo` (multipart) o URL prefirmada. |
| **B-29** | Foto de portada de restaurante | C2, C3 | Uso de `logoUrl` con degradado y monograma como respaldo (**E4**). | Campo `fotoUrl` en catálogo público y admin de restaurante. |

---

## 2. Backlog Pendiente de Aprobación / Diseño (Carlos)

| ID | Endpoints disponibles en backend | Descripción | Estado actual |
|---|---|---|---|
| **P-01** | `GET /v1/solicitudes-plan`, `POST .../{id}/cobrar`, `POST .../{id}/rechazar` | Bandeja en Caja para cobrar/rechazar solicitudes de plan enviadas por comensales (`C5`). | Métodos listos en `ApiOwnerRepository`; **sin UI** en `CajaScreen` hasta aprobación de diseño de Carlos. |
| **P-02** | `GET /v1/pagos/pendientes`, `POST /v1/pagos/{id}/confirmar\|rechazar` | Confirmación diferida de pagos por transferencia o Deuna. | Por ahora se envía `pagoConfirmado: true` al confirmar en caja. |
| **P-03** | `POST /v1/ofertas/{id}/canjear` | Validación/cobro directo de oferta flash en caja. | Pendiente de UI en módulo Dueño. |
| **P-04** | `GET /v1/reclamos`, `POST .../devolver\|rechazar`, `POST /v1/mis/consumos/{id}/reclamo` | Flujo formal de reclamos/devoluciones de almuerzos. | Pendiente de diseño y aprobación. |
| **P-05** | `GET /v1/suscripcion`, `GET /v1/suscripcion/uso` | Indicador de cupo SaaS (`LIMITE_SAAS`). | El escáner maneja error `LIMITE_SAAS`; pantalla de uso pendiente. |
| **P-06** | `GET/POST/PATCH /v1/restaurante/personal...` | Administración de cajeros desde Ajustes. | Pendiente de UI. |
| **P-07** | `GET/PUT /v1/restaurante/horarios` | Editor de horarios de atención del local. | Pendiente de decisión (**B-06**). |
| **P-08** | `GET/PUT /v1/sellos/config`, `POST /v1/clientes/{id}/sellos/canjear` | Configuración de sellos y cobro explícito de premio. | Pendiente de UI. |
| **P-09** | `GET/POST/PATCH /v1/restaurante/mesas` | Catálogo físico de mesas del local. | Pendiente de UI. |
| **P-10** | `GET /v1/mis/consumos`, `GET /v1/mis/opiniones` | Historial extendido de opiniones del comensal con respuesta del dueño. | `getRecentActivity` conectado a `/v1/mis/consumos`; vista de respuestas en Comensal pendiente. |
| **P-11** | `POST /v1/eventos` | Telemetría por lotes (máx. 50 eventos). | **Implementada:** `EventsService` conectado (ingresos, errores API/Flutter, vistas de ruta y uso por función sin PII). |
| **P-12** | `POST /v1/auth/logout-all` | Cierre de sesión en todos los dispositivos. | Pendiente de botón en Ajustes. |
| **P-13** | `POST /v1/clientes/{id}/vincular\|desvincular` | Vincular cliente manual del local con su correo en la app. | `addClient` intenta vincular silenciosamente si se ingresa correo; falta UI dedicada de vinculación/edición. |
