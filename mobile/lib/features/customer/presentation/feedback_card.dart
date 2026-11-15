import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';

const _tags = ['Rico', 'Rápido', 'Porción'];

/// C10 · "¿Qué tal hoy?": una etiqueta de un toque. Se muestra sobre Mi Pase.
class FeedbackCard extends StatelessWidget {
  const FeedbackCard({super.key, required this.controller});

  final CustomerController controller;

  Future<void> _send(BuildContext context, String tag) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.submitFeedback(tag);
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(ok ? '¡Gracias por tu opinión!' : 'Error al enviar calificación'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('¿Qué tal hoy?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: controller.dismissFeedback,
            icon: Icon(Icons.close_rounded, size: 20, color: colors.onSurfaceVariant),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(children: [
            for (final tag in _tags) ...[
              if (tag != _tags.first) const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: colors.primaryContainer,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => _send(context, tag),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(tag,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
