import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart';

/// C4 · Planes: planes de cada local y estado del plan activo.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(customerControllerProvider);
    final colors = context.colorScheme;

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Planes de almuerzo',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
            const SizedBox(height: 2),
            Text('Ahorra en cada comida y olvídate del efectivo diario',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          ]),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _body(context, controller, controller.state),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context, CustomerController controller, CustomerUiState s) {
    if (s.restaurants.isEmpty && s.isError) {
      return CustomerErrorView(
        title: 'Error al cargar planes',
        message: 'No pudimos cargar los restaurantes disponibles.',
        onRetry: controller.loadDashboard,
      );
    }
    final current = s.plansRestaurantId == null ? null : s.restaurantById(s.plansRestaurantId!);
    if (current == null) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        SkeletonBox(height: 200, radius: 28),
        SizedBox(height: 16),
        SkeletonBox(height: 140, radius: 18),
      ]);
    }

    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final singleCents = (current.singleLunchPrice * 100).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _SummaryCard(restaurant: current, pass: s.passFor(current.id)),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: SectionLabel('Selecciona restaurante')),
          Text('${s.restaurants.length} disponibles',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: s.restaurants.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final r = s.restaurants[i];
              return _RestaurantPill(
                name: r.name,
                selected: r.id == current.id,
                hasPlan: s.passFor(r.id) != null,
                onTap: () => controller.selectPlansRestaurant(r.id),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('Planes disponibles en ${current.name}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: b.successContainer,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
            child: Text('Suelto: ${formatMoney(current.singleLunchPrice)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: b.success)),
          ),
        ]),
        const SizedBox(height: 12),
        if (s.isLoadingPlans)
          for (var i = 0; i < 2; i++) ...[
            const SkeletonBox(height: 120, radius: 18),
            const SizedBox(height: 12),
          ]
        else if (s.planTemplates.isEmpty)
          const _NoPlans()
        else
          for (final plan in s.planTemplates) ...[
            _PlanCard(
              plan: plan,
              singleCents: singleCents,
              onOpen: () => context.push('/customer/planes/${plan.id}'),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 4),
        const _WhyPrepay(),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Restaurant restaurant;
  final CustomerPass? pass;

  const _SummaryCard({required this.restaurant, required this.pass});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final r = restaurant;
    final p = pass;
    final mutedStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: 0.5),
            colors.surface,
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: b.heroGradient, borderRadius: BorderRadius.circular(16)),
            child: Text(monogram(r.name),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: b.imageForeground)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Text('Restaurante seleccionado',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colors.primary)),
              ),
              const SizedBox(height: 2),
              Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 13, color: colors.primary),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(r.address.isEmpty ? r.zone : r.address,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: p != null ? b.successContainer : colors.surface,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              border: p != null ? null : Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              p != null ? 'Plan Activo' : 'Sin plan activo',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: p != null ? b.success : colors.onSurfaceVariant,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Divider(height: 1, color: colors.outlineVariant),
        const SizedBox(height: 14),
        if (p != null) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.planName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onSurface)),
                const SizedBox(height: 2),
                Text('Vence el ${formatShortDate(p.expiresAt)} · Valida con QR en caja', style: mutedStyle),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${p.remainingLunches}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    color: colors.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              Text('de ${p.totalLunches} restantes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
            ]),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: p.totalLunches == 0 ? 0 : p.remainingLunches / p.totalLunches,
              backgroundColor: colors.outlineVariant.withValues(alpha: 0.6),
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${p.totalLunches - p.remainingLunches} consumidos',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            const Spacer(),
            Text(
              '${p.totalLunches == 0 ? 0 : (p.remainingLunches * 100 / p.totalLunches).round()}% disponible',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colors.primary),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: b.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Ahorro activo de hasta \$5,00/mes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: b.success)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => context.go('/customer/pase'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: const Text('Ver pase QR'),
            ),
          ]),
        ] else ...[
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Actualmente no tienes un plan contratado en '),
              TextSpan(text: r.name, style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurface)),
              const TextSpan(text: '. El almuerzo suelto diario cuesta '),
              TextSpan(
                text: formatMoney(r.singleLunchPrice),
                style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurface),
              ),
              const TextSpan(text: '.'),
            ]),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(children: [
              Icon(Icons.lightbulb_outline_rounded, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Con un plan Bocadoo:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ),
              Text('Ahorras hasta \$5,00/mes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: b.success)),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.arrow_downward_rounded, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Selecciona un plan a continuación para solicitarlo sin pago inmediato:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _RestaurantPill extends StatelessWidget {
  final String name;
  final bool selected;
  final bool hasPlan;
  final VoidCallback onTap;

  const _RestaurantPill({required this.name, required this.selected, required this.hasPlan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Material(
      color: selected ? colors.primary : Theme.of(context).scaffoldBackgroundColor,
      shape: StadiumBorder(side: BorderSide(color: selected ? colors.primary : colors.outlineVariant)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: selected ? colors.onPrimary : colors.onSurface,
                )),
            if (hasPlan) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Tienes un plan activo aquí',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: selected ? colors.onPrimary : b.success, shape: BoxShape.circle),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanTemplate plan;
  final int singleCents;
  final VoidCallback onOpen;

  const _PlanCard({required this.plan, required this.singleCents, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final saving = singleCents * plan.lunches - plan.priceCents;
    final unit = switch (plan.category) {
      'DESAYUNO' => 'desayunos',
      'MIXTO' => 'combos',
      _ => 'almuerzos',
    };

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(plan.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.onSurface)),
                    if (saving > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: b.successContainer,
                          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                        ),
                        child: Text('Ahorras ${formatCents(saving)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: b.success)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text('${plan.lunches} $unit · Vigencia de ${plan.validityDays} días hábiles',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatCents(plan.priceCents),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.1, color: colors.primary)),
                Text('${formatCents(plan.perLunchCents)} c/u',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
              ]),
            ]),
            const SizedBox(height: 12),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.verified_user_outlined, size: 16, color: b.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Valida con QR · Ver términos',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ),
              PillAction(
                label: 'Pedir plan',
                icon: Icons.arrow_forward_rounded,
                trailingIcon: true,
                onPressed: onOpen,
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _NoPlans extends StatelessWidget {
  const _NoPlans();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(children: [
        Icon(Icons.info_outline_rounded, size: 24, color: colors.onSurfaceVariant),
        const SizedBox(height: 6),
        Text('Sin planes disponibles',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurface)),
        const SizedBox(height: 2),
        Text('Este restaurante aún no ha publicado planes activos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
      ]),
    );
  }
}

class _WhyPrepay extends StatelessWidget {
  const _WhyPrepay();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    Widget line(String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle_outline_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('¿Por qué prepagar con Bocadoo?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurface)),
        line('Sin colas en caja: muestras tu QR y te sientas a almorzar.'),
        line('Ahorro garantizado de hasta \$5,00 cada mes frente a pagar suelto.'),
        line('Acumulas sellos automáticos para premios y almuerzos gratis.'),
      ]),
    );
  }
}
