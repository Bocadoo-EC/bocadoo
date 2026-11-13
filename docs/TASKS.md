# 📋 Master Task Breakdown & Antigravity Prompts — Bocadoo Mobile

**Stack:** Flutter (Dart), Material Design 3, Clean Architecture + MVVM  
**Ramas Git:** `main` (Core) ➡️ `feat/customer` (James) | `feat/owner` (Carlos)

---

## 🧭 Regla de Trabajo en Paralelo (Flujo de Git)

```
                       ┌──> [feat/customer] (James) ──> Fases Comensal (C1-C5) ──┐
                       │                                                         ├──> PRs a main
[main] ──> FASE 0 ─────┤                                                         │
 (Core Compartido)     │                                                         │
                       └──> [feat/owner]    (Carlos) ──> Fases Dueño (O1-O5) ────┘
```

1. **Paso Inicial (James):** En `main`, Antigravity lee el PMV web del workspace y ejecuta la **FASE 0**. Se hace `git push origin main`.
2. **Paso Siguiente (Carlos):** Hace `git pull origin main`, crea su rama `git checkout -b feat/owner` y ejecuta sus **Prompts de Dueño (O1 a O5)**.
3. **Paso Siguiente (James):** En su terminal crea `git checkout -b feat/customer` y ejecuta sus **Prompts de Comensal (C1 a C5)**.

---

## ⚙️ FASE 0: Core Compartido & Auditoría (Ejecutar en `main`)

### Resumen de Trabajo
- Leer colores, componentes, textos y modelos del PMV Web agregado al Workspace.
- Actualizar `app_theme.dart` (paleta morada clara/oscura).
- Llenar `models.dart` y `repositories.dart` (interfaces globales).
- Llenar `qr_parser.dart` y `api_config.dart`.
- Conectar `app_router.dart` y `login_screen.dart` (pantalla de selección de rol o inicio de sesión).

### 🤖 Prompt para Antigravity (FASE 0 — James)
> Copia y pega esto en Antigravity estando en la rama `main`:

```text
Lee las reglas del proyecto en @GEMINI.md antes de escribir cualquier código.

Revisa los archivos del PMV Web que está montado en el Workspace para extraer los colores exactos, logos, textos, tipos de datos y payloads de QR.

Ejecuta la FASE 0 del proyecto Flutter en bocadoo/mobile/lib/:

1. `core/theme/app_theme.dart`: Define la paleta de colores del PMV Web (modo claro y oscuro M3).
2. `core/contracts/models.dart`: Crea los data models inmutables (CustomerPass, Restaurant, MenuItem, ConsumptionRecord, OwnerStore, ScanResult, TransactionSummary).
3. `core/contracts/repositories.dart`: Define las interfaces abstractas ICustomerRepository e IOwnerRepository.
4. `core/contracts/qr_parser.dart`: Lógica para validar y extraer el token/payload del QR escaneado.
5. `core/router/app_router.dart` y `main.dart`: Configura las rutas iniciales y el tema.
6. `features/auth/presentation/login_screen.dart`: Implementa la pantalla de Login con opción de ingresar como Comensal o como Dueño de restaurante.

Requisitos estrictos: No modifiques nada dentro de `features/customer/` ni `features/owner/`. Al terminar, ejecuta `flutter analyze` en `mobile/` y confirma que compile sin errores.
```

---

## 🍔 TRACK A: Comensal / Customer (James) — Rama `feat/customer`

### Lista de Fases y Archivos
* **Archivos asignados:** `features/customer/data/*` y `features/customer/presentation/*`

| Fase | Archivo / Componente | Descripción |
| :--- | :--- | :--- |
| **C1** | `mock_customer_repo.dart` | Repositorio mock con datos simulados del PMV (Pase, Restaurantes, Menú, Historial). |
| **C2** | `customer_controller.dart` | Controller/State notifier para manejar `CustomerUiState` (Loading, Success, Error). |
| **C3** | `pase_screen.dart` | Pantalla principal: Tarjeta morada de saldo, QR dinámico con animación/timer y modal de historial. |
| **C4** | `restaurants_screen.dart` | Catálogo de restaurantes con filtro por categorías, buscador y modal del menú del día. |
| **C5** | Persistencia Offline & Router | Guardar último QR/Pase cargado para visualización offline sin red y probar flujo completo. |

---

### 🤖 Prompts para Antigravity — Comensal (James)

#### 📌 Prompt C1 + C2: Data Mock & Controller
```text
Lee las reglas en @GEMINI.md y el contrato ICustomerRepository en `mobile/lib/core/contracts/repositories.dart`.

Estamos en la rama `feat/customer`. Implementa:

1. `mobile/lib/features/customer/data/mock_customer_repo.dart`:
   - Implementa `ICustomerRepository`.
   - Simula delays de 400ms con `Future.delayed`.
   - Retorna datos realistas del PMV Web: Un CustomerPass activo (14/20 almuerzos), 4 restaurantes universitarios con fotos Unsplash, sus menús por categoría (Sopa, Principal, Bebida) y un historial de consumos.

2. `mobile/lib/features/customer/presentation/customer_controller.dart`:
   - Crea `CustomerController` usando `ValueNotifier<CustomerUiState>` o `ChangeNotifier`.
   - Maneja los estados: Initial, Loading, Success, Error.
   - Incluye métodos: `loadDashboard()`, `refreshQr()`, `filterRestaurants(query)`.

Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt C3: Pantalla del Pase Digital (`pase_screen.dart`)
```text
Lee las reglas en @GEMINI.md y revisa la vista de comensal en el PMV Web del Workspace.

Construye `mobile/lib/features/customer/presentation/pase_screen.dart`:

1. Top bar con foto de perfil, saludo al usuario y Badge "PLAN ACTIVO".
2. Card principal morada (`AppTheme.primaryPurple`) con gradiente, mostrando "14 / 20 Almuerzos", barra de progreso redondeada y fecha de vencimiento.
3. Card central contenedora del Código QR (usa un generador visual de QR o `CustomPainter` limpio) con un contador regresivo de validez ("Se actualiza en 45s") y botón "🔄 Actualizar QR".
4. Botón inferior para abrir un `showModalBottomSheet` con el historial de consumos (`ConsumptionRecord`).
5. Botón de acceso directo al catálogo de restaurantes.

Conecta esta pantalla con `CustomerController`. Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt C4 + C5: Catálogo de Restaurantes, Menús y Caché Offline (`restaurants_screen.dart`)
```text
Lee las reglas en @GEMINI.md y revisa la vista de restaurantes en el PMV Web.

Implementa:

1. `mobile/lib/features/customer/presentation/restaurants_screen.dart`:
   - Buscador (`TextField`) y filtros con `ChoiceChip` (Todos, Ejecutivo, Veggie, Cerca).
   - Lista de restaurantes en tarjetas con imagen, rating de estrellas, distancia en km y badge de estado.
   - Al tocar un restaurante, abre `showModalBottomSheet` con el Menú del Día categorizado (Entrada, Plato Fuerte, Bebida, Postre).

2. Caché local en `mock_customer_repo.dart`:
   - Guarda el último `CustomerPass` en memoria/preferencias para que el QR sea visible inmediatamente si no hay conexión a internet.

3. Verifica que en `app_router.dart` las rutas `/customer/pase` y `/customer/restaurants` abran estas pantallas.

Ejecuta `flutter analyze` y confirma que la interfaz del Comensal esté lista.
```

---

## 🏪 TRACK B: Dueño de Restaurante / Owner (Carlos) — Rama `feat/owner`

### Lista de Fases y Archivos
* **Archivos asignados:** `features/owner/data/*` y `features/owner/presentation/*`

| Fase | Archivo / Componente | Descripción |
| :--- | :--- | :--- |
| **O1** | `mock_owner_repo.dart` | Repositorio mock con validación de QR, registro de ventas y cierre de caja. |
| **O2** | `owner_controller.dart` | Controller/State notifier para el flujo de escaneo, cobro y métricas del día. |
| **O3** | `scanner_screen.dart` | Vista del escáner QR usando cámara/ML Kit con marco guía, flash y entrada manual de código. |
| **O4** | `scan_result_screen.dart` | Pantalla de resultado: Modal de éxito (verde) con datos del estudiante o error (rojo) si ya fue canjeado. |
| **O5** | `cash_closing_screen.dart` & `sell_plan_modal.dart` | Dashboard de cierre de caja (métricas del día, almuerzos canjeados, ingresos) y modal para vender plan nuevo. |

---

### 🤖 Prompts para Antigravity — Dueño (Carlos)

#### 📌 Prompt O1 + O2: Data Mock & Controller Dueño
```text
Lee las reglas en @GEMINI.md y el contrato IOwnerRepository en `mobile/lib/core/contracts/repositories.dart`.

Estamos en la rama `feat/owner`. Implementa:

1. `mobile/lib/features/owner/data/mock_owner_repo.dart`:
   - Implementa `IOwnerRepository`.
   - Simula la validación de un QR (si el token contiene "INVALID", retorna error de pase expirado o ya usado; de lo contrario, confirma el canje).
   - Retorna métricas del cierre de caja del día (ej. 42 almuerzos servidos, 3 planes vendidos, total $168.00).

2. `mobile/lib/features/owner/presentation/owner_controller.dart`:
   - Controller con `ValueNotifier` o `ChangeNotifier`.
   - Métodos: `validateQrCode(String code)`, `confirmRedeem(String passId)`, `sellPlan(String userCode, String planId)`, `loadCashClosing()`.

Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt O3: Escáner QR del Dueño (`scanner_screen.dart`)
```text
Lee las reglas en @GEMINI.md y revisa la vista del escáner en el PMV Web del Workspace.

Construye `mobile/lib/features/owner/presentation/scanner_screen.dart`:

1. Vista de cámara con marco superpuesto (Overlay estilizado) para centrar el QR. Usa `mobile_scanner` o simulación visual interactiva de cámara con animación de escaneo.
2. Botones flotantes de control: Activar/Desactivar Linterna (Flash) y Cambiar Cámara.
3. Botón inferior "Ingresar Código Manualmente" que despliega un diálogo para escribir el código si el QR no se lee bien.
4. Al detectar un código válido, navega a `ScanResultScreen`.
5. Botón de navegación flotante o appbar para ir al "Cierre de Caja".

Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt O4: Resultado del Escaneo (`scan_result_screen.dart`)
```text
Lee las reglas en @GEMINI.md y revisa las pantallas de respuesta del PMV Web.

Construye `mobile/lib/features/owner/presentation/scan_result_screen.dart`:

1. Si el pase es VÁLIDO:
   - Tarjeta verde de Éxito con icono `Icons.check_circle_outline`.
   - Foto del estudiante, nombre, carrera y plan activo.
   - Mensaje claro: "Almuerzo disponible (Restantes: 13/20)".
   - Botón grande "CONFIRMAR CANJE" que descuenta el almuerzo y regresa al escáner.

2. Si el pase es INVÁLIDO / YA USADO HOY:
   - Tarjeta roja de Advertencia con icono `Icons.cancel_outlined`.
   - Causa del rechazo (ej. "Este pase ya fue canjeado hoy a las 12:45 PM" o "Saldo insuficiente").
   - Botón "Volver a Escanear".

Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt O5: Cierre de Caja y Venta de Planes (`cash_closing_screen.dart` & `sell_plan_modal.dart`)
```text
Lee las reglas en @GEMINI.md y las vistas de caja/métricas del PMV Web.

Implementa:

1. `mobile/lib/features/owner/presentation/cash_closing_screen.dart`:
   - Tarjetas de resumen del día: Total de Almuerzos Canjeados hoy, Planes Vendidos, Ingresos Totales.
   - Lista detallada de últimas transacciones del día con hora y nombre del usuario.
   - Botón "Vender Nuevo Plan" que abre `sell_plan_modal.dart`.
   - Botón "Realizar Cierre de Caja".

2. `mobile/lib/features/owner/presentation/sell_plan_modal.dart`:
   - Modal para ingresar código/cédula del estudiante, seleccionar tipo de plan (10, 20 o 30 almuerzos) y método de pago (Efectivo / Transferencia).
   - Botón "Registrar Venta".

3. Conecta las rutas `/owner/scanner`, `/owner/scan-result` y `/owner/cash-closing` en `app_router.dart`.

Ejecuta `flutter analyze` y confirma que la interfaz del Dueño compile perfectamente.
```

---

## 🛠️ Checklist Final de Integración antes del Merge a `main`

- [ ] **James (`feat/customer`):**
  - [ ] Compila sin errores (`flutter analyze`).
  - [ ] El pase morado muestra 14/20 almuerzos y QR en movimiento.
  - [ ] Muestra restaurantes y su menú al tocar.
  - [ ] Funciona en modo offline cargando el QR desde caché.

- [ ] **Carlos (`feat/owner`):**
  - [ ] Compila sin errores (`flutter analyze`).
  - [ ] Escáner lee o simula códigos QR.
  - [ ] Pantalla de resultado verde (éxito) y roja (error) funcionan.
  - [ ] Cierre de caja muestra estadísticas e historial de transacciones.
  - [ ] Modal permite registrar ventas de planes nuevos.

- [ ] **Merge:** Ambas ramas hacen Pull Request a `main` sin ningún conflicto de archivos.
