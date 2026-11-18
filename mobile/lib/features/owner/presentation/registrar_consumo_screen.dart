import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../domain/models/cash_models.dart';
import '../domain/models/daily_menu.dart';
import 'owner_controller.dart';
import 'owner_widgets.dart';
import 'scan_result_screen.dart';

const _soloSecondDiscountCents = 50;
const _soloSoupCents = 125;
const _planBreakfastCents = 250;

String _fmt(int cents) =>
    '\$${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';

int? _parseCents(String text) {
  final clean = text.trim().replaceAll(',', '.');
  if (clean.isEmpty) return null;
  final n = double.tryParse(clean);
  return n == null || n < 0 ? null : (n * 100).round();
}

enum _PosTab { almuerzoCompleto, soloSegundo, soloSopa, extras }

const _tabs = [
  (_PosTab.almuerzoCompleto, 'Almuerzo completo'),
  (_PosTab.soloSegundo, 'Solo Segundo'),
  (_PosTab.soloSopa, 'Solo Sopa'),
  (_PosTab.extras, 'Extras'),
];

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

/// O6 · Registrar consumo (POS rápido de 2 toques).
class RegistrarConsumoScreen extends ConsumerStatefulWidget {
  const RegistrarConsumoScreen({super.key});

  @override
  ConsumerState<RegistrarConsumoScreen> createState() =>
      _RegistrarConsumoScreenState();
}

class _RegistrarConsumoScreenState
    extends ConsumerState<RegistrarConsumoScreen> {
  bool _planMode = false;
  bool _paraLlevar = false;
  _PosTab _tab = _PosTab.almuerzoCompleto;
  final List<_Line> _cart = [];
  String? _comboSoupId;
  String? _comboMainId;
  String _quickNote = '';
  bool _charging = false;

  void _updateCart(void Function() change) {
    setState(() {
      change();
      _cart.removeWhere((l) => l.qty <= 0);
    });
  }

  void _addLine(_Line line) {
    _updateCart(() {
      final existing = _cart.where((l) => l.key == line.key).firstOrNull;
      if (existing != null) {
        existing.qty += 1;
      } else {
        _cart.add(line);
      }
    });
  }

  void _changeQty(String key, int delta) {
    _updateCart(() {
      for (final l in _cart) {
        if (l.key == key) l.qty += delta;
      }
    });
  }

  int _qtyOf(String key) =>
      _cart.where((l) => l.key == key).firstOrNull?.qty ?? 0;

  void _pickCombo({
    String? soupId,
    String? mainId,
    required DailyMenu menu,
    required int lunchCents,
  }) {
    setState(() {
      if (soupId != null) _comboSoupId = soupId;
      if (mainId != null) _comboMainId = mainId;
    });
    final s = _comboSoupId;
    final m = _comboMainId;
    if (s == null || m == null) return;
    setState(() {
      _comboSoupId = null;
      _comboMainId = null;
    });
    final soupName = menu.courses.firstWhere((c) => c.id == s).name;
    final mainName = menu.courses.firstWhere((c) => c.id == m).name;
    _addLine(
      _Line(
        key: 'alm|$s|$m',
        name: 'Almuerzo',
        detail: '$soupName + $mainName',
        unitCents: lunchCents,
        isLunch: true,
      ),
    );
  }

  int _planDiscountCents(int subtotalCents, int lunchCents) {
    if (!_planMode) return 0;
    final int value;
    if (_cart.any((l) => l.isLunch)) {
      value = lunchCents;
    } else if (_cart.any((l) => l.isBreakfast)) {
      value = _planBreakfastCents;
    } else {
      value = 0;
    }
    return value.clamp(0, subtotalCents);
  }

  Future<void> _editQuickNote() async {
    final ctrl = TextEditingController(text: _quickNote);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota rápida'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ej: Sin ají, Juan, para retirar…',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: const Text('Limpiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (res != null && mounted) {
      setState(() => _quickNote = res);
    }
  }

  Future<void> _openCartSheet(int discountCents, int totalCents) async {
    if (_cart.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final colors = ctx.colorScheme;
          final liveSubtotal =
              _cart.fold<int>(0, (s, l) => s + l.unitCents * l.qty);
          final liveTotal = (liveSubtotal - discountCents).clamp(0, liveSubtotal);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Detalle del consumo',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      if (_cart.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            _updateCart(() => _cart.clear());
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Vaciar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _cart.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final l = _cart[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                    if (l.detail != null && l.detail!.isNotEmpty)
                                      Text(
                                        l.detail!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _fmt(l.unitCents * l.qty),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _SquareButton(
                                icon: Icons.remove_rounded,
                                tooltip: 'Quitar uno',
                                onTap: () {
                                  _changeQty(l.key, -1);
                                  if (_cart.isEmpty) {
                                    Navigator.of(ctx).pop();
                                  } else {
                                    setSheetState(() {});
                                  }
                                },
                              ),
                              SizedBox(
                                width: 26,
                                child: Text(
                                  '${l.qty}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              _SquareButton(
                                icon: Icons.add_rounded,
                                tooltip: 'Agregar otro',
                                filled: true,
                                onTap: () {
                                  _changeQty(l.key, 1);
                                  setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (discountCents > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Descuento Plan Bocadoo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          '-${_fmt(discountCents)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total a cobrar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        _fmt(liveTotal),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openChargeModal(int totalCents, int discountCents) async {
    if (_cart.isEmpty || totalCents <= 0 || _charging) return;

    final result = await showModalBottomSheet<
        ({OwnerPayMethod method, bool paraLlevar, int changeCents})>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ChargeBottomSheet(
        totalCents: totalCents,
        discountCents: discountCents,
        itemCount: _cart.fold<int>(0, (s, l) => s + l.qty),
        initialTakeaway: _paraLlevar,
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _paraLlevar = result.paraLlevar);
    await _submitSale(
      totalCents: totalCents,
      method: result.method,
      paraLlevar: result.paraLlevar,
      changeCents: result.changeCents,
    );
  }

  Future<void> _submitSale({
    required int totalCents,
    required OwnerPayMethod method,
    required bool paraLlevar,
    required int changeCents,
  }) async {
    final snapshot = _cart.map((l) => l.copy()).toList();
    if (snapshot.isEmpty || totalCents <= 0) return;

    final itemCount = snapshot.fold<int>(0, (s, l) => s + l.qty);
    final baseLabel = paraLlevar
        ? (_quickNote.isNotEmpty ? 'Para llevar ($_quickNote)' : 'Para llevar')
        : (_quickNote.isNotEmpty ? _quickNote : 'En local');
    final saleLabel = '$baseLabel · $itemCount productos';

    setState(() => _charging = true);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final saleId = await repo.registerPosSale(
      restaurantId: ref.read(ownerRestaurantIdProvider),
      label: saleLabel,
      lines: [
        for (final l in snapshot)
          PosSaleLine(
            name: l.name,
            detail: l.detail,
            unitPrice: Money.fromCents(l.unitCents),
            qty: l.qty,
            isLunch: l.isLunch,
          ),
      ],
      total: Money.fromCents(totalCents),
      method: method,
    );

    if (!mounted) return;
    setState(() => _charging = false);
    if (saleId == null) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      showInfoSnackBar(messenger, apiErr ?? 'No se pudo registrar el cobro');
      return;
    }

    container.invalidate(dailySummaryProvider);
    setState(() {
      _cart.clear();
      _quickNote = '';
      _paraLlevar = false;
      _comboSoupId = null;
      _comboMainId = null;
    });

    showUndoSnackBar(
      messenger,
      label: changeCents > 0
          ? 'Cobrado ${_fmt(totalCents)} · Vuelto ${_fmt(changeCents)}'
          : 'Cobrado ${_fmt(totalCents)} · ${method.label}',
      onUndo: () async {
        await repo.undoTransaction(saleId);
        container.invalidate(dailySummaryProvider);
        if (!mounted) return;
        setState(() {
          _cart
            ..clear()
            ..addAll(snapshot);
          _paraLlevar = paraLlevar;
        });
      },
    );
  }

  void _back() => context.canPop() ? context.pop() : context.go('/owner/caja');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final lunchCents =
        Money.toCents(ref.watch(lunchPriceProvider).value ?? 3.0);
    final subtotalCents =
        _cart.fold<int>(0, (s, l) => s + l.unitCents * l.qty);
    final discountCents = _planDiscountCents(subtotalCents, lunchCents);
    final totalCents = (subtotalCents - discountCents).clamp(0, subtotalCents);
    final totalItems = _cart.fold<int>(0, (s, l) => s + l.qty);
    final canCharge = _cart.isNotEmpty && totalCents > 0 && !_charging;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(bottom: BorderSide(color: colors.outlineVariant)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OwnerBackHeader(
                    title: 'Registrar consumo',
                    onBack: _back,
                    eyebrow: Row(
                      children: [
                        Text(
                          'Caja abierta',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 5),
                        CircleAvatar(
                          radius: 3.5,
                          backgroundColor: context.bocadooColors.success,
                        ),
                      ],
                    ),
                    trailing: IconButton.filledTonal(
                      tooltip: 'Cuadre de caja',
                      onPressed: () => context.push('/owner/cash-closing'),
                      icon: const Icon(Icons.receipt_long_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ModeSwitch(
                    planMode: _planMode,
                    onChanged: (v) => setState(() => _planMode = v),
                  ),
                  if (_planMode) ...[
                    const SizedBox(height: 8),
                    _PlanNotice(
                      lunchCents: lunchCents,
                      onScan: () => openScannerFlow(context, ref),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          avatar: Icon(
                            Icons.shopping_bag_outlined,
                            size: 16,
                            color: _paraLlevar
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
                          ),
                          label: const Text('+ Para llevar'),
                          selected: _paraLlevar,
                          onSelected: (v) => setState(() => _paraLlevar = v),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: Icon(
                            Icons.edit_note_rounded,
                            size: 16,
                            color: _quickNote.isNotEmpty
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          label: Text(
                            _quickNote.isNotEmpty ? _quickNote : '+ Nota rápida',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: _editQuickNote,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (tab, label) in _tabs) ...[
                          if (tab != _PosTab.almuerzoCompleto)
                            const SizedBox(width: 6),
                          _Pill(
                            label: label,
                            selected: _tab == tab,
                            onTap: () => setState(() => _tab = tab),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildTabContent(lunchCents)),
          ],
        ),
      ),
      bottomNavigationBar: _CompactBottomBar(
        totalItems: totalItems,
        totalCents: totalCents,
        charging: _charging,
        canCharge: canCharge,
        onShowDetails: _cart.isEmpty
            ? null
            : () => _openCartSheet(discountCents, totalCents),
        onCharge: canCharge
            ? () => _openChargeModal(totalCents, discountCents)
            : null,
      ),
    );
  }

  Widget _buildTabContent(int lunchCents) {
    final catalog = ref.watch(catalogProvider).value ?? const <CatalogItem>[];
    final menuAsync = ref.watch(posMenuProvider);

    switch (_tab) {
      case _PosTab.almuerzoCompleto:
        return menuAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _buildCompleteLunchOnly(null, lunchCents),
          data: (menu) => _buildCompleteLunchOnly(menu, lunchCents),
        );
      case _PosTab.soloSegundo:
        return menuAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _EmptyMenu(onPublish: () => context.go('/owner/menu')),
          data: (menu) => _buildSoloSegundo(menu, lunchCents),
        );
      case _PosTab.soloSopa:
        return menuAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _EmptyMenu(onPublish: () => context.go('/owner/menu')),
          data: (menu) => _buildSoloSopa(menu),
        );
      case _PosTab.extras:
        return _buildExtras(catalog);
    }
  }

  Widget _buildCompleteLunchOnly(DailyMenu? menu, int lunchCents) {
    final colors = context.colorScheme;
    final courses =
        menu != null && menu.isPublished ? menu.courses : const <DailyMenuCourse>[];
    final soups = courses.where((c) => c.category == 'Sopa').toList();
    final mains = courses.where((c) => c.category == 'Fuerte').toList();
    final includes = [
      courses
          .where((c) => c.category == 'Jugo' && !c.isSoldOut)
          .map((c) => c.name)
          .join(' / '),
      courses
          .where((c) => c.category == 'Postre' && !c.isSoldOut)
          .map((c) => c.name)
          .join(' / '),
    ].where((s) => s.isNotEmpty).join(' · ');
    final comboQty = _qtyOf('alm|combo');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Material(
          color: colors.primary,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _addLine(
              _Line(
                key: 'alm|combo',
                name: 'Almuerzo',
                detail: 'Almuerzo completo',
                unitCents: lunchCents,
                isLunch: true,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.onPrimary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.restaurant_rounded,
                      size: 24,
                      color: colors.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Almuerzo completo · ${_fmt(lunchCents)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: colors.onPrimary,
                          ),
                        ),
                        Text(
                          '1 toque para agregar al ticket sin elegir por separado',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onPrimary.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (comboQty > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onPrimary,
                        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      ),
                      child: Text(
                        '$comboQty×',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ] else
                    Icon(Icons.add_circle_outline_rounded, color: colors.onPrimary),
                ],
              ),
            ),
          ),
        ),
        if (includes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Incluye: ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(text: includes),
                ],
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
        ],
        if (soups.isNotEmpty && mains.isNotEmpty && menu != null) ...[
          const SizedBox(height: 16),
          const OwnerSectionLabel('O arma indicando sopa y segundo'),
          const SizedBox(height: 4),
          _Hint(
            _comboSoupId == null && _comboMainId == null
                ? 'Toca una sopa y un segundo para detallar el combo.'
                : _comboSoupId != null
                    ? 'Ahora elige el segundo.'
                    : 'Ahora elige la sopa.',
          ),
          const SizedBox(height: 10),
          const OwnerSectionLabel('Sopa'),
          const SizedBox(height: 6),
          _TwoColumns(
            children: [
              for (final s in soups)
                _TouchDishCard(
                  name: s.name,
                  priceText: s.isSoldOut ? 'Agotado' : 'Disponible',
                  soldOut: s.isSoldOut,
                  selected: _comboSoupId == s.id,
                  onTap: () => _pickCombo(
                    soupId: s.id,
                    menu: menu,
                    lunchCents: lunchCents,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const OwnerSectionLabel('Segundo'),
          const SizedBox(height: 6),
          _TwoColumns(
            children: [
              for (final m in mains)
                _TouchDishCard(
                  name: m.name,
                  priceText: m.isSoldOut ? 'Agotado' : _fmt(lunchCents),
                  soldOut: m.isSoldOut,
                  selected: _comboMainId == m.id,
                  onTap: () => _pickCombo(
                    mainId: m.id,
                    menu: menu,
                    lunchCents: lunchCents,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSoloSegundo(DailyMenu? menu, int lunchCents) {
    final courses =
        menu != null && menu.isPublished ? menu.courses : const <DailyMenuCourse>[];
    final mains = courses.where((c) => c.category == 'Fuerte').toList();
    if (mains.isEmpty) {
      return _EmptyMenu(onPublish: () => context.go('/owner/menu'));
    }
    final priceCents =
        (lunchCents - _soloSecondDiscountCents).clamp(50, lunchCents);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const OwnerSectionLabel('Solo Segundo'),
        const SizedBox(height: 4),
        const _Hint('Toca un segundo para agregarlo directo al ticket.'),
        const SizedBox(height: 10),
        _TwoColumns(
          children: [
            for (final m in mains)
              _TouchDishCard(
                name: m.name,
                priceText: m.isSoldOut ? 'Agotado' : _fmt(priceCents),
                soldOut: m.isSoldOut,
                qty: _qtyOf('seg|${m.id}'),
                onTap: () => _addLine(
                  _Line(
                    key: 'seg|${m.id}',
                    name: 'Solo segundo',
                    detail: m.name,
                    unitCents: priceCents,
                    isLunch: true,
                  ),
                ),
                onRemove: () => _changeQty('seg|${m.id}', -1),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSoloSopa(DailyMenu? menu) {
    final courses =
        menu != null && menu.isPublished ? menu.courses : const <DailyMenuCourse>[];
    final soups = courses.where((c) => c.category == 'Sopa').toList();
    if (soups.isEmpty) {
      return _EmptyMenu(onPublish: () => context.go('/owner/menu'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const OwnerSectionLabel('Solo Sopa'),
        const SizedBox(height: 4),
        const _Hint('Toca una sopa para agregarla directo al ticket.'),
        const SizedBox(height: 10),
        _TwoColumns(
          children: [
            for (final s in soups)
              _TouchDishCard(
                name: s.name,
                priceText: s.isSoldOut ? 'Agotado' : _fmt(_soloSoupCents),
                soldOut: s.isSoldOut,
                qty: _qtyOf('sop|${s.id}'),
                onTap: () => _addLine(
                  _Line(
                    key: 'sop|${s.id}',
                    name: 'Solo sopa',
                    detail: s.name,
                    unitCents: _soloSoupCents,
                    isLunch: true,
                  ),
                ),
                onRemove: () => _changeQty('sop|${s.id}', -1),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildExtras(List<CatalogItem> catalog) {
    final extrasAndDrinks = catalog
        .where((c) =>
            c.category == PosCategory.extras || c.category == PosCategory.bebidas)
        .toList();
    final cartaAndBreakfast = catalog
        .where((c) =>
            c.category == PosCategory.carta || c.category == PosCategory.desayunos)
        .toList();

    if (catalog.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aún no hay extras o adicionales en tu catálogo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (extrasAndDrinks.isNotEmpty) ...[
          const OwnerSectionLabel('Extras y bebidas'),
          const SizedBox(height: 8),
          _TwoColumns(
            children: [
              for (final item in extrasAndDrinks)
                _TouchDishCard(
                  name: item.name,
                  priceText: _fmt(Money.toCents(item.price)),
                  qty: _qtyOf(item.id),
                  onTap: () => _addLine(
                    _Line(
                      key: item.id,
                      name: item.name,
                      unitCents: Money.toCents(item.price),
                    ),
                  ),
                  onRemove: () => _changeQty(item.id, -1),
                ),
            ],
          ),
        ],
        if (cartaAndBreakfast.isNotEmpty) ...[
          if (extrasAndDrinks.isNotEmpty) const SizedBox(height: 16),
          const OwnerSectionLabel('A la carta y desayunos'),
          const SizedBox(height: 8),
          _TwoColumns(
            children: [
              for (final item in cartaAndBreakfast)
                _TouchDishCard(
                  name: item.name,
                  priceText: _fmt(Money.toCents(item.price)),
                  qty: _qtyOf(item.id),
                  onTap: () => _addLine(
                    _Line(
                      key: item.id,
                      name: item.name,
                      unitCents: Money.toCents(item.price),
                      isBreakfast: item.category == PosCategory.desayunos,
                    ),
                  ),
                  onRemove: () => _changeQty(item.id, -1),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CompactBottomBar extends StatelessWidget {
  const _CompactBottomBar({
    required this.totalItems,
    required this.totalCents,
    required this.charging,
    required this.canCharge,
    required this.onShowDetails,
    required this.onCharge,
  });

  final int totalItems;
  final int totalCents;
  final bool charging;
  final bool canCharge;
  final VoidCallback? onShowDetails;
  final VoidCallback? onCharge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final itemsLabel = totalItems == 1 ? '1 ítem' : '$totalItems ítems';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onShowDetails,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$itemsLabel · Total: ${_fmt(totalCents)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (onShowDetails != null)
                          Icon(
                            Icons.expand_less_rounded,
                            size: 18,
                            color: colors.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: canCharge ? onCharge : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(116, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                ),
                child: charging
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Text(
                        'Cobrar →',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChargeBottomSheet extends StatefulWidget {
  const _ChargeBottomSheet({
    required this.totalCents,
    required this.discountCents,
    required this.itemCount,
    required this.initialTakeaway,
  });

  final int totalCents;
  final int discountCents;
  final int itemCount;
  final bool initialTakeaway;

  @override
  State<_ChargeBottomSheet> createState() => _ChargeBottomSheetState();
}

class _ChargeBottomSheetState extends State<_ChargeBottomSheet> {
  OwnerPayMethod _method = OwnerPayMethod.efectivo;
  late bool _paraLlevar = widget.initialTakeaway;
  final TextEditingController _cash = TextEditingController();

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final isCash = _method == OwnerPayMethod.efectivo;
    final receivedCents = isCash ? _parseCents(_cash.text) : null;
    final invalid = isCash && _cash.text.trim().isNotEmpty && receivedCents == null;
    final shortfall = isCash && receivedCents != null && receivedCents < widget.totalCents;
    final changeCents = receivedCents == null ? 0 : receivedCents - widget.totalCents;
    final canConfirm = !isCash || (!invalid && !shortfall);
    final bills = [5, 10, 20].where((v) => v * 100 >= widget.totalCents).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Confirmar cobro',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.itemCount == 1
                                ? '1 ítem en consumo'
                                : '${widget.itemCount} ítems en consumo',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          _fmt(widget.totalCents),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (widget.discountCents > 0) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Incluye descuento Plan (-${_fmt(widget.discountCents)})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: b.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const OwnerSectionLabel('Método de pago'),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (m, icon) in const [
                    (OwnerPayMethod.efectivo, Icons.payments_outlined),
                    (OwnerPayMethod.transferencia, Icons.account_balance_outlined),
                    (OwnerPayMethod.deuna, Icons.bolt_rounded),
                  ]) ...[
                    if (m != OwnerPayMethod.efectivo) const SizedBox(width: 8),
                    Expanded(
                      child: Material(
                        color: _method == m
                            ? colors.primary
                            : Theme.of(context).scaffoldBackgroundColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: _method == m
                                ? colors.primary
                                : colors.outlineVariant,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() {
                            _method = m;
                            if (m != OwnerPayMethod.efectivo) _cash.clear();
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 20,
                                  color: _method == m
                                      ? colors.onPrimary
                                      : colors.onSurface,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m.shortLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: _method == m
                                        ? colors.onPrimary
                                        : colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _paraLlevar,
                onChanged: (v) => setState(() => _paraLlevar = v),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(
                  'Para llevar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Opcional · Marca si el cliente retira el pedido',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (isCash) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cash,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: '\$ ',
                          hintText: 'Efectivo recibido (opcional)',
                          errorText: invalid
                              ? 'Monto inválido'
                              : (shortfall
                                  ? 'Faltan ${_fmt(widget.totalCents - receivedCents)}'
                                  : null),
                        ),
                      ),
                    ),
                    if (changeCents > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: b.successContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Vuelto ${_fmt(changeCents)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: b.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (bills.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final v in bills)
                        ActionChip(
                          label: Text('\$$v'),
                          onPressed: () => setState(() => _cash.text = '$v'),
                        ),
                      ActionChip(
                        label: const Text('Exacto'),
                        onPressed: () => setState(() => _cash.clear()),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: canConfirm
                    ? () => Navigator.of(context).pop((
                          method: _method,
                          paraLlevar: _paraLlevar,
                          changeCents: changeCents > 0 ? changeCents : 0,
                        ))
                    : null,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text('Confirmar cobro · ${_fmt(widget.totalCents)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TouchDishCard extends StatelessWidget {
  const _TouchDishCard({
    required this.name,
    required this.priceText,
    required this.onTap,
    this.onRemove,
    this.qty = 0,
    this.selected = false,
    this.soldOut = false,
  });

  final String name;
  final String priceText;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final int qty;
  final bool selected;
  final bool soldOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final highlighted = selected || qty > 0;
    final fg = selected ? colors.onPrimary : colors.onSurface;

    return Opacity(
      opacity: soldOut ? 0.55 : 1,
      child: Material(
        color: selected ? colors.primary : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: highlighted ? colors.primary : colors.outlineVariant,
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: soldOut ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: fg,
                    decoration: soldOut ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: soldOut
                              ? b.danger
                              : (selected ? colors.onPrimary : colors.primary),
                        ),
                      ),
                    ),
                    if (qty > 0 && onRemove != null) ...[
                      _SquareButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Quitar uno',
                        onTap: onRemove!,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '$qty',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.colorScheme.onSurfaceVariant,
        ),
      );
}

class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
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

    Widget tab({
      required bool selected,
      required Color bg,
      required Color fg,
      required Widget child,
      required VoidCallback onTap,
    }) {
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
                  data: IconThemeData(
                    size: 16,
                    color: selected ? fg : colors.onSurfaceVariant,
                  ),
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
      child: Row(
        children: [
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
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_2_rounded),
                SizedBox(width: 6),
                Text('Plan + Extras'),
              ],
            ),
          ),
        ],
      ),
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
      child: Row(
        children: [
          Icon(Icons.check_rounded, size: 16, color: b.success),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Descuenta 1 almuerzo (-${_fmt(lunchCents)}) o desayuno (-${_fmt(_planBreakfastCents)})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: b.success,
              ),
            ),
          ),
          TextButton(
            onPressed: onScan,
            style: TextButton.styleFrom(foregroundColor: b.success),
            child: const Text(
              'Escanear QR',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: selected
          ? colors.primary
          : Theme.of(context).scaffoldBackgroundColor,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });

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
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 16, color: colors.primary),
          ),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DashedBorderBox(
          color: colors.outlineVariant,
          radius: 24,
          fill: colors.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.restaurant_menu_rounded,
                    size: 32, color: colors.primary),
                const SizedBox(height: 8),
                Text(
                  'Aún no hay menú publicado hoy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Publícalo en 2 toques y aparece aquí al instante.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: onPublish,
                  child: const Text('Publicar menú de hoy'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
