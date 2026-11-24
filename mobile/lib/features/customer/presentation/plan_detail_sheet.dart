import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';

/// FASE 3 · Modal Emergente 2: Confirmación Express con Línea de Tiempo de 3 pasos,
/// acordeón colapsado por defecto y redirección directa a `Mi Pase`.
class PlanDetailSheet extends ConsumerStatefulWidget {
  final String planId;

  const PlanDetailSheet({super.key, required this.planId});

  @override
  ConsumerState<PlanDetailSheet> createState() => _PlanDetailSheetState();
}

class _PlanDetailSheetState extends ConsumerState<PlanDetailSheet> {
  bool _showMenuAndTerms = false;
  bool _sending = false;

  Future<void> _confirm(
    CustomerController controller,
    PlanTemplate plan,
    Restaurant restaurant,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.of(context);

    setState(() => _sending = true);
    final ok = await controller.requestPlan(plan, restaurant: restaurant);
    if (!mounted) return;
    setState(() => _sending = false);

    if (!ok) {
      final error = controller.lastActionError;
      if (error != null && error.isNotEmpty) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text(error)),
        );
      }
      return;
    }

    // FASE 4.1 · Cerrar modales abiertos y navegar directo a `Mi Pase`.
    rootNav.popUntil((route) => route.isFirst);
    router.go('/customer/pase');
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    final detail = ref.watch(planDetailProvider(widget.planId));
    final s = controller.state;
    final colors = context.colorScheme;
    final textTheme = Theme.of(context).textTheme;

    PlanTemplate? plan =
        s.planTemplates.where((p) => p.id == widget.planId).firstOrNull;
    Restaurant? restaurant =
        plan == null ? null : s.restaurantById(plan.restaurantId);
    if (plan == null || restaurant == null) {
      final loaded = detail.value;
      plan ??= loaded?.$1;
      restaurant ??= loaded?.$2;
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.84,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Confirmar plan',
                    style: (textTheme.headlineSmall ?? const TextStyle())
                        .copyWith(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          if (plan == null || restaurant == null)
            Expanded(
              child: detail.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomerErrorView(
                      title: 'Error al cargar el plan',
                      message: 'No pudimos cargar el detalle de este plan.',
                      onRetry: () =>
                          ref.invalidate(planDetailProvider(widget.planId)),
                    ),
            )
          else ...[
            Expanded(
              child: _buildExpressBody(
                context,
                controller: controller,
                plan: plan,
                restaurant: restaurant,
              ),
            ),
            Builder(
              builder: (context) {
                final existingPass = s.passFor(restaurant!.id);
                final hasActiveHere = existingPass != null &&
                    existingPass.remainingLunches > 0 &&
                    !existingPass.isExpired;
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasActiveHere) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: context.bocadooColors.successContainer,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: context.bocadooColors.success
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              'Ya tienes un plan activo en este local (${existingPass.remainingLunches} almuerzos disponibles).',
                              textAlign: TextAlign.center,
                              style:
                                  (textTheme.bodySmall ?? const TextStyle())
                                      .copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                        FilledButton(
                          onPressed: (_sending || hasActiveHere)
                              ? null
                              : () =>
                                  _confirm(controller, plan!, restaurant!),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.onPrimary,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: _sending
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: colors.onPrimary,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Confirmar y pedir plan',
                                      style: (textTheme.labelLarge ??
                                              const TextStyle())
                                          .copyWith(
                                        color: colors.onPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.check_rounded, size: 19),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpressBody(
    BuildContext context, {
    required CustomerController controller,
    required PlanTemplate plan,
    required Restaurant restaurant,
  }) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final textTheme = Theme.of(context).textTheme;
    final singleCents = (restaurant.singleLunchPrice * 100).round();
    final totalSingle = singleCents * plan.lunches;
    final saving = (totalSingle - plan.priceCents).clamp(0, totalSingle);
    final includes = controller.planIncludesFor(restaurant, [plan]);
    final unitLabel = switch (plan.category) {
      'DESAYUNO' => 'desayunos',
      'MIXTO' => 'combos',
      _ => 'almuerzos',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        // 1. Tarjeta Resumen Superior
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.primary.withValues(alpha: 0.24)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primaryContainer.withValues(alpha: 0.45),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: b.heroGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      monogram(restaurant.name),
                      style:
                          (textTheme.titleSmall ?? const TextStyle()).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: b.imageForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (textTheme.titleSmall ?? const TextStyle())
                              .copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          '${plan.name} · ${plan.lunches} $unitLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (textTheme.bodySmall ?? const TextStyle()).copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (saving > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: b.successContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Ahorras ${formatCents(saving)}',
                        style:
                            (textTheme.labelSmall ?? const TextStyle()).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: b.success,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total a pagar en caja',
                            style: (textTheme.bodySmall ?? const TextStyle())
                                .copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Vigencia de ${plan.validityDays} días · ${formatCents(plan.perLunchCents)} c/u',
                            style: (textTheme.bodySmall ?? const TextStyle())
                                .copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatCents(plan.priceCents),
                      style: (textTheme.headlineMedium ?? const TextStyle())
                          .copyWith(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. Línea de Tiempo Visual de 3 Pasos ("¿Cómo funciona?")
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Cómo funciona?',
                style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              const _TimelineStep(
                step: '1',
                icon: Icons.touch_app_rounded,
                title: 'Solicita ahora (\$0 hoy)',
                subtitle: 'Reservas tu plan desde la app sin pago anticipado.',
              ),
              const _TimelineStep(
                step: '2',
                icon: Icons.storefront_rounded,
                title: 'Activa en caja',
                subtitle:
                    'Acércate al restaurante y cancela el valor en efectivo o transferencia para habilitar tus almuerzos.',
              ),
              const _TimelineStep(
                step: '3',
                icon: Icons.qr_code_2_rounded,
                title: 'Ordena y usa tu QR',
                subtitle:
                    'Genera tu orden diaria y presenta tu QR en caja para descontar 1 almuerzo.',
                isLast: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 3. Acordeón colapsado por defecto
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () =>
                    setState(() => _showMenuAndTerms = !_showMenuAndTerms),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ver qué incluye el menú y términos',
                          style:
                              (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        _showMenuAndTerms
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showMenuAndTerms)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1, color: colors.outlineVariant),
                      const SizedBox(height: 10),
                      if (includes.isNotEmpty)
                        _TermItem(
                          label: 'Incluye:',
                          text: includes.join(' + '),
                        ),
                      _TermItem(
                        label: 'Horario:',
                        text: 'Válido en horario de atención (${restaurant.schedule}).',
                      ),
                      _TermItem(
                        label: 'Vigencia:',
                        text: '${plan.validityDays} días desde la activación en caja.',
                      ),
                      const _TermItem(
                        label: 'Consumo:',
                        text:
                            'Cada almuerzo se descuenta al escanear el QR de tu orden diaria en caja. Los cupos no usados al vencer no son reembolsables.',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final String step;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(icon, size: 15, color: colors.primary),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: colors.primary.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$step. $title',
                    style: (textTheme.titleSmall ?? const TextStyle()).copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TermItem extends StatelessWidget {
  const _TermItem({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 14,
              color: context.bocadooColors.success,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                fontSize: 12,
                height: 1.35,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
