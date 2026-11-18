import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

enum ScanDialogAction { done, scanAgain, sellPlan, retry, publishMenu }

class ScanDialogResult {
  const ScanDialogResult(
    this.action, {
    this.extraGuests = 0,
    this.undone = false,
  });

  final ScanDialogAction action;
  final int extraGuests;
  final bool undone;
}

/// Abre el escáner (O2) y, si vuelve con un resultado, muestra la tarjeta
/// flotante sobre la pantalla actual. Lo usan Caja y el POS.
Future<void> openScannerFlow(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final controller = ref.read(ownerControllerProvider.notifier);
  while (true) {
    await router.push('/owner/scanner');
    if (!context.mounted) return;
    var state = ref.read(ownerControllerProvider);
    if (state is OwnerRedirect) {
      // Mesa o preorden: se abre su pantalla de cobro (O5 / O12).
      controller.reset();
      await router.push(state.location);
      if (context.mounted) {
        ref.invalidate(dailySummaryProvider);
        ref.invalidate(activeOrdersProvider);
        ref.invalidate(pendingTablesProvider);
        ref.invalidate(ordersOnTheWayProvider);
        unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
      }
      return;
    }
    if (state is! OwnerSuccess && state is! OwnerError) return;

    while (true) {
      if (!context.mounted) return;
      state = ref.read(ownerControllerProvider);
      if (state is! OwnerSuccess && state is! OwnerError) return;

      ref.invalidate(activeOrdersProvider);
      ref.invalidate(pendingTablesProvider);
      ref.invalidate(ordersOnTheWayProvider);

      final name = switch (state) {
        OwnerSuccess(:final result) => result.studentName,
        OwnerError(:final result) => result?.studentName,
        _ => null,
      };
      final dialogResult = await showDialog<ScanDialogResult>(
        context: context,
        builder: (_) => const ScanResultDialog(),
      );
      if (!context.mounted) return;

      final action = dialogResult?.action ?? ScanDialogAction.done;
      final extraGuests = dialogResult?.extraGuests ?? 0;
      final alreadyUndone = dialogResult?.undone ?? false;
      final messenger = ScaffoldMessenger.of(context);

      if (action == ScanDialogAction.retry) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
        await controller.retryLastCode();
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        continue;
      }

      if (!alreadyUndone && state is OwnerSuccess && state.redeemed) {
        final result = state.result;
        final passId = result.passId;
        final isPlanBatch = passId != null &&
            !passId.startsWith('ORD:') &&
            !passId.startsWith('MESA:') &&
            result.remainingLunches != null;
        if (isPlanBatch) {
          final batchId = result.batchRedemptionId ?? passId;
          if (extraGuests > 0) {
            unawaited(
              controller.commitExtraGuests(
                passId: passId,
                extraGuests: extraGuests,
                batchRedemptionId: result.batchRedemptionId,
              ).then((_) {
                if (context.mounted) {
                  ref.read(cajaMovementsProvider.notifier).refresh();
                }
              }),
            );
          }
          final totalRedeemed = 1 + extraGuests;
          final who = result.studentName ?? 'Comensal';
          final undoLabel = totalRedeemed == 1
              ? '1 almuerzo canjeado · $who'
              : '$totalRedeemed almuerzos canjeados · $who';
          showUndoSnackBar(
            messenger,
            label: undoLabel,
            onUndo: () async {
              final ok = await controller.undoBatchRedemption(
                batchId,
                fallbackPassId: passId,
              );
              ref.invalidate(dailySummaryProvider);
              if (context.mounted) {
                unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
              }
              showInfoSnackBar(
                messenger,
                ok
                    ? (totalRedeemed == 1
                        ? 'Descuento revertido'
                        : 'Canje de $totalRedeemed almuerzos revertido')
                    : 'No se pudo deshacer el descuento',
              );
            },
          );
        }
      }

      controller.reset();
      ref.invalidate(dailySummaryProvider);
      ref.invalidate(activeOrdersProvider);
      ref.invalidate(pendingTablesProvider);
      ref.invalidate(ordersOnTheWayProvider);
      unawaited(ref.read(cajaMovementsProvider.notifier).refresh());

      if (action == ScanDialogAction.scanAgain) break;
      if (action == ScanDialogAction.publishMenu) {
        router.go('/owner/menu');
        return;
      }
      if (action == ScanDialogAction.sellPlan) {
        await router.push('/owner/vender-plan', extra: name);
      }
      return;
    }
  }
}

enum _Tone { success, warning, danger, neutral }

class _View {
  const _View(
    this.tone,
    this.icon,
    this.title,
    this.detail, {
    this.dishName,
    this.action,
    this.actionLabel,
  });

  final _Tone tone;
  final IconData icon;
  final String title;
  final String detail;
  final String? dishName;
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
  int _extraGuests = 0;

  bool get _redeemed {
    final shown = _shown;
    return shown is OwnerSuccess && shown.redeemed;
  }

  bool get _supportsExtraGuests {
    final shown = _shown;
    if (shown is! OwnerSuccess || !shown.redeemed) return false;
    final passId = shown.result.passId ?? '';
    if (passId.startsWith('ORD:') || passId.startsWith('MESA:')) return false;
    return shown.result.remainingLunches != null;
  }

  int get _postScanRemaining {
    final shown = _shown;
    if (shown is! OwnerSuccess) return 0;
    return (shown.result.remainingLunches ?? 0).clamp(0, 9999);
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
    navigator.pop(const ScanDialogResult(ScanDialogAction.done, undone: true));
    showInfoSnackBar(messenger, ok ? 'Descuento revertido' : 'No se pudo deshacer el descuento');
  }

  static String _lunchesLeft(int n) => n == 1 ? 'Queda 1 almuerzo' : 'Quedan $n almuerzos';

  _View _view() {
    final shown = _shown;
    if (shown is OwnerSuccess) {
      final r = shown.result;
      final postScan = r.remainingLunches ?? 0;
      final left = _supportsExtraGuests
          ? (postScan - _extraGuests).clamp(0, postScan)
          : postScan;
      if (r.isWarning) {
        final detail = left > 0 ? '${_lunchesLeft(left)} · ${r.supportingLine}' : r.supportingLine;
        return _View(
          _Tone.warning,
          Icons.warning_amber_rounded,
          r.title,
          detail,
          dishName: r.dishName,
          action: ScanDialogAction.sellPlan,
          actionLabel: 'Ofrecer nuevo plan',
        );
      }
      final title = _supportsExtraGuests && _extraGuests > 0
          ? '${1 + _extraGuests} almuerzos canjeados'
          : (r.title.isNotEmpty && r.title != 'Validado' ? r.title : 'Almuerzo canjeado');
      final detail = r.remainingLunches != null ? _lunchesLeft(left) : r.supportingLine;
      return _View(
        _Tone.success,
        Icons.check_circle_outline_rounded,
        title,
        detail,
        dishName: r.dishName,
      );
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
      if (r.isWarning) {
        return _View(
          _Tone.warning,
          Icons.info_outline_rounded,
          r.title,
          r.supportingLine,
        );
      }
      if (r.isAlreadyRedeemed) {
        final at = r.redeemedAt;
        return _View(_Tone.neutral, Icons.history_rounded, r.title,
            at != null ? 'Se descontó a las ${OwnerFormat.time(at)}' : r.supportingLine);
      }
      if (r.actionRequired == 'RETRY_NETWORK') {
        return _View(
          _Tone.danger,
          Icons.wifi_off_rounded,
          r.title,
          r.supportingLine,
          action: ScanDialogAction.retry,
          actionLabel: 'Reintentar',
        );
      }
      if (r.actionRequired == 'PUBLISH_MENU') {
        return _View(
          _Tone.danger,
          Icons.restaurant_menu_rounded,
          r.title,
          r.supportingLine,
          action: ScanDialogAction.publishMenu,
          actionLabel: 'Ir a publicar menú',
        );
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
      _Tone.warning => (b.walletAccent, b.onWalletAccent),
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
                  if (view.dishName != null && view.dishName!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Text(
                        view.dishName!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  tooltip: 'Cerrar',
                  style: IconButton.styleFrom(backgroundColor: colors.surface.withValues(alpha: 0.7)),
                  onPressed: () => pop(
                    ScanDialogResult(
                      ScanDialogAction.done,
                      extraGuests: _extraGuests,
                    ),
                  ),
                  icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
                ),
              ),
            ]),
            if (_supportsExtraGuests) ...[
              const SizedBox(height: 12),
              _ExtraGuestsSelector(
                extraGuests: _extraGuests,
                postScanRemaining: _postScanRemaining,
                disabled: _undoing,
                onChanged: (next) => setState(() => _extraGuests = next),
              ),
            ],
            const SizedBox(height: 16),
            if (view.action != null) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: buttonSize),
                onPressed: _undoing
                    ? null
                    : () => pop(
                          ScanDialogResult(
                            view.action!,
                            extraGuests: _extraGuests,
                          ),
                        ),
                child: Text(view.actionLabel!),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: buttonSize),
                onPressed: _undoing
                    ? null
                    : () => pop(
                          ScanDialogResult(
                            ScanDialogAction.done,
                            extraGuests: _extraGuests,
                          ),
                        ),
                child: const Text('Listo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ] else
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: buttonSize),
                onPressed: _undoing
                    ? null
                    : () => pop(
                          ScanDialogResult(
                            ScanDialogAction.done,
                            extraGuests: _extraGuests,
                          ),
                        ),
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
                    child: Text(
                      _extraGuests > 0
                          ? '${1 + _extraGuests} almuerzos seleccionados'
                          : 'Almuerzo descontado',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onSurface),
                    ),
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

class _ExtraGuestsSelector extends StatelessWidget {
  const _ExtraGuestsSelector({
    required this.extraGuests,
    required this.postScanRemaining,
    required this.disabled,
    required this.onChanged,
  });

  final int extraGuests;
  final int postScanRemaining;
  final bool disabled;
  final ValueChanged<int> onChanged;

  static String _leftText(int n) =>
      n == 1 ? 'Queda 1 almuerzo' : 'Quedan $n almuerzos';

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final totalRedeemed = 1 + extraGuests;
    final finalRemaining = (postScanRemaining - extraGuests).clamp(0, postScanRemaining);
    final summaryLine = extraGuests == 0
        ? '1 almuerzo canjeado · ${_leftText(postScanRemaining)}'
        : '$totalRedeemed almuerzos canjeados · ${_leftText(finalRemaining)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invitados extras:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Quitar invitado',
                visualDensity: VisualDensity.compact,
                onPressed: !disabled && extraGuests > 0
                    ? () => onChanged(extraGuests - 1)
                    : null,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$extraGuests',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colors.onSurface,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Agregar invitado',
                visualDensity: VisualDensity.compact,
                onPressed: !disabled && extraGuests < postScanRemaining
                    ? () => onChanged(extraGuests + 1)
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final add in const [1, 2, 3]) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                    ),
                    onPressed: !disabled && extraGuests + add <= postScanRemaining
                        ? () => onChanged(extraGuests + add)
                        : null,
                    child: Text(
                      '+$add',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (add != 3) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            summaryLine,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
