import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

/// Selector reutilizable de tema (Sistema / Claro / Oscuro) conectado a
/// [themeModeProvider].
///
/// Usa [compact] = `true` para mostrar un botón de ícono en barras superiores
/// o `false` (por defecto) para mostrar el selector completo de 3 opciones en
/// pantallas de Ajustes.
class ThemeToggle extends ConsumerWidget {
  final bool compact;

  const ThemeToggle({
    super.key,
    this.compact = false,
  });

  const ThemeToggle.compact({super.key}) : compact = true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);

    if (compact) {
      final (IconData icon, String tooltip) = switch (currentMode) {
        ThemeMode.system => (Icons.brightness_auto_rounded, 'Tema: Sistema'),
        ThemeMode.light => (Icons.light_mode_rounded, 'Tema: Claro'),
        ThemeMode.dark => (Icons.dark_mode_rounded, 'Tema: Oscuro'),
      };

      return IconButton(
        onPressed: notifier.cycleThemeMode,
        icon: Icon(icon),
        tooltip: tooltip,
      );
    }

    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    const options = [
      (ThemeMode.system, 'Sistema', Icons.brightness_auto_rounded),
      (ThemeMode.light, 'Claro', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Oscuro', Icons.dark_mode_rounded),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, label, icon) in options)
            _ThemeOptionChip(
              label: label,
              icon: icon,
              selected: currentMode == mode,
              colors: colors,
              textTheme: textTheme,
              onTap: () => notifier.setThemeMode(mode),
            ),
        ],
      ),
    );
  }
}

class _ThemeOptionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final ColorScheme colors;
  final TextTheme textTheme;
  final VoidCallback onTap;

  const _ThemeOptionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.textTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    final bg = selected ? colors.primaryContainer : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
