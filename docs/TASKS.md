# 🚀 Master Execution Plan & Antigravity Prompts — Bocadoo Mobile

> **Stack:** Flutter (Dart) | Material Design 3 | Clean Architecture + MVVM  
> **Estrategia Git:** `main` (Core compartida) ➡️ `feat/customer` (James) | `feat/owner` (Carlos)

---

## 🛠️ 1. Configuración Obligatoria del Workspace (Para Ambos)

Antes de ejecutar cualquier prompt en Antigravity IDE:

1. Abre **Antigravity IDE** en la carpeta del proyecto `bocadoo`.
2. Ve al menú superior: **`File` > `Add Folder to Workspace...`**.
3. Selecciona la carpeta local donde tienes clonado el **PMV Web** (landing/web actual).
4. Verifica que ambas carpetas aparezcan en el panel explorador lateral. Esto permite que el agente de IA inspeccione pantallas, colores, modelos de datos y lógica directamente del código web existente.

---

## 🔀 2. Flujo de Trabajo en Git (Paralelo y Sin Conflictos)

```
                            ┌──> [feat/customer] (James)  ──> Prompts C1 a C4 ──┐
                            │                                                   ├──> PRs a main
 [main] (Fase 0 Completa) ──┤                                                   │
                            │                                                   │
                            └──> [feat/owner]    (Carlos) ──> Prompts O1 a O4 ──┘
```

### Comandos de inicio de rama (Ejecutar en la terminal de `bocadoo`):

* **James (Módulo Comensal):**
  ```powershell
  git checkout main
  git pull origin main
  git checkout -b feat/customer
  ```

* **Carlos (Módulo Dueño / Restaurante):**
  ```powershell
  git checkout main
  git pull origin main
  git checkout -b feat/owner
  ```

---

## 🔒 3. Reglas de Oro de Estructura

* ❌ **Prohibido modificar contratos globales:** No alteres archivos dentro de `lib/core/` sin coordinar antes.
* 🟢 **James trabaja únicamente en:** `lib/features/customer/` (y añade dependencias en `pubspec.yaml` si lo requiere).
* 🔵 **Carlos trabaja únicamente en:** `lib/features/owner/` (y añade dependencias en `pubspec.yaml` si lo requiere).
* ✅ **Verificación obligatoria:** Ejecutar siempre `flutter analyze` al finalizar cada prompt.

---

## 🍔 TRACK A: Módulo Comensal — James (`feat/customer`)

| Fase | Componentes / Archivos | Objetivo |
| :--- | :--- | :--- |
| **C1** | `mock_customer_repo.dart`, `customer_controller.dart` | Repositorio mock con datos del PMV Web y gestor de estado MVVM. |
| **C2** | `pase_screen.dart` | Pase digital, tarjeta con saldo 14/20, QR dinámico e historial. |
| **C3** | `restaurants_screen.dart` | Catálogo de restaurantes, filtros de categorías y modal de Menú del Día. |
| **C4** | Persistencia local offline | Caché en memoria / SharedPreferences para mostrar QR sin internet. |

---

### 🤖 Prompts para Antigravity — Track Comensal

#### 📌 Prompt C1 — Data Mock & Controller MVVM
```markdown
Lee las reglas en @GEMINI.md. Estamos en la rama `feat/customer`.
Inspecciona el código del PMV Web en este Workspace para extraer la estructura exacta de los datos del Comensal (planes activos, almuerzos disponibles/usados, historial de consumos, restaurantes y menú del día).

Implementa dentro de `bocadoo/mobile/lib/features/customer/`:
1. `data/mock_customer_repo.dart`: Implementa `ICustomerRepository` (definido en `core/contracts/repositories.dart`) con datos realistas idénticos al flujo del PMV Web, simulando latencia de red (`Future.delayed`) y manejo de errores.
2. `presentation/customer_controller.dart`: Gestor de estado (`ChangeNotifier` o `ValueNotifier`) que maneje los estados `Loading`, `Success` y `Error` sin bloquear la UI.

REGLA: No modifiques ningún archivo fuera de `features/customer/` (salvo `pubspec.yaml` si requiere paquetes). Ejecuta `flutter analyze` en `bocadoo/mobile` al terminar.
```

#### 📌 Prompt C2 — Pantalla del Pase Digital (`pase_screen.dart`)
```markdown
Lee las reglas en @GEMINI.md.
Inspecciona en el PMV Web la vista principal del Comensal (tarjeta de pase digital, contador de almuerzos restantes, barra de progreso, código QR dinámico y estado cuando el plan está agotado).

Implementa `bocadoo/mobile/lib/features/customer/presentation/pase_screen.dart`:
1. Replica la jerarquía visual, paleta morada Material 3 (modo claro y oscuro) y textos del PMV Web.
2. Renderiza el código QR dinámico del usuario usando el payload generado por `core/contracts/qr_parser.dart` (instala `qr_flutter` si hace falta).
3. Maneja los estados visuales: Carga (Shimmer), Pase Activo, Pase Agotado (con botón para ver/renovar planes) y Error.
4. Incluye botón desplegable (`showModalBottomSheet`) para el Historial de Consumos (`ConsumptionRecord`) y botón para cerrar sesión (`/login`).

REGLA: Trabaja exclusivamente dentro de `features/customer/`. Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt C3 — Catálogo de Restaurantes y Menú del Día (`restaurants_screen.dart`)
```markdown
Lee las reglas en @GEMINI.md.
Inspecciona en el PMV Web la vista de restaurantes afiliados, filtros, horarios y detalle del menú del día.

Implementa `bocadoo/mobile/lib/features/customer/presentation/restaurants_screen.dart`:
1. Muestra la lista de restaurantes afiliados con buscador (`TextField`), filtros rápidos con `ChoiceChip` (Todos, Ejecutivo, Veggie, Económico) y tarjetas estilizadas.
2. Al hacer tap en un restaurante, despliega un modal `showModalBottomSheet` con el Menú del Día categorizado (Sopa, Fuerte, Bebida, Postre).
3. Conecta la navegación fluida con `pase_screen.dart`.

REGLA: Trabaja exclusivamente dentro de `features/customer/`. Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt C4 — Persistencia Local Offline (Caché QR)
```markdown
Lee las reglas en @GEMINI.md.
Para garantizar que el comensal pueda presentar su QR en el restaurante aun sin señal/internet:

1. Actualiza `mock_customer_repo.dart` (o añade `local_customer_cache.dart` en `features/customer/data/`) usando `shared_preferences` para almacenar el último `CustomerPass` cargado y su token QR.
2. Si falla la red o no hay conexión, `pase_screen.dart` debe mostrar automáticamente el pase guardado en caché con un indicador discreto de "Modo Offline".
3. Asegura que las rutas `/customer/pase` y `/customer/restaurants` estén conectadas correctamente en `app_router.dart`.

Ejecuta `flutter analyze` y verifica que el flujo de Comensal compile con 0 errores.
```

---

### 📤 Subida Final de James
```powershell
git add .
git commit -m "feat(customer): modulo comensal completo con pase QR, restaurantes y soporte offline"
git push origin feat/customer
```

---

## 🏪 TRACK B: Módulo Dueño / Restaurante — Carlos (`feat/owner`)

| Fase | Componentes / Archivos | Objetivo |
| :--- | :--- | :--- |
| **O1** | `mock_owner_repo.dart`, `owner_controller.dart` | Lógica de validación QR, consumo de pases y métricas de caja. |
| **O2** | `scanner_screen.dart` | Escáner QR de alta velocidad con overlay, linterna e ingreso manual. |
| **O3** | `scan_result_screen.dart` | Vistas de resultado: Verde (Canje Exitoso) y Rojo (Rechazado/Sin saldo). |
| **O4** | `cash_closing_screen.dart`, `sell_plan_modal.dart` | Resumen de caja diaria, historial de ventas y modal para vender plan. |

---

### 🤖 Prompts para Antigravity — Track Dueño

#### 📌 Prompt O1 — Data Mock & Controller Dueño
```markdown
Lee las reglas en @GEMINI.md. Estamos en la rama `feat/owner`.
Inspecciona el código del PMV Web en este Workspace para extraer la lógica del Dueño/Restaurante (validación de QR, canje de almuerzos, métricas de caja y venta de nuevos planes).

Implementa dentro de `bocadoo/mobile/lib/features/owner/`:
1. `data/mock_owner_repo.dart`: Implementa `IOwnerRepository` (definido en `core/contracts/repositories.dart`). Simula validación de QR usando `core/contracts/qr_parser.dart`, control de doble escaneo y resumen de caja.
2. `presentation/owner_controller.dart`: Gestor de estado MVVM con estados `Idle`, `Scanning`, `Success` y `Error`.

REGLA: No modifiques ningún archivo fuera de `features/owner/` (salvo `pubspec.yaml` si requiere paquetes). Ejecuta `flutter analyze` en `bocadoo/mobile` al terminar.
```

#### 📌 Prompt O2 — Escáner QR (`scanner_screen.dart`)
```markdown
Lee las reglas en @GEMINI.md.
Inspecciona en el PMV Web la pantalla de escaneo del Dueño.

Implementa `bocadoo/mobile/lib/features/owner/presentation/scanner_screen.dart`:
1. Vista de lectura QR en dispositivo usando `mobile_scanner` (basado en ML Kit Barcode Scanning offline) con overlay animado y botón de linterna.
2. Incluye un botón "Simular Escaneo" (para pruebas en emulador) que pruebe un token válido y uno inválido/expirado.
3. Botón inferior "Ingresar Código Manualmente" con diálogo modal para escribir el token en caso de falla de cámara.
4. Al detectar un código, invoca `ownerController.validateQr()` y navega a `scan_result_screen.dart`.

REGLA: Trabaja exclusivamente dentro de `features/owner/`. Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt O3 — Resultado del Escaneo (`scan_result_screen.dart`)
```markdown
Lee las reglas en @GEMINI.md.
Inspecciona en el PMV Web las pantallas de confirmación y rechazo del escáner.

Implementa `bocadoo/mobile/lib/features/owner/presentation/scan_result_screen.dart`:
1. Caso Pase VÁLIDO (Verde): Muestra avatar del estudiante, nombre, plan actual, saldo restante (ej: "13/20 restantes") y botón "CONFIRMAR CANJE".
2. Caso Pase INVÁLIDO / SIN SALDO (Rojo): Muestra motivo del rechazo (ej: "Pase consumido hoy a las 12:45 PM") y botón directo "VENDER PLAN" que abre `sell_plan_modal.dart`.
3. Botón principal "Volver a Escanear".

REGLA: Trabaja exclusivamente dentro de `features/owner/`. Ejecuta `flutter analyze` al finalizar.
```

#### 📌 Prompt O4 — Cierre de Caja y Venta de Planes (`cash_closing_screen.dart` & `sell_plan_modal.dart`)
```markdown
Lee las reglas en @GEMINI.md.
Inspecciona en el PMV Web el dashboard de caja diaria y el modal para registrar ventas de planes.

Implementa dentro de `bocadoo/mobile/lib/features/owner/presentation/`:
1. `cash_closing_screen.dart`: Cards con métricas (Total Almuerzos Canjeados Hoy, Planes Vendidos, Ingresos Totales $), lista cronológica de transacciones y botón "Cerrar Caja".
2. `sell_plan_modal.dart`: BottomSheet con formulario para ID/Cédula del estudiante, selector de plan (10, 20 o 30 almuerzos), método de pago y botón "Registrar Venta".
3. Conecta las rutas `/owner/scanner`, `/owner/scan-result` y `/owner/cash-closing` en `app_router.dart`.

Ejecuta `flutter analyze` y confirma que la app de Dueño compile sin errores ni advertencias.
```

---

### 📤 Subida Final de Carlos
```powershell
git add .
git commit -m "feat(owner): modulo dueño completo con escaner ML Kit, resultado de canje y cierre de caja"
git push origin feat/owner
```

---

## 🎯 4. Checklist de Integración Final (Pull Request a `main`)

- [ ] **Fase 0:** Tema, modelos de datos, interfaces y login subidos a `main`.
- [ ] **James (`feat/customer`):** `flutter analyze` arroja `0 issues`. Pantalla de pase QR, catálogo y caché offline verificados.
- [ ] **Carlos (`feat/owner`):** `flutter analyze` arroja `0 issues`. Escáner QR, pantalla verde/roja, cierre de caja y venta de planes verificados.
- [ ] **Integración en GitHub:** Crear Pull Request de `feat/customer` ➡️ `main` y `feat/owner` ➡️ `main`.
