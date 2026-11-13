import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/contracts/qr_parser.dart';
import '../../../core/theme/app_theme.dart';
import 'owner_controller.dart';

/// Ruta de la pantalla de resultado (definida en `core/router/app_router.dart`).
const String _scanResultRoute = '/owner/scan-result';

/// Escáner QR del Dueño: cámara con ML Kit (offline), overlay animado,
/// linterna, simulación para emulador e ingreso manual del token.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _frameSize = 260;

  late final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  late final AnimationController _scanLine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  /// `true` mientras hay un diálogo abierto o se está navegando al resultado,
  /// para que la cámara no dispare validaciones paralelas.
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deja el controlador en Scanning al abrir la pantalla.
    Future.microtask(() {
      if (mounted) ref.read(ownerControllerProvider.notifier).startScanning();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanLine.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_camera.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_paused) _camera.start();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _camera.stop();
    }
  }

  // ---------------------------------------------------------------------------
  // Lógica
  // ---------------------------------------------------------------------------

  void _onDetect(BarcodeCapture capture) {
    if (_paused) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _submit(value);
        return;
      }
    }
  }

  Future<void> _submit(String rawToken) async {
    if (_paused) return;
    _paused = true;
    final controller = ref.read(ownerControllerProvider.notifier);
    await controller.onCodeDetected(rawToken);
    if (!mounted) return;

    final state = ref.read(ownerControllerProvider);
    if (state is OwnerSuccess || state is OwnerError) {
      await _camera.stop();
      if (!mounted) return;
      await context.push(_scanResultRoute);
      if (!mounted) return;
      // De vuelta del resultado: listo para escanear al siguiente comensal.
      controller.startScanning();
      _paused = false;
      await _camera.start();
    } else {
      _paused = false;
    }
  }

  Future<void> _openSimulator() async {
    _paused = true;
    final token = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SimulatorSheet(),
    );
    _paused = false;
    if (token != null && mounted) _submit(token);
  }

  Future<void> _openManualEntry() async {
    _paused = true;
    final token = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualEntryDialog(),
    );
    _paused = false;
    if (token != null && mounted) _submit(token);
  }

  void _close() {
    ref.read(ownerControllerProvider.notifier).reset();
    if (context.canPop()) context.pop();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final state = ref.watch(ownerControllerProvider);
    final processing = state is OwnerScanning && state.isProcessing;

    return Scaffold(
      backgroundColor: scheme.scrim,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
            placeholderBuilder: (context) => ColoredBox(color: scheme.scrim),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _scanLine,
              builder: (context, _) => CustomPaint(
                painter: _ScanOverlayPainter(
                  frameSize: _frameSize,
                  progress: _scanLine.value,
                  scrimColor: scheme.scrim.withValues(alpha: 0.65),
                  cornerColor: scheme.primary,
                  lineColor: scheme.primary,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  camera: _camera,
                  onClose: _close,
                ),
                const Spacer(),
                const SizedBox(height: _frameSize),
                const SizedBox(height: 24),
                _StatusHint(processing: processing),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      if (kDebugMode) ...[
                        OutlinedButton.icon(
                          onPressed: processing ? null : _openSimulator,
                          icon: const Icon(Icons.bug_report_outlined),
                          label: const Text('Simular Escaneo'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ElevatedButton.icon(
                        onPressed: processing ? null : _openManualEntry,
                        icon: const Icon(Icons.keyboard_alt_outlined),
                        label: const Text('Ingresar Código Manualmente'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.camera, required this.onClose});

  final MobileScannerController camera;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: 'Cerrar escáner',
            style: IconButton.styleFrom(
              backgroundColor: scheme.surface,
              foregroundColor: scheme.onSurface,
            ),
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              'Escanear QR',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.surface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          IconButton.filled(
            tooltip: 'Cierre de caja',
            style: IconButton.styleFrom(
              backgroundColor: scheme.surface,
              foregroundColor: scheme.onSurface,
            ),
            onPressed: () => context.push('/owner/cash-closing'),
            icon: const Icon(Icons.point_of_sale),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: camera,
            builder: (context, value, _) {
              final available = value.torchState != TorchState.unavailable;
              final on = value.torchState == TorchState.on;
              return IconButton.filled(
                tooltip: on ? 'Apagar linterna' : 'Encender linterna',
                style: IconButton.styleFrom(
                  backgroundColor: on ? scheme.primary : scheme.surface,
                  foregroundColor: on ? scheme.onPrimary : scheme.onSurface,
                ),
                onPressed: available ? camera.toggleTorch : null,
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusHint extends StatelessWidget {
  const _StatusHint({required this.processing});

  final bool processing;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: scheme.surface,
          fontWeight: FontWeight.w600,
        );
    if (processing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text('Validando pase…', style: style),
        ],
      );
    }
    return Text(
      'Apunta al QR del comensal',
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: scheme.scrim,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined,
                  size: 48, color: scheme.surface),
              const SizedBox(height: 16),
              Text(
                denied
                    ? 'Sin permiso de cámara'
                    : 'No se pudo abrir la cámara',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.surface,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Activa el permiso en Ajustes o ingresa el código manualmente.'
                    : 'Ingresa el código manualmente para continuar.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.surface,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hoja con tokens de prueba (solo debug / emulador).
class _SimulatorSheet extends StatelessWidget {
  const _SimulatorSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.check_circle_outline, color: scheme.primary),
            title: const Text('Token válido'),
            subtitle: const Text('Camila Andrade (u1) · QR vigente'),
            onTap: () => Navigator.pop(
              context,
              BocadooQrParser.generateQrPayload('u1'),
            ),
          ),
          ListTile(
            leading: Icon(Icons.timer_off_outlined, color: scheme.error),
            title: const Text('Token expirado'),
            subtitle: const Text('QR generado hace 5 minutos'),
            onTap: () => Navigator.pop(
              context,
              BocadooQrParser.generateQrPayload(
                'u1',
                DateTime.now().subtract(const Duration(minutes: 5)),
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.cancel_outlined, color: scheme.error),
            title: const Text('Token inválido'),
            subtitle: const Text('Formato no reconocido'),
            onTap: () => Navigator.pop(context, 'INVALID'),
          ),
        ],
      ),
    );
  }
}

/// Diálogo para escribir el token a mano si falla la cámara.
class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog();

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _accept() {
    final value = _text.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Escribe el código del pase.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ingresar código'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Escribe el código que aparece bajo el QR del comensal.'),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'BCD1.u1.…',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _accept(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _accept, child: const Text('Validar')),
      ],
    );
  }
}

/// Oscurece todo menos el marco de lectura y dibuja esquinas + línea animada.
class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({
    required this.frameSize,
    required this.progress,
    required this.scrimColor,
    required this.cornerColor,
    required this.lineColor,
  });

  final double frameSize;
  final double progress;
  final Color scrimColor;
  final Color cornerColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frameSize,
      height: frameSize,
    );
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(24));

    // Scrim con hueco.
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = scrimColor);

    // Esquinas.
    const len = 36.0;
    final corner = Paint()
      ..color = cornerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final l = frame.left, t = frame.top, r = frame.right, b = frame.bottom;
    canvas
      ..drawPath(
        Path()
          ..moveTo(l, t + len)
          ..lineTo(l, t + 24)
          ..arcToPoint(Offset(l + 24, t), radius: const Radius.circular(24))
          ..lineTo(l + len, t),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(r - len, t)
          ..lineTo(r - 24, t)
          ..arcToPoint(Offset(r, t + 24), radius: const Radius.circular(24))
          ..lineTo(r, t + len),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(r, b - len)
          ..lineTo(r, b - 24)
          ..arcToPoint(Offset(r - 24, b), radius: const Radius.circular(24))
          ..lineTo(r - len, b),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(l + len, b)
          ..lineTo(l + 24, b)
          ..arcToPoint(Offset(l, b - 24), radius: const Radius.circular(24))
          ..lineTo(l, b - len),
        corner,
      );

    // Línea de barrido.
    final y = frame.top + 16 + (frame.height - 32) * progress;
    final line = Paint()
      ..shader = LinearGradient(
        colors: [
          lineColor.withValues(alpha: 0),
          lineColor,
          lineColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(frame.left, y, frame.width, 2))
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(frame.left + 12, y),
      Offset(frame.right - 12, y),
      line,
    );
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.progress != progress ||
      old.scrimColor != scrimColor ||
      old.cornerColor != cornerColor ||
      old.lineColor != lineColor;
}
