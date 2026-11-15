import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/external_links.dart';
import '../domain/models/extras_models.dart';
import 'owner_controller.dart';
import 'owner_widgets.dart';

const _tags = ['Rico', 'Rápido', 'Porción'];

IconData _tagIcon(String tag) => switch (tag) {
      'Rico' => Icons.favorite_outline_rounded,
      'Rápido' => Icons.bolt_rounded,
      'Porción' => Icons.rice_bowl_outlined,
      _ => Icons.chat_bubble_outline_rounded,
    };

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Ahora';
  if (d.inMinutes < 60) return 'Hace ${d.inMinutes} min';
  if (d.inHours < 24) return d.inHours == 1 ? 'Hace 1 hora' : 'Hace ${d.inHours} horas';
  return d.inDays == 1 ? 'Ayer' : 'Hace ${d.inDays} días';
}

enum _Action { thanks, replaceLunch, whatsApp }

/// O15 · Opiniones: calificaciones rápidas (Rico, Rápido, Porción) con la nota
/// del comensal. El dueño agradece, repone un almuerzo o le escribe.
class OpinionesScreen extends ConsumerStatefulWidget {
  const OpinionesScreen({super.key});

  @override
  ConsumerState<OpinionesScreen> createState() => _OpinionesScreenState();
}

class _OpinionesScreenState extends ConsumerState<OpinionesScreen> {
  int _tab = 0;

  void _back() => context.canPop() ? context.pop() : context.go('/owner/settings');

  Future<void> _respond(OwnerOpinion op) async {
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<_Action>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ReplySheet(opinion: op, localName: ref.read(ownerRestaurantNameProvider)),
    );
    if (action == null || !mounted) return;
    if (action == _Action.whatsApp) {
      final phone = op.phone;
      if (phone == null) return;
      await openExternal(
        context,
        whatsAppUri(
          'Hola ${op.dinerName.split(' ').first}, gracias por tu opinión en ${ref.read(ownerRestaurantNameProvider)}.',
          phone: toInternationalPhone(phone),
        ),
        failMessage: 'No se pudo abrir WhatsApp',
      );
      return;
    }
    final reply = action == _Action.replaceLunch ? OpinionReply.replaceLunch : OpinionReply.thanks;
    final repo = ref.read(ownerFeedbackRepositoryProvider);
    final ok = await repo.replyOpinion(ref.read(ownerRestaurantIdProvider), op.id, reply);
    if (!mounted) return;
    ref.invalidate(opinionsProvider);
    if (!ok) {
      showInfoSnackBar(messenger, 'No se pudo enviar la respuesta');
      return;
    }
    showUndoSnackBar(
      messenger,
      label: reply == OpinionReply.replaceLunch
          ? 'Almuerzo repuesto a ${op.dinerName} (+1)'
          : 'Respuesta enviada a ${op.dinerName}',
      onUndo: () async {
        await repo.undoReply(op.id);
        if (mounted) ref.invalidate(opinionsProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final opinions = ref.watch(opinionsProvider);
    final pending = opinions.value?.where((o) => o.isPending).length ?? 0;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
            child: OwnerBackHeader(
              title: 'Opiniones',
              onBack: _back,
              trailing: OwnerBadge(
                label: pending == 1 ? '1 pendiente' : '$pending pendientes',
                background: colors.primaryContainer,
                foreground: colors.onPrimaryContainer,
              ),
            ),
          ),
          Expanded(
            child: opinions.when(
              skipLoadingOnReload: true,
              loading: () => const OwnerLoadingView('Cargando opiniones'),
              error: (_, _) => OwnerErrorView(
                title: 'Error al cargar buzón',
                message: 'No se pudieron obtener las opiniones.',
                onRetry: () => ref.invalidate(opinionsProvider),
              ),
              data: (all) {
                final shown = all.where((o) => _tab == 0 ? o.isPending : !o.isPending).toList();
                return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
                  _TagSummary(opinions: all),
                  const SizedBox(height: 14),
                  OwnerSegmented(
                    labels: const ['Pendientes', 'Respondidas'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(height: 14),
                  if (shown.isEmpty)
                    _Empty(pendingTab: _tab == 0)
                  else
                    for (final op in shown) ...[
                      _OpinionCard(opinion: op, onRespond: () => _respond(op)),
                      const SizedBox(height: 12),
                    ],
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _TagSummary extends StatelessWidget {
  const _TagSummary({required this.opinions});

  final List<OwnerOpinion> opinions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Row(children: [
      for (final tag in _tags) ...[
        if (tag != _tags.first) const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(children: [
              Icon(_tagIcon(tag), size: 20, color: colors.primary),
              const SizedBox(height: 2),
              Text('${opinions.where((o) => o.tag == tag).length}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
              Text(tag, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _OpinionCard extends StatelessWidget {
  const _OpinionCard({required this.opinion, required this.onRespond});

  final OwnerOpinion opinion;
  final VoidCallback onRespond;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final note = opinion.note;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(opinion.dinerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          Text(_ago(opinion.createdAt),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_tagIcon(opinion.tag), size: 14, color: colors.onPrimaryContainer),
              const SizedBox(width: 4),
              Text(opinion.tag,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.format_quote_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                note == null || note.isEmpty ? 'Solo dejó la calificación, sin nota escrita.' : note,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontStyle: note == null || note.isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: note == null || note.isEmpty ? colors.onSurfaceVariant : colors.onSurface,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (opinion.isPending)
          Align(
            alignment: Alignment.centerRight,
            child: OwnerSmallButton(label: 'Responder', icon: Icons.reply_rounded, onPressed: onRespond),
          )
        else
          Row(children: [
            Icon(Icons.check_circle_rounded, size: 18, color: b.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Respondida: ${opinion.reply}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: b.success)),
            ),
          ]),
      ]),
    );
  }
}

class _ReplySheet extends StatelessWidget {
  const _ReplySheet({required this.opinion, required this.localName});

  final OwnerOpinion opinion;
  final String localName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;

    Widget option(_Action action, IconData icon, String title, String subtitle, {bool enabled = true}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: enabled ? colors.surface : colors.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: enabled ? () => Navigator.of(context).pop(action) : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.primaryContainer,
                    child: Icon(icon, size: 18, color: enabled ? colors.primary : colors.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: enabled ? colors.onSurface : colors.onSurfaceVariant,
                          )),
                      Text(subtitle,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
                    ]),
                  ),
                  if (enabled) Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                ]),
              ),
            ),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Responder a ${opinion.dinerName}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 16),
          option(_Action.thanks, Icons.favorite_outline_rounded, 'Agradecer',
              'Le llega un gracias de $localName en la app'),
          option(
            _Action.replaceLunch,
            Icons.add_circle_outline_rounded,
            'Reponer almuerzo',
            opinion.canReplaceLunch ? 'Suma 1 almuerzo a su plan' : 'No tiene un plan activo en tu local',
            enabled: opinion.canReplaceLunch,
          ),
          option(
            _Action.whatsApp,
            Icons.chat_outlined,
            'Escribir por WhatsApp',
            opinion.phone != null ? 'Abre un chat con ${opinion.dinerName.split(' ').first}' : 'No tenemos su celular',
            enabled: opinion.phone != null,
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.pendingTab});

  final bool pendingTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(Icons.forum_outlined, size: 52, color: colors.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(pendingTab ? 'Sin opiniones pendientes' : 'Aún no respondes opiniones',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
        const SizedBox(height: 4),
        Text(pendingTab ? 'No tienes mensajes nuevos de comensales.' : 'Las que respondas aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
      ]),
    );
  }
}
