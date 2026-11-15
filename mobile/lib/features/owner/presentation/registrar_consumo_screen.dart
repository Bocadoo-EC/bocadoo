import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/daily_menu.dart';
import 'owner_controller.dart';
import 'owner_widgets.dart';
import 'scan_result_screen.dart';

const _none = '__none__';
const _takeaway = 'Para llevar';
const _mesas = ['Mesa 1', 'Mesa 2', 'Mesa 3', 'Mesa 4', 'Mesa 5', 'Barra', _takeaway];
const _soloSecondDiscountCents = 50;
const _soloSoupCents = 125;
const _planBreakfastCents = 250;

String _fmt(int cents) => '\$${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';

int? _parseCents(String text) {
  final clean = text.trim().replaceAll(',', '.');
  if (clean.isEmpty) return null;
  final n = double.tryParse(clean);
  return n == null || n < 0 ? null : (n * 100).round();
}

class _Line {
  _Line({
    required this.key,
    required this.name,
    required this.unitCents,
    this.detail,
    this.qty = 1,
    this.isLunch = false,
    this.isBreakfast = false,
  });

  final String key;
  final String name;
  final String? detail;
  final int unitCents;
  int qty;
  final bool isLunch;
  final bool isBreakfast;

  _Line copy() => _Line(
        key: key,
        name: name,
        unitCents: unitCents,
        detail: detail,
        qty: qty,
        isLunch: isLunch,
        isBreakfast: isBreakfast,
      );
}

const _categories = [
  (PosCategory.almuerzos, 'Almuerzos'),
  (PosCategory.desayunos, 'Desayunos'),
  (PosCategory.carta, 'A la carta'),
  (PosCategory.extras, 'Extras'),
  (PosCategory.bebidas, 'Bebidas'),
];

/// O6 · Registrar consumo (POS). Es el destino de "Cobro suelto" en Caja (O4).
class RegistrarConsumoScreen extends ConsumerStatefulWidget {
  const RegistrarConsumoScreen({super.key});

  @override
  ConsumerState<RegistrarConsumoScreen> createState() => _RegistrarConsumoScreenState();
}

class _RegistrarConsumoScreenState extends ConsumerState<RegistrarConsumoScreen> {
  bool _planMode = false;
  String _mesa = _mesas.first;
  PosCategory _category = PosCategory.almuerzos;
  final Map<String, List<_Line>> _tickets = {};
  String? _soup;
  String? _main;
  bool _ticketOpen = false;
  OwnerPayMethod _payment = OwnerPayMethod.efectivo;
  final _cash = TextEditingController();
  int _ticketNumber = 149;
  bool _charging = false;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  List<_Line> get _cart => _tickets[_mesa] ?? const [];

  void _updateCart(void Function(List<_Line> lines) change) {
    setState(() {
      final lines = [...?_tickets[_mesa]];
      change(lines);
      lines.removeWhere((l) => l.qty <= 0);
      if (lines.isEmpty) {
        _tickets.remove(_mesa);
      } else {
        _tickets[_mesa] = lines;
      }
    });
  }

  void _addLine(_Line line) {
    _updateCart((lines) {
      final existing = lines.where((l) => l.key == line.key).firstOrNull;
      if (existing != null) {
        existing.qty += 1;
      } else {
        lines.add(line);
      }
    });
  }

  void _changeQty(String key, int delta) {
    _updateCart((lines) {
      for (final l in lines) {
        if (l.key == key) l.qty += delta;
      }
    });
  }

  int _qtyOf(String key) => _cart.where((l) => l.key == key).firstOrNull?.qty ?? 0;

  void _pick({String? soup, String? main, required DailyMenu menu, required int lunchCents}) {
    setState(() {
      if (soup != null) _soup = soup;
      if (main != null) _main = main;
    });
    final s = _soup, m = _main;
    if (s == null || m == null) return;
    setState(() {
      _soup = null;
      _main = null;
    });
    if (s == _none && m == _none) return;

    String nameOf(String id) => menu.courses.firstWhere((c) => c.id == id).name;
    final int price;
    final String name;
    final String detail;
    if (s != _none && m != _none) {
      price = lunchCents;
      name = 'Almuerzo';
      detail = '${nameOf(s)} + ${nameOf(m)}';
    } else if (m != _none) {
      price = lunchCents - _soloSecondDiscountCents;
      name = 'Solo segundo';
      detail = nameOf(m);
    } else {
      price = _soloSoupCents;
      name = 'Solo sopa';
      detail = nameOf(s);
    }
    _addLine(_Line(key: 'alm|$s|$m', name: name, detail: detail, unitCents: price, isLunch: true));
  }

  int _planDiscount(int subtotal, int lunchCents) {
    if (!_planMode) return 0;
    final int value;
    if (_cart.any((l) => l.isLunch)) {
      value = lunchCents;
    } else if (_cart.any((l) => l.isBreakfast)) {
      value = _planBreakfastCents;
    } else {
      value = 0;
    }
    return value.clamp(0, subtotal);
  }

  Future<void> _charge(int total) async {
    final lines = _cart.map((l) => l.copy()).toList();
    if (lines.isEmpty) return;
    final received = _payment == OwnerPayMethod.efectivo ? _parseCents(_cash.text) : null;
    final change = received == null ? 0 : received - total;
    final mesa = _mesa;

    setState(() => _charging = true);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final saleId = await repo.registerPosSale(
      restaurantId: ref.read(ownerRestaurantIdProvider),
      label: '$mesa · ${lines.fold<int>(0, (s, l) => s + l.qty)} ítems',
      lines: [
        for (final l in lines)
          PosSaleLine(name: l.name, detail: l.detail, unitPrice: l.unitCents / 100, qty: l.qty, isLunch: l.isLunch),
      ],
      total: total / 100,
      method: _payment,
    );
    if (!mounted) return;
    setState(() => _charging = false);
    if (saleId == null) {
      showInfoSnackBar(messenger, 'No se pudo registrar el cobro');
      return;
    }
    container.invalidate(dailySummaryProvider);
    setState(() {
      _tickets.remove(mesa);
      _cash.clear();
      _ticketOpen = false;
      _ticketNumber++;
    });
    showUndoSnackBar(
      messenger,
      label: change > 0
          ? 'Cobrado ${_fmt(total)} · Vuelto ${_fmt(change)}'
          : 'Cobrado ${_fmt(total)} · ${_payment.label}',
      onUndo: () async {
        await repo.undoTransaction(saleId);
        container.invalidate(dailySummaryProvider);
        if (!mounted) return;
        setState(() {
          _tickets[mesa] = lines;
          _mesa = mesa;
        });
      },
    );
  }

  void _back() => context.canPop() ? context.pop() : context.go('/owner/caja');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final lunchCents = ((ref.watch(lunchPriceProvider).value ?? 3.0) * 100).round();
    final subtotal = _cart.fold<int>(0, (s, l) => s + l.unitCents * l.qty);
    final discount = _planDiscount(subtotal, lunchCents);
    final total = subtotal - discount;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OwnerBackHeader(
                title: 'Registrar consumo',
                onBack: _back,
                eyebrow: Row(children: [
                  Text('Caja abierta',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurfaceVariant)),
                  const SizedBox(width: 5),
                  CircleAvatar(radius: 3.5, backgroundColor: context.bocadooColors.success),
                ]),
                trailing: IconButton.filledTonal(
                  tooltip: 'Cuadre de caja',
                  onPressed: () => context.push('/owner/cash-closing'),
                  icon: const Icon(Icons.receipt_long_rounded),
                ),
              ),
              const SizedBox(height: 10),
              _ModeSwitch(planMode: _planMode, onChanged: (v) => setState(() => _planMode = v)),
              if (_planMode) ...[
                const SizedBox(height: 8),
                _PlanNotice(lunchCents: lunchCents, onScan: () => openScannerFlow(context, ref)),
              ],
              const SizedBox(height: 8),
              _MesaBar(
                selected: _mesa,
                openTotals: {
                  for (final e in _tickets.entries) e.key: e.value.fold<int>(0, (s, l) => s + l.unitCents * l.qty),
                },
                onSelect: (m) => setState(() {
                  _mesa = m;
                  _soup = null;
                  _main = null;
                }),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (cat, label) in _categories) ...[
                    if (cat != PosCategory.almuerzos) const SizedBox(width: 6),
                    _Pill(
                      label: label,
                      selected: _category == cat,
                      onTap: () => setState(() => _category = cat),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
          Expanded(child: _content(lunchCents)),
          _TicketPanel(
            ticketNumber: _ticketNumber,
            mesa: _mesa,
            lines: _cart,
            discount: discount,
            total: total,
            open: _ticketOpen,
            onToggle: () => setState(() => _ticketOpen = !_ticketOpen),
            onQty: _changeQty,
            onClear: () => _updateCart((lines) => lines.clear()),
            payment: _payment,
            onPayment: (m) => setState(() {
              _payment = m;
              if (m != OwnerPayMethod.efectivo) _cash.clear();
            }),
            cash: _cash,
            onCashChanged: () => setState(() {}),
            charging: _charging,
            onCharge: () => _charge(total),
          ),
        ]),
      ),
    );
  }

  Widget _content(int lunchCents) {
    final catalog = ref.watch(catalogProvider).value ?? const <CatalogItem>[];
    switch (_category) {
      case PosCategory.almuerzos:
        return ref.watch(posMenuProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _EmptyMenu(onPublish: () => context.go('/owner/menu')),
              data: (menu) => _lunches(menu, lunchCents),
            );
      case PosCategory.desayunos:
        final items = catalog.where((c) => c.category == PosCategory.desayunos).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          const OwnerSectionLabel('Desayunos de hoy'),
          const SizedBox(height: 2),
          _Hint('Toca un desayuno para agregarlo al ticket.'),
          const SizedBox(height: 10),
          _TwoColumns(children: [
            for (final b in items)
              _DishChip(
                name: b.name,
                subtitle: _fmt((b.price * 100).round()),
                selected: _qtyOf('des|${b.id}') > 0,
                onTap: () => _addLine(_Line(
                  key: 'des|${b.id}',
                  name: b.name,
                  unitCents: (b.price * 100).round(),
                  isBreakfast: true,
                )),
              ),
          ]),
        ]);
      case PosCategory.carta:
      case PosCategory.extras:
      case PosCategory.bebidas:
        final items = catalog.where((c) => c.category == _category).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          _TwoColumns(children: [
            for (final item in items)
              _CatalogTile(
                item: item,
                withImage: _category == PosCategory.carta,
                qty: _qtyOf(item.id),
                onAdd: () => _addLine(_Line(key: item.id, name: item.name, unitCents: (item.price * 100).round())),
                onRemove: () => _changeQty(item.id, -1),
              ),
          ]),
        ]);
    }
  }

  Widget _lunches(DailyMenu? menu, int lunchCents) {
    final courses = menu != null && menu.isPublished ? menu.courses : const <DailyMenuCourse>[];
    final soups = courses.where((c) => c.category == 'Sopa').toList();
    final mains = courses.where((c) => c.category == 'Fuerte').toList();
    if (menu == null || (soups.isEmpty && mains.isEmpty)) {
      return _EmptyMenu(onPublish: () => context.go('/owner/menu'));
    }
    final includes = [
      courses.where((c) => c.category == 'Jugo' && !c.isSoldOut).map((c) => c.name).join(' / '),
      courses.where((c) => c.category == 'Postre' && !c.isSoldOut).map((c) => c.name).join(' / '),
    ].where((s) => s.isNotEmpty).join(' · ');
    final hint = _soup == null && _main == null
        ? 'Toca la sopa y el segundo: se agrega solo.'
        : _soup != null && _main == null
            ? 'Ahora elige el segundo.'
            : 'Ahora elige la sopa.';
    final colors = context.colorScheme;

    Widget dish(DailyMenuCourse c, {required bool isSoup}) => _DishChip(
          name: c.name,
          subtitle: c.isSoldOut ? 'Agotado' : (isSoup ? 'Disponible' : _fmt(lunchCents)),
          soldOut: c.isSoldOut,
          selected: isSoup ? _soup == c.id : _main == c.id,
          onTap: () => isSoup
              ? _pick(soup: c.id, menu: menu, lunchCents: lunchCents)
              : _pick(main: c.id, menu: menu, lunchCents: lunchCents),
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      OwnerSectionLabel('Menú de hoy', color: colors.primary),
      const SizedBox(height: 2),
      _Hint(hint),
      if (soups.isNotEmpty) ...[
        const SizedBox(height: 12),
        const OwnerSectionLabel('Sopa'),
        const SizedBox(height: 6),
        _TwoColumns(children: [
          for (final s in soups) dish(s, isSoup: true),
          _NoneChip(
            label: 'Sin sopa',
            selected: _soup == _none,
            onTap: () => _pick(soup: _none, menu: menu, lunchCents: lunchCents),
          ),
        ]),
      ],
      if (mains.isNotEmpty) ...[
        const SizedBox(height: 12),
        const OwnerSectionLabel('Segundo'),
        const SizedBox(height: 6),
        _TwoColumns(children: [
          for (final m in mains) dish(m, isSoup: false),
          _NoneChip(
            label: 'Sin segundo',
            selected: _main == _none,
            onTap: () => _pick(main: _none, menu: menu, lunchCents: lunchCents),
          ),
        ]),
      ],
      if (includes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Incluye: ', style: TextStyle(fontWeight: FontWeight.w900)),
              TextSpan(text: includes),
            ]),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onPrimaryContainer),
          ),
        ),
      ],
    ]);
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colorScheme.onSurfaceVariant),
      );
}

class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final child in children) SizedBox(width: w, child: child),
      ]);
    });
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.planMode, required this.onChanged});

  final bool planMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;

    Widget tab({required bool selected, required Color bg, required Color fg, required Widget child, required VoidCallback onTap}) {
      return Expanded(
        child: Material(
          color: selected ? bg : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: selected ? fg : colors.onSurfaceVariant,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(size: 16, color: selected ? fg : colors.onSurfaceVariant),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        tab(
          selected: !planMode,
          bg: b.footerBg,
          fg: b.imageForeground,
          onTap: () => onChanged(false),
          child: const Text('Venta directa', textAlign: TextAlign.center),
        ),
        tab(
          selected: planMode,
          bg: colors.primary,
          fg: colors.onPrimary,
          onTap: () => onChanged(true),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.qr_code_2_rounded),
            SizedBox(width: 6),
            Text('Plan + Extras'),
          ]),
        ),
      ]),
    );
  }
}

class _PlanNotice extends StatelessWidget {
  const _PlanNotice({required this.lunchCents, required this.onScan});

  final int lunchCents;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
      decoration: BoxDecoration(
        color: b.successContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: b.success.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.check_rounded, size: 16, color: b.success),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Descuenta del plan: 1 almuerzo (-${_fmt(lunchCents)}) o 1 desayuno (-${_fmt(_planBreakfastCents)})',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: b.success),
            ),
          ),
          TextButton(
            onPressed: onScan,
            style: TextButton.styleFrom(foregroundColor: b.success),
            child: const Text('Escanear QR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          ),
        ]),
        Text(
          'Úsalo solo si un comensal con plan pidió extras, bebidas o platos a la carta. '
          'Si solo viene por su almuerzo, escanea su QR directo en Caja.',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: b.onSuccessContainer),
        ),
      ]),
    );
  }
}

class _MesaBar extends StatelessWidget {
  const _MesaBar({required this.selected, required this.openTotals, required this.onSelect});

  final String selected;
  final Map<String, int> openTotals;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final m in _mesas) ...[
          if (m != _mesas.first) const SizedBox(width: 6),
          Material(
            color: m == selected
                ? colors.primary
                : openTotals.containsKey(m)
                    ? colors.primaryContainer
                    : Theme.of(context).scaffoldBackgroundColor,
            shape: StadiumBorder(
              side: BorderSide(
                color: m == selected
                    ? colors.primary
                    : openTotals.containsKey(m)
                        ? colors.primary
                        : colors.outlineVariant,
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onSelect(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (m == _takeaway) ...[
                    Icon(Icons.shopping_bag_outlined,
                        size: 14, color: m == selected ? colors.onPrimary : colors.onSurfaceVariant),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    openTotals.containsKey(m) && m != selected ? '$m · ${_fmt(openTotals[m]!)}' : m,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: m == selected ? colors.onPrimary : colors.onSurface,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: selected ? colors.primary : Theme.of(context).scaffoldBackgroundColor,
      shape: StadiumBorder(side: BorderSide(color: selected ? colors.primary : colors.outlineVariant)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              )),
        ),
      ),
    );
  }
}

class _DishChip extends StatelessWidget {
  const _DishChip({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.soldOut = false,
  });

  final String name;
  final String subtitle;
  final bool selected;
  final bool soldOut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Opacity(
      opacity: soldOut ? 0.6 : 1,
      child: Material(
        color: selected ? colors.primary : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? colors.primary : colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: soldOut ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: fg,
                    decoration: soldOut ? TextDecoration.lineThrough : null,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: soldOut
                        ? b.danger
                        : selected
                            ? colors.onPrimary.withValues(alpha: 0.85)
                            : colors.primary,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NoneChip extends StatelessWidget {
  const _NoneChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return DashedBorderBox(
      color: selected ? colors.primary : colors.outlineVariant,
      radius: 18,
      fill: selected ? colors.primary : Theme.of(context).scaffoldBackgroundColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text(label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              )),
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.item,
    required this.withImage,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final CatalogItem item;
  final bool withImage;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (withImage)
          Container(
            height: 64,
            color: colors.primaryContainer,
            child: Icon(Icons.restaurant_menu_rounded, size: 28, color: colors.primary),
          ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
            Text(item.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(_fmt((item.price * 100).round()),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.primary)),
              ),
              if (qty > 0) ...[
                _SquareButton(icon: Icons.remove_rounded, tooltip: 'Quitar uno', onTap: onRemove),
                SizedBox(
                  width: 22,
                  child: Text('$qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onSurface)),
                ),
              ],
              _SquareButton(icon: Icons.add_rounded, tooltip: 'Agregar', onTap: onAdd, filled: true),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.tooltip, required this.onTap, this.filled = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.primaryContainer),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 18, color: colors.primary)),
        ),
      ),
    );
  }
}

class _EmptyMenu extends StatelessWidget {
  const _EmptyMenu({required this.onPublish});

  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      DashedBorderBox(
        color: colors.outlineVariant,
        radius: 24,
        fill: colors.surface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.restaurant_menu_rounded, size: 32, color: colors.primary),
            const SizedBox(height: 8),
            Text('Aún no hay menú publicado hoy',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
            const SizedBox(height: 4),
            Text('Publícalo en 2 toques y aparece aquí al instante.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onPublish, child: const Text('Publicar menú de hoy')),
          ]),
        ),
      ),
    ]);
  }
}

class _TicketPanel extends StatelessWidget {
  const _TicketPanel({
    required this.ticketNumber,
    required this.mesa,
    required this.lines,
    required this.discount,
    required this.total,
    required this.open,
    required this.onToggle,
    required this.onQty,
    required this.onClear,
    required this.payment,
    required this.onPayment,
    required this.cash,
    required this.onCashChanged,
    required this.charging,
    required this.onCharge,
  });

  final int ticketNumber;
  final String mesa;
  final List<_Line> lines;
  final int discount;
  final int total;
  final bool open;
  final VoidCallback onToggle;
  final void Function(String key, int delta) onQty;
  final VoidCallback onClear;
  final OwnerPayMethod payment;
  final ValueChanged<OwnerPayMethod> onPayment;
  final TextEditingController cash;
  final VoidCallback onCashChanged;
  final bool charging;
  final VoidCallback onCharge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final fg = b.imageForeground;
    final items = lines.fold<int>(0, (s, l) => s + l.qty);
    final isCash = payment == OwnerPayMethod.efectivo;
    final received = _parseCents(cash.text);
    final invalid = cash.text.trim().isNotEmpty && received == null;
    final shortfall = received != null && received < total;
    final change = received == null ? 0 : received - total;
    final canCharge = lines.isNotEmpty && !charging && (!isCash || (!invalid && !shortfall));
    final bills = [5, 10, 20, 50].where((v) => v * 100 >= total).take(3).toList();

    TextStyle small(double alpha, {FontWeight w = FontWeight.w700}) =>
        TextStyle(fontSize: 13, fontWeight: w, color: fg.withValues(alpha: alpha));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: b.footerBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Row(children: [
            Text('Ticket #$ticketNumber', style: small(0.85, w: FontWeight.w900)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: Text(mesa, style: small(0.85)),
            ),
            const SizedBox(width: 6),
            Flexible(child: Text('$items ${items == 1 ? 'ítem' : 'ítems'}', style: small(0.6))),
            const Spacer(),
            Text(_fmt(total), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: fg)),
            Icon(open ? Icons.expand_more_rounded : Icons.expand_less_rounded, color: fg.withValues(alpha: 0.6)),
          ]),
        ),
        if (open) ...[
          Divider(color: fg.withValues(alpha: 0.12), height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: lines.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Ticket vacío. Toca un plato para agregarlo.',
                        textAlign: TextAlign.center, style: small(0.55, w: FontWeight.w500)),
                  )
                : ListView(shrinkWrap: true, children: [
                    for (final l in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${l.qty}× ${l.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
                              if (l.detail != null)
                                Text(l.detail!,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: small(0.55, w: FontWeight.w500)),
                            ]),
                          ),
                          Text(_fmt(l.unitCents * l.qty),
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
                          const SizedBox(width: 6),
                          _TicketQty(icon: Icons.remove_rounded, tooltip: 'Quitar uno', onTap: () => onQty(l.key, -1)),
                          const SizedBox(width: 4),
                          _TicketQty(
                              icon: Icons.add_rounded, tooltip: 'Agregar otro', onTap: () => onQty(l.key, 1), filled: true),
                        ]),
                      ),
                    if (discount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Expanded(child: Text('Descuento plan Bocadoo', style: small(0.85))),
                          Text('-${_fmt(discount)}', style: small(0.85)),
                        ]),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: onClear,
                        style: TextButton.styleFrom(foregroundColor: fg.withValues(alpha: 0.6)),
                        child: const Text('Vaciar ticket',
                            style: TextStyle(fontSize: 13, decoration: TextDecoration.underline)),
                      ),
                    ),
                  ]),
          ),
        ],
        const SizedBox(height: 8),
        Row(children: [
          for (final (m, icon) in const [
            (OwnerPayMethod.efectivo, Icons.payments_outlined),
            (OwnerPayMethod.transferencia, Icons.account_balance_outlined),
            (OwnerPayMethod.deuna, Icons.bolt_rounded),
            (OwnerPayMethod.tarjeta, Icons.credit_card_rounded),
          ]) ...[
            if (m != OwnerPayMethod.efectivo) const SizedBox(width: 6),
            Expanded(
              child: Material(
                color: payment == m ? colors.primary : fg.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onPayment(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, size: 14, color: payment == m ? colors.onPrimary : fg.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(m.shortLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: payment == m ? colors.onPrimary : fg.withValues(alpha: 0.8),
                            )),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
        if (isCash && lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: fg.withValues(alpha: 0.1)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: cash,
                    onChanged: (_) => onCashChanged(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: fg),
                    cursorColor: fg,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: fg.withValues(alpha: 0.1),
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: fg.withValues(alpha: 0.6)),
                      hintText: 'Recibido (ej. 15)',
                      hintStyle: small(0.45, w: FontWeight.w600),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: invalid || shortfall ? BorderSide(color: b.danger, width: 2) : BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: invalid || shortfall ? b.danger : colors.primary.withValues(alpha: 0.6), width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (invalid)
                  _StatusPill(text: 'Monto inválido', color: b.danger)
                else if (shortfall)
                  _StatusPill(text: 'Faltan ${_fmt(total - received)}', color: b.danger)
                else if (change > 0)
                  _StatusPill(text: 'Vuelto ${_fmt(change)}', color: b.success)
                else
                  Text('Exacto', style: small(0.55)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                for (final v in bills) ...[
                  _BillChip(label: '\$$v', onTap: () {
                    cash.text = '$v';
                    onCashChanged();
                  }),
                  const SizedBox(width: 6),
                ],
                _BillChip(label: 'Exacto', onTap: () {
                  cash.clear();
                  onCashChanged();
                }),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: canCharge ? onCharge : null,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: fg.withValues(alpha: 0.15),
            disabledForegroundColor: fg.withValues(alpha: 0.4),
          ),
          icon: charging
              ? SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary))
              : const Icon(Icons.payments_outlined),
          label: Text('Cobrar ${_fmt(total)}'),
        ),
      ]),
    );
  }
}

class _TicketQty extends StatelessWidget {
  const _TicketQty({required this.icon, required this.tooltip, required this.onTap, this.filled = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = context.bocadooColors.imageForeground;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? colors.primary : fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 16, color: filled ? colors.onPrimary : fg.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: context.bocadooColors.imageForeground)),
    );
  }
}

class _BillChip extends StatelessWidget {
  const _BillChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = context.bocadooColors.imageForeground;
    return Material(
      color: fg.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: fg)),
        ),
      ),
    );
  }
}
