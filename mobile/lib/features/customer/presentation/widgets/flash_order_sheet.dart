import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/contracts/models.dart';
import '../../../../core/theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _confirm(CustomerController controller, RestaurantOffer offer, bool takeaway) async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await controller.reserveOffer(offer, takeaway: takeaway);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      navigator.pop();
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
              onPressed: live && !_sending && !hasActiveOrder && offer.reservable
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
                              ? 'Confirmar pedido · ${formatMoney((offer.price ?? 0) + (takeaway ? restaurant.takeawaySurcharge : 0))}'
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
