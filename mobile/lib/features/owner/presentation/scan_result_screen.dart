import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'sell_plan_modal.dart';

/// Variante visual del resultado.
enum _Tone { success, warning, danger, neutral }

/// Resultado del escaneo: confirmación de canje (verde / advertencia) o
/// rechazo (rojo / gris). Lee el estado de [ownerControllerProvider].
class ScanResultScreen extends ConsumerStatefulWidget {
  const ScanResultScreen({super.key});

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  bool _confirming = false;

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    await ref.read(ownerControllerProvider.notifier).confirmRedeem();
    if (mounted) setState(() => _confirming = false);
  }

  Future<void> _sellPlan(ScanResult result) async {
    final name = result.studentName;
    if (name == null) return;
    final sold = await showSellPlanModal(context, studentIdentifier: name);
    if (sold == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plan vendido. Vuelve a escanear para validar.'),
        ),
      );
    }
  }

  void _scanAgain() {
    ref.read(ownerControllerProvider.notifier).startScanning();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/owner/scanner');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);

    final ScanResult? result;
    final String? errorMessage;
    final bool redeemed;
    switch (state) {
      case OwnerSuccess(result: final r, redeemed: final done):
        result = r;
        errorMessage = null;
        redeemed = done;
      case OwnerError(result: final r, :final message):
        result = r;
        // Si el pase era válido, el error vino de confirmar el canje.
        errorMessage = (r == null || r.isValid) ? message : null;
        redeemed = false;
      default:
        result = null;
        errorMessage = 'No hay un resultado de escaneo para mostrar.';
        redeemed = false;
    }

    final view = _ResultView.from(
      result: result,
      errorMessage: errorMessage,
      redeemed: redeemed,
    );

    final canConfirm = state is OwnerSuccess && !redeemed;
    final canSell =
        result != null &&
        result.actionRequired == 'VENDER_PLAN' &&
        result.studentName != null &&
        !redeemed;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Resultado'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: _ResultCard(view: view, result: result),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  if (canConfirm) ...[
                    ElevatedButton(
                      onPressed: _confirming ? null : _confirm,
                      child: _confirming
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: context.colorScheme.onPrimary,
                              ),
                            )
                          : const Text('CONFIRMAR VALIDACIÓN'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (canSell) ...[
                    // Un solo botón relleno por grupo: si ya hay "Confirmar",
                    // vender plan va como acción secundaria.
                    if (canConfirm)
                      OutlinedButton(
                        onPressed: () => _sellPlan(result!),
                        child: const Text('VENDER PLAN'),
                      )
                    else
                      ElevatedButton(
                        onPressed: () => _sellPlan(result!),
                        child: const Text('VENDER PLAN'),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (canConfirm || canSell)
                    OutlinedButton(
                      onPressed: _confirming ? null : _scanAgain,
                      child: const Text('Volver a Escanear'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _scanAgain,
                      child: const Text('Volver a Escanear'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Textos y tono ya resueltos para pintar la tarjeta.
class _ResultView {
  const _ResultView({
    required this.tone,
    required this.icon,
    required this.title,
    required this.detail,
    this.balanceLabel,
  });

  final _Tone tone;
  final IconData icon;
  final String title;
  final String detail;

  /// Ej.: "13/20 restantes". Solo cuando hay saldo que informar.
  final String? balanceLabel;

  factory _ResultView.from({
    required ScanResult? result,
    required String? errorMessage,
    required bool redeemed,
  }) {
    if (result == null || errorMessage != null) {
      return _ResultView(
        tone: _Tone.danger,
        icon: Icons.error_outline,
        title: 'No se pudo completar',
        detail: errorMessage ?? 'Intenta escanear de nuevo.',
      );
    }

    final balance =
        (result.remainingLunches != null &&
            result.totalLunches != null &&
            result.isValid)
        ? '${result.remainingLunches}/${result.totalLunches} restantes'
        : null;

    if (result.isValid && redeemed) {
      return _ResultView(
        tone: _Tone.success,
        icon: Icons.check_circle,
        title: 'Almuerzo registrado',
        detail: 'Almuerzo descontado del plan.',
        balanceLabel: balance,
      );
    }
    if (result.isSuccess) {
      return _ResultView(
        tone: _Tone.success,
        icon: Icons.check_circle,
        title: 'Pase válido',
        detail: 'Confirma para descontar el almuerzo.',
        balanceLabel: balance,
      );
    }
    if (result.isWarning) {
      return _ResultView(
        tone: _Tone.warning,
        icon: Icons.warning_amber_rounded,
        title: result.title,
        detail: result.supportingLine,
        balanceLabel: balance,
      );
    }
    if (result.isAlreadyRedeemed) {
      final at = result.redeemedAt;
      return _ResultView(
        tone: _Tone.neutral,
        icon: Icons.history,
        title: result.title,
        detail: at != null
            ? 'Pase consumido hoy a las ${OwnerFormat.time(at)}'
            : result.supportingLine,
      );
    }
    return _ResultView(
      tone: _Tone.danger,
      icon: Icons.cancel,
      title: result.title,
      detail: result.supportingLine,
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.view, required this.result});

  final _ResultView view;
  final ScanResult? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.colorScheme;
    final tokens = context.bocadooColors;

    final (Color bg, Color fg) = switch (view.tone) {
      _Tone.success => (tokens.successContainer, tokens.onSuccessContainer),
      _Tone.warning => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _Tone.danger => (tokens.dangerContainer, tokens.onDangerContainer),
      _Tone.neutral => (scheme.surface, scheme.onSurface),
    };

    final name = result?.studentName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: view.tone == _Tone.neutral
            ? Border.all(color: scheme.outlineVariant)
            : null,
      ),
      child: Column(
        children: [
          Icon(view.icon, size: 56, color: fg),
          const SizedBox(height: 12),
          Text(
            view.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (name != null) ...[
            const SizedBox(height: 20),
            _StudentAvatar(
              name: name,
              imageUrl: result?.studentAvatar,
              foreground: fg,
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (result?.studentCareer != null)
              Text(
                result!.studentCareer!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fg.withValues(alpha: 0.8),
                ),
              ),
          ],
          if (view.balanceLabel != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: Text(
                view.balanceLabel!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            view.detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentAvatar extends StatelessWidget {
  const _StudentAvatar({
    required this.name,
    required this.imageUrl,
    required this.foreground,
  });

  final String name;
  final String? imageUrl;
  final Color foreground;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final second = parts.length > 1 ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      _initials,
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
    );
    return CircleAvatar(
      radius: 36,
      backgroundColor: foreground.withValues(alpha: 0.14),
      foregroundImage: (imageUrl != null && imageUrl!.isNotEmpty)
          ? NetworkImage(imageUrl!)
          : null,
      child: initials,
    );
  }
}
