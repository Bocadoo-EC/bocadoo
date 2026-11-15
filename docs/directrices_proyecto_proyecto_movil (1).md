## Tarea 2.2. "Bosquejo del Proyecto Final"

## 1. Instrucciones Generales

El objetivo es que los grupos apliquen la metodología de aprendizaje basado en proyectos para definir una solución móvil que resuelva un problema real dentro del dominio que cubre la facultad de Hábitat, Creatividad e Infraestructura.

- 1. Conformación: Reúnanse en sus grupos de trabajo.

- 2. Lluvia de Ideas: Identifiquen un problema que pueda resolverse con una app móvil nativa. Consideren que el proyecto debe integrar obligatoriamente:

- Persistencia de datos local (Room).

- Consumo de servicios externos (API REST).

- Capacidades de Inteligencia Artificial procesada en el dispositivo (ML Kit).

- Arquitectura MVVM o Clean Architecture.

- 3. Definición del Alcance: El proyecto debe ser escalable y demostrar un manejo eficiente de recursos (batería, red y memoria).

## 2. Entregable: Planificación del Proyecto Final

Cada grupo debe entregar un documento (y presentación) que contenga la siguiente estructura de planificación:

| Sección | Descripción Requerida |
| --- | --- |
| Título y Problema | Nombre de la App y descripción del problema en el contexto de hábitat o sociedad. |
| Público Objetivo | ¿Quiénes serán los usuarios finales de la aplicación? |


| Funcionalidades Core | Al menos 3 funciones principales que usen UI Declarativa (Jetpack Compose). |
| --- | --- |
| Wireframes / Mockups | Bosquejos visuales de al menos 3 pantallas principales. Deben señalar explícitamente qué contenedores declarativos usarán (ej. Column, Row, LazyColumn) |
| Modelado de Estado Inicial (Aplicando el "Mindset Kotlin") | Definición teórica de al menos una data class fundamental (ej. Producto, Paciente). Definición de una sealed class que represente el estado de la UI (ej. UiState: Loading, Success, Error) para manejar la asincronía de forma exhaustiva y blindada contra nulos. |
| Cronograma de Integración Tecnológica | Una tabla que mapee las próximas semanas del curso con las características de su app. Por ejemplo: Semanas 9-10 (MVVM y Navegación): "Implementaremos el ViewModel para que los datos no se pierdan al rotar la pantalla y el NavHost para transitar entre el Login y el Home". Semanas 11-12 (Corrutinas y Redes): "Conectaremos la app a una API REST usando Retrofit sin bloquear el hilo principal". Semanas 13-15 (Edge AI): "Integraremos ML Kit para que la cámara reconozca texto offline" |
| Componente de IA | Describir qué modelo de Edge AI se usará (ej: reconocimiento de texto, detección de objetos, traducción local). |
| Estrategia de Datos | ¿Qué información se guardará localmente en Room y qué se consultará vía API?. |


| Stack Tecnológico | Confirmar el uso de Kotlin, Corrutinas para concurrencia y herramientas de perfilado. |
| --- | --- |

## 3. Opciones de Temas Generales

Como ejemplos, pueden elegir o adaptar uno de estos temas enfocados en las competencias del dominio:

- Gestor de Salud y Bienestar Inteligente (Health Tracker)

- Base actual: Pueden basarse en el reto de la Calculadora de IMC que ya realizaron.

- Proyección: Integrar lazy lists para historiales médicos, base de datos local (Room) para guardar el progreso diario, y usar IA (ML Kit) para escanear y reconocer etiquetas nutricionales de alimentos físicos.

- Sistema de Inventario y Escaneo Comercial

- Base actual: Evolución de los laboratorios de "Gestión de Inventario Seguro".

- Proyección: Uso de LazyColumn para catálogos de miles de productos, consumo de una API REST para sincronizar precios, e IA local para lectura rápida de códigos de barras o reconocimiento visual de productos sin internet.

## Aplicación Educativa / Gestor de Estudio

- Base actual: Evolución del laboratorio "Lista de Estudiantes" y "Validador de Perfiles".

- Proyección: Navegación entre perfiles y cursos, persistencia de notas con Room, y uso de ML Kit para traducir textos o digitalizar apuntes escritos a mano utilizando la cámara del dispositivo.

- Eficiencia de Recursos y Sostenibilidad: Aplicación que ayude a los ciudadanos a optimizar el uso de recursos (agua/energía), integrando una base de datos local para el historial de consumo y consejos generados por IA local.

- Seguridad y Conectividad Comunitaria: Sistema de información para mejorar la seguridad en barrios, con notificaciones en tiempo real (APIs) y manejo de permisos sensibles de privacidad.

- Asistente de Movilidad Adaptable: App que ayude a personas con discapacidad a navegar la infraestructura física de la ciudad, usando visión artificial local para identificar obstáculos o señales de accesibilidad.

- Gestión Inteligente de Hábitat: App para el reporte de incidencias en infraestructura urbana, que use IA para clasificar automáticamente el tipo de daño mediante fotos (Edge AI) y GPS para la ubicación.

## 4. Consideraciones Importantes para el Grupo

Se sugiere poner especial atención a estos puntos técnicos que serán evaluados según la rúbrica:


- Manejo del Ciclo de Vida: Su bosquejo debe considerar cómo la app mantendrá el estado ante cambios de configuración, como la rotación de pantalla.

- No Bloquear el Hilo Principal: Toda operación pesada (IA o Red) debe planificarse con Corrutinas de Kotlin para evitar que la app se congele (ANR).

- Diseño Moderno: Consideren los principios de Material Design 3 y aseguren que la interfaz sea adaptable (Modo oscuro y diferentes tamaños de pantalla).

## 5. Adaptación del equipo a Flutter (Bocadoo)

Las directrices anteriores están escritas para Android nativo (Kotlin, Jetpack Compose, Room, Retrofit, ML Kit). Bocadoo se desarrolla en Flutter (Dart). El equipo cumple los mismos requisitos del curso con su equivalente en Flutter. No se usan Kotlin ni Compose tal cual.

| Requisito del curso (Android) | Equivalente en Bocadoo (Flutter) | Estado |
|---|---|---|
| Kotlin | Dart 3: `sealed class`, `switch` con patrones, records | En uso |
| Jetpack Compose (UI declarativa) | Widgets de Flutter: `Column`, `Row`, `ListView.builder` (equivale a `LazyColumn`) | En uso |
| `data class` | Clase Dart con campos `final` y `copyWith` | En uso (`freezed` pendiente de aprobación) |
| `sealed class UiState` (Loading, Success, Error) | `AsyncValue` de Riverpod (`loading`, `data`, `error`) o `sealed class` propia en Dart | En uso |
| ViewModel | `Notifier` / `AsyncNotifier` de Riverpod | En uso |
| Room (persistencia local) | Base local (`drift` o `sqflite`) solo si el backend la necesita. La base principal es Postgres (Neon o Supabase), integrada por el equipo de backend | Diferido a la integración con backend |
| Retrofit (API REST) | `dio` | Declarado; sin endpoints reales (mock) |
| Corrutinas | `async`/`await`, `Future`, `Stream`; `compute()` para trabajo pesado | En uso |
| ML Kit (QR y texto offline) | `mobile_scanner` (ML Kit de códigos). Reconocimiento de texto requiere paquete nuevo | QR en uso |
| NavHost (navegación) | `go_router` | En uso |
| Material Design 3, modo oscuro | Tema en `lib/core/theme` con tokens claros y oscuros | En uso |
| Android Studio Profiler | Flutter DevTools (CPU, memoria, red) | Pendiente |

Reglas de equivalencia para el documento del curso:
- **Ciclo de vida (rotación):** los datos de la pantalla viven en providers de Riverpod, no en `setState` local, así sobreviven a la reconstrucción del widget. Se verifica girando el emulador.
- **Hilo principal:** toda llamada de red va con `dio` (asíncrona). El trabajo pesado usa `compute()` o un isolate. Nada bloquea el build.
- **Modo oscuro y tamaños:** `LayoutBuilder` o `MediaQuery`, y colores solo del tema.
- **Cronograma (semanas 9 a 15):** las mismas tareas, traducidas: ViewModel → Riverpod; NavHost → go_router; Retrofit → dio; Edge AI → `mobile_scanner` y, si se aprueba, reconocimiento de texto.

Esta tabla es la propuesta del equipo, no una decisión del curso. Conviene confirmar con el profesor que la entrega en Flutter es aceptable.
