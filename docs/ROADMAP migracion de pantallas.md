# Roadmap de migración: prototipo React → Flutter

Estado: **listo para empezar**, con las condiciones de la sección 6. Alcance: 34 pantallas. Responsable de owner: Carlos. Responsable de customer: James.

Documentos relacionados:
- Flujo de cada botón, destino y petición: `Fichas de migracion pantallas react-flutter/FLUJO_PANTALLAS.md`
- Adaptación de las directrices del curso a Flutter: `docs/directrices_proyecto_proyecto_movil (1).md`, sección 5

## 1. Cómo se organiza

- **Fase** = carpeta. Son 7 fases (0 a 6).
- **Sub-fase** = un archivo de ficha. Agrupa las pantallas que se conectan por navegación (un flujo).
- **Ficha** = un `.md` por sub-fase con tres partes:
  - **Copia del MVP:** flujo, botones, estados y textos del prototipo.
  - **Ajustes de Carlos:** cambios finales que se aplican sobre la copia. Si no hay ajustes, se copia tal cual.
  - **Estado en Flutter:** qué existe hoy y qué falta.

Una ficha por fase sería demasiado grande para Gemini y mezclaría flujos sin relación. Una ficha por pantalla sería demasiado fina y perdería las transiciones.

## 2. Flujo de trabajo por sub-fase

Unidad de trabajo: la sub-fase (por ejemplo, 1.1 Login). Cada pantalla se nombra con su ID de `FLUJO_PANTALLAS.md` (A1 a A7, C1 a C11, O1 a O16). Carlos, Gemini y Claude Code usan ese ID para referirse a la misma pantalla.

1. **Ficha (Claude).** Lee el `.tsx`, el `copy.ts` del prototipo y el código Flutter actual. Escribe la ficha de la sub-fase con las tres partes de la sección 1: copia del MVP, botones con destino y petición lógica, y estado en Flutter.
2. **Ajustes (Carlos).** Revisa la ficha y anota sus cambios en "Ajustes de Carlos". Si no hay cambios, queda la copia del MVP.
3. **Prompt (Gemini).** Recibe la ficha aprobada, las capturas de las pantallas de la sub-fase (con su ID) y `docs/design/REGLAS_UX.md`. Devuelve un prompt de implementación. No inventa botones ni rutas que no estén en la ficha.
4. **Revisión del prompt (Carlos).** Verifica que cumpla la sección 4 y que los IDs coincidan con la ficha.
5. **Implementación (Claude Code).** Recibe el prompt y las mismas capturas. Cambia solo `presentation/` de la sub-fase, las rutas en `app_router.dart` y deja `// TODO` donde falte backend.
6. **Verificación.** `flutter analyze` sin errores y compilación. La captura en emulador la toma Carlos.
7. **Commit.** Un commit por sub-fase, con el ID en el mensaje (por ejemplo, `feat(auth): migra 1.1 Login (A1-A3)`).
8. **Aviso a James.** Si la sub-fase toca `core/` o `features/auth/`, se le avisa antes del commit.

Por qué la ficha va antes de Gemini: Gemini solo ve capturas y lo que se le explique. Sin ficha puede inventar botones o rutas, y la ficha es lo que mantiene el prompt cerca del MVP.

## 3. Fases y sub-fases

Las rutas de las 34 pantallas ya están declaradas en `app_router.dart`. Las que no tienen diseño muestran el marcador "Pantalla pendiente de migración".

| Fase | Sub-fase | Pantallas (ID y nombre) | Estado hoy | Responsable |
|---|---|---|---|---|
| 0. Base | 0.1 Reglas y navegación | O1 Caja (login del dueño → Caja, hecho en v0) | Rutas declaradas. Caja v0 creada | Core (avisar a James) |
| 1. Auth | 1.1 Login | A1 Login, A2 Olvidé contraseña, A3 Cuenta de Google | Login parcial | Compartido |
| | 1.2 Registro | A4 Registro comensal, A5 Registro dueño | Pendiente | Compartido |
| | 1.3 Onboarding | A6 Bienvenida comensal, A7 Bienvenida dueño | Pendiente | Compartido |
| 2. Customer núcleo | 2.1 Mi Pase | C1 Mi Pase (home comensal) | Parcial | James |
| | 2.2 Dónde comer | C2 Dónde comer, C3 Ficha del local | Parcial | James |
| | 2.3 Planes | C4 Planes, C5 Detalle del plan | Pendiente | James |
| 3. Owner núcleo | 3.1 Caja | O1 Caja (home dueño) | Caja v0 | Carlos |
| | 3.2 Escáner | O2 Escanear pase y resultado | Existe | Carlos |
| | 3.3 Venta y cobro | O3 Vender plan, O4 Cobro suelto | Parcial / Pendiente | Carlos |
| | 3.4 Cierre | O13 Cierre de caja | Parcial | Carlos |
| 4. Owner gestión | 4.1 Menú | O7 Menú de hoy | Parcial | Carlos |
| | 4.2 Planes y clientes | O8 Planes y clientes, O9 Crear o editar plan | Pendiente | Carlos |
| | 4.3 Registrar consumo | O6 Registrar consumo (POS) | Pendiente | Carlos |
| | 4.4 Ajustes | O16 Ajustes | Parcial | Carlos |
| 5. Customer social | 5.1 Mesa | C9 Mesa con amigos, C7 Unirme a mesa | Pendiente | James |
| | 5.2 Pedido y calificación | C8 Estado del pedido, C10 Calificar almuerzo | Pendiente | James |
| | 5.3 Mi cuenta | C6 Mi cuenta | Pendiente | James |
| 6. Extras | 6.1 Mapa | C11 Mapa interactivo | Pendiente | James |
| | 6.2 Cobro de mesa | O5 Cobrar mesa | Pendiente | Carlos |
| | 6.3 Oferta flash | O11 Oferta flash | Pendiente | Carlos |
| | 6.4 Pedidos en camino | O12 Pedidos en camino | Pendiente | Carlos |
| | 6.5 Métricas y opiniones | O14 Métricas, O15 Opiniones | Pendiente | Carlos |
| | 6.6 Cartulina | O10 Pasar cartulina | Pendiente | Carlos |

Nota: A1 a A7 son Auth, C1 a C11 son Customer y O1 a O16 son Owner. El índice completo está en `FLUJO_PANTALLAS.md`.

Total: **34 pantallas** (7 Auth, 11 Customer, 16 Owner). Si Carlos pide pantallas nuevas, se agregan aquí y en la sección 7.

## 4. Reglas que aplican a cada sub-fase

De `GEMINI.md`:
- Colores y tipografía solo desde `lib/core/theme`. Nada hardcodeado. Tema claro y oscuro.
- Cada módulo solo edita su carpeta. No editar `core/` sin avisar.
- La API la define el backend. No inventar endpoints: usar mock y dejar `// TODO: Conectar con provider de backend`.
- No agregar paquetes sin preguntar. Los paquetes aprobados se agregan en la fase donde se usan.
- Antes de terminar: `flutter analyze` sin errores y que compile.

De `REGLAS_UX.md`:
- Un solo botón morado relleno por pantalla.
- Columnas con botones usan `CrossAxisAlignment.stretch`.
- Botones con verbo + objeto.
- Mínimo de texto visible: se mantiene 13 px hasta evaluar la primera migración (ver sección 5).

De las directrices del curso, traducidas a Flutter (ver `directrices`, sección 5):
- Arquitectura por capas con Riverpod (equivale a ViewModel). Navegación con go_router.
- Persistencia: la base principal es Postgres (Neon o Supabase) y la integra James. Las pantallas leen de repositorios (mock hoy, API después) y no conocen la fuente. Persistencia local (Room) se define con James (ver 5.1).
- API REST con `dio`. Edge AI con `mobile_scanner` (ML Kit).
- Estado que sobrevive a la rotación en providers, no en `setState`.
- Trabajo de red y pesado fuera del hilo principal.

## 5. Decisiones y pendientes

**Decidido:**
- Se mantienen las 34 pantallas. Carlos lleva owner. James lleva customer.
- **Entrada del dueño:** después del login, el dueño entra a Caja (O1), no al escáner. Se aplica en la fase 0.1.
- **Filtros de Dónde comer:** los del MVP, que son Cerca, Con plan, Libre y Ofertas. Son los que reflejan la lógica del producto (plan y ocupación). Los filtros de Flutter (Ejecutivo, Veggie, Económico) eran datos de prueba.
- **Mapa:** se aprueba un paquete. Recomendado: `flutter_map` con `latlong2`. Usa OpenStreetMap, no requiere clave de API ni cuenta de facturación. Diferencia con el MVP: el prototipo muestra un mapa de Google; Flutter mostrará OpenStreetMap. Se agrega cuando se use (A5 y 6.1).
- **Ajustes finales:** Carlos puede pedir cambios sobre la copia del MVP por pantalla. Se anotan en la ficha y se aplican sobre la copia.
- **Botones:** navegan desde ya a su destino. Las peticiones están en `FLUJO_PANTALLAS.md`. James conecta la API.
- **Login con Google:** se deja abierto. El equipo lo configura después.
- **Texto:** 13 px durante la primera migración. Después se evalúa si se sube.

**Pendiente:**
1. **Persistencia local (Room).** Diferido a James. Ver 5.1.
2. **Commits.** ¿Un commit por sub-fase en `feat/owner-ux`? La rama no existe en el remoto y no se hará push sin tu orden.
3. **Profesor.** ¿Conviene confirmar que la entrega en Flutter es aceptable para el curso?

### 5.1 Qué es Room y su equivalente en Flutter

Room es la librería de Android para guardar datos en el teléfono. Usa SQLite por debajo. Se define en tres partes: las tablas (entidades), las consultas (DAO) y la base de datos. Sirve para que la app funcione sin internet: por ejemplo, el pase en caché, el menú de hoy o el historial.

En Flutter, el equivalente más cercano es **drift**. Define las tablas en Dart, las consultas tienen tipos, maneja migraciones de la base y genera el código con `build_runner`.

Alternativas:
- **sqflite:** SQLite con SQL escrito a mano. Más simple, pero sin tipos ni generación de código.
- **shared_preferences** (lo que usa hoy el proyecto): guarda pares clave-valor. No sirve para listas ni consultas.

Decisión: diferido a James. Su integración decide si hace falta una base local además de Postgres. Por ahora no se agrega ningún paquete de base de datos.

## 6. Siguiente paso

Listos para empezar, con dos condiciones:
1. **Ajustes de Login.** Dime qué cambios quieres en la pantalla de login o confirma que la copia del MVP va tal cual.
2. **Aviso a James.** La fase 0.1 toca `app_router.dart` y `core/widgets`. Hay que avisarle antes de hacer commit.

Con eso, empiezo con la **fase 0.1** (login del dueño → Caja) y la ficha de la **sub-fase 1.1 (Login)** en `fase-1-auth/1.1-login.md`.

## 7. Cambios pedidos

| Fecha | Cambio | Pantallas afectadas |
|---|---|---|
| 2026-11-14 | Entrada del dueño después del login: Caja, no escáner | A1, A7, O1 |
| 2026-11-14 | Filtros de Dónde comer: los del MVP | C2 |
| 2026-11-14 | Mapa: se aprueba paquete, recomendado `flutter_map` | A5, C11 |
| 2026-11-14 | Ajustes finales por pantalla sobre la copia del MVP | Todas |
| 2026-11-14 | Caja v0: pantalla de entrada del dueño con resumen del turno (ingresos, almuerzos, planes, efectivo esperado, movimientos) y accesos a escanear, vender plan y cierre. Diseño final pendiente del MVP y de tus ajustes | O1, A1 |
| 2026-11-14 | Room diferido a James. La base es Postgres (Neon o Supabase) y las pantallas solo usan repositorios | Ninguna pantalla |
