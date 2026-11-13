import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';

/// Contenedor oficial del código QR de Bocadoo.
/// Regla de marca inviolable: fondo SIEMPRE blanco (#FFFFFF) y módulos #2D0050
/// en modo claro y oscuro para garantizar lectura óptica en caja.
class BocadooQr extends StatelessWidget {
  final String data;
  final double size;
  final VoidCallback? onTap;
  final bool showZoomBadge;

  const BocadooQr({
    super.key,
    required this.data,
    this.size = 185,
    this.onTap,
    this.showZoomBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final bColor = context.bocadooColors;
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bColor.qrBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            QrImageView(
              data: data,
              version: QrVersions.auto,
              size: size,
              backgroundColor: bColor.qrBackground,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: bColor.qrForeground,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: bColor.qrForeground,
              ),
            ),
            if (showZoomBadge)
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fullscreen_rounded,
                  size: 14,
                  color: colors.onPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

