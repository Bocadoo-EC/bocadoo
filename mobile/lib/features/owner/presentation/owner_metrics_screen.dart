import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/external_links.dart';
import '../domain/models/metrics_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';
import 'weekly_summary_preview.dart';

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _decimal(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// O14 · Tus números: pestañas Hoy, Dinero y Clientes.
class OwnerMetricsScreen extends ConsumerStatefulWidget {
  const OwnerMetricsScreen({super.key});

  @override
  ConsumerState<OwnerMetricsScreen> createState() => _OwnerMetricsScreenState();
}

class _OwnerMetricsScreenState extends ConsumerState<OwnerMetricsScreen> {
  int _tab = 0;
  MetricsPeriod _period = MetricsPeriod.semana;

  Future<void> _writeWhatsApp(ClientFollowUp c) => openExternal(
        context,
        whatsAppUri(
          'Hola ${c.name.split(' ').first}, te escribimos de ${ref.read(ownerRestaurantNameProvider)}.',
          phone: toInternationalPhone(c.phone),
        ),
        failMessage: 'No se pudo abrir WhatsApp',
      );

  Future<void> _setWeekly(bool enabled) async {
    await ref
        .read(ownerMetricsRepositoryProvider)
        .setWeeklySummary(ref.read(ownerRestaurantIdProvider), enabled: enabled);
    if (mounted) ref.invalidate(metricsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final now = DateTime.now();
    final metrics = ref.watch(metricsProvider(_period));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Tus números', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
              Text(
                '${ref.watch(ownerRestaurantNameProvider)} · '
                '${_capitalize(_weekdays[now.weekday - 1])} ${now.day} de ${_months[now.month - 1]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              OwnerSegmented(
                labels: const ['Hoy', 'Dinero', 'Clientes'],
                icons: const [Icons.calendar_today_outlined, Icons.payments_outlined, Icons.group_outlined],
                index: _tab,
                filledSelected: true,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ]),
          ),
          Expanded(
            child: metrics.when(
              skipLoadingOnReload: true,
              loading: () => const OwnerLoadingView('Sacando tus números…'),
              error: (_, _) => OwnerErrorView(
                title: 'No pudimos traer tus números',
                message: 'Revisa tu conexión e inténtalo de nuevo.',
                onRetry: () => ref.invalidate(metricsProvider(_period)),
              ),
              data: (m) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: switch (_tab) {
                  0 => [
                      _DayCard(m: m, weekday: _weekdays[now.weekday - 1]),
                      _DishesCard(m: m),
                      _OpinionsLink(onTap: () => context.push('/owner/opiniones')),
                    ],
                  1 => [
                      _PendingCard(m: m),
                      if (ApiCapabilities.expiredLunchesReport) _ExpiredCard(m: m),
                      _SalesCard(m: m, period: _period, onPeriod: (p) => setState(() => _period = p)),
                    ],
                  _ => [
                      _FollowUpCard(
                        title: 'Por renovar',
                        subtitle: 'Su plan vence en los próximos 5 días',
                        icon: Icons.autorenew_rounded,
                        clients: m.renewals,
                        empty: 'Nadie tiene que renovar esta semana.',
                        detail: (c) => switch (c.days) {
                          <= 0 => 'Vence hoy',
                          1 => 'Vence mañana',
                          _ => 'Vence en ${c.days} días',
                        },
                        onWrite: _writeWhatsApp,
                      ),
                      _FollowUpCard(
                        title: 'No han vuelto',
                        subtitle: 'Tienen plan, pero +7 días sin venir',
                        icon: Icons.person_off_outlined,
                        clients: m.absent,
                        empty: 'Todos tus clientes con plan están viniendo. ¡Bien!',
                        detail: (c) => '${c.days} días sin venir · le quedan ${c.lunchesLeft}',
                        onWrite: _writeWhatsApp,
                      ),
                      _PeakCard(m: m),
                      _WeeklySummaryCard(
                        m: m,
                        localName: ref.watch(ownerRestaurantNameProvider),
                        onChanged: _setWeekly,
                      ),
                    ],
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Acceso a O15 desde Métricas, con las opiniones sin responder.
class _OpinionsLink extends ConsumerWidget {
  const _OpinionsLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final pending = ref.watch(opinionsProvider).value?.where((o) => o.isPending).length ?? 0;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.forum_outlined, size: 18, color: colors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Opiniones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
                Text(
                  pending == 0 ? 'Rico, Rápido, Porción y sus notas' : '$pending sin responder',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.icon, required this.children, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: colors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            ]),
          ),
          ?trailing,
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber(this.value, this.unit);

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: value,
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: colors.onSurface),
        ),
        TextSpan(
          text: '  $unit',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text, {this.color, this.weight = FontWeight.w600});

  final String text;
  final Color? color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text,
            style: TextStyle(fontSize: 13, fontWeight: weight, color: color ?? context.colorScheme.onSurfaceVariant)),
      );
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.m, required this.weekday});

  final OwnerMetrics m;
  final String weekday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.bocadooColors;
    final colors = context.colorScheme;
    final last = m.servedLastWeekSameTime;
    final diff = last == null ? 0 : m.servedToday - last;
    // Valor aproximado: almuerzos servidos × precio del almuerzo suelto.
    final price = ref.watch(lunchPriceProvider).value;
    return _MetricCard(title: 'Almuerzos de hoy', icon: Icons.restaurant_rounded, children: [
      if (m.servedToday == 0)
        const _Muted('Todavía no sirves almuerzos hoy. Aquí verás cómo va el día.')
      else ...[
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _BigNumber('${m.servedToday}', 'servidos'),
          const Spacer(),
          if (price != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${OwnerFormat.money(m.servedToday * price)} aprox.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.primary)),
            ),
        ]),
        if (last == null)
          const _Muted('La semana pasada a esta hora no habías servido')
        else
          _Muted(
            '${diff >= 0 ? '+' : ''}$diff vs. el $weekday pasado a esta hora',
            color: diff >= 0 ? b.success : b.danger,
            weight: FontWeight.w800,
          ),
      ],
      _Muted('${m.pendingLunches} almuerzos por servir en planes activos'),
    ]);
  }
}

class _DishesCard extends StatelessWidget {
  const _DishesCard({required this.m});

  final OwnerMetrics m;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final top = m.dishes.isEmpty ? 1 : m.dishes.map((d) => d.orders).reduce((a, b) => a > b ? a : b);
    final rated = [for (final d in m.dishes) if (d.rating != null) d];
    final worst = rated.isEmpty ? null : rated.reduce((a, b) => a.rating! <= b.rating! ? a : b);

    return _MetricCard(
      title: 'Platos más pedidos',
      subtitle: 'Último mes · nota de “¿Qué tal hoy?”',
      icon: Icons.emoji_events_outlined,
      children: [
        if (m.dishes.isEmpty)
          const _Muted('Cuando sirvas almuerzos verás aquí tus platos estrella.')
        else ...[
          for (var i = 0; i < m.dishes.length; i++) ...[
            Row(children: [
              SizedBox(
                width: 24,
                child: Text('${i + 1}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.primary)),
              ),
              Expanded(
                child: Text(m.dishes[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
              ),
              Text('${m.dishes[i].orders} pedidos',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
              const SizedBox(width: 8),
              Icon(Icons.star_rounded, size: 15, color: colors.primary),
              Text(m.dishes[i].rating == null ? 'Sin notas' : _decimal(m.dishes[i].rating!),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurface)),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                child: LinearProgressIndicator(
                  value: m.dishes[i].orders / top,
                  minHeight: 6,
                  backgroundColor: colors.primaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (worst != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('El que menos gusta: ${worst.name} (${_decimal(worst.rating!)})',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurface)),
            ),
        ],
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.m});

  final OwnerMetrics m;

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      title: 'Almuerzos por servir',
      icon: Icons.lunch_dining_outlined,
      children: m.pendingLunches == 0
          ? const [_Muted('No debes almuerzos: nadie tiene planes activos.')]
          : [
              _BigNumber('${m.pendingLunches}', 'almuerzos'),
              const _Muted('Ya los cobraste, pero todavía se los debes a tus clientes.'),
              _Muted('${m.clientsWithPlan} clientes con plan activo'),
            ],
    );
  }
}

class _ExpiredCard extends StatelessWidget {
  const _ExpiredCard({required this.m});

  final OwnerMetrics m;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return _MetricCard(
      title: 'Almuerzos que no se usaron',
      icon: Icons.hourglass_bottom_rounded,
      children: m.expiredLunches == 0
          ? const [_Muted('En el último mes todos usaron sus almuerzos completos.')]
          : [
              _BigNumber('${m.expiredLunches}', 'almuerzos'),
              _Muted(OwnerFormat.money(m.expiredValue), color: b.success, weight: FontWeight.w900),
              const _Muted('Vencieron sin usarse el último mes. Esto ya es ganancia limpia.'),
              if (m.expiredPlans > 0)
                _Muted('≈ ${_decimal(m.expiredLunches / m.expiredPlans)} sin usar por cada plan vencido'),
            ],
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.m, required this.period, required this.onPeriod});

  final OwnerMetrics m;
  final MetricsPeriod period;
  final ValueChanged<MetricsPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final total = m.salesCash + m.salesTransfer;

    Widget row(IconData icon, Color bg, Color fg, String label, double value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(radius: 15, backgroundColor: bg, child: Icon(icon, size: 16, color: fg)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurface)),
            ),
            Text(OwnerFormat.money(value),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ]),
        );

    return _MetricCard(
      title: 'Planes vendidos',
      subtitle: period == MetricsPeriod.semana ? 'Últimos 7 días' : 'Últimos 30 días',
      icon: Icons.sell_outlined,
      children: [
        OwnerSegmented(
          labels: const ['Semana', 'Mes'],
          index: period.index,
          onChanged: (i) => onPeriod(MetricsPeriod.values[i]),
        ),
        const SizedBox(height: 10),
        if (m.plansSold == 0)
          const _Muted('No vendiste planes en este periodo.')
        else ...[
          _BigNumber(OwnerFormat.money(total), '${m.plansSold} planes'),
          const SizedBox(height: 6),
          row(Icons.payments_outlined, b.successContainer, b.success, 'Efectivo', m.salesCash),
          Divider(height: 1, color: colors.outlineVariant),
          row(Icons.smartphone_rounded, colors.primaryContainer, colors.primary, 'Transferencia', m.salesTransfer),
        ],
      ],
    );
  }
}

class _FollowUpCard extends StatefulWidget {
  const _FollowUpCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.clients,
    required this.empty,
    required this.detail,
    required this.onWrite,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<ClientFollowUp> clients;
  final String empty;
  final String Function(ClientFollowUp) detail;
  final ValueChanged<ClientFollowUp> onWrite;

  @override
  State<_FollowUpCard> createState() => _FollowUpCardState();
}

class _FollowUpCardState extends State<_FollowUpCard> {
  static const _preview = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final shown = _all ? widget.clients : widget.clients.take(_preview).toList();
    return _MetricCard(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      children: [
        if (widget.clients.isEmpty)
          _Muted(widget.empty)
        else ...[
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
                    Text(widget.detail(c),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
                  ]),
                ),
                IconButton.filledTonal(
                  tooltip: 'Escribir a ${c.name} por WhatsApp',
                  onPressed: () => widget.onWrite(c),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                ),
              ]),
            ),
          if (widget.clients.length > _preview && !_all)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = true),
                child: Text('Ver todos (${widget.clients.length})'),
              ),
            ),
        ],
      ],
    );
  }
}

class _PeakCard extends StatelessWidget {
  const _PeakCard({required this.m});

  final OwnerMetrics m;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final grid = m.peakGrid;
    if (grid.isEmpty) {
      return const _MetricCard(
        title: 'Horas pico',
        icon: Icons.schedule_rounded,
        children: [_Muted('Aún no hay almuerzos suficientes para ver tus horas pico.')],
      );
    }
    var max = 0, peakDay = 0, peakHour = 0;
    var strongest = 0, strongestSum = -1;
    for (var d = 0; d < grid.length; d++) {
      final sum = grid[d].fold<int>(0, (s, v) => s + v);
      if (sum > strongestSum) {
        strongestSum = sum;
        strongest = d;
      }
      for (var h = 0; h < grid[d].length; h++) {
        if (grid[d][h] > max) {
          max = grid[d][h];
          peakDay = d;
          peakHour = h;
        }
      }
    }

    Widget cell(double t) => Container(
          height: 26,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Color.lerp(colors.primaryContainer, colors.primary, t),
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return _MetricCard(
      title: 'Horas pico',
      subtitle: 'Últimas 4 semanas',
      icon: Icons.schedule_rounded,
      children: [
        Text('Tu hora pico es ${m.peakDays[peakDay].toLowerCase()} ${m.peakHours[peakHour]}',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
        _Muted('Día más fuerte: ${m.peakDays[strongest].toLowerCase()}'),
        const SizedBox(height: 10),
        Row(children: [
          const SizedBox(width: 40),
          for (final h in m.peakHours)
            Expanded(
              child: Text(h,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            ),
        ]),
        for (var d = 0; d < grid.length; d++)
          Row(children: [
            SizedBox(
              width: 40,
              child: Text(m.peakDays[d],
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurface)),
            ),
            for (final v in grid[d]) Expanded(child: cell(max == 0 ? 0 : v / max)),
          ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _Muted('Menos'),
          const SizedBox(width: 6),
          for (final t in const [0.0, 0.33, 0.66, 1.0]) SizedBox(width: 18, child: cell(t)),
          const SizedBox(width: 6),
          _Muted('Más'),
        ]),
      ],
    );
  }
}

class _WeeklySummaryCard extends StatelessWidget {
  const _WeeklySummaryCard({required this.m, required this.localName, required this.onChanged});

  final OwnerMetrics m;
  final String localName;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = m.weeklySummaryEnabled;

    return _MetricCard(
      title: 'Resumen semanal por WhatsApp',
      subtitle: on ? 'Activado' : 'Desactivado',
      icon: Icons.chat_outlined,
      trailing: Switch(value: on, onChanged: onChanged),
      children: [
        const _Muted('Cada lunes a las 8:00 te llega cómo te fue la semana.'),
        const SizedBox(height: 10),
        if (!on)
          const _Muted('No recibirás el resumen hasta que lo actives.')
        else ...[
          const OwnerSectionLabel('Así se verá'),
          const SizedBox(height: 6),
          WeeklySummaryPreview(metrics: m, localName: localName),
        ],
      ],
    );
  }
}
