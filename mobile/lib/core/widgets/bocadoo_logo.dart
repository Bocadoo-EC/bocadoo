import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Logos oficiales de Bocadoo (`assets/logos/`). En tema oscuro usa la versión
/// blanca para que el trazo siga siendo legible.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = _wordmark ? 'wordmark' : 'isotipo';
    final asset = 'assets/logos/bocadoo-$name${dark ? '-blanco' : ''}.svg';
    return Semantics(
      label: 'Bocadoo',
      image: true,
      child: SvgPicture.asset(
        asset,
        height: size,
        width: _wordmark ? size * 420 / 80 : size,
        excludeFromSemantics: true,
      ),
    );
  }
}
