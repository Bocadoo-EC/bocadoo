import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bocadoo/core/theme/app_theme.dart';
import 'package:bocadoo/core/theme/theme_provider.dart';
import 'package:bocadoo/core/widgets/theme_toggle.dart';

void main() {
  group('ThemeModeNotifier', () {
    test('defaults to ThemeMode.system when no preference is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('loads saved dark preference from bocadoo-theme', () async {
      SharedPreferences.setMockInitialValues({
        bocadooThemeStorageKey: 'dark',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(themeModeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('persists light, dark and system under bocadoo-theme', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(themeModeProvider.notifier);

      await notifier.setThemeMode(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(bocadooThemeStorageKey), 'light');

      await notifier.setThemeMode(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(bocadooThemeStorageKey), 'dark');

      await notifier.setThemeMode(ThemeMode.system);
      expect(container.read(themeModeProvider), ThemeMode.system);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(bocadooThemeStorageKey), 'system');
    });
  });

  group('ThemeToggle', () {
    testWidgets('updates themeModeProvider when selecting Claro and Oscuro',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const Scaffold(
              body: Center(child: ThemeToggle()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Oscuro'), findsOneWidget);

      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(bocadooThemeStorageKey), 'dark');
    });
  });
}

