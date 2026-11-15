import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

/// Selector Sistema / Claro / Oscuro (C6 Mi cuenta y O16 Ajustes).
class AppearanceSelector extends ConsumerWidget {
  const AppearanceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final mode = ref.watch(themeModeProvider);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        for (final (m, label, icon) in const [
          (ThemeMode.system, 'Sistema', Icons.desktop_windows_outlined),
          (ThemeMode.light, 'Claro', Icons.light_mode_outlined),
          (ThemeMode.dark, 'Oscuro', Icons.dark_mode_outlined),
        ])
          Expanded(
            child: Semantics(
              selected: mode == m,
              button: true,
              child: Material(
                color: mode == m ? colors.primary : colors.surface.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(children: [
                      Icon(icon, size: 20, color: mode == m ? colors.onPrimary : colors.onSurfaceVariant),
                      const SizedBox(height: 2),
                      Text(label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: mode == m ? colors.onPrimary : colors.onSurfaceVariant,
                          )),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
