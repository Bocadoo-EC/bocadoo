import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_bottom_nav.dart';
import 'customer_controller.dart';
import 'plan_checkout_modal.dart';

/// Pantalla principal del Comensal: Pase digital, saldo de almuerzos y QR rotativo.
class PaseScreen extends ConsumerStatefulWidget {
  const PaseScreen({super.key});

  @override
  ConsumerState<PaseScreen> createState() => _PaseScreenState();
}

class _PaseScreenState extends ConsumerState<PaseScreen> {
  Timer? _countdownTimer;
  int _secondsRemaining = BocadooQrParser.getRemainingSecondsInCycle();

  @override
  void initState() {
    super.initState();
    _startQrCountdown();
  }

  void _startQrCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = BocadooQrParser.getRemainingSecondsInCycle();
      // Cuando el ciclo de 30s reinicia, regeneramos el QR automáticamente
      if (remaining > _secondsRemaining) {
        ref.read(customerControllerProvider).refreshQr();
      }
      setState(() {
        _secondsRemaining = remaining;
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final uiState = controller.state;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: switch (uiState.status) {
            CustomerStatus.initial ||
            CustomerStatus.loading when uiState.pass == null =>
              const _PaseShimmerSkeleton(),
            CustomerStatus.error when uiState.pass == null => _PaseErrorView(
                message: uiState.errorMessage ?? 'No pudimos cargar tu pase.',
                onRetry: () => controller.loadDashboard(),
                onLogout: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
              ),
            _ => _buildContent(context, controller, uiState),
          },
          bottomNavigationBar: const CustomerBottomNav(currentIndex: 0),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    CustomerController controller,
    CustomerUiState uiState,
  ) {
    final pass = uiState.pass;

    if (pass == null || pass.remainingLunches <= 0 || pass.status == 'AGOTADO') {
      return _PaseExhaustedView(
        pass: pass,
        onRenew: () => PlanCheckoutModal.show(
          context,
          restaurantId: pass?.restaurantId ?? 'r1',
          restaurantName: pass?.restaurantName ?? 'La Cuchara de San Blas',
          isRenewal: true,
        ),
        onExploreRestaurants: () => context.go('/customer/restaurants'),
        onLogout: () async {
          await ref.read(authProvider.notifier).logout();
          if (context.mounted) context.go('/login');
        },
        onShowHistory: () => _showHistorySheet(context, uiState.history),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;
    final authUser = ref.watch(authProvider).user;
    final displayFirstName =
        ((authUser?.fullName.trim().isNotEmpty ?? false)
                ? authUser!.fullName.trim()
                : pass.studentName.trim())
            .split(' ')
            .first;
    final isExpiredOrEmpty =
        pass.remainingLunches <= 0 || pass.expiresAt.isBefore(DateTime.now());
    final isExpiringSoon = !isExpiredOrEmpty &&
        (pass.remainingLunches <= 3 ||
            pass.expiresAt.difference(DateTime.now()).inDays <= 3);
    final (
      String badgeLabel,
      Color badgeBg,
      Color badgeFg,
    ) = isExpiredOrEmpty
        ? ('AGOTADO', bColor.dangerContainer, bColor.danger)
        : isExpiringSoon
            ? (
                'POR VENCER',
                colors.primaryContainer,
                colors.onPrimaryContainer,
              )
            : ('PLAN ACTIVO', bColor.successContainer, bColor.success);
    final progress = pass.totalLunches > 0
        ? (pass.remainingLunches / pass.totalLunches).clamp(0.0, 1.0)
        : 0.0;

    return RefreshIndicator(
      onRefresh: () => controller.loadDashboard(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. ENCABEZADO HERO CON DEGRADADO MORADO
            Container(
              decoration: BoxDecoration(
                gradient: bColor.heroGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 16,
                20,
                76,
              ),
              child: Column(
                children: [
                  // Top Bar: Perfil + Badge "Pase activo" + Cerrar sesión
                  Row(
                    children: [
                      _UserAvatar(avatarUrl: pass.avatarUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola, $displayFirstName',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.onPrimary.withValues(alpha: 0.85),
                              ),
                            ),
                            Text(
                              pass.restaurantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colors.onPrimary,
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
                          color: badgeBg,
                          borderRadius:
                              BorderRadius.circular(AppTheme.buttonRadius),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: badgeFg,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              badgeLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: badgeFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Cerrar sesión',
                        onPressed: () async {
                          await ref.read(authProvider.notifier).logout();
                          if (context.mounted) context.go('/login');
                        },
                        icon: Icon(
                          Icons.logout_rounded,
                          color: colors.onPrimary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Indicador discreto de Modo Offline cuando se usa el pase en caché
                  if (uiState.isOffline || uiState.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onPrimary.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 14,
                            color: colors.onPrimary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              uiState.isOffline
                                  ? 'Sin conexión · Pase guardado'
                                  : uiState.errorMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Nombre del Plan
                  Text(
                    pass.planName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimary.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Contador protagonista: "14 / 20 Almuerzos"
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${pass.remainingLunches}',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -1,
                          color: colors.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ ${pass.totalLunches} almuerzos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Barra de progreso redondeada
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: colors.onPrimary.withValues(alpha: 0.22),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.onPrimary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Fecha de vencimiento
                  Text(
                    'Vence ${_formatExpiryDate(pass.expiresAt)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.onPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),

            // 2. TARJETA CENTRAL DEL CÓDIGO QR (superpuesta 48px sobre el degradado)
            Transform.translate(
              offset: const Offset(0, -48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: colors.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.10),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Caja blanca fija para QR (siempre #FFFFFF con módulos #2D0050)
                          GestureDetector(
                            onTap: () => _showZoomedQr(context, pass.qrToken),
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
                                    data: pass.qrToken,
                                    version: QrVersions.auto,
                                    size: 185,
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
                          ),

                          const SizedBox(height: 16),

                          // Contador regresivo de validez
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 16,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Se actualiza en ${_secondsRemaining}s',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Botón Actualizar QR
                          OutlinedButton.icon(
                            onPressed: uiState.isRefreshingQr
                                ? null
                                : () {
                                    controller.refreshQr();
                                    setState(() {
                                      _secondsRemaining = BocadooQrParser
                                          .getRemainingSecondsInCycle();
                                    });
                                  },
                            icon: uiState.isRefreshingQr
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.primary,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 20),
                            label: Text(
                              uiState.isRefreshingQr
                                  ? 'Actualizando...'
                                  : 'Actualizar QR',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 3. BOTONES DE ACCIÓN INFERIORES
                    ElevatedButton.icon(
                      onPressed: () => PlanCheckoutModal.show(
                        context,
                        restaurantId: pass.restaurantId,
                        restaurantName: pass.restaurantName,
                        isRenewal: true,
                      ),
                      icon: const Icon(Icons.autorenew_rounded, size: 20),
                      label: const Text('Renovar'),
                    ),

                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: () => context.go('/customer/restaurants'),
                      icon: const Icon(Icons.restaurant_rounded, size: 20),
                      label: const Text('Explorar restaurantes'),
                    ),

                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: () =>
                          _showHistorySheet(context, uiState.history),
                      icon: const Icon(Icons.receipt_long_rounded, size: 20),
                      label: Text(
                        'Historial de consumos (${uiState.history.length})',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showZoomedQr(BuildContext context, String qrData) {
    final bColor = context.bocadooColors;
    final colors = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tu pase digital',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bColor.qrBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 230,
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
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHistorySheet(
    BuildContext context,
    List<ConsumptionRecord> records,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.88,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Historial de consumos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            if (records.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'Aún no registras consumos.',
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final item = records[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: bColor.successContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.restaurant_menu_rounded,
                              color: bColor.success,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.restaurantName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatRecordDate(item.date),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '-${item.lunchesUsed}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                              ),
                              Text(
                                'Quedan ${item.remainingAfter}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatExpiryDate(DateTime date) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  static String _formatRecordDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$dd/$mm · $hh:$min';
  }
}

class _UserAvatar extends StatelessWidget {
  final String? avatarUrl;

  const _UserAvatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.onPrimary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        image: avatarUrl != null && avatarUrl!.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Icon(Icons.person_rounded, color: colors.onPrimary, size: 22)
          : null,
    );
  }
}

/// Estado visual: Pase agotado o sin planes activos
class _PaseExhaustedView extends StatelessWidget {
  final CustomerPass? pass;
  final VoidCallback onRenew;
  final VoidCallback onExploreRestaurants;
  final VoidCallback onLogout;
  final VoidCallback onShowHistory;

  const _PaseExhaustedView({
    required this.pass,
    required this.onRenew,
    required this.onExploreRestaurants,
    required this.onLogout,
    required this.onShowHistory,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Cerrar sesión',
                onPressed: onLogout,
                icon: Icon(Icons.logout_rounded, color: colors.onSurface),
              ),
            ),
            const Spacer(),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.restaurant_rounded,
                size: 38,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              pass == null ? 'Sin planes activos' : 'Sin almuerzos',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Encuentra un restaurante cercano y adquiere o renueva tu paquete.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onRenew,
              icon: const Icon(Icons.autorenew_rounded),
              label: const Text('Renovar'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onExploreRestaurants,
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Explorar restaurantes'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onShowHistory,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Ver historial'),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Estado visual: Error al cargar el pase
class _PaseErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  const _PaseErrorView({
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Cerrar sesión',
                onPressed: onLogout,
                icon: Icon(Icons.logout_rounded, color: colors.onSurface),
              ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: colors.error),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 44,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Error al cargar pase',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: colors.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    ),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Estado visual: Shimmer Skeleton de carga sin dependencias externas
class _PaseShimmerSkeleton extends StatefulWidget {
  const _PaseShimmerSkeleton();

  @override
  State<_PaseShimmerSkeleton> createState() => _PaseShimmerSkeletonState();
}

class _PaseShimmerSkeletonState extends State<_PaseShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bColor = context.bocadooColors;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = 0.35 + (_controller.value * 0.35);
        final lightBlock = colors.onPrimary.withValues(alpha: pulse * 0.45);
        final surfaceBlock = colors.secondaryContainer.withValues(alpha: pulse);

        return SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: bColor.heroGradient,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(40),
                    bottomRight: Radius.circular(40),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 16,
                  20,
                  76,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _ShimmerBox(width: 44, height: 44, radius: 14, color: lightBlock),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ShimmerBox(width: 90, height: 12, radius: 8, color: lightBlock),
                            const SizedBox(height: 6),
                            _ShimmerBox(width: 150, height: 16, radius: 8, color: lightBlock),
                          ],
                        ),
                        const Spacer(),
                        _ShimmerBox(width: 84, height: 26, radius: 999, color: lightBlock),
                      ],
                    ),
                    const SizedBox(height: 26),
                    _ShimmerBox(width: 160, height: 16, radius: 8, color: lightBlock),
                    const SizedBox(height: 12),
                    _ShimmerBox(width: 140, height: 44, radius: 14, color: lightBlock),
                    const SizedBox(height: 14),
                    _ShimmerBox(width: double.infinity, height: 10, radius: 999, color: lightBlock),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Column(
                          children: [
                            _ShimmerBox(width: 200, height: 200, radius: 24, color: surfaceBlock),
                            const SizedBox(height: 16),
                            _ShimmerBox(width: 140, height: 14, radius: 8, color: surfaceBlock),
                            const SizedBox(height: 16),
                            _ShimmerBox(width: double.infinity, height: 54, radius: 999, color: surfaceBlock),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ShimmerBox(width: double.infinity, height: 56, radius: 999, color: surfaceBlock),
                      const SizedBox(height: 12),
                      _ShimmerBox(width: double.infinity, height: 56, radius: 999, color: surfaceBlock),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final Color color;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
