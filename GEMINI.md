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
- NUNCA ejecutes `dart analyze`, `flutter analyze` ni `flutter test` en la terminal del agente (en Windows bloquean el servidor de análisis del IDE).
- Para verificar errores de compilación, usa exclusivamente la inspección del editor / diagnósticos del IDE (panel Problems).