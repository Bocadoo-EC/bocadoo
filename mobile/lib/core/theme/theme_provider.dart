import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clave de persistencia para la preferencia de tema en [SharedPreferences].
const String bocadooThemeStorageKey = 'bocadoo-theme';

/// Provider global del modo de tema de Bocadoo (`system`, `light`, `dark`).
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Notifier encargado de leer y persistir el [ThemeMode] seleccionado.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  bool _hasUserChanged = false;
  bool _disposed = false;

  @override
  ThemeMode build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _loadSavedTheme();
    return ThemeMode.system;
  }

  Future<void> _loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(bocadooThemeStorageKey);
      if (_disposed || _hasUserChanged || raw == null) return;
      state = _parseThemeMode(raw);
    } catch (_) {
      // Mantiene ThemeMode.system si SharedPreferences no está disponible (ej. tests).
    }
  }

  /// Actualiza el modo de tema y lo persiste bajo [bocadooThemeStorageKey].
  Future<void> setThemeMode(ThemeMode mode) async {
    _hasUserChanged = true;
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(bocadooThemeStorageKey, _serializeThemeMode(mode));
    } catch (_) {
      // Ignora errores de escritura en entornos sin plataforma (ej. tests).
    }
  }

  /// Alterna cíclicamente entre Sistema → Claro → Oscuro.
  Future<void> cycleThemeMode() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    return setThemeMode(next);
  }

  static ThemeMode _parseThemeMode(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String _serializeThemeMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}

