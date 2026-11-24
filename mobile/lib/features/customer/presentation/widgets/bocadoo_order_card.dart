import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../customer_widgets.dart' show formatCents;

/// Tipo de orden mostrado en la tarjeta principal de Mi Pase.
enum BocadooOrderCardType {
  preorderWithoutPlan,
  preorderWithPlan,
  groupOrder,
  flashOffer,
}

/// Tarjeta principal de orden/preorden/plan con estética degradada morada,
/// marca de agua del logo, métrica dinámica, hora confirmada y marco QR.
class BocadooOrderCard extends StatelessWidget {
  const BocadooOrderCard({
    super.key,
    required this.restaurantName,
    required this.orderType,
    this.totalCents,
    this.availableLunches,
    this.scheduledTime,
    this.extraCashCents = 0,
    this.qrPayload,
    this.hasActiveOrderQr = false,
    this.inactiveQrLabel = 'Se activará al pedir',
    this.onTapQr,
    required this.onTapViewStatus,
    this.actionLabel = 'VER ESTADO',
  });

  final String restaurantName;
  final BocadooOrderCardType orderType;
  final int? totalCents;
  final int? availableLunches;
  final String? scheduledTime;
  final int extraCashCents;
  final String? qrPayload;
  final bool hasActiveOrderQr;
  final String inactiveQrLabel;
  final VoidCallback? onTapQr;
  final VoidCallback onTapViewStatus;
  final String actionLabel;

  bool get _isPlanType => orderType == BocadooOrderCardType.preorderWithPlan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cleanRestaurant = restaurantName.trim().isEmpty
        ? 'RESTAURANTE'
        : restaurantName.trim().toUpperCase();
    final metricLabel = _isPlanType ? 'Almuerzos disponibles' : 'Total de';
    final metricValue = _isPlanType
        ? '${availableLunches ?? 0}'
        : formatCents(totalCents ?? 0);
    final hasTime = scheduledTime != null && scheduledTime!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B2CBF).withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minHeight: 204),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFBFBBF5),
                Color(0xFF7B2CBF),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Marca de agua del logo escalada y suavemente recortada abajo.
              Positioned(
                left: -24,
                bottom: -74,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.18,
                    child: Image.asset(
                      'assets/logos/LOGO-MAIN-CLARO.png',
                      width: 268,
                      height: 268,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fila superior: Nombre del restaurante + píldora de tipo.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            cleanRestaurant,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (textTheme.titleMedium ?? const TextStyle())
                                .copyWith(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _OrderTypePill(orderType: orderType),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Cuerpo: Métrica izquierda + Marco QR derecho.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                metricLabel,
                                style: (textTheme.bodySmall ?? const TextStyle())
                                    .copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  metricValue,
                                  style: (textTheme.displayLarge ??
                                          const TextStyle())
                                      .copyWith(
                                    color: Colors.white,
                                    fontSize: 42,
                                    fontWeight: FontWeight.w700,
                                    height: 1.05,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              if (hasTime || extraCashCents > 0) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (hasTime)
                                      _TranslucentMetaPill(
                                        icon: Icons.access_time_rounded,
                                        label: 'Hora: ${scheduledTime!.trim()}',
                                      ),
                                    if (_isPlanType && extraCashCents > 0)
                                      _TranslucentMetaPill(
                                        icon: Icons.payments_outlined,
                                        label:
                                            '+ ${formatCents(extraCashCents)} caja',
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Zona derecha: QR dentro de 4 esquinas blancas + VER ESTADO.
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _QrFocusFrame(
                              qrPayload: qrPayload,
                              hasActiveOrderQr: hasActiveOrderQr,
                              inactiveQrLabel: inactiveQrLabel,
                              onTapQr: onTapQr,
                            ),
                            const SizedBox(height: 6),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onTapViewStatus,
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    actionLabel.toUpperCase(),
                                    style: (textTheme.labelMedium ??
                                            const TextStyle())
                                        .copyWith(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderTypePill extends StatelessWidget {
  const _OrderTypePill({required this.orderType});

  final BocadooOrderCardType orderType;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (label, icon, isHighlighted) = switch (orderType) {
      BocadooOrderCardType.preorderWithoutPlan => (
          'Preorden',
          Icons.receipt_long_rounded,
          false,
        ),
      BocadooOrderCardType.preorderWithPlan => (
          'Plan Activo',
          Icons.confirmation_number_rounded,
          true,
        ),
      BocadooOrderCardType.groupOrder => (
          'Orden Grupal',
          Icons.groups_rounded,
          false,
        ),
      BocadooOrderCardType.flashOffer => (
          'Oferta Flash',
          Icons.bolt_rounded,
          true,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isHighlighted ? 0.24 : 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted
              ? Colors.white.withValues(alpha: 0.48)
              : Colors.white24,
          width: isHighlighted ? 1.15 : 1.0,
        ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.16),
                  blurRadius: 10,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: (textTheme.labelMedium ?? const TextStyle()).copyWith(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TranslucentMetaPill extends StatelessWidget {
  const _TranslucentMetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: (textTheme.labelMedium ?? const TextStyle()).copyWith(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrFocusFrame extends StatelessWidget {
  const _QrFocusFrame({
    required this.qrPayload,
    required this.hasActiveOrderQr,
    required this.inactiveQrLabel,
    this.onTapQr,
  });

  final String? qrPayload;
  final bool hasActiveOrderQr;
  final String inactiveQrLabel;
  final VoidCallback? onTapQr;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cleanPayload = qrPayload?.trim() ?? '';
    final canRenderQr = hasActiveOrderQr && cleanPayload.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canRenderQr ? onTapQr : null,
        borderRadius: BorderRadius.circular(18),
        child: CustomPaint(
          painter: const _QrFocusCornersPainter(),
          child: SizedBox(
            width: 112,
            height: 112,
            child: Center(
              child: canRenderQr
                  ? QrImageView(
                      data: cleanPayload,
                      version: QrVersions.auto,
                      size: 88,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.transparent,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.30),
                        ),
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            inactiveQrLabel,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: (textTheme.bodySmall ?? const TextStyle())
                                .copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 9.5,
                              height: 1.15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrFocusCornersPainter extends CustomPainter {
  const _QrFocusCornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    const arm = 20.0;
    const r = 13.0;
    final w = size.width;
    final h = size.height;

    // Esquina superior izquierda
    final tl = Path()
      ..moveTo(0, arm)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(arm, 0);
    canvas.drawPath(tl, paint);

    // Esquina superior derecha
    final tr = Path()
      ..moveTo(w - arm, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, arm);
    canvas.drawPath(tr, paint);

    // Esquina inferior izquierda
    final bl = Path()
      ..moveTo(0, h - arm)
      ..lineTo(0, h - r)
      ..quadraticBezierTo(0, h, r, h)
      ..lineTo(arm, h);
    canvas.drawPath(bl, paint);

    // Esquina inferior derecha
    final br = Path()
      ..moveTo(w - arm, h)
      ..lineTo(w - r, h)
      ..quadraticBezierTo(w, h, w, h - r)
      ..lineTo(w, h - arm);
    canvas.drawPath(br, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
