import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';

/// C5 · Detalle del plan: desglose de ahorro, términos y solicitud.
class PlanDetailSheet extends ConsumerStatefulWidget {
  final String planId;

  const PlanDetailSheet({super.key, required this.planId});

  @override
  ConsumerState<PlanDetailSheet> createState() => _PlanDetailSheetState();
}

class _PlanDetailSheetState extends ConsumerState<PlanDetailSheet> {
  bool _showFullTerms = false;
  bool _sending = false;

  Future<void> _confirm(CustomerController controller, PlanTemplate plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _sending = true);
    final ok = await controller.requestPlan(plan);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      final error = controller.lastActionError;
      if (error != null && error.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    router.pop();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 76),
      content: Text('¡Solicitud de ${plan.name} enviada! Acércate a caja para activar.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    final detail = ref.watch(planDetailProvider(widget.planId));
    final s = controller.state;
    final colors = context.colorScheme;

    PlanTemplate? plan = s.planTemplates.where((p) => p.id == widget.planId).firstOrNull;
    Restaurant? restaurant = plan == null ? null : s.restaurantById(plan.restaurantId);
    if (plan == null || restaurant == null) {
      final loaded = detail.value;
      plan = loaded?.$1;
      restaurant = loaded?.$2;
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Detalle y Términos del Plan',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: colors.onSurface)),
        ),
        if (plan == null || restaurant == null)
          Expanded(
            child: detail.isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomerErrorView(
                    title: 'Error al cargar el plan',
                    message: 'No pudimos cargar el detalle de este plan.',
                    onRetry: () => ref.invalidate(planDetailProvider(widget.planId)),
                  ),
          )
        else ...[
          Expanded(child: _details(context, plan, restaurant)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ElevatedButton(
                onPressed: _sending ? null : () => _confirm(controller, plan!),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(child: Text('Confirmar y solicitar plan', overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ]),
              ),
              const SizedBox(height: 8),
              Text(
                'Solicitas sin pago inmediato · Pagas en caja en efectivo o transferencia al activar',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _details(BuildContext context, PlanTemplate plan, Restaurant restaurant) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final singleCents = (restaurant.singleLunchPrice * 100).round();
    final totalSingle = singleCents * plan.lunches;
    final saving = (totalSingle - plan.priceCents).clamp(0, totalSingle);
    final discount = totalSingle > 0 ? (saving * 100 / totalSingle).round() : 0;
    final soft = Theme.of(context).scaffoldBackgroundColor;
    final muted = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant);

    BoxDecoration box() => BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: box(),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: b.heroGradient, borderRadius: BorderRadius.circular(14)),
              child: Text(monogram(restaurant.name),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: b.imageForeground)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.location_on_outlined, size: 14, color: colors.primary),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(restaurant.address.isEmpty ? restaurant.zone : restaurant.address,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ),
                ]),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 13, color: colors.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text('Horario: ${restaurant.schedule}', style: muted.copyWith(fontSize: 11)),
                ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primaryContainer.withValues(alpha: 0.4), soft],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    ),
                    child: Text('${plan.type} · ${plan.lunches} almuerzos',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colors.primary)),
                  ),
                  const SizedBox(height: 6),
                  Text(plan.name,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, height: 1.15, color: colors.onSurface)),
                  const SizedBox(height: 2),
                  Text('Vigencia de ${plan.validityDays} días hábiles', style: muted),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatCents(plan.priceCents),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1, color: colors.primary)),
                const SizedBox(height: 2),
                Text('${formatCents(plan.perLunchCents)} / comida',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
              ]),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      '${plan.lunches} almuerzos a precio regular (${formatCents(singleCents)} c/u):',
                      style: muted.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(formatCents(totalSingle),
                      style: muted.copyWith(fontWeight: FontWeight.w600, decoration: TextDecoration.lineThrough)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text('Precio especial prepago Bocadoo:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.onSurface)),
                  ),
                  Text(formatCents(plan.priceCents),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.primary)),
                ]),
                if (saving > 0) ...[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: colors.outlineVariant),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.percent_rounded, size: 16, color: b.success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Tu descuento directo ($discount% OFF)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: b.success)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: b.successContainer,
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Text('Ahorras ${formatCents(saving)}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: b.success)),
                    ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: box(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _BoxTitle(icon: Icons.restaurant_menu_rounded, text: '¿Qué incluye cada almuerzo?'),
            const SizedBox(height: 6),
            Text(
              'Cada almuerzo incluye: sopa o crema casera del día, plato fuerte a tu elección (pollo, carne, pescado o plato vegetariano), jugo natural fresco de fruta y postre tradicional de la casa.',
              style: muted.copyWith(height: 1.45),
            ),
            const SizedBox(height: 10),
            const Wrap(spacing: 6, runSpacing: 6, children: [
              _InfoChip(icon: Icons.restaurant_rounded, label: 'Para comer aquí'),
              _InfoChip(icon: Icons.takeout_dining_outlined, label: 'Para llevar (aplica recargo tarrina)'),
              _InfoChip(icon: Icons.bolt_rounded, label: 'Valida con QR sin efectivo'),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: box(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _BoxTitle(icon: Icons.auto_awesome_rounded, text: 'Sobre ${restaurant.name}'),
            const SizedBox(height: 6),
            Text(
              restaurant.description.isEmpty
                  ? 'Comida casera fresca preparada a diario con ingredientes locales de la mejor calidad.'
                  : restaurant.description,
              style: muted.copyWith(height: 1.45),
            ),
            if (restaurant.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final tag in restaurant.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Text(tag,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
                  ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: box(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _showFullTerms = !_showFullTerms),
              child: Row(children: [
                Expanded(
                  child: _BoxTitle(icon: Icons.verified_user_outlined, text: 'Términos y condiciones del plan'),
                ),
                Icon(
                  _showFullTerms ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
              ]),
            ),
            const SizedBox(height: 4),
            _Term(label: 'Vigencia:', text: 'Válido por ${plan.validityDays} días desde el momento de activación.'),
            const _Term(label: 'Validación segura:', text: 'Cada almuerzo se descuenta al escanear tu código QR en caja.'),
            if (_showFullTerms) ...[
              _Term(
                label: 'Horario:',
                text: 'Válido de lunes a viernes en horario de almuerzo (${restaurant.schedule}).',
              ),
              const _Term(
                label: 'No acumulable:',
                text:
                    'Los consumos no utilizados dentro del período caducan automáticamente y no son reembolsables en efectivo.',
              ),
              const _Term(
                label: 'Transferencia:',
                text: 'Puedes utilizar tus almuerzos con amigos en tu misma mesa si vienes acompañado.',
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

class _BoxTitle extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BoxTitle({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Row(children: [
      Icon(icon, size: 16, color: colors.primary),
      const SizedBox(width: 6),
      Flexible(
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurface)),
      ),
    ]);
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: colors.primary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

class _Term extends StatelessWidget {
  final String label;
  final String text;

  const _Term({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.check_circle_outline_rounded, size: 14, color: context.bocadooColors.success),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label ', style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurface)),
              TextSpan(text: text),
            ]),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}
