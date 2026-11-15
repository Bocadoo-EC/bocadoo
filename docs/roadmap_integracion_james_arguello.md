# Roadmap maestro de integración Backend ↔ Frontend (Bocadoo)

**Para:** James Argüello y su asistente de IA.
**Qué hace este documento:** es la única guía técnica para conectar la app Flutter (`mobile/`) con el backend NestJS desplegado en Render, sin tocar la capa visual y sin romper las reglas de UX.
**Backend:** `https://bck-bocadoo.onrender.com` · API "Bocadoo API" `1.0.0-rc.1` · 97 rutas · 147 esquemas.
**Especificación cruda:** `docs/api/openapi.json` (se descargó de `https://bck-bocadoo.onrender.com/docs-json` el 2026-11-15).
**Estado del frontend:** las 34 pantallas están migradas y funcionan contra mocks en memoria. Falta conectarlas.

Este documento es autocontenido: trae el inventario del frontend, la matriz endpoint por endpoint de las 34 pantallas, los mapeos campo por campo, las brechas del backend con su plan B, y cinco fases con prompts listos para copiar.

> Si algo de este documento contradice a `docs/api/openapi.json`, manda el `openapi.json`. Si el `openapi.json` contradice al backend en vivo, manda el backend en vivo y se avisa a Chucho (backend).

---

## Índice

1. Cómo usar este documento y reglas de oro
2. Estado real del backend
3. Arquitectura del frontend (`mobile/lib/`)
4. Funcionalidades críticas de QA que no pueden romperse
5. Bloque 0: red, autenticación y seguridad
6. Bloque 1: Auth (A1 a A7)
7. Bloque 2: Comensal (C1 a C11)
8. Bloque 3: Dueño (O1 a O16)
9. Mapeo de modelos, campo por campo
10. Brechas del backend y planes B
11. Plan de ejecución en 5 fases, con prompts
12. Pruebas de humo contra Render
13. Textos de error para la app
- Apéndice A. Índice de los 97 endpoints
- Apéndice B. Los 147 esquemas

---

## 1. Cómo usar este documento y reglas de oro

### 1.1 Cómo lo usa la IA de James

1. Léelo completo una vez. Después trabaja **una fase a la vez** (sección 11) y copia el prompt de esa fase.
2. Antes de escribir código de una fase, abre `docs/api/openapi.json` y confirma el endpoint, el DTO y los códigos de error que vas a usar.
3. Al terminar cada fase: `flutter analyze` con **0 problemas**, `flutter build apk --debug` correcto, pruebas de humo de la sección 12, y recién entonces un commit.

### 1.2 Reglas de oro (no negociables)

| # | Regla | Por qué |
|---|---|---|
| R1 | **No se toca `presentation/`**, salvo los 6 ajustes mínimos de la sección 3.8. | La UI ya está aprobada por Carlos. Todo el trabajo va en `data/`, `domain/`, `core/` y los providers. |
| R2 | **Las pantallas no conocen la fuente de datos.** Hablan con repositorios (interfaces). Se cambia el mock por la implementación HTTP en los providers. | Así se mantiene el modo mock para demos y pruebas. |
| R3 | **El modo mock debe seguir funcionando** con `--dart-define=BOCADOO_USE_MOCK=true`. | Demos sin internet y pruebas de UI. |
| R4 | **Colores y tipografía solo desde `lib/core/theme`** (Outfit). Nada hardcodeado. | `REGLAS_UX.md` §1 y §2. |
| R5 | **Texto mínimo de 13 px.** Un solo botón morado relleno por pantalla o modal. Columnas con botones en `CrossAxisAlignment.stretch`. | Decisión vigente de Carlos. |
| R6 | **La palabra "canje" no puede aparecer en ningún texto visible.** El backend usa `canjear` en rutas y campos (`/canjear`, `canjeadoEn`, `CANJEADA`). Eso es interno: en pantalla se dice "validar" o "entregar". | `REGLAS_UX.md` §5. Los mensajes del servidor tampoco se muestran crudos: se traducen por `code` (sección 13). |
| R7 | **Cero emojis en titulares.** Íconos de Material. | `REGLAS_UX.md` §5. |
| R8 | **Sin mayúsculas sostenidas** en badges ni encabezados. | Decisión de Carlos. |
| R9 | **No se agregan paquetes sin aprobación.** Aprobados y ya instalados: `dio`, `flutter_riverpod`, `go_router`, `flutter_secure_storage`, `shared_preferences`, `qr_flutter`, `mobile_scanner`, `flutter_map`, `latlong2`, `url_launcher`, `geolocator`, `image_picker`, `flutter_svg`, `google_fonts`. **Pendiente de aprobación:** `google_sign_in` (sección 6.4). | `GEMINI.md` y `ROADMAP`. |
| R10 | **Todo lo que no exista en el backend se resuelve con el plan B de la sección 10.** La app nunca debe caerse ni mostrar un error técnico. Cada plan B lleva un `// TODO(backend):` con el nombre del endpoint que se le pidió a Chucho. | El backend es `1.0.0-rc.1`; faltan piezas. |
| R11 | **Un commit por fase**, con el ID de pantallas en el mensaje. **No hacer `git push`** sin orden de Carlos. | `ROADMAP` §2. |
| R12 | **Avisar a Carlos** antes de cada commit si se tocó `presentation/`. | R1. |
| R13 | **Nunca dejar secretos ni tokens en el repositorio ni en los logs.** | Seguridad. |
| R14 | **La IA no inventa endpoints.** Si necesitas algo que no está en el Swagger, usa el plan B y anótalo en la sección 10 del PR. | `ApiConfig` ya lo dice. |

### 1.3 Decisiones de producto ya cerradas que el código debe respetar

- Después del login el dueño entra a **Caja (O1)**, no al escáner.
- Filtros de "Dónde comer": **Cerca, Con plan, Libre, Ofertas**.
- Deshacer de **10 segundos** en cobros, entregas, validaciones, ventas y respuestas.
- Tarjeta de calificación **"¿Qué tal hoy?"**: entre **25 minutos y 24 horas** después de validar. Etiquetas visibles en la app: Rico, Rápido, Porción.
- Pedidos por cobrar **solo en efectivo** (preórdenes). Los pedidos cubiertos por plan no cobran nada.
- Planes sugeridos (sus precios no cambian): **Semanal $15 / 5 almuerzos / 7 días**, **Quincenal $28 / 10 almuerzos / 15 días**, **Mensual $55 / 20 almuerzos / 30 días**, **Libre $32 / 10 almuerzos / 60 días**.
- El rol "Cajero / Ayudante" del dispositivo cambia la barra inferior del dueño a **Caja, Pedidos, Turno**.
- Montos en dólares con coma decimal (`$55,00`). Fechas cortas `30/10`. Horas `12:45`.
- Ubicación del comensal y mapas: `flutter_map` + `geolocator` **dentro de la app**. Nunca se abre Google Maps externo.

---

## 2. Estado real del backend

### 2.1 Verificación en vivo (2026-11-15)

| Prueba | Resultado |
|---|---|
| `GET /health` | `200` en 0,4 s: `{"status":"ok","servicio":"bck-bocadoo","hora":"…"}` |
| `GET /v1/restaurantes?limit=3` | `200` en 0,5 s. Devuelve 3 locales de prueba en la zona `{"id":1,"nombre":"Frente a la PUCE"}`, `precioSueltoCentavos: 350`, `latitud: null`, `longitud: null`. |
| Swagger UI | `https://bck-bocadoo.onrender.com/docs` |
| JSON del Swagger | `https://bck-bocadoo.onrender.com/docs-json` (424 KB) |

Qué significa para la app:
- Los locales de prueba **no traen coordenadas** (`latitud`/`longitud` nulos) ni foto (`logoUrl` nulo). La UI debe tolerarlo (R10).
- El servicio estaba despierto al probar. En el plan gratuito de Render el servidor se duerme tras un rato sin tráfico y la primera petición puede tardar de 30 a 60 s (sección 5.5).

### 2.2 Convenciones generales de la API

| Tema | Regla |
|---|---|
| Versión | Todo cuelga de `/v1` salvo `/health` y `/health/ready`. |
| Autenticación | `Authorization: Bearer <accessToken>`. JWT ES256 de **15 minutos** (`expiresIn: 900`). |
| Refresh | `POST /v1/auth/refresh` con `{refreshToken}`. **Cada refresh token sirve una sola vez.** Reutilizar uno viejo **revoca toda la sesión**. Se guarda el par nuevo en cada refresh. |
| Roles | Etiquetas del Swagger: **Público** (sin token), **Comensal** (cualquier sesión), **Caja** (cajero o dueño), **Dueño** (solo dueño). |
| Restaurante activo | Los endpoints de **Caja** y **Dueño** exigen el encabezado `x-restaurant-id: <uuid>`. El uuid sale de `GET /v1/auth/me` → `restaurantes[].id`. Sin él, o con un local ajeno: `403 FORBIDDEN`. |
| Idempotencia | Los endpoints que mueven dinero o crean cosas exigen `Idempotency-Key: <uuid v4>` generado por el cliente. Reintentar con la **misma** clave devuelve el mismo resultado sin duplicar. Una clave reutilizada con otro cuerpo da `409 IDEMPOTENCY_KEY_REUTILIZADA`. Una clave mal formada da `400 IDEMPOTENCY_KEY_INVALIDA`. Lista completa: Apéndice A, columna IK. |
| Dinero | **Siempre en centavos enteros** (`precioCentavos: 350` = $3,50). La app usa dólares `double`: convertir en el repositorio (sección 5.8). |
| Fechas | ISO 8601 (`2026-11-13T17:00:00.000Z`). Los días son `AAAA-MM-DD` en la zona horaria del local (`America/Guayaquil`, UTC−5, sin horario de verano). En los paths `{fecha}` se acepta `hoy`. |
| Teléfonos | E.164 (`+593991234567`). La app captura `0991234567`: convertir. |
| Paginación | Por cursor. `limit` de 1 a 50 (por defecto 20). Se pasa `nextCursor` como `cursor`. `nextCursor: null` = no hay más. Cursor roto: `400 CURSOR_INVALIDO`. |
| Identificadores | Los `id` de restaurante, usuario, pedido, mesa, venta, consumo y plan vendido son **UUID**. Los `id` de cliente, plantilla de plan, plato, renglón de menú y solicitud son **cadenas numéricas** (`"12"`, `"3"`). Trátalos siempre como `String`. |
| Errores | `application/problem+json` (RFC 9457): `{type, title, status, code, detail, instance, requestId}`. **El cliente decide por `code`, nunca por el texto de `detail`.** |
| Límite de tasa | `429 TOO_MANY_REQUESTS` (también hay límites por hora en agregar cajero y vincular cliente). |
| Salud | `GET /health` (no toca la base) y `GET /health/ready` (verifica los dos roles de base de datos; `503 SERVICE_UNAVAILABLE` si la base no responde). |

### 2.3 Códigos de error del backend (todos los que declara el Swagger)

Genéricos: `BAD_REQUEST` (400), `UNAUTHORIZED` (401), `FORBIDDEN` (403), `NOT_FOUND` (404), `CONFLICT` (409), `TOO_MANY_REQUESTS` (429), `ERROR_INTERNO` (500), `SERVICE_UNAVAILABLE` (503).

Específicos, por dominio:

| Dominio | Códigos |
|---|---|
| Paginación y fechas | `CURSOR_INVALIDO`, `FECHA_INVALIDA`, `RANGO_INVALIDO`, `RANGO_MUY_LARGO` |
| Idempotencia | `IDEMPOTENCY_KEY_INVALIDA`, `IDEMPOTENCY_KEY_REUTILIZADA` |
| Restaurantes | `RESTAURANTE_NO_ENCONTRADO`, `RESTAURANTE_NO_DISPONIBLE` |
| Pase y consumos | `CONSUMO_NO_ENCONTRADO`, `CONSUMO_REVERTIDO`, `RECLAMO_VENCIDO`, `RECLAMO_YA_EXISTE` |
| Pedidos | `PEDIDO_VACIO`, `ALMUERZO_INVALIDO`, `MENU_NO_PUBLICADO`, `PEDIDO_ACTIVO`, `PLATO_AGOTADO`, `PLATO_NO_DISPONIBLE`, `PLATO_SIN_PRECIO`, `PEDIDO_NO_ENCONTRADO`, `PEDIDO_EXPIRADO`, `PEDIDO_CANCELADO`, `PEDIDO_NO_CANCELABLE`, `PEDIDO_NO_CANJEADO` |
| Mesas | `HORA_LLEGADA_INVALIDA`, `MESA_NO_ENCONTRADA`, `MESA_CERRADA`, `MESA_VENCIDA`, `MESA_LLENA`, `SOLO_ANFITRION` |
| Opiniones | `OPINION_VACIA`, `OPINION_AUN_NO_DISPONIBLE`, `OPINION_VENCIDA`, `OPINION_YA_ENVIADA`, `OPINION_NO_ENCONTRADA`, `OPINION_YA_RESPONDIDA` |
| Sellos | `TARJETA_NO_CONFIGURADA`, `CLIENTE_NO_ENCONTRADO`, `SIN_PREMIOS` |
| Ofertas | `PLATO_NO_ENCONTRADO`, `OFERTA_PRECIO_INVALIDO`, `OFERTA_NO_ENCONTRADA`, `COMENSAL_NO_ENCONTRADO`, `OFERTA_AGOTADA`, `STOCK_INSUFICIENTE`, `OFERTA_CERRADA`, `OFERTA_EXPIRADA`, `OFERTA_NO_INICIADA`, `METODO_PAGO_NO_DISPONIBLE` |
| Eventos | `EVENTO_USUARIO_AJENO`, `EVENTO_MUY_GRANDE`, `EVENTO_FECHA_INVALIDA`, `EVENTOS_LIMITE_TASA` |

Los textos para mostrarlos al usuario están en la sección 13.

### 2.4 Resultados de `POST /v1/caja/validar`

La validación **siempre responde 200** con un `resultado`:

| `resultado` | Significado | ¿Descuenta? |
|---|---|---|
| `OK` | Almuerzo descontado. | Sí |
| `OK_ADVERTENCIA` | Descontado. Era el último o el plan vence pronto: ofrecer renovar. | Sí |
| `DUPLICADO` | Ya se validó a este comensal hace menos de 1 minuto. | No |
| `SIN_PLAN` | No tiene plan en este restaurante. | No |
| `SIN_SALDO` | Su plan ya no tiene almuerzos. | No |
| `VENCIDO` | Su plan está vencido. | No |
| `DIA_NO_VALIDO` | Su plan no vale hoy (`diasValidos`). | No |
| `OTRO_LOCAL` | El código es de otro restaurante. | No |
| `QR_EXPIRADO` | El código venció (cambia cada 30 s; la caja acepta ±1 paso). | No |
| `QR_INVALIDO` | Código no válido. | No |
| `LIMITE_SAAS` | El local llegó al tope de validaciones de su suscripción. | No |

El descuento es FIFO: sale del plan que vence primero. Deshacer una validación: `POST /v1/caja/consumos/{id}/deshacer`, **solo dentro de los 10 segundos siguientes** (después, `409`). El `consumo.deshacerHasta` de la respuesta lo dice.

### 2.5 Estados de las entidades

| Entidad | Estados |
|---|---|
| Restaurante | `BORRADOR`, `ACTIVO`, `PAUSADO`, `BAJA` (el registro lo deja en borrador; `activar` exige precio suelto y al menos un horario) |
| Plan vendido | `ACTIVA`, `AGOTADA`, `VENCIDA`, `ANULADA` · origen `VENTA` o `MIGRADA` |
| Pago de plan | `PENDIENTE`, `CONFIRMADO`, `RECHAZADO` (efectivo siempre queda confirmado) |
| Pedido | `EN_CAMINO` → `CANJEADA` → `SERVIDA`; o `EXPIRADA` (30 min) / `CANCELADA` |
| Mesa compartida | `ABIERTA`, `EN_CAMINO`, `EN_MESA`, `FINALIZADA`, `CANCELADA` · modo `CADA_UNO` o `INVITO_YO` |
| Reclamo | `PENDIENTE`, `DEVUELTO`, `RECHAZADO` |
| Oferta | `VIGENTE`, `PROGRAMADA`, `AGOTADA`, `EXPIRADA`, `CERRADA` |
| Ocupación | `LIBRE` (<50 %), `MODERADO` (50 a 89 %), `LLENO` (≥90 % o "Local lleno" manual) |
| Suscripción | `TRIAL`, `FREEMIUM`, `ACTIVA_PRO`, `MOROSA`, `SUSPENDIDA`, `CANCELADA`, `SIN_SUSCRIPCION` |

### 2.6 Enumeraciones de contenido

- **Categoría de plato:** `ALMUERZO`, `A_LA_CARTA`, `EXTRA`, `BEBIDA`.
- **Sección dentro del almuerzo:** `JUGO`, `SOPA`, `FUERTE`, `POSTRE`, `ADICIONAL`.
- **Tipo de plan:** `SEMANAL`, `QUINCENAL`, `MENSUAL`, `LIBRE`.
- **Método de pago:** `EFECTIVO`, `TRANSFERENCIA`, `DEUNA`. (**No existe tarjeta.**)
- **Canal de consumo:** `QR`, `MANUAL`, `PREORDEN`, `MESA`.
- **Etiquetas de opinión (10):** `RICO`, `BUENA_PORCION`, `RAPIDO`, `BUENA_ATENCION`, `LIMPIO`, `FRIO`, `SALADO`, `PORCION_PEQUENA`, `DEMORA`, `MALA_ATENCION`.
- **Momento de cobro del local:** `ANTES_DE_SERVIR`, `DESPUES_DE_SERVIR`.
- **Tipo de ítem de venta:** `ALMUERZO` (precio suelto del local), `PLATO` (del catálogo), `LIBRE` (nombre y precio libres).
- **Motivos de seguimiento de cliente:** `POR_VENCER`, `SIN_VENIR`, `PARA_RENOVAR`.

### 2.7 Lo que el backend decide y la app nunca debe calcular

- **Precios de almuerzo y platos en ventas y pedidos:** los pone el servidor.
- **Si un plan cubre el almuerzo de un pedido** (`almuerzo.cubiertoPorPlan`).
- **El saldo, el vencimiento y el orden FIFO de los planes.**
- **La validez del QR del pase.** La app **no valida el hash localmente** en modo API: manda `codigoQr` tal cual (sección 7, C1 y O2).
- **La regla de 25 minutos a 24 horas para opinar** (`/mis/opiniones/pendientes` solo devuelve lo vigente).
- **La ocupación** (`ocupacion.nivel`).

### 2.8 Objetos anidados que el Swagger deja como `object`

El Swagger declara estos campos como `object` sin forma. Esta es la forma real, tomada de sus ejemplos:

| Dónde | Forma |
|---|---|
| `TokenResponseDto.usuario`, `RegisterResponseDto.usuario/restaurante` | **Sin forma documentada.** Confirmar con una llamada real. Para identidad confiable usar `GET /v1/auth/me` (`usuario: {id, nombre}`). |
| `MeResponseDto.usuario` | `{id (uuid), nombre}` |
| `MesaResponse.restaurante` | `{id, nombre, slug}` |
| `MesaResponse.anfitrion`, `InvitacionResponse.anfitrion` | `{nombre}` |
| `PaseResponse.usuario` | `{id, nombre}` |
| `PaseResponse.codigo` | `{codigo, validoSegundos, expiraEn}` |
| `LocalPase.restaurante` | `{id, nombre, slug, logoUrl}` |
| `ValidacionResponse.cliente` | `{id, nombre}` |
| `ValidacionResponse.consumo` | `{id, creadoEn, deshacerHasta}` |
| `ValidacionResponse.plan` | `{nombre, venceEl}` |
| `ConsumoItem.restaurante` | `{id, nombre, slug}` · `ConsumoItem.plan` → `{id, nombre}` |
| `ReclamoResponse.consumo`, `PendienteResponse.consumo`, `OpinionResponse.consumo` | `{id, fecha, restaurante: {id, nombre, slug}}` |
| `PedidoResponse.restaurante` / `PedidoCaja.restaurante` | `{id, nombre, slug}` |
| `PedidoResponse.almuerzo` / `PedidoCaja.almuerzo` | `{platos: [{id, nombre, seccion}], precioCentavos, cubiertoPorPlan}`; `null` si solo pidió extras |
| `PedidoCaja.comensal` | `{nombre}` · `PedidoCaja.cliente` → `{nombre, almuerzosDisponibles}`; `null` si no es cliente del local |
| `PedidoCanjeResponse.almuerzo` | `{resultado, mensaje, descontado, consumoId}`; `null` si el pedido no lleva almuerzo; `resultado` es `null` si se repite un canje ya hecho |
| `OpinionResponse.respuesta` / `OpinionBandeja.respuesta` | `{texto, respondidoEn}` o `null` |
| `OpinionBandeja.cliente` | `{nombre}` · `OpinionBandeja.plan` → `{nombre}` |
| `BandejaResponse.resumen` | `{total, sinResponder, conComentario, etiquetas: {RICO: 8, FRIO: 2, …}}` (últimos 30 días, sin descartes) |
| `MiTarjeta.restaurante` | `{id, nombre, slug}` |
| `OfertaResponse.plato` | `{id, nombre}` o `null` |
| `PlanVendidoResponse.pago` | `{id, estado, metodo, montoCentavos, fecha, comprobanteUrl, reverso: {id, montoCentavos} \| null}` |
| `ResumenDiarioResponse.almuerzos.porCanal` | `{QR, MANUAL, PREORDEN, MESA}` (conteos) |
| `ResumenDiarioResponse.ingresos.porOrigen` | `{planes, ventas, ofertas, pedidos}` (centavos) |
| `ResumenDiarioResponse.ingresos.porMetodo` | `[{metodo, centavos}]` |
| `ResumenDiarioResponse.ingresos.pendientesPorConfirmar` | `{cantidad, centavos}` |
| `ResumenDiarioResponse.ofertas` | `{unidades, centavos}` · `escaneos` → `{total, validos, rechazados}` |
| `VentasPlanesResponse.total` | `{vendidos, anulados, ingresoCentavos}` · `porDia` → `[{fecha, vendidos, ingresoCentavos}]` |
| `PlatoRanking.plato` | `{id, nombre}` |
| `PendientesResponse.total` | `{clientes, planes, almuerzos, pasivoCentavos}` |

---
## 3. Arquitectura del frontend (`mobile/lib/`)

### 3.1 Árbol del proyecto

```text
mobile/
  pubspec.yaml                      dependencias (ver R9)
  assets/logos/                     bocadoo-isotipo(.svg|-blanco.svg), bocadoo-wordmark(.svg|-blanco.svg)
  android/app/src/main/AndroidManifest.xml   permisos: INTERNET, CAMERA, ACCESS_FINE/COARSE_LOCATION
  lib/
    main.dart                       ProviderScope + MaterialApp.router (tema claro/oscuro, themeModeProvider)
    core/
      contracts/
        models.dart                 modelos inmutables del Comensal y del Dueño (ver 3.2)
        repositories.dart           ICustomerRepository e IOwnerRepository
        qr_parser.dart              BocadooQrParser: genera y valida QR "BCD1.{userId}.{paso}.{hash}" (SOLO para el mock)
      demo/demo_store.dart          almacén en memoria compartido por los mocks (ver 3.5)
      config/support_config.dart    contacto de soporte por --dart-define
      network/api_config.dart       URL base y timeouts (hoy apunta a un dominio de ejemplo: se corrige en el Bloque 0)
      network/dio_client.dart       Dio sin interceptores (se amplía en el Bloque 0)
      location/location_service.dart  geolocator: permiso, posición, distancia, minutos a pie
      router/app_router.dart        go_router con 2 ShellRoute (comensal y dueño) y hojas inferiores
      theme/                        app_theme.dart (Outfit, tokens, BocadooColors), theme_provider.dart
      utils/external_links.dart     openExternal, whatsAppUri, toInternationalPhone
      widgets/                      bocadoo_logo (SVG), appearance_selector, location_picker_map, bottom_nav_bar, …
    features/
      auth/presentation/            A1, A2, A4, A5, A6, A7 + google_sign_in_flow.dart (A3 ya no es pantalla)
      customer/
        domain/                     feedback_rules.dart, commercial_zones.dart
        data/                       mock_customer_repo.dart, api_customer_repo.dart (STUB), local_customer_cache.dart,
                                    walking_route_service.dart (OSRM público)
        presentation/               customer_controller.dart (ChangeNotifier + providers), shell, C1 a C11
      owner/
        domain/models/              cash_models, daily_menu, menu_models, metrics_models, extras_models
        domain/repositories/        i_owner_repository.dart (8 interfaces)
        data/                       mock_owner_repo.dart, repositories/owner_repository.dart, api_owner_repo.dart (VACÍO)
        presentation/               owner_controller.dart (providers + escáner), owner_shell, O1 a O16
```

### 3.2 Contratos: modelos (`core/contracts/models.dart`) y repositorios

**Modelos del Comensal:** `CustomerPass`, `Restaurant` (con `latitude`/`longitude`, `hasLocation`), `RestaurantOffer`, `PlanTemplate` (precio en centavos), `StampCard`, `ActiveTable`, `ActiveOrder` (estados `PREPARANDO`, `LISTO`, `ENTREGADO`; `paidAmount`, `hasPlan`, `expiresAt`), `TableMode {eachOwn, hostPays}`, `TableMember`, `TableDish`, `SharedTable`, `CustomerProfile`, `PendingFeedback`, `ActivityItem`, `MenuItem`, `ConsumptionRecord`.

**Modelos del Dueño en `core/contracts`:** `OwnerStore`, `ScanResult` (`outcome`: `VERDE`, `ADVERTENCIA`, `ROJO`, `GRIS`; `actionRequired`: `VENDER_PLAN`, `COBRAR_SUELTO`, `NINGUNA`), `TransactionItem`, `TransactionSummary`.

**Modelos del Dueño en `features/owner/domain/models/`:**
- `cash_models.dart`: `OwnerPayMethod {efectivo, transferencia, deuna, tarjeta}`, `OwnerClient` (`id, name, phone, email, notes, habitualPlan`), `PlanKind`, `PlanCoverage {almuerzo, desayuno, mixto}`, `OwnerPlanTemplate` (`kind, coverage, includes, days, quota, visible, active, lunches, price, validityDays`), `PosCategory`, `CatalogItem`, `PosSaleLine`, `OfferKind {flash, programada}`, `FlashOffer`.
- `daily_menu.dart`: `DailyMenuCourse` (`category`: `Sopa|Fuerte|Jugo|Postre|Desayuno`, `isSoldOut`, `price`), `DailyMenu`.
- `menu_models.dart`: `DishKind {sopa, segundo, bebida, postre, desayuno, carta}`, `CatalogDish`.
- `metrics_models.dart`: `MetricsPeriod`, `DishRank`, `ClientFollowUp`, `OwnerMetrics`.
- `extras_models.dart`: `OwnerRole {owner, cashier}`, `OwnerOrder` (`number, dinerName, soup, main, takeaway, amount, createdAt, paidByPlan, validated`), `PendingTable`, `TableChargeVia`, `TableChargeLine`, `TablePreview`, `OpinionReply`, `OwnerOpinion`, `LocalInfo`.

**Interfaces (los contratos que se implementan con HTTP):**

| Interfaz | Archivo | Métodos |
|---|---|---|
| `ICustomerRepository` | `core/contracts/repositories.dart` | `getActivePass`, `refreshQrToken`, `getRestaurants`, `getRestaurantById`, `getTodayMenu`, `getConsumptionHistory`, `getCachedPass`, `saveCachedPass`, `getActivePasses`, `getStampCard`, `claimReward`, `getActiveTable`, `getActiveOrder`, `getRecentActivity`, `preorder`, `cancelPreorder`, `acknowledgeOrder`, `getPlanTemplates`, `getPlanTemplateById`, `requestPlan`, `cancelPlanRequest`, `openSharedTable`, `getSharedTable`, `setTableMode`, `notifyKitchen`, `joinTable`, `getProfile`, `getPendingFeedback`, `submitFeedback`, `dismissFeedback` |
| `IOwnerRepository` | `core/contracts/repositories.dart` | `validateQrCode`, `confirmRedeem`, `sellPlan`, `getDailyClosingSummary`, `getTodayTransactions` |
| `IOwnerMenuRepository` | `features/owner/domain/repositories/i_owner_repository.dart` | `getTodayMenu`, `getYesterdayMenu`, `publishMenu`, `unpublishMenu`, `setCourseSoldOut`, `setStoreOpen` |
| `IOwnerCatalogRepository` | idem | `getDishes`, `addDish`, `setDishArchived` |
| `IOwnerMetricsRepository` | idem | `getMetrics`, `setWeeklySummary` |
| `IOwnerCashRepository` | idem | `getSingleLunchPrice`, `getClients`, `addClient`, `getPlanTemplates`, `savePlanTemplate`, `setPlanActive`, `getPlanClientCounts`, `sellPlanTemplate`, `undoTransaction`, `undoRedeem`, `getCatalog`, `registerPosSale`, `getActiveOffer`, `publishOffer`, `cancelOffer`, `setManualBusy`, `getOrdersOnTheWayCount`, `isShiftClosed`, `closeShift`, `reopenShift`, `registerPhysicalCard`, `undoPhysicalCard` |
| `IOwnerOrdersRepository` | idem | `getActiveOrders`, `validateOrder`, `undoValidate`, `deliverOrder`, `undoDeliver` |
| `IOwnerTablesRepository` | idem | `getPendingTables`, `previewTable`, `setTableMode`, `chargeTable`, `undoTableCharge` |
| `IOwnerFeedbackRepository` | idem | `getOpinions`, `replyOpinion`, `undoReply` |
| `IOwnerSettingsRepository` | idem | `getLocalInfo`, `setLogo` |

### 3.3 Providers de Riverpod (qué hay hoy y dónde cambiarlo)

**Comensal** (`features/customer/presentation/customer_controller.dart`):
- `customerRepositoryProvider` → hoy `MockCustomerRepository()`. **Aquí se cambia por `ApiCustomerRepository`.**
- `customerControllerProvider` → `CustomerController` (un `ChangeNotifier`) que llama a `loadDashboard()` al crearse. Estado en `CustomerUiState`: `passes`, `passIndex`, `selectedQrMode` (`preorden|mesa|plan`), `stampCards`, `activeTable`, `activeOrder`, `pendingFeedback`, `recentActivity`, `restaurants`, filtros, planes del local elegido, `undo`. La UI lo lee con `ListenableBuilder`.
- `restaurantDetailProvider(id)` y `planDetailProvider(planId)` → `FutureProvider.autoDispose.family`.
- `customerProfileProvider` (`account_screen.dart`).
- `CustomerShell` (`customer_shell.dart`) llama a `controller.refreshLive()` al entrar y muestra la hoja `DeliveredOrderSheet` cuando `activeOrder.isDelivered`; luego llama `acknowledgeDelivery()`.

**Dueño** (`features/owner/presentation/owner_controller.dart`): un mock compartido (`_sharedMock`) y un `OwnerRepository` que lo envuelve. Providers:
`ownerRepositoryProvider`, `ownerMenuRepositoryProvider`, `ownerCashRepositoryProvider`, `ownerCatalogRepositoryProvider`, `ownerMetricsRepositoryProvider`, `ownerOrdersRepositoryProvider`, `ownerTablesRepositoryProvider`, `ownerFeedbackRepositoryProvider`, `ownerSettingsRepositoryProvider`.
Datos: `ownerRestaurantIdProvider` (hoy `'rest-001'`) y `ownerRestaurantNameProvider` (hoy `'La Cuchara de San Blas'`), `catalogDishesProvider`, `planClientCountsProvider`, `metricsProvider(period)`, `dailySummaryProvider`, `lunchPriceProvider`, `ownerClientsProvider`, `planTemplatesProvider`, `catalogProvider`, `posMenuProvider`, `activeOfferProvider`, `ordersOnTheWayProvider`, `shiftClosedProvider`, `activeOrdersProvider`, `pendingTablesProvider`, `opinionsProvider`, `localInfoProvider`, `busyUntilProvider`, `ownerRoleProvider` (guarda `bocadoo-owner-role` en `shared_preferences`), y el escáner `ownerControllerProvider` (`OwnerIdle`, `OwnerScanning`, `OwnerSuccess`, `OwnerError`, `OwnerRedirect`).

Las pantallas invalidan providers (`ref.invalidate(...)`) después de cada acción. **Esa convención se mantiene**: el repositorio HTTP solo devuelve datos; la UI refresca.

### 3.4 Router (`core/router/app_router.dart`)

- `initialLocation: '/login'`. Hoy **no hay guardia de sesión**: se agrega en el Bloque 0.
- `ShellRoute` del comensal (`CustomerShell`, barra Pase / Restaurantes / Planes / Yo):
  `/customer/pase`, `/customer/restaurants` (hoja hija `:restaurantId`), `/customer/planes` (hoja hija `:planId`), `/customer/cuenta`.
- `ShellRoute` del dueño (`OwnerShell`, barra por rol): `/owner/caja`, `/owner/registrar-consumo`, `/owner/cobro-suelto` (abre el POS), `/owner/cash-closing`, `/owner/menu`, `/owner/planes`, `/owner/metricas`, `/owner/settings`, `/owner/pedidos` (acepta `?cobrar=<n>`), `/owner/opiniones`.
- Fuera de los shell: `/owner/scanner`, `/owner/scan-result` (redirige a Caja), hojas `OwnerSheetPage`: `/owner/vender-plan` (`extra`: nombre del cliente), `/owner/oferta-flash`, `/owner/planes/nuevo`, `/owner/planes/:planId/editar`, `/owner/clientes/nuevo` (devuelve `AddedClient`), `/owner/cartulina`, `/owner/cobrar-mesa/:mesaId`.
- Hojas del comensal (`BottomSheetPage`): `/customer/mesa?restaurantId=`, `/customer/pedido/:orderId`. Pantalla: `/customer/mesa/:mesaId` (invitación), `/customer/mapa`. `/customer/calificar/:orderId` redirige a Mi Pase (C10 es una tarjeta).
- Auth: `/login`, `/auth/olvide-contrasena`, `/auth/registro/comensal`, `/auth/registro/dueno`, `/auth/bienvenida/comensal` (`extra`: `{nombre, zona, lat, lng}`), `/auth/bienvenida/dueno` (`extra`: `double` precio base).

### 3.5 Mocks y almacén compartido (`core/demo/demo_store.dart`)

Mientras no hay API, comensal y dueño se hablan a través de `DemoStore.instance` (un `ChangeNotifier` singleton):

| Colección | Contenido |
|---|---|
| `preorders` (`DemoPreorder`) | número, restaurante, comensal, sopa, segundo, `amount`, `hasPlan`, `validated`, `status` (`pending`, `delivered`, `acknowledged`, `cancelled`), `createdAt`, `expiresAt`. Semilla: #40 Sofía Almeida (con plan), #42 Carlos Mejía (efectivo, $3,00), #43 Andrea Morales (efectivo, $3,00). |
| `tables` (`SharedTable`) | mesas con amigos. Semilla: `M1234` en La Cuchara de San Blas, 13:00, con Carlos Mejía (anfitrión), Valentina Ortiz y Mateo Ruiz (para llevar). |
| `settledTables` | mesas ya cobradas en caja. |
| `feedback` (`DemoFeedback`) | opiniones con `tag`, `note`, `reply`. |

`MockCustomerRepository` y `MockOwnerRepository` leen y escriben ahí, y llaman a `changed()` para avisar. **Todo lo que hoy viaja por `DemoStore` debe viajar por la API real** (sección 4). Los QR del mock siguen el formato `BCD1.{userId}.{paso}.{hash}` (`BocadooQrParser`): son solo para el mock.

### 3.6 Cómo reemplazar los mocks por HTTP sin tocar la UI

1. **Bandera de modo** (`core/config/app_mode.dart`, nuevo):
   ```dart
   class AppMode {
     static const useMock = bool.fromEnvironment('BOCADOO_USE_MOCK', defaultValue: false);
   }
   ```
2. **Implementar** `ApiCustomerRepository` (completar `features/customer/data/api_customer_repo.dart`, hoy lanza `UnimplementedError`) y `ApiOwnerRepository` (completar `features/owner/data/api_owner_repo.dart`, hoy vacío). `ApiOwnerRepository` implementa **las 8 interfaces del dueño**, igual que `MockOwnerRepository`.
3. **Cambiar los providers** (R2):
   ```dart
   final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
     if (AppMode.useMock) return MockCustomerRepository();
     return ApiCustomerRepository(ref.watch(apiClientProvider));
   });

   // owner_controller.dart: reemplazar _sharedMock/_sharedOwnerRepository por:
   final _ownerApiProvider = Provider<ApiOwnerRepository>(
     (ref) => ApiOwnerRepository(ref.watch(apiClientProvider), ref.watch(sessionProvider)));
   final ownerRepositoryProvider        = Provider<IOwnerRepository>((ref) => AppMode.useMock ? _mockOwner : ref.watch(_ownerApiProvider));
   final ownerCashRepositoryProvider    = Provider<IOwnerCashRepository>((ref) => AppMode.useMock ? _mockOwner : ref.watch(_ownerApiProvider));
   // …lo mismo para las otras 7 interfaces
   ```
4. **`ownerRestaurantIdProvider` y `ownerRestaurantNameProvider`** pasan a leerse de la sesión (`sessionProvider.restaurant.id`, `.nombre`). En modo mock siguen devolviendo los valores de hoy.
5. **No cambies las firmas** de las interfaces. Si una operación necesita un dato que la firma no trae (por ejemplo el `uuid` de un pedido cuando la firma recibe el número), el repositorio HTTP guarda un mapa interno `número → uuid`, o se agrega un campo **opcional** al modelo (sección 9.12). Agregar campos opcionales a los modelos no rompe a nadie.
6. **Los repositorios lanzan `ApiException`** (sección 5.6). Las pantallas ya tienen estados de error con "Reintentar".
7. **Mantén el mock** detrás de `AppMode.useMock`. `DemoStore` se queda para el modo mock.

### 3.7 Reglas de UX que condicionan el código

- Estados de carga, vacío y error por pantalla, con "Reintentar" (`REGLAS_UX` §6). Los providers `FutureProvider` ya los resuelven.
- Deshacer de 10 s: **hay operaciones sin deshacer en el servidor.** Para ellas se usa el patrón **commit diferido** (sección 10.2): se muestra el aviso de 10 s y recién después se envía la petición; si el usuario toca "Deshacer", no se envía nada.
- Mensajes siempre en español de Ecuador, tuteo, sin "canje" (sección 13).
- Todo `onPressed` ya navega por GoRouter. No se agregan botones nuevos sin avisar a Carlos.

### 3.8 Ajustes mínimos permitidos en `presentation/` (R1)

Son los **únicos** cambios permitidos a archivos de `presentation/`. Ninguno cambia el aspecto.

| # | Ajuste | Dónde |
|---|---|---|
| E1 | Reemplazar los bloques `// TODO: Conectar con provider de backend` y los `Future.delayed` simulados por llamadas al repositorio de auth. | `login_screen.dart` (`_login`), `register_diner_screen.dart` (`_register`), `register_owner_screen.dart` (`_register`), `forgot_password_screen.dart`, `onboarding_owner_screen.dart` (guardar planes, aforo y finalizar), `onboarding_diner_screen.dart`, `google_sign_in_flow.dart` |
| E2 | Validación de contraseña: **mínimo 10 caracteres** (el backend rechaza menos) y el texto de ayuda correspondiente. Hoy la UI pide 6. | `register_diner_screen.dart`, `register_owner_screen.dart` |
| E3 | Lectura de capacidades: `ApiCapabilities` (sección 10.1) para ocultar un control cuyo endpoint no existe. Solo un `if` por control, sin cambiar estilos. | `caja_screen.dart` (banner de mesas), `cobrar_mesa_sheet.dart` (selector de modo), `table_sheet.dart` (selector de modo y "Avisar a cocina"), `oferta_flash_sheet.dart` (promo programada), `sell_plan_modal.dart` y `registrar_consumo_screen.dart` (método Tarjeta), `owner_metrics_screen.dart` (tarjetas sin fuente), `opiniones_screen.dart` (Reponer almuerzo) |
| E4 | Imagen de restaurante vacía: la API no entrega fotos de portada, solo `logoUrl`. Mostrar el logo o un degradado del tema cuando `imageUrl` está vacío. | `restaurants_screen.dart`, `restaurant_sheet.dart`, `customer_widgets.dart` |
| E5 | Los providers `ownerRestaurantIdProvider` y `ownerRestaurantNameProvider` leen la sesión (sección 3.6, punto 4). | `owner_controller.dart` |
| E6 | Ocultar la nota "Tarjeta" y otros textos de método de pago que el backend no soporta. | `cash_models.dart` (`OwnerPayMethod.tarjeta`) y quien lo lista |

> Si la IA considera que necesita un cambio de `presentation/` que no está en esta tabla, **se detiene y le pregunta a James**, y James a Carlos.

---

### 3.9 Inventario de las 34 pantallas

Marcos comunes: `CustomerShell` (barra **Pase, Restaurantes, Planes, Yo**) y `OwnerShell` (barra del **dueño**: Caja, Menú, Planes, Métricas, Ajustes; barra del **cajero**: Caja, Pedidos, Turno).

| ID | Pantalla | Ruta | Archivo (`lib/features/…/presentation/`) |
|---|---|---|---|
| A1 | Login | `/login` | `auth/login_screen.dart` |
| A2 | Olvidé mi contraseña | `/auth/olvide-contrasena` | `auth/forgot_password_screen.dart` |
| A3 | Acceso con Google | (flujo directo, sin pantalla) | `auth/google_sign_in_flow.dart` |
| A4 | Registro de comensal | `/auth/registro/comensal` | `auth/register_diner_screen.dart` |
| A5 | Registro de dueño | `/auth/registro/dueno` | `auth/register_owner_screen.dart` |
| A6 | Bienvenida del comensal | `/auth/bienvenida/comensal` | `auth/onboarding_diner_screen.dart` |
| A7 | Bienvenida del dueño | `/auth/bienvenida/dueno` | `auth/onboarding_owner_screen.dart` |
| C1 | Mi Pase | `/customer/pase` | `customer/pase_screen.dart` |
| C2 | Dónde comer | `/customer/restaurants` | `customer/restaurants_screen.dart` |
| C3 | Ficha del local | `/customer/restaurants/:restaurantId` (hoja) | `customer/restaurant_sheet.dart` |
| C4 | Planes | `/customer/planes` | `customer/plans_screen.dart` |
| C5 | Detalle del plan | `/customer/planes/:planId` (hoja) | `customer/plan_detail_sheet.dart` |
| C6 | Mi cuenta | `/customer/cuenta` | `customer/account_screen.dart` |
| C7 | Unirme a mesa | `/customer/mesa/:mesaId` | `customer/join_table_screen.dart` |
| C8 | Estado del pedido | `/customer/pedido/:orderId` (hoja) | `customer/order_status_sheet.dart` y `DeliveredOrderSheet` en `customer_shell.dart` |
| C9 | Mesa con amigos | `/customer/mesa?restaurantId=` (hoja) | `customer/table_sheet.dart` |
| C10 | Calificar almuerzo | tarjeta en Mi Pase (`/customer/calificar/:orderId` redirige a `/customer/pase`) | `customer/feedback_card.dart` |
| C11 | Mapa | `/customer/mapa` | `customer/map_screen.dart` |
| O1 | Caja | `/owner/caja` | `owner/caja_screen.dart` |
| O2 | Escáner y resultado | `/owner/scanner` (el resultado es una tarjeta sobre Caja) | `owner/scanner_screen.dart`, `owner/scan_result_screen.dart` |
| O3 | Vender plan | `/owner/vender-plan` (hoja) | `owner/sell_plan_modal.dart` |
| O4 | Cobro suelto | `/owner/cobro-suelto` (abre el POS) | `owner/registrar_consumo_screen.dart` |
| O5 | Cobrar mesa | `/owner/cobrar-mesa/:mesaId` (hoja) | `owner/cobrar_mesa_sheet.dart` |
| O6 | Registrar consumo (POS) | `/owner/registrar-consumo` | `owner/registrar_consumo_screen.dart` |
| O7 | Menú de hoy y "Mis platos" | `/owner/menu` | `owner/owner_menu_screen.dart` |
| O8 | Planes y clientes | `/owner/planes` y hoja `/owner/clientes/nuevo` | `owner/owner_plans_screen.dart`, `owner/add_client_sheet.dart` |
| O9 | Crear o editar plan | `/owner/planes/nuevo`, `/owner/planes/:planId/editar` (hojas) | `owner/plan_editor_sheet.dart` |
| O10 | Pasar cartulina | `/owner/cartulina` (hoja; solo desde Ajustes) | `owner/cartulina_sheet.dart` |
| O11 | Oferta flash | `/owner/oferta-flash` (hoja) | `owner/oferta_flash_sheet.dart` |
| O12 | Pedidos en camino | `/owner/pedidos` (acepta `?cobrar=<n>`) | `owner/pedidos_screen.dart` |
| O13 | Cierre de caja | `/owner/cash-closing` | `owner/cash_closing_screen.dart` |
| O14 | Métricas ("Tus números") | `/owner/metricas` | `owner/owner_metrics_screen.dart`, `owner/weekly_summary_preview.dart` |
| O15 | Opiniones | `/owner/opiniones` | `owner/opiniones_screen.dart` |
| O16 | Ajustes del dueño | `/owner/settings` | `owner/owner_settings_screen.dart` |

---

## 4. Funcionalidades críticas de QA que no pueden perderse

Esta sección existe porque el QA agregó comportamiento que hoy solo funciona gracias a los mocks. **Cada ítem tiene su prueba de aceptación.** Si una fase deja de cumplirla, la fase no está terminada.

### 4.1 Sincronización Comensal ↔ Dueño (hoy `core/demo/DemoStore`)

#### 4.1.1 Preórdenes del comensal que aparecen en O12 (en efectivo y cubiertas por plan)

**Hoy:** el comensal toca "Pedir" en Dónde comer (C2) o "Preordenar" en la ficha (C3). `MockCustomerRepository.preorder` crea un `DemoPreorder` y la hoja `OrderStatusSheet` (C8) muestra número, cuenta regresiva de 30 min y QR. La caja lo ve en `O12 Pedidos en camino`. Si el local tiene plan (`hasPlan`), el pedido no cobra nada.

**Con la API:**

| Paso | Llamada |
|---|---|
| Comensal crea el pedido | `POST /v1/mis/pedidos` + `Idempotency-Key`. Body: `{restaurante: <uuid>, paraLlevar, almuerzo: {platos: [<id sopa>, <id fuerte>, …]}, extras: [{plato, cantidad}]}`. Los ids de plato salen de `menuHoy.secciones[].platos[].id` de `GET /v1/restaurantes/{slug}`. |
| El servidor decide el precio | Respuesta `PedidoResponse`: `numero` ("Pedido #7"), `qr` (= `id` del pedido), `estado: EN_CAMINO`, `almuerzo.cubiertoPorPlan`, `almuerzo.precioCentavos` (0 si un plan lo cubre), `totalCentavos`, `venceEn` (= creación + 30 min). |
| Reglas del servidor | Un pedido en camino a la vez por local (`409 PEDIDO_ACTIVO`). Menú sin publicar → `409 MENU_NO_PUBLICADO`. Plato agotado → `409 PLATO_AGOTADO`. |
| La caja lo ve | `GET /v1/caja/pedidos` (por defecto las activas, ordenadas por `numero`). Cada `PedidoCaja` trae `comensal.nombre`, `almuerzo.platos`, `almuerzo.cubiertoPorPlan`, `totalCentavos`, `estado`, `creadoEn`. |
| Tiempo real | **No hay websockets ni push.** La app hace **polling** (sección 5.9): O12 cada 8 s mientras está abierta; C8 y el aviso de entrega cada 5 s mientras haya un pedido activo. |

Mapeo a la UI de O12 (`OwnerOrder`): ver sección 8, O12.

**Aceptación:** crear un pedido desde el emulador del comensal y verlo aparecer en O12 del dueño en menos de 10 s, con el nombre del comensal, sopa y segundo. Si el local tiene un plan del comensal, `paidByPlan = true` y no se pide efectivo.

#### 4.1.2 Validar y entregar en O12 → "Tu pedido · Entregado" en el comensal

**Hoy:**
- Pedido **en efectivo**: tarjeta con "$3,00 en efectivo" y "Cobrar y entregar" (morado tonal). Abre la hoja "Cobrar pedido #N" con "Cobré $X · Entregar" (morado relleno).
- Pedido **cubierto por plan**: botón "Validar QR" (descuenta 1 almuerzo del plan); luego aparece el badge verde "Validado" y el botón "Entregar" (morado tonal). No se cobra nada.
- Al entregar, el comensal ve la hoja **"Tu pedido · Entregado · Buen provecho"** ("Pagaste $X en efectivo." o "Se descontó 1 almuerzo de tu plan.").

**Con la API (máquina de estados del pedido):**

```text
EN_CAMINO --POST /v1/caja/pedidos/{id}/canjear--> CANJEADA --POST /v1/caja/pedidos/{id}/servir--> SERVIDA
    |  (30 min sin validar)                          (409 PEDIDO_NO_CANJEADO si se intenta servir antes)
    v
 EXPIRADA            (el comensal puede cancelar solo en EN_CAMINO: POST /v1/mis/pedidos/{id}/cancelar)
```

| Acción en la app | Llamadas |
|---|---|
| "Validar QR" (con plan) | `POST /v1/caja/pedidos/{id}/canjear` + `Idempotency-Key`. Si el comensal es cliente y el pedido lleva almuerzo, **descuenta del plan que vence primero** (canal `PREORDEN`). Devuelve `{pedido, yaCanjeado, almuerzo: {resultado, mensaje, descontado, consumoId}, porCobrarCentavos}`. Si `almuerzo.resultado` no es `OK` ni `OK_ADVERTENCIA` (por ejemplo `SIN_SALDO`), mostrar el mensaje traducido y **no** pasar a "Validado". |
| "Entregar" (con plan) | `POST /v1/caja/pedidos/{id}/servir`. |
| "Cobrar y entregar" (efectivo) | 1) `POST …/canjear` (+ IK). 2) Verificar `porCobrarCentavos` (lo que se cobra aparte). 3) `POST …/servir`. Ver la **verificación de caja** en la nota siguiente. |
| Aviso al comensal | El comensal hace polling de `GET /v1/mis/pedidos/{id}`. Cuando `estado == SERVIDA` y no se ha mostrado antes, abre `DeliveredOrderSheet`. El "ya lo vi" (`acknowledgeOrder`) se guarda **en el teléfono** (clave `pedido_visto_<id>` en `shared_preferences`): la API no tiene un "visto". |
| Descuento del saldo | Lo hace el servidor al canjear. La app solo refresca `GET /v1/pase`. |

> **Nota de verificación de caja (obligatoria en la Fase 3):** el Swagger dice que `canjear` devuelve `porCobrarCentavos` ("lo que la caja cobra aparte") y que el cierre cuenta "pedidos" como origen de ingreso (`ingresos.porOrigen.pedidos`). **No dice si el servidor ya registra ese efectivo al canjear.** Prueba: canjear un pedido en efectivo y consultar `GET /v1/caja/cierre/hoy` y `GET /v1/reportes/resumen-diario`. Si `efectivoEsperadoCentavos` subió, no hagas nada más. Si no subió, registra el cobro con `POST /v1/caja/ventas` (`tipo: ALMUERZO`, `cantidad: 1`, `EFECTIVO`, `mesaTexto: "Pedido #N"`) y avisa a Chucho. **Nunca cobres dos veces.**

> **Deshacer:** el backend **no** tiene "deshacer entrega" ni "deshacer validación de pedido". Solo existe `POST /v1/caja/consumos/{id}/deshacer` (10 s) para el consumo que creó el canje (`almuerzo.consumoId`). Plan B: patrón commit diferido (sección 10.2) para "Entregar", y para "Validar QR" usar `consumos/{consumoId}/deshacer` si el pedido sigue en `CANJEADA`.

**Aceptación:** con un pedido de plan: Validar QR → el saldo del comensal baja 1 y la tarjeta muestra "Validado"; Entregar → en ≤5 s el comensal ve "Tu pedido · Entregado". Con un pedido en efectivo: Cobrar y entregar → el comensal ve "Pagaste $X en efectivo" y el efectivo esperado del cierre sube exactamente $X (una sola vez).

#### 4.1.3 Mesas compartidas (C9, C7) y cobro en O5

**Hoy:**
- C9 `Mesa con amigos` (`table_sheet.dart`): el anfitrión elige hora (12:30 a 14:00), ve el QR de la mesa (`BCD-MESA-{id}`), comparte el enlace, elige el modo **"Cada quien lo suyo"** o **"Yo invito la mesa"** y ve a los miembros ("Anfitrión", "En local", "Para llevar").
- C7 `Unirme a mesa` (`join_table_screen.dart`): el invitado pone nombre, sopa, plato fuerte y modalidad.
- O5 `Cobrar mesa` (`cobrar_mesa_sheet.dart`): lista de integrantes con su vía de pago (Plan prepagado, Plan del anfitrión, Paga suelto), modo, total en efectivo y sellos. Un botón cobra a toda la mesa. También se abre desde el banner de Caja y desde el escáner.

**Con la API:**

| Acción | Llamada |
|---|---|
| Crear mesa (C9) | `POST /v1/mis/mesas` + IK. Body `{restaurante, horaLlegada (ISO, de ahora a 12 h), modo: CADA_UNO\|INVITO_YO, paraLlevar}`. El anfitrión entra como primer miembro. Respuesta `MesaResponse` con `id`, `invitacion`, `miembros`, `estado: ABIERTA`. |
| Enlace de invitación | `bocadoo://mesa/<invitacion>` (así lo declara el backend). Ver deep link en 4.7. |
| Ver mi mesa | `GET /v1/mis/mesas/{id}` (polling 8 s mientras C9 está abierta) o `GET /v1/mis/mesas` para encontrar la activa. |
| Validar invitación (C7) | `GET /v1/mesas/invitacion/{id}` → `{restaurante, anfitrion, horaLlegada, modo, estado, personas, capacidad, puedeUnirse, motivo}`. |
| Unirse (C7) | `POST /v1/mesas/invitacion/{id}/unirse` + IK, body `{paraLlevar}`. Unirse dos veces no duplica. |
| Cancelar | `POST /v1/mis/mesas/{id}/cancelar` (solo el anfitrión: `403 SOLO_ANFITRION`; si la caja ya la validó: `409 MESA_CERRADA`). |
| Vista previa en caja (O5) | `GET /v1/caja/mesas/{id}` → `{modo, estado, horaLlegada, validadaEn, personas, cubiertos, miembros: [{nombre, esAnfitrion, paraLlevar, tieneCuenta, almuerzosDisponibles}]}`. |
| Cobrar la mesa (O5) | `POST /v1/caja/mesas/{id}/validar` + IK. `CADA_UNO`: cada quien con su plan. `INVITO_YO`: paga el anfitrión. Los que no tienen plan quedan **por cobrar**. Devuelve `{resultados: [{miembro, resultado, descontado, consumoId}], descontados, porCobrar, yaValidada, …}`. |

**Cómo se calcula la UI de O5 con esos datos** (el servidor no manda "quién paga cómo"):
- `CADA_UNO`: si `tieneCuenta && almuerzosDisponibles > 0` → "Plan prepagado"; si no → "Paga suelto" (precio suelto del local + recargo si `paraLlevar`).
- `INVITO_YO`: todos "Plan del anfitrión". Si el anfitrión tiene `almuerzosDisponibles < personas`, `cubiertos < personas` y la UI muestra el aviso "El plan de {anfitrión} no alcanza…".
- Precio suelto y recargo salen de `GET /v1/restaurante` (`precioSueltoCentavos`, `recargoParaLlevarCentavos`).
- Después de `validar`, si `porCobrar > 0`, la app registra el efectivo con `POST /v1/caja/ventas` (`ALMUERZO × porCobrar`, `EFECTIVO`, `mesaTexto: "Mesa <id>"`) — **sujeto a la misma verificación de caja de 4.1.2**.
- Sellos: el servidor suma un sello por almuerzo validado (`GET /v1/mis/sellos`); la línea "Sellos: Carlos +1" se arma con `resultados`.

**Brechas (plan B en la sección 10):** (a) no hay endpoint para **cambiar el modo** después de crear la mesa; (b) no hay "avisar a cocina"; (c) `unirse` **no recibe sopa ni plato fuerte** (solo `paraLlevar`); (d) **no hay endpoint para listar las mesas pendientes de la caja** (el banner de Caja); (e) el nombre del invitado sale de su cuenta.

**Aceptación:** un comensal crea la mesa; otro entra por el enlace; en Caja se escanea `BCD-MESA-<id>` y se ve a ambos; "Cobrar" descuenta los planes y la mesa pasa a `FINALIZADA` (el comensal lo ve en ≤8 s).

#### 4.1.4 Escáner universal de Caja (O2): 3 tipos de QR

**Hoy** (`OwnerController.onCodeDetected`, `owner_controller.dart`):
- `BCD-MESA-<id>` → estado `OwnerRedirect('/owner/cobrar-mesa/<id>')`.
- `BCD-ORD-<n>` → `OwnerRedirect('/owner/pedidos?cobrar=<n>')`.
- cualquier otro → pase de plan (`validateQrCode` + `confirmRedeem`).
- `openScannerFlow` (`scan_result_screen.dart`) abre el escáner; si el estado es `OwnerRedirect`, navega a esa ruta.

**Con la API, el reconocimiento queda así** (en este orden):

| Contenido leído | Qué es | Acción |
|---|---|---|
| empieza con `BCD1.` | Pase de plan (lo genera el backend en `GET /v1/pase` o `/v1/pase/codigo`) | `POST /v1/caja/validar` con `{codigoQr: <texto tal cual>}` |
| empieza con `BCD-MESA-` | Mesa compartida (convención **de la app**; el backend solo da el `id`) | `OwnerRedirect('/owner/cobrar-mesa/<id>')` |
| empieza con `BCD-ORD-` | Pedido (convención de la app) | `OwnerRedirect('/owner/pedidos?cobrar=<id o número>')` |
| un UUID suelto | Pedido: el backend dice que el QR del pedido **es** su `id` (`qr`) | `GET /v1/caja/pedidos/{id}`; si existe → `OwnerRedirect('/owner/pedidos?cobrar=<numero>')` |
| otra cosa | Inválido | Estado "Código no legible" |

Decisiones:
- **La app arma el QR de la mesa como `BCD-MESA-<id de la mesa>`** (el `id` de `MesaResponse`) para distinguirlo de un pedido, ya que los dos son UUID.
- **El QR del pedido que dibuja el comensal es el `qr` que devuelve el backend** (no se inventa otro). La app puede mostrar al lado el texto "Pedido #<numero>".
- Para ingresar código a mano: aceptar el número del pedido (`#43`) y resolverlo contra `GET /v1/caja/pedidos`.
- En modo API **`BocadooQrParser.parseAndValidate` no se usa** (el servidor valida firma y ventana de 30 s).
- El **simulador de tokens** del escáner (hoja de pruebas con "Token válido", "Mesa M1234", "Preorden #43") queda **solo en modo mock** (`AppMode.useMock`).

**Diferencia de comportamiento clave:** en el mock, escanear = `validateQrCode` (solo lee) y luego `confirmRedeem` (descuenta). **En la API `POST /v1/caja/validar` ya descuenta** (`descontado: true`). Por eso en `ApiOwnerRepository`:
- `validateQrCode(raw)` hace la llamada, devuelve el `ScanResult` ya con el descuento y guarda `consumo.id` en un mapa interno `passId → consumoId` (con `ScanResult.passId = cliente.id`).
- `confirmRedeem(passId)` devuelve `true` **sin llamar a la API**.
- `undoRedeem(passId)` llama a `POST /v1/caja/consumos/{consumoId}/deshacer` (solo funciona 10 s).

Mapeo `resultado` → `ScanResult` (la UI ya sabe pintar estos cuatro `outcome`):

| `resultado` | `outcome` | `title` (UI) | `actionRequired` |
|---|---|---|---|
| `OK` | `VERDE` | "Almuerzo registrado" | `NINGUNA` |
| `OK_ADVERTENCIA` | `ADVERTENCIA` | "Último almuerzo" si `almuerzosRestantes == 0`; si no "Vence pronto" | `VENDER_PLAN` |
| `DUPLICADO` | `GRIS` | "Ya validado" | `NINGUNA` |
| `SIN_PLAN`, `SIN_SALDO`, `VENCIDO` | `ROJO` | "Sin plan" / "Sin saldo activo" / "Plan vencido" | `VENDER_PLAN` |
| `DIA_NO_VALIDO` | `ROJO` | "Su plan no vale hoy" | `NINGUNA` |
| `OTRO_LOCAL` | `ROJO` | "Es de otro local" | `VENDER_PLAN` |
| `QR_EXPIRADO` | `ROJO` | "Código vencido" ("Pide al comensal abrir su app.") | `COBRAR_SUELTO` |
| `QR_INVALIDO` | `ROJO` | "QR no válido" | `NINGUNA` |
| `LIMITE_SAAS` | `ROJO` | "Llegaste al límite de tu plan Bocadoo" | `NINGUNA` |

**Aceptación:** un mismo escáner reconoce un pase real (descuenta y muestra "Le quedan N almuerzos"), una mesa (abre O5) y un pedido (abre O12 con la hoja de cobro o de validación).

### 4.2 Registro del comensal con mapa

**Hoy:** `register_diner_screen.dart` captura nombre, correo, celular, **zona** (chips), **ubicación exacta** con `LocationPickerMap` (`core/widgets/location_picker_map.dart`: `flutter_map` + OpenStreetMap, se toca el mapa o "Mi GPS" con `geolocator`) y contraseña. Al terminar navega a `/auth/bienvenida/comensal` con `extra: {nombre, zona, lat, lng}` (`lat`/`lng` como texto).

**Con la API:** `POST /v1/auth/register` solo acepta `{nombre, correo, password (10 a 128), nombreUsuario?, aceptaTerminos (true)}`. **No acepta teléfono, zona, latitud ni longitud.** Plan:

1. Registrar con los campos que sí acepta y luego hacer login (`POST /v1/auth/login`) para obtener tokens.
2. **Guardar localmente** teléfono, zona y coordenadas en `LocalProfileStore` (nuevo, `shared_preferences`, claves `perfil_telefono`, `perfil_zona`, `perfil_lat`, `perfil_lng`). Así C2 puede ordenar por cercanía y C6 puede mostrar el teléfono.
3. Enviar un evento de analítica `registro.ubicacion` con `POST /v1/eventos` (`propiedades: {zona, lat, lng}`; el backend lo guarda sin identidad si no hay consentimiento).
4. **Pedir a Chucho** que `RegisterDto` y un nuevo `PATCH /v1/auth/me` acepten `telefono`, `zonaId`, `latitud`, `longitud` (sección 10, B-02). Cuando exista, un solo `TODO(backend)` lo conecta.

Para C2/C11 las coordenadas del comensal se usan **en el teléfono** (distancia Haversine contra `latitud`/`longitud` de cada local). El servidor no filtra por distancia.

**Aceptación:** registrar un comensal con zona y pin → login automático → entra a la bienvenida con su nombre y zona → Dónde comer ordena "Cerca" con su pin.

### 4.3 Google Sign-In directo

**Hoy:** se eliminó la pantalla intermedia de cuentas (`google_account_screen.dart` y la ruta `/auth/google`). Los botones de A1, A4 y A5 llaman a `continueWithGoogle(context, role:)` (`google_sign_in_flow.dart`): muestra "Conectando con Google" un instante y enruta por rol. **Hoy lo simula.**

**El backend NO tiene un endpoint de Google** (revisados los 97 paths). Ver sección 6.4 para el plan completo (paquete `google_sign_in`, endpoint pedido a Chucho y comportamiento mientras no exista).

### 4.4 Módulo del Dueño: lo que no debe perderse

| Pantalla | Comportamiento que se conserva | Fuente API (detalle en sección 8) |
|---|---|---|
| **O7 Menú** | "Hay / Se acabó" **plato por plato, en vivo**, sin despublicar todo el menú; catálogo "Mis platos" (Almuerzos, Desayunos, A la carta); archivar sin borrar. | `PATCH /v1/menu/{fecha}/items/{id}/agotado` (rol Caja); catálogo `GET/POST/PATCH /v1/menu/platos` |
| **O8 Planes y clientes** | Botón `+` **"Agregar cliente"** (hoja con nombre, celular, correo y notas opcionales) y "Guardar y vender plan"; venta rápida de planes (O3) con Efectivo, Transferencia y Deuna. | `POST /v1/clientes`, `POST /v1/clientes/{id}/planes` |
| **O9 Crear / editar plan** | Precios y vigencias sincronizados: **Mensual $55 / 30 días, Quincenal $28 / 15 días, Semanal $15 / 7 días, Libre $32 / 60 días.** | `POST /v1/planes`, `PATCH /v1/planes/{id}` |
| **O14 Tus números** | Pestañas Hoy (con el **valor aproximado** "$X,XX aprox." = servidos × precio del almuerzo suelto), Dinero y Clientes. | `GET /v1/reportes/*` |
| **O15 Opiniones** y **C10** | Calificación tras **25 min** de validar; etiquetas Rico, Rápido, Porción **más la nota escrita**; "Reponer almuerzo" (+1 al saldo). | `GET /v1/mis/opiniones/pendientes`, `POST /v1/mis/consumos/{id}/opinion`, `GET /v1/opiniones`, `POST /v1/opiniones/{id}/responder` |
| **O16 Ajustes** | Rol Dueño vs Cajero / Ayudante (cambia la barra a **Caja, Pedidos, Turno**), logo con `image_picker`, resumen semanal con vista previa **sin emojis**, soporte configurable sin número fijo. | `GET/PATCH /v1/restaurante`, `GET /v1/auth/me` |

### 4.5 Mapas internos (C11 y registro)

`flutter_map` + `geolocator`, siempre dentro de la app. No se abre Google Maps externo.
- **Teselas:** OpenStreetMap (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`, `userAgentPackageName: 'ec.bocadoo.bocadoo'`). Las teselas públicas son para demo: **pedir una solución para producción** (sección 10, B-14).
- **Ruta a pie:** `walking_route_service.dart` consulta el OSRM público de FOSSGIS. Si falla, dibuja una línea directa marcada "Ruta aproximada". Es un servicio de terceros: enviarle origen y destino es un dato de ubicación. **Antes de producción hay que reemplazarlo** por un servicio propio o con clave (B-14).
- Coordenadas de los locales: `RestauranteCardResponse.latitud/longitud` (pueden ser `null`; la app ya lo tolera con `Restaurant.hasLocation`).
- Permisos Android: `ACCESS_FINE_LOCATION` y `ACCESS_COARSE_LOCATION` (ya en el manifiesto).

### 4.6 Aviso de entrega y regla de pedido único

- Un comensal solo puede tener **un pedido en camino por local** (`409 PEDIDO_ACTIVO`). La UI ya impide pedir si hay uno activo (`CustomerController.preorder`); además hay que traducir el `409` por si otro dispositivo creó uno.
- `getActiveOrder()` debe devolver el pedido `EN_CAMINO` o `CANJEADA` (como `PREPARANDO` / `LISTO`) **o** uno `SERVIDA` que el comensal todavía no vio. Sale de `GET /v1/mis/pedidos?limit=5`.

### 4.7 Enlace profundo de las mesas (resuelve B12 de la Fase 5)

El backend declara el enlace como `bocadoo://mesa/<invitacion>`. Para que abra la app:
1. `AndroidManifest.xml`: dentro de `<activity>`, un `<intent-filter>` con `action VIEW`, categorías `DEFAULT` y `BROWSABLE`, `<data android:scheme="bocadoo" android:host="mesa"/>`.
2. En `app_router.dart`, un `redirect` que convierta `bocadoo://mesa/<id>` en `/customer/mesa/<id>` (go_router recibe el URI completo).
3. `SharedTable.shareUrl` pasa a ser `bocadoo://mesa/<invitacion>`. Para compartir por WhatsApp, un enlace `bocadoo://` no es clicable en todos los chats: **pedir a Chucho una página web puente** `https://bocadoo.ec/mesa/<id>` que redirija al esquema (B-11). Mientras tanto se comparte el texto con el enlace `bocadoo://` **y** el código.
4. Si el invitado no tiene sesión: guardar el `id` pendiente, llevarlo a `/login`, y al volver abrir `/customer/mesa/<id>`.

---
## 5. Bloque 0: red, autenticación y seguridad

Todo el Bloque 0 vive en `core/` y se termina **antes** de conectar cualquier pantalla (Fase 1). Nada de esto cambia `presentation/`.

### 5.1 Archivos nuevos

```text
core/config/app_mode.dart            AppMode.useMock, AppMode.apiUrl
core/config/api_capabilities.dart    banderas de funciones que el backend aún no tiene (5.12)
core/network/api_config.dart         (reescribir) URL base, timeouts, rutas
core/network/api_exception.dart      ApiException + ErrorMessages (sección 13)
core/network/token_store.dart        flutter_secure_storage
core/network/api_client.dart         Dio + interceptores + atajos get/post/patch/put
core/network/idempotency.dart        uuidV4() y claves por intención
core/network/polling.dart            ayudas de polling
core/utils/formatters.dart           Money, Phone (E.164), fechas de Ecuador
core/session/session_notifier.dart   sesión, rol y restaurante activo
features/auth/data/auth_repository.dart   IAuthRepository + ApiAuthRepository + MockAuthRepository
```

### 5.2 Configuración (`api_config.dart`, `app_mode.dart`)

Hoy `ApiConfig.baseUrl` apunta a `https://api.bocadoo.app/v1` (un dominio de ejemplo) y las rutas (`/customer/pass`, `/owner/validate-qr`…) **no existen en el backend**. Se reescribe:

```dart
class AppMode {
  AppMode._();
  /// flutter run --dart-define=BOCADOO_USE_MOCK=true  → todo contra mocks (demo sin internet)
  static const useMock = bool.fromEnvironment('BOCADOO_USE_MOCK', defaultValue: false);
  /// flutter run --dart-define=BOCADOO_API_URL=http://10.0.2.2:3000  → apuntar a un backend local
  static const apiUrl = String.fromEnvironment('BOCADOO_API_URL', defaultValue: 'https://bck-bocadoo.onrender.com');
}

class ApiConfig {
  ApiConfig._();
  static const baseUrl = AppMode.apiUrl;          // SIN el /v1: cada ruta lo lleva
  static const v1 = '/v1';
  // Render gratuito se duerme: la primera petición puede tardar. Ver 5.5.
  static const connectTimeout = Duration(seconds: 30);
  static const receiveTimeout = Duration(seconds: 45);
  static const warmUpTimeout = Duration(seconds: 90);
}
```

- El emulador de Android llega al equipo anfitrión por `10.0.2.2`. Si James prueba contra un backend local, usa `--dart-define=BOCADOO_API_URL=http://10.0.2.2:3000` y `android:usesCleartextTraffic="true"` **solo en un manifiesto de depuración** (`android/app/src/debug/AndroidManifest.xml`), nunca en el principal.
- Se borran las constantes de rutas de ejemplo. Las rutas viven en cada repositorio.

### 5.3 Almacenamiento seguro de tokens (`token_store.dart`)

`flutter_secure_storage` ya está en el `pubspec`. Claves: `access_token`, `refresh_token`, `access_expires_at` (ISO), `active_restaurant_id`.

```dart
class TokenStore {
  TokenStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  Future<String?> get access => _s.read(key: 'access_token');
  Future<String?> get refresh => _s.read(key: 'refresh_token');
  Future<String?> get restaurantId => _s.read(key: 'active_restaurant_id');
  Future<DateTime?> get accessExpiresAt async {
    final v = await _s.read(key: 'access_expires_at');
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Guarda el par completo. Cada refresh token sirve UNA vez: siempre se reemplaza el par entero.
  Future<void> saveTokens({required String access, required String refresh, required int expiresInSeconds}) async {
    final exp = DateTime.now().add(Duration(seconds: expiresInSeconds));
    await Future.wait([
      _s.write(key: 'access_token', value: access),
      _s.write(key: 'refresh_token', value: refresh),
      _s.write(key: 'access_expires_at', value: exp.toIso8601String()),
    ]);
  }

  Future<void> setRestaurant(String? id) => id == null
      ? _s.delete(key: 'active_restaurant_id')
      : _s.write(key: 'active_restaurant_id', value: id);

  Future<void> clear() => _s.deleteAll();
}
```

### 5.4 Cliente HTTP (`api_client.dart`)

Un solo `Dio` con 4 interceptores, en este orden: **auth → restaurante → reintento → errores**.

```dart
class ApiClient {
  ApiClient({required TokenStore tokens, required void Function() onSessionExpired}) {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {'Accept': 'application/json'},
      contentType: 'application/json',
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ));
    final refreshDio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl, connectTimeout: ApiConfig.connectTimeout));
    dio.interceptors.addAll([
      AuthInterceptor(dio, refreshDio, tokens, onSessionExpired),
      RestaurantInterceptor(tokens),
      RetryInterceptor(dio),
      ProblemInterceptor(),
      if (kDebugMode) LogInterceptor(requestHeader: false, responseHeader: false), // sin Authorization
    ]);
  }
  late final Dio dio;

  /// Cuerpo de respuesta como mapa.
  Future<Map<String, dynamic>> getMap(String path, {Map<String, dynamic>? query, bool restaurant = false}) async =>
      (await dio.get<Map<String, dynamic>>(path, queryParameters: query, options: _o(restaurant: restaurant))).data!;
  Future<List<dynamic>> getList(String path, {Map<String, dynamic>? query, bool restaurant = false}) async =>
      (await dio.get<List<dynamic>>(path, queryParameters: query, options: _o(restaurant: restaurant))).data!;

  /// POST/PATCH/PUT. `idempotencyKey` != null → agrega el encabezado y permite reintentar.
  Future<T?> send<T>(String method, String path, {Object? body, bool restaurant = false, String? idempotencyKey, bool auth = true}) async {
    final r = await dio.request<T>(path, data: body, options: _o(method: method, restaurant: restaurant, idempotencyKey: idempotencyKey, auth: auth));
    return r.data;
  }

  Options _o({String? method, bool restaurant = false, String? idempotencyKey, bool auth = true}) => Options(
        method: method,
        headers: {if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey},
        extra: {'restaurant': restaurant, 'auth': auth, 'retryable': idempotencyKey != null},
      );
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final session = ref.watch(sessionProvider);
  return ApiClient(tokens: session.tokens, onSessionExpired: session.expire);
});
```

**`AuthInterceptor`** (el más delicado):
- `onRequest`: si `extra['auth'] == false` (login, registro, refresh, rutas públicas) deja pasar. Si no, **antes de enviar** comprueba `accessExpiresAt`: si faltan menos de 60 s, refresca. Pone `Authorization: Bearer <access>`.
- `onError` con `401`: refresca **una sola vez** y reintenta la petición. Marca `extra['retried'] = true` para no entrar en bucle.
- **Refresh de un solo vuelo (single-flight):** mientras haya un refresh en curso, todas las demás peticiones esperan el mismo `Future<bool>`. Esto es obligatorio: el refresh token es de **un solo uso** y reutilizarlo **revoca toda la sesión** (`POST /v1/auth/refresh`).
- Si el refresh responde `400` o `401`, se hace `tokens.clear()`, se llama `onSessionExpired()` (que lleva a `/login` con el aviso "Tu sesión venció. Entra de nuevo.") y se rechaza la petición.

```dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, this._refreshDio, this._tokens, this._onExpired);
  final Dio _dio, _refreshDio;
  final TokenStore _tokens;
  final void Function() _onExpired;
  Future<bool>? _refreshing;

  Future<bool> _refresh() => _refreshing ??= () async {
        try {
          final rt = await _tokens.refresh;
          if (rt == null) return false;
          final r = await _refreshDio.post<Map<String, dynamic>>('/v1/auth/refresh', data: {'refreshToken': rt});
          final d = r.data!;
          await _tokens.saveTokens(access: d['accessToken'], refresh: d['refreshToken'], expiresInSeconds: d['expiresIn']);
          return true;
        } on DioException catch (e) {
          final s = e.response?.statusCode;
          if (s == 400 || s == 401) { await _tokens.clear(); _onExpired(); }
          return false;               // sin red: NO se cierra la sesión
        } finally {
          _refreshing = null;
        }
      }();

  @override
  Future<void> onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    if (o.extra['auth'] == false) return h.next(o);
    final exp = await _tokens.accessExpiresAt;
    if (exp != null && exp.difference(DateTime.now()) < const Duration(seconds: 60)) await _refresh();
    final t = await _tokens.access;
    if (t != null) o.headers['Authorization'] = 'Bearer $t';
    h.next(o);
  }

  @override
  Future<void> onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    if (e.response?.statusCode == 401 && o.extra['auth'] != false && o.extra['retried'] != true) {
      if (await _refresh()) {
        o.extra['retried'] = true;
        o.headers['Authorization'] = 'Bearer ${await _tokens.access}';
        try { return h.resolve(await _dio.fetch(o)); } on DioException catch (e2) { return h.next(e2); }
      }
    }
    h.next(e);
  }
}
```

**`RestaurantInterceptor`:** si `extra['restaurant'] == true`, agrega `x-restaurant-id` con el uuid del restaurante activo (`TokenStore.restaurantId`). Si no hay restaurante activo y la ruta lo exige, rechaza localmente con `ApiException(code: 'SIN_RESTAURANTE')`.

**`RetryInterceptor`** (cold start y red inestable): reintenta **hasta 3 veces**, con esperas de 2 s, 5 s y 10 s, **solo si** la petición es un `GET` o lleva `Idempotency-Key` (`extra['retryable'] == true`), y solo ante `connectionTimeout`, `receiveTimeout`, `connectionError` o estados `502`, `503`, `504`. **Un `POST` sin clave de idempotencia nunca se reintenta.** Los `4xx` no se reintentan.

**`ProblemInterceptor`:** convierte cualquier `DioException` en un `DioException` cuyo `error` es un `ApiException` (sección 5.6), de modo que los repositorios hacen:

```dart
Future<T> guard<T>(Future<T> Function() f) async {
  try { return await f(); }
  on DioException catch (e) { throw (e.error is ApiException) ? e.error as ApiException : ApiException.network(); }
}
```

### 5.5 Arranque en frío de Render

En el plan gratuito, Render apaga el servicio tras unos minutos sin tráfico; la primera petición puede tardar de 30 a 60 s y a veces responde `502/503`. Medidas:

1. **Calentar al abrir la app:** en el arranque (pantalla de login o splash) lanzar `GET /health` con `receiveTimeout: 90 s`, sin bloquear la UI. Si tarda más de 4 s, mostrar bajo el botón el texto "Despertando el servidor… puede tardar un momento." (un `Text` de 13 px con el color secundario del tema; es el único texto nuevo permitido).
2. **Timeouts amplios** en el primer intento (`connectTimeout 30 s`, `receiveTimeout 45 s`) y reintentos con espera (5.4).
3. **Nunca mostrar "Error 502".** Si tras los reintentos sigue fallando: "No pudimos conectar con el servidor. Revisa tu conexión e inténtalo de nuevo." con "Reintentar".
4. En pruebas de humo (sección 12), la primera llamada del día se mide aparte.

### 5.6 `ApiException` y mapeo global de errores HTTP

```dart
class ApiException implements Exception {
  ApiException({this.status, required this.code, this.detail = '', this.requestId, this.isNetwork = false});
  final int? status;
  final String code;       // el `code` del problem+json, o el nombre HTTP, o 'SIN_CONEXION'
  final String detail;     // texto del servidor: SOLO para logs, nunca para la UI
  final String? requestId; // para soporte
  final bool isNetwork;

  factory ApiException.network() => ApiException(code: 'SIN_CONEXION', isNetwork: true);
  factory ApiException.fromResponse(Response r) {
    final d = r.data is Map ? r.data as Map : const {};
    return ApiException(status: r.statusCode, code: (d['code'] ?? 'ERROR_INTERNO').toString(),
        detail: (d['detail'] ?? '').toString(), requestId: d['requestId']?.toString());
  }
  String get userMessage => ErrorMessages.of(this);   // sección 13
}
```

| HTTP | Qué significa en Bocadoo | Qué hace la app |
|---|---|---|
| **400** `BAD_REQUEST` y específicos (`PEDIDO_VACIO`, `FECHA_INVALIDA`, `CURSOR_INVALIDO`, `IDEMPOTENCY_KEY_INVALIDA`…) | Datos inválidos | Mensaje por `code` (sección 13). Si el `code` es genérico: "Revisa los datos e inténtalo de nuevo." |
| **401** `UNAUTHORIZED` | Token vencido o ausente | El interceptor refresca y reintenta una vez. Si falla: sesión vencida, a `/login`. |
| **403** `FORBIDDEN`, `SOLO_ANFITRION`, `EVENTO_USUARIO_AJENO` | Sin permiso: rol insuficiente o local ajeno | "No tienes permiso para hacer esto." Si ocurre en una ruta de dueño con un cajero, volver a Caja. No cerrar sesión. |
| **404** `NOT_FOUND` y específicos (`PEDIDO_NO_ENCONTRADO`, `MESA_NO_ENCONTRADA`, …) | No existe o no es tuyo | Mensaje por `code`. En detalles (ficha, mesa, pedido) mostrar el estado vacío con la acción de volver. |
| **409** `CONFLICT` y específicos (`PEDIDO_ACTIVO`, `MESA_LLENA`, `OFERTA_AGOTADA`, `IDEMPOTENCY_KEY_REUTILIZADA`…) | Conflicto de estado | Mensaje por `code`, y **refrescar los datos** de la pantalla (el estado cambió). |
| **422** (`PLATO_NO_DISPONIBLE`, `PLATO_SIN_PRECIO`, `OFERTA_PRECIO_INVALIDO`, `METODO_PAGO_NO_DISPONIBLE`, `EVENTO_MUY_GRANDE`) | Regla de negocio no cumplida | Mensaje por `code`. |
| **429** `TOO_MANY_REQUESTS`, `EVENTOS_LIMITE_TASA` | Límite de tasa | "Demasiados intentos. Espera un momento." No reintentar solo. |
| **500** `ERROR_INTERNO` | Fallo del servidor | "Algo salió mal de nuestro lado. Inténtalo en un momento." Guardar `requestId` en el log. |
| **502/503/504** `SERVICE_UNAVAILABLE` | Servicio dormido o caído | Reintentos automáticos (5.4); si persiste, mensaje de conexión. |
| Sin red / timeout | | `ApiException.network()`: "No tienes conexión. Revisa tu internet." Con datos en caché, mostrar el aviso "Sin conexión" (ya existe `isOffline` en `CustomerUiState`). |

### 5.7 Claves de idempotencia (`idempotency.dart`)

Sin el paquete `uuid` (R9), se genera un UUID v4 a mano:

```dart
String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

/// Misma intención del usuario → misma clave durante 2 minutos. Evita el doble cobro si la
/// respuesta se perdió y el usuario vuelve a tocar el botón.
class IdempotencyStore {
  final _keys = <String, ({String key, DateTime at})>{};
  String keyFor(String intent) {
    final v = _keys[intent];
    if (v != null && DateTime.now().difference(v.at) < const Duration(minutes: 2)) return v.key;
    final k = uuidV4();
    _keys[intent] = (key: k, at: DateTime.now());
    return k;
  }
  void done(String intent) => _keys.remove(intent);   // al terminar con éxito
}
```

La `intención` es una cadena estable, por ejemplo `venta-plan:<clienteId>:<planId>:<metodo>`, `canjear-pedido:<pedidoId>`, `crear-pedido:<restauranteId>:<platos ordenados>`. **Una clave no se reutiliza con otro cuerpo** (`409 IDEMPOTENCY_KEY_REUTILIZADA`).

### 5.8 Formatos (`formatters.dart`)

```dart
class Money {
  static double fromCents(int c) => c / 100;
  static int toCents(double v) => (v * 100).round();
}

class Phone {
  /// 0991234567 → +593991234567. Si ya viene con 593 o +, lo normaliza.
  static String toE164(String input) {
    final d = input.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('0')) return '+593${d.substring(1)}';
    if (d.startsWith('593')) return '+$d';
    return '+$d';
  }
  /// +593991234567 → 0991234567 (para mostrar).
  static String toLocal(String? e164) {
    if (e164 == null || e164.isEmpty) return '';
    final d = e164.replaceAll(RegExp(r'\D'), '');
    return d.startsWith('593') ? '0${d.substring(3)}' : d;
  }
}

/// Ecuador es UTC−5 todo el año (sin horario de verano).
class EcuadorTime {
  static DateTime now() => DateTime.now().toUtc().subtract(const Duration(hours: 5));
  /// 'AAAA-MM-DD' de hoy en Ecuador (o usar el literal `hoy` en los paths {fecha}).
  static String today() { final n = now(); return '${n.year}-${_2(n.month)}-${_2(n.day)}'; }
  /// '13:00' de hoy → instante UTC (para `horaLlegada` de las mesas).
  static DateTime todayAtUtc(String hhmm) {
    final p = hhmm.split(':'); final n = now();
    return DateTime.utc(n.year, n.month, n.day, int.parse(p[0]) + 5, int.parse(p[1]));
  }
  static String _2(int v) => v.toString().padLeft(2, '0');
}
```

Fechas que llegan del backend: parsear con `DateTime.parse(...)` y convertir con `.toLocal()` solo para mostrar. Los días `AAAA-MM-DD` (`venceEl`, `fecha`) **no** son instantes: parsearlos como fecha sin zona.

### 5.9 Polling (no hay tiempo real)

El backend **no tiene websockets, SSE ni push**. La sincronización Comensal ↔ Dueño es por consultas periódicas, y **solo mientras la pantalla está visible**:

| Quién | Qué consulta | Cada | Se detiene cuando |
|---|---|---|---|
| Dueño, O12 y franja "N en camino" de Caja | `GET /v1/caja/pedidos` | 8 s | se sale de la pantalla |
| Comensal, C8 / aviso de entrega | `GET /v1/mis/pedidos/{id}` | 5 s | el pedido llega a `SERVIDA`, `EXPIRADA` o `CANCELADA` |
| Comensal, C9 abierta | `GET /v1/mis/mesas/{id}` | 8 s | se cierra la hoja |
| Comensal, Mi Pase | `GET /v1/pase` (el QR cambia cada 30 s) | `codigo.validoSegundos` | se sale del Pase |
| Dueño, Caja (resumen) | `GET /v1/caja/cierre/hoy` | 30 s | se sale de Caja |

Con los `FutureProvider.autoDispose` del dueño (que ya usan `skipLoadingOnReload` en O12), el patrón mínimo es:

```dart
final activeOrdersProvider = FutureProvider.autoDispose<List<OwnerOrder>>((ref) {
  final t = Timer(const Duration(seconds: 8), ref.invalidateSelf);   // se cancela solo al salir
  ref.onDispose(t.cancel);
  return ref.read(ownerOrdersRepositoryProvider).getActiveOrders(ref.read(ownerRestaurantIdProvider));
});
```

Para el comensal (un `ChangeNotifier`), el `CustomerController` mantiene un `Timer.periodic` de 5 s que llama a `refreshLive()` mientras `activeOrder != null`, y lo cancela en `dispose()`. **Pausar el polling cuando la app va a segundo plano** (`WidgetsBindingObserver`). Esto es lo que mantiene a Render dormido menos tiempo, pero también cuida la batería y el límite de tasa (`429`).

### 5.10 Sesión, rol y guardia del router

```dart
enum AppRole { diner, owner, cashier }

class SessionNotifier extends ChangeNotifier {
  final tokens = TokenStore();
  bool isAuthenticated = false;
  String? userId, userName;
  List<MeRestaurant> restaurants = const [];        // de GET /v1/auth/me
  String? activeRestaurantId;
  String? expiredMessage;                            // "Tu sesión venció…"

  bool get hasRestaurant => restaurants.isNotEmpty;
  MeRestaurant? get activeRestaurant => restaurants.where((r) => r.id == activeRestaurantId).firstOrNull;
  /// CAJERO de verdad (por la cuenta): el rol del dispositivo no puede subir a Dueño.
  bool get isCashierAccount => activeRestaurant?.rol == 'CAJERO';

  Future<void> loadFromStorage() async { /* si hay refresh token → refrescar y GET /v1/auth/me */ }
  Future<void> onLogin(TokenResponse t) async { /* guarda tokens → GET /v1/auth/me → elige restaurante */ }
  void expire() { isAuthenticated = false; expiredMessage = 'Tu sesión venció. Entra de nuevo.'; notifyListeners(); }
  Future<void> logout() async { /* POST /v1/auth/logout con el refreshToken; tokens.clear(); */ }
}
final sessionProvider = Provider<SessionNotifier>((ref) => sessionNotifier);   // singleton global
```

`app_router.dart` recibe la sesión:

```dart
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  refreshListenable: sessionNotifier,
  redirect: (context, state) {
    if (AppMode.useMock) return null;                      // el modo mock no exige sesión
    final path = state.uri.path;
    final isPublic = path == '/login' || path.startsWith('/auth/');
    if (!sessionNotifier.isAuthenticated) return isPublic ? null : '/login';
    if (path == '/login') return sessionNotifier.hasRestaurant ? '/owner/caja' : '/customer/pase';
    if (path.startsWith('/owner/') && !sessionNotifier.hasRestaurant) return '/customer/pase';
    return null;
  },
  routes: [ … ],
);
```

Reglas de rol:
- `GET /v1/auth/me` → `restaurantes: []` = **comensal**. Con al menos un elemento = **dueño** (`rol: DUENO`) o **cajero** (`rol: CAJERO`).
- Un dueño también es un usuario normal: puede usar las pantallas de comensal con la misma sesión. La pestaña "Dueño / Comensal" de A1 decide a dónde entra.
- **A1 pestaña "Dueño" con una cuenta sin restaurantes:** mensaje "Esta cuenta no tiene un restaurante. Regístrate como dueño o entra como comensal." No se entra.
- **Varios restaurantes:** no hay selector en la UI. Se toma el primero y se guarda en `active_restaurant_id` (anotar en la sección 10, B-13).
- **Cuenta cajero:** `ownerRoleProvider` arranca en `cashier` y `ApiCapabilities.canSwitchToOwner` es `false` (el selector de rol de O16 deja el botón "Dueño (Todo)" desactivado). Un cajero real **no puede** llamar a endpoints de Dueño (`403`).
- **Modo cajero del dispositivo en una cuenta dueño:** es una restricción **solo visual** (la barra y las pantallas). El servidor sigue aceptando todo lo del dueño. Es el comportamiento acordado.
- **Cerrar sesión (A1 / O16 / C6):** `POST /v1/auth/logout` con `{refreshToken}`, `tokens.clear()`, limpiar el estado de Riverpod (`ref.invalidate` de los providers de datos) y `context.go('/login')`.

### 5.11 Seguridad

- **Tokens solo en `flutter_secure_storage`.** Nunca en `shared_preferences`, nunca en logs, nunca en `extra` del router.
- `LogInterceptor` solo en `kDebugMode` y **sin** cabeceras ni cuerpos de `/auth/*`.
- **HTTPS siempre.** No habilitar `usesCleartextTraffic` en el manifiesto principal.
- Build de release: `flutter build apk --release --obfuscate --split-debug-info=build/symbols`.
- Los datos de otro usuario no deben sobrevivir al cierre de sesión: limpiar `LocalCustomerCache`, `LocalProfileStore` y los providers.
- `android:allowBackup="false"` en el manifiesto para que la copia de seguridad de Android no incluya el almacén seguro.
- No imprimir contraseñas. Los campos de contraseña ya usan `obscureText`.
- El `requestId` de los errores se muestra solo en el log de depuración y en el diálogo de "Reportar problema" si existe; la UI normal no lo muestra.
- Los permisos de la app son los mínimos: `INTERNET`, `CAMERA` (escáner), ubicación (mapas y registro).

### 5.12 Banderas de capacidades (`api_capabilities.dart`)

Una clase de constantes que el código de `presentation/` lee (ajuste E3) para ocultar controles cuyo endpoint no existe. **Cuando el backend entrega el endpoint, se cambia la bandera a `true` y se conecta el repositorio.**

```dart
class ApiCapabilities {
  ApiCapabilities._();
  static bool get _api => !AppMode.useMock;

  // Mesas compartidas
  static bool get sharedTableModeChange   => !_api;   // no hay PATCH de modo
  static bool get sharedTableNotifyKitchen => !_api;  // no hay "avisar a cocina"
  static bool get sharedTableDishChoice   => !_api;   // unirse no recibe sopa ni fuerte
  static bool get ownerPendingTablesList  => !_api;   // no hay listado de mesas para la caja
  // Auth
  static bool get googleSignIn            => !_api;   // sin endpoint (B-01)
  static bool get forgotPassword          => !_api;   // sin endpoint (B-03)
  // Dueño
  static bool get cardPayment             => !_api;   // el backend no tiene tarjeta
  static bool get flashScheduledOffer     => !_api;   // solo oferta que empieza al publicar
  static bool get weeklySummaryToggle     => !_api;   // sin endpoint
  static bool get expiredLunchesReport    => !_api;   // sin reporte
  static bool get peakByWeekday           => !_api;   // horas-pico no trae día de semana
  static bool get salesByMethodRange      => !_api;   // ventas-planes no trae método
  static bool get orderUndoDelivery       => !_api;   // sin deshacer entrega
  // Comensal
  static bool get claimStampReward        => !_api;   // el premio se usa en caja
  static bool get cancelPlanRequest       => !_api;   // sin cancelar solicitud
  static bool get canSwitchToOwner        => true;    // false si la cuenta es CAJERO (ver 5.10)
}
```

Cuando el backend entregue cada endpoint, se cambia el `!_api` por `true`. Lo que cada bandera esconde, y el plan B asociado, está en la sección 10.

---
## 6. Bloque 1: Auth (A1 a A7)

Convención de las matrices de las secciones 6, 7 y 8: **Repo** = método del repositorio que se implementa; **Endpoint** = método y ruta del Swagger; **IK** = lleva `Idempotency-Key`; **Plan B** = qué hacer si falta algo (detalle en la sección 10).

### 6.1 Contrato nuevo: `IAuthRepository` (`features/auth/data/auth_repository.dart`)

Las pantallas de auth hoy **no** tienen repositorio: llaman a `Future.delayed` dentro del propio widget (ajuste E1). Se crea:

```dart
abstract class IAuthRepository {
  Future<AuthResult> login({required String identifier, required String password});
  Future<void> registerDiner({required String name, required String email, required String password});
  Future<void> registerOwner({required String ownerName, required String email, required String password, required String restaurantName});
  Future<MeInfo> me();                       // GET /v1/auth/me
  Future<void> logout();                     // POST /v1/auth/logout
  Future<void> logoutAll();                  // POST /v1/auth/logout-all
  Future<AuthResult> signInWithGoogle({required String role});   // sin endpoint: ver 6.4
  Future<bool> requestPasswordReset(String email);               // sin endpoint: ver 6.5
}
class AuthResult { final bool ok; final String? errorMessage; final bool hasRestaurant; }
class MeInfo { final String userId, name; final List<MeRestaurant> restaurants; }
class MeRestaurant { final String id, name, rol; }   // rol: DUENO | CAJERO
```

`MockAuthRepository` conserva el comportamiento actual (espera simulada y entra). `ApiAuthRepository` usa `ApiClient`. El provider elige según `AppMode.useMock`.

### 6.2 A1 · Login (`login_screen.dart`)

**Hoy:** pestañas Comensal / Dueño, correo (validado con expresión regular), contraseña, "¿Olvidaste tu contraseña?" (→ A2), "Continuar con Google", "Crear cuenta" (→ A4 o A5), "Ingresar" (→ `/customer/pase` o `/owner/caja`).

| Acción | Repo | Endpoint | Request | Respuesta → destino |
|---|---|---|---|---|
| Ingresar | `login` | `POST /v1/auth/login` (público, sin IK) | `LoginDto {identificador: <correo>, password}` | `TokenResponseDto {accessToken, refreshToken, tokenType, expiresIn: 900, usuario}` → `TokenStore.saveTokens` |
| Datos de sesión | `me` | `GET /v1/auth/me` | — | `{usuario: {id, nombre}, restaurantes: [{id, nombre, rol}]}` → `SessionNotifier` |
| Destino | — | — | — | Pestaña **Comensal** → `/customer/pase`. Pestaña **Dueño** → `/owner/caja` **solo si** `restaurantes` no está vacío; si está vacío, mensaje "Esta cuenta no tiene un restaurante." |

- El backend acepta correo **o nombre de usuario** en `identificador`. La UI solo pide correo: no se cambia.
- Errores: `400` (datos o credenciales inválidos) y `429` (límite de intentos). Credenciales incorrectas → "Correo o contraseña incorrectos." (tratar `400` y `401` igual en este endpoint). `429` → "Demasiados intentos. Espera un momento."
- Al entrar como dueño con rol `CAJERO`, `ownerRoleProvider` arranca en `cashier` (5.10).
- Calentar el servidor al mostrar esta pantalla (5.5).

### 6.3 A4 · Registro de comensal (`register_diner_screen.dart`) → A6

**Hoy:** nombre, correo, celular, zona (chips), **mapa con pin** (4.2), contraseña y confirmación, términos, "Crear cuenta y elegir restaurante", "Registrarme con Google". Navega a `/auth/bienvenida/comensal` con `extra {nombre, zona, lat, lng}`.

| Acción | Repo | Endpoint | Request | Respuesta |
|---|---|---|---|---|
| Crear cuenta | `registerDiner` | `POST /v1/auth/register` (público) | `RegisterDto {nombre, correo, password (10 a 128), aceptaTerminos: true}`. **No** enviar `nombreUsuario` (opcional). | `201 RegisterResponseDto {usuario, restaurante?}` |
| Entrar | `login` | `POST /v1/auth/login` | con el mismo correo y contraseña | tokens |
| Guardar ubicación | — | **ninguno**. Plan B 4.2: `LocalProfileStore` + evento `POST /v1/eventos` | | |
| Bienvenida | — | — | — | `/auth/bienvenida/comensal` con `extra` (A6) |

- Errores: `409 CONFLICT` → "Ya existe una cuenta con ese correo. Entra o recupera tu contraseña." `400` → mensaje de validación.
- **Ajuste E2:** la contraseña mínima pasa de 6 a **10** caracteres. El texto de error es "La contraseña debe tener mínimo 10 caracteres."
- El teléfono `0991234567` se guarda localmente (`Phone.toLocal`); cuando exista el campo en el backend se envía en E.164.

### 6.4 A3 · Google Sign-In directo (`google_sign_in_flow.dart`)

**Hoy:** `continueWithGoogle(context, role:)` simula y enruta. **El backend no tiene endpoint de Google.** Plan:

1. **Pedir a Chucho (B-01):** `POST /v1/auth/google` con `{idToken: string, rol?: 'COMENSAL'|'DUENO', restaurante?: {nombre, ciudadId}}` que verifique el ID token de Google, cree o encuentre al usuario y responda `TokenResponseDto`. Pedirle también el **Web client ID** de OAuth.
2. **Paquete `google_sign_in`: requiere aprobación de Carlos (R9).** Cuando se apruebe:
   - `pubspec.yaml`: `google_sign_in`.
   - Google Cloud Console: un cliente OAuth de tipo **Android** (nombre de paquete `ec.bocadoo.bocadoo` + huella SHA-1 del keystore de depuración y de release) y uno **Web** (su ID es el `serverClientId`).
   - Flujo nativo y directo, **sin pantalla intermedia propia**: `GoogleSignIn.instance.authenticate()` abre el selector de cuentas del sistema; se toma `idToken` y se llama al endpoint de arriba; luego `GET /v1/auth/me` y enrutar.
3. **Mientras no exista el endpoint:** `ApiAuthRepository.signInWithGoogle` **no** simula en modo API. Devuelve `AuthResult(ok: false, errorMessage: 'El acceso con Google estará disponible pronto. Entra con tu correo.')` y la UI lo muestra en un `SnackBar` (R10). El botón se queda en pantalla. En modo mock sigue simulando.
4. Para el registro (A4 y A5) con Google, el rol viaja en `role`: `customer` u `owner`. Un dueño nuevo con Google necesita además el nombre del restaurante: pedirlo en A5 antes (la pantalla ya lo tiene) y enviarlo en `restaurante`.

### 6.5 A2 · Olvidé mi contraseña (`forgot_password_screen.dart`)

**Hoy:** pide el correo, simula 1,2 s y muestra la confirmación. **El backend no tiene recuperación de contraseña** (no hay `/auth/forgot`, `/auth/reset`).

- Plan B (R10): en modo API, `requestPasswordReset` **no finge éxito**: devuelve `false` y la pantalla muestra "Por ahora escríbenos y te ayudamos." con un botón que abre el soporte (`SupportConfig.link(...)`, ya existente). Si `SupportConfig` no está configurado, el botón queda desactivado con el aviso que ya existe en C6.
- **Pedir a Chucho (B-03):** `POST /v1/auth/forgot {correo}` (siempre `204`, para no revelar cuentas) y `POST /v1/auth/reset {token, password}`.

### 6.6 A5 · Registro de dueño (`register_owner_screen.dart`) → A7

**Hoy:** nombre del restaurante, nombre del dueño, RUC, correo, WhatsApp, buscador de dirección, "Mi GPS", mapa con zonas, zona (chips), precio del almuerzo suelto (3,50 por defecto), contraseña, términos, "Registrar restaurante" (→ A7 con `extra: precioBase`), "Registrar con Google Workspace".

Secuencia de llamadas:

| # | Repo | Endpoint | Body |
|---|---|---|---|
| 1 | `registerOwner` | `POST /v1/auth/register-owner` | `{nombre: <dueño>, correo, password (10 a 128), aceptaTerminos: true, restaurante: {nombre: <restaurante>, ciudadId: 1}}` |
| 2 | `login` | `POST /v1/auth/login` | correo y contraseña |
| 3 | `me` | `GET /v1/auth/me` | → toma `restaurantes[0].id` y lo guarda como activo |
| 4 | `updateProfile` (en `ApiOwnerRepository`) | `PATCH /v1/restaurante` (Dueño, `x-restaurant-id`) | `{telefono: E.164 del WhatsApp, direccion, latitud, longitud, zonaId, precioSueltoCentavos: round(precio × 100)}` |

El restaurante nace en **`BORRADOR`** (no aparece en la vitrina). Se activa al final de A7 (ver abajo).

- `ciudadId: 1` es Quito (catálogo del backend).
- **`zonaId`:** el backend referencia zonas por número y **no expone un catálogo** (`GET /v1/zonas` no existe). Verificado en vivo: `1 = "Frente a la PUCE"`. Para las demás zonas de la UI (La Floresta, La Mariscal, Centro Histórico, Cumbayá, UDLA Granados, EPN / Salesiana, Villaflora): **pedir la tabla a Chucho (B-04)** y guardarla en `core/config/zones.dart` (`const Map<String, int>`). Hasta tenerla, enviar solo `zonaId: 1` para "Frente a la PUCE" y **omitir** `zonaId` para las otras (el campo admite nulo).
- **RUC:** el backend no tiene campo de RUC. Guardarlo en `LocalProfileStore` y pedirlo (B-05).
- **Dirección:** `direccion` es texto libre; `latitud`/`longitud` salen del mapa (`flutter_map` + `geolocator`, ya implementado).
- El texto "Google Maps" del encabezado del mapa de A5 no es correcto (el mapa es de OpenStreetMap): el botón ya no abre Google. **Cambiar el texto a "Mapa" requiere avisar a Carlos** (ajuste de texto).
- Errores: `409` → "Ya existe una cuenta con ese correo." (`CONFLICT`), `400` → validación.
- **E2:** contraseña mínima 10.

### 6.7 A6 · Bienvenida del comensal (`onboarding_diner_screen.dart`)

Sin llamadas. Recibe `{nombre, zona, lat, lng}` y el botón "Continuar" va a `/customer/restaurants` (C2). Solo asegurar que `lat`/`lng` ya quedaron en `LocalProfileStore` (4.2).

### 6.8 A7 · Bienvenida del dueño (`onboarding_owner_screen.dart`)

**Hoy:** 3 pasos. Paso 1 "Planes listos para publicar" (tres planes calculados desde el `precioBase`: semanal, quincenal y mensual; botón "Usar estos planes"). Paso 2 aforo y configuración. Paso 3 invitar al cajero por WhatsApp (enlace) y "Ir a mi Caja".

| Acción | Repo | Endpoint | Request |
|---|---|---|---|
| "Usar estos planes" | `savePlanTemplate` ×3 | `POST /v1/planes` (Dueño) | Uno por plan: `{tipo: SEMANAL\|QUINCENAL\|MENSUAL, nombre, almuerzos: 5\|10\|20, precioCentavos: <total que muestra la tarjeta ×100>, vigenciaDias: 7\|15\|30, diasValidos: [1,2,3,4,5], incluye: ['Sopa','Segundo','Jugo'], visibleEnMarketplace: true}` |
| Aforo | `updateProfile` | `PATCH /v1/restaurante` | `{puestos}` (y los demás ajustes de configuración que ya capture la pantalla: `anotarMesa`, `momentoCobro`) |
| Invitar cajero por WhatsApp | — | **ninguno** (la UI manda un enlace) | Se mantiene `openExternal(whatsAppUri(...))`. El backend agrega cajeros **por correo**: `POST /v1/restaurante/personal/cajeros {correo, nombreVisible?}` y la persona debe tener cuenta. Ver backlog 10.4 ("Personal"). |
| "Ir a mi Caja" | `activateRestaurant` | `PUT /v1/restaurante/horarios` y `POST /v1/restaurante/activar` | Si el local no tiene horarios, poner uno por defecto (lunes a viernes 12:00 a 15:30) con `PUT /v1/restaurante/horarios {horarios: [{diaSemana, abre, cierra}]}`; luego `activar`. **`activar` exige precio suelto y al menos un horario.** |

- La UI no captura horarios todavía. **Preguntar a Carlos (B-06)** si se agrega un editor de horarios; mientras tanto el horario por defecto se usa y se deja `// TODO`.
- Si `activar` falla, dejar el local en borrador, mostrar un `SnackBar` ("Tu local quedó en borrador. Completa tu menú para publicarlo.") y continuar a Caja.
- Los precios de los 3 planes son **los que la pantalla ya calcula**. Los 4 tipos y sus precios de referencia (Mensual $55, Quincenal $28, Semanal $15, Libre $32) viven en el editor de planes (O9), sección 8.

---

## 7. Bloque 2: Comensal (C1 a C11)

**Repositorio:** `ApiCustomerRepository implements ICustomerRepository` (`features/customer/data/api_customer_repo.dart`). Mapeos campo por campo: sección 9.

**Regla de identificadores:** en la app, `Restaurant.id` pasa a ser el **uuid** del restaurante; se agrega `Restaurant.slug` (campo opcional nuevo en `models.dart`). Las rutas `/customer/restaurants/:restaurantId` y `/customer/mesa?restaurantId=` siguen usando el `id` (uuid). Para pedir la ficha (`GET /v1/restaurantes/{slug}`) el repositorio busca el `slug` en la lista ya cargada (`getRestaurants`) y la guarda en un mapa `id → slug`.

### 7.1 C1 · Mi Pase (`pase_screen.dart`, `customer_controller.dart`)

**Hoy:** tarjeta del plan (nombre, `remaining/total`, vencimiento), carrusel entre locales (`passIndex`), QR en tres modos (`preorden`, `mesa`, `plan`) con cuenta regresiva de 30 s, tarjeta de sellos, actividad reciente, tarjeta "¿Qué tal hoy?" (C10), "Mesa con amigos", "Ver estado del pedido", banner de deshacer.

`CustomerController.loadDashboard()` llama, en este orden, a: `getCachedPass`, `getActivePasses`, `getRestaurants`, `getActiveTable`, `getActiveOrder`, `getRecentActivity`, `getPendingFeedback`, y `getStampCard` por cada pase.

| Repo | Endpoint | Notas |
|---|---|---|
| `getActivePasses` / `getActivePass` | `GET /v1/pase` | `{usuario, codigo: {codigo, validoSegundos, expiraEn}, locales: [{restaurante, hoy, almuerzosDisponibles, planes: [PlanPase]}]}`. **Un `CustomerPass` por local** (9.1). Solo planes activos y no vencidos, en orden FIFO. |
| `refreshQrToken(passId)` | `GET /v1/pase/codigo?restaurante=<uuid>` | `{codigo, validoSegundos, expiraEn}`. Con `restaurante`, el código **solo vale en ese local**. |
| `getCachedPass` / `saveCachedPass` | — (local, `LocalCustomerCache`) | Se mantiene para el modo sin conexión. |
| `getStampCard(restaurantId)` | `GET /v1/mis/sellos` | Lista de tarjetas; se filtra por `restaurante.id`. Devuelve `null` si el local no tiene tarjeta. 9.5 |
| `claimReward` | **ninguno para el comensal** | El premio se usa en caja (`POST /v1/clientes/{id}/sellos/canjear`, rol Caja). Plan B 10.3 (B-09). |
| `getActiveTable` | `GET /v1/mis/mesas` | Devuelve la mesa `ABIERTA`/`EN_CAMINO`/`EN_MESA` de hoy, o `null`. **No debe crear mesas** (el mock sí lo hace; la API no). |
| `getActiveOrder` | `GET /v1/mis/pedidos?limit=5` | 4.6 y 9.3 |
| `getRecentActivity` | `GET /v1/mis/consumos?limit=10` | Cada consumo → `ActivityItem(kind: 'lunch', name: restaurante.nombre, detail: 'Almuerzo validado · HH:mm', value: '- 1')`. La compra de planes **no** tiene historial para el comensal: no se muestra (plan B, solo consumos). |
| `getConsumptionHistory(passId)` | `GET /v1/mis/consumos?restaurante=<uuid>&limit=20` | `ConsumoItem` no trae los platos ni el saldo posterior: `description` = nombre del plan; `remainingAfter` = 0 y no se muestra. 9.2 |
| `getPendingFeedback` | `GET /v1/mis/opiniones/pendientes` | Ver C10. |

- **Contador del QR (importante):** `pase_screen.dart` refresca el QR al cruzar el límite de cada ciclo de 30 s usando `BocadooQrParser.getRemainingSecondsInCycle()` (reloj del teléfono, alineado a múltiplos de 30 s desde la época). El backend usa el mismo paso de 30 s y la caja acepta ±1 paso, así que **debería funcionar sin cambios si el reloj del teléfono está sincronizado**. Comprobarlo en la prueba de humo: si el QR llega vencido a la caja (`QR_EXPIRADO`), el ajuste es leer `codigo.expiraEn` del servidor en lugar del reloj local (es un cambio chico en `pase_screen.dart`; **avisar a Carlos**).
- **QR de plan en `customerController.qrValue`:** `currentPass.qrToken` = `codigo.codigo` (empieza con `BCD1.`).
- El QR de `preorden` es `activeOrder.qrPayload` = `qr` del `PedidoResponse` (uuid). El de `mesa` es `activeTable.url` = `BCD-MESA-<id>`.
- Sin conexión: se muestra el pase en caché con el aviso existente; el QR en caché **vence** (30 s) y la caja lo rechazará con `QR_EXPIRADO`. La UI ya lo contempla con `isOffline`.

### 7.2 C2 · Dónde comer (`restaurants_screen.dart`)

**Hoy:** buscador, filtros **Cerca** (<1 km), **Con plan**, **Libre**, **Ofertas**, tarjetas con distancia ("0,2 km · 2 min"), ocupación, botón "Pedir" (`quickOrder`) y "Mesa", acceso al mapa.

| Repo | Endpoint | Detalle |
|---|---|---|
| `getRestaurants({query, category})` | `GET /v1/restaurantes` (público) | Query: `q` (texto), `zonaId`, `ciudadId`, `etiqueta`, `limit` (1 a 50), `cursor`. Cargar todas las páginas (`nextCursor`) al abrir. `RestauranteCardResponse` → `Restaurant` (9.4). |

Filtros (se resuelven en el teléfono con `CustomerUiState.filteredRestaurants`; el servidor no filtra por distancia ni por plan):
- **Cerca:** `distanceKm < 1.0`. `distanceKm` se calcula con Haversine entre la ubicación del comensal (`LocalProfileStore` o GPS) y `latitud`/`longitud` del local. Si el local no tiene coordenadas (`null`): `distanceKm = 99` y queda excluido de "Cerca"; la tarjeta no muestra distancia.
- **Libre:** `ocupacion.nivel == LIBRE` → `occupancy = 'LIBRE'`. Mapa de niveles: `LIBRE→LIBRE`, `MODERADO→MOVIDO`, `LLENO→LLENO`.
- **Con plan:** la tarjeta de la lista **no** dice si el local tiene planes. Plan B: al abrir un local o en segundo plano se carga el detalle y se completa `hasPlan`. Hasta entonces, "Con plan" muestra los locales cuyo detalle ya se cargó. **Pedir a Chucho (B-07)** que `RestauranteCardResponse` incluya `tienePlanes: boolean` y `tieneOfertas: boolean`.
- **Ofertas:** `GET /v1/restaurantes/{slug}/ofertas` por cada local sería un N+1. Plan B igual que arriba (B-07).
- `abiertoAhora` → `isOpen`.
- **Ordenamiento:** por distancia si hay ubicación.
- Foto de portada: **no existe** (`logoUrl` es lo único). Ajuste E4.

| Acción | Repo | Endpoint |
|---|---|---|
| "Pedir" (`quickOrder`) | `preorder` | `POST /v1/mis/pedidos` + IK, con la primera sopa y el primer fuerte **no agotados** del menú del local. Ver C3. |
| "Mesa" | — | abre C9 (`/customer/mesa?restaurantId=`) |
| Mapa | — | `/customer/mapa` (C11) |

### 7.3 C3 · Ficha del local (`restaurant_sheet.dart`)

**Hoy:** hoja con foto, ocupación, horario, menú (sopas, fuertes, desayunos), ofertas, botones "Preordenar", "Armar mesa", tarjeta de sellos.

| Repo | Endpoint | Detalle |
|---|---|---|
| `getRestaurantById(id)` | `GET /v1/restaurantes/{slug}` (público) | `RestauranteDetalleResponse`: card + `telefono`, `horarios: [{diaSemana, abre, cierra}]`, `menuHoy: {fecha, publicado, secciones: [{seccion, platos: [PlatoVitrina]}]}`, `planes: [PlanVitrina]`. Un menú sin publicar → `menuHoy.publicado = false` y `secciones = []`; un local en borrador o pausado → `404`. |
| `getTodayMenu(restaurantId)` | (el mismo detalle) | `menuHoy.secciones` → `List<MenuItem>` (9.4). |
| ofertas del local | `GET /v1/restaurantes/{slug}/ofertas` (público) | Solo vigentes y con stock. → `RestaurantOffer` (9.4). |
| `preorder(...)` | `POST /v1/mis/pedidos` + IK | Body `CrearPedidoDto` (4.1.1). `soupId`/`mainId` = `PlatoVitrina.id` (uuid). `breakfastId`: ver nota. `takeaway` → `paraLlevar`. Respuesta → `ActiveOrder` (9.3). |
| `cancelPreorder(orderNumber)` | `POST /v1/mis/pedidos/{id}/cancelar` | El repositorio traduce el número al uuid con su mapa interno. `409 PEDIDO_NO_CANCELABLE` si ya se validó. Es el "Deshacer" de 10 s tras pedir. |
| `reserveOffer` | **ninguno** | El backend solo permite **canjear la oferta en caja** (`POST /v1/ofertas/{id}/canjear`, rol Caja). No hay reserva del comensal. Plan B: el botón de la oferta (`reservable`) se queda en `false` para ofertas reales y el texto muestra "Pídela en caja". 10.3 (B-08). |

- **Desayunos:** el backend **no tiene categoría de desayuno** (`ALMUERZO`, `A_LA_CARTA`, `EXTRA`, `BEBIDA`). Los desayunos del menú llegan como platos `A_LA_CARTA`/`EXTRA` con `precioCentavos` y se piden como **`extras`** (`{plato, cantidad: 1}`) y no como almuerzo. Si el pedido solo tiene extras, `almuerzo = null`.
- **`takeawaySurcharge`:** el detalle público **no** trae el recargo para llevar (solo el endpoint de Dueño). Plan B: usar el valor por defecto 0,25 y el precio real lo corrige el servidor en `totalCentavos`. **Pedir a Chucho (B-10)** que lo incluya en el detalle público.
- La regla "un pedido en camino a la vez por local" (`409 PEDIDO_ACTIVO`) se traduce a "Ya tienes un pedido en camino en este local."

### 7.4 C4 · Planes y C5 · Detalle del plan (`plans_screen.dart`, `plan_detail_sheet.dart`)

| Repo | Endpoint | Detalle |
|---|---|---|
| `getPlanTemplates(restaurantId)` | `GET /v1/restaurantes/{slug}` → `planes` | `PlanVitrinaResponse {id, tipo, nombre, almuerzos, precioCentavos, vigenciaDias, diasValidos, incluye}` → `PlanTemplate` (9.6). |
| `getPlanTemplateById(planId)` | (de la misma lista en caché) | El backend no tiene `GET /planes/{id}` público. |
| `requestPlan(planId)` | `POST /v1/restaurantes/{slug}/solicitudes-plan` | Body `{planId}` (el `id` de `PlanVitrinaResponse`). `201 {id, estado: PENDIENTE, plan, creadaEn}`. `409 CONFLICT` si ya hay una solicitud pendiente. |
| `cancelPlanRequest(planId)` | **ninguno** | Es el "Deshacer" de 10 s. Plan B: commit diferido (10.2): la solicitud se envía recién pasados los 10 s si no se tocó "Deshacer". |

- **Importante:** la solicitud llega a la caja del dueño (`GET /v1/solicitudes-plan`). **Hoy la UI del dueño no tiene una bandeja para verlas** (backlog 10.4, ítem P-01). Sin esa pantalla, las solicitudes del comensal no se ven en ningún lado. Se incluye en la Fase 4.
- El plan se paga **en caja** (el botón dice "solicitar", no "pagar").
- Un plan con `incluye` vacío: mostrar las secciones por defecto (Sopa, Segundo, Jugo).

### 7.5 C6 · Mi cuenta (`account_screen.dart`) — pestaña "Yo"

**Hoy:** cabecera con inicial y teléfono, "Tu plan habitual" con chips (Sopa, Segundo, Bebida), selector de apariencia (Sistema, Claro, Oscuro), "Ayuda por WhatsApp" (configurable), logo. La pestaña "Yo" de la barra del comensal abre `/customer/cuenta` dentro del `CustomerShell`; no hay marcadores.

| Repo | Fuente | Detalle |
|---|---|---|
| `getProfile` | `GET /v1/auth/me` + `GET /v1/pase` + `LocalProfileStore` | `name` = `usuario.nombre`. `phone` = `LocalProfileStore` (el backend no lo guarda). `habitualPlanName` = nombre del primer plan del primer local del pase (o `null` → "Todavía no tienes un plan"). `habitualPlanIncludes` = `incluye` del plan de la vitrina con el mismo nombre, o la lista por defecto. `supportWhatsApp` = `SupportConfig.whatsApp`. |
| Cerrar sesión | `logout` | `POST /v1/auth/logout {refreshToken}` → `/login`. (Si C6 no tiene el botón, se agrega solo si Carlos lo aprueba; hoy el cierre está en otra parte del flujo.) |

- El selector de apariencia es local (`themeModeProvider`): no hay llamada.
- Pedir a Chucho (B-02) `PATCH /v1/auth/me` para guardar teléfono y ubicación.

### 7.6 C7 · Unirme a mesa (`join_table_screen.dart`)

| Repo | Endpoint | Detalle |
|---|---|---|
| `getSharedTable(tableId)` | `GET /v1/mesas/invitacion/{id}` | `InvitacionResponse {id, restaurante, anfitrion, horaLlegada, modo, estado, personas, capacidad, puedeUnirse, motivo}`. Si `puedeUnirse == false`, mostrar el motivo: `MESA_CERRADA` "La mesa ya cerró.", `MESA_VENCIDA` "La mesa ya venció.", `MESA_LLENA` "La mesa está llena.", `RESTAURANTE_NO_DISPONIBLE` "El local no está disponible.", `YA_ERES_MIEMBRO` "Ya estás en esta mesa." |
| `joinTable(...)` | `POST /v1/mesas/invitacion/{id}/unirse` + IK | Body `{paraLlevar}`. **`name`, `soup` y `main` no se envían** (el backend no los recibe; el nombre sale de la cuenta). Respuesta `MesaResponse` → `SharedTable`. Plan B: la elección de sopa y fuerte se muestra pero no viaja (10.1, B-12). |

- Requiere sesión (la ruta es de comensal). Sin sesión: guardar la invitación pendiente y llevar a login (4.7).
- La lista de "compañeros" sale de `miembros` (nombre, `esAnfitrion`, `paraLlevar`).

### 7.7 C8 · Estado del pedido (`order_status_sheet.dart`)

**Hoy:** número de orden, **cuenta regresiva** de 30 min, sopa, segundo, modalidad, QR `BCD-ORD-…` y cómo se valida (con plan o sin plan: "Tu caso").

| Repo | Endpoint | Detalle |
|---|---|---|
| `getActiveOrder` / ver pedido | `GET /v1/mis/pedidos/{id}` | `PedidoResponse` → `ActiveOrder`. `numero` → `orderNumber`; `qr` → `qrPayload`; `venceEn` → `expiresAt`; `almuerzo.cubiertoPorPlan` → `hasPlan`; `estado` → `status` (9.3). **Polling cada 5 s** mientras la hoja está abierta o haya pedido activo. |
| Cancelar | `POST /v1/mis/pedidos/{id}/cancelar` | |
| "Visto" | local (`shared_preferences`) | `acknowledgeOrder` |

- La hoja muestra "Pedido #N" con `numero`. El texto `BCD-ORD-…` que hoy se arma con el número debe mostrar el **`qr` real** (o solo "Pedido #N").
- Estados: `EN_CAMINO` → "Preparando"; `CANJEADA` → "Listo" (la caja ya lo validó); `SERVIDA` → hoja "Entregado"; `EXPIRADA` → "Tu pedido venció." y se limpia; `CANCELADA` → se limpia.

### 7.8 C9 · Mesa con amigos (`table_sheet.dart`)

| Repo | Endpoint | Detalle |
|---|---|---|
| `openSharedTable({restaurantId, time})` | `POST /v1/mis/mesas` + IK | Antes de crear, `GET /v1/mis/mesas` y reutilizar una `ABIERTA` del mismo local y hora. Body `{restaurante: uuid, horaLlegada: EcuadorTime.todayAtUtc(time).toIso8601String(), modo: 'CADA_UNO', paraLlevar: false}`. La hora debe estar **de ahora a 12 horas** (`400 HORA_LLEGADA_INVALIDA`). El selector de la UI (12:30 a 14:00) debe deshabilitar horas pasadas: si ya pasaron, usar la siguiente. |
| `getSharedTable` (anfitrión) | `GET /v1/mis/mesas/{id}` | Polling cada 8 s. |
| `setTableMode(tableId, mode)` | **ninguno** | Plan B 10.1 (B-12): el modo se fija **al crear**. Si el anfitrión cambia el modo en la UI, el repositorio **cancela la mesa y crea una nueva** con el modo nuevo **solo si** todavía no tiene invitados; si ya tiene invitados, conserva el modo y avisa "El modo no se puede cambiar con invitados." (E3 oculta el selector cuando `ApiCapabilities.sharedTableModeChange == false`). Pedir `PATCH /v1/mis/mesas/{id} {modo}`. |
| `notifyKitchen` | **ninguno** | Plan B: no se envía nada; el botón "Avisar a cocina" se oculta (E3). El estado `EN_CAMINO` lo maneja el backend. Preguntar a Chucho cuándo cambia a `EN_CAMINO`. |
| Compartir | local | `shareUrl` = `bocadoo://mesa/<invitacion>` (4.7). QR de la mesa = `BCD-MESA-<id>`. |

`SharedTable.occupancyLabel`, `soups`, `mains`, `takeawaySurcharge` salen de `GET /v1/restaurantes/{slug}` del local de la mesa (9.7).

### 7.9 C10 · Calificar almuerzo (`feedback_card.dart`, `feedback_rules.dart`)

**Hoy:** tarjeta "¿Qué tal hoy?" bajo el QR de Mi Pase con tres etiquetas (Rico, Rápido, Porción) y cerrar. Aparece entre 25 minutos y 24 horas después de validar. Se envía con un toque.

| Repo | Endpoint | Detalle |
|---|---|---|
| `getPendingFeedback` | `GET /v1/mis/opiniones/pendientes` | `[{consumo: {id, fecha, restaurante}, expiraEn, etiquetasDisponibles}]`. Solo devuelve almuerzos propios no revertidos de **25 min a 24 h**, sin opinión ni descarte: **el servidor aplica la regla** (la app solo toma el primero). → `PendingFeedback(redemptionId: consumo.id, restaurantId, restaurantName, validatedAt: consumo.fecha)` |
| `submitFeedback(redemptionId, tag, note)` | `POST /v1/mis/consumos/{id}/opinion` + IK | Body `{etiquetas: [...], comentario?}`. Mapa de etiquetas de la UI: `Rico→RICO`, `Rápido→RAPIDO`, `Porción→BUENA_PORCION`. `comentario` = la nota (solo lo lee el restaurante). `400 OPINION_VACIA` si no hay etiquetas ni comentario. |
| `dismissFeedback` | `POST /v1/mis/consumos/{id}/opinion/descartar` + IK | Cuenta como la única opinión de ese almuerzo. |

- Errores: `OPINION_AUN_NO_DISPONIBLE` (antes de 25 min), `OPINION_VENCIDA` (después de 24 h), `OPINION_YA_ENVIADA`, `CONSUMO_REVERTIDO`. En todos: cerrar la tarjeta.
- **Nota escrita:** el backend ya soporta `comentario`. La tarjeta de la UI (decisión B1) solo ofrece etiquetas; la nota llega a O15 cuando existe. Si Carlos pide que el comensal escriba la nota, es un cambio de UI aparte (no está aprobado).

### 7.10 C11 · Mapa (`map_screen.dart`)

**Hoy:** pide GPS (`geolocator`) o zona comercial, radio 100 m / 200 m / 500 m / 1 km / Todos, pines con ocupación, tarjeta del local, "Ver ruta" (dibuja dentro del mapa) y "Ver menú".

| Dato | Fuente |
|---|---|
| Locales y pines | `getRestaurants()` (`GET /v1/restaurantes`): `latitud`, `longitud`, `ocupacion`, `nombre`. Locales sin coordenadas **no se dibujan**. |
| "Ver menú" | abre `/customer/restaurants/<id>` (C3) |
| Ruta a pie | `walking_route_service.dart` (OSRM). No es del backend. B-14. |

Sin llamadas nuevas al backend. Las zonas comerciales (`commercial_zones.dart`) son del frontend.

---
## 8. Bloque 3: Dueño (O1 a O16)

**Repositorio:** `ApiOwnerRepository` (`features/owner/data/api_owner_repo.dart`, hoy vacío) implementa **las 8 interfaces del dueño** y usa `ApiClient` con `restaurant: true` (agrega `x-restaurant-id`). Mapeos campo por campo: sección 9.

**Roles:** los endpoints de **Caja** los puede llamar un cajero o un dueño. Los de **Dueño** solo el dueño (un cajero recibe `403`). La tabla indica el rol mínimo.

**Identificador del restaurante:** el valor que hoy es `ownerRestaurantIdProvider` (`'rest-001'`) pasa a ser el uuid de `GET /v1/auth/me`. Los métodos reciben `restaurantId` por firma pero el repositorio **usa el activo de la sesión** para el encabezado.

### 8.1 O1 · Caja (`caja_screen.dart`)

**Hoy:** encabezado con "Libre / Movido" y "Marcar lleno", franja "N en camino", banners de mesas por cobrar, tarjeta "Escanear QR", oferta flash activa, botón "Cobro suelto (POS)", fichas "Vender plan", "Oferta flash", "Cuadre caja" (solo dueño), tarjeta "Tus números" (solo dueño), lista "Cobros de hoy".

| Provider / acción | Repo | Endpoint (rol) | Detalle |
|---|---|---|---|
| `dailySummaryProvider` | `getDailyClosingSummary` | `GET /v1/caja/cierre/hoy` (Caja) y `GET /v1/reportes/resumen-diario` (Dueño) | `TransactionSummary` (9.11). El cajero **no** puede llamar a `reportes` (rol Dueño): para el cajero, `plansSoldToday` se deja en 0 y se oculta. |
| "Cobros de hoy" | `getTodayTransactions` | `GET /v1/caja/ventas` (Caja) + `GET /v1/caja/pedidos?estado=SERVIDA` (Caja) | Lista de movimientos con monto > 0. **No existe una lista de planes vendidos ni de validaciones del día** (B-17). Se muestran ventas sueltas y pedidos servidos. |
| `ordersOnTheWayProvider` | `getOrdersOnTheWayCount` | `GET /v1/caja/pedidos` (Caja) | `length` de la lista de activos. Polling 8 s. |
| `pendingTablesProvider` | `getPendingTables` | **ninguno** | `[]` en modo API (B-15). El banner no aparece; las mesas se cobran escaneando su QR. E3. |
| `activeOfferProvider` | `getActiveOffer` | `GET /v1/ofertas?estado=VIGENTE&limit=1` (Caja) | → `FlashOffer?` (O11). |
| "Marcar lleno" | `setManualBusy` | `POST /v1/restaurante/lleno {lleno: bool}` (Caja) | Dura **20 minutos** y expira solo (coincide con `BusyUntilNotifier.busyDuration`). Al iniciar, `busyUntilProvider` se inicializa con `llenoManualHasta` de `GET /v1/restaurante`. |
| Etiqueta "Libre / Movido" | — | — | Se mantiene la heurística actual (`lunchesToday >= 10` → Movido). No hay llamada. |
| "Escanear QR" | — | — | O2. |
| "Cobro suelto" | — | — | O4 → O6 (POS). |
| "Vender plan" | — | — | O3. |
| "Cuadre caja" | — | — | O13. |

### 8.2 O2 · Escáner universal y resultado (`scanner_screen.dart`, `scan_result_screen.dart`)

El comportamiento completo, el reconocimiento de los 3 QR y el mapeo de resultados están en **4.1.4**. Resumen de repositorio:

| Repo | Endpoint | Notas |
|---|---|---|
| `validateQrCode(raw)` | `POST /v1/caja/validar` (Caja) + **IK** | Body `{codigoQr: raw, paraLlevar?, mesaLocalId?}`. **Ya descuenta.** Siempre `200` con `resultado`. |
| `confirmRedeem(passId)` | — | Devuelve `true` sin llamar a la API (4.1.4). |
| `undoRedeem(passId)` | `POST /v1/caja/consumos/{consumoId}/deshacer` (Caja) | Solo 10 s. `409` fuera de plazo → "Ya pasó el tiempo para deshacer." |
| Ingreso manual | `validateQrCode` | El diálogo "escribir el código" acepta lo que se pegue. Para validar **por búsqueda de cliente** (canal `MANUAL`), `POST /v1/caja/validar {clienteId}`; hoy la UI no tiene esa búsqueda (backlog). |

- Permiso de cámara: ya resuelto en `scanner_screen.dart` (`mobile_scanner`).
- `LIMITE_SAAS`: mostrar "Llegaste al límite de validaciones de tu plan Bocadoo." y no ofrecer reintentar.

### 8.3 O3 · Vender plan (`sell_plan_modal.dart`)

**Hoy:** busca o crea un cliente rápido, elige plan, elige método (**Efectivo, Transferencia, Deuna**, y Tarjeta en el mock), "Confirmar venta" y deshacer de 10 s.

| Repo | Endpoint (rol) | Body / detalle |
|---|---|---|
| `getClients` | `GET /v1/clientes?limit=50&cursor=` (Caja) | Recorrer `nextCursor` hasta agotar (tope de seguridad: 500). |
| `getPlanTemplates` | `GET /v1/planes` (Caja) | Solo `activo` y con `cuposDisponibles != 0`. Trae `cupos`, `cuposDisponibles`, `vendidosActivos`. |
| cliente rápido (solo nombre) | `addClient` → `POST /v1/clientes` (Caja) | `{nombre}` (teléfono, correo y nota nulos). `201 ClienteDetalleResponse`. |
| `sellPlanTemplate` | `POST /v1/clientes/{id}/planes` (Caja) + **IK** | `{planId, metodoPago: EFECTIVO\|TRANSFERENCIA\|DEUNA, pagoConfirmado}`. Respuesta `PlanVendidoResponse` (`id` → `saleId` para deshacer). |
| `undoTransaction(saleId)` | `POST /v1/planes-vendidos/{id}/deshacer` (Caja) + **IK** | `{motivo}`. "Solo sin almuerzos consumidos; el cajero, solo el mismo día." Registra un pago inverso, nunca borra. |

- **Método Tarjeta:** el backend **no** lo tiene (`metodoPago` solo admite 3 valores). Se oculta (E3/E6).
- **`pagoConfirmado`:** efectivo siempre queda confirmado. Para Transferencia y Deuna, si no se manda `true`, el pago queda `PENDIENTE` hasta que el dueño lo confirme (`GET /v1/pagos/pendientes`, `POST /v1/pagos/{id}/confirmar|rechazar`), y **la UI no tiene esa pantalla**. Decisión para v1: enviar `pagoConfirmado: true` (el cajero confirma el pago al dar "Confirmar venta" con el comprobante a la vista) y registrar la pantalla "Pagos por confirmar" en el backlog (P-02). `referenciaExterna` y `comprobanteUrl` no se capturan hoy.
- Errores: `404 CLIENTE_NO_ENCONTRADO`, `409` (plan inactivo, sin cupos). El repositorio traduce a "No se pudo vender el plan. Revisa el plan y el cliente."
- El nombre del plan vendido y el vencimiento (`venceEl`) los calcula el servidor.

### 8.4 O4 · Cobro suelto (`/owner/cobro-suelto`)

Abre el mismo POS que O6 (decisión D1 de la Fase 3). Sin llamadas propias.

### 8.5 O5 · Cobrar mesa (`cobrar_mesa_sheet.dart`)

Flujo completo en **4.1.3**. Repositorio:

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `getPendingTables` | **ninguno** | `[]` (B-15) |
| `previewTable(restaurantId, tableId)` | `GET /v1/caja/mesas/{id}` (Caja) | Se construye `TablePreview` con las reglas de 4.1.3 y precios de `GET /v1/restaurante` (9.10). `404 MESA_NO_ENCONTRADA` → "Mesa no encontrada." `yaValidada`/`estado: FINALIZADA` → "Esta mesa ya fue cobrada." |
| `setTableMode` | **ninguno** | Devuelve el mismo preview (solo lectura). Selector deshabilitado por E3. |
| `chargeTable` | `POST /v1/caja/mesas/{id}/validar` (Caja) + **IK** | Luego, si `porCobrar > 0`: `POST /v1/caja/ventas` (+ IK) `ALMUERZO × porCobrar`, `EFECTIVO`, `mesaTexto: "Mesa <id>"` (sujeto a la verificación de caja de 4.1.2). Devuelve un `chargeId` interno con los `consumoId` y el `ventaId`. |
| `undoTableCharge(chargeId)` | `POST /v1/caja/consumos/{consumoId}/deshacer` (por cada consumo) y `POST /v1/caja/ventas/{id}/deshacer` | Solo dentro de los 10 s (`409` después). |

### 8.6 O6 · Registrar consumo / POS (`registrar_consumo_screen.dart`)

**Hoy:** selector de mesa (Mesa 1 a 5, Barra, Para llevar; son etiquetas **locales**), categorías **Almuerzos, Desayunos, Carta, Extras, Bebidas**, carrito por mesa, método de pago con efectivo recibido y vuelto (**solo UI**), "Registrar consumo", "Escanear pase" (O2), deshacer de 10 s. Tiene un catálogo local (`CatalogItem`) con ids propios (`des-1`, `car-1`…).

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `getCatalog` | `GET /v1/menu/platos?soloActivos=true` (Caja) | → `CatalogItem` (9.9): `A_LA_CARTA`→Carta, `EXTRA`→Extras, `BEBIDA`→Bebidas. "Almuerzos": un ítem "Almuerzo" al `precioSueltoCentavos` de `GET /v1/restaurante`, con la descripción del menú de hoy. **"Desayunos": el backend no tiene categoría** (B-27): los platos de desayuno se crean como `A_LA_CARTA` o `EXTRA` y aparecen en esas categorías. |
| `registerPosSale` | `POST /v1/caja/ventas` (Caja) + **IK** | Body `VentaDto`: `items` (almuerzos → `{tipo: ALMUERZO, cantidad}`; platos del catálogo → `{tipo: PLATO, platoId, cantidad}`; cobros libres → `{tipo: LIBRE, nombre, precioUnitarioCentavos, cantidad}`), `metodoPago`, `paraLlevar` (verdadero si la mesa es "Para llevar"), `mesaTexto` (la etiqueta de mesa), `pagoConfirmado`. **El servidor pone los precios de ALMUERZO y PLATO**: mostrar el total que devuelve `VentaResponse.totalCentavos`. → `saleId = id`. |
| `undoTransaction(saleId)` | `POST /v1/caja/ventas/{id}/deshacer` (Caja) + **IK** | "El cajero, solo las del mismo día." |
| `posMenuProvider` | `getTodayMenu` (O7) | para el detalle del almuerzo |

- **Ítems que hoy usan ids locales** (`des-1`, `car-1`…) deben desaparecer en modo API: el carrito usa `platoId` del catálogo real.
- Los reportes cuentan los almuerzos sueltos como "ventas" (`ventasPos.almuerzos`).

### 8.7 O7 · Menú de hoy y catálogo (`owner_menu_screen.dart`)

**Hoy:** segmento **Hoy** (secciones Sopa, Segundo, Bebida/Jugo, Postre, Desayuno) y segmento **Mis platos** (catálogo). Cada plato publicado tiene **"Hay / Se acabó"** individual, sin despublicar todo. "Publicar menú", "Cancelar publicación" (deshacer de 10 s), "Ver pedidos".

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `getTodayMenu` | `GET /v1/menu/hoy` (Caja) | `MenuDiaResponse {fecha, publicado, publicadoEn, items}` → `DailyMenu` (9.9). Si no hay platos, `items: []`. |
| `getYesterdayMenu` | `GET /v1/menu/{AAAA-MM-DD de ayer}` (Caja) | La UI ya no tiene "Repetir ayer"; el método se mantiene. Alternativa: `POST /v1/menu/hoy/copiar {desde, reemplazar}` (Dueño). |
| `publishMenu(menu)` | `PUT /v1/menu/hoy` (Dueño) y luego `POST /v1/menu/hoy/publicar` (Dueño) | Body `DefinirMenuDto {items: [{platoId, seccion, precioCentavos?, porciones?, orden}]}`. "Lista completa y libre": lo que no esté se quita; lo que se mantiene conserva su `agotado`. |
| `unpublishMenu` | `POST /v1/menu/hoy/despublicar` (Dueño) | Es el "deshacer" de publicar. |
| **`setCourseSoldOut(restaurantId, courseName, soldOut)`** | `PATCH /v1/menu/hoy/items/{itemId}/agotado` (**Caja**) | Body `{agotado: bool}`. `itemId` es el **renglón del menú** (`ItemMenuResponse.id`), no el `platoId`. El repositorio busca el `itemId` por nombre en el último menú cargado. Guarda la hora en `agotadoEn`. **No** despublica ni toca los demás platos. Responde el menú completo: usarlo para refrescar. |
| `setStoreOpen` | `POST /v1/restaurante/activar` / `POST /v1/restaurante/pausar` (Dueño) | Abrir/cerrar el local. **Ojo:** "pausar" saca el local de la vitrina. `activar` exige precio y horario. |

Catálogo ("Mis platos"):

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `getDishes` | `GET /v1/menu/platos` (Caja), `soloActivos` opcional, `categoria` opcional | → `CatalogDish` (9.9). Los archivados llegan con `activo: false`. |
| `addDish` | `POST /v1/menu/platos` (Dueño) | `{categoria, seccion?, nombre, descripcion?, precioCentavos?, etiquetas?}`. Mapa de `DishKind`: `sopa` → `ALMUERZO/SOPA`; `segundo` → `ALMUERZO/FUERTE`; `bebida` → `ALMUERZO/JUGO`; `postre` → `ALMUERZO/POSTRE`; `carta` → `A_LA_CARTA`; `desayuno` → sin categoría propia (B-27): `EXTRA` con `seccion: ADICIONAL`. |
| `setDishArchived` | `PATCH /v1/menu/platos/{id}` (Dueño) | `{activo: !archived}`. "Los platos no se borran: se desactivan." |

- Para publicar un plato **escrito a mano** en el menú, primero hay que crearlo en el catálogo (`POST /v1/menu/platos`) para tener su `platoId`.
- `veggie` y `topPick` de `CatalogDish`: `veggie` ↔ etiqueta `vegetariano` en `etiquetas`; `topPick` no existe en el backend (queda en falso).
- Cada llamada de menú del dueño debe refrescar `posMenuProvider`.

### 8.8 O8 · Planes y clientes (`owner_plans_screen.dart`)

**Hoy:** segmento **Planes** (tarjetas con interruptor activo, "toca la cantidad para editarla", botón `+` nuevo plan) y segmento **Clientes** (buscador, **botón `+` "Agregar cliente"** que abre la hoja `AddClientSheet`, tarjeta con "Vender plan"). "Pasar cartulina" **ya no está aquí**: quedó solo en Ajustes.

| Acción | Repo | Endpoint (rol) | Detalle |
|---|---|---|---|
| Lista de planes | `getPlanTemplates` | `GET /v1/planes` (Caja) | 9.8 |
| Contador "Clientes" por plan | `getPlanClientCounts` | (mismo `GET /v1/planes`) | `vendidosActivos` por plantilla. Es "planes activos vendidos", una aproximación a "clientes". |
| Activar / desactivar | `setPlanActive` | `PATCH /v1/planes/{id} {activo}` (Dueño) | No cambia los planes ya vendidos. |
| Lista de clientes | `getClients` | `GET /v1/clientes?q=&limit=50&cursor=` (Caja) | Búsqueda por nombre o teléfono. |
| **Agregar cliente** (`+`) | `addClient` | `POST /v1/clientes` (Caja) | Body `{nombre, telefono: Phone.toE164(celular), correo?, nota?}`. `201 ClienteDetalleResponse`. **`409 CONFLICT`** si el teléfono ya existe en el local → "Ya tienes un cliente con ese celular." Devuelve `OwnerClient`; la hoja ya ofrece "Guardar cliente" y "Guardar y vender plan" (abre O3 con su nombre). |
| Vender plan | — | O3 | |

- La tarjeta del cliente muestra `habitualPlan ?? 'Sin plan'`. La lista de clientes **no trae el nombre del plan** (sí `almuerzosDisponibles` y `proximoVencimiento`). `habitualPlan` = `"<n> almuerzos disponibles"` si `n > 0`, o `null` ("Sin plan"). **Pedir `planActual` en `ClienteResponse` (B-25).**
- Estados vacíos: sin clientes → botón "Agregar cliente" (ya existe).

### 8.9 O9 · Crear y editar plan (`plan_editor_sheet.dart`)

**Hoy:** selector Semanal / Quincenal / Mensual / Libre que aplica los valores base; campos de cantidad de almuerzos, precio, vigencia, cupos, días válidos, qué incluye, visibilidad y cobertura (Almuerzo, Desayuno, Mixto).

**Valores base que el servidor debe aceptar sin cambios:**

| Tipo | Nombre base | Almuerzos | Precio | Vigencia | Cupos base | Días |
|---|---|---|---|---|---|---|
| `SEMANAL` | Plan semanal | 5 | $15 → `1500` | 7 días | 20 | 1 a 5 |
| `QUINCENAL` | Plan quincenal | 10 | $28 → `2800` | 15 días | 30 | 1 a 5 |
| `MENSUAL` | Plan mensual ejecutivo | 20 | $55 → `5500` | 30 días | 40 | 1 a 5 |
| `LIBRE` | Plan libre 10 | 10 | $32 → `3200` | 60 días | 40 | 1 a 7 |

| Repo | Endpoint (rol) | Body |
|---|---|---|
| `savePlanTemplate` con `id` vacío | `POST /v1/planes` (Dueño) | `CrearPlanDto {tipo, nombre, almuerzos, precioCentavos, vigenciaDias, cupos, diasValidos: [int], incluye: [String], visibleEnMarketplace}` |
| `savePlanTemplate` con `id` | `PATCH /v1/planes/{id}` (Dueño) | `ActualizarPlanDto` (todos opcionales, más `activo`). **El Swagger tipa `diasValidos` como `[string]` en el PATCH y como `[integer]` en el POST.** Enviar enteros; si el servidor responde `400`, reintentar con cadenas y avisar a Chucho. |

- **Cobertura (Almuerzo / Desayuno / Mixto):** el backend **no tiene** el campo. Plan B (B-27): se codifica en `incluye` (por ejemplo `["Desayuno","Sopa","Segundo"]`) y el nombre; al leer, `coverage` se infiere: contiene "Desayuno" y "Sopa" → mixto; solo "Desayuno"/"Plato principal" → desayuno; si no → almuerzo.
- `quota` ↔ `cupos` (`null` = sin límite). `visible` ↔ `visibleEnMarketplace`. `active` ↔ `activo`.
- Cambiar precio o cantidad **no afecta** a los planes ya vendidos (lo dice el endpoint); la UI ya lo comunica.
- Respuesta `PlantillaPlanResponse.id` (cadena numérica) = `OwnerPlanTemplate.id`.

### 8.10 O10 · Pasar cartulina (`cartulina_sheet.dart`)

**Hoy:** hoja con buscador de clientes o alta rápida (nombre y celular 09XXXXXXXX), selección del plan de la cartulina, stepper de **almuerzos ya consumidos** con "Consumidos / Le quedan / Del plan", "Digitalizar cartulina" (único botón morado), deshacer de 10 s. **No genera cobro.** Se abre **solo desde Ajustes**.

| Paso | Endpoint (rol) | Body |
|---|---|---|
| (si es cliente nuevo) crear cliente | `POST /v1/clientes` (Caja) | `{nombre, telefono: E.164}` |
| `registerPhysicalCard` | `POST /v1/clientes/{id}/migrar-cartulina` (**Dueño**) | `{almuerzosRestantes: template.lunches − used, venceEl: hoy + template.validityDays (AAAA-MM-DD), precioUnitarioCentavos: round(template.price / template.lunches × 100), nombrePlan: "Cartulina · <plan>", diasValidos: template.days, anotacion: "Cartulina física"}` |

- "Crea un plan de origen `MIGRADA`, sin cobro" (lo dice el endpoint). `precioUnitarioCentavos` es "lo que el local le debe al cliente": cuenta en `almuerzos-pendientes` (pasivo).
- Respuesta `ClienteDetalleResponse`: el plan nuevo es `planes[0]` (el más reciente) → `cardId = planes[0].id`.
- **Deshacer:** `POST /v1/planes-vendidos/{id}/deshacer` "solo sin almuerzos consumidos": **verificar en la prueba de humo que acepta planes `MIGRADA`**. Si responde `400/409`, usar commit diferido (10.2). Si se creó un cliente nuevo y se deshace, además `PATCH /v1/clientes/{id} {activo: false}`.
- Solo rol Dueño: un cajero que llegue a esta pantalla recibe `403` (el rol Cajero ya no ve Ajustes con esta entrada).

### 8.11 O11 · Oferta flash (`oferta_flash_sheet.dart`)

**Hoy:** dos tipos, **Flash de hoy** y **Promo programada** (días y horas "muertas"), con plato, descuento (%), cupos y hora límite; "Publicar oferta" y "Cancelar oferta".

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `publishOffer(restaurantId, offer)` | `POST /v1/ofertas` (Dueño) + **IK** | `PublicarOfertaDto {titulo (≤80), descripcion (≤300), platoId?, precioCentavos, precioOriginalCentavos, stock (1 a 1000), duracionMinutos (5 a 1440)}`. `precioCentavos` **debe ser menor** al original (`422 OFERTA_PRECIO_INVALIDO`). `stock` = `slots`. `duracionMinutos` = minutos hasta `validUntil` (`HH:mm` de hoy). `precioOriginal` = precio normal del plato; `precio` = `original × (1 − descuento/100)` redondeado. |
| `getActiveOffer` | `GET /v1/ofertas?estado=VIGENTE&limit=1` (Caja) | `OfertaResponse` → `FlashOffer` (9.9). |
| `cancelOffer` | `POST /v1/ofertas/{id}/cerrar` (Dueño) | "Repetirlo devuelve la misma oferta ya cerrada." |

- **Promo programada** (por días de la semana y franja horaria): el backend **solo conoce ofertas que empiezan al publicarse** y duran N minutos. Plan B (B-20): ocultar la opción "Promo programada" (E3) hasta tener el endpoint.
- Del lado del comensal: `GET /v1/restaurantes/{slug}/ofertas` (público). El cobro de una oferta se hace **en caja** con `POST /v1/ofertas/{id}/canjear` (Caja, + IK; `{cantidad, metodoPago, comensalId?}`); hoy la UI de Caja no tiene esa acción (backlog P-03).

### 8.12 O12 · Pedidos en camino (`pedidos_screen.dart`)

**Hoy:** lista de preórdenes con sopa, segundo, tiempo ("Hace N min") y dos casos:
- **En efectivo:** "$3,00 en efectivo" y **"Cobrar y entregar"** (morado tonal) → hoja "Cobrar pedido #N" (solo efectivo, **"Cobré $3,00 · Entregar"** morado relleno).
- **Cubierto por plan:** línea "Pago: Plan prepagado", `QR: …`, botón **"Validar QR"** (descuenta 1 almuerzo); luego badge verde **"Validado"** y botón **"Entregar"** (morado tonal). Sin botones verdes rellenos.
- El escáner con `BCD-ORD-<n>` abre esta pantalla con `?cobrar=<n>` y salta directo a la hoja que corresponda.

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `getActiveOrders` | `GET /v1/caja/pedidos` (Caja) | Por defecto las activas (`EN_CAMINO` y `CANJEADA`), por `numero`. Polling 8 s. → `OwnerOrder` (9.10). |
| `validateOrder(number)` | `POST /v1/caja/pedidos/{id}/canjear` (Caja) + **IK** | Solo para pedidos con plan. Guardar `almuerzo.consumoId`. Si `almuerzo.resultado` no es `OK`/`OK_ADVERTENCIA` → devolver `false` con el motivo traducido (por ejemplo `SIN_SALDO` → "Su plan ya no tiene almuerzos."). |
| `undoValidate(number)` | `POST /v1/caja/consumos/{consumoId}/deshacer` (Caja) | 10 s. |
| `deliverOrder(number)` | `POST /v1/caja/pedidos/{id}/servir` (Caja) | Con plan: solo `servir`. En efectivo: `canjear` y luego `servir`. **Commit diferido de 10 s** (10.2): el repositorio marca el pedido "por entregar", lo **oculta** de `getActiveOrders` y envía las llamadas a los 10 s. |
| `undoDeliver(number)` | — | Cancela el temporizador del commit diferido. Pasados los 10 s no hay deshacer (`ApiCapabilities.orderUndoDelivery == false`). |

Qué hace falta que el repositorio recuerde: mapa `número → {id (uuid), consumoId?, paidByPlan, validated}` y el conjunto de pedidos "por entregar".

Reglas de la UI sobre el pedido (9.10):
- `paidByPlan` = `almuerzo?.cubiertoPorPlan == true`. Si `totalCentavos > 0` aun con plan (extras o recargo), la tarjeta además pide ese efectivo: **tras validar, mostrar "Cobrar $X · Entregar"** con la hoja de efectivo. Si la UI actual no lo contempla, se trata como cobro en efectivo del excedente.
- `validated` = `estado == CANJEADA`.
- Un pedido `EXPIRADA` o `CANCELADA` sale de la lista. `409 PEDIDO_EXPIRADO`: "Este pedido venció (pasaron más de 30 minutos)."

### 8.13 O13 · Cierre de caja (`cash_closing_screen.dart`)

**Hoy:** efectivo esperado, campo "efectivo contado", diferencia (Cuadra / Falta / Sobra), "Cerrar turno" (solo dueño), reabrir.

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `getDailyClosingSummary` | `GET /v1/caja/cierre/hoy` (Caja) | `CierreCajaResponse` → `TransactionSummary` (9.11). `efectivoEsperadoCentavos` = cobros confirmados en efectivo del día (planes + ventas sueltas + pedidos + ofertas) menos reversos. |
| `isShiftClosed` | (mismo) | `cierre != null`. |
| `closeShift(restaurantId, countedCash)` | `POST /v1/caja/cierre/hoy` (Caja) | `{efectivoContadoCentavos, nota?}`. "Un solo cierre activo por día (repetir → 409)". "El cajero solo cierra el día de hoy." `cierre.movimientosDespuesDelCierre == true` → avisar "Hubo cobros después del cierre. Reabre y vuelve a contar." |
| `reopenShift` | `POST /v1/caja/cierre/hoy/reabrir` (**Dueño**) | "El cierre anterior queda en el historial." |

- **No hay comisión de Bocadoo**: el modelo es SaaS por mensualidad ("el local se queda con todo lo que cobra"). Si algún texto o cálculo de la UI muestra una comisión, hay que quitarlo (avisar a Carlos).
- `porMetodo` (efectivo, transferencia, Deuna) permite mostrar el desglose si la UI lo pide.

### 8.14 O14 · Tus números (`owner_metrics_screen.dart`)

**Hoy:** tres pestañas. **Hoy** (almuerzos servidos con comparación, **valor aproximado "$X,XX aprox."**, almuerzos por servir, platos más pedidos, acceso a Opiniones), **Dinero** (por servir, vencidos, ventas con periodo semana/mes), **Clientes** (por renovar, no han vuelto, horas pico, resumen semanal por WhatsApp). Todo en rol Dueño.

| Dato de la UI (`OwnerMetrics`) | Endpoint (Dueño) | Cálculo |
|---|---|---|
| `servedToday` | `GET /v1/reportes/resumen-diario` | `almuerzos.servidos` |
| **valor aproximado de hoy** | `GET /v1/restaurante` | `servedToday × precioSueltoCentavos / 100` (es `lunchPriceProvider`; la UI ya lo calcula) |
| `servedLastWeekSameTime` | `GET /v1/reportes/horas-pico?desde=<hoy−7>&hasta=<hoy−7>` | Suma de `porHora[h].almuerzos` para `h ≤ hora actual`. Si falla, `null` ("La semana pasada a esta hora no habías servido"). |
| `pendingLunches`, `clientsWithPlan` | `GET /v1/reportes/almuerzos-pendientes` | `total.almuerzos`, `total.clientes` |
| `dishes` (`DishRank`) | `GET /v1/reportes/ranking-platos?desde&hasta&limit=5` | `plato.nombre`, `orders = unidades`, `rating = null` (el backend no tiene calificación por plato; `DishRank.rating` ya admite `null`) |
| `expiredLunches`, `expiredPlans`, `expiredValue` | **ninguno** | Plan B (B-18): ocultar la tarjeta "vencidos" (E3). |
| `salesCash`, `salesTransfer` | `GET /v1/reportes/resumen-diario` por día | `ventas-planes` **no** separa por método. Plan B: sumar `ingresos.porMetodo` de `resumen-diario` por cada día del periodo (7 o 30 llamadas en paralelo, con caché de 60 s). Pedir `porMetodo` en `ventas-planes` (B-18). |
| `plansSold` | `GET /v1/reportes/ventas-planes?desde&hasta` | `total.vendidos` |
| `renewals` (`ClientFollowUp`) | `GET /v1/reportes/clientes-a-contactar` | Items con motivo `POR_VENCER` o `PARA_RENOVAR`. `days` = días hasta `venceEl` (o `diasSinActividad`); `lunchesLeft = almuerzosRestantes`; `phone = telefono` (E.164: `toInternationalPhone` ya normaliza). |
| `absent` | (mismo) | Items con motivo `SIN_VENIR`; `days = diasSinActividad`. |
| `peakGrid`, `peakDays`, `peakHours` | `GET /v1/reportes/horas-pico` | Solo devuelve **por hora**, no por día de la semana. Plan B (B-18): una llamada por día de la última semana (hasta 7 en paralelo) para armar la cuadrícula; o mostrar solo las horas. |
| `weeklySummaryEnabled` / `setWeeklySummary` | **ninguno** | Preferencia local (`shared_preferences`) y pedir el envío semanal al backend (B-19). |
| `weekServed`, `weekCollected` | `horas-pico` (7 días) y `ventas-planes` (7 días) | `totalAlmuerzos` y `total.ingresoCentavos` |

- El "valor aproximado" **no** es un reporte: es servidos × precio suelto. Se marca "aprox." por eso.
- Periodo `semana` = últimos 7 días; `mes` = últimos 30 (`RANGO_MUY_LARGO` por encima de 366 días).

### 8.15 O15 · Opiniones (`opiniones_screen.dart`)

**Hoy:** resumen por etiqueta (Rico, Rápido, Porción), pestañas **Pendientes / Respondidas**, tarjeta con nombre, etiqueta, hora y **nota escrita del comensal**, botón "Responder" (tonal) con **Agradecer**, **Reponer almuerzo** (+1 al saldo) y **Escribir por WhatsApp**; deshacer de 10 s. Se abre desde Ajustes y desde Métricas (Hoy).

| Repo | Endpoint (rol) | Detalle |
|---|---|---|
| `getOpinions` | `GET /v1/opiniones?limit=50&cursor=` (Dueño) | `BandejaResponse {items, nextCursor, resumen}`. `OpinionBandeja {id (= id del consumo), cliente: {nombre}, almuerzoEn, plan: {nombre}, creadoEn, etiquetas, comentario, respuesta: {texto, respondidoEn}\|null}` → `OwnerOpinion` (9.10). `isPending` = `respuesta == null`. |
| `replyOpinion(…, thanks)` | `POST /v1/opiniones/{id}/responder` (Dueño) | `{respuesta: "¡Gracias por tu opinión!"}`. "Una por opinión": `409 OPINION_YA_RESPONDIDA`. |
| `replyOpinion(…, replaceLunch)` | `POST /v1/opiniones/{id}/responder` **y** un +1 al saldo | **No hay endpoint para sumar un almuerzo.** Plan B (B-21): responder con "Te repusimos un almuerzo. ¡Gracias por avisarnos!" y crear un plan de cortesía de 1 almuerzo con `POST /v1/clientes/{clienteId}/migrar-cartulina` (Dueño): `{almuerzosRestantes: 1, venceEl: hoy + 7 días, precioUnitarioCentavos: precio suelto, nombrePlan: "Almuerzo de cortesía", anotacion: "Reposición por opinión"}`. Ese plan aparece en el pasivo de `almuerzos-pendientes`. Usar **solo hasta** que exista un endpoint propio. |
| `undoReply(opinionId)` | — | Commit diferido (10.2): la respuesta se envía a los 10 s. Si el +1 ya se aplicó y se deshace, no hay reverso: por eso en `replaceLunch` **todo** (respuesta y +1) va en el commit diferido. |
| Escribir por WhatsApp | local | `whatsAppUri` con `phone` del cliente |

- La opinión **no trae el id ni el teléfono del cliente**, solo `cliente.nombre`. Para "Reponer almuerzo" y "WhatsApp" hay que resolver el cliente con `GET /v1/clientes?q=<nombre>` y quedarse con la coincidencia exacta (B-22: pedir `clienteId` y `telefono` en `OpinionBandeja`). Si no hay coincidencia: `canReplaceLunch = false` y `phone = null` (la UI ya desactiva esas opciones).
- Etiquetas: la UI pinta `Rico`, `Rápido`, `Porción`. Para las demás, usar los nombres: `BUENA_ATENCION` → "Buena atención", `LIMPIO` → "Limpio", `FRIO` → "Frío", `SALADO` → "Salado", `PORCION_PEQUENA` → "Porción pequeña", `DEMORA` → "Demora", `MALA_ATENCION` → "Mala atención". `tag` = la primera etiqueta.
- `resumen.sinResponder` alimenta el contador "N pendientes".

### 8.16 O16 · Ajustes del dueño (`owner_settings_screen.dart`)

**Hoy:** **Rol del dispositivo** (Dueño (Todo) / Cajero / Ayudante; al elegir cajero, la barra pasa a **Caja, Pedidos, Turno** y el título a "Turno"), "Tus números", "Opiniones", "Pasar cartulina", **Resumen semanal por WhatsApp** con vista previa sin emojis, **Logo del local** (`image_picker`, máx. 60 KB, cuadrado 256 px), "Local abierto/cerrado", **Apariencia** (Sistema, Claro, Oscuro), "Soporte Bocadoo" (enlace configurable por `--dart-define`, sin número fijo), datos del local, "Cerrar sesión".

| Elemento | Repo | Endpoint (rol) | Detalle |
|---|---|---|---|
| Datos del local | `getLocalInfo` | `GET /v1/restaurante` (Caja) | `nombre`, `direccion`, `puestos` → `LocalInfo` (9.10). |
| Rol del dispositivo | `ownerRoleProvider` | — | Local (`shared_preferences`, clave `bocadoo-owner-role`). Una cuenta `CAJERO` arranca en cajero y no puede subir a dueño (5.10). |
| Resumen semanal | `setWeeklySummary` | **ninguno** | Local + B-19. La vista previa se arma con los reportes de O14. |
| Logo | `setLogo` | **ninguno para subir** | El backend solo guarda una URL (`PATCH /v1/restaurante {logoUrl}`), pero **no hay endpoint para subir la imagen** (B-28). Plan B: guardar los bytes (≤60 KB) en el teléfono (`shared_preferences` en base64) y mostrarlos; cuando exista la subida, subir y enviar `logoUrl`. Agregar `logoUrl` opcional a `LocalInfo`. |
| Local abierto/cerrado | `setStoreOpen` | `POST /v1/restaurante/activar` / `pausar` (Dueño) | 8.7 |
| Soporte | — | — | `SupportConfig` (no cambia). |
| Cerrar sesión | `AuthRepository.logout` | `POST /v1/auth/logout` | |
| "Tus números", "Opiniones", "Pasar cartulina" | — | — | navegación local |

- En **modo cajero** quedan: rol, apariencia, soporte, datos del local y cerrar sesión.
- Mostrar el uso de escaneos del plan SaaS (`GET /v1/suscripcion/uso`, rol Caja) es backlog (P-05).

---
## 9. Mapeo de modelos, campo por campo

Convención: `←` = de dónde sale el campo Dart. `(c)` = convertir de centavos a dólares con `Money.fromCents`. `(null)` = el backend no lo da y se deja nulo o se usa el valor indicado.

### 9.1 `CustomerPass` ← `PaseResponse` (un pase **por local**)

| Campo Dart | ← API |
|---|---|
| `id` | `locales[i].planes[0].id` (el plan que se descuenta primero, FIFO) |
| `userId` | `usuario.id` |
| `studentName` | `usuario.nombre` |
| `studentCareer` | (null) |
| `planName` | `planes[0].nombre` |
| `totalLunches` | suma de `planes[].almuerzosTotales` |
| `remainingLunches` | `locales[i].almuerzosDisponibles` |
| `expiresAt` | el menor `venceEl` entre `planes[]` (`AAAA-MM-DD`, tratarlo como fecha de fin de día en Ecuador) |
| `qrToken` | `codigo.codigo` (o `GET /v1/pase/codigo?restaurante=` por local) |
| `restaurantId` / `restaurantName` | `locales[i].restaurante.id` / `.nombre` |
| `avatarUrl` | (null) |

### 9.2 `ConsumptionRecord` ← `ConsumoItem`

`id` ← `id` · `passId` ← parámetro · `restaurantName`/`restaurantId` ← `restaurante.nombre`/`.id` · `date` ← `fecha` · `description` ← `plan.nombre` (el backend no da los platos) · `lunchesUsed` ← 1 · `remainingAfter` ← (null, 0) · `status` ← `revertido ? 'Anulado' : 'Validado'`.

### 9.3 `ActiveOrder` ← `PedidoResponse`

| Campo Dart | ← API |
|---|---|
| `orderNumber` | `numero` como texto |
| `status` | `EN_CAMINO → 'PREPARANDO'`, `CANJEADA → 'LISTO'`, `SERVIDA → 'ENTREGADO'` (`EXPIRADA` y `CANCELADA`: no hay pedido activo) |
| `restaurantName` | `restaurante.nombre` |
| `qrPayload` | `qr` |
| `detail` | nombres de `almuerzo.platos` y `extras`, separados por " · " (+ "Para llevar") |
| `soup` | `almuerzo.platos` con `seccion == SOPA` → `nombre` |
| `main` | `almuerzo.platos` con `seccion == FUERTE` → `nombre`; si no hay almuerzo, el primer `extras[].nombre` |
| `takeaway` | `paraLlevar` |
| `takeawaySurcharge` | `recargoLlevarCentavos` (c), o 0,25 por defecto (B-10) |
| `singleLunchPrice` | `precioSueltoCentavos` (c) del local (de la caché de `getRestaurants`), o 3,00 |
| `hasPlan` | `almuerzo?.cubiertoPorPlan ?? false` |
| `expiresAt` | `venceEn` |
| `paidAmount` | solo si `SERVIDA` y no cubierto por plan: `totalCentavos` (c) |
| **`id`** (campo nuevo, opcional) | `id` (uuid) |

### 9.4 `Restaurant`, `MenuItem`, `RestaurantOffer`

`Restaurant` ← `RestauranteCardResponse` (lista) y `RestauranteDetalleResponse` (ficha):

| Campo Dart | ← API |
|---|---|
| `id` | `id` (uuid) |
| **`slug`** (campo nuevo, opcional) | `slug` |
| `name` | `nombre` |
| `description` | `descripcionCorta` ?? '' |
| `address` | `direccion` ?? '' |
| `zone` | `zona.nombre` ?? '' |
| `rating` | (null) — el backend no tiene calificación del local; no mostrarla |
| `distanceKm` | calculado en el teléfono (Haversine) con `latitud`/`longitud`; sin coordenadas: 99 |
| `latitude` / `longitude` | `latitud` / `longitud` |
| `imageUrl` | '' (no hay foto de portada; E4) |
| `logoUrl` | `logoUrl` |
| `singleLunchPrice` | `precioSueltoCentavos` (c) |
| `planLunchPrice` | del detalle: `min(planes[].precioCentavos / almuerzos)` (c); si no hay planes, `null` |
| `occupancy` | `ocupacion.nivel`: `LIBRE→'LIBRE'`, `MODERADO→'MOVIDO'`, `LLENO→'LLENO'` |
| `isOpen` | `abiertoAhora` |
| `categories` | `etiquetas` (o `['Todos']`) |
| `todayMenu` | de `menuHoy.secciones` (abajo) |
| `featuredDish` | nombre del primer plato `FUERTE` no agotado, o 'Sin menú publicado hoy' |
| `hasPlan` | `planes.isNotEmpty` (solo detalle; B-07) |
| `offers` | `GET /v1/restaurantes/{slug}/ofertas` |
| `schedule` | del `horarios` de hoy: "12:00 - 15:30" (día ISO de hoy en Ecuador); si hay varios tramos, unirlos con " · " |
| `tags` | `etiquetas` |
| `juice`, `dessert` | nombre del primer plato `JUGO` / `POSTRE` del menú |
| `takeawaySurcharge` | 0,25 por defecto (B-10) |

`MenuItem` ← `PlatoVitrinaResponse`: `id` ← `id` · `name` ← `nombre` · `category`: `SOPA→'Sopa'`, `FUERTE→'Plato Fuerte'`, `JUGO→'Jugo'`, `POSTRE→'Postre'`, `ADICIONAL→'Desayuno'` si tiene la etiqueta `desayuno` (si no, 'Adicional') · `price` ← `precioCentavos` (c) · `isSoldOut` ← `agotado` · `imageUrl` ← `fotoUrl` · `isVeggie` ← `etiquetas` contiene `vegetariano`.

`RestaurantOffer` ← `OfertaResponse`: `id` ← `id` · `restaurantId` ← el local consultado · `title` ← `titulo` · `badge` ← "Flash · Quedan {stockRestante} cupos · hasta {HH:mm de expiraEn}" · `price` ← `precioCentavos` (c) · `originalPrice` ← `precioOriginalCentavos` (c) · `slotsLeft` ← `stockRestante` · `availableNow` ← `estado == VIGENTE` · `appliesToday` ← true · `reservable` ← false (B-08).

### 9.5 `StampCard` ← `MiTarjeta`

`restaurantId` ← `restaurante.id` · `name` ← `nombre ?? "Club " + restaurante.nombre` · `current` ← `sellos` · `goal` ← `meta` · `reward` ← `premio` · `rewardsAvailable` ← `premiosDisponibles`.

### 9.6 `PlanTemplate` ← `PlanVitrinaResponse`

`id` ← `id` · `restaurantId` ← el local · `type` ← `tipo` en minúscula con inicial mayúscula (`Semanal`) · `name` ← `nombre` · `lunches` ← `almuerzos` · `priceCents` ← `precioCentavos` · `validityDays` ← `vigenciaDias` · `category` ← `'ALMUERZO'` (se infiere de `incluye`; B-27).

### 9.7 `SharedTable`, `TableMember`, `ActiveTable` ← `MesaResponse`

| Campo Dart | ← API |
|---|---|
| `SharedTable.id` | `id` |
| **`invitation`** (campo nuevo, opcional) | `invitacion` |
| `restaurantId` / `restaurantName` | `restaurante.id` / `.nombre` |
| `hostName` | `anfitrion.nombre` |
| `time` | `horaLlegada` → "HH:mm" en hora de Ecuador |
| `mode` | `CADA_UNO→eachOwn`, `INVITO_YO→hostPays` |
| `members` | `miembros[]` → `TableMember(id: 'mem-$i', name: nombre, isHost: esAnfitrion, soup: null, main: null, takeaway: paraLlevar)` |
| `onTheWay` | `estado == EN_CAMINO` |
| `qrPayload` | `"BCD-MESA-" + id` |
| `shareUrl` | `"bocadoo://mesa/" + invitacion` (4.7) |
| `occupancyLabel`, `soups`, `mains`, `takeawaySurcharge` | de `GET /v1/restaurantes/{slug}` del local (menú de hoy y ocupación): `LIBRE→'Fluido · Llegas y te sientas'`, `MODERADO→'Movido · Puede haber una espera corta'`, `LLENO→'Lleno · Mejor llega un poco más tarde'` |
| `ActiveTable.url` | `"BCD-MESA-" + id` · `membersCount` ← `miembros.length` · `time` ← igual que arriba |

### 9.8 `OwnerPlanTemplate` ← `PlantillaPlanResponse`

`id` ← `id` · `name` ← `nombre` · `lunches` ← `almuerzos` · `price` ← `precioCentavos` (c) · `validityDays` ← `vigenciaDias` · `kind`: `SEMANAL→semanal`, `QUINCENAL→quincenal`, `MENSUAL→mensual`, `LIBRE→libre` · `coverage` ← inferida de `incluye` (8.9) · `includes` ← `incluye` · `days` ← `diasValidos` (ints) · `quota` ← `cupos ?? 0` (0 = sin límite; la UI usa un número, mostrar "Sin límite" si es 0 requiere E3; alternativa: `cupos ?? 999`) · `visible` ← `visibleEnMarketplace` · `active` ← `activo`. Contadores: `vendidosActivos`, `cuposDisponibles`.

### 9.9 Dueño: clientes, platos, menú, catálogo POS y ofertas

`OwnerClient` ← `ClienteResponse`: `id` ← `id` · `name` ← `nombre` · `phone` ← `Phone.toLocal(telefono)` · `email` ← `correo ?? ''` · `notes` ← `nota ?? ''` · `habitualPlan` ← `almuerzosDisponibles > 0 ? "<n> almuerzos disponibles" : null` (B-25).

`CatalogDish` ← `PlatoResponse`: `id` ← `id` · `name` ← `nombre` · `kind`: (`ALMUERZO`,`SOPA`)→`sopa`, (`ALMUERZO`,`FUERTE`)→`segundo`, (`ALMUERZO`,`JUGO`)→`bebida`, (`ALMUERZO`,`POSTRE`)→`postre`, `A_LA_CARTA`→`carta`, `EXTRA`+etiqueta `desayuno`→`desayuno` · `price` ← `precioCentavos` (c) · `description` ← `descripcion ?? ''` · `archived` ← `!activo` · `veggie` ← etiqueta `vegetariano` · `topPick` ← false.

`DailyMenuCourse` ← `ItemMenuResponse`: `id` ← `id` (renglón) · **`dishId`** (campo nuevo, opcional) ← `platoId` · `name` ← `nombre` · `category`: `SOPA→'Sopa'`, `FUERTE→'Fuerte'`, `JUGO→'Jugo'`, `POSTRE→'Postre'`, `ADICIONAL` con etiqueta `desayuno` → `'Desayuno'` · `isSoldOut` ← `agotado` · `price` ← `(precioDelDiaCentavos ?? precioCentavos)` (c).
`DailyMenu` ← `MenuDiaResponse`: `restaurantId` ← el activo · `date` ← `fecha` · `courses` ← `items` · `isPublished` ← `publicado` · `isOpen` ← `GET /v1/restaurante` → `estado == 'ACTIVO'`.
Para publicar, el camino inverso: cada `DailyMenuCourse` → `{platoId: dishId, seccion: (Sopa→SOPA, Fuerte→FUERTE, Jugo→JUGO, Postre→POSTRE, Desayuno→ADICIONAL), precioCentavos: price→centavos solo si difiere, orden: índice}`.

`CatalogItem` (POS) ← `PlatoResponse`: `id` ← `id` · `name` ← `nombre` · `description` ← `descripcion ?? ''` · `price` ← `precioCentavos` (c) · `category`: `A_LA_CARTA→carta`, `EXTRA→extras`, `BEBIDA→bebidas`. "Almuerzos" y "Desayunos": ver 8.6.

`FlashOffer` ← `OfertaResponse`: `kind` ← `flash` · `title` ← `titulo` · `discountPercent` ← `descuentoPorcentaje` · `slots` ← `stockRestante` · `price` ← `precioCentavos` (c) · `validUntil` ← `expiraEn` → "HH:mm" local · `days`/`fromMinutes`/`toMinutes` ← vacíos (B-20).

### 9.10 Dueño: pedidos, mesas, opiniones, local

`OwnerOrder` ← `PedidoCaja`:

| Campo Dart | ← API |
|---|---|
| `number` | `numero` como texto |
| **`id`** (campo nuevo, opcional) | `id` (uuid) |
| `dinerName` | `comensal.nombre` |
| `soup` / `main` | `almuerzo.platos` por `seccion` (`SOPA` / `FUERTE`) |
| `takeaway` | `paraLlevar` |
| `amount` | `totalCentavos` (c) — lo que se cobra en efectivo (0 si el plan lo cubre y no hay extras) |
| `createdAt` | `creadoEn` |
| `paidByPlan` | `almuerzo?.cubiertoPorPlan == true` |
| `validated` | `estado == CANJEADA` |

`TablePreview` ← `MesaVistaResponse` (+ precios de `GET /v1/restaurante`): `tableId` ← id del paso · `hostName` ← el miembro con `esAnfitrion` · `time` ← `horaLlegada` "HH:mm" · `mode` ← `modo` · `lines[]` ← una `TableChargeLine` por miembro con la vía de pago de 4.1.3 · `stamps` ← de `resultados` tras validar · `settled` ← `estado == FINALIZADA` o `validadaEn != null` · `error` ← según 4.1.3.
`TableChargeLine.amount` (efectivo): `precioSueltoCentavos` + (`paraLlevar` ? `recargoParaLlevarCentavos` : 0), en dólares.

`OwnerOpinion` ← `OpinionBandeja`: `id` ← `id` · `dinerName` ← `cliente.nombre` · `tag` ← primera de `etiquetas` con su nombre en español (8.15) · `note` ← `comentario` · `createdAt` ← `creadoEn` · `reply` ← `respuesta?.texto` · `phone`/`canReplaceLunch` ← por búsqueda de cliente (B-22).

`LocalInfo` ← `RestauranteResponse`: `name` ← `nombre` · `address` ← `direccion ?? ''` · `seats` ← `puestos` · **`logoUrl`** (campo nuevo, opcional) ← `logoUrl` · `logo` ← bytes locales (B-28).

### 9.11 Dueño: caja, ventas y escaneo

`ScanResult` ← `ValidacionResponse` (tabla completa en 4.1.4): `isValid` ← `descontado` · `studentName` ← `cliente.nombre` · `passId` ← `cliente.id` · `remainingLunches` ← `almuerzosRestantes` · `redemptionId` ← `consumo.id` · `redeemedAt` ← `consumo.creadoEn` · `supportingLine` ← `mensaje` traducido · `totalLunches` (null) · `studentCareer` (null).

`TransactionSummary` ← `CierreCajaResponse` (+ `resumen-diario` para `plansSoldToday`):
`date` ← `fecha` · `lunchesRedeemedToday` ← `almuerzosServidos` · `plansSoldToday` ← `resumen.planesVendidos.cantidad` (0 para cajero) · `totalIncomeToday` ← `totalCentavos` (c) · `cashExpected` ← `efectivoEsperadoCentavos` (c) · `cashCounted` ← `cierre?.efectivoContadoCentavos ?? esperado` (c) · `cashDifference` ← `cierre?.diferenciaCentavos ?? 0` (c) · `cashStatus` ← `diferencia == 0 ? 'Cuadra' : (diferencia < 0 ? 'Falta' : 'Sobra')` · `transactions` ← 8.1.

`TransactionItem` ← `VentaResponse`: `id` ← `id` · `customerName` ← `mesaTexto ?? 'Venta #<ticket>'` · `type` ← `'Venta Suelta'` · `amount` ← `totalCentavos` (c) · `paymentMethod` ← `pago.metodo` en español (`EFECTIVO→Efectivo`, `TRANSFERENCIA→Transferencia`, `DEUNA→Deuna`) · `timestamp` ← `creadoEn`. Ventas con `deshecha == true` no se listan.

### 9.12 Campos nuevos, todos opcionales (no rompen la UI ni el mock)

| Modelo | Campo | Uso |
|---|---|---|
| `Restaurant` | `slug` | ficha, ofertas y solicitud de plan |
| `ActiveOrder` | `id` | cancelar, polling |
| `SharedTable` | `invitation` | enlace de invitación |
| `OwnerOrder` | `id` | canjear, servir |
| `DailyMenuCourse` | `dishId` | publicar el menú |
| `LocalInfo` | `logoUrl` | logo remoto |

---

## 10. Brechas del backend y planes B

### 10.1 Tabla de brechas

Cada fila = algo que la app tiene (o necesita) y el backend `1.0.0-rc.1` **no** ofrece. Todas tienen plan B (R10) y una bandera en `ApiCapabilities` cuando aplica. La columna "Pedir a Chucho" se entrega tal cual a backend.

| ID | Qué falta | Pantallas | Plan B hoy | Pedir a Chucho |
|---|---|---|---|---|
| B-01 | Login con Google | A1, A3, A4, A5 | Mensaje "estará disponible pronto"; botón visible | `POST /v1/auth/google {idToken, rol?, restaurante?}` → `TokenResponseDto`, y el OAuth Web client ID |
| B-02 | Teléfono, zona y coordenadas del comensal | A4, C6, C2 | `LocalProfileStore` + evento `registro.ubicacion` en `/v1/eventos` | `telefono`, `zonaId`, `latitud`, `longitud` opcionales en `RegisterDto` y un `PATCH /v1/auth/me` |
| B-03 | Recuperar contraseña | A2 | Mensaje de soporte (no finge éxito) | `POST /v1/auth/forgot`, `POST /v1/auth/reset` |
| B-04 | Catálogo de zonas | A5, A4 | Solo `zonaId: 1` ("Frente a la PUCE") confirmado | `GET /v1/zonas?ciudadId=1` o la tabla id ↔ nombre |
| B-05 | RUC del restaurante | A5 | Guardar local | Campo `ruc` en `RestauranteNuevoDto` y `PATCH /v1/restaurante` |
| B-06 | Editor de horarios (UI) | A7, O16 | Horario por defecto lun a vie 12:00 a 15:30 | **Pregunta a Carlos**: ¿se agrega pantalla de horarios? |
| B-07 | `tienePlanes` y `tieneOfertas` en la tarjeta de la lista | C2 | Cargar el detalle en segundo plano | Esos dos booleanos en `RestauranteCardResponse` |
| B-08 | Reservar una oferta flash desde la app | C3 | `reservable = false`; "Pídela en caja" | `POST /v1/restaurantes/{slug}/ofertas/{id}/reservar` |
| B-09 | Que el comensal use su premio de sellos | C1 | El premio se usa en caja; el botón "Reclamar" se reemplaza por texto "Muéstralo en caja" (E3, `claimStampReward`) | Aceptable tal cual; confirmar |
| B-10 | Recargo para llevar en el detalle público | C3, C8 | 0,25 por defecto; el servidor corrige el total | `recargoParaLlevarCentavos` en `RestauranteDetalleResponse` |
| B-11 | Enlace web de la mesa | C9 | Compartir `bocadoo://mesa/<id>` + código | Página puente `https://bocadoo.ec/mesa/<id>` que abra el esquema |
| B-12a | Cambiar el modo de la mesa | C9, O5 | Cancelar y recrear si no hay invitados; si hay, bloquear (E3) | `PATCH /v1/mis/mesas/{id} {modo}` |
| B-12b | "Avisar a cocina" | C9 | Ocultar el botón (E3) | Definir cuándo pasa a `EN_CAMINO`, o `POST /v1/mis/mesas/{id}/en-camino` |
| B-12c | Elegir sopa y fuerte al unirse | C7 | Se muestra pero no se envía | `sopaId`, `fuerteId` opcionales en `UnirseDto` |
| B-13 | Varios restaurantes por usuario | A1, O* | Se toma el primero | Confirmar si es posible; si sí, un selector (UI nueva) |
| B-14 | Ruta a pie y teselas para producción | C11 | OSRM y OSM públicos (solo demo) | `GET /v1/rutas?...` propio, o un proveedor con clave |
| B-15 | Listado de mesas por cobrar para la caja | O1, O5 | Banner oculto; se cobra por QR (E3) | `GET /v1/caja/mesas?estado=ABIERTA\|EN_CAMINO` |
| B-16 | Deshacer entrega o validación de un pedido | O12 | Commit diferido de 10 s (10.2) | `POST /v1/caja/pedidos/{id}/deshacer` |
| B-17 | Movimientos del día (planes vendidos y validaciones) | O1 | "Cobros de hoy" = ventas + pedidos servidos | `GET /v1/caja/movimientos?fecha=` |
| B-18 | Reportes: almuerzos vencidos; ventas de planes por método; horas pico por día de la semana | O14 | Ocultar "vencidos"; sumar `resumen-diario` por día; 7 llamadas de `horas-pico` | `GET /v1/reportes/almuerzos-vencidos`; `porMetodo` en `ventas-planes`; `porDiaSemana` en `horas-pico` |
| B-19 | Resumen semanal por WhatsApp | O14, O16 | Preferencia local | `PUT /v1/restaurante/resumen-semanal {activo}` y el envío programado |
| B-20 | Oferta programada (días y franja) | O11 | Ocultar la opción (E3) | `diasSemana`, `desde`, `hasta` en `PublicarOfertaDto` |
| B-21 | "Reponer almuerzo" (+1) | O15 | `migrar-cartulina` de 1 almuerzo (8.15) | `POST /v1/clientes/{id}/almuerzos {cantidad, motivo}` |
| B-22 | `clienteId` y `telefono` en la bandeja de opiniones | O15 | Buscar el cliente por nombre | Esos campos en `OpinionBandeja` |
| B-23 | Cancelar una solicitud de plan | C5 | Commit diferido de 10 s | `POST /v1/solicitudes-plan/{id}/cancelar` (comensal) |
| B-24 | Que `deshacer` acepte planes migrados (cartulina) | O10 | Probar en la Fase 4; si no, commit diferido (10.2) | Confirmar si `POST /v1/planes-vendidos/{id}/deshacer` acepta `origen: MIGRADA` |
| B-25 | Plan actual del cliente en la lista | O8 | "n almuerzos disponibles" | `planActual` en `ClienteResponse` |
| B-26 | ¿`canjear` registra el efectivo del pedido? | O12 | Verificar en la Fase 3 (4.1.2) | Confirmar el comportamiento por escrito |
| B-27 | Categorías de desayuno y cobertura de plan (almuerzo, desayuno, mixto) | O7, O9, O6, C3 | Etiqueta `desayuno` y `incluye` (8.7, 8.9) | Categoría `DESAYUNO` en platos y `cobertura` en planes |
| B-28 | Subir el logo del local | O16 | Guardar local (≤60 KB) | `POST /v1/restaurante/logo` (multipart) o una URL prefirmada |
| B-29 | Foto de portada del local | C2, C3 | Logo o degradado (E4) | `fotoUrl` en el local |

Banderas de `ApiCapabilities` (5.12): B-01 `googleSignIn`, B-03 `forgotPassword`, B-09 `claimStampReward`, B-12a `sharedTableModeChange`, B-12b `sharedTableNotifyKitchen`, B-12c `sharedTableDishChoice`, B-15 `ownerPendingTablesList`, B-16 `orderUndoDelivery`, B-18 `expiredLunchesReport`/`peakByWeekday`/`salesByMethodRange`, B-19 `weeklySummaryToggle`, B-20 `flashScheduledOffer`, B-23 `cancelPlanRequest`, tarjeta `cardPayment`.

### 10.2 Patrón "commit diferido" (para el deshacer de 10 s sin endpoint)

Se usa cuando la UI ofrece "Deshacer" pero el backend no tiene la operación inversa (O12 entregar, O15 responder, C5 solicitar plan, O10 cartulina si el deshacer del plan migrado no aplica).

```dart
class DeferredCommit {
  final _timers = <String, Timer>{};
  final _pending = <String>{};
  bool isPending(String key) => _pending.contains(key);

  /// Programa [action] en 10 s. El repositorio devuelve `true` enseguida.
  void schedule(String key, Future<void> Function() action, {Duration delay = const Duration(seconds: 10)}) {
    _pending.add(key);
    _timers[key] = Timer(delay, () async {
      _timers.remove(key);
      try { await action(); } finally { _pending.remove(key); }
    });
  }
  /// "Deshacer": cancela el envío. Devuelve `true` si todavía estaba pendiente.
  bool cancel(String key) {
    final t = _timers.remove(key);
    t?.cancel();
    return _pending.remove(key) && t != null;
  }
}
```

Reglas:
1. Mientras un elemento está pendiente, el repositorio lo **oculta o lo marca** en las listas (por ejemplo `getActiveOrders` excluye los pedidos "por entregar") para que la UI se vea como si ya se hubiera hecho.
2. Si la petición diferida falla, el repositorio guarda el error y la próxima lectura restaura el elemento; mostrar un `SnackBar` con el mensaje traducido.
3. Si la app se cierra antes de los 10 s, **la acción se pierde**: la operación vuelve a aparecer pendiente al volver. Es el comportamiento aceptado.
4. **Nunca** usar commit diferido para dinero que ya se cobró en una llamada anterior sin reverso. Por eso en O12 en efectivo, **todo** (`canjear` y `servir`) se difiere junto.

### 10.3 Textos de la app cuando falta una función

Usar estos textos (13 px, sin "canje", tuteo) y siempre con una salida:

| Situación | Texto |
|---|---|
| Google no disponible | "El acceso con Google estará disponible pronto. Entra con tu correo." |
| Recuperar contraseña | "Por ahora escríbenos y te ayudamos." |
| Oferta sin reserva | "Pídela en caja." |
| Premio de sellos | "Muéstralo en caja." |
| Cambiar modo de la mesa con invitados | "El modo no se puede cambiar con invitados." |
| Sin conexión | "Sin conexión. Mostramos lo último que guardamos." |
| Servidor despertando | "Despertando el servidor… puede tardar un momento." |

### 10.4 Backlog: lo que el backend ya tiene y la app no muestra

Estas pantallas **no existen hoy**. No se hacen sin que Carlos las apruebe y diseñe. Se registran aquí para que James las conozca; solo **P-01** es necesaria para que el flujo del comensal tenga sentido.

| ID | Endpoint(s) | Qué falta | Prioridad |
|---|---|---|---|
| P-01 | `GET /v1/solicitudes-plan`, `POST …/{id}/cobrar`, `POST …/{id}/rechazar` | **Bandeja de solicitudes de plan** del comensal (C5). Sin ella nadie ve esas solicitudes. Propuesta: tarjeta "N solicitudes de plan" en Caja → hoja con la lista y "Cobrar" (reutiliza el selector de método de O3). | **Alta (Fase 4)** |
| P-02 | `GET /v1/pagos/pendientes`, `POST /v1/pagos/{id}/confirmar\|rechazar` | Pagos por transferencia o Deuna pendientes de confirmar | Media |
| P-03 | `POST /v1/ofertas/{id}/canjear` (texto de UI: "Validar oferta") | Cobrar una oferta flash en caja | Media |
| P-04 | `GET /v1/reclamos`, `POST …/devolver\|rechazar`, `POST /v1/mis/consumos/{id}/reclamo`, `GET /v1/mis/reclamos` | Reclamos de almuerzos (comensal y dueño) | Media |
| P-05 | `GET /v1/suscripcion`, `GET /v1/suscripcion/uso` | Plan SaaS y uso de escaneos (aviso al 80 % y al 100 %: `LIMITE_SAAS`) | Media |
| P-06 | `GET/POST/PATCH /v1/restaurante/personal…` | Personal: agregar cajeros por correo | Media |
| P-07 | `GET/PUT /v1/restaurante/horarios` | Editor de horarios | Alta para publicar (B-06) |
| P-08 | `GET/PUT /v1/sellos/config` y `GET /v1/clientes/{id}/sellos`, `POST …/sellos/canjear` | Configurar la tarjeta de sellos y usar un premio | Media |
| P-09 | `GET/POST/PATCH /v1/restaurante/mesas` | Mesas físicas del local (etiqueta y capacidad) | Baja |
| P-10 | `GET /v1/mis/consumos`, `GET /v1/mis/opiniones` | Historial completo del comensal y sus opiniones con respuesta | Baja |
| P-11 | `POST /v1/eventos` | Analítica de producto en lote (opcional, ver Fase 5) | Baja |
| P-12 | `POST /v1/auth/logout-all` | "Cerrar sesión en todos los dispositivos" | Baja |
| P-13 | `POST /v1/clientes/{id}/vincular\|desvincular` | Vincular un cliente del local con la cuenta de la app (por correo) | Media: es lo que hace que un cliente de caja **vea sus planes en su app** |

> **P-13 es crítico para el flujo comensal ↔ caja:** los planes vendidos en caja pertenecen a un **cliente del local**. El comensal solo los ve en `GET /v1/pase` si su cuenta está **vinculada** a ese cliente (`vinculadoApp: true`). Si el cliente se creó solo con nombre y teléfono, el comensal **no verá** su plan en la app hasta que el dueño lo vincule por correo (`POST /v1/clientes/{id}/vincular {correo}`). Para las pruebas de humo, vincular por `curl` (sección 12). Proponer a Carlos el campo "correo de la app" en "Agregar cliente" que, si se llena, llame a `vincular` automáticamente (el correo del formulario ya existe).

### 10.5 Preguntas abiertas

**Para Carlos** (producto y UI): ¿editor de horarios (B-06)? ¿pantalla de solicitudes de plan (P-01) y de pagos por confirmar (P-02)? ¿"correo de la app" en Agregar cliente para vincular (P-13)? ¿selector de restaurante si un usuario tiene varios (B-13)? ¿cambiar el texto "Google Maps" del encabezado del mapa de A5?
**Para Chucho** (backend): las filas de la tabla 10.1, más: forma del objeto `usuario` en login y registro; el comportamiento de `canjear` con efectivo (B-26); si `deshacer` de un plan vendido acepta planes `MIGRADA`; el tipo de `diasValidos` en `PATCH /v1/planes/{id}` (string o entero); los ids de zona; qué credenciales inválidas devuelve el login (`400` o `401`); si `GET /v1/restaurante/mesas` lista mesas físicas o mesas compartidas (el esquema de respuesta dice `MesaResponse`, de las compartidas, pero el cuerpo de creación es `{etiqueta, capacidad}`).

---
## 11. Plan de ejecución en 5 fases, con prompts listos para copiar

Orden: cada fase depende de la anterior. **No se salta ninguna.** Al final de cada fase: `flutter analyze` con 0 problemas, `flutter build apk --debug` correcto, pruebas de humo (sección 12) y **un commit** con el ID de las pantallas.

| Fase | Pantallas | Qué entrega |
|---|---|---|
| **1** | A1 a A7 + Bloque 0 | Red, sesión, tokens, errores, guardia del router y Auth completo |
| **2** | C1 a C6, C11 | Comensal: pase con QR, restaurantes, fichas, planes, cuenta, mapa, pedir y solicitar plan |
| **3** | O1 a O6, O11 a O13 + C8 | Dueño operativo: Caja, escáner universal, ventas, POS, ofertas, **pedidos (O12) con su aviso al comensal**, cierre |
| **4** | O7 a O10, O14, O16 + P-01 | Dueño de gestión: menú, planes, clientes, cartulina, métricas, ajustes y bandeja de solicitudes de plan |
| **5** | C7, C9, C10, O5, O15 + cierre | Mesas, opiniones, sincronización final, enlaces, analítica opcional, retiro del `DemoStore` en modo API y endurecimiento |

### 11.0 Prompt maestro (pegar una sola vez al empezar la sesión)

```text
Eres el asistente de James Argüello. Vas a conectar la app Flutter de Bocadoo (carpeta mobile/) con el backend NestJS desplegado en https://bck-bocadoo.onrender.com. La única guía es docs/roadmap_integracion_james_arguello.md; la especificación del backend está en docs/api/openapi.json. Léelos completos antes de escribir código.

Reglas que nunca se rompen:
1. NO modifiques lib/features/*/presentation/ salvo los ajustes E1 a E6 de la sección 3.8 del roadmap. Si crees que necesitas otro, DETENTE y pregunta.
2. Las pantallas hablan con repositorios (interfaces). Implementas ApiCustomerRepository y ApiOwnerRepository; no cambias las firmas de las interfaces. Agregas solo campos OPCIONALES a los modelos (sección 9.12).
3. El modo mock debe seguir funcionando con --dart-define=BOCADOO_USE_MOCK=true.
4. Cero endpoints inventados. Lo que no existe en el Swagger se resuelve con el plan B de la sección 10 y un comentario // TODO(backend): B-xx.
5. Colores y fuente solo del tema (Outfit). Texto mínimo 13 px. Un solo botón morado relleno por pantalla. Sin emojis en titulares. La palabra "canje" NUNCA aparece en un texto visible (el backend usa "canjear" internamente: es solo código). Los errores se muestran traducidos por code (sección 13), nunca el detail del servidor.
6. No agregues paquetes sin aprobación (sección 1.2, R9).
7. Dinero en centavos hacia y desde el backend; la app usa dólares (Money). Teléfonos en E.164. Todo POST/PATCH que mueve dinero o crea cosas lleva Idempotency-Key.
8. Tokens solo en flutter_secure_storage. Nunca en logs.
9. Al terminar la fase: flutter analyze sin problemas, flutter build apk --debug correcto, y las pruebas de humo de la sección 12. No hagas git push. Haz UN commit con el ID de las pantallas.
10. Al final, entrega un resumen: qué conectaste, qué plan B usaste (con su ID B-xx) y qué quedó pendiente.
```

### 11.1 Fase 1 — Bloque 0 y Auth (A1 a A7)

**Objetivo:** que la app pueda registrar, iniciar sesión, mantener la sesión y proteger rutas, con errores traducidos y tolerancia al arranque en frío de Render.

**Prerrequisito:** ninguno.

**Archivos:** los de 5.1 (`core/config`, `core/network`, `core/session`, `core/utils/formatters.dart`, `features/auth/data/`), `core/router/app_router.dart` (guardia), `features/auth/presentation/*` (solo E1 y E2), `android/.../AndroidManifest.xml` (`allowBackup="false"`).

**Prompt:**

```text
FASE 1 — Bloque 0 y Auth (A1 a A7). Aplica el prompt maestro.

Haz, en este orden:
1. core/config/app_mode.dart y reescribe core/network/api_config.dart (sección 5.2): baseUrl https://bck-bocadoo.onrender.com por defecto, BOCADOO_API_URL y BOCADOO_USE_MOCK por --dart-define. Borra las rutas de ejemplo.
2. core/network/token_store.dart (flutter_secure_storage), api_exception.dart (ApiException + ErrorMessages con la tabla de la sección 13), idempotency.dart (uuidV4 e IdempotencyStore), formatters.dart (Money, Phone, EcuadorTime).
3. core/network/api_client.dart con los 4 interceptores de la sección 5.4: AuthInterceptor con refresh de UN SOLO VUELO (el refresh token es de un solo uso; reutilizarlo revoca la sesión), RestaurantInterceptor (x-restaurant-id), RetryInterceptor (solo GET o peticiones con Idempotency-Key; 2s, 5s, 10s; solo timeouts, errores de conexión y 502/503/504) y ProblemInterceptor que produce ApiException desde application/problem+json.
4. core/session/session_notifier.dart (sección 5.10): login, GET /v1/auth/me, restaurante activo, expire(), logout (POST /v1/auth/logout y limpiar). Un singleton global que lee el router y un sessionProvider.
5. core/config/api_capabilities.dart (sección 5.12).
6. features/auth/data/auth_repository.dart: IAuthRepository, MockAuthRepository (comportamiento actual), ApiAuthRepository (login, registerDiner, registerOwner, me, logout, logoutAll; signInWithGoogle y requestPasswordReset con el plan B de 6.4 y 6.5, sin fingir éxito).
7. Guardia del router (5.10) en app_router.dart. Con AppMode.useMock no se exige sesión.
8. Calentamiento del servidor: GET /health al abrir el login con timeout de 90 s, sin bloquear; si tarda más de 4 s, mostrar "Despertando el servidor… puede tardar un momento." (único texto nuevo permitido).
9. Presentation, SOLO ajustes E1 y E2: reemplaza los Future.delayed y los TODO de login_screen, register_diner_screen, register_owner_screen, forgot_password_screen, onboarding_diner_screen, onboarding_owner_screen y google_sign_in_flow por llamadas a IAuthRepository (provider que elige Mock o Api). Contraseña mínima de 10 caracteres en A4 y A5.
10. Registro de dueño (6.6): register-owner → login → me → PATCH /v1/restaurante con teléfono E.164, dirección, latitud, longitud, zonaId (solo 1 = "Frente a la PUCE" está confirmado; omite zonaId para las demás) y precioSueltoCentavos. Onboarding del dueño (6.8): POST /v1/planes x3, PATCH /v1/restaurante {puestos}, PUT /v1/restaurante/horarios por defecto lunes a viernes 12:00-15:30 y POST /v1/restaurante/activar al final (si falla, deja en borrador con un SnackBar).
11. Registro de comensal (6.3): register → login; teléfono, zona y coordenadas a un LocalProfileStore (shared_preferences) y un evento registro.ubicacion en POST /v1/eventos si hay sesión (ignora si falla).
12. AndroidManifest.xml: android:allowBackup="false".

No toques nada de customer/ ni owner/ en esta fase salvo lo necesario para que compilen. Entrega: lista de archivos, resultado de flutter analyze y de la prueba de humo de la Fase 1.
```

**Criterios de aceptación:**
- Registrar un comensal nuevo desde la app y entrar a Mi Pase con sesión real.
- Registrar un dueño nuevo, pasar el onboarding y entrar a Caja; el restaurante queda `ACTIVO` (o en borrador con aviso).
- Cerrar la app y volver a abrirla: la sesión se mantiene (refresh transparente).
- Con el access token vencido (esperar 15 min o forzar), una petición protegida se refresca sola y **no** cierra la sesión.
- Dos peticiones simultáneas con el token vencido provocan **un solo** `POST /v1/auth/refresh`.
- Credenciales incorrectas: mensaje claro; correo repetido: mensaje claro; sin red: mensaje de conexión.
- "Continuar con Google" muestra el aviso de la sección 10.3 sin caerse.
- `AppMode.useMock = true`: la app se comporta como antes.

**Humo:** 12.2, "Fase 1". **Commit:** `feat(integracion): bloque 0 y auth contra el backend (A1-A7)`.

### 11.2 Fase 2 — Comensal (C1 a C6, C11)

**Objetivo:** el comensal ve datos reales: su pase con QR rotativo, restaurantes, fichas, planes y su cuenta; puede pedir, cancelar y solicitar un plan.

**Prerrequisito:** Fase 1 aprobada. Al menos un local `ACTIVO` con menú publicado y un plan (se crean con `curl`, sección 12.1).

**Prompt:**

```text
FASE 2 — Comensal (C1 a C6 y C11). Aplica el prompt maestro. Prerrequisito: Fase 1 terminada.

Implementa features/customer/data/api_customer_repo.dart (ApiCustomerRepository implements ICustomerRepository) y cambia customerRepositoryProvider para elegir Mock o Api con AppMode.useMock. Usa ApiClient y guard(). Los mapeos están en la sección 9 y las llamadas en la sección 7. Detalles obligatorios:

1. Modelos (9.12): agrega Restaurant.slug (opcional) y ActiveOrder.id (opcional). Restaurant.id pasa a ser el uuid; guarda un mapa id→slug al cargar getRestaurants.
2. getRestaurants: GET /v1/restaurantes con paginación por cursor (limit 50) hasta agotar. Convierte según 9.4. distanceKm se calcula con Haversine desde la ubicación guardada en LocalProfileStore o el GPS (core/location/location_service.dart); sin coordenadas, 99. Mapa de ocupación: LIBRE→LIBRE, MODERADO→MOVIDO, LLENO→LLENO.
3. getRestaurantById / getTodayMenu / getPlanTemplates / getPlanTemplateById: GET /v1/restaurantes/{slug} (menuHoy, horarios, planes). getPlanTemplateById lee de la caché de planes.
4. Ofertas: GET /v1/restaurantes/{slug}/ofertas → RestaurantOffer (9.4), reservable=false.
5. getActivePasses/getActivePass: GET /v1/pase → un CustomerPass por local (9.1). refreshQrToken: GET /v1/pase/codigo?restaurante=<uuid>. Mantén getCachedPass/saveCachedPass. NO uses BocadooQrParser en modo API. Comprueba en el emulador que el QR de Mi Pase cambia cada 30 s (7.1) y reporta si hay desfase de reloj.
6. getStampCard: GET /v1/mis/sellos filtrado por local (9.5). claimReward: devuelve false y marca ApiCapabilities.claimStampReward = false (B-09).
7. getActiveTable: GET /v1/mis/mesas; la mesa ABIERTA/EN_CAMINO/EN_MESA de hoy o null. NUNCA crear mesas aquí.
8. getActiveOrder: GET /v1/mis/pedidos?limit=5 (9.3). preorder: POST /v1/mis/pedidos con Idempotency-Key (IdempotencyStore con intención "crear-pedido:<restaurante>:<platos ordenados>"), body según 4.1.1 (almuerzo.platos = ids de sopa y fuerte; desayunos como extras; paraLlevar). cancelPreorder: POST /v1/mis/pedidos/{id}/cancelar con mapa interno número→uuid. acknowledgeOrder: bandera local pedido_visto_<id>.
9. getRecentActivity y getConsumptionHistory: GET /v1/mis/consumos (9.2).
10. requestPlan: POST /v1/restaurantes/{slug}/solicitudes-plan {planId}. cancelPlanRequest con commit diferido de 10 s (10.2).
11. getProfile: GET /v1/auth/me + GET /v1/pase + LocalProfileStore (7.5). Cerrar sesión: sessionProvider.logout().
12. getPendingFeedback/submitFeedback/dismissFeedback: déjalos conectados según 7.9 (GET /v1/mis/opiniones/pendientes, POST …/opinion, POST …/opinion/descartar) — se prueba a fondo en la Fase 5.
13. openSharedTable/getSharedTable/setTableMode/notifyKitchen/joinTable: déjalos con UnimplementedError controlado hasta la Fase 5 (que la UI no se caiga: el modo API muestra el aviso "Disponible pronto" donde corresponda).
14. Ajuste E4 (imagen vacía) y E3 donde aplique (claimStampReward).
15. CustomerController: polling de 5 s (refreshLive) mientras haya pedido activo; pausar en segundo plano (WidgetsBindingObserver). Traduce ApiException con userMessage y mantén los estados de carga/error/vacío existentes.

Verifica las reglas: un pedido en camino por local (409 PEDIDO_ACTIVO), menú sin publicar (409 MENU_NO_PUBLICADO), plato agotado (409 PLATO_AGOTADO). Entrega el resumen de planes B usados.
```

**Criterios de aceptación:**
- Mi Pase muestra el plan real (nombre, `restantes/total`, vencimiento) y un QR que cambia cada 30 s.
- Dónde comer lista los locales reales; los filtros funcionan con lo que hay; locales sin coordenadas no rompen el mapa.
- La ficha muestra el menú de hoy, horarios, ocupación y planes.
- "Pedir" crea un pedido real; la hoja C8 muestra `Pedido #N`, la cuenta regresiva de 30 min y el QR; "Deshacer" cancela.
- "Solicitar plan" crea la solicitud real (verificable con `GET /v1/solicitudes-plan` del dueño).
- Sin conexión: se ve el pase en caché con el aviso.
- Ninguna pantalla muestra un texto técnico de error.

**Humo:** 12.2, "Fase 2". **Commit:** `feat(integracion): comensal contra el backend (C1-C6, C11)`.

### 11.3 Fase 3 — Dueño operativo (O1 a O6, O11 a O13) y el aviso de entrega (C8)

**Objetivo:** la caja funciona de punta a punta: escanear (los 3 QR), vender, cobrar, ofertas, cerrar, y el ciclo **pedido del comensal → validar y entregar en caja → "Tu pedido · Entregado" en el comensal**.

**Prerrequisito:** Fase 2 aprobada. Un comensal con plan **vinculado** a un cliente del local (P-13 en 10.4; los pasos están en 12.1).

**Prompt:**

```text
FASE 3 — Dueño operativo (O1-O6, O11-O13) y aviso de entrega (C8). Aplica el prompt maestro. Prerrequisito: Fases 1 y 2.

Implementa features/owner/data/api_owner_repo.dart (ApiOwnerRepository) que implemente IOwnerRepository, IOwnerCashRepository, IOwnerOrdersRepository, IOwnerTablesRepository, IOwnerMenuRepository, IOwnerCatalogRepository, IOwnerMetricsRepository, IOwnerFeedbackRepository e IOwnerSettingsRepository (en esta fase solo los métodos de esta lista; el resto con UnimplementedError controlado y su bandera de ApiCapabilities). Cambia los providers de owner_controller.dart para elegir Mock o Api (sección 3.6). Ajuste E5: ownerRestaurantIdProvider y ownerRestaurantNameProvider leen la sesión. Todas las llamadas de Caja/Dueño usan restaurant:true (x-restaurant-id).

Haz:
1. Escáner universal (4.1.4): en OwnerController.onCodeDetected reconoce BCD1. (pase), BCD-MESA-<id>, BCD-ORD-<id o número> y un UUID suelto (pedido). validateQrCode llama POST /v1/caja/validar con Idempotency-Key y envía el texto TAL CUAL (no uses BocadooQrParser en modo API); ya descuenta. confirmRedeem devuelve true sin llamar. undoRedeem llama POST /v1/caja/consumos/{consumoId}/deshacer (10 s). Mapea resultado→ScanResult con la tabla de 4.1.4. El simulador de tokens del escáner solo en modo mock.
2. O1 (8.1): getDailyClosingSummary con GET /v1/caja/cierre/hoy (+ resumen-diario solo para el dueño); getTodayTransactions con GET /v1/caja/ventas + GET /v1/caja/pedidos?estado=SERVIDA; getOrdersOnTheWayCount con GET /v1/caja/pedidos; setManualBusy con POST /v1/restaurante/lleno; getPendingTables devuelve [] (B-15) y oculta el banner con ApiCapabilities.ownerPendingTablesList (E3).
3. O3 (8.3): getClients (GET /v1/clientes paginado), getPlanTemplates (GET /v1/planes), addClient (POST /v1/clientes), sellPlanTemplate (POST /v1/clientes/{id}/planes con IK; efectivo, transferencia y Deuna; pagoConfirmado:true), undoTransaction (POST /v1/planes-vendidos/{id}/deshacer con IK o POST /v1/caja/ventas/{id}/deshacer según el tipo; guarda un mapa saleId→tipo). Oculta el método Tarjeta (E3/E6).
4. O4/O6 (8.6): getCatalog (GET /v1/menu/platos), registerPosSale (POST /v1/caja/ventas con IK; precios del servidor), undoTransaction para ventas.
5. O11 (8.11): publishOffer (POST /v1/ofertas con IK), getActiveOffer (GET /v1/ofertas?estado=VIGENTE&limit=1), cancelOffer (POST /v1/ofertas/{id}/cerrar). Oculta "Promo programada" (E3, B-20).
6. O13 (8.13): getDailyClosingSummary, isShiftClosed, closeShift (POST /v1/caja/cierre/hoy), reopenShift (POST …/reabrir). Sin comisión.
7. O12 (4.1.2 y 8.12): getActiveOrders (GET /v1/caja/pedidos, polling 8 s con Timer+invalidateSelf en activeOrdersProvider), validateOrder (canjear + guardar consumoId; si el resultado no es OK/OK_ADVERTENCIA devuelve false con el motivo), undoValidate, deliverOrder y undoDeliver con COMMIT DIFERIDO de 10 s (sección 10.2): en efectivo difiere canjear+servir juntos; con plan difiere solo servir; oculta los pendientes en getActiveOrders. Mapea PedidoCaja→OwnerOrder (9.10).
8. VERIFICACIÓN DE CAJA (4.1.2): canjea un pedido en efectivo de $3,50 y compara GET /v1/caja/cierre/hoy antes y después. Si efectivoEsperadoCentavos NO subió, registra el cobro con POST /v1/caja/ventas (ALMUERZO x1, EFECTIVO, mesaTexto "Pedido #N") y deja un // TODO(backend): B-26. Documenta el resultado en el resumen. NUNCA cobres dos veces.
9. C8 / aviso de entrega: el comensal ya hace polling (Fase 2). Confirma que, al servir el pedido en O12, la hoja "Tu pedido · Entregado" aparece en ≤5 s y que el texto distingue "Pagaste $X en efectivo" de "Se descontó 1 almuerzo de tu plan".
10. Rol del dispositivo: si la cuenta es CAJERO, ownerRoleProvider arranca en cashier y ApiCapabilities.canSwitchToOwner es false (5.10). Un cajero no llama a endpoints de Dueño (403): para él oculta o evita las llamadas de reportes y de reabrir caja.

Entrega el resumen de planes B usados (B-15, B-16, B-17, B-20, B-26).
```

**Criterios de aceptación:**
- Escanear un pase real descuenta 1 almuerzo y muestra "Le quedan N almuerzos"; "Deshacer" lo devuelve (dentro de 10 s).
- Escanear `BCD-MESA-<id>` abre O5; escanear el `qr` de un pedido abre O12 con la hoja correcta.
- Pedido con plan: "Validar QR" baja el saldo del comensal en 1 → "Validado" → "Entregar" → el comensal ve "Entregado" en ≤5 s.
- Pedido en efectivo: "Cobrar y entregar" → el efectivo esperado del cierre sube exactamente el monto, **una vez**.
- Vender un plan (efectivo, transferencia, Deuna) y deshacerlo dentro de 10 s.
- POS: registrar y deshacer una venta; los precios son los del servidor.
- Oferta flash: publicar y cerrar; aparece en la ficha del comensal.
- Cierre: contar efectivo, cerrar, reabrir (dueño). El cajero no ve "Cuadre caja".
- Resultados del escáner: probar al menos `OK`, `DUPLICADO`, `SIN_PLAN`, `QR_EXPIRADO` y `QR_INVALIDO`.

**Humo:** 12.2, "Fase 3". **Commit:** `feat(integracion): caja del dueño, escáner universal y pedidos (O1-O6, O11-O13, C8)`.

### 11.4 Fase 4 — Dueño de gestión (O7 a O10, O14, O16, P-01)

**Objetivo:** el dueño administra su menú, sus planes, sus clientes y ve sus números.

**Prerrequisito:** Fase 3 aprobada.

**Prompt:**

```text
FASE 4 — Dueño de gestión (O7, O8, O9, O10, O14, O16 y la bandeja P-01). Aplica el prompt maestro. Prerrequisito: Fases 1 a 3.

Completa ApiOwnerRepository:
1. O7 Menú (8.7): getTodayMenu (GET /v1/menu/hoy), publishMenu (PUT /v1/menu/hoy + POST /publicar; agrega DailyMenuCourse.dishId opcional; plato escrito a mano = primero POST /v1/menu/platos), unpublishMenu (POST /despublicar), getYesterdayMenu (GET /v1/menu/{ayer}), setCourseSoldOut (PATCH /v1/menu/hoy/items/{itemId}/agotado con el id del RENGLÓN, buscado por nombre en el último menú; plato por plato, sin despublicar), setStoreOpen (POST /v1/restaurante/activar|pausar). Catálogo: getDishes/addDish/setDishArchived (GET/POST/PATCH /v1/menu/platos) con el mapa de DishKind de 8.7.
2. O8 (8.8): getClients con búsqueda, addClient con Phone.toE164 (manejar 409 "Ya tienes un cliente con ese celular."). Si el formulario trae correo, intenta POST /v1/clientes/{id}/vincular en silencio e IGNORA si falla (P-13: así el comensal ve su plan en la app). getPlanClientCounts con vendidosActivos. setPlanActive con PATCH.
3. O9 (8.9): savePlanTemplate (POST o PATCH /v1/planes; diasValidos enteros — si el PATCH da 400 reintenta con cadenas y anótalo). Cobertura (almuerzo/desayuno/mixto) codificada en incluye (B-27). quota↔cupos, visible↔visibleEnMarketplace, active↔activo. Verifica los valores base: Semanal 5/$15/7d, Quincenal 10/$28/15d, Mensual 20/$55/30d, Libre 10/$32/60d.
4. O10 (8.10): registerPhysicalCard (crear cliente si es nuevo + POST /v1/clientes/{id}/migrar-cartulina; precioUnitario = precio del plan/almuerzos). undoPhysicalCard: prueba POST /v1/planes-vendidos/{id}/deshacer con el plan migrado; si el servidor lo rechaza, usa commit diferido (10.2). Solo rol Dueño.
5. O14 (8.14): getMetrics con los reportes de la tabla: resumen-diario, horas-pico, almuerzos-pendientes, ranking-platos, ventas-planes, clientes-a-contactar. El "valor aproximado del día" = servedToday x precio suelto (GET /v1/restaurante). Planes B de B-18 (ocultar "vencidos" con E3; sumar resumen-diario por día para ventas por método; hasta 7 llamadas de horas-pico para la cuadrícula) con caché de 60 s y llamadas en paralelo. setWeeklySummary local (B-19). No llames a reportes con una cuenta CAJERO.
6. O16 (8.16): getLocalInfo (GET /v1/restaurante; agrega LocalInfo.logoUrl opcional), setLogo (guarda ≤60 KB en el teléfono; B-28), rol del dispositivo, cerrar sesión.
7. P-01: bandeja de solicitudes de plan del comensal. Pide primero la aprobación de Carlos para el diseño; si ya está aprobado, implementa una tarjeta "N solicitudes de plan" en Caja que abre una hoja con GET /v1/solicitudes-plan y "Cobrar" (POST /v1/solicitudes-plan/{id}/cobrar con IK, método efectivo/transferencia/Deuna) y "Rechazar". Si NO está aprobado, deja la lógica del repositorio lista y NO toques la UI.

Cada acción invalida los providers que correspondan (planTemplatesProvider, ownerClientsProvider, planClientCountsProvider, catalogDishesProvider, posMenuProvider, metricsProvider, localInfoProvider). Entrega el resumen de planes B usados.
```

**Criterios de aceptación:**
- Publicar el menú del día; marcar un plato "Se acabó" y volver a "Hay" sin despublicar nada; el comensal lo ve agotado en ≤1 min.
- Crear y editar los 4 planes con los valores base; desactivar uno.
- Agregar un cliente desde `+` y venderle un plan desde la hoja; si se puso correo de una cuenta existente, el comensal ve ese plan en Mi Pase.
- Pasar una cartulina desde Ajustes y ver al cliente con su saldo.
- Tus números: las tres pestañas cargan con datos reales (con los planes B documentados); "Hoy" muestra "$X,XX aprox.".
- Ajustes: cambiar a cajero cambia la barra a Caja, Pedidos, Turno; subir un logo lo muestra.

**Humo:** 12.2, "Fase 4". **Commit:** `feat(integracion): gestión del dueño (O7-O10, O14, O16)`.

### 11.5 Fase 5 — Mesas, opiniones, sincronización y cierre (C7, C9, C10, O5, O15)

**Objetivo:** los flujos compartidos que quedaban, el retiro del almacén de demostración en modo API y el endurecimiento final.

**Prerrequisito:** Fase 4 aprobada.

**Prompt:**

```text
FASE 5 — Mesas, opiniones, sincronización y cierre (C7, C9, C10, O5, O15). Aplica el prompt maestro. Prerrequisito: Fases 1 a 4.

1. Mesas del comensal (4.1.3, 7.6 y 7.8): openSharedTable (GET /v1/mis/mesas y reutiliza una ABIERTA; si no, POST /v1/mis/mesas con IK; horaLlegada con EcuadorTime.todayAtUtc; la hora debe estar entre ahora y 12 h: si ya pasó, usa la siguiente), getSharedTable (invitación: GET /v1/mesas/invitacion/{id}; propia: GET /v1/mis/mesas/{id}), joinTable (POST /v1/mesas/invitacion/{id}/unirse con IK; solo paraLlevar), setTableMode con el plan B de B-12a, notifyKitchen oculto (B-12b), elección de platos no se envía (B-12c). SharedTable según 9.7: qrPayload "BCD-MESA-<id>", shareUrl "bocadoo://mesa/<invitacion>". Polling de 8 s en C9.
2. Enlace profundo (4.7): intent-filter bocadoo://mesa en AndroidManifest.xml, redirect en app_router.dart a /customer/mesa/<id>, invitación pendiente si no hay sesión. Comparte el texto con el enlace Y el código.
3. O5 del dueño (4.1.3 y 8.5): previewTable (GET /v1/caja/mesas/{id} + GET /v1/restaurante para precios; construir TablePreview), setTableMode solo lectura (E3), chargeTable (POST /v1/caja/mesas/{id}/validar con IK y, si porCobrar>0, POST /v1/caja/ventas ALMUERZO x porCobrar en EFECTIVO con mesaTexto "Mesa <id>" — misma verificación de caja de la Fase 3), undoTableCharge (consumos/{id}/deshacer + ventas/{id}/deshacer, 10 s).
4. C10 (7.9): conecta feedback_card con GET /v1/mis/opiniones/pendientes, POST …/opinion (etiquetas RICO, RAPIDO, BUENA_PORCION; comentario opcional) y …/descartar. Traduce OPINION_AUN_NO_DISPONIBLE, OPINION_VENCIDA, OPINION_YA_ENVIADA y CONSUMO_REVERTIDO cerrando la tarjeta. La regla de 25 min a 24 h la aplica el servidor.
5. O15 (8.15): getOpinions (GET /v1/opiniones paginado), replyOpinion thanks (POST /v1/opiniones/{id}/responder), replyOpinion replaceLunch (responder + plan de cortesía con migrar-cartulina, B-21; TODO en commit diferido), undoReply con commit diferido, resolución del cliente por nombre (B-22). Etiquetas en español (8.15).
6. Sincronización final: revisa los 4 eventos de la sección 4.1 uno por uno con dos emuladores o con el emulador y curl. Verifica que ninguna pantalla en modo API lee core/demo/demo_store.dart.
7. Retiro del DemoStore en modo API: los repositorios Api no lo importan. DemoStore y los mocks quedan SOLO detrás de AppMode.useMock. Borra de modo API el simulador de tokens del escáner.
8. Analítica opcional (P-11): si Carlos la aprueba, un EventsService que agrupe eventos (hasta 50 por lote) y los envíe con POST /v1/eventos (Idempotency-Key, sesionId UUID por sesión, plataforma ANDROID, versionApp). Sin aprobación, no lo hagas.
9. Endurecimiento: build release con --obfuscate y --split-debug-info; revisa que no haya logs con tokens ni datos personales; revisa manejo de 401/403/409/429 en cada repositorio; revisa que el polling se detiene al salir de pantalla y en segundo plano; prueba sin conexión y con el servidor dormido.
10. Limpieza: elimina el // TODO de lo que ya se conectó y deja un // TODO(backend): B-xx en cada plan B. Actualiza docs/api/ con una nota de las brechas abiertas.

Entrega el resumen final: pantallas conectadas, planes B vigentes (con sus ID), pendientes para Chucho y para Carlos.
```

**Criterios de aceptación:**
- Un comensal crea una mesa, otro entra por el enlace `bocadoo://mesa/<id>`, y en Caja se escanea `BCD-MESA-<id>`: O5 muestra a ambos con su vía de pago; "Cobrar" descuenta los planes y registra el efectivo de quien paga suelto; la mesa queda `FINALIZADA` (el comensal lo ve en ≤8 s).
- Modo "Yo invito la mesa": todos con el plan del anfitrión; si no le alcanza, se avisa.
- Tras validar un almuerzo, en ≥25 min aparece "¿Qué tal hoy?"; enviar "Rico" y ver la opinión en O15 con su nota si la hay.
- Responder una opinión (Agradecer) y que el comensal la vea (`GET /v1/mis/opiniones`). "Reponer almuerzo" suma 1 al saldo del comensal.
- Ningún repositorio de modo API toca `DemoStore`.
- Pasan los 4 eventos de la sección 4.1 y la prueba de extremo a extremo de 12.3.

**Humo:** 12.2, "Fase 5" y 12.3. **Commit:** `feat(integracion): mesas, opiniones y cierre de la integración (C7, C9, C10, O5, O15)`.

---

## 12. Pruebas de humo contra Render

### 12.1 Preparación (una vez)

Variables y cuentas de prueba, con `curl` (cambia los correos; la contraseña mínima es de 10 caracteres). **Usa cuentas de prueba, nunca datos reales.**

```bash
BASE=https://bck-bocadoo.onrender.com
# 0) Despertar el servidor (la primera vez puede tardar de 30 a 60 s)
curl -s -m 90 -w "\nHTTP %{http_code} en %{time_total}s\n" $BASE/health

# 1) Dueño de prueba (nace en BORRADOR)
curl -s -X POST $BASE/v1/auth/register-owner -H 'Content-Type: application/json' -d '{
  "nombre":"Dueño Prueba","correo":"dueno.prueba@correo.com","password":"clave-segura-123",
  "aceptaTerminos":true,"restaurante":{"nombre":"Local de Prueba","ciudadId":1}}'
OWNER=$(curl -s -X POST $BASE/v1/auth/login -H 'Content-Type: application/json' \
  -d '{"identificador":"dueno.prueba@correo.com","password":"clave-segura-123"}' | jq -r .accessToken)
RID=$(curl -s $BASE/v1/auth/me -H "Authorization: Bearer $OWNER" | jq -r '.restaurantes[0].id')

# 2) Dejar el local listo y activo
H=(-H "Authorization: Bearer $OWNER" -H "x-restaurant-id: $RID" -H 'Content-Type: application/json')
curl -s -X PATCH $BASE/v1/restaurante "${H[@]}" -d '{"precioSueltoCentavos":350,"recargoParaLlevarCentavos":25,"puestos":24,"zonaId":1,"latitud":-0.2105,"longitud":-78.502}'
curl -s -X PUT $BASE/v1/restaurante/horarios "${H[@]}" -d '{"horarios":[{"diaSemana":1,"abre":"00:00","cierra":"23:59"},{"diaSemana":2,"abre":"00:00","cierra":"23:59"},{"diaSemana":3,"abre":"00:00","cierra":"23:59"},{"diaSemana":4,"abre":"00:00","cierra":"23:59"},{"diaSemana":5,"abre":"00:00","cierra":"23:59"},{"diaSemana":6,"abre":"00:00","cierra":"23:59"},{"diaSemana":7,"abre":"00:00","cierra":"23:59"}]}'
curl -s -X POST $BASE/v1/restaurante/activar "${H[@]}"

# 3) Platos, menú de hoy y plan
SOPA=$(curl -s -X POST $BASE/v1/menu/platos "${H[@]}" -d '{"categoria":"ALMUERZO","seccion":"SOPA","nombre":"Locro de papa"}' | jq -r .id)
FUERTE=$(curl -s -X POST $BASE/v1/menu/platos "${H[@]}" -d '{"categoria":"ALMUERZO","seccion":"FUERTE","nombre":"Seco de pollo"}' | jq -r .id)
curl -s -X PUT $BASE/v1/menu/hoy "${H[@]}" -d "{\"items\":[{\"platoId\":\"$SOPA\",\"seccion\":\"SOPA\",\"orden\":1},{\"platoId\":\"$FUERTE\",\"seccion\":\"FUERTE\",\"orden\":2}]}"
curl -s -X POST $BASE/v1/menu/hoy/publicar "${H[@]}"
PLAN=$(curl -s -X POST $BASE/v1/planes "${H[@]}" -d '{"tipo":"SEMANAL","nombre":"Plan semanal","almuerzos":5,"precioCentavos":1500,"vigenciaDias":7,"diasValidos":[1,2,3,4,5,6,7],"incluye":["Sopa","Segundo"],"visibleEnMarketplace":true}' | jq -r .id)

# 4) Comensal de prueba, cliente en el local, vínculo y venta de un plan
curl -s -X POST $BASE/v1/auth/register -H 'Content-Type: application/json' -d '{"nombre":"Comensal Prueba","correo":"comensal.prueba@correo.com","password":"clave-segura-123","aceptaTerminos":true}'
CLI=$(curl -s -X POST $BASE/v1/clientes "${H[@]}" -d '{"nombre":"Comensal Prueba","telefono":"+593990000111"}' | jq -r .id)
curl -s -X POST $BASE/v1/clientes/$CLI/vincular "${H[@]}" -d '{"correo":"comensal.prueba@correo.com"}'
curl -s -X POST $BASE/v1/clientes/$CLI/planes "${H[@]}" -H "Idempotency-Key: $(uuidgen)" -d "{\"planId\":\"$PLAN\",\"metodoPago\":\"EFECTIVO\"}"

# 5) El comensal debe ver su plan
DINER=$(curl -s -X POST $BASE/v1/auth/login -H 'Content-Type: application/json' -d '{"identificador":"comensal.prueba@correo.com","password":"clave-segura-123"}' | jq -r .accessToken)
curl -s $BASE/v1/pase -H "Authorization: Bearer $DINER" | jq .
```

> Si `uuidgen` o `jq` no están instalados, usa cualquier UUID v4 y lee el JSON a ojo. El horario de 24 h en los 7 días es solo para pruebas (para que `abiertoAhora` sea `true` a cualquier hora).

Ejecutar la app contra Render (emulador Pixel 8):

```bash
flutter run --dart-define=BOCADOO_SUPPORT_WHATSAPP=593999999999    # modo API (por defecto)
flutter run --dart-define=BOCADOO_USE_MOCK=true                    # modo mock (demo sin internet)
```

### 12.2 Lista de verificación por fase (en el emulador, contra Render)

**Fase 1**
- [ ] Primera petición del día: se mide el tiempo; con el servidor dormido aparece "Despertando el servidor…" y la app no se cae.
- [ ] Registrar un comensal nuevo → entra a Mi Pase.
- [ ] Registrar un dueño nuevo → onboarding → Caja.
- [ ] Cerrar y abrir la app → la sesión continúa.
- [ ] Esperar 16 min (o borrar el access token del almacén) → una petición protegida se refresca sola. En el log del servidor (o con `LogInterceptor`) se ve **un solo** `POST /v1/auth/refresh` aunque haya varias peticiones a la vez.
- [ ] Contraseña de 9 caracteres: la app avisa antes de enviar.
- [ ] Correo repetido: mensaje claro.
- [ ] Avión (sin red): mensaje de conexión; al volver, "Reintentar" funciona.
- [ ] "Continuar con Google": aviso de la sección 10.3.
- [ ] `--dart-define=BOCADOO_USE_MOCK=true`: todo como antes.

**Fase 2**
- [ ] Mi Pase: plan real y QR que cambia cada 30 s. Leerlo con la caja (Fase 3) o con `curl POST /v1/caja/validar`.
- [ ] Dónde comer: aparecen los locales reales (incluidos los de prueba públicos); filtros sin errores.
- [ ] Ficha: menú publicado de hoy, horarios, ocupación y planes.
- [ ] Pedir: crea pedido; C8 muestra `Pedido #N`, 30 min y QR; Deshacer lo cancela; pedir dos veces → mensaje de "pedido en camino".
- [ ] Solicitar plan: `GET /v1/solicitudes-plan` (dueño) lo muestra.
- [ ] Mapa: locales con coordenadas se dibujan; los que no, no rompen nada.

**Fase 3**
- [ ] Escanear el QR del pase: descuento y "Le quedan N almuerzos"; Deshacer dentro de 10 s; a los 11 s, mensaje de plazo vencido.
- [ ] Mismo QR dos veces seguidas: `DUPLICADO` ("Ya validado").
- [ ] QR vencido (esperar 2 min): `QR_EXPIRADO`.
- [ ] Texto inventado: `QR_INVALIDO`.
- [ ] Pedido con plan: Validar QR → saldo −1 → Validado → Entregar → el comensal ve "Entregado" en ≤5 s.
- [ ] Pedido en efectivo: Cobrar y entregar → efectivo esperado sube una sola vez (verificación de caja).
- [ ] Vender plan en efectivo, transferencia y Deuna; deshacer.
- [ ] POS: vender un almuerzo y un plato; total del servidor; deshacer.
- [ ] Oferta flash publicada y cerrada.
- [ ] Cierre: contar, cerrar, intentar cerrar otra vez (`409`), reabrir.
- [ ] Cuenta cajero: barra Caja, Pedidos, Turno; sin "Cuadre caja".

**Fase 4**
- [ ] Menú: publicar; "Se acabó" de un plato sin despublicar; el comensal lo ve agotado.
- [ ] Catálogo: crear, archivar.
- [ ] Planes: los 4 con sus valores base; desactivar uno.
- [ ] Clientes: `+` Agregar cliente; con celular repetido → mensaje; "Guardar y vender plan".
- [ ] Cartulina desde Ajustes: el cliente queda con su saldo; deshacer.
- [ ] Tus números: tres pestañas; "$X,XX aprox." en Hoy; "Dinero" y "Clientes" sin errores.
- [ ] Ajustes: rol cajero cambia la barra; logo; abrir/cerrar local.

**Fase 5**
- [ ] Mesa: crear, unirse por enlace, ver miembros en ≤8 s.
- [ ] O5: escanear `BCD-MESA-<id>`, cobrar, ver `FINALIZADA` en el comensal.
- [ ] Opinión: validar un almuerzo, esperar 25 min (o usar un consumo antiguo), enviar "Rico", verlo en O15.
- [ ] Responder y que el comensal lo vea.
- [ ] Release: `flutter build apk --release --obfuscate --split-debug-info=build/symbols` compila.

### 12.3 Prueba de extremo a extremo (cierre de la Fase 5)

Dos emuladores (o un emulador y `curl` para el otro rol):

1. **Dueño:** registra el local, lo activa, publica el menú y crea un plan (Fase 4).
2. **Dueño:** agrega al comensal como cliente con su correo y le vende el plan (queda vinculado).
3. **Comensal:** ve su plan y el QR en Mi Pase.
4. **Comensal:** pide almuerzo (cubierto por plan). **Dueño:** lo ve en O12 en <10 s.
5. **Dueño:** Validar QR → el saldo del comensal baja 1. **Dueño:** Entregar → **comensal** ve "Tu pedido · Entregado".
6. **Comensal:** crea una mesa y comparte el enlace; un segundo comensal se une.
7. **Dueño:** escanea el QR de la mesa → O5 → Cobrar. Ambos comensales ven la mesa `FINALIZADA`.
8. **Dueño:** escanea el pase de un comensal → descuento.
9. **Comensal:** tras 25 min, "¿Qué tal hoy?" → "Rico". **Dueño:** lo ve en O15 y responde.
10. **Dueño:** cierra caja. El efectivo esperado coincide con lo cobrado en efectivo (sin duplicados).

### 12.4 Cosas que revisar siempre

- `flutter analyze`: **0 problemas**.
- `flutter build apk --debug`: correcto.
- Ningún texto visible con la palabra "canje", ningún emoji en titulares, ninguna fuente fuera de Outfit.
- Ningún token en el log (`adb logcat | findstr /i bearer` no debe mostrar nada).
- El polling se detiene al salir de la pantalla (observar las peticiones con `LogInterceptor` en depuración).

---

## 13. Textos de error para la app

Se decide **por `code`** (sección 2.3). Sin la palabra "canje". Tuteo. Pegar en `ErrorMessages`:

```dart
class ErrorMessages {
  static String of(ApiException e) {
    if (e.isNetwork) return 'No tienes conexión. Revisa tu internet e inténtalo de nuevo.';
    return _byCode[e.code] ?? _byStatus(e.status);
  }

  static String _byStatus(int? s) => switch (s) {
        400 => 'Revisa los datos e inténtalo de nuevo.',
        401 => 'Tu sesión venció. Entra de nuevo.',
        403 => 'No tienes permiso para hacer esto.',
        404 => 'No encontramos lo que buscabas.',
        409 => 'Esto cambió mientras lo hacías. Actualizamos los datos.',
        422 => 'No pudimos completar esto. Revisa los datos.',
        429 => 'Demasiados intentos. Espera un momento.',
        502 || 503 || 504 => 'No pudimos conectar con el servidor. Inténtalo en un momento.',
        _ => 'Algo salió mal de nuestro lado. Inténtalo en un momento.',
      };

  static const _byCode = <String, String>{
    // Sesión y registro
    'UNAUTHORIZED': 'Tu sesión venció. Entra de nuevo.',
    'FORBIDDEN': 'No tienes permiso para hacer esto.',
    'CONFLICT': 'Ya existe un registro con esos datos.',
    'TOO_MANY_REQUESTS': 'Demasiados intentos. Espera un momento.',
    'ERROR_INTERNO': 'Algo salió mal de nuestro lado. Inténtalo en un momento.',
    'SERVICE_UNAVAILABLE': 'El servidor está despertando. Inténtalo en un momento.',
    'SIN_CONEXION': 'No tienes conexión. Revisa tu internet e inténtalo de nuevo.',
    'SIN_RESTAURANTE': 'Esta cuenta no tiene un restaurante.',
    // Genéricos de datos
    'CURSOR_INVALIDO': 'No pudimos cargar más resultados. Actualiza la lista.',
    'FECHA_INVALIDA': 'La fecha no es válida.',
    'RANGO_INVALIDO': 'El rango de fechas no es válido.',
    'RANGO_MUY_LARGO': 'Elige un rango de fechas más corto.',
    'IDEMPOTENCY_KEY_INVALIDA': 'No pudimos enviar esto. Inténtalo de nuevo.',
    'IDEMPOTENCY_KEY_REUTILIZADA': 'Esta acción ya se envió. Actualiza para ver el resultado.',
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
    'HORA_LLEGADA_INVALIDA': 'Elige una hora de llegada de ahora a las próximas 12 horas.',
    'MESA_NO_ENCONTRADA': 'No encontramos esa mesa.',
    'MESA_CERRADA': 'Esta mesa ya cerró.',
    'MESA_VENCIDA': 'Esta mesa ya venció.',
    'MESA_LLENA': 'Esta mesa está llena.',
    'SOLO_ANFITRION': 'Solo el anfitrión puede hacer esto.',
    // Opiniones
    'OPINION_VACIA': 'Elige una etiqueta o escribe una nota.',
    'OPINION_AUN_NO_DISPONIBLE': 'Podrás calificar este almuerzo en unos minutos.',
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
    'OFERTA_PRECIO_INVALIDO': 'El precio de la oferta debe ser menor al precio normal.',
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
```

Mensajes que se arman en el repositorio (no vienen de un `code`):

| Situación | Texto |
|---|---|
| Credenciales incorrectas en el login | "Correo o contraseña incorrectos." |
| Correo ya registrado | "Ya existe una cuenta con ese correo. Entra o recupera tu contraseña." |
| Teléfono de cliente repetido | "Ya tienes un cliente con ese celular." |
| Cuenta sin restaurante en la pestaña Dueño | "Esta cuenta no tiene un restaurante. Regístrate como dueño o entra como comensal." |
| `LIMITE_SAAS` | "Llegaste al límite de validaciones de tu plan Bocadoo." |
| Deshacer fuera de plazo (`409` en `consumos/{id}/deshacer`) | "Ya pasó el tiempo para deshacer." |
| Hubo cobros después del cierre | "Hubo cobros después del cierre. Reabre y vuelve a contar." |
| Plan vendido que no se puede deshacer | "Este plan ya tiene almuerzos consumidos, no se puede deshacer." |

---

---

## Apéndice A. Índice completo de endpoints (97 rutas, generado de `docs/api/openapi.json`)

Rol: **Público** no lleva token. **Sesión** lleva `Authorization: Bearer`. **Caja** y **Dueño** llevan además `x-restaurant-id`. `IK` = exige `Idempotency-Key`.

| # | Método | Ruta | Rol | IK | Body | Respuesta 2xx | Parámetros |
|---|---|---|---|---|---|---|---|
| 1 | GET | `/health` | Público |  | — | 200 HealthResponse |  |
| 2 | GET | `/health/ready` | Público |  | — | 200 ReadyResponse |  |
| 3 | POST | `/v1/auth/register` | Público |  | RegisterDto | 201 RegisterResponseDto |  |
| 4 | POST | `/v1/auth/register-owner` | Público |  | RegisterOwnerDto | 201 RegisterResponseDto |  |
| 5 | POST | `/v1/auth/login` | Público |  | LoginDto | 200 TokenResponseDto |  |
| 6 | POST | `/v1/auth/refresh` | Público |  | RefreshDto | 200 TokenResponseDto |  |
| 7 | POST | `/v1/auth/logout` | Público |  | RefreshDto | 204 sin cuerpo |  |
| 8 | POST | `/v1/auth/logout-all` | Sesión (cualquier usuario) |  | — | 204 sin cuerpo |  |
| 9 | GET | `/v1/auth/me` | Sesión (cualquier usuario) |  | — | 200 MeResponseDto |  |
| 10 | GET | `/v1/restaurante` | Caja (cajero o dueño) |  | — | 200 RestauranteResponse |  |
| 11 | PATCH | `/v1/restaurante` | Dueño |  | UpdateRestauranteDto | 200 RestauranteResponse |  |
| 12 | POST | `/v1/restaurante/activar` | Dueño |  | — | 200 RestauranteResponse |  |
| 13 | POST | `/v1/restaurante/pausar` | Dueño |  | — | 200 RestauranteResponse |  |
| 14 | GET | `/v1/restaurante/horarios` | Caja (cajero o dueño) |  | — | 200 [HorarioResponse] |  |
| 15 | PUT | `/v1/restaurante/horarios` | Dueño |  | ReemplazarHorariosDto | 200 [HorarioResponse] |  |
| 16 | GET | `/v1/restaurante/mesas` | Caja (cajero o dueño) |  | — | 200 [MesaResponse] |  |
| 17 | POST | `/v1/restaurante/mesas` | Dueño |  | CrearMesaDto | 201 MesaResponse |  |
| 18 | PATCH | `/v1/restaurante/mesas/{id}` | Dueño |  | ActualizarMesaDto | 200 MesaResponse | `id`* |
| 19 | POST | `/v1/restaurante/lleno` | Caja (cajero o dueño) |  | LlenoDto | 200 LlenoResponse |  |
| 20 | GET | `/v1/restaurante/personal` | Dueño |  | — | 200 [PersonalResponse] |  |
| 21 | POST | `/v1/restaurante/personal/cajeros` | Dueño |  | InviteCashierDto | 201 PersonalResponse |  |
| 22 | PATCH | `/v1/restaurante/personal/{usuarioId}` | Dueño |  | SetActiveDto | 200 PersonalResponse | `usuarioId`* |
| 23 | GET | `/v1/menu/platos` | Caja (cajero o dueño) |  | — | 200 [PlatoResponse] | `categoria`, `soloActivos` |
| 24 | POST | `/v1/menu/platos` | Dueño |  | CrearPlatoDto | 201 PlatoResponse |  |
| 25 | PATCH | `/v1/menu/platos/{id}` | Dueño |  | ActualizarPlatoDto | 200 PlatoResponse | `id`* |
| 26 | GET | `/v1/menu/{fecha}` | Caja (cajero o dueño) |  | — | 200 MenuDiaResponse | `fecha`* |
| 27 | PUT | `/v1/menu/{fecha}` | Dueño |  | DefinirMenuDto | 200 MenuDiaResponse | `fecha`* |
| 28 | POST | `/v1/menu/{fecha}/publicar` | Dueño |  | — | 200 MenuDiaResponse | `fecha`* |
| 29 | POST | `/v1/menu/{fecha}/despublicar` | Dueño |  | — | 200 MenuDiaResponse | `fecha`* |
| 30 | POST | `/v1/menu/{fecha}/copiar` | Dueño |  | CopiarMenuDto | 200 MenuDiaResponse | `fecha`* |
| 31 | PATCH | `/v1/menu/{fecha}/items/{id}/agotado` | Caja (cajero o dueño) |  | AgotadoDto | 200 MenuDiaResponse | `fecha`*, `id`* |
| 32 | GET | `/v1/restaurantes` | Público |  | — | 200 RestauranteBusquedaResponse | `q`, `zonaId`, `ciudadId`, `etiqueta`, `limit`, `cursor` |
| 33 | GET | `/v1/restaurantes/{slug}` | Público |  | — | 200 RestauranteDetalleResponse | `slug`* |
| 34 | GET | `/v1/planes` | Caja (cajero o dueño) |  | — | 200 [PlantillaPlanResponse] |  |
| 35 | POST | `/v1/planes` | Dueño |  | CrearPlanDto | 201 PlantillaPlanResponse |  |
| 36 | PATCH | `/v1/planes/{id}` | Dueño |  | ActualizarPlanDto | 200 PlantillaPlanResponse | `id`* |
| 37 | GET | `/v1/clientes` | Caja (cajero o dueño) |  | — | 200 ClientePageResponse | `q`, `limit`, `cursor` |
| 38 | POST | `/v1/clientes` | Caja (cajero o dueño) |  | CrearClienteDto | 201 ClienteDetalleResponse |  |
| 39 | GET | `/v1/clientes/{id}` | Caja (cajero o dueño) |  | — | 200 ClienteDetalleResponse | `id`* |
| 40 | PATCH | `/v1/clientes/{id}` | Caja (cajero o dueño) |  | ActualizarClienteDto | 200 ClienteDetalleResponse | `id`* |
| 41 | POST | `/v1/clientes/{id}/migrar-cartulina` | Dueño |  | MigrarCartulinaDto | 201 ClienteDetalleResponse | `id`* |
| 42 | POST | `/v1/clientes/{id}/vincular` | Caja (cajero o dueño) |  | VincularDto | 200 ClienteDetalleResponse | `id`* |
| 43 | POST | `/v1/clientes/{id}/desvincular` | Caja (cajero o dueño) |  | — | 200 ClienteDetalleResponse | `id`* |
| 44 | POST | `/v1/clientes/{id}/planes` | Caja (cajero o dueño) | sí | VenderPlanDto | 201 PlanVendidoResponse | `id`* |
| 45 | POST | `/v1/planes-vendidos/{id}/deshacer` | Caja (cajero o dueño) | sí | DeshacerDto | 200 PlanVendidoResponse | `id`* |
| 46 | GET | `/v1/pagos/pendientes` | Dueño |  | — | 200 [PlanVendidoResponse] |  |
| 47 | POST | `/v1/pagos/{id}/confirmar` | Dueño |  | — | 200 PlanVendidoResponse | `id`* |
| 48 | POST | `/v1/pagos/{id}/rechazar` | Dueño |  | — | 200 PlanVendidoResponse | `id`* |
| 49 | GET | `/v1/solicitudes-plan` | Caja (cajero o dueño) |  | — | 200 [SolicitudPendienteResponse] |  |
| 50 | POST | `/v1/solicitudes-plan/{id}/cobrar` | Caja (cajero o dueño) | sí | CobroDto | 200 PlanVendidoResponse | `id`* |
| 51 | POST | `/v1/solicitudes-plan/{id}/rechazar` | Caja (cajero o dueño) |  | — | 200 SolicitudRechazadaResponse | `id`* |
| 52 | POST | `/v1/restaurantes/{slug}/solicitudes-plan` | Sesión (cualquier usuario) |  | SolicitarPlanDto | 201 SolicitudPlanCreadaResponse | `slug`* |
| 53 | GET | `/v1/pase/codigo` | Sesión (cualquier usuario) |  | — | 200 CodigoPaseResponse | `restaurante` |
| 54 | POST | `/v1/pase/rotar` | Sesión (cualquier usuario) |  | — | 204 sin cuerpo |  |
| 55 | POST | `/v1/caja/validar` | Caja (cajero o dueño) | sí | ValidarDto | 200 ValidacionResponse |  |
| 56 | POST | `/v1/caja/consumos/{id}/deshacer` | Caja (cajero o dueño) |  | — | 200 ConsumoRevertidoResponse | `id`* |
| 57 | GET | `/v1/caja/mesas/{id}` | Caja (cajero o dueño) |  | — | 200 MesaVistaResponse | `id`* |
| 58 | POST | `/v1/caja/mesas/{id}/validar` | Caja (cajero o dueño) | sí | — | 200 MesaValidadaResponse | `id`* |
| 59 | GET | `/v1/caja/ventas` | Caja (cajero o dueño) |  | — | 200 [VentaResponse] |  |
| 60 | POST | `/v1/caja/ventas` | Caja (cajero o dueño) | sí | VentaDto | 201 VentaResponse |  |
| 61 | POST | `/v1/caja/ventas/{id}/deshacer` | Caja (cajero o dueño) | sí | — | 200 VentaResponse | `id`* |
| 62 | GET | `/v1/caja/cierre/{fecha}` | Caja (cajero o dueño) |  | — | 200 CierreCajaResponse | `fecha`* |
| 63 | POST | `/v1/caja/cierre/{fecha}` | Caja (cajero o dueño) |  | CerrarCajaDto | 201 CierreCajaResponse | `fecha`* |
| 64 | POST | `/v1/caja/cierre/{fecha}/reabrir` | Dueño |  | — | 200 CierreCajaResponse | `fecha`* |
| 65 | GET | `/v1/reclamos` | Caja (cajero o dueño) |  | — | 200 [ReclamoPersonalResponse] | `estado` |
| 66 | POST | `/v1/reclamos/{id}/devolver` | Dueño |  | DevolverDto | 200 ReclamoPersonalResponse | `id`* |
| 67 | POST | `/v1/reclamos/{id}/rechazar` | Dueño |  | RechazarDto | 200 ReclamoPersonalResponse | `id`* |
| 68 | GET | `/v1/pase` | Sesión (cualquier usuario) |  | — | 200 PaseResponse | `restaurante` |
| 69 | GET | `/v1/mis/consumos` | Sesión (cualquier usuario) |  | — | 200 HistorialResponse | `limit`, `cursor`, `restaurante` |
| 70 | GET | `/v1/mis/consumos/{id}` | Sesión (cualquier usuario) |  | — | 200 ConsumoItem | `id`* |
| 71 | GET | `/v1/mis/reclamos` | Sesión (cualquier usuario) |  | — | 200 [ReclamoResponse] |  |
| 72 | POST | `/v1/mis/consumos/{id}/reclamo` | Sesión (cualquier usuario) | sí | ReclamarDto | 201 ReclamoResponse | `id`* |
| 73 | POST | `/v1/mis/pedidos` | Sesión (cualquier usuario) | sí | CrearPedidoDto | 201 PedidoResponse |  |
| 74 | GET | `/v1/mis/pedidos` | Sesión (cualquier usuario) |  | — | 200 PedidosResponse | `limit`, `cursor` |
| 75 | GET | `/v1/mis/pedidos/{id}` | Sesión (cualquier usuario) |  | — | 200 PedidoResponse | `id`* |
| 76 | POST | `/v1/mis/pedidos/{id}/cancelar` | Sesión (cualquier usuario) |  | — | 200 PedidoResponse | `id`* |
| 77 | GET | `/v1/caja/pedidos` | Caja (cajero o dueño) |  | — | 200 [PedidoCaja] | `estado` |
| 78 | GET | `/v1/caja/pedidos/{id}` | Caja (cajero o dueño) |  | — | 200 PedidoCaja | `id`* |
| 79 | POST | `/v1/caja/pedidos/{id}/canjear` | Caja (cajero o dueño) | sí | — | 200 PedidoCanjeResponse | `id`* |
| 80 | POST | `/v1/caja/pedidos/{id}/servir` | Caja (cajero o dueño) |  | — | 200 PedidoCaja | `id`* |
| 81 | POST | `/v1/mis/mesas` | Sesión (cualquier usuario) | sí | CrearMesaCompartidaDto | 201 MesaResponse |  |
| 82 | GET | `/v1/mis/mesas` | Sesión (cualquier usuario) |  | — | 200 [MesaResponse] |  |
| 83 | GET | `/v1/mis/mesas/{id}` | Sesión (cualquier usuario) |  | — | 200 MesaResponse | `id`* |
| 84 | POST | `/v1/mis/mesas/{id}/cancelar` | Sesión (cualquier usuario) |  | — | 200 MesaResponse | `id`* |
| 85 | GET | `/v1/mesas/invitacion/{id}` | Sesión (cualquier usuario) |  | — | 200 InvitacionResponse | `id`* |
| 86 | POST | `/v1/mesas/invitacion/{id}/unirse` | Sesión (cualquier usuario) | sí | UnirseDto | 200 MesaResponse | `id`* |
| 87 | GET | `/v1/mis/opiniones/pendientes` | Sesión (cualquier usuario) |  | — | 200 [PendienteResponse] |  |
| 88 | GET | `/v1/mis/opiniones` | Sesión (cualquier usuario) |  | — | 200 [OpinionResponse] |  |
| 89 | POST | `/v1/mis/consumos/{id}/opinion` | Sesión (cualquier usuario) | sí | OpinarDto | 201 OpinionResponse | `id`* |
| 90 | POST | `/v1/mis/consumos/{id}/opinion/descartar` | Sesión (cualquier usuario) | sí | — | 200 OpinionResponse | `id`* |
| 91 | GET | `/v1/opiniones` | Dueño |  | — | 200 BandejaResponse | `limit`, `cursor`, `estado` |
| 92 | POST | `/v1/opiniones/{id}/responder` | Dueño |  | ResponderDto | 200 OpinionBandeja | `id`* |
| 93 | GET | `/v1/mis/sellos` | Sesión (cualquier usuario) |  | — | 200 [MiTarjeta] |  |
| 94 | GET | `/v1/sellos/config` | Caja (cajero o dueño) |  | — | 200 ConfigResponse |  |
| 95 | PUT | `/v1/sellos/config` | Dueño |  | ConfigDto | 200 ConfigResponse |  |
| 96 | GET | `/v1/clientes/{id}/sellos` | Caja (cajero o dueño) |  | — | 200 TarjetaResponse | `id`* |
| 97 | POST | `/v1/clientes/{id}/sellos/canjear` | Caja (cajero o dueño) | sí | — | 200 TarjetaResponse | `id`* |
| 98 | POST | `/v1/ofertas` | Dueño | sí | PublicarOfertaDto | 201 OfertaResponse |  |
| 99 | GET | `/v1/ofertas` | Caja (cajero o dueño) |  | — | 200 OfertasPage | `limit`, `cursor`, `estado` |
| 100 | POST | `/v1/ofertas/{id}/cerrar` | Dueño |  | — | 200 OfertaResponse | `id`* |
| 101 | POST | `/v1/ofertas/{id}/canjear` | Caja (cajero o dueño) | sí | CanjearOfertaDto | 201 OfertaCanjeResponse | `id`* |
| 102 | GET | `/v1/restaurantes/{slug}/ofertas` | Público |  | — | 200 OfertasPublicas | `slug`* |
| 103 | GET | `/v1/reportes/resumen-diario` | Dueño |  | — | 200 ResumenDiarioResponse | `fecha` |
| 104 | GET | `/v1/reportes/ventas-planes` | Dueño |  | — | 200 VentasPlanesResponse | `desde`, `hasta` |
| 105 | GET | `/v1/reportes/horas-pico` | Dueño |  | — | 200 HorasPicoResponse | `desde`, `hasta` |
| 106 | GET | `/v1/reportes/ranking-platos` | Dueño |  | — | 200 RankingResponse | `desde`, `hasta`, `limit` |
| 107 | GET | `/v1/reportes/almuerzos-pendientes` | Dueño |  | — | 200 PendientesResponse |  |
| 108 | GET | `/v1/reportes/clientes-a-contactar` | Dueño |  | — | 200 SeguimientoResponse | `limit`, `diasVencer`, `diasSinVenir`, `diasRenovar` |
| 109 | GET | `/v1/suscripcion` | Dueño |  | — | 200 SuscripcionResponse |  |
| 110 | GET | `/v1/suscripcion/uso` | Caja (cajero o dueño) |  | — | 200 UsoResponse |  |
| 111 | POST | `/v1/eventos` | Sesión (cualquier usuario) | sí | LoteEventosDto | 201 LoteResponse |  |

---

## Apéndice B. Esquemas del backend (147), campo por campo

Notación: `campo*` = obligatorio. `null` = admite nulo. `[T]` = lista. Los comentarios son los del Swagger. Los objetos que el Swagger deja como `object` están descritos en la sección 2.8.

```text
## HealthResponse
  status*: string
  servicio*: string
  hora*: string
## RolesDbResponse
  app*: string  // Rol con el que corre la API (sujeto a RLS)
  service*: string  // Rol de servicio (auth y cron)
## ReadyResponse
  status*: string
  db*: RolesDbResponse
## RegisterDto
  nombre*: string
  correo*: string
  password*: string(minLength=10,maxLength=128)
  nombreUsuario: string
  aceptaTerminos*: boolean  // Debe ser true
## RegisterResponseDto
  usuario*: object
  restaurante: object
## RestauranteNuevoDto
  nombre*: string
  ciudadId*: number  // ciudad_id del catálogo (1 = Quito)
## RegisterOwnerDto
  nombre*: string
  correo*: string
  password*: string(minLength=10,maxLength=128)
  nombreUsuario: string
  aceptaTerminos*: boolean  // Debe ser true
  restaurante*: RestauranteNuevoDto
## LoginDto
  identificador*: string  // Correo o nombre de usuario
  password*: string
## TokenResponseDto
  accessToken*: string  // JWT ES256 de vida corta (15 min)
  refreshToken*: string  // Opaco y rotativo: úsalo una sola vez en /v1/auth/refresh
  tokenType*: string
  expiresIn*: number  // Segundos de vida del access token
  usuario*: object
## RefreshDto
  refreshToken*: string  // Refresh token opaco recibido en el login o en el refresh anterior
## MeRestauranteDto
  id*: string(format=uuid)  // public_id del restaurante: va en el encabezado `x-restaurant-id`
  nombre*: string
  rol*: enum(DUENO|CAJERO)
## MeResponseDto
  usuario*: object
  restaurantes*: [MeRestauranteDto]  // Vacío para un comensal sin trabajo en ningún local
## RestauranteResponse
  id*: string(format=uuid)  // public_id
  nombre*: string
  slug*: string
  descripcionCorta*: string(null)
  etiquetas*: [string]
  paisCodigo*: string
  ciudadId*: number
  zonaId*: number(null)
  monedaCodigo*: string
  zonaHoraria*: string
  direccion*: string(null)
  latitud*: number(null)
  longitud*: number(null)
  telefono*: string(null)
  logoUrl*: string(null)
  puestos*: number  // Puestos del local
  anotarMesa*: boolean  // Los comensales pueden anotar su mesa
  momentoCobro*: enum(ANTES_DE_SERVIR|DESPUES_DE_SERVIR)
  precioSueltoCentavos*: number  // Centavos
  recargoParaLlevarCentavos*: number  // Centavos
  llenoManualHasta*: string(format=date-time,null)  // Hasta cuándo dura "Local lleno"; null si no está activo
  estado*: string  // BORRADOR, ACTIVO, PAUSADO o BAJA
  creadoEn*: string(format=date-time)
  actualizadoEn*: string(format=date-time)
## UpdateRestauranteDto
  nombre: string
  descripcionCorta: string(null)
  etiquetas: [string]
  direccion: string(null)
  latitud: number(null)
  longitud: number(null)
  telefono: string(null)
  logoUrl: string(null)
  puestos: number  // Puestos del local; base del cálculo de ocupación
  anotarMesa: boolean
  momentoCobro: enum(ANTES_DE_SERVIR|DESPUES_DE_SERVIR)
  precioSueltoCentavos: number  // Precio del almuerzo suelto, en centavos
  recargoParaLlevarCentavos: number  // Recargo por llevar, en centavos
  zonaId: number(null)  // zona_id del catálogo (debe ser de la ciudad del local)
## HorarioResponse
  diaSemana*: number(minimum=1,maximum=7)  // Día ISO: 1 = lunes … 7 = domingo
  abre*: string
  cierra*: string
## HorarioDto
  diaSemana*: number  // ISO: 1 = lunes … 7 = domingo
  abre*: string
  cierra*: string
## ReemplazarHorariosDto
  horarios*: [HorarioDto]  // Reemplaza todos los horarios; [] los deja sin horario
## MesaResponse
  id*: string  // public_id de la mesa
  invitacion*: string  // Lo que va en el link de invitación (bocadoo://mesa/<invitacion>): el public_id de la mesa
  restaurante*: object
  anfitrion*: object
  soyAnfitrion*: boolean
  horaLlegada*: string(format=date-time)
  modo*: enum(CADA_UNO|INVITO_YO)
  estado*: enum(ABIERTA|EN_CAMINO|EN_MESA|FINALIZADA|CANCELADA)
  validadaEn: string(format=date-time,null)  // Cuándo la validó la caja
  miembros*: [MiembroMesa]
## CrearMesaDto
  etiqueta*: string
  capacidad*: number
## ActualizarMesaDto
  etiqueta: string
  capacidad: number
  activo: boolean
## LlenoDto
  lleno*: boolean  // true marca "Local lleno" por 20 minutos; false lo quita
## LlenoResponse
  lleno*: boolean
  llenoManualHasta*: string(format=date-time,null)  // Cuándo expira solo (20 minutos); null si se quitó
## PersonalResponse
  usuarioId*: string(format=uuid)  // public_id del usuario
  nombre*: string
  nombreVisible*: string(null)
  rol*: enum(DUENO|CAJERO)
  activo*: boolean
## InviteCashierDto
  correo*: string
  nombreVisible: string  // Nombre que verá el local; por defecto, el de su cuenta
## SetActiveDto
  activo*: boolean
## PlatoResponse
  id*: string  // Id del plato en el catálogo del local
  categoria*: enum(ALMUERZO|A_LA_CARTA|EXTRA|BEBIDA)
  seccion*: enum(JUGO|SOPA|FUERTE|POSTRE|ADICIONAL)
  nombre*: string
  descripcion*: string(null)
  precioCentavos*: number(null)  // Centavos; null = solo dentro del almuerzo
  fotoUrl*: string(null)
  etiquetas*: [string]
  activo*: boolean
## CrearPlatoDto
  categoria*: enum(ALMUERZO|A_LA_CARTA|EXTRA|BEBIDA)
  seccion: enum(JUGO|SOPA|FUERTE|POSTRE|ADICIONAL)  // Sección habitual dentro del almuerzo
  nombre*: string
  descripcion: string(null)
  precioCentavos: number(null)  // Centavos. Vacío = solo se sirve dentro del almuerzo
  fotoUrl: string(null)
  etiquetas: [string]
## ActualizarPlatoDto
  categoria: enum(ALMUERZO|A_LA_CARTA|EXTRA|BEBIDA)
  seccion: enum(JUGO|SOPA|FUERTE|POSTRE|ADICIONAL)
  nombre: string
  descripcion: string(null)
  precioCentavos: number(null)
  fotoUrl: string(null)
  etiquetas: [string]
  activo: boolean
## ItemMenuResponse
  id*: string  // Id del renglón del menú
  platoId*: string
  nombre*: string
  categoria*: enum(ALMUERZO|A_LA_CARTA|EXTRA|BEBIDA)
  descripcion*: string(null)
  fotoUrl*: string(null)
  etiquetas*: [string]
  seccion*: enum(JUGO|SOPA|FUERTE|POSTRE|ADICIONAL)
  precioCentavos*: number(null)  // Precio del catálogo (centavos)
  precioDelDiaCentavos*: number(null)  // Precio de ese día si difiere (centavos)
  porciones*: number(null)  // Porciones disponibles; null = sin límite
  agotado*: boolean
  agotadoEn*: string(format=date-time,null)  // Hora en que se acabó
  orden*: number
## MenuDiaResponse
  fecha*: string
  publicado*: boolean  // false = borrador: los comensales no lo ven
  publicadoEn*: string(format=date-time,null)
  items*: [ItemMenuResponse]
## ItemMenuDto
  platoId*: string  // Id del plato del catálogo
  seccion*: enum(JUGO|SOPA|FUERTE|POSTRE|ADICIONAL)
  precioCentavos: number(null)  // Precio de ese día si difiere del catálogo (centavos)
  porciones: number(null)  // Porciones disponibles; vacío = sin límite
  orden: number
## DefinirMenuDto
  items*: [ItemMenuDto]  // Menú completo del día, sin límite por sección. Quita lo que no esté en la lista.
## CopiarMenuDto
  desde: string  // Fecha de origen; por defecto, el último menú anterior con platos
  reemplazar: boolean  // Si el día destino ya tiene platos, true los reemplaza
## AgotadoDto
  agotado*: boolean
## ZonaResponse
  id*: number  // zona_id del catálogo
  nombre*: string
## OcupacionResponse
  nivel*: enum(LIBRE|MODERADO|LLENO)  // LIBRE (<50%), MODERADO (50–89%), LLENO (≥90% o "Local lleno" manual)
  porcentaje*: number  // Porcentaje de puestos ocupados (0–100)
  lleno*: boolean
## RestauranteCardResponse
  id*: string(format=uuid)  // public_id del restaurante
  nombre*: string
  slug*: string  // Identificador legible para la URL
  descripcionCorta*: string(null)
  etiquetas*: [string]
  zona*: ZonaResponse
  ciudadId*: number
  direccion*: string(null)
  latitud*: number(null)
  longitud*: number(null)
  logoUrl*: string(null)
  precioSueltoCentavos*: number  // Precio del almuerzo suelto, en centavos
  monedaCodigo*: string
  abiertoAhora*: boolean  // Según el horario del local y su zona horaria
  ocupacion*: OcupacionResponse
## RestauranteBusquedaResponse
  items*: [RestauranteCardResponse]
  nextCursor*: string(null)  // Pásalo como `cursor` para la página siguiente; null = no hay más
## PlatoVitrinaResponse
  id*: string(format=uuid)  // public_id del plato
  nombre*: string
  descripcion*: string(null)
  fotoUrl*: string(null)
  etiquetas*: [string]
  precioCentavos*: number(null)  // Centavos; null = solo se sirve dentro del almuerzo
  agotado*: boolean
## SeccionMenuResponse
  seccion*: string
  platos*: [PlatoVitrinaResponse]
## MenuHoyResponse
  fecha*: string  // Hoy en la zona horaria del local
  publicado*: boolean  // false si el menú de hoy no se publicó: `secciones` viene vacío
  secciones*: [SeccionMenuResponse]
## PlanVitrinaResponse
  id*: string  // Id de la plantilla de plan; es el `planId` de `POST /v1/restaurantes/{slug}/solicitudes-plan`
  tipo*: string
  nombre*: string
  almuerzos*: number
  precioCentavos*: number  // Centavos
  vigenciaDias*: number
  diasValidos*: [number]
  incluye*: [string]
## RestauranteDetalleResponse
  id*: string(format=uuid)  // public_id del restaurante
  nombre*: string
  slug*: string  // Identificador legible para la URL
  descripcionCorta*: string(null)
  etiquetas*: [string]
  zona*: ZonaResponse
  ciudadId*: number
  direccion*: string(null)
  latitud*: number(null)
  longitud*: number(null)
  logoUrl*: string(null)
  precioSueltoCentavos*: number  // Precio del almuerzo suelto, en centavos
  monedaCodigo*: string
  abiertoAhora*: boolean  // Según el horario del local y su zona horaria
  ocupacion*: OcupacionResponse
  telefono*: string(null)
  horarios*: [HorarioResponse]
  menuHoy*: MenuHoyResponse
  planes*: [PlanVitrinaResponse]
## PlantillaPlanResponse
  id*: string  // Id de la plantilla
  tipo*: enum(SEMANAL|QUINCENAL|MENSUAL|LIBRE)
  nombre*: string
  almuerzos*: number
  precioCentavos*: number  // Centavos
  vigenciaDias*: number
  cupos*: number(null)  // Máximo de planes activos a la vez; null = sin límite
  cuposDisponibles*: number(null)
  vendidosActivos*: number  // Planes activos vendidos de esta plantilla
  diasValidos*: [number]
  incluye*: [string]
  visibleEnMarketplace*: boolean  // Se muestra en la vitrina pública
  activo*: boolean
## CrearPlanDto
  tipo*: enum(SEMANAL|QUINCENAL|MENSUAL|LIBRE)
  nombre*: string
  almuerzos*: number
  precioCentavos*: number  // Centavos
  vigenciaDias*: number  // Días de vigencia desde la compra
  cupos: number(null)  // Máximo de planes activos vendidos a la vez; vacío = sin límite
  diasValidos: [integer]  // ISO: 1 = lunes … 7 = domingo
  incluye: [string]
  visibleEnMarketplace: boolean  // Mostrar en la vitrina pública
## ActualizarPlanDto
  tipo: enum(SEMANAL|QUINCENAL|MENSUAL|LIBRE)
  nombre: string
  almuerzos: number
  precioCentavos: number
  vigenciaDias: number
  cupos: number(null)
  diasValidos: [string]
  incluye: [string]
  visibleEnMarketplace: boolean
  activo: boolean
## ClienteResponse
  id*: string  // Id del cliente dentro del local
  nombre*: string
  telefono*: string(null)
  correo*: string(null)
  nota*: string(null)
  activo*: boolean
  vinculadoApp*: boolean  // Tiene una cuenta de la app vinculada
  almuerzosDisponibles*: number  // Suma de los planes vigentes
  proximoVencimiento*: string(null)
## ClientePageResponse
  items*: [ClienteResponse]
  nextCursor*: string(null)  // Cursor de la página siguiente; null = no hay más
## CrearClienteDto
  nombre*: string
  telefono: string(null)  // E.164; único por restaurante
  correo: string(null)
  nota: string(null)
## ClienteRefResponse
  id*: string  // Id del cliente dentro del local
  nombre*: string
## ReversoPagoResponse
  id*: string(format=uuid)
  montoCentavos*: number  // Centavos (negativo: pago inverso)
## PagoPlanResponse
  id*: string(format=uuid)
  estado*: string  // PENDIENTE, CONFIRMADO o RECHAZADO
  metodo*: string
  montoCentavos*: number  // Centavos
  fecha*: string
  comprobanteUrl*: string(null)
  reverso*: ReversoPagoResponse
## PlanVendidoResponse
  id*: string(format=uuid)  // public_id del plan vendido
  cliente*: ClienteRefResponse
  planId*: string(null)  // Plantilla de la que salió; null si es una migración
  origen*: enum(VENTA|MIGRADA)  // MIGRADA = saldo de la cartulina de papel
  nombrePlan*: string
  almuerzosTotales*: number
  almuerzosRestantes*: number
  precioPagadoCentavos*: number  // Centavos
  precioUnitarioCentavos*: number  // Centavos por almuerzo
  monedaCodigo*: string
  diasValidos*: [number]
  compradaEn*: string(format=date-time)
  venceEl*: string  // Último día de validez (zona horaria del local)
  estado*: enum(ACTIVA|AGOTADA|VENCIDA|ANULADA)
  anuladaEn*: string(format=date-time,null)
  anotacion*: string(null)
  pago*: PagoPlanResponse
## ClienteDetalleResponse
  id*: string  // Id del cliente dentro del local
  nombre*: string
  telefono*: string(null)
  correo*: string(null)
  nota*: string(null)
  activo*: boolean
  vinculadoApp*: boolean  // Tiene una cuenta de la app vinculada
  almuerzosDisponibles*: number  // Suma de los planes vigentes
  proximoVencimiento*: string(null)
  planes*: [PlanVendidoResponse]  // Todos sus planes, del más reciente al más antiguo
## ActualizarClienteDto
  nombre: string
  telefono: string(null)
  correo: string(null)
  nota: string(null)
  activo: boolean
## MigrarCartulinaDto
  almuerzosRestantes*: number  // Almuerzos que le quedan en la cartulina de papel
  venceEl*: string  // Último día válido
  precioUnitarioCentavos*: number  // Valor de cada almuerzo (centavos): es lo que el local le debe al cliente
  nombrePlan: string
  diasValidos: [integer]
  anotacion: string
## VincularDto
  correo*: string  // Correo de la cuenta de la app del comensal
## VenderPlanDto
  metodoPago*: enum(EFECTIVO|TRANSFERENCIA|DEUNA)
  pagoConfirmado: boolean  // Transferencia o Deuna ya verificada. Si no, queda PENDIENTE hasta que el dueño la confirme. Efectivo siempre se confirma.
  comprobanteUrl: string  // Foto del comprobante (https)
  referenciaExterna: string  // Número de la transferencia o id de Deuna
  planId*: string  // Id de la plantilla de plan
## DeshacerDto
  motivo: string
## PlanSolicitadoResponse
  id*: string
  nombre*: string
  precioCentavos*: number
  almuerzos*: number
## SolicitudPendienteResponse
  id*: string
  creadaEn*: string(format=date-time)
  cliente*: ClienteRefResponse
  plan*: PlanSolicitadoResponse
## CobroDto
  metodoPago*: enum(EFECTIVO|TRANSFERENCIA|DEUNA)
  pagoConfirmado: boolean  // Transferencia o Deuna ya verificada. Si no, queda PENDIENTE hasta que el dueño la confirme. Efectivo siempre se confirma.
  comprobanteUrl: string  // Foto del comprobante (https)
  referenciaExterna: string  // Número de la transferencia o id de Deuna
## SolicitudRechazadaResponse
  id*: string
  estado*: enum(RECHAZADA)
## SolicitarPlanDto
  planId*: string  // Id del plan, tal como aparece en la vitrina
## SolicitudPlanCreadaResponse
  id*: string  // Id de la solicitud
  estado*: enum(PENDIENTE)
  plan*: string
  creadaEn*: string(format=date-time)
## CodigoPaseResponse
  codigo*: string  // Texto que se dibuja como QR. Cambia cada 30 s.
  validoSegundos*: number
  expiraEn*: string(format=date-time)  // Cuándo deja de servir este código (la caja acepta además ±1 paso)
## ValidarDto
  codigoQr: string  // Contenido del QR del comensal (canal QR)
  clienteId: string  // Id del cliente elegido en la búsqueda manual (canal MANUAL)
  paraLlevar: boolean
  mesaLocalId: string  // Mesa del local donde se sirve
## ValidacionResponse
  resultado*: enum(OK|OK_ADVERTENCIA|DUPLICADO|SIN_PLAN|SIN_SALDO|VENCIDO|DIA_NO_VALIDO|OTRO_LOCAL|QR_EXPIRADO|QR_INVALIDO|LIMITE_SAAS)
  mensaje*: string
  descontado*: boolean  // true solo si se descontó un almuerzo (OK u OK_ADVERTENCIA)
  cliente: object
  consumo: object
  plan: object
  almuerzosRestantes: number(null)
  diasParaVencer: number(null)
## ConsumoRevertidoResponse
  id*: string(format=uuid)  // public_id del consumo
  revertido*: boolean
## MiembroMesaResponse
  nombre*: string
  esAnfitrion*: boolean
  paraLlevar*: boolean
  tieneCuenta*: boolean  // Es cliente del local (tiene ficha)
  almuerzosDisponibles*: number
## MesaVistaResponse
  modo*: string  // CADA_UNO o INVITO_YO
  estado*: string
  horaLlegada*: string(format=date-time)
  validadaEn*: string(format=date-time,null)
  personas*: number
  cubiertos*: number  // Cuántos almuerzos cubren los planes
  miembros*: [MiembroMesaResponse]
## ResultadoMiembroResponse
  miembro*: string
  resultado*: string
  descontado*: boolean
  consumoId*: string(format=uuid,null)
## MesaValidadaResponse
  modo*: string  // CADA_UNO o INVITO_YO
  estado*: string
  horaLlegada*: string(format=date-time)
  validadaEn*: string(format=date-time,null)
  personas*: number
  cubiertos*: number  // Cuántos almuerzos cubren los planes
  miembros*: [MiembroMesaResponse]
  yaValidada*: boolean  // La mesa ya se había validado: no se descontó nada esta vez
  resultados*: [ResultadoMiembroResponse]
  descontados*: number
  porCobrar*: number  // Almuerzos a cobrar aparte
## PagoVentaResponse
  estado*: string
  metodo*: string(null)
## ItemVentaResponse
  nombre*: string
  esAlmuerzo*: boolean
  cantidad*: number
  precioUnitarioCentavos*: number
  subtotalCentavos*: number
## VentaResponse
  id*: string(format=uuid)  // public_id de la venta
  ticket*: number  // Número de ticket del día
  fecha*: string
  totalCentavos*: number  // Centavos
  monedaCodigo*: string
  paraLlevar*: boolean
  mesaTexto*: string(null)
  creadoEn*: string(format=date-time)
  deshecha*: boolean  // true si ya se deshizo (pago inverso registrado)
  pago*: PagoVentaResponse
  items*: [ItemVentaResponse]
## ItemVentaDto
  tipo*: enum(ALMUERZO|PLATO|LIBRE)  // ALMUERZO: almuerzo suelto al precio del local. PLATO: del catálogo. LIBRE: cobro suelto con nombre y precio.
  platoId: string  // Obligatorio en PLATO
  nombre: string  // Obligatorio en LIBRE
  precioUnitarioCentavos: number  // Centavos; obligatorio en LIBRE
  cantidad*: number
## VentaDto
  items*: [ItemVentaDto]
  metodoPago*: enum(EFECTIVO|TRANSFERENCIA|DEUNA)
  paraLlevar: boolean  // Suma el recargo para llevar del local por cada almuerzo
  mesaTexto: string
  pagoConfirmado: boolean  // Transferencia o Deuna ya verificada; si no, queda pendiente
  comprobanteUrl: string
  referenciaExterna: string
## MetodoCierreResponse
  metodo*: string
  nombre*: string
  esEfectivo*: boolean
  planesCentavos*: number  // Cobros de planes, centavos
  posCentavos*: number  // Ventas sueltas, pedidos y ofertas, centavos
  totalCentavos*: number
## CierreRegistradoResponse
  efectivoEsperadoCentavos*: number
  efectivoContadoCentavos*: number
  diferenciaCentavos*: number
  nota*: string(null)
  cerradoEn*: string(format=date-time)
  cerradoPor*: string
  movimientosDespuesDelCierre*: boolean  // Hubo cobros o reversos en efectivo después de cerrar: conviene reabrir y recontar
## CierreCajaResponse
  fecha*: string
  efectivoEsperadoCentavos*: number
  totalCentavos*: number
  porMetodo*: [MetodoCierreResponse]
  almuerzosServidos*: number
  almuerzosConPlan*: number
  almuerzosSueltos*: number
  almuerzosParaLlevar*: number
  pagosPendientes*: number  // Pagos por confirmar ese día
  cierre*: CierreRegistradoResponse  // null si la caja no se cerró
## CerrarCajaDto
  efectivoContadoCentavos*: number  // Efectivo contado en la gaveta, en centavos
  nota: string
## ClienteRef
  id*: string
  nombre*: string
## ConsumoReclamado
  id*: string(format=uuid)
  fecha*: string(format=date-time)
  canal*: string
  plan*: string
## ReclamoPersonalResponse
  id*: string
  estado*: enum(PENDIENTE|DEVUELTO|RECHAZADO)
  mensaje*: string
  respuesta*: string(null)
  creadoEn*: string(format=date-time)
  resueltoEn*: string(format=date-time,null)
  cliente*: ClienteRef
  consumo*: ConsumoReclamado
## DevolverDto
  respuesta: string
## RechazarDto
  respuesta*: string
## PlanPase
  id*: string  // public_id del plan vendido
  nombre*: string
  almuerzosRestantes*: number
  almuerzosTotales*: number
  venceEl*: string
  diasParaVencer*: number
  diasValidos*: [integer]
  valeHoy*: boolean  // El plan vale hoy (día de la semana permitido)
## LocalPase
  restaurante*: object
  hoy*: string  // Hoy en la zona horaria del local
  almuerzosDisponibles*: number  // Suma de los planes vigentes
  planes*: [PlanPase]  // En orden FIFO: el primero es el que se descuenta
## PaseResponse
  usuario*: object
  codigo*: object
  locales*: [LocalPase]
## ConsumoItem
  id*: string  // public_id del consumo
  fecha*: string(format=date-time)
  fechaLocal*: string  // Día del almuerzo en la hora local del restaurante
  restaurante*: object
  plan*: object
  canal*: enum(QR|MANUAL|PREORDEN|MESA)
  paraLlevar*: boolean
  revertido*: boolean  // El almuerzo se devolvió al plan (deshacer en caja o reclamo aceptado)
  revertidoEn: string(format=date-time,null)
## HistorialResponse
  items*: [ConsumoItem]
  nextCursor: string(null)  // null si no hay más páginas
## ReclamoResponse
  consumo*: object
  estado*: enum(PENDIENTE|DEVUELTO|RECHAZADO)  // DEVUELTO: el almuerzo volvió a tu plan
  mensaje*: string
  respuesta: string(null)  // Respuesta del restaurante
  creadoEn*: string(format=date-time)
  resueltoEn: string(format=date-time,null)
## ReclamarDto
  mensaje*: string(minLength=10,maxLength=500)
## AlmuerzoDto
  platos*: [string]  // public_id de los platos elegidos del menú de hoy, uno por sección (JUGO, SOPA, FUERTE, POSTRE)
## ExtraDto
  plato*: string  // public_id del plato (con precio) del menú de hoy
  cantidad*: number(minimum=1,maximum=10)
## CrearPedidoDto
  restaurante*: string  // public_id del restaurante
  paraLlevar: boolean  // Suma el recargo para llevar del local al almuerzo
  almuerzo: AlmuerzoDto
  extras: [ExtraDto]
## ExtraPedido
  id*: string
  nombre*: string
  cantidad*: number
  precioUnitarioCentavos*: number
  subtotalCentavos*: number
## PedidoResponse
  id*: string  // public_id del pedido
  qr*: string  // Contenido del QR que la caja escanea: es el public_id del pedido
  numero*: number  // "Pedido #7" del día
  fecha*: string
  restaurante*: object
  estado*: enum(EN_CAMINO|CANJEADA|SERVIDA|EXPIRADA|CANCELADA)
  paraLlevar*: boolean
  almuerzo: object  // null si solo pidió extras
  extras*: [ExtraPedido]
  recargoLlevarCentavos*: number
  totalCentavos*: number  // Lo que se pagaría en caja según lo conocido al pedir
  monedaCodigo*: string
  creadoEn*: string(format=date-time)
  venceEn*: string(format=date-time)  // creadoEn + 30 minutos
  canjeadoEn: string(format=date-time,null)
  servidoEn: string(format=date-time,null)
  canceladoEn: string(format=date-time,null)
## PedidosResponse
  items*: [PedidoResponse]
  nextCursor: string(null)
## PedidoCaja
  id*: string  // public_id del pedido
  qr*: string  // Contenido del QR que la caja escanea: es el public_id del pedido
  numero*: number  // "Pedido #7" del día
  fecha*: string
  restaurante*: object
  estado*: enum(EN_CAMINO|CANJEADA|SERVIDA|EXPIRADA|CANCELADA)
  paraLlevar*: boolean
  almuerzo: object  // null si solo pidió extras
  extras*: [ExtraPedido]
  recargoLlevarCentavos*: number
  totalCentavos*: number  // Lo que se pagaría en caja según lo conocido al pedir
  monedaCodigo*: string
  creadoEn*: string(format=date-time)
  venceEn*: string(format=date-time)  // creadoEn + 30 minutos
  canjeadoEn: string(format=date-time,null)
  servidoEn: string(format=date-time,null)
  canceladoEn: string(format=date-time,null)
  comensal*: object  // Quién pidió (nombre de su cuenta)
  cliente: object  // Su ficha de cliente en este local; null si no es cliente
## PedidoCanjeResponse
  pedido*: PedidoCaja
  yaCanjeado*: boolean  // El pedido ya estaba canjeado: no se descontó nada esta vez
  almuerzo: object  // null si el pedido no lleva almuerzo. `resultado` es null al repetir un canje ya hecho.
  porCobrarCentavos*: number  // Lo que la caja cobra aparte: extras, recargo y el almuerzo si ningún plan lo cubrió
## CrearMesaCompartidaDto
  restaurante*: string  // public_id del restaurante
  horaLlegada*: string  // Hora de llegada (de ahora a 12 horas)
  modo: enum(CADA_UNO|INVITO_YO)  // CADA_UNO: cada quien con su plan. INVITO_YO: paga el anfitrión.
  paraLlevar: boolean
## MiembroMesa
  nombre*: string
  esAnfitrion*: boolean
  paraLlevar*: boolean
  soyYo*: boolean  // Es el comensal que consulta
## InvitacionResponse
  id*: string
  restaurante*: object
  anfitrion*: object
  horaLlegada*: string(format=date-time)
  modo*: enum(CADA_UNO|INVITO_YO)
  estado*: string
  personas*: number
  capacidad*: number
  puedeUnirse*: boolean
  motivo: enum(MESA_CERRADA|MESA_VENCIDA|MESA_LLENA|RESTAURANTE_NO_DISPONIBLE|YA_ERES_MIEMBRO)  // Por qué no puede unirse; null si puede
## UnirseDto
  paraLlevar: boolean
## PendienteResponse
  consumo*: object
  expiraEn*: string(format=date-time)
  etiquetasDisponibles*: [enum(RICO|BUENA_PORCION|RAPIDO|BUENA_ATENCION|LIMPIO|FRIO|SALADO|PORCION_PEQUENA|DEMORA|MALA_ATENCION)]
## OpinionResponse
  consumo*: object
  etiquetas*: [enum(RICO|BUENA_PORCION|RAPIDO|BUENA_ATENCION|LIMPIO|FRIO|SALADO|PORCION_PEQUENA|DEMORA|MALA_ATENCION)]
  comentario: string(null)
  descartada*: boolean  // Cerró la tarjeta sin opinar
  creadoEn*: string(format=date-time)
  respuesta: object
## OpinarDto
  etiquetas: [enum(RICO|BUENA_PORCION|RAPIDO|BUENA_ATENCION|LIMPIO|FRIO|SALADO|PORCION_PEQUENA|DEMORA|MALA_ATENCION)]
  comentario: string  // Solo lo lee el restaurante; no se publica
## OpinionBandeja
  id*: string  // La opinión se identifica por el public_id de su almuerzo (una por almuerzo)
  cliente*: object
  almuerzoEn*: string(format=date-time)  // Cuándo almorzó
  plan*: object
  creadoEn*: string(format=date-time)
  etiquetas*: [enum(RICO|BUENA_PORCION|RAPIDO|BUENA_ATENCION|LIMPIO|FRIO|SALADO|PORCION_PEQUENA|DEMORA|MALA_ATENCION)]
  comentario: string(null)
  respuesta: object
## BandejaResponse
  items*: [OpinionBandeja]
  nextCursor: string(null)
  resumen*: object  // Últimos 30 días (sin descartes)
## ResponderDto
  respuesta*: string
## MiTarjeta
  sellos*: number
  meta*: number
  faltan*: number  // Sellos que faltan para el próximo premio
  premiosDisponibles*: number
  premio*: string
  nombre: string(null)
  activa*: boolean  // false si el local apagó la tarjeta (los premios ya ganados se pueden canjear)
  restaurante*: object
## ConfigResponse
  activa*: boolean
  meta*: number
  premio*: string
  nombre: string(null)
  cuenta*: enum(ALMUERZO|PLATO)
## ConfigDto
  activa*: boolean  // Encender o apagar la tarjeta
  meta*: number(minimum=2,maximum=50)  // Sellos para ganar un premio
  premio*: string
  nombre: string
  cuenta: enum(ALMUERZO)  // Qué suma un sello. Por ahora, cada almuerzo validado.
## TarjetaResponse
  sellos*: number
  meta*: number
  faltan*: number  // Sellos que faltan para el próximo premio
  premiosDisponibles*: number
  premio*: string
  nombre: string(null)
  activa*: boolean  // false si el local apagó la tarjeta (los premios ya ganados se pueden canjear)
## PublicarOfertaDto
  titulo*: string(maxLength=80)
  descripcion: string(maxLength=300)
  platoId: string  // Plato del catálogo (public_id) al que corresponde la oferta
  precioCentavos*: number  // Precio de la oferta en centavos; debe ser menor que el original
  precioOriginalCentavos*: number  // Precio normal en centavos
  stock*: number(minimum=1,maximum=1000)  // Unidades disponibles
  duracionMinutos: number(minimum=5,maximum=1440)  // Cuánto dura desde que se publica
## OfertaResponse
  id*: string  // public_id
  titulo*: string
  descripcion: string(null)
  plato: object
  precioCentavos*: number  // Centavos
  precioOriginalCentavos*: number  // Centavos
  descuentoPorcentaje*: number  // Descuento entero sobre el precio original
  moneda*: string
  stockTotal*: number
  stockRestante*: number  // Nunca negativo
  canjeadas*: number  // Unidades ya canjeadas
  iniciaEn*: string(format=date-time)
  expiraEn*: string(format=date-time)
  estado*: enum(VIGENTE|PROGRAMADA|AGOTADA|EXPIRADA|CERRADA)  // CERRADA tiene prioridad; luego AGOTADA, EXPIRADA, PROGRAMADA y VIGENTE
## OfertasPage
  items*: [OfertaResponse]
  nextCursor: string(null)
## CanjearOfertaDto
  cantidad: number(minimum=1,maximum=10)  // Unidades que se llevan en este canje
  metodoPago*: enum(EFECTIVO|TRANSFERENCIA|DEUNA)  // Con qué paga en caja. El cobro queda confirmado: el canje se entrega al pagar.
  comensalId: string  // Comensal con cuenta (public_id), si lo identifican. Sin él, es un canje de mostrador.
## OfertaCanjeResponse
  id*: string  // public_id del canje
  cantidad*: number
  montoCentavos*: number  // Precio de la oferta × cantidad, en centavos. Es todo lo que cobra el local: sin comisión.
  moneda*: string
  metodoPago*: enum(EFECTIVO|TRANSFERENCIA|DEUNA)
  comensalId: string(null)  // public_id del comensal, si se identificó
  creadoEn*: string(format=date-time)
  oferta*: OfertaResponse  // La oferta tal como quedó después del canje (stock actualizado)
## OfertasPublicas
  items*: [OfertaResponse]  // Solo vigentes con stock
## AlmuerzosDia
  servidos*: number  // Almuerzos descontados de planes, netos de devoluciones
  paraLlevar*: number
  porCanal*: object
## IngresosDia
  totalCentavos*: number  // Cobros confirmados del día, netos de reversos (centavos)
  porOrigen*: object
  porMetodo*: [object]
  pendientesPorConfirmar*: object  // Transferencias o Deuna sin confirmar (no están en el total)
## VentasPosDia
  tickets*: number
  reversos*: number  // Tickets deshechos
  totalCentavos*: number  // Neto de reversos (centavos)
  almuerzos*: number  // Almuerzos sueltos vendidos, netos
## CantidadMonto
  cantidad*: number
  centavos*: number
## ResumenDiarioResponse
  fecha*: string  // Día local del restaurante
  zonaHoraria*: string
  moneda*: string
  almuerzos*: AlmuerzosDia
  ingresos*: IngresosDia
  ventasPos*: VentasPosDia
  planesVendidos*: CantidadMonto  // Planes vendidos ese día, sin los anulados ni las cartulinas migradas
  ofertas*: object  // Canjes de ofertas flash
  escaneos*: object  // Escaneos en caja
## PlanVentas
  nombre*: string
  vendidos*: number  // No anulados
  anulados*: number
  ingresoCentavos*: number  // Precio pagado de los vendidos (centavos)
  almuerzosVendidos*: number  // Almuerzos incluidos en lo vendido
  almuerzosConsumidos*: number  // Almuerzos ya consumidos de lo vendido
## VentasPlanesResponse
  desde*: string
  hasta*: string
  zonaHoraria*: string
  moneda*: string
  total*: object
  porPlan*: [PlanVentas]  // Por nombre de plan, de más a menos ingreso
  porDia*: [object]  // Solo los días con ventas
## HoraPico
  hora*: number(minimum=0,maximum=23)  // Hora local del restaurante (0 = 00:00–00:59)
  almuerzos*: number  // Almuerzos de planes servidos esa hora (los devueltos no cuentan)
  ventas*: number  // Tickets de ventas sueltas de esa hora (los deshechos no cuentan)
  total*: number  // almuerzos + ventas
## HorasPicoResponse
  desde*: string
  hasta*: string
  zonaHoraria*: string
  porHora*: [HoraPico]  // Siempre 24 filas, de la hora 0 a la 23
  horaPico: number(null)  // Hora con más movimiento (la más temprana si hay empate); null si no hubo nada
  totalAlmuerzos*: number
  totalVentas*: number
## PlatoRanking
  posicion*: number
  plato*: object  // id = public_id del plato
  unidades*: number  // unidadesVentas + unidadesPedidos
  unidadesVentas*: number  // Vendidas sueltas en caja (netas de tickets deshechos)
  unidadesPedidos*: number  // Incluidas en pedidos de comensales ya canjeados
  ingresoCentavos*: number  // Lo cobrado por ese plato (centavos); los platos dentro del almuerzo cuestan 0
## RankingResponse
  desde*: string
  hasta*: string
  zonaHoraria*: string
  moneda*: string
  items*: [PlatoRanking]
## PlanPendiente
  nombre*: string
  planes*: number
  almuerzos*: number
  pasivoCentavos*: number
## BloqueVencimiento
  rango*: enum(HOY|EN_1_A_3_DIAS|EN_4_A_7_DIAS|EN_MAS_DE_7_DIAS)
  planes*: number
  almuerzos*: number
  pasivoCentavos*: number
## PendientesResponse
  fecha*: string  // Hoy, en la zona del local
  zonaHoraria*: string
  moneda*: string
  total*: object  // Lo que el local todavía debe en almuerzos prepagados
  porPlan*: [PlanPendiente]  // Por nombre de plan, de más a menos pasivo
  porVencimiento*: [BloqueVencimiento]  // Siempre los 4 bloques, en este orden
## ClienteSeguimiento
  clienteId*: string  // Id del cliente dentro del local (el mismo de /v1/clientes)
  nombre*: string
  telefono: string(null)
  motivos*: [enum(POR_VENCER|SIN_VENIR|PARA_RENOVAR)]  // Por qué aparece; puede tener más de uno. El primero es el más urgente.
  almuerzosRestantes*: number  // Almuerzos que le quedan en planes vigentes (0 si no tiene)
  venceEl: string(null)  // Vencimiento más próximo entre sus planes vigentes
  ultimaVisita: string(null)  // Último almuerzo servido (día local); null si nunca
  diasSinActividad*: number  // Días desde su última actividad (último almuerzo o última compra de plan)
## SeguimientoResponse
  fecha*: string  // Hoy, en la zona del local
  zonaHoraria*: string
  total*: number  // Cuántos cumplen algún criterio (puede ser más que los devueltos por `limit`)
  items*: [ClienteSeguimiento]  // POR_VENCER primero (vence antes, antes), luego SIN_VENIR (más días sin venir, antes) y PARA_RENOVAR (el que se quedó sin plan más recién, antes)
## PlanSaasResponse
  codigo*: string
  nombre*: string
  precioMensualCentavos: number(null)  // Precio mensual vigente en el país del local (centavos); null si el plan no tiene precio ahí
  moneda: string(null)
## CicloResponse
  inicio*: string  // Primer día del ciclo
  fin*: string  // Día en que termina el ciclo
  diasRestantes*: number  // Días desde hoy (hora local del local) hasta `fin`; 0 si ya pasó
  vencido*: boolean  // true si `fin` ya pasó y el ciclo no se renovó: los contadores siguen del ciclo anterior
## LimitesResponse
  escaneosMes: number(null)  // Escaneos por ciclo; null = sin límite
  mesaGrupal*: boolean
  reportesAvanzados*: boolean
## SuscripcionResponse
  estado*: enum(TRIAL|FREEMIUM|ACTIVA_PRO|MOROSA|SUSPENDIDA|CANCELADA|SIN_SUSCRIPCION)  // `SIN_SUSCRIPCION`: el local aún no tiene plan SaaS asignado (se comporta como sin límite)
  plan: PlanSaasResponse
  ciclo: CicloResponse
  proximoCobro: string(null)  // null en planes gratuitos
  limites*: LimitesResponse
## UsoResponse
  ciclo: CicloResponse
  escaneosUsados*: number  // Escaneos válidos del ciclo (un almuerzo descontado cuenta uno; deshacerlo no lo devuelve)
  limite: number(null)  // null = sin límite
  restantes: number(null)  // Lo que queda antes del tope; null = sin límite
  porcentaje: number(null)  // Porcentaje entero del límite usado (puede pasar de 100); null = sin límite
  nivel*: enum(ILIMITADO|NORMAL|CERCA_DEL_LIMITE|LIMITE_ALCANZADO)  // CERCA_DEL_LIMITE desde el 80 %; LIMITE_ALCANZADO desde el 100 %: la caja responde `LIMITE_SAAS`
  rechazadosPorLimite*: number  // Escaneos que la caja rechazó con `LIMITE_SAAS` desde que empezó el ciclo
## EventoDto
  tipo*: string(maxLength=60)  // minúsculas, dígitos y `_`, con puntos para agrupar (`menu.visto`)
  ocurridoEn: string  // Cuándo ocurrió en el dispositivo. De hace 7 días a 5 minutos en el futuro; por defecto, ahora.
  restauranteId: string  // Local al que se refiere (public_id)
  usuarioId: string  // Solo para verificar: si se manda, debe ser el usuario de la sesión; el de otro se rechaza
  propiedades: object  // Objeto plano, hasta 20 claves y 1024 bytes
## LoteEventosDto
  sesionId: string  // Sesión de la app (UUID generado por el cliente)
  plataforma: enum(ANDROID|IOS|WEB)
  versionApp: string(maxLength=20)
  eventos*: [EventoDto]
## LoteResponse
  aceptados*: number  // Eventos guardados de este lote
  anonimizado*: boolean  // true si el usuario no dio su consentimiento de analítica: los eventos se guardaron sin su identidad (sin usuario ni sesión)
## ProblemDetails — Error según RFC 9457 (`application/problem+json`). El cliente decide por `code`, nunca por el texto de `detail`.
  type*: string
  title*: string
  status*: integer
  code*: string  // Código estable; sin código propio es el nombre del estado HTTP
  detail*: string
  instance: string  // Ruta de la petición
  requestId: string  // Identificador para buscar la petición en el log
```
