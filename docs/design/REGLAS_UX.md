# Reglas UX de Bocadoo (mobile Flutter)

> Documento de trabajo para `docs/design/REGLAS_UX.md`. Fuente de verdad visual: `identidad-visual/tokens.json` y las capturas de `docs/design/`. Si este archivo y las capturas se contradicen, mandan las capturas y se avisa.
> Estado: **borrador**. Las decisiones marcadas con (pendiente) necesitan confirmación de Carlos.

## 1. Color
Usa solo los tokens de `tokens.json` a través del tema. Nunca escribas `Color(0x...)` ni `Colors.*` en `presentation/`.

| Token | Claro | Uso |
|---|---|---|
| brand | #7B2CBF | Botón principal, palabra resaltada, íconos, enlaces |
| lila | #E0AAFF | Degradado del hero, píldoras, detalles |
| structure | #4A0E78 | Titulares y texto principal (decisión: se usa este, no negro) |
| surface-soft | #F5F3FA | Fondo de pantalla y secciones |
| surface | #FFFFFF | Tarjetas y fondo base |
| success / warning | #1F7A4D / #9A5700 | Solo estados: validado/pagado y pendiente/por vencer |
| danger | #B3261E | Solo errores y acciones de borrar |

- Un solo botón morado relleno por pantalla. El resto son secundarios.
- Verde solo para validado, pagado o disponible. Rojo solo para error o borrar.
- Degradados solo de lila a morado a morado oscuro.
- Tema oscuro: usa los tokens oscuros de `tokens.json`.

## 2. Tipografía
- Familia única: **Plus Jakarta Sans** (la de `tokens.json`). (pendiente: confirmar que el prototipo en Outfit se descarta.)
- Escala: display 56, h1 40, h2 28, h3 20, cuerpo 16, etiqueta 14, pequeño 13, cifras 32 con números tabulares.
- **Mínimo 13 px** para cualquier texto visible. (pendiente: confirmar que se descarta el 9 a 11 px del prototipo React.)
- Títulos en 800 o 700. Sin mayúsculas sostenidas en botones ni badges.
- Palabra resaltada: una sola por titular, dentro de una píldora `pill-bg`. Nunca dos.

## 3. Forma, espacio y sombra
- Botones, badges, chips y navbar: cápsula (radio 999).
- Tarjetas grandes: 28. Tarjetas pequeñas y de plan: 18. Inputs e íconos internos: 10.
- Espaciado en pasos de 4: 4, 8, 12, 16, 24, 32, 48, 80.
- Una sombra: `shadow-soft`, teñida de morado. Solo para lo que flota (tarjeta de plan, navbar).
- Una tarjeta destacada por grupo.

## 4. Logo e íconos
- Logo: SVG de `identidad-visual/logos/`. Versión blanca sobre morado u morado oscuro, a color sobre fondos claros. (pendiente: confirmar que el wordmark manuscrito del landing no se usa en la app.)
- Tamaño mínimo: isotipo 24 px, wordmark 120 px de ancho.
- Íconos de trazo redondeado, en `brand`, dentro de un cuadrado `tint` con radio 10.

## 5. Tono y texto
- Español de Ecuador, tuteo siempre ("tú").
- Frases cortas. Nombra objetos reales: plan, almuerzo, caja, fila, cuaderno.
- Vocabulario permitido: restaurante, comensal, plan, almuerzo, validar, caja.
- Vocabulario prohibido en la UI: transacción, canje, merchant, usuario B2B, delivery, fintech, ecosistema.
- Botones en verbo + objeto: "Escanear QR", "Vender plan", "Guardar cambios".
- Errores que dicen qué hacer: "Escribe el nombre del plato."
- Estados vacíos en tono amable, con una acción.
- Montos en dólares con coma decimal: $55, $39,20, $1.320.
- Fechas cortas: 30/10. Horas: 12:45.
- Sin emojis en titulares.

## 6. Pantallas y navegación
- Comensal: barra inferior con Mi Pase, Dónde comer y Ajustes.
- Dueño: barra inferior con Escáner, Caja, Menú y Ajustes. "Vender plan" entra desde Caja o desde un resultado de escaneo.
- Todo `onPressed` va conectado a GoRouter. Lo que dependa del backend se deja como `// TODO: Conectar con provider de backend`.
- Un estado de carga, error y vacío por pantalla, con botón "Reintentar" en error.

## 7. Accesibilidad
- Área táctil mínima de 48 px.
- Contraste de texto según `tokens.json` (texto principal sobre superficie y texto secundario sobre superficie).
- Respeta el modo oscuro y tamaños de pantalla distintos (LayoutBuilder o MediaQuery).
- No dependas solo del color para indicar un estado: acompáñalo con texto o ícono.

## 8. Flujo de trabajo para cambios de UX
1. Captura de la pantalla en `docs/design/` y descripción del flujo: qué botón lleva a dónde, qué campos y validaciones.
2. Cambio en `presentation/` y tema. No tocar controladores, repositorios ni modelos desde la rama de UX.
3. `flutter analyze` sin advertencias.
4. Captura en el emulador antes de hacer commit.
5. Commit y push a la rama de UX.

## 9. Decisiones tomadas en este borrador (pendiente de confirmar)
1. Plus Jakarta Sans como única tipografía.
2. `#4A0E78` como color de texto principal.
3. Mínimo de texto de 13 px.
4. Logo SVG de `identidad-visual/logos/`.
5. "Tu almuerzo, sin cartulinas" como eslogan principal.
