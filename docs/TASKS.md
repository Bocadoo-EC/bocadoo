# 📋 Plan de Ejecución por Fases — Bocadoo Mobile (Flutter)

> **Documento de Control y Tareas — Bocadoo PMV**
> **Stack:** Flutter (Dart) | Material Design 3 | Riverpod | GoRouter | Dio
> **Fuente de verdad de diseño:** `docs/IDENTIDAD_BOCADOO.md`
> **Referencia Web:** Workspace `pmv/inspo-palette-creation`
> **Flujo Git:** `main` (Core compartido) ➡️ `feat/customer` (James) | `feat/owner` (Carlos)

---

## 📊 Estado Actual del Proyecto

### 🎨 FASE 0: Sistema de Diseño, Tokens y Core (`main`)
- [x] **0.1 Configuración de Tokens y Tema (`app_theme.dart`)** — Paleta clara/oscura M3 (`#8234C6` / `#DEB7FF`), `BocadooColors` ThemeExtension, gradientes `heroGradient` y colores fijos del QR (`#2D0050` sobre `#FFFFFF`).
- [x] **0.2 Tipografía y Radios Globales** — `google_fonts` (`Plus Jakarta Sans`), escala tipográfica oficial (13px metadatos, 15px lectura, 17px botones, 32–48px números protagonistas) y radios globales (cápsula 999px, tarjetas 28px, inputs 16px).
- [x] **0.3 Componentes Atómicos (`lib/core/widgets/`)** — `BocadooButton`, `BocadooHeader`, `BocadooQr`, `StatusChip` y `BocadooBottomNavBar` exportados desde `core/widgets/widgets.dart`.
- [ ] **0.4 Provider Global de Tema & Permisos iOS** — `ThemeMode` persistente (Sistema/Claro/Oscuro) en `main.dart` y `NSCameraUsageDescription` en `ios/Runner/Info.plist`.

### 👤 FASE 1: Módulo Comensal — James (`feat/customer`)
- [x] **1.1 Catálogo de Restaurantes (`restaurants_screen.dart`)** — Buscador, `ChoiceChip` de filtros, tarjetas con foto/ocupación/distancia/precio y modal de Menú del Día categorizado.
- [x] **1.2 Pantalla Mi Pase y Modo Offline (`pase_screen.dart`)** — Hero gradient, contador `14 / 20`, QR rotativo `BCD1`, shimmer, estado agotado, historial en bottom sheet y persistencia offline con `shared_preferences`.
- [ ] **1.3 Flujo de Adquisición y Renovación de Plan** — Modal/pantalla para elegir plan y confirmar usando vocabulario oficial (*"Quiero este"*, *"Paga en caja"*, *"Renovar"*).
- [ ] **1.4 Perfil, Ajustes y Navegación Comensal** — `ThemeToggle` (Sistema/Claro/Oscuro), acciones de historial (*"No fui yo"* / *"Devolver"*) y `BocadooBottomNavBar` compartida.

### 🏪 FASE 2: Módulo Dueño — Carlos (`feat/owner`)
- [x] **2.0 Pantallas Base del Dueño** — `scanner_screen.dart`, `scan_result_screen.dart`, `cash_closing_screen.dart` y `sell_plan_modal.dart` implementadas en `lib/features/owner/presentation/`.
- [ ] **2.1 Ajustes, Control de Menú y Auditoría en `features/owner/`** — `ThemeToggle`, publicación rápida del menú (*"Repetir ayer"*, *"Publicar"*, *"Agotado"*), migración de importación a `package:material_ui/material_ui.dart` y limpieza de vocabulario prohibido.

### 🔬 FASE FINAL: Auditoría de Marca y Calidad (`main`)
- [ ] **F.1 Auditoría Total de Marca (`IDENTIDAD_BOCADOO.md`)** — Cero hex fuera de `app_theme.dart`, cero palabras prohibidas en toda la app y verificación final (`flutter analyze` + `flutter test`).

---

## 🤖 Prompts Autocontenidos Listos para Copiar y Pegar

### 1️⃣ En `main` — Tarea 0.4: Provider Global de Tema & Permisos iOS
```text
Lee las reglas en @GEMINI.md y @docs/IDENTIDAD_BOCADOO.md. Estamos en la rama `main`.

Implementa:
1. `mobile/lib/core/theme/theme_provider.dart`: Crea un `NotifierProvider<ThemeModeNotifier, ThemeMode>` con Riverpod que persista la preferencia del usuario (`system`, `light`, `dark`) usando `shared_preferences` bajo la clave `bocadoo-theme` (por defecto `ThemeMode.system`), y crea el widget reutilizable `ThemeToggle` en `mobile/lib/core/widgets/theme_toggle.dart`.
2. Conecta `themeMode: ref.watch(themeModeProvider)` en `mobile/lib/main.dart`.
3. Verifica `mobile/ios/Runner/Info.plist` y agrega `NSCameraUsageDescription` con un mensaje claro en español para el escáner QR del dueño.

Al terminar, ejecuta `flutter analyze` y `flutter test` en `mobile/` y confirma 0 errores.
```

---

### 2️⃣ Para James (`feat/customer`) — Tareas 1.3 y 1.4: Planes, Ajustes y BottomNavBar
```text
Lee las reglas en @GEMINI.md y @docs/IDENTIDAD_BOCADOO.md. Estamos en la rama `feat/customer`.
Inspecciona en el PMV Web (`pmv/inspo-palette-creation`) las vistas de adquisición de planes y perfil/ajustes del comensal.

Implementa dentro de `mobile/lib/features/customer/`:
1. **Tarea 1.3 (Adquisición / Renovación de Plan):**
   - Crea `presentation/plan_checkout_modal.dart` (o intégralo en `restaurants_screen.dart` y `pase_screen.dart`) para seleccionar un paquete de almuerzos (5, 10 o 20) desde la ficha del restaurante o desde el botón "Renovar".
   - Usa exclusivamente el vocabulario oficial permitido: "Quiero este", "Paga en caja", "Renovar", "Ahorras $5" y formato monetario Ecuador (`$2,75`, `$55,00`). Cero palabras prohibidas.
2. **Tarea 1.4 (Perfil, Ajustes y Navegación):**
   - Crea `presentation/customer_profile_screen.dart` con `ThemeToggle` (Sistema / Claro / Oscuro) y opciones en el historial de consumos con los textos oficiales "No fui yo" y "Devolver".
   - Integra `BocadooBottomNavBar` (de `core/widgets/widgets.dart`) con pastilla `primaryContainer` para navegar entre Mi Pase, Dónde comer y Ajustes.

REGLA: Trabaja únicamente en `features/customer/` (y conecta la ruta en `app_router.dart` avisando en el resumen). Ejecuta `flutter analyze` en `mobile/` al finalizar.
```

---

### 3️⃣ Para Carlos (`feat/owner`) — Tarea 2.1: Ajustes, Menú del Día y Limpieza en `features/owner/`
```text
Lee las reglas en @GEMINI.md y @docs/IDENTIDAD_BOCADOO.md. Estamos en la rama `feat/owner`.
Inspecciona en el PMV Web (`pmv/inspo-palette-creation`) las vistas de menú del día y ajustes del dueño.

Implementa y actualiza dentro de `mobile/lib/features/owner/`:
1. **Control de Menú del Día (`presentation/owner_menu_screen.dart`):**
   - Permite ingresar o actualizar los platos de hoy (Sopa, Fuerte, Jugo, Postre) con botones rápidos oficiales: "Repetir ayer", "Publicar" y botón de pánico "Se acabó" / "Agotado".
2. **Ajustes del Dueño (`presentation/owner_settings_screen.dart`):**
   - Incluye el selector de tema `ThemeToggle` (Sistema / Claro / Oscuro) y estado de apertura del local.
3. **Limpieza y Vocabulario en `features/owner/`:**
   - Reemplaza `package:flutter/material.dart` por `package:material_ui/material_ui.dart` en las pantallas existentes (`scanner_screen.dart`, `scan_result_screen.dart`, `cash_closing_screen.dart`, `sell_plan_modal.dart`).
   - Reemplaza cualquier palabra prohibida ("canje", "transacción", "suscripción", "gestión", "procesar", "ítem") por el diccionario permitido (`Validado`, `Le quedan 19`, `Pasar cartulina`, `Cerrar caja`, `Cuadra`, `Faltan $3,00`, `Sobran $1,50`).

REGLA: Trabaja únicamente en `features/owner/`. Ejecuta `flutter analyze` en `mobile/` al finalizar.
```

---

### 4️⃣ Fase Final (`main`) — Auditoría Completa de Marca y Calidad
```text
Lee @docs/IDENTIDAD_BOCADOO.md y @GEMINI.md. Estamos en `main` tras integrar `feat/customer` y `feat/owner`.

Realiza la auditoría final de marca y calidad en `mobile/lib/`:
1. Verifica que no existan colores hexadecimales hardcodeados fuera de `core/theme/app_theme.dart`.
2. Busca y elimina cualquier aparición visible al usuario de las palabras prohibidas: "suscripción", "transacción", "canje", "redención", "gestión", "módulo", "dashboard", "procesar", "ítem".
3. Verifica que todos los montos monetarios usen coma decimal estilo Ecuador (`$2,75`, `$55,00`, `$0,00`) y que ningún texto sea menor a 13px.
4. Verifica que `BocadooQr` mantenga fondo `#FFFFFF` y módulos `#2D0050` tanto en tema claro como en oscuro.
5. Ejecuta `flutter analyze` (0 errores, 0 warnings) y `flutter test` en `mobile/`.
```
