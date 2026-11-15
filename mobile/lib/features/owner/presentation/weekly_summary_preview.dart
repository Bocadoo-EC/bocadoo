import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/bocadoo_logo.dart';
import '../domain/models/metrics_models.dart';
import 'owner_format.dart';

/// Vista previa del mensaje semanal por WhatsApp (O14 y O16). Íconos de
/// Material en lugar de emojis.
class WeeklySummaryPreview extends StatelessWidget {
  const WeeklySummaryPreview({super.key, required this.metrics, required this.localName});

  final OwnerMetrics metrics;
  final String localName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final star = metrics.dishes.isEmpty ? null : metrics.dishes.first.name;
    final lines = <(IconData, String)>[
      (Icons.restaurant_rounded, '${metrics.weekServed} almuerzos servidos'),
      (Icons.payments_outlined, '${OwnerFormat.money(metrics.weekCollected)} cobrados en planes'),
      (Icons.autorenew_rounded, '${metrics.renewals.length} clientes por renovar'),
      if (star != null) (Icons.star_outline_rounded, 'Plato estrella: $star'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const BocadooLogo.isotipo(size: 22),
            const SizedBox(width: 8),
            Text('Bocadoo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.primary)),
          ]),
          const SizedBox(height: 6),
          Text('¡Hola! Así le fue a $localName esta semana:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface)),
          const SizedBox(height: 4),
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(icon, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface)),
                ),
              ]),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text('lun 08:00',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          ),
        ]),
      ),
    );
  }
}
