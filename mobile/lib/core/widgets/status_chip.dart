import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Variantes semánticas de los chips de estado de Bocadoo.
enum BocadooStatusVariant { validated, danger, offer, neutral }

/// Chip de estado oficial de Bocadoo:
/// - [BocadooStatusVariant.validated]: `successContainer` + `success`
/// - [BocadooStatusVariant.danger]: `dangerContainer` + `onDangerContainer`
/// - [BocadooStatusVariant.offer]: `primary` + `onPrimary`
/// - [BocadooStatusVariant.neutral]: `secondaryContainer` + `onSecondaryContainer`
class StatusChip extends StatelessWidget {
  final String label;
  final BocadooStatusVariant variant;
  final IconData? icon;
  final bool showDot;

  const StatusChip({
    super.key,
    required this.label,
    required this.variant,
    this.icon,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bColor = context.bocadooColors;

    final (Color bg, Color fg) = switch (variant) {
      BocadooStatusVariant.validated => (
          bColor.successContainer,
          bColor.success,
        ),
      BocadooStatusVariant.danger => (
          bColor.dangerContainer,
          bColor.onDangerContainer,
        ),
      BocadooStatusVariant.offer => (
          colors.primary,
          colors.onPrimary,
        ),
      BocadooStatusVariant.neutral => (
          colors.secondaryContainer,
          colors.onSecondaryContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

