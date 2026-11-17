import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

enum ScanDialogAction { done, scanAgain, sellPlan }

/// Abre el escáner (O2) y, si vuelve con un resultado, muestra la tarjeta
/// flotante sobre la pantalla actual. Lo usan Caja y el POS.
Future<void> openScannerFlow(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final controller = ref.read(ownerControllerProvider.notifier);
  while (true) {
    await router.push('/owner/scanner');
    if (!context.mounted) return;
    final state = ref.read(ownerControllerProvider);
    if (state is OwnerRedirect) {
      // Mesa o preorden: se abre su pantalla de cobro (O5 / O12).
      controller.reset();
      await router.push(state.location);
      if (context.mounted) {
        ref.invalidate(dailySummaryProvider);
        ref.invalidate(activeOrdersProvider);
        ref.invalidate(pendingTablesProvider);
        ref.invalidate(ordersOnTheWayProvider);
      }
      return;
    }
    if (state is! OwnerSuccess && state is! OwnerError) return;
    ref.invalidate(dailySummaryProvider);
    ref.invalidate(activeOrdersProvider);
    ref.invalidate(pendingTablesProvider);
    ref.invalidate(ordersOnTheWayProvider);

    final name = switch (state) {
      OwnerSuccess(:final result) => result.studentName,
      OwnerError(:final result) => result?.studentName,
      _ => null,
    };
    final action = await showDialog<ScanDialogAction>(
      context: context,
      builder: (_) => const ScanResultDialog(),
    );
    if (!context.mounted) return;
    controller.reset();
    ref.invalidate(dailySummaryProvider);
    ref.invalidate(activeOrdersProvider);
    ref.invalidate(pendingTablesProvider);
    ref.invalidate(ordersOnTheWayProvider);

    if (action == ScanDialogAction.scanAgain) continue;
    if (action == ScanDialogAction.sellPlan) {
      await router.push('/owner/vender-plan', extra: name);
    }
    return;
  }
}

enum _Tone { success, warning, danger, neutral }

class _View {
  const _View(this.tone, this.icon, this.title, this.detail, {this.action, this.actionLabel});

  final _Tone tone;
  final IconData icon;
  final String title;
  final String detail;
  final ScanDialogAction? action;
  final String? actionLabel;
}

/// Tarjeta compacta y centrada con el resultado del escaneo.
class ScanResultDialog extends ConsumerStatefulWidget {
  const ScanResultDialog({super.key});

  @override
  ConsumerState<ScanResultDialog> createState() => _ScanResultDialogState();
}

class _ScanResultDialogState extends ConsumerState<ScanResultDialog> {
  late final OwnerState _shown = ref.read(ownerControllerProvider);
  Timer? _timer;
  int _undoSeconds = 0;
  bool _undoing = false;

  bool get _redeemed {
    final shown = _shown;
    return shown is OwnerSuccess && shown.redeemed;
  }

  @override
  void initState() {
    super.initState();
    if (_redeemed) {
      _undoSeconds = 10;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _undoSeconds--);
        if (_undoSeconds <= 0) t.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _undo() async {
    setState(() => _undoing = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await ref.read(ownerControllerProvider.notifier).undoRedeem();
    if (!mounted) return;
    navigator.pop(ScanDialogAction.done);
    showInfoSnackBar(messenger, ok ? 'Descuento revertido' : 'No se pudo deshacer el descuento');
  }

  static String _lunchesLeft(int n) => n == 1 ? 'Le queda 1 almuerzo' : 'Le quedan $n almuerzos';

  _View _view() {
    final shown = _shown;
    if (shown is OwnerSuccess) {
      final r = shown.result;
      final left = r.remainingLunches ?? 0;
      if (r.isWarning) {
        final detail = left > 0 ? '${_lunchesLeft(left)} · ${r.supportingLine}' : r.supportingLine;
        return _View(_Tone.warning, Icons.warning_amber_rounded, r.title, detail,
            action: ScanDialogAction.sellPlan, actionLabel: 'Ofrecer nuevo plan');
      }
      return _View(_Tone.success, Icons.check_circle_outline_rounded, 'Almuerzo registrado', _lunchesLeft(left));
    }
    if (shown is OwnerError) {
      final r = shown.result;
      if (r == null) {
        final msg = shown.message.trim();
        return _View(
          _Tone.danger,
          Icons.qr_code_2_rounded,
          msg.isNotEmpty ? msg : 'Código no legible',
          'Vuelve a intentarlo.',
          action: ScanDialogAction.scanAgain,
          actionLabel: 'Reintentar',
        );
      }
      if (r.isAlreadyRedeemed) {
        final at = r.redeemedAt;
        return _View(_Tone.neutral, Icons.history_rounded, r.title,
            at != null ? 'Se descontó a las ${OwnerFormat.time(at)}' : r.supportingLine);
      }
      if (r.actionRequired == 'VENDER_PLAN') {
        return _View(_Tone.danger, Icons.cancel_outlined, r.title, r.supportingLine,
            action: ScanDialogAction.sellPlan,
            actionLabel: r.studentName != null ? 'Vender nuevo plan' : 'Vender plan');
      }
      if (r.actionRequired == 'NINGUNA') {
        return _View(_Tone.danger, Icons.cancel_outlined, r.title, r.supportingLine);
      }
      return _View(_Tone.danger, Icons.cancel_outlined, r.title, r.supportingLine,
          action: ScanDialogAction.scanAgain, actionLabel: 'Volver a escanear');
    }
    return const _View(_Tone.neutral, Icons.qr_code_2_rounded, 'Sin resultado', 'Escanea un pase para continuar.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final view = _view();
    final name = switch (_shown) {
      OwnerSuccess(:final result) => result.studentName,
      OwnerError(:final result) => result?.studentName,
      _ => null,
    };
    final (Color bg, Color fg) = switch (view.tone) {
      _Tone.success => (b.successContainer, b.success),
      _Tone.warning => (colors.primaryContainer, colors.onPrimaryContainer),
      _Tone.danger => (b.dangerContainer, b.onDangerContainer),
      _Tone.neutral => (colors.surfaceContainerHighest, colors.onSurface),
    };
    final pop = Navigator.of(context).pop;
    const buttonSize = Size.fromHeight(52);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  Icon(view.icon, size: 52, color: fg),
                  const SizedBox(height: 10),
                  if (name != null)
                    Text(name,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.1, color: fg)),
                  const SizedBox(height: 4),
                  Text(view.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
                  const SizedBox(height: 4),
                  Text(view.detail,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                ]),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  tooltip: 'Cerrar',
                  style: IconButton.styleFrom(backgroundColor: colors.surface.withValues(alpha: 0.7)),
                  onPressed: () => pop(ScanDialogAction.done),
                  icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            if (view.action != null) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: buttonSize),
                onPressed: _undoing ? null : () => pop(view.action),
                child: Text(view.actionLabel!),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: buttonSize),
                onPressed: _undoing ? null : () => pop(ScanDialogAction.done),
                child: const Text('Listo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ] else
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: buttonSize),
                onPressed: _undoing ? null : () => pop(ScanDialogAction.done),
                child: const Text('Listo'),
              ),
            if (_undoSeconds > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: b.successContainer,
                    child: Text('$_undoSeconds',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: b.success)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Almuerzo descontado',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onSurface)),
                  ),
                  TextButton(
                    onPressed: _undoing ? null : _undo,
                    child: const Text('Deshacer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
