import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/feedback_rules.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';
import 'feedback_card.dart';

/// C1 · Mi Pase: QR del plan, preorden o mesa, sellos y últimos movimientos.
class PaseScreen extends ConsumerStatefulWidget {
  const PaseScreen({super.key});

  @override
  ConsumerState<PaseScreen> createState() => _PaseScreenState();
}

class _PaseScreenState extends ConsumerState<PaseScreen> {
  Timer? _qrTimer;
  int _lastRemaining = BocadooQrParser.getRemainingSecondsInCycle();

  @override
  void initState() {
    super.initState();
    // El QR del plan rota cada ciclo para que una captura no sirva en caja.
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = BocadooQrParser.getRemainingSecondsInCycle();
      if (remaining > _lastRemaining) {
        ref.read(customerControllerProvider).refreshQr();
      }
      _lastRemaining = remaining;
    });
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.state;
        final hasAnyPassOrLive =
            s.passes.isNotEmpty || s.activeOrder != null || s.activeTable != null;
        if (!hasAnyPassOrLive &&
            (s.isLoading || s.status == CustomerStatus.initial)) {
          return const _PaseSkeleton();
        }
        if (!hasAnyPassOrLive && s.isError) {
          return CustomerErrorView(
            title: 'Error al cargar pase',
            message: s.errorMessage ?? 'No pudimos cargar tu pase.',
            onRetry: controller.loadDashboard,
          );
        }
        final stampRestaurantId = s.currentPass?.restaurantId;
        return RefreshIndicator(
          onRefresh: () => controller.loadDashboard(silent: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(state: s, controller: controller),
                Transform.translate(
                  offset: const Offset(0, -48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _QrCard(state: s, controller: controller),
                        if (shouldShowFeedback(
                          s.pendingFeedback,
                          DateTime.now(),
                        )) ...[
                          const SizedBox(height: 16),
                          FeedbackCard(controller: controller),
                        ],
                        if (stampRestaurantId != null)
                          if (s.stampCards[stampRestaurantId]
                              case final card?) ...[
                            const SizedBox(height: 16),
                            _StampSection(card: card, controller: controller),
                          ],
                        const SizedBox(height: 16),
                        _TableButton(hasTable: s.activeTable != null),
                        const SizedBox(height: 20),
                        _RecentActivity(items: s.recentActivity),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _modeLabel(QrMode mode, CustomerUiState s) => switch (mode) {
  QrMode.plan => 'Mi plan',
  QrMode.preorden => 'Preorden #${s.activeOrder?.orderNumber ?? ''}',
  QrMode.mesa => 'Mesa ${s.activeTable?.time ?? ''}',
};

class _Hero extends StatelessWidget {
  final CustomerUiState state;
  final CustomerController controller;

  const _Hero({
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    final colors = context.colorScheme;
    final fg = b.imageForeground;
    final pass = state.currentPass;
    final modes = state.availableQrModes;
    final mode = state.qrMode;

    return Container(
      decoration: BoxDecoration(
        gradient: b.heroGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 16,
        20,
        72,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.restaurant_rounded, size: 20, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TU ALMUERZO DE HOY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                    Text(
                      pass?.restaurantName ??
                          state.activeOrder?.restaurantName ??
                          'Bocadoo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: pass != null
                      ? b.successContainer
                      : fg.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: pass != null ? b.success : fg,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pass != null ? 'Pase activo' : 'Sin plan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: pass != null ? b.success : fg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.isOffline) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 14, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      'Sin conexión · Código guardado',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (modes.length > 1) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Row(
                  children: [
                    for (final m in modes)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => controller.selectQrMode(m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: m == mode ? colors.surface : null,
                              borderRadius: BorderRadius.circular(
                                AppTheme.buttonRadius,
                              ),
                            ),
                            child: Text(
                              _modeLabel(m, state),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: m == mode ? colors.onSurface : fg,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              children: [
                if (pass != null) ...[
                  Text(
                    pass.restaurantName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _BigCount(
                    value: '${pass.remainingLunches}',
                    unit: 'almuerzos',
                    size: 52,
                    color: fg,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vence ${formatShortDate(pass.expiresAt)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: 0.85),
                    ),
                  ),
                ] else if (state.activeOrder != null) ...[
                  Text(
                    state.activeOrder!.restaurantName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Preorden #${state.activeOrder!.orderNumber}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: fg.withValues(alpha: 0.9),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Ahorra en cada almuerzo',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Adquiere un plan en tu restaurante favorito y olvídate del efectivo diario.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: 0.88),
                    ),
                  ),
                ],
                if (mode == QrMode.preorden && state.activeOrder != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: b.successContainer,
                      borderRadius: BorderRadius.circular(
                        AppTheme.buttonRadius,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: b.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state.activeOrder!.status == 'LISTO'
                              ? 'Listo para entregar'
                              : 'Preparando tu plato',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: b.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.activeOrder!.detail.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      state.activeOrder!.detail,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ],
                if (mode == QrMode.mesa && state.activeTable != null) ...[
                  const SizedBox(height: 8),
                  _BigCount(
                    value: '${state.activeTable!.membersCount}',
                    unit: 'en la mesa · ${state.activeTable!.time}',
                    size: 44,
                    color: fg,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigCount extends StatelessWidget {
  final String value;
  final String unit;
  final double size;
  final Color color;

  const _BigCount({
    required this.value,
    required this.unit,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -1,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            unit,
            style: TextStyle(
              fontSize: size > 48 ? 18 : 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _QrCard extends StatelessWidget {
  final CustomerUiState state;
  final CustomerController controller;

  const _QrCard({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final mode = state.qrMode;
    final linkStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: colors.primary,
      decoration: TextDecoration.underline,
      decorationColor: colors.primary,
    );
    final hintStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colors.onSurfaceVariant,
    );

    if (state.availableQrModes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.local_offer_rounded,
                size: 30,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Todavía no tienes un plan activo',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Elige un paquete semanal o mensual y presenta tu QR en caja para ahorrar en cada comida.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/customer/plans'),
                icon: const Icon(Icons.confirmation_number_outlined),
                label: const Text('Ver planes y ahorrar'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/customer/restaurants'),
              child: Text('Explorar restaurantes cercanos', style: linkStyle),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () =>
                _showZoomedQr(context, state.qrValue, _modeLabel(mode, state)),
            child: Container(
              width: 208,
              height: 208,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: b.qrBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _Qr(value: state.qrValue, size: 160),
                  Positioned(
                    right: -16,
                    bottom: -16,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 14,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mode == QrMode.preorden && state.activeOrder != null) ...[
            const SizedBox(height: 12),
            Text(
              'Al escanear se descuenta de tu plan',
              textAlign: TextAlign.center,
              style: hintStyle,
            ),
            TextButton(
              onPressed: () => context.push(
                '/customer/pedido/${state.activeOrder!.orderNumber}',
              ),
              child: Text('Ver estado del pedido', style: linkStyle),
            ),
          ],
          if (mode == QrMode.mesa && state.activeTable != null) ...[
            const SizedBox(height: 12),
            Text(
              'Tus amigos lo escanean para unirse. En caja: una cuenta o cada uno lo suyo.',
              textAlign: TextAlign.center,
              style: hintStyle,
            ),
            TextButton(
              onPressed: () => context.push('/customer/mesa'),
              child: Text('Ver mesa y compartir', style: linkStyle),
            ),
          ],
          if (mode == QrMode.plan && state.passes.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundIcon(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Restaurante anterior',
                  onTap: controller.previousPass,
                ),
                const SizedBox(width: 16),
                Text(
                  '${state.passIndex + 1} de ${state.passes.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                _RoundIcon(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Siguiente restaurante',
                  onTap: controller.nextPass,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showZoomedQr(BuildContext context, String value, String label) {
    final colors = context.colorScheme;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar QR ampliado',
      pageBuilder: (ctx, _, _) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Material(
          color: colors.surface,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: ctx.bocadooColors.qrBackground,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: _Qr(value: value, size: 280),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Toca en cualquier lugar para cerrar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: 'Cerrar QR ampliado',
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Qr extends StatelessWidget {
  final String value;
  final double size;

  const _Qr({required this.value, required this.size});

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return QrImageView(
      data: value.isEmpty ? 'BOCADOO' : value,
      version: QrVersions.auto,
      size: size,
      padding: EdgeInsets.zero,
      backgroundColor: b.qrBackground,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: b.qrForeground),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: b.qrForeground,
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
      ),
      icon: Icon(icon, size: 24),
    );
  }
}

class _StampSection extends StatelessWidget {
  final StampCard card;
  final CustomerController controller;

  const _StampSection({required this.card, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final rows = <List<int>>[];
    for (var i = 1; i <= card.goal; i += 5) {
      rows.add([for (var n = i; n < i + 5 && n <= card.goal; n++) n]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        AppTheme.buttonRadius,
                      ),
                    ),
                    child: Text(
                      '${card.current}/${card.goal}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final n in row)
                        _Stamp(number: n, done: n <= card.current),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Premio: ${card.reward}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: colors.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Tus sellos y premios no caducan',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        if (card.rewardsAvailable > 0) ...[
          const SizedBox(height: 12),
          if (ApiCapabilities.claimStampReward)
            ElevatedButton(
              onPressed: () => controller.claimReward(card.restaurantId),
              child: Text(
                card.rewardsAvailable > 1
                    ? 'Reclamar premio (${card.rewardsAvailable} disponibles)'
                    : 'Reclamar premio',
              ),
            )
          else
            Text(
              'Muéstralo en caja.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
        ],
      ],
    );
  }
}

class _Stamp extends StatelessWidget {
  final int number;
  final bool done;

  const _Stamp({required this.number, required this.done});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? colors.primary : colors.surface,
        shape: BoxShape.circle,
        border: done
            ? null
            : Border.all(color: colors.outlineVariant, width: 1.5),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 22, color: colors.onPrimary)
          : Text(
              '$number',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
    );
  }
}

class _TableButton extends StatelessWidget {
  final bool hasTable;

  const _TableButton({required this.hasTable});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return OutlinedButton.icon(
      onPressed: () => context.push('/customer/mesa'),
      style: OutlinedButton.styleFrom(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.onSurface,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      icon: Icon(Icons.group_outlined, size: 18, color: colors.primary),
      label: Text(hasTable ? 'Mi mesa' : 'Mesa con amigos'),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  final List<ActivityItem> items;

  const _RecentActivity({required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: SectionLabel('Últimos movimientos'),
        ),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Aún sin movimientos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final t in items.take(5))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      switch (t.kind) {
                        'plan' => Icons.shopping_bag_outlined,
                        'lunch' => Icons.restaurant_rounded,
                        _ => Icons.receipt_long_outlined,
                      },
                      size: 17,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          t.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: t.positive ? b.success : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _PaseSkeleton extends StatelessWidget {
  const _PaseSkeleton();

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    final light = b.imageForeground.withValues(alpha: 0.2);
    return Semantics(
      label: 'Cargando pase',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 300,
            decoration: BoxDecoration(
              gradient: b.heroGradient,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(40),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 16,
              20,
              72,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: light,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 150,
                      height: 14,
                      decoration: BoxDecoration(
                        color: light,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 180,
                  height: 18,
                  decoration: BoxDecoration(
                    color: light,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 130,
                  height: 48,
                  decoration: BoxDecoration(
                    color: light,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -48),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkeletonBox(height: 248, radius: 32),
                  SizedBox(height: 16),
                  SkeletonBox(height: 52, radius: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
