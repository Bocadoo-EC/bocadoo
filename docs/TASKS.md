# 📋 Plan de Ejecución por Fases — Bocadoo Mobile (Producto Oficial)

> **Documento de Control y Tareas — Bocadoo Mobile (Production Grade)**  
> **Stack:** Flutter (Dart) | Material Design 3 | Riverpod (AsyncNotifier) | GoRouter | Dio | Flutter Secure Storage  
> **Arquitectura:** Clean Architecture (Domain, Data, Presentation)  
> **Fuente de verdad de diseño:** `docs/IDENTIDAD_BOCADOO.md`  
> **Referencia Web Visual:** Workspace `pmv/inspo-palette-creation`  
> **Flujo Git:** `main` (Core compartido) ➡️ `feat/customer` (James) | `feat/owner` (Carlos)

---

## 🏗️ Estándar de Producción Requerido

Toda implementación en este proyecto debe cumplir con los siguientes criterios de arquitectura de producción:
1. **Clean Architecture:** Separación estricta entre `domain/` (Entidades e Interfaces abstractas), `data/` (DTOs, Repositorios e Integraciones con API/Storage) y `presentation/` (Widgets y Notifiers de Riverpod).
2. **Manejo de Estados de Red (`AsyncValue`):** Todas las pantallas deben manejar explícitamente tres estados: *Carga* (Shimmer), *Error* (Mensaje amigable en español + botón reintentar) y *Éxito* (Datos renderizados).
3. **Persistencia y Modo Offline Real:** Sincronización de token JWT en `FlutterSecureStorage` y caché local en `SharedPreferences` para consulta offline del pase y menú.
4. **Cero Cadenas Mágicas / Cero Colores Hardcodeados:** Todo color debe provenir de `AppTheme` / `BocadooColors` y todo texto debe respetar la nomenclatura de `IDENTIDAD_BOCADOO.md`.

---

## 📊 Estado Actual del Proyecto

### 🎨 FASE 0: Sistema de Diseño, Tokens y Core (`main`)
- [x] **0.1 Configuración de Tokens y Tema (`app_theme.dart`)** — Paleta clara/oscura M3 (`#8234C6` / `#DEB7FF`), `BocadooColors` ThemeExtension, gradientes `heroGradient` y colores fijos del QR (`#2D0050` sobre `#FFFFFF`).
- [x] **0.2 Tipografía y Radios Globales** — `google_fonts` (`Plus Jakarta Sans`), escala tipográfica oficial (13px metadatos, 15px lectura, 17px botones, 32–48px números protagonistas) y radios globales (cápsula 999px, tarjetas 28px, inputs 16px).
- [x] **0.3 Componentes Atómicos (`lib/core/widgets/`)** — `BocadooButton`, `BocadooHeader`, `BocadooQr`, `StatusChip` y `BocadooBottomNavBar` exportados desde `core/widgets/widgets.dart`.
- [x] **0.4 Provider Global de Tema & Permisos iOS** — `ThemeMode` persistente (Sistema/Claro/Oscuro) con Riverpod en `main.dart`, widget `ThemeToggle` y `NSCameraUsageDescription` en `ios/Runner/Info.plist`.

### 👤 FASE 1: Módulo Comensal — James (`feat/customer`)
- [x] **1.1 Catálogo de Restaurantes (`restaurants_screen.dart`)** — Buscador, `ChoiceChip` de filtros, tarjetas con foto/ocupación/distancia/precio y modal de Menú del Día categorizado.
- [x] **1.2 Pantalla Mi Pase y Modo Offline (`pase_screen.dart`)** — Hero gradient, contador `14 / 20`, QR rotativo `BCD1`, shimmer, estado agotado, historial en bottom sheet y persistencia offline con `shared_preferences`.
- [ ] **1.3 Flujo de Adquisición y Renovación de Plan (Producción)** — Adquisición/Renovación con interfaz de repositorio abstracta (`IPlanRepository`), modelos DTO, estados de carga/error y confirmación con vocabulario oficial (*"Quiero este"*, *"Paga en caja"*, *"Renovar"*).
- [ ] **1.4 Perfil, Ajustes y Navegación Comensal (Producción)** — `presentation/customer_profile_screen.dart` con `ThemeToggle`, acciones de historial (*"No fui yo"* / *"Devolver"*), integración de `BocadooBottomNavBar` y gestión de sesión del comensal.

### 🏪 FASE 2: Módulo Dueño — Carlos (`feat/owner`)
- [x] **2.0 Pantallas Base del Dueño** — `scanner_screen.dart`, `scan_result_screen.dart`, `cash_closing_screen.dart` y `sell_plan_modal.dart` implementadas en `lib/features/owner/presentation/`.
- [ ] **2.1 Ajustes, Control de Menú y Operación en Caja (Producción)** — Control de Menú del Día (`owner_menu_screen.dart` con *"Repetir ayer"*, *"Publicar"*, *"Agotado"*), `ThemeToggle`, unificación de importaciones de UI y limpieza total de vocabulario prohibido en `features/owner/`.

### 🔌 FASE 3: Capa de Red y Backend Real (`main`)
- [ ] **3.0 Cliente de Red e Interceptores HTTP (`core/network/`)** — Instancia global de `Dio` con base URL dinámico (`api.bocadoo.ec`), interceptor Bearer JWT con `FlutterSecureStorage` y mapeo global de excepciones de red (`NetworkException`).
- [ ] **3.1 Autenticación Real y Control de Sesión (`core/auth/`)** — Repositorio `AuthRepository` (Login/Registro/Logout), guardado persistente del JWT, renovación de token y protección de rutas en `app_router.dart` según rol (`customer` / `owner`).
- [ ] **3.2 Switch de Mocks a Endpoints Reales (`data/repositories/`)** — Inyección de dependencias en Riverpod para conmutar entre `MockRepository` y `RemoteRepository` mediante una sola variable de entorno/configuración sin alterar la capa de presentación.

### 🔬 FASE FINAL: Auditoría de Marca, Seguridad y Producción (`main`)
- [ ] **F.1 Auditoría Total de Marca y Calidad (`IDENTIDAD_BOCADOO.md`)** — 0 hex fuera de `app_theme.dart`, 0 palabras prohibidas en toda la app, manejo impecable de errores HTTP en español, montos en formato ecuatoriano (`$2,75`) y compilación limpia (`flutter analyze` + `flutter test`).

---

## 🤖 Prompts Autocontenidos de Producción

### 1️⃣ Para James (`feat/customer`) — Tareas 1.3 y 1.4: Adquisición de Planes, Perfil y BottomNavBar (Grado Producción)

```text
Lee las reglas en @GEMINI.md y @docs/IDENTIDAD_BOCADOO.md. Estamos en la rama `feat/customer`.
Inspecciona en el PMV Web (`pmv/inspo-palette-creation`) las vistas de adquisición de planes y perfil/ajustes del comensal.

Implementa en `mobile/lib/features/customer/` bajo Clean Architecture de Producción:

1. **Dominio y Datos (`domain/` & `data/`):**
   - Crea `domain/models/plan_option.dart` (paquetes de 5, 10 o 20 almuerzos, precio, ahorro) y la interfaz abstracta `domain/repositories/i_plan_repository.dart`.
   - Crea `data/repositories/customer_plan_repository.dart` implementando la interfaz con persistencia y estado mock listo para conmutarse a la API HTTP.

2. **Tarea 1.3 (Adquisición / Renovación de Plan):**
   - Crea `presentation/plan_checkout_modal.dart` (usable desde `restaurants_screen.dart` y `pase_screen.dart` en el botón "Renovar").
   - Maneja estados de procesamiento mediante `AsyncValue` en Riverpod (estado cargando al procesar la selección, diálogo de éxito y actualización inmediata del pase activo).
   - Usa exclusivamente el vocabulario oficial permitido: "Quiero este", "Paga en caja", "Renovar", "Ahorras $5" y formato monetario Ecuador (`$2,75`, `$55,00`). Cero palabras prohibidas.

3. **Tarea 1.4 (Perfil, Ajustes y Navegación Comensal):**
   - Crea `presentation/customer_profile_screen.dart` integrando `ThemeToggle` (Sistema / Claro / Oscuro), datos del usuario y opciones en el historial con acciones de reclamo oficiales: "No fui yo" y "Devolver".
   - Conecta `BocadooBottomNavBar` (de `core/widgets/widgets.dart`) con la pastilla `primaryContainer` en la pestaña activa para navegar fluidamente entre "Mi Pase", "Dónde comer" y "Ajustes".

REGLA: Trabaja únicamente en `features/customer/` (conecta las rutas necesarias en `app_router.dart`). Ejecuta `flutter analyze` en `mobile/` al finalizar y asegura 0 errores.
```

---

### 2️⃣ Para Carlos (`feat/owner`) — Tarea 2.1: Control de Menú del Día, Operaciones en Caja y Limpieza (Grado Producción)

```text
Lee las reglas en @GEMINI.md y @docs/IDENTIDAD_BOCADOO.md. Estamos en la rama `feat/owner`.
Inspecciona en el PMV Web (`pmv/inspo-palette-creation`) las vistas del módulo de dueño.

Implementa y actualiza en `mobile/lib/features/owner/` bajo Clean Architecture de Producción:

1. **Dominio y Datos de Menú (`domain/` & `data/`):**
   - Crea `domain/models/daily_menu.dart` (Sopa, Fuerte, Jugo, Postre, estado activo/agotado) y la interfaz `domain/repositories/i_owner_repository.dart`.
   - Crea `data/repositories/owner_repository.dart` para gestionar la publicación del menú diario y el estado de la caja.

2. **Control de Menú del Día (`presentation/owner_menu_screen.dart`):**
   - Pantalla de gestión operativa del menú con botones de acción rápida oficiales: "Repetir ayer", "Publicar" y botón de pánico de agotado: "Se acabó" / "Agotado".
   - Conecta notifiers de Riverpod con estado `AsyncValue` para dar retroalimentación visual al dueño al publicar.

3. **Ajustes del Dueño (`presentation/owner_settings_screen.dart`):**
   - Incluye el selector de tema `ThemeToggle` (Sistema / Claro / Oscuro), estado de apertura del local ("Abierto" / "Cerrado") y cierre de sesión.

4. **Limpieza Visual y Vocabulario en `features/owner/`:**
   - Unifica todas las importaciones de UI a `package:flutter/material.dart` y `app_theme.dart` en las pantallas (`scanner_screen.dart`, `scan_result_screen.dart`, `cash_closing_screen.dart`, `sell_plan_modal.dart`).
   - Reemplaza de raíz cualquier palabra prohibida ("canje", "transacción", "suscripción", "gestión", "procesar", "ítem") por el vocabulario permitido (`Validado`, `Le quedan 19`, `Pasar cartulina`, `Cerrar caja`, `Cuadra`, `Faltan $3,00`, `Sobran $1,50`).

REGLA: Trabaja únicamente en `features/owner/`. Ejecuta `flutter analyze` en `mobile/` al finalizar y asegura 0 errores.
```

---

### 3️⃣ Producción Backend (`main`) — Tareas 3.0 y 3.1: Cliente HTTP Dio, JWT & Autenticación Real

```text
Lee las reglas en @GEMINI.md y @docs/IDENTIDAD_BOCADOO.md. Estamos en `main`.

Implementa la infraestructura de red y autenticación para conectar la app a producción:
1. **Cliente HTTP y Seguridad (`mobile/lib/core/network/`):**
   - Crea `api_client.dart` utilizando `Dio`. Configura la URL base desde una variable de entorno/constante de producción, impón timeouts (10s) e implementa un `Interceptor` que adhiera el token Bearer JWT desde `FlutterSecureStorage`.
   - Implementa un manejador global de errores (`NetworkException`) que convierta fallos 401, 403, 404, 500 y falta de conexión a mensajes claros y amigables en español.
2. **Autenticación Real (`mobile/lib/core/auth/`):**
   - Crea `AuthRepository` y `authProvider` en Riverpod con soporte para `login(email, password)`, `register(...)`, `logout()` y verificación de validez de sesión.
   - Guarda el token JWT de forma segura y expón el estado del usuario actual (`Customer` u `Owner`).
3. **Control de Rutas (`app_router.dart`):**
   - Protege las rutas con `redirect` según el estado de autenticación y el rol del usuario, asegurando que un comensal no acceda al escáner de caja ni un dueño al pase de comida.

Ejecuta `flutter analyze` en `mobile/` al finalizar y confirma 0 errores.
```

---

### 4️⃣ Fase Final (`main`) — Auditoría Completa de Marca, Calidad y Compilación de Producción

```text
Lee @docs/IDENTIDAD_BOCADOO.md y @GEMINI.md. Estamos en `main` tras integrar `feat/customer` y `feat/owner`.

Realiza la auditoría final de calidad de producción en `mobile/lib/`:
1. **Auditoría Estricta de Diseño:** Confirma que no existan colores hexadecimales hardcodeados fuera de `core/theme/app_theme.dart`.
2. **Auditoría Estricta de Vocabulario:** Busca e imita cualquier aparición en UI de palabras prohibidas ("suscripción", "transacción", "canje", "redención", "gestión", "módulo", "dashboard", "procesar", "ítem").
3. **Formato Monetario Ecuatoriano:** Garantiza que todos los valores monetarios usen coma decimal (`$2,75`, `$55,00`, `$0,00`) y que el texto no baje de 13px.
4. **Resistencia del Escáner y QR:** Verifica que `BocadooQr` mantenga fondo `#FFFFFF` y módulos `#2D0050` tanto en tema claro como en oscuro.
5. **Verificación de Compilación:** Ejecuta `flutter analyze` (0 errores, 0 warnings) y `flutter test` en `mobile/`.
```
