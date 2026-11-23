import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

/// Gestor de ofertas activas dentro de Caja: una fila por oferta flash (un
/// plato cada una) con cupos restantes, cronómetro en vivo y acciones para
/// pausarla o cerrarla. No ocupa espacio cuando no hay ofertas.
class FlashOffersManager extends ConsumerStatefulWidget {
  const FlashOffersManager({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  ConsumerState<FlashOffersManager> createState() => _FlashOffersManagerState();
}

class _FlashOffersManagerState extends ConsumerState<FlashOffersManager> {
  static const _refreshEveryTicks = 30;

  Timer? _ticker;
  DateTime _now = DateTime.now();
  int _ticks = 0;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _ticks += 1;
      // Los cupos bajan cuando se canjea en caja: se relee cada 30 s.
      if (_ticks % _refreshEveryTicks == 0) {
        ref.invalidate(activeOffersProvider);
      }
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _togglePause(FlashOffer offer) async {
    final id = offer.id;
    if (id == null || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ownerCashRepositoryProvider);
    final ok = await repo.setOfferPaused(
      ref.read(ownerRestaurantIdProvider),
      id,
      paused: !offer.paused,
    );
    if (!mounted) return;
    ref.invalidate(activeOffersProvider);
    setState(() => _busy.remove(id));
    showInfoSnackBar(
      messenger,
      ok
          ? (offer.paused
                ? '"${offer.title}" se reactivó'
                : '"${offer.title}" quedó en pausa')
          : 'No se pudo cambiar el estado de la oferta',
    );
  }

  Future<void> _close(FlashOffer offer) async {
    final id = offer.id;
    if (id == null || _busy.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar oferta'),
        content: Text(
          'Dejarás de ofrecer "${offer.title}". Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar oferta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(id));
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(ownerCashRepositoryProvider)
        .cancelOffer(ref.read(ownerRestaurantIdProvider), offerId: id);
    if (!mounted) return;
    ref.invalidate(activeOffersProvider);
    setState(() => _busy.remove(id));
    final apiErr = ok || AppMode.useMock
        ? null
        : ref.read(apiOwnerRepositoryProvider).consumeLastError();
    showInfoSnackBar(
      messenger,
      ok ? 'Oferta cerrada' : (apiErr ?? 'No se pudo cerrar la oferta'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final menu = ref.watch(posMenuProvider).value;
    final soldOutIds = <String>{
      if (menu != null)
        for (final c in menu.courses)
          if (c.isSoldOut && (c.dishId ?? '').isNotEmpty) c.dishId!,
    };
    final soldOutNames = <String>{
      if (menu != null)
        for (final c in menu.courses)
          if (c.isSoldOut) c.name.trim().toLowerCase(),
    };
    bool isSoldOutOffer(FlashOffer o) {
      if (o.dishId != null && soldOutIds.contains(o.dishId)) return true;
      if (soldOutNames.isEmpty) return false;
      final parts = o.title.split(' + ').map((p) => p.trim().toLowerCase());
      return parts.any(soldOutNames.contains) ||
          soldOutNames.contains(o.title.trim().toLowerCase());
    }

    final offers = [
      for (final o
          in ref.watch(activeOffersProvider).value ?? const <FlashOffer>[])
        if ((o.endsAt == null || o.endsAt!.isAfter(_now)) && !isSoldOutOffer(o))
          o,
    ];
    if (offers.isEmpty) return const SizedBox.shrink();
    final canPause = ref.read(ownerCashRepositoryProvider).supportsOfferPause;
    final flashCount = offers.where((o) => o.kind == OfferKind.flash).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: colors.primary,
                child: Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  flashCount > 0
                      ? 'Ofertas flash activas ($flashCount)'
                      : 'Ofertas activas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: widget.onCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nueva'),
              ),
            ],
          ),
          for (final o in offers) ...[
            Divider(height: 1, color: colors.primary.withValues(alpha: 0.15)),
            _OfferRow(
              offer: o,
              now: _now,
              canPause: canPause && o.kind == OfferKind.flash,
              busy: o.id != null && _busy.contains(o.id),
              onTogglePause: () => _togglePause(o),
              onClose: () => _close(o),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.offer,
    required this.now,
    required this.canPause,
    required this.busy,
    required this.onTogglePause,
    required this.onClose,
  });

  final FlashOffer offer;
  final DateTime now;
  final bool canPause;
  final bool busy;
  final VoidCallback onTogglePause;
  final VoidCallback onClose;

  static String _remaining(Duration d) {
    final safe = d.isNegative ? Duration.zero : d;
    final h = safe.inHours;
    final m = safe.inMinutes % 60;
    final s = safe.inSeconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}min';
    }
    if (m > 0) {
      return '${m}min ${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final isFlash = offer.kind == OfferKind.flash;
    final endsAt = offer.endsAt;

    final cupos = isFlash
        ? (offer.slots <= 0
            ? 'Agotada (0 de ${offer.totalSlots} cupos)'
            : 'Quedan ${offer.slots} de ${offer.totalSlots} cupos')
        : '${offer.slots} cupos';
    final subtitle = '$cupos · ${OwnerFormat.money(offer.price)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        offer.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (offer.paused) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'En pausa',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (isFlash && endsAt != null)
                  Text(
                    'Termina en ${_remaining(endsAt.difference(now))}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.primary,
                    ),
                  )
                else if (!isFlash)
                  Text(
                    'Promo programada',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else ...[
            if (canPause)
              IconButton(
                tooltip: offer.paused ? 'Reanudar oferta' : 'Pausar oferta',
                onPressed: onTogglePause,
                icon: Icon(
                  offer.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: colors.primary,
                ),
              ),
            IconButton(
              tooltip: 'Cerrar oferta',
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: b.danger),
            ),
          ],
        ],
      ),
    );
  }
}
