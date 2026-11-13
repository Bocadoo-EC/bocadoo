# Identidad Visual y Manual de Marca — Bocadoo

> **Última revisión: 27 oct 2026** — paleta morada Material Design 3 con modo claro y oscuro.

## 1. Paleta de Colores Oficial (claro y oscuro)

**Fuente única de verdad: `src/styles.css`.** Los valores viven ahí una sola vez (`:root` = claro, `.dark` = oscuro) y se leen desde Tailwind (`bg-primary`, `text-muted-foreground`, …) y desde `landing.css`. Fuera de `styles.css` **no se escribe ningún hex** (la única excepción son los colores del QR, ver reglas).

La paleta se generó con Material Design 3 desde la semilla `#7B2CBF`. El primario oficial es **`#8234C6`** y el texto base es **`#2D0050`**.

| Token | Claro | Oscuro |
|---|---|---|
| `background` | `#F5ECFF` | `#1C1127` |
| `surface` (tarjetas) | `#FFFFFF` | `#2A1B3A` |
| `surface-nav` (barra inferior) | `#FFFFFF` | `#24172F` |
| `foreground` (texto) | `#2D0050` | `#F1DBFF` |
| `muted-foreground` | `#635C65` | `#CDB8E0` |
| `primary` | `#8234C6` | `#DEB7FF` |
| `primary-foreground` | `#FFFFFF` | `#4A007F` |
| `primary-hover` | `#680EAC` | `#F1DBFF` |
| `primary-container` | `#F1DBFF` | `#680EAC` |
| `on-primary-container` | `#2D0050` | `#F1DBFF` |
| `secondary-container` | `#EDDDF6` | `#4A007F` |
| `on-secondary-container` | `#211829` | `#F1DBFF` |
| `border` | `#CDC4CE` | `#4A454D` |
| `outline` (inputs) | `#7C757E` | `#968E98` |
| `input-bg` | `#FFFFFF` | `#2A1B3A` |
| `success` | `#157A41` | `#7FDC9F` |
| `success-container` | `#E6F6EC` | `#0F3D22` |
| `danger` | `#BA1A1A` | `#FFB4AB` |
| `danger-container` | `#FFDAD6` | `#93000A` |
| `on-danger-container` | `#410002` | `#FFB4AB` |
| `footer-bg` (landing) | `#2D0050` | `#120A1A` |
| `footer-accent` (eslogan) | `#DEB7FF` | `#DEB7FF` |
| `hero-gradient` | `linear-gradient(160deg,#9C51E1 0%,#8234C6 45%,#680EAC 100%)` | `linear-gradient(160deg,#8234C6 0%,#680EAC 45%,#2D0050 100%)` |
| `shadow-sm` | `0 2px 8px rgba(74,14,120,.06)` | `0 2px 8px rgba(0,0,0,.30)` |
| `shadow` | `0 12px 40px rgba(74,14,120,.10)` | `0 12px 40px rgba(0,0,0,.35)` |
| `shadow-lg` | `0 30px 80px rgba(74,14,120,.18)` | `0 30px 80px rgba(0,0,0,.45)` |
| `shadow-brand` (botón) | `0 10px 24px rgba(130,52,198,.35)` | sin sombra |

### Tokens derivados (decisiones de implementación)
La tabla no cubre todos los casos; estos se añadieron en `styles.css` para que ningún componente necesite un hex suelto:

| Token | Claro | Oscuro | Para qué |
|---|---|---|---|
| `success-foreground` | `#FFFFFF` | `#0F3D22` | Texto sobre `success` sólido |
| `danger-foreground` | `#FFFFFF` | `#690005` | Texto sobre `danger` sólido |
| `image-foreground` | `#FFFFFF` | `#FFFFFF` | Texto sobre fotos y sobre `hero-gradient` (siempre blanco) |
| `scrim` | = `footer-bg` | = `footer-bg` | Telón de modales (`bg-scrim/40`) |
| `qr-fg` / `qr-bg` | `#2D0050` / `#FFFFFF` | `#2D0050` / `#FFFFFF` | Colores del QR (idénticos en ambos temas) |
| `phone` | = `footer-bg` | = `footer-bg` | Marco del celular (morado profundo, nunca negro) |

Los tokens heredados de shadcn/Tailwind siguen existiendo y apuntan a la tabla: `card`→`surface`, `popover`→`surface`, `secondary`/`muted`→`secondary-container`, `accent`/`lavender`/`primary-soft`→`primary-container`, `destructive`→`danger`, `danger-soft`→`danger-container`, `input`→`outline`, `ring`→`primary`, `card-dark`→`footer-bg`, `showcase*`→mezcla de `background`/`foreground`.

### Reglas de aplicación
- **Encabezado del pase del comensal** (plan, almuerzos restantes, saldo, vencimiento): bloque a todo el ancho con `hero-gradient`, esquinas inferiores de 40 px y texto blanco. Debajo, la tarjeta del QR en `surface`, superpuesta unos 48 px sobre el degradado.
- **El QR va SIEMPRE sobre fondo blanco `#FFFFFF` y con módulos `#2D0050`**, también en modo oscuro (si no, no se puede escanear). Se dibuja con `BocadooQr` y su contenedor usa `bg-qr-bg`.
- **Barra de navegación inferior**: la pestaña activa lleva una pastilla `primary-container` con el ícono y la etiqueta en `on-primary-container`. Las pestañas inactivas van en `muted-foreground`.
- **Botón principal** (Escanear QR, Guardar y publicar plan, etc.): `primary` con texto `primary-foreground`. **Un solo elemento relleno de morado por grupo.** Las acciones secundarias van en `surface` con borde o en `primary-container`.
- **Chips de estado**: Validado = `success-container` + `success`; Renovar / Agotado / Error = `danger-container` + `on-danger-container`; Oferta = `primary` + `primary-foreground`.
- **Landing**: fondo general `surface`, secciones lila en `background`, hero en `primary-container`, bloque CTA en `primary` (claro) / `primary-container` (oscuro), footer en `footer-bg`. Los `.pill` y `.hl` usan `primary`.
- **Degradados** solo dentro de la familia morada. Nada de negro puro (`#000`) ni blanco puro como fondo de pantalla en oscuro.
- **Sombras**: en claro teñidas de morado, en oscuro negras; siempre desde los tokens `shadow-*`.
- **Nunca** hex, `rgb()`, `bg-white`, `text-black`, `bg-black` ni colores nombrados de Tailwind (`amber-*`, `emerald-*`…). `npm run lint:brand` lo verifica.
- **Contraste**: todo texto ≥ 4,5:1 sobre su fondo; borde de inputs (`outline`) ≥ 3:1.
- **Las fotos de comida no cambian** con el tema.

### Cambio de tema
- Estrategia por clase: `.dark` en `<html>`.
- Tres opciones: **Sistema** (por defecto, sigue `prefers-color-scheme`), **Claro** y **Oscuro**. La elección se guarda en `localStorage` con la clave `bocadoo-theme`.
- Un script inline en el `<head>` (`__root.tsx`) fija la clase antes del primer render: no hay parpadeo.
- API: hook `useTheme()` (`src/hooks/use-theme.ts`) y componente `ThemeToggle` (`src/components/theme/ThemeToggle.tsx`).
- El selector vive en Ajustes del comensal, en Ajustes del dueño (control Sistema / Claro / Oscuro) y en el navbar de la landing (botón sol/luna).
- Las transiciones de tema (`.2s`) se apagan con `prefers-reduced-motion`.

---

## 2. Tipografía y Escala
- **Familia**: `Plus Jakarta Sans`, pesos `400` (Regular), `500` (Medium), `600` (SemiBold), `700` (Bold), `800` (ExtraBold). Reemplaza a Outfit y browser defaults.
- **Mínimos de legibilidad**:
  - Metadatos y fechas: mínimo `13 px` (peso 600).
  - Texto de lectura y etiquetas: mínimo `15 px`.
  - Botones y acciones: mínimo `17 px` (peso 700 / 800).
  - Números protagonistas (saldo, total a cobrar, ticket): `32 px` a `48 px` (peso 800).
- **Prohibido**: `text-[7px]`, `text-[8px]`, `text-[9px]`, `text-[10px]`.

---

## 3. Radios y Formas
- **Botones**: Cápsula completa (`rounded-full` / `999px`). Alto mínimo en app `56 px` (en Caja `64 px`).
- **Tarjetas y Contenedores**: `rounded-[28px]` a `rounded-[32px]`.
- **Campos de Entrada (Inputs)**: `rounded-2xl` (`14–16 px`).

---

## 4. Tono, Vocabulario y Redacción
- **Regla de concisión**: 1 título de máximo 3 palabras, opcional 1 apoyo de máximo 8 palabras. Nada de párrafos explicativos.
- **Formato monetario**: Estilo Ecuador: `$2,75`, `$55,00`, `$0,00`.
- **Diccionario Permitido**:
  `Validado`, `Le quedan 19`, `Te quedan 14`, `Vence 30 oct`, `Último almuerzo`, `Sin almuerzos`, `Vencido`, `Es de otro local`, `Ya validado`, `Deshacer`, `Vender plan`, `Pasar cartulina`, `Guardar`, `Otra`, `Venta rápida`, `Cobrar $3,00`, `Efectivo`, `Transferencia`, `Para llevar`, `Comer aquí`, `Se acabó`, `Agotado`, `Repetir ayer`, `Publicar`, `Lleno`, `Libre`, `Movido`, `Cerrar caja`, `Cuadra`, `Faltan $3,00`, `Sobran $1,50`, `Almuerzos que debes`, `Quiero este`, `Paga en caja`, `Renovar`, `No fui yo`, `Devolver`, `Ahorras $5`, `Con amigos`, `Hoy en La Cuchara`, `Buscar restaurante`.
- **Palabras Prohibidas**:
  "suscripción", "transacción", "canje", "redención", "gestión", "módulo", "dashboard", "procesar", "ítem".

---

## 5. Inconsistencias resueltas
- **Inconsistencia 2 — Color de texto:** resuelta. El texto base oficial es `#2D0050` (`foreground` en claro; `#F1DBFF` en oscuro). Antes convivían `#4A0E78` y `#1F1135` en las clases, y `foreground` en negro puro (`oklch(0 0 0)`) en el tema.
- **Inconsistencia 4 — Morado primario:** resuelta. El primario oficial es `#8234C6`, generado con Material 3 desde la semilla `#7B2CBF` (`primary-hover` `#680EAC`). Antes convivían `#7B2CBF` (clases y landing), un primario `oklch` distinto en el tema y tres hover diferentes (`#6A22A9`, `#6A24A6`, `#6824A3`).
