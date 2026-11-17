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
    final asset = _wordmark
        ? 'assets/logos/logo completo.png'
        : 'assets/logos/logo isotopo.png';
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
