Plan de Ejecución por Fases: Bocadoo Mobile (Flutter)

Documento de Control y Tareas — Bocadoo PMV
Fuente de verdad de diseño: bocadoo/docs/IDENTIDAD_BOCADOO.md
Referencia de prototipo Web: Workspace inspo-palette-creation

🎯 Objetivo General

Trasladar de manera fiel el prototipo web funcional y visualmente completo (inspo-palette-creation) a la aplicación Flutter (bocadoo/mobile). La app debe respetar estrictamente el sistema de diseño Material Design 3 de Bocadoo (paleta morada #8234C6, tipografía Plus Jakarta Sans, radios redondeados, soporte claro/oscuro sin destellos y diccionario de microcopy permitido).

📋 Lista de Fases y Tareas Tecnológicas

🎨 FASE 0: Sistema de Diseño, Tokens y Componentes Atómicos (Material 3)

Objetivo: Establecer la base visual inmutable para que ninguna pantalla use colores hardcodeados ni estilos fuera del manual de marca.

[ ] 0.1 Configuración de Tokens y Tema (app_theme.dart)

Implementar paleta clara y oscura oficial en mobile/lib/core/theme/app_theme.dart:

Primario: #8234C6 (Claro) / #DEB7FF (Oscuro)

Fondo general: #F5ECFF (Claro) / #1C1127 (Oscuro)

Tarjetas (surface): #FFFFFF (Claro) / #2A1B3A (Oscuro)

Texto base (foreground): #2D0050 (Claro) / #F1DBFF (Oscuro)

Texto secundario: #635C65 (Claro) / #CDB8E0 (Oscuro)

Configurar tema de bordes (#CDC4CE / #4A454D) y contenedor de inputs (#FFFFFF / #2A1B3A).

Configurar ThemeData claro y oscuro de Flutter usando Material 3 (useMaterial3: true).

[ ] 0.2 Tipografía y Radios Globales

Asegurar la fuente Plus Jakarta Sans en el proyecto (pubspec.yaml y assets/google_fonts).

Aplicar jerarquía de tamaños: Metadatos 13px (600), Lectura 15px, Botones 17px (700/800), Números gigantes 32px–48px (800).

Definir radios globales: Botones en Cápsula (rounded-full / 56px de alto), Tarjetas de 28px a 32px, Inputs de 14px a 16px (rounded-2xl).

[ ] 0.3 Componentes Atómicos Reutilizables (core/widgets/ o common/)

BocadooButton: Botón cápsula primario (morado sólido, 1 por grupo) y secundario (borde o container).

BocadooHeader: Header superior con degradado hero-gradient (linear-gradient(160deg, #9C51E1, #8234C6, #680EAC)) y esquinas inferiores redondeadas de 40px.

BocadooQr: Contenedor del QR con fondo blanco obligatorio #FFFFFF y módulos #2D0050 (inviolable en ambos temas).

StatusChip: Chips de estado para Validado (verde), Renovar/Agotado/Error (rojo) y Oferta (morado).

BottomNavBar: NavigationBar de Flutter adaptado a la identidad (pastilla primary-container para la pestaña activa).

👤 FASE 1: Módulo Comensal / Customer App

Objetivo: Replicar el catálogo de restaurantes, compra/renovación de pases y la tarjeta digital de almuerzos (QR).

[ ] 1.1 Catalogo de Restaurantes (restaurants_screen.dart)

Encabezado con saludo al usuario y barra de búsqueda ("Buscar restaurante").

Tarjetas de restaurantes con fotos de comida (sin alteración por tema), etiqueta de precio, descuento y badge "Ahorras $X".

Selector de menús o del día para el restaurante seleccionado.

[ ] 1.2 Pantalla Mi Pase / Cartulina (pase_screen.dart)

Bloque superior a todo el ancho con hero-gradient y curvas de 40px. Muestra: nombre del plan, almuerzos restantes ("Te quedan 14") y fecha de vencimiento ("Vence 30 oct").

Tarjeta de QR superpuesta ~48px sobre el degradado en surface con el código QR escaneable (#2D0050 sobre #FFFFFF).

Botón rápido "Renovar" o "Comprar más almuerzos".

[ ] 1.3 Flujo de Adquisición / Selección de Plan

Modal/Bottom Sheet para elegir plan de almuerzos (ej: 10 almuerzos, 20 almuerzos).

Resumen de pago claro usando el vocabulario permitido: "Quiero este", "Paga en caja".

[ ] 1.4 Perfil y Ajustes del Comensal

Selector de Tema (ThemeToggle): Sistema (por defecto), Claro y Oscuro. Persistencia de la selección.

Historial de almuerzos consumidos.

🏪 FASE 2: Módulo Dueño / Owner App

Objetivo: Replicar las herramientas operativas del dueño: escáner de pases, validación instantánea, caja y menú.

[ ] 2.1 Escáner de Pases QR (scanner_screen.dart)

Vista de cámara completa utilizando paquete nativo optimizado (mobile_scanner / ML Kit).

Marco guía de escaneo con diseño en bordes morados y botón de linterna/flash.

Switch rápido para cambiar modo (Validar Almuerzo vs. Venta Rápida).

[ ] 2.2 Resultado de Validación (scan_result_screen.dart)

Feedback visual instantáneo tras el escaneo:

Estado Éxito: Chip verde Validado, muestra almuerzos restantes ("Le quedan 19"), botón grande "Pasar cartulina" o "Deshacer".

Estado Error: Chip rojo Ya validado, Vencido o Sin almuerzos.

Sonido/Vibración de confirmación.

[ ] 2.3 Cierre de Caja Diaria (cash_closing_screen.dart)

Resumen de métricas del día: Total cobrado, almuerzos servidos, desglose por Efectivo y Transferencia.

Calculadora/Cuadre de caja: Botón "Cerrar caja", badges de "Cuadra", "Faltan $3,00" o "Sobran $1,50".

Lista de "Almuerzos que debes" / pendientes de cobro.

[ ] 2.4 Publicación de Menú del Día

Pantalla o modal rápido para ingresar/actualizar el plato de hoy.

Acciones rápidas: "Publicar", "Repetir ayer", botón de pánico "Se acabó" / "Agotado".

🔀 FASE 3: Enrutamiento, Estado y Persistencia

Objetivo: Conectar todas las pantallas mediante GoRouter y sincronizar el estado global.

[ ] 3.1 Consolidación de Rutas (app_router.dart)

Definir la estructura limpia con GoRouter para navegación por Shell (BottomNavigationBar compartida para Comensal y Dueño).

Separación clara de rutas /customer/* y /owner/*.

[ ] 3.2 Gestión de Estado (Provider / Riverpod)

Provider de Autenticación / Rol (Comensal vs. Dueño).

Provider de Pases y Consumo (actualización en tiempo real del saldo de almuerzos).

Provider de Menú y Estado del Restaurante.

[ ] 3.3 Conexión con Datos (Mock / Backend API)

Repositorios alineados con las estructuras de datos usadas en inspo-palette-creation.

Simulación de latencia y manejo de errores sin conexión.

🔬 FASE 4: Auditoría de Marca, Calidad y Pruebas Multiplataforma

Objetivo: Verificar cumplimiento estricto del manual de marca y asegurar estabilidad.

[ ] 4.1 Auditoría de Marca e Identidad (IDENTIDAD_BOCADOO.md)

Verificación de Colores: Cero valores hexadecimales fuera de app_theme.dart.

Verificación de Contraste: Todo texto ≥ 4.5:1 sobre su fondo.

Verificación de Vocabulario: Cero palabras prohibidas ("suscripción", "transacción", "canje", "redención", "gestión", "módulo", "dashboard", "procesar", "ítem"). Todo en lenguaje simple y coloquial ecuatoriano.

Verificación de Formato de Dinero: $2,75, $55,00, $0,00.

[ ] 4.2 Pruebas en Android y Preparación para iOS

Ejecutar flutter analyze en mobile/: 0 errores.

Ejecutar flutter test en mobile/: todos los tests pasando.

Verificar permisos de cámara en Android (AndroidManifest.xml) e iOS (ios/Runner/Info.plist con NSCameraUsageDescription).

Probar renderizado y respuesta táctil en emulador/dispositivo Android y navegador (modo vista previa iOS).

📌 Protocolo de Trabajo para Antigravity

Progreso Incremental: Ejecutar una tarea o subfase a la vez.

Validación Visual Obligatoria: Tras modificar cada pantalla, verificar el resultado en el tema claro y oscuro.

Registro de Estado: Marcar las casillas [x] en este archivo TASKS.md a medida que se completen y verifiquen las funcionalidades.
