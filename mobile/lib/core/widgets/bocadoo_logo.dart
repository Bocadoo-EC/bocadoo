import 'package:material_ui/material_ui.dart';

/// Logos oficiales de Bocadoo (`assets/logos/`).
class BocadooLogo extends StatelessWidget {
  /// Solo el isotipo circular.
  const BocadooLogo.isotipo({super.key, this.size = 32}) : _wordmark = false;

  /// Isotipo y nombre "bocadoo".
  const BocadooLogo.wordmark({super.key, this.size = 28}) : _wordmark = true;

  /// Alto del logo.
  final double size;
  final bool _wordmark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = _wordmark
        ? (isDark
            ? 'assets/logos/LetrasParaFondoNegro.png'
            : 'assets/logos/LetrasParaFondoBlanco.png')
        : (isDark
            ? 'assets/logos/LOGO-MAIN-CLARO.png'
            : 'assets/logos/LOGO-MAIN-OSCURO.png');
    return Semantics(
      label: 'Bocadoo',
      image: true,
      child: Image.asset(
        asset,
        height: size,
        width: _wordmark ? size * 420 / 80 : size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
