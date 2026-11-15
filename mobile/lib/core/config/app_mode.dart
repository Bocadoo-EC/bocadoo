/// Modo de ejecución de Bocadoo y URL base del backend.
///
/// - Modo API (por defecto): conecta contra `https://bck-bocadoo.onrender.com`.
/// - Modo mock (`--dart-define=BOCADOO_USE_MOCK=true`): ejecuta todo contra mocks locales.
/// - Backend local (`--dart-define=BOCADOO_API_URL=http://10.0.2.2:3000`).
class AppMode {
  AppMode._();

  static const bool useMock = bool.fromEnvironment(
    'BOCADOO_USE_MOCK',
    defaultValue: false,
  );

  static const String apiUrl = String.fromEnvironment(
    'BOCADOO_API_URL',
    defaultValue: 'https://bck-bocadoo.onrender.com',
  );
}
