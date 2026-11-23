import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../customer_controller.dart';
import '../customer_widgets.dart';
import 'flash_offer_card.dart';

/// Abre la confirmación de orden de una oferta flash (combo ya elegido).
Future<void> showFlashOrderSheet(
  BuildContext context, {
  required Restaurant restaurant,
  required RestaurantOffer offer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FlashOrderSheet(restaurantId: restaurant.id, offerId: offer.id),
  );
}

/// Confirmación de orden con el combo exacto de la oferta al precio flash.
/// Al confirmar se descuenta 1 cupo; si el reloj llega a 00:00 o los cupos a 0
/// la oferta deja de poder pedirse en tiempo real.
class FlashOrderSheet extends ConsumerStatefulWidget {
  const FlashOrderSheet({super.key, required this.restaurantId, required this.offerId});

  final String restaurantId;
  final String offerId;

  @override
  ConsumerState<FlashOrderSheet> createState() => _FlashOrderSheetState();
}

class _FlashOrderSheetState extends ConsumerState<FlashOrderSheet> {
  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _takeaway = false;
  bool _sending = false;

  /// Hora de llegada elegida (instante UTC). Debe caer entre ahora + 10 min y
  /// el fin de la oferta que fijó el Dueño.
  DateTime? _arrival;
  String? _arrivalError;
  List<DateTime> _chips = const [];

  static const _minLead = Duration(minutes: 10);

  /// Ecuador (UTC-5) como `HH:mm`.
  static String _hhmm(DateTime instant) {
    final t = instant.toUtc().subtract(const Duration(hours: 5));
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Ventana válida de llegada; `null` si ya no queda margen.
  ({DateTime min, DateTime? max})? _window(RestaurantOffer offer, DateTime now) {
    final min = now.add(_minLead);
    final max = offer.endsAt;
    if (max != null && max.isBefore(min)) return null;
    return (min: min, max: max);
  }

  bool _inWindow(DateTime t, ({DateTime min, DateTime? max}) w) =>
      !t.isBefore(w.min) && (w.max == null || !t.isAfter(w.max!));

  static String _rangeText(({DateTime min, DateTime? max}) w) =>
      w.max == null ? 'desde ${_hhmm(w.min)}' : 'entre ${_hhmm(w.min)} y ${_hhmm(w.max!)}';

  List<DateTime> _buildChips(RestaurantOffer offer) {
    final now = DateTime.now();
    final w = _window(offer, now);
    if (w == null) return const [];
    DateTime floorMin(DateTime d) => DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);
    final out = <DateTime>[];
    for (final c in [
      floorMin(now.toUtc().add(const Duration(minutes: 15))),
      floorMin(now.toUtc().add(const Duration(minutes: 30))),
      if (w.max != null) floorMin(w.max!.toUtc()),
    ]) {
      if (_inWindow(c, w) && !out.any((o) => o.isAtSameMomentAs(c))) out.add(c);
    }
    return out;
  }

  Future<void> _pickArrival(RestaurantOffer offer) async {
    final w = _window(offer, DateTime.now());
    if (w == null) return;
    final ec = (_arrival ?? w.min).toUtc().subtract(const Duration(hours: 5));
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: ec.hour, minute: ec.minute),
      helpText: 'Llegas ${_rangeText(w)}',
    );
    if (picked == null || !mounted) return;
    final instant = EcuadorTime.todayAtUtc(
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
    final fresh = _window(offer, DateTime.now());
    if (fresh == null || !_inWindow(instant, fresh)) {
      setState(() => _arrivalError =
          fresh == null ? 'La oferta ya no admite llegadas.' : 'Elige una hora ${_rangeText(fresh)}.');
      return;
    }
    setState(() {
      _arrival = instant;
      _arrivalError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    final restaurant = ref.read(customerControllerProvider).state.restaurantById(widget.restaurantId);
    final offer = restaurant?.offers.where((o) => o.id == widget.offerId).firstOrNull;
    if (offer != null) _chips = _buildChips(offer);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _customArrival =>
      _arrival != null && !_chips.any((c) => c.isAtSameMomentAs(_arrival!));

  Future<void> _confirm(CustomerController controller, RestaurantOffer offer, bool takeaway) async {
    final arrival = _arrival;
    final w = _window(offer, DateTime.now());
    if (arrival == null || w == null || !_inWindow(arrival, w)) {
      setState(() => _arrivalError =
          w == null ? 'La oferta ya no admite llegadas.' : 'Tu hora ya no es válida. Elige otra ${_rangeText(w)}.');
      return;
    }
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await controller.reserveOffer(
      offer,
      takeaway: takeaway,
      estimatedArrival: _hhmm(arrival),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Pedido confirmado · Llegas a las ${_hhmm(arrival)}'),
      ));
      return;
    }
    final error = controller.lastActionError;
    messenger.showSnackBar(SnackBar(
      content: Text(error != null && error.isNotEmpty ? error : 'No pudimos enviar tu pedido.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final controller = ref.watch(customerControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final restaurant = controller.state.restaurantById(widget.restaurantId);
        final offer = restaurant?.offers.where((o) => o.id == widget.offerId).firstOrNull;
        final live = restaurant != null && offer != null && offer.isActiveFlashAt(_now);
        final isFull = restaurant != null &&
            ref.watch(restaurantPublicStatusProvider(restaurant.id)).isFull;
        final takeaway = isFull || _takeaway;
        final window = live ? _window(offer, _now) : null;
        final arrivalOk = _arrival != null && window != null && _inWindow(_arrival!, window);
        final hasActiveOrder = controller.state.activeOrder != null &&
            !controller.state.activeOrder!.isDelivered;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Confirmar oferta flash',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: colors.onSurface),
            ),
            const SizedBox(height: 12),
            if (!live)
              _Notice(
                icon: Icons.timer_off_outlined,
                text: 'Esta oferta ya terminó o se agotó.',
                color: b.danger,
              )
            else ...[
              FlashOfferCard(
                restaurant: restaurant,
                offer: offer,
                now: _now,
                showAvatar: true,
                ctaLabel: '',
                onTap: () {},
                showCta: false,
              ),
              const SizedBox(height: 16),
              Text(
                'Modalidad',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _ModeButton(
                    label: 'Para comer aquí',
                    icon: Icons.restaurant_rounded,
                    selected: !takeaway,
                    onTap: isFull ? null : () => setState(() => _takeaway = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    label: 'Para llevar (+${formatMoney(restaurant.takeawaySurcharge)})',
                    icon: Icons.takeout_dining_outlined,
                    selected: takeaway,
                    onTap: () => setState(() => _takeaway = true),
                  ),
                ),
              ]),
              if (isFull) ...[
                const SizedBox(height: 8),
                _Notice(
                  icon: Icons.info_outline_rounded,
                  text: 'Salón lleno por ahora: este pedido es solo para llevar.',
                  color: colors.onSurfaceVariant,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '¿A qué hora llegas?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                offer.endsAt == null
                    ? 'Elige tu hora de llegada.'
                    : 'Oferta válida hasta ${_hhmm(offer.endsAt!)}. Llega antes de esa hora.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (window == null)
                _Notice(
                  icon: Icons.timer_off_outlined,
                  text: 'Quedan menos de 10 minutos de oferta: ya no admite llegadas.',
                  color: b.danger,
                )
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in _chips.where((c) => _inWindow(c, window)))
                    _ArrivalChip(
                      label: _hhmm(c),
                      selected: _arrival != null && _arrival!.isAtSameMomentAs(c),
                      onTap: () => setState(() {
                        _arrival = c;
                        _arrivalError = null;
                      }),
                    ),
                  _ArrivalChip(
                    label: _customArrival ? _hhmm(_arrival!) : 'Elegir hora',
                    icon: Icons.schedule_rounded,
                    selected: _customArrival,
                    onTap: () => _pickArrival(offer),
                  ),
                ]),
              if (_arrival != null && window != null && !arrivalOk) ...[
                const SizedBox(height: 8),
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  text: 'Tu hora ya no es válida. Elige otra ${_rangeText(window)}.',
                  color: b.danger,
                ),
              ],
              if (_arrivalError != null) ...[
                const SizedBox(height: 8),
                _Notice(icon: Icons.error_outline_rounded, text: _arrivalError!, color: b.danger),
              ],
              if (!offer.reservable) ...[
                const SizedBox(height: 8),
                _Notice(
                  icon: Icons.storefront_outlined,
                  text: 'Esta oferta se pide y se paga directamente en caja.',
                  color: colors.onSurfaceVariant,
                ),
              ],
              if (hasActiveOrder) ...[
                const SizedBox(height: 8),
                Text(
                  'Límite: tienes una orden activa pendiente.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: b.danger),
                ),
              ],
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: live && !_sending && !hasActiveOrder && offer.reservable && arrivalOk
                  ? () => _confirm(controller, offer, takeaway)
                  : (live ? null : () => Navigator.of(context).pop()),
              child: _sending
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                    )
                  : Text(
                      !live
                          ? 'Cerrar'
                          : offer.reservable
                              ? 'Confirmar${arrivalOk ? ' · llegas ${_hhmm(_arrival!)}' : ''} · ${formatMoney((offer.price ?? 0) + (takeaway ? restaurant.takeawaySurcharge : 0))}'
                              : 'Pídela en caja',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Opacity(
      opacity: onTap == null && !selected ? 0.5 : 1,
      child: Material(
        color: selected ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          side: BorderSide(color: selected ? colors.primary : colors.primary.withValues(alpha: 0.25)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: selected ? fg : colors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.15, fontWeight: FontWeight.w800, color: fg),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    ]);
  }
}


class _ArrivalChip extends StatelessWidget {
  const _ArrivalChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          side: BorderSide(color: selected ? colors.primary : colors.primary.withValues(alpha: 0.25)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 84),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: selected ? fg : colors.primary),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
