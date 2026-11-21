import 'dart:async';

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

String _fmt(int cents) =>
    '\$${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';

int? _parseCents(String text) {
  final clean = text.trim().replaceAll(',', '.');
  if (clean.isEmpty) return null;
  final n = double.tryParse(clean);
  return n == null || n < 0 ? null : (n * 100).round();
}

enum _FilterTab { sopa, platoFuerte, bebida }

const _filterTabs = [
  (_FilterTab.sopa, 'Sopa'),
  (_FilterTab.platoFuerte, 'Plato Fuerte'),
  (_FilterTab.bebida, 'Bebida'),
];

class _Line {
  _Line({
    required this.key,
    required this.name,
    required this.unitCents,
    this.detail,
    this.qty = 1,
    this.isLunch = false,
    this.admiteParaLlevar = false,
    this.paraLlevar = false,
  });

  final String key;
  final String name;
  final String? detail;
  final int unitCents;
  int qty;
  final bool isLunch;
  final bool admiteParaLlevar;
  bool paraLlevar;

  _Line copy() => _Line(
        key: key,
        name: name,
        unitCents: unitCents,
        detail: detail,
        qty: qty,
        isLunch: isLunch,
        admiteParaLlevar: admiteParaLlevar,
        paraLlevar: paraLlevar,
      );
}

class _PosGridItem {
  const _PosGridItem({
    required this.key,
    required this.name,
    required this.tag,
    required this.priceCents,
    this.soldOut = false,
    this.lineName,
    this.lineDetail,
    this.isLunch = false,
    this.admiteParaLlevar = false,
  });

  final String key;
  final String name;
  final String tag;
  final int priceCents;
  final bool soldOut;
  final String? lineName;
  final String? lineDetail;
  final bool isLunch;
  final bool admiteParaLlevar;
}

class _ScannedPlanClient {
  const _ScannedPlanClient({
    required this.name,
    required this.remainingLunches,
    this.passId,
  });

  final String name;
  final int remainingLunches;
  final String? passId;
}

/// O6 · Registrar consumo (POS rápido).
class RegistrarConsumoScreen extends ConsumerStatefulWidget {
  const RegistrarConsumoScreen({super.key});

  @override
  ConsumerState<RegistrarConsumoScreen> createState() =>
      _RegistrarConsumoScreenState();
}

class _RegistrarConsumoScreenState
    extends ConsumerState<RegistrarConsumoScreen> {
  bool _planMode = false;
  bool _planLunchParaLlevar = false;
  _FilterTab _filterTab = _FilterTab.sopa;

  final List<_Line> _directCart = [];
  final List<_Line> _planExtrasCart = [];
  _ScannedPlanClient? _scannedPlan;

  String _quickNote = '';
  bool _charging = false;

  List<_Line> get _activeCart => _planMode ? _planExtrasCart : _directCart;

  int get _takeawayCount {
    var count = _activeCart
        .where((l) => l.admiteParaLlevar && l.paraLlevar)
        .fold<int>(0, (s, l) => s + l.qty);
    if (_planMode && _scannedPlan != null && _planLunchParaLlevar) {
      count += 1;
    }
    return count;
  }

  void _updateCart(void Function() change) {
    setState(() {
      change();
      _activeCart.removeWhere((l) => l.qty <= 0);
    });
  }

  void _addLine(_Line line) {
    _updateCart(() {
      final existing = _activeCart.where((l) => l.key == line.key).firstOrNull;
      if (existing != null) {
        existing.qty += 1;
      } else {
        _activeCart.add(line);
      }
    });
  }

  void _changeQty(String key, int delta) {
    _updateCart(() {
      for (final l in _activeCart) {
        if (l.key == key) l.qty += delta;
      }
    });
  }

  void _toggleLineParaLlevar(String key) {
    _updateCart(() {
      for (final l in _activeCart) {
        if (l.key == key && l.admiteParaLlevar) {
          l.paraLlevar = !l.paraLlevar;
        }
      }
    });
  }

  int _qtyOf(String key) =>
      _activeCart.where((l) => l.key == key).firstOrNull?.qty ?? 0;

  bool _isLunchSoldOut(DailyMenu? menu) {
    if (menu == null || !menu.isPublished) return false;
    final soups = menu.courses.where((c) => c.category == 'Sopa').toList();
    final mains = menu.courses.where((c) => c.category == 'Fuerte').toList();
    final allSoupsOut = soups.isNotEmpty && soups.every((c) => c.isSoldOut);
    final allMainsOut = mains.isNotEmpty && mains.every((c) => c.isSoldOut);
    return allSoupsOut || allMainsOut;
  }

  Future<void> _scanPlanClient() async {
    final controller = ref.read(ownerControllerProvider.notifier);
    controller.reset();
    await context.push('/owner/scanner');
    if (!mounted) return;

    final scanState = ref.read(ownerControllerProvider);
    if (scanState is OwnerRedirect) {
      final loc = scanState.location;
      controller.reset();
      await context.push(loc);
      if (mounted) {
        ref.invalidate(dailySummaryProvider);
        ref.invalidate(activeOrdersProvider);
        ref.invalidate(pendingTablesProvider);
        ref.invalidate(ordersOnTheWayProvider);
        unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
      }
      return;
    }

    if (scanState is OwnerSuccess && scanState.result.isValid) {
      final r = scanState.result;
      setState(() {
        _scannedPlan = _ScannedPlanClient(
          name: (r.studentName ?? '').trim().isNotEmpty
              ? r.studentName!.trim()
              : 'Comensal con plan',
          remainingLunches: r.remainingLunches ?? 0,
          passId: r.passId,
        );
        _planLunchParaLlevar = false;
      });
      controller.reset();
      ref.invalidate(dailySummaryProvider);
      ref.invalidate(activeOrdersProvider);
      ref.invalidate(pendingTablesProvider);
      ref.invalidate(ordersOnTheWayProvider);
      unawaited(ref.read(cajaMovementsProvider.notifier).refresh());
      return;
    }

    if (scanState is OwnerError) {
      final msg = scanState.message;
      controller.reset();
      showInfoSnackBar(ScaffoldMessenger.of(context), msg);
      return;
    }

    controller.reset();
  }

  Future<void> _editQuickNote() async {
    final ctrl = TextEditingController(text: _quickNote);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Observación de cocina'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 48,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ej: Sin ají, Juan, sin cebolla…',
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

  Future<void> _openCartSheet(int takeawaySurchargeCents) async {
    final hasPlanLunch = _planMode && _scannedPlan != null;
    if (_activeCart.isEmpty && !hasPlanLunch) return;
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
          final b = ctx.bocadooColors;
          final cartSubtotal =
              _activeCart.fold<int>(0, (s, l) => s + l.unitCents * l.qty);
          final takeawayCount = _takeawayCount;
          final takeawayFee = takeawayCount * takeawaySurchargeCents;
          final liveTotal = cartSubtotal + takeawayFee;

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
                      if (_activeCart.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            _updateCart(() => _activeCart.clear());
                            if (!hasPlanLunch) {
                              Navigator.of(ctx).pop();
                            } else {
                              setSheetState(() {});
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Vaciar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (hasPlanLunch) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: b.successContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 18, color: b.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Almuerzo completo · Plan (${_scannedPlan!.name})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: b.onSuccessContainer,
                                  ),
                                ),
                                if (_planLunchParaLlevar)
                                  Text(
                                    'Para llevar (+${_fmt(takeawaySurchargeCents)})',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: colors.primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _fmt(_planLunchParaLlevar
                                ? takeawaySurchargeCents
                                : 0),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: b.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TakeoutToggleButton(
                            active: _planLunchParaLlevar,
                            onTap: () {
                              setState(() =>
                                  _planLunchParaLlevar = !_planLunchParaLlevar);
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_activeCart.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (_activeCart.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _activeCart.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final l = _activeCart[i];
                          final lineTotalCents = (l.unitCents +
                                  (l.admiteParaLlevar && l.paraLlevar
                                      ? takeawaySurchargeCents
                                      : 0)) *
                              l.qty;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  colors.primaryContainer.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                      if (l.detail != null &&
                                          l.detail!.isNotEmpty)
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
                                      if (l.admiteParaLlevar && l.paraLlevar)
                                        Text(
                                          'Para llevar (+${_fmt(takeawaySurchargeCents)})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: colors.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _fmt(lineTotalCents),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: colors.onSurface,
                                  ),
                                ),
                                if (l.admiteParaLlevar) ...[
                                  const SizedBox(width: 6),
                                  _TakeoutToggleButton(
                                    active: l.paraLlevar,
                                    onTap: () {
                                      _toggleLineParaLlevar(l.key);
                                      setSheetState(() {});
                                    },
                                  ),
                                ],
                                const SizedBox(width: 6),
                                _SquareButton(
                                  icon: Icons.remove_rounded,
                                  tooltip: 'Quitar uno',
                                  onTap: () {
                                    _changeQty(l.key, -1);
                                    if (_activeCart.isEmpty && !hasPlanLunch) {
                                      Navigator.of(ctx).pop();
                                    } else {
                                      setSheetState(() {});
                                    }
                                  },
                                ),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${l.qty}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13.5,
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
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: _quickNote.isNotEmpty
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        await _editQuickNote();
                        if (ctx.mounted) setSheetState(() {});
                      },
                      icon: Icon(
                        _quickNote.isNotEmpty
                            ? Icons.edit_note_rounded
                            : Icons.add_comment_outlined,
                        size: 16,
                      ),
                      label: Text(
                        _quickNote.isNotEmpty
                            ? 'Observación: $_quickNote'
                            : '+ Agregar observación',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 16, color: colors.outlineVariant),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          takeawayCount > 0
                              ? 'Envases para llevar ($takeawayCount)'
                              : 'Envases para llevar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        _fmt(takeawayFee),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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

  Future<void> _handlePrimaryAction(
    int totalCents,
    int totalItems,
    int takeawaySurchargeCents,
  ) async {
    if (_charging) return;

    if (_planMode) {
      final client = _scannedPlan;
      if (client == null) return;
      if (totalCents <= 0) {
        final messenger = ScaffoldMessenger.of(context);
        final who = client.name;
        setState(() {
          _scannedPlan = null;
          _planExtrasCart.clear();
          _planLunchParaLlevar = false;
          _quickNote = '';
        });
        ref.invalidate(dailySummaryProvider);
        showInfoSnackBar(messenger, 'Plan canjeado · $who');
        return;
      }
      await _openChargeModal(
        totalCents: totalCents,
        itemCount: totalItems,
        takeawayCount: _takeawayCount,
        takeawaySurchargeCents: takeawaySurchargeCents,
        planClient: client,
      );
      return;
    }

    if (_directCart.isEmpty || totalCents <= 0) return;
    await _openChargeModal(
      totalCents: totalCents,
      itemCount: totalItems,
      takeawayCount: _takeawayCount,
      takeawaySurchargeCents: takeawaySurchargeCents,
    );
  }

  Future<void> _openChargeModal({
    required int totalCents,
    required int itemCount,
    required int takeawayCount,
    required int takeawaySurchargeCents,
    _ScannedPlanClient? planClient,
  }) async {
    if (_charging) return;

    final result = await showModalBottomSheet<
        ({OwnerPayMethod method, int changeCents})>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ChargeBottomSheet(
        title: planClient != null ? 'Canjear y cobrar extras' : 'Confirmar cobro',
        totalCents: totalCents,
        takeawayCount: takeawayCount,
        takeawayFeeCents: takeawayCount * takeawaySurchargeCents,
        planClientName: planClient?.name,
        itemCount: itemCount,
      ),
    );

    if (result == null || !mounted) return;

    await _submitSale(
      totalCents: totalCents,
      method: result.method,
      takeawayCount: takeawayCount,
      takeawaySurchargeCents: takeawaySurchargeCents,
      changeCents: result.changeCents,
      planClient: planClient,
    );
  }

  Future<void> _submitSale({
    required int totalCents,
    required OwnerPayMethod method,
    required int takeawayCount,
    required int takeawaySurchargeCents,
    required int changeCents,
    _ScannedPlanClient? planClient,
  }) async {
    final snapshot = _activeCart.map((l) => l.copy()).toList();
    if (totalCents <= 0) return;
    if (snapshot.isEmpty && takeawayCount == 0) return;

    final itemCount =
        snapshot.fold<int>(0, (s, l) => s + l.qty) + (planClient != null ? 1 : 0);
    final hasTakeaway = takeawayCount > 0;
    final modality = hasTakeaway
        ? (_quickNote.isNotEmpty
            ? 'Para llevar ($takeawayCount · $_quickNote)'
            : 'Para llevar ($takeawayCount)')
        : (_quickNote.isNotEmpty ? _quickNote : 'En local');
    final baseLabel =
        planClient != null ? 'Plan ${planClient.name} · $modality' : modality;
    final saleLabel = '$baseLabel · $itemCount productos';

    final saleLines = <PosSaleLine>[
      for (final l in snapshot)
        PosSaleLine(
          name: l.paraLlevar ? '${l.name} (Para llevar)' : l.name,
          detail: l.detail,
          unitPrice: Money.fromCents(l.unitCents),
          qty: l.qty,
          isLunch: l.isLunch,
        ),
      if (hasTakeaway && takeawaySurchargeCents > 0)
        PosSaleLine(
          name: 'Envases para llevar',
          unitPrice: Money.fromCents(takeawaySurchargeCents),
          qty: takeawayCount,
        ),
    ];

    setState(() => _charging = true);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final saleId = await repo.registerPosSale(
      restaurantId: ref.read(ownerRestaurantIdProvider),
      label: saleLabel,
      lines: saleLines,
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
    final savedPlanMode = _planMode;
    final savedPlanLunchParaLlevar = _planLunchParaLlevar;
    setState(() {
      if (savedPlanMode) {
        _planExtrasCart.clear();
        _scannedPlan = null;
        _planLunchParaLlevar = false;
      } else {
        _directCart.clear();
      }
      _quickNote = '';
    });

    final prefix = planClient != null ? 'Canjeado y cobrado' : 'Cobrado';
    showUndoSnackBar(
      messenger,
      label: changeCents > 0
          ? '$prefix ${_fmt(totalCents)} · Vuelto ${_fmt(changeCents)}'
          : '$prefix ${_fmt(totalCents)} · ${method.label}',
      onUndo: () async {
        await repo.undoTransaction(saleId);
        container.invalidate(dailySummaryProvider);
        if (!mounted) return;
        setState(() {
          if (savedPlanMode) {
            _planExtrasCart
              ..clear()
              ..addAll(snapshot);
            _scannedPlan = planClient;
            _planLunchParaLlevar = savedPlanLunchParaLlevar;
          } else {
            _directCart
              ..clear()
              ..addAll(snapshot);
          }
        });
      },
    );
  }

  List<_PosGridItem> _itemsForTab({
    required _FilterTab tab,
    required DailyMenu? menu,
    required List<PermanentCatalogItem> permanentItems,
    required int soloSoupCents,
    required int soloSecondCents,
  }) {
    final courses =
        menu != null && menu.isPublished ? menu.courses : const <DailyMenuCourse>[];

    switch (tab) {
      case _FilterTab.sopa:
        final soups = courses.where((c) => c.category == 'Sopa').toList();
        return [
          for (final s in soups)
            _PosGridItem(
              key: 'sop|${s.id}',
              name: s.name,
              tag: 'Del día',
              priceCents: (s.price != null && s.price! > 0)
                  ? Money.toCents(s.price!)
                  : soloSoupCents,
              soldOut: s.isSoldOut,
              lineName: 'Solo sopa',
              lineDetail: s.name,
              isLunch: true,
              admiteParaLlevar: true,
            ),
        ];

      case _FilterTab.platoFuerte:
        final mains = courses.where((c) => c.category == 'Fuerte').toList();
        final cartaItems = permanentItems
            .where((p) => p.group == PermanentCatalogGroup.carta)
            .map(
              (item) => _PosGridItem(
                key: 'carta|${item.id}',
                name: item.name,
                tag: 'Carta',
                priceCents: item.priceCents,
                soldOut: !item.available,
                admiteParaLlevar: true,
              ),
            )
            .toList();

        return [
          for (final m in mains)
            _PosGridItem(
              key: 'seg|${m.id}',
              name: m.name,
              tag: 'Del día',
              priceCents: (m.price != null && m.price! > 0)
                  ? Money.toCents(m.price!)
                  : soloSecondCents,
              soldOut: m.isSoldOut,
              lineName: 'Solo segundo',
              lineDetail: m.name,
              isLunch: true,
              admiteParaLlevar: true,
            ),
          ...cartaItems,
        ];

      case _FilterTab.bebida:
        final lunchJuiceNames = courses
            .where((c) => c.category == 'Jugo')
            .map((c) => c.name.trim().toLowerCase())
            .toSet();
        return permanentItems
            .where((p) {
              if (p.group != PermanentCatalogGroup.bebidas) return false;
              final norm = p.name.trim().toLowerCase();
              return !lunchJuiceNames.contains(norm) &&
                  !norm.contains('vaso de jugo') &&
                  !norm.contains('jugo incluido') &&
                  !norm.contains('jugo del día');
            })
            .map(
              (d) => _PosGridItem(
                key: 'beb|${d.id}',
                name: d.name,
                tag: 'Bebida',
                priceCents: d.priceCents,
                soldOut: !d.available,
                admiteParaLlevar: false,
              ),
            )
            .toList();
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/owner/caja');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final prices = ref.watch(executivePricesProvider);
    final lunchCents = Money.toCents(prices.lunch);
    final soloSecondCents = Money.toCents(prices.soloSecond);
    final soloSoupCents = Money.toCents(prices.soloSoup);
    final takeawaySurchargeCents = Money.toCents(prices.takeawaySurcharge);
    final menuAsync = ref.watch(posMenuProvider);
    final menu = menuAsync.value;
    final permanentItems = ref.watch(permanentCatalogProvider).items;

    final hasPlanClient = _planMode && _scannedPlan != null;
    final cartSubtotalCents =
        _activeCart.fold<int>(0, (s, l) => s + l.unitCents * l.qty);
    final totalCents =
        cartSubtotalCents + (_takeawayCount * takeawaySurchargeCents);
    final totalItems =
        _activeCart.fold<int>(0, (s, l) => s + l.qty) + (hasPlanClient ? 1 : 0);

    final bool ctaEnabled;
    final String ctaLabel;
    if (_planMode) {
      if (_scannedPlan == null) {
        ctaEnabled = false;
        ctaLabel = 'Canjear plan →';
      } else {
        ctaEnabled = !_charging;
        ctaLabel = totalCents > 0
            ? 'Canjear y cobrar ${_fmt(totalCents)} →'
            : 'Canjear plan · ${_fmt(0)} →';
      }
    } else {
      ctaEnabled = _directCart.isNotEmpty && totalCents > 0 && !_charging;
      ctaLabel = 'Cobrar →';
    }

    final lunchSoldOut = _isLunchSoldOut(menu);
    final lunchQty = _qtyOf('alm|combo');
    final gridItems = _itemsForTab(
      tab: _filterTab,
      menu: menu,
      permanentItems: permanentItems,
      soloSoupCents: soloSoupCents,
      soloSecondCents: soloSecondCents,
    );

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
                border:
                    Border(bottom: BorderSide(color: colors.outlineVariant)),
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_planMode)
                    _DirectLunchQuickCard(
                      lunchCents: lunchCents,
                      qty: lunchQty,
                      soldOut: lunchSoldOut,
                      onAdd: () => _addLine(
                        _Line(
                          key: 'alm|combo',
                          name: 'Almuerzo',
                          detail: 'Almuerzo completo',
                          unitCents: lunchCents,
                          isLunch: true,
                          admiteParaLlevar: true,
                        ),
                      ),
                      onIncrement: () => _changeQty('alm|combo', 1),
                      onDecrement: () => _changeQty('alm|combo', -1),
                    )
                  else ...[
                    _PlanHeaderCard(
                      client: _scannedPlan,
                      onScan: _scanPlanClient,
                    ),
                    const SizedBox(height: 8),
                    _PlanLunchCard(
                      active: _scannedPlan != null,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _FilterTabBar(
                    selected: _filterTab,
                    onChanged: (t) => setState(() => _filterTab = t),
                  ),
                ],
              ),
            ),
            Expanded(
              child: menuAsync.isLoading && menu == null
                  ? const Center(child: CircularProgressIndicator())
                  : gridItems.isEmpty
                      ? _EmptyTabState(
                          tab: _filterTab,
                          onPublishMenu: () => context.go('/owner/menu'),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                          children: [
                            _TwoColumnGrid(
                              children: [
                                for (final item in gridItems)
                                  _PosItemCard(
                                    item: item,
                                    qty: _qtyOf(item.key),
                                    onAdd: () => _addLine(
                                      _Line(
                                        key: item.key,
                                        name: item.lineName ?? item.name,
                                        detail: item.lineDetail,
                                        unitCents: item.priceCents,
                                        isLunch: item.isLunch,
                                        admiteParaLlevar: item.admiteParaLlevar,
                                      ),
                                    ),
                                    onIncrement: () =>
                                        _changeQty(item.key, 1),
                                    onDecrement: () =>
                                        _changeQty(item.key, -1),
                                  ),
                              ],
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _CompactBottomBar(
        totalItems: totalItems,
        totalCents: totalCents,
        charging: _charging,
        ctaEnabled: ctaEnabled,
        ctaLabel: ctaLabel,
        onShowDetails: (_activeCart.isNotEmpty || hasPlanClient)
            ? () => _openCartSheet(takeawaySurchargeCents)
            : null,
        onPrimaryAction: ctaEnabled
            ? () => _handlePrimaryAction(
                  totalCents,
                  totalItems,
                  takeawaySurchargeCents,
                )
            : null,
      ),
    );
  }
}

class _DirectLunchQuickCard extends StatelessWidget {
  const _DirectLunchQuickCard({
    required this.lunchCents,
    required this.qty,
    required this.soldOut,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int lunchCents;
  final int qty;
  final bool soldOut;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final bg = soldOut ? colors.surfaceContainerHighest : colors.primary;
    final fg = soldOut ? colors.onSurfaceVariant : colors.onPrimary;

    return Opacity(
      opacity: soldOut ? 0.72 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: soldOut ? null : onAdd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.restaurant_rounded,
                    size: 20,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Almuerzo completo · ${_fmt(lunchCents)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (soldOut)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    ),
                    child: Text(
                      'Agotado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (qty == 0)
                  FilledButton(
                    onPressed: onAdd,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.onPrimary,
                      foregroundColor: colors.primary,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '+ Agregar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.onPrimary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniIconButton(
                          icon: Icons.remove_rounded,
                          color: colors.primary,
                          onTap: onDecrement,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '$qty',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        _MiniIconButton(
                          icon: Icons.add_rounded,
                          color: colors.primary,
                          onTap: onIncrement,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanHeaderCard extends StatelessWidget {
  const _PlanHeaderCard({
    required this.client,
    required this.onScan,
  });

  final _ScannedPlanClient? client;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final b = context.bocadooColors;

    if (client == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: b.successContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: b.success.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: b.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.qr_code_scanner_rounded,
                size: 20,
                color: b.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Escanea el QR del cliente',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: b.onSuccessContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cubre 1 Almuerzo completo; suma aquí solo bebidas, extras o para llevar',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: b.onSuccessContainer.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onScan,
              style: FilledButton.styleFrom(
                backgroundColor: b.success,
                foregroundColor: b.successForeground,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: const Text(
                'Escanear QR',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
    }

    final remaining = client!.remainingLunches;
    final remLabel =
        remaining == 1 ? '1 almuerzo restante' : '$remaining almuerzos restantes';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: b.successContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: b.success, width: 1.3),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 20, color: b.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '✓ ${client!.name} · Plan activo ($remLabel)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: b.onSuccessContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onScan,
            style: TextButton.styleFrom(
              foregroundColor: b.success,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Cambiar',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanLunchCard extends StatelessWidget {
  const _PlanLunchCard({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? b.successContainer.withValues(alpha: 0.72)
            : colors.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? b.success : colors.outlineVariant,
          width: active ? 1.3 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.restaurant_rounded,
            size: 20,
            color: active ? b.success : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Almuerzo completo · Plan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: active ? b.onSuccessContainer : colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  active
                      ? '1 Almuerzo cubierto por plan (${_fmt(0)}) aplicado'
                      : 'Se aplica automáticamente al escanear QR del plan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? b.onSuccessContainer.withValues(alpha: 0.85)
                        : colors.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: b.success,
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: Text(
                'Cargado ✓',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: b.successForeground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterTabBar extends StatelessWidget {
  const _FilterTabBar({
    required this.selected,
    required this.onChanged,
  });

  final _FilterTab selected;
  final ValueChanged<_FilterTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          for (final (tab, label) in _filterTabs)
            Expanded(
              child: InkWell(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(10)),
                onTap: () => onChanged(tab),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected == tab
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: selected == tab
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 3,
                      decoration: BoxDecoration(
                        color: selected == tab
                            ? colors.primary
                            : Colors.transparent,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PosItemCard extends StatelessWidget {
  const _PosItemCard({
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final _PosGridItem item;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final highlighted = qty > 0 && !item.soldOut;

    final (Color tagBg, Color tagFg) = switch (item.tag) {
      'Carta' => (colors.secondaryContainer, colors.onSecondaryContainer),
      'Bebida' => (b.walletAccent.withValues(alpha: 0.32), b.onWalletAccent),
      _ => (colors.primaryContainer, colors.onPrimaryContainer),
    };

    return Opacity(
      opacity: item.soldOut ? 0.58 : 1,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: highlighted ? colors.primary : colors.outlineVariant,
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: item.soldOut ? null : onAdd,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.soldOut
                            ? colors.surfaceContainerHighest
                            : tagBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: item.soldOut ? colors.onSurfaceVariant : tagFg,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: colors.onSurface,
                        decoration:
                            item.soldOut ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _fmt(item.priceCents),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: item.soldOut
                                ? colors.onSurfaceVariant
                                : colors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (item.soldOut)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Agotado',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      )
                    else if (qty == 0)
                      _SquareButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Agregar',
                        filled: true,
                        onTap: onAdd,
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SquareButton(
                            icon: Icons.remove_rounded,
                            tooltip: 'Quitar uno',
                            onTap: onDecrement,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text(
                              '$qty',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          _SquareButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Agregar otro',
                            filled: true,
                            onTap: onIncrement,
                          ),
                        ],
                      ),
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

class _TwoColumnGrid extends StatelessWidget {
  const _TwoColumnGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final left = children[i];
      final right = i + 1 < children.length ? children[i + 1] : null;
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 8),
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _TakeoutToggleButton extends StatelessWidget {
  const _TakeoutToggleButton({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Tooltip(
      message: active ? 'Quitar envase para llevar' : 'Marcar para llevar',
      child: Material(
        color: active ? colors.primary : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: active ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(
              Icons.takeout_dining_outlined,
              size: 16,
              color: active ? colors.onPrimary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBottomBar extends StatelessWidget {
  const _CompactBottomBar({
    required this.totalItems,
    required this.totalCents,
    required this.charging,
    required this.ctaEnabled,
    required this.ctaLabel,
    required this.onShowDetails,
    required this.onPrimaryAction,
  });

  final int totalItems;
  final int totalCents;
  final bool charging;
  final bool ctaEnabled;
  final String ctaLabel;
  final VoidCallback? onShowDetails;
  final VoidCallback? onPrimaryAction;

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
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onShowDetails,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '$itemsLabel · ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Text(
                              'Ver detalle',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 16,
                              color: colors.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Total: ${_fmt(totalCents)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: ctaEnabled ? onPrimaryAction : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(116, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.buttonRadius),
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
                    : Text(
                        ctaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
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
    required this.title,
    required this.totalCents,
    required this.takeawayCount,
    required this.takeawayFeeCents,
    required this.itemCount,
    this.planClientName,
  });

  final String title;
  final int totalCents;
  final int takeawayCount;
  final int takeawayFeeCents;
  final int itemCount;
  final String? planClientName;

  @override
  State<_ChargeBottomSheet> createState() => _ChargeBottomSheetState();
}

class _ChargeBottomSheetState extends State<_ChargeBottomSheet> {
  OwnerPayMethod _method = OwnerPayMethod.efectivo;
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
    final effectiveTotal = widget.totalCents;
    final isCash = _method == OwnerPayMethod.efectivo && effectiveTotal > 0;
    final receivedCents = isCash ? _parseCents(_cash.text) : null;
    final invalid =
        isCash && _cash.text.trim().isNotEmpty && receivedCents == null;
    final shortfall =
        isCash && receivedCents != null && receivedCents < effectiveTotal;
    final changeCents =
        receivedCents == null ? 0 : receivedCents - effectiveTotal;
    final canConfirm = !isCash || (!invalid && !shortfall);
    final bills =
        [5, 10, 20].where((v) => v * 100 >= effectiveTotal).toList();

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
                      widget.title,
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
                          _fmt(effectiveTotal),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (widget.takeawayCount > 0) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Incluye ${widget.takeawayCount} envase(s) para llevar (+${_fmt(widget.takeawayFeeCents)})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    if (widget.planClientName != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Plan activo · ${widget.planClientName} (Almuerzo \$0,00)',
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
              if (effectiveTotal > 0) ...[
                const SizedBox(height: 14),
                const OwnerSectionLabel('Método de pago'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (m, icon) in const [
                      (OwnerPayMethod.efectivo, Icons.payments_outlined),
                      (
                        OwnerPayMethod.transferencia,
                        Icons.account_balance_outlined
                      ),
                      (OwnerPayMethod.deuna, Icons.bolt_rounded),
                    ]) ...[
                      if (m != OwnerPayMethod.efectivo)
                        const SizedBox(width: 8),
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
              ],
              if (isCash) ...[
                const SizedBox(height: 12),
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
                                  ? 'Faltan ${_fmt(effectiveTotal - receivedCents)}'
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
                          changeCents: changeCents > 0 ? changeCents : 0,
                        ))
                    : null,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  effectiveTotal > 0
                      ? 'Confirmar cobro · ${_fmt(effectiveTotal)}'
                      : 'Confirmar canje · ${_fmt(0)}',
                ),
              ),
            ],
          ),
        ),
      ),
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

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: color),
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
            width: 28,
            height: 28,
            child: Icon(icon, size: 15, color: colors.primary),
          ),
        ),
      ),
    );
  }
}

class _EmptyTabState extends StatelessWidget {
  const _EmptyTabState({
    required this.tab,
    required this.onPublishMenu,
  });

  final _FilterTab tab;
  final VoidCallback onPublishMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final label = switch (tab) {
      _FilterTab.sopa => 'No hay sopas publicadas hoy',
      _FilterTab.platoFuerte => 'No hay platos fuertes disponibles',
      _FilterTab.bebida => 'No hay bebidas configuradas',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: DashedBorderBox(
          color: colors.outlineVariant,
          radius: 20,
          fill: colors.surface,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restaurant_menu_rounded,
                    size: 28, color: colors.primary),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: onPublishMenu,
                  child: const Text('Publicar menú de hoy'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
