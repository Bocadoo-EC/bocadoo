import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

const _commission = 0.07;
const _soloPlateDiscount = 0.50;
const _weekDays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// O11 · Oferta flash: liquidación de hoy o promo programada en horas muertas.
class FlashOfferSheet extends ConsumerStatefulWidget {
  const FlashOfferSheet({super.key});

  @override
  ConsumerState<FlashOfferSheet> createState() => _FlashOfferSheetState();
}

class _FlashOfferSheetState extends ConsumerState<FlashOfferSheet> {
  OfferKind _kind = OfferKind.flash;

  bool _menuDeHoy = true;
  int? _flashDiscount = 10;
  int _flashSlots = 10;
  String _until = '14:00';

  final _title = TextEditingController();
  final Set<int> _days = {2, 4};
  TimeOfDay _from = const TimeOfDay(hour: 16, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 18, minute: 0);
  int? _progDiscount = 20;
  int _progSlots = 20;

  final _manual = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _manual.dispose();
    super.dispose();
  }

  bool get _isFlash => _kind == OfferKind.flash;

  int get _discount {
    final preset = _isFlash ? _flashDiscount : _progDiscount;
    if (preset != null) return preset;
    return (int.tryParse(_manual.text) ?? 0).clamp(0, 90);
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickTime(bool from) async {
    final picked = await showTimePicker(context: context, initialTime: from ? _from : _to);
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _publish(double basePrice) async {
    final discount = _discount;
    if (discount <= 0) {
      setState(() => _error = 'Elige un descuento');
      return;
    }
    if (!_isFlash && _days.isEmpty) {
      setState(() => _error = 'Elige al menos un día');
      return;
    }
    if (!_isFlash && _minutes(_from) >= _minutes(_to)) {
      setState(() => _error = 'La hora de inicio debe ser antes del final');
      return;
    }
    final price = (basePrice * (100 - discount) / 100 * 100).roundToDouble() / 100;
    final slots = _isFlash ? _flashSlots : _progSlots;
    final offer = _isFlash
        ? FlashOffer(
            kind: OfferKind.flash,
            title: _menuDeHoy ? 'Menú de hoy' : 'Plato suelto',
            discountPercent: discount,
            slots: slots,
            price: price,
            validUntil: _until,
          )
        : FlashOffer(
            kind: OfferKind.programada,
            title: _title.text.trim().isEmpty ? 'Promo programada' : _title.text.trim(),
            discountPercent: discount,
            slots: slots,
            price: price,
            days: (_days.toList()..sort()),
            fromMinutes: _minutes(_from),
            toMinutes: _minutes(_to),
          );

    setState(() {
      _sending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final rid = ref.read(ownerRestaurantIdProvider);
    final ok = await repo.publishOffer(rid, offer);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _sending = false;
        _error = 'No se pudo publicar la oferta';
      });
      return;
    }
    container.invalidate(activeOfferProvider);
    navigator.pop(true);
    showUndoSnackBar(messenger, label: 'Oferta publicada ($slots cupos)', onUndo: () async {
      await repo.cancelOffer(rid);
      container.invalidate(activeOfferProvider);
    });
  }

  Future<void> _cancelActive() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(ownerCashRepositoryProvider).cancelOffer(ref.read(ownerRestaurantIdProvider));
    if (!mounted) return;
    container.invalidate(activeOfferProvider);
    navigator.pop(true);
    showInfoSnackBar(messenger, 'Oferta cancelada sin costo');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final lunchPrice = ref.watch(lunchPriceProvider).value ?? 3.0;
    final active = ref.watch(activeOfferProvider).value;
    final base = _isFlash && !_menuDeHoy ? lunchPrice - _soloPlateDiscount : lunchPrice;
    final discount = _discount;
    final newPrice = base * (100 - discount) / 100;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(_isFlash ? Icons.bolt_rounded : Icons.event_repeat_rounded, size: 20, color: colors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Oferta flash',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: colors.onSurface)),
            ),
            IconButton.filledTonal(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          if (active != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Expanded(
                  child: Text('Activa: ${active.title} · ${active.slots} cupos a ${OwnerFormat.money(active.price)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
                ),
                TextButton(onPressed: _cancelActive, child: const Text('Cancelar oferta')),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(children: [
              Expanded(
                child: _KindTab(
                  icon: Icons.bolt_rounded,
                  title: 'Flash de hoy',
                  subtitle: 'Liquidación de excedentes',
                  selected: _isFlash,
                  onTap: () => setState(() {
                    _kind = OfferKind.flash;
                    _error = null;
                  }),
                ),
              ),
              Expanded(
                child: _KindTab(
                  icon: Icons.calendar_month_rounded,
                  title: 'Horas muertas',
                  subtitle: 'Promo programada',
                  selected: !_isFlash,
                  onTap: () => setState(() {
                    _kind = OfferKind.programada;
                    _error = null;
                  }),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            _isFlash
                ? 'Vende hoy lo que te sobró: tu plato o combo con descuento, por pocos cupos y hasta una hora de hoy.'
                : 'Atrae clientes en los días y horas de poco movimiento. Se repite cada semana durante 30 días.',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.35, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (_isFlash) ..._flashFields() else ..._scheduledFields(),
          const SizedBox(height: 14),
          _Label(
            'Descuento',
            trailing: Text.rich(TextSpan(children: [
              TextSpan(
                text: OwnerFormat.money(base),
                style: TextStyle(color: colors.onSurfaceVariant, decoration: TextDecoration.lineThrough),
              ),
              TextSpan(
                text: '  ${OwnerFormat.money(newPrice)} · -$discount%',
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800),
              ),
            ]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          _OptionRow(
            options: [
              for (final d in _isFlash ? const [10, 20] : const [10, 20, 30]) ('-$d %', d),
              ('Manual', null),
            ],
            selected: _isFlash ? _flashDiscount : _progDiscount,
            onSelect: (v) => setState(() {
              if (_isFlash) {
                _flashDiscount = v;
              } else {
                _progDiscount = v;
              }
              _error = null;
            }),
          ),
          if ((_isFlash ? _flashDiscount : _progDiscount) == null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _manual,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Descuento en %', suffixText: '%'),
            ),
          ],
          const SizedBox(height: 8),
          _InfoBox('Recibes ${OwnerFormat.money(newPrice * (1 - _commission))} por venta', centered: true),
          const SizedBox(height: 14),
          const _Label('Cupos disponibles'),
          _OptionRow(
            options: [for (final s in _isFlash ? const [5, 10, 15] : const [10, 20, 30]) ('$s cupos', s)],
            selected: _isFlash ? _flashSlots : _progSlots,
            onSelect: (v) => setState(() {
              if (_isFlash) {
                _flashSlots = v!;
              } else {
                _progSlots = v!;
              }
            }),
          ),
          const SizedBox(height: 14),
          if (_isFlash) ...[
            const _Label('Válida hasta'),
            _OptionRow(
              options: const [('13:30', 0), ('14:00', 1), ('14:30', 2)],
              selected: const ['13:30', '14:00', '14:30'].indexOf(_until),
              onSelect: (v) => setState(() => _until = const ['13:30', '14:00', '14:30'][v!]),
            ),
          ] else
            const _InfoBox('La promo queda vigente 30 días. Puedes cancelarla cuando quieras.'),
          const SizedBox(height: 10),
          const _InfoBox('Publicar es gratis. Pagas el 7 % solo de lo que se venda.'),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.bocadooColors.danger)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _sending ? null : () => _publish(base),
            child: Text(_isFlash ? 'Publicar oferta' : 'Publicar promo programada'),
          ),
        ]),
      ),
    );
  }

  List<Widget> _flashFields() => [
        const _Label('Qué ofreces'),
        Row(children: [
          Expanded(
            child: OwnerChoice(
              label: 'Menú de hoy',
              selected: _menuDeHoy,
              onTap: () => setState(() => _menuDeHoy = true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OwnerChoice(
              label: 'Plato suelto',
              selected: !_menuDeHoy,
              onTap: () => setState(() => _menuDeHoy = false),
            ),
          ),
        ]),
      ];

  List<Widget> _scheduledFields() {
    final colors = context.colorScheme;
    return [
      const _Label('Título de la promo'),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Ej. Almuerzo ejecutivo a precio especial'),
      ),
      const SizedBox(height: 14),
      const _Label('Días de la semana'),
      Row(children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Material(
              color: _days.contains(i + 1) ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => setState(() {
                  _days.contains(i + 1) ? _days.remove(i + 1) : _days.add(i + 1);
                  _error = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    _weekDays[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _days.contains(i + 1) ? colors.onPrimary : colors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      const _Label('Rango horario'),
      Row(children: [
        Expanded(child: _TimeField(label: 'Desde', value: _hhmm(_from), onTap: () => _pickTime(true))),
        const SizedBox(width: 10),
        Expanded(child: _TimeField(label: 'Hasta', value: _hhmm(_to), onTap: () => _pickTime(false))),
      ]),
    ];
  }
}

class _KindTab extends StatelessWidget {
  const _KindTab({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Material(
      color: selected ? colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? fg : colors.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: fg)),
              ),
            ]),
            Text(subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.85))),
          ]),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.colorScheme.onSurface)),
        ),
        ?trailing,
      ]),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.options, required this.selected, required this.onSelect});

  final List<(String, int?)> options;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: OwnerChoice(
            label: options[i].$1,
            selected: options[i].$2 == selected,
            onTap: () => onSelect(options[i].$2),
          ),
        ),
      ],
    ]);
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox(this.text, {this.centered = false});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: 13,
          fontWeight: centered ? FontWeight.w800 : FontWeight.w600,
          color: centered ? colors.onSurface : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
      const SizedBox(height: 4),
      Material(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text(value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.onSurface)),
              ),
              Icon(Icons.schedule_rounded, size: 18, color: colors.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    ]);
  }
}
