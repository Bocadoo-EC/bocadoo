import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Encabezado hero oficial de Bocadoo a todo el ancho con degradado morado
/// y esquinas inferiores redondeadas de 40px.
class BocadooHeader extends StatelessWidget {
  final Widget child;
  final double bottomPadding;
  final double horizontalPadding;

  const BocadooHeader({
    super.key,
    required this.child,
    this.bottomPadding = 72,
    this.horizontalPadding = 20,
  });

  @override
  Widget build(BuildContext context) {
    final bColor = context.bocadooColors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: bColor.heroGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        MediaQuery.of(context).padding.top + 16,
        horizontalPadding,
        bottomPadding,
      ),
      child: child,
    );
  }
}

