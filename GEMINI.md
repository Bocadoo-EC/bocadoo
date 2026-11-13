# Bocadoo (Flutter, Android)
- Estado: flutter_riverpod. Rutas: go_router. HTTP: dio.
- Diseño de referencia: docs/design/. Si algo no está en las capturas, pregunta.
- Colores y tipografía solo desde lib/core/theme. Nada hardcodeado.
- Soportar tema claro y oscuro.
- Cada módulo solo edita su carpeta: lib/features/customer (James) o lib/features/owner (Carlos).
- No edites lib/core/ sin avisar al otro.
- La API la define el backend (Chucho). No inventes endpoints: pregunta o usa datos mock.
- Antes de terminar: flutter analyze sin errores y que compile.
- No inventes paquetes; usa los de pubspec.yaml o pregunta antes de agregar uno.

## Verificación Obligatoria tras Generar Código Flutter
- Después de crear o modificar archivos `.dart`, ejecuta SIEMPRE `dart analyze` pasando únicamente las rutas relativas de los archivos recién tocados dentro de `mobile/` (ej. `cd mobile && dart analyze lib/features/customer/presentation/plan_checkout_modal.dart`).
- No ejecutes `flutter analyze` global sin argumentos salvo en la auditoría final, para evitar bloqueos en Windows.
- Si `dart analyze` reporta algún `error` o `warning` en esos archivos, corrígelo antes de dar la tarea por terminada.