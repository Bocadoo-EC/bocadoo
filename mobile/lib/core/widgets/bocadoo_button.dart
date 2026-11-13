import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Variantes visuales oficiales para botones de Bocadoo.
/// Regla de marca: máximo 1 botón primario relleno por grupo.
enum BocadooButtonVariant { primary, secondary, tonal }

/// Botón cápsula oficial de Bocadoo (alto mínimo 56px, radio 999px).
class BocadooButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BocadooButtonVariant variant;
  final bool isLoading;
  final double minHeight;

  const BocadooButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = BocadooButtonVariant.primary,
    this.isLoading = false,
    this.minHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveOnPressed = isLoading ? null : onPressed;

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: variant == BocadooButtonVariant.primary
                  ? colors.onPrimary
                  : colors.primary,
            ),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    return switch (variant) {
      BocadooButtonVariant.primary => ElevatedButton(
          onPressed: effectiveOnPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: Size.fromHeight(minHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
          ),
          child: content,
        ),
      BocadooButtonVariant.secondary => OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(minHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
          ),
          child: content,
        ),
      BocadooButtonVariant.tonal => FilledButton.tonal(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            minimumSize: Size.fromHeight(minHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
          ),
          child: content,
        ),
    };
  }
}

