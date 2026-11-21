import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/contracts/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/api_owner_repo.dart';
import '../domain/models/daily_menu.dart';
import '../domain/models/menu_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const _months = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];
const _lunchKinds = [
  DishKind.sopa,
  DishKind.segundo,
  DishKind.bebida,
  DishKind.postre,
];

String _plural(DishKind k) => switch (k) {
      DishKind.sopa => 'sopas',
      DishKind.segundo => 'segundos',
      DishKind.bebida => 'bebidas incluidas',
      DishKind.postre => 'postres incluidos',
      DishKind.desayuno => 'desayunos',
      DishKind.carta => 'platos a la carta',
    };

/// O7 · Menú de hoy (rotativo diario) y Carta y Bebidas (catálogo fijo permanente).
class OwnerMenuScreen extends ConsumerStatefulWidget {
  const OwnerMenuScreen({super.key});

  @override
  ConsumerState<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends ConsumerState<OwnerMenuScreen> {
  bool _catalogView = false;
  PermanentCatalogGroup _catalogFilter = PermanentCatalogGroup.carta;

  final Map<DishKind, List<String>> _today = {
    DishKind.sopa: ['Locro de papa con queso', 'Sopa de lenteja'],
    DishKind.segundo: ['Pollo a la plancha', 'Seco de pollo con maduro'],
    DishKind.bebida: ['Jugo de naranjilla'],
    DishKind.postre: ['Higos con queso'],
  };
  final Set<String> _soldOut = {};
  final Set<String> _expandedSections = {'sopa', 'segundo'};
  bool _published = false;
  bool _menuLoaded = false;
  bool _publishing = false;

  void _toggleAccordion(String key) {
    setState(() {
      if (!_expandedSections.remove(key)) _expandedSections.add(key);
    });
  }

  String get _rid => ref.read(ownerRestaurantIdProvider);

  @override
  void initState() {
    super.initState();
    _loadPublished();
  }

  /// Si ya hay un menú publicado hoy, la pantalla parte de él.
  Future<void> _loadPublished() async {
    final menu = await ref.read(ownerMenuRepositoryProvider).getTodayMenu(_rid);
    if (!mounted) return;
    setState(() {
      _menuLoaded = true;
      if (menu == null || !menu.isPublished) return;
      _published = true;
      for (final k in _lunchKinds) {
        final names = [
          for (final c in menu.courses)
            if (c.category == k.courseCategory) c.name,
        ];
        if (names.isNotEmpty) _today[k] = names;
      }
      _soldOut
        ..clear()
        ..addAll([
          for (final c in menu.courses)
            if (c.isSoldOut) c.name,
        ]);
    });
  }

  Future<void> _toggleSoldOut(String name) async {
    final soldOut = !_soldOut.contains(name);
    setState(() {
      if (soldOut) {
        _soldOut.add(name);
      } else {
        _soldOut.remove(name);
      }
    });
    if (!_published) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ownerMenuRepositoryProvider);
    final ok = await repo.setCourseSoldOut(_rid, name, soldOut: soldOut);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        if (soldOut) {
          _soldOut.remove(name);
        } else {
          _soldOut.add(name);
        }
      });
      final msg = repo is ApiOwnerRepository
          ? (repo.consumeLastError() ??
              'No se pudo actualizar el estado del plato.')
          : 'No se pudo actualizar el estado del plato.';
      showInfoSnackBar(messenger, msg);
      return;
    }
    ref.invalidate(posMenuProvider);
    ref.invalidate(activeOfferProvider);
    final dishes =
        ref.read(catalogDishesProvider).value ?? const <CatalogDish>[];
    if (_published &&
        dishes.isNotEmpty &&
        _buildMenu(dishes).availabilityState ==
            MenuAvailabilityState.agotadoTotal) {
      showInfoSnackBar(
        messenger,
        'Todo el menú quedó agotado hoy. Las ofertas flash activas se pausaron.',
      );
    }
  }

  DailyMenu _buildMenu(List<CatalogDish> dishes) {
    final courses = <DailyMenuCourse>[];
    for (final k in _lunchKinds) {
      final names = _today[k] ?? const <String>[];
      for (var i = 0; i < names.length; i++) {
        final matched = dishes
            .where(
              (d) =>
                  d.kind == k &&
                  d.name.trim().toLowerCase() == names[i].trim().toLowerCase(),
            )
            .firstOrNull;
        courses.add(
          DailyMenuCourse(
            id: matched?.id ?? '${k.name}-$i',
            name: names[i],
            category: k.courseCategory,
            price: matched?.price,
            isSoldOut: _soldOut.contains(names[i]),
          ),
        );
      }
    }
    return DailyMenu(
      restaurantId: _rid,
      date: DateTime.now(),
      courses: courses,
      isPublished: true,
    );
  }

  Future<void> _publish(List<CatalogDish> dishes) async {
    final messenger = ScaffoldMessenger.of(context);
    final menu = _buildMenu(dishes);
    if (menu.courses.isEmpty) {
      showInfoSnackBar(
        messenger,
        'Agrega al menos un plato antes de publicar el menú.',
      );
      return;
    }
    setState(() => _publishing = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerMenuRepositoryProvider);
    final rid = _rid;
    final ok = await repo.publishMenu(menu);
    if (!mounted) return;
    setState(() {
      _publishing = false;
      if (ok) _published = true;
    });
    if (!ok) {
      final msg = repo is ApiOwnerRepository
          ? (repo.consumeLastError() ??
              'Error al publicar · No se pudo actualizar el menú de hoy.')
          : 'Error al publicar · No se pudo actualizar el menú de hoy.';
      showInfoSnackBar(messenger, msg);
      return;
    }
    container.invalidate(posMenuProvider);
    container.invalidate(activeOfferProvider);
    if (menu.availabilityState != MenuAvailabilityState.agotadoTotal) {
      final occupancyErr = await ref
          .read(manualOccupancyProvider.notifier)
          .setStatus(ManualOccupancyStatus.libre);
      if (!mounted) return;
      if (occupancyErr != null && occupancyErr.isNotEmpty) {
        showInfoSnackBar(messenger, occupancyErr);
      }
    }
    final publishMsg =
        menu.availabilityState == MenuAvailabilityState.agotadoTotal
            ? 'Menú marcado como Agotado hoy (ofertas flash pausadas)'
            : 'Menú de hoy actualizado con éxito';
    showUndoSnackBar(
      messenger,
      label: publishMsg,
      onUndo: () async {
        final undone = await repo.unpublishMenu(rid);
        if (undone) {
          container.invalidate(posMenuProvider);
          container.invalidate(activeOfferProvider);
          if (mounted) setState(() => _published = false);
        } else {
          final err = repo is ApiOwnerRepository
              ? (repo.consumeLastError() ??
                  'No se pudo deshacer la publicación.')
              : 'No se pudo deshacer la publicación.';
          showInfoSnackBar(messenger, err);
        }
      },
    );
  }

  Future<void> _openOptions(DishKind kind) {
    final current = List.of(_today[kind] ?? const <String>[]);
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OptionsSheet(
        kind: kind,
        initial: current,
        onChanged: (names) => setState(() => _today[kind] = names),
      ),
    );
  }

  Future<void> _editPermanentPrice(PermanentCatalogItem item) async {
    final ctrl = TextEditingController(
      text: (item.priceCents / 100).toStringAsFixed(2),
    );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Editar precio · ${item.name}'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Precio (\$)',
              prefixText: '\$ ',
              hintText: 'Ej. 5.50',
              errorText: error,
            ),
            onChanged: (_) {
              if (error != null) setDialogState(() => error = null);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final parsed =
                    double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) {
                  setDialogState(() => error = 'Ingresa un precio válido.');
                  return;
                }
                ref
                    .read(permanentCatalogProvider.notifier)
                    .updatePrice(item.id, (parsed * 100).round());
                Navigator.of(ctx).pop();
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _openAddPermanentItem(PermanentCatalogGroup group) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewPermanentItemSheet(group: group),
    );
  }

  void _savePermanentChanges() {
    ref.read(permanentCatalogProvider.notifier).saveChanges();
    showInfoSnackBar(
      ScaffoldMessenger.of(context),
      'Cambios guardados en Carta y Bebidas',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final catalog = ref.watch(catalogDishesProvider);
    final permanentState = ref.watch(permanentCatalogProvider);
    final dishes = catalog.value ?? const <CatalogDish>[];

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(dishes, permanentState),
            Expanded(
              child: !_catalogView
                  ? (!_menuLoaded
                      ? const OwnerLoadingView('Cargando menú de hoy')
                      : catalog.when(
                          loading: () =>
                              const OwnerLoadingView('Cargando platos'),
                          error: (_, _) => OwnerErrorView(
                            title: 'No se pudo cargar el menú',
                            message: 'Revisa tu conexión e inténtalo de nuevo.',
                            onRetry: () => ref.invalidate(catalogDishesProvider),
                          ),
                          data: _todayBody,
                        ))
                  : _permanentCatalogBody(permanentState),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomActionContainer(
        child: !_catalogView
            ? ElevatedButton.icon(
                onPressed: _publishing || !_menuLoaded
                    ? null
                    : () => _publish(dishes),
                icon: _publishing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.visibility_outlined),
                label: Text(
                  _published
                      ? 'Actualizar menú de hoy'
                      : 'Publicar menú de hoy',
                ),
              )
            : ElevatedButton.icon(
                onPressed: _savePermanentChanges,
                icon: const Icon(Icons.check_rounded),
                label: const Text('✓ Guardar cambios'),
              ),
      ),
    );
  }

  Widget _header(
    List<CatalogDish> dishes,
    PermanentCatalogState permanentState,
  ) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final now = DateTime.now();
    final avail = !_published
        ? MenuAvailabilityState.sinPublicar
        : _buildMenu(dishes).availabilityState;
    final totalPermanent = permanentState.items.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_catalogView)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ref.watch(ownerRestaurantNameProvider),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                      Text(
                        'Carta y Bebidas',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    OwnerBadge(
                      label: 'Activo siempre',
                      background: b.successContainer,
                      foreground: b.success,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalPermanent == 1
                          ? '1 ítem'
                          : '$totalPermanent ítems',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Menú del día',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                      Text(
                        '${_weekdays[now.weekday - 1]} ${now.day}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        '${_months[now.month - 1]} · ${now.year}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                switch (avail) {
                  MenuAvailabilityState.disponible => OwnerBadge(
                      label: 'Publicado',
                      background: b.successContainer,
                      foreground: b.success,
                    ),
                  MenuAvailabilityState.agotadoTotal => OwnerBadge(
                      label: 'Agotado hoy',
                      background: b.dangerContainer,
                      foreground: b.onDangerContainer,
                    ),
                  MenuAvailabilityState.sinPublicar => OwnerBadge(
                      label: 'Borrador',
                      background: Theme.of(context).scaffoldBackgroundColor,
                      foreground: colors.onSurfaceVariant,
                    ),
                },
              ],
            ),
          const SizedBox(height: 10),
          OwnerSegmented(
            labels: const ['Menú de hoy', 'Carta y Bebidas'],
            index: _catalogView ? 1 : 0,
            onChanged: (i) => setState(() => _catalogView = i == 1),
          ),
        ],
      ),
    );
  }

  // ── Pestaña 1: Menú de hoy ────────────────────────────────────────────────

  Widget _todayBody(List<CatalogDish> dishes) {
    final prices = ref.watch(executivePricesProvider);

    final sections = [
      (
        key: 'sopa',
        title: 'Sopas',
        icon: Icons.soup_kitchen_outlined,
        kind: DishKind.sopa,
        items: _today[DishKind.sopa] ?? const <String>[],
      ),
      (
        key: 'segundo',
        title: 'Segundos',
        icon: Icons.restaurant_rounded,
        kind: DishKind.segundo,
        items: _today[DishKind.segundo] ?? const <String>[],
      ),
      (
        key: 'bebida',
        title: 'Bebida incluida (Jugo)',
        icon: Icons.local_drink_outlined,
        kind: DishKind.bebida,
        items: _today[DishKind.bebida] ?? const <String>[],
      ),
      (
        key: 'postre',
        title: 'Postre incluido',
        icon: Icons.icecream_outlined,
        kind: DishKind.postre,
        items: _today[DishKind.postre] ?? const <String>[],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _ExecutivePriceBanner(
          prices: prices,
          onEditSettings: () => context.go('/owner/settings'),
        ),
        const SizedBox(height: 12),
        for (final sec in sections) ...[
          _AccordionSectionCard(
            title: sec.title,
            icon: sec.icon,
            items: sec.items,
            soldOut: _soldOut,
            expanded: _expandedSections.contains(sec.key),
            onToggleExpand: () => _toggleAccordion(sec.key),
            onToggleDish: _toggleSoldOut,
            onChooseDishes: () => _openOptions(sec.kind),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── Pestaña 2: Carta y Bebidas ────────────────────────────────────────────

  Widget _permanentCatalogBody(PermanentCatalogState permanentState) {
    final colors = context.colorScheme;
    final filtered = permanentState.items
        .where((item) => item.group == _catalogFilter)
        .toList();

    final (String filterTitle, String addButtonLabel) = switch (_catalogFilter) {
      PermanentCatalogGroup.carta => ('Platos a la carta', '+ Agregar plato'),
      PermanentCatalogGroup.bebidas => ('Bebidas', '+ Agregar bebida'),
      PermanentCatalogGroup.extras => ('Extras', '+ Agregar extra'),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (group, label) in const [
                (PermanentCatalogGroup.carta, 'Platos a la carta'),
                (PermanentCatalogGroup.bebidas, 'Bebidas'),
                (PermanentCatalogGroup.extras, 'Extras'),
              ]) ...[
                if (group != PermanentCatalogGroup.carta)
                  const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(label),
                  selected: _catalogFilter == group,
                  onSelected: (_) => setState(() => _catalogFilter = group),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                filterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _openAddPermanentItem(_catalogFilter),
              child: Text(
                addButtonLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          _EmptyLine('No hay ítems en $filterTitle todavía.')
        else
          for (final item in filtered)
            _PermanentItemCard(
              item: item,
              onEditPrice: () => _editPermanentPrice(item),
              onToggleAvailable: (val) => ref
                  .read(permanentCatalogProvider.notifier)
                  .setAvailable(item.id, val),
            ),
      ],
    );
  }
}

class _ExecutivePriceBanner extends StatelessWidget {
  const _ExecutivePriceBanner({
    required this.prices,
    required this.onEditSettings,
  });

  final ExecutivePrices prices;
  final VoidCallback onEditSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final summary =
        'Almuerzo ${OwnerFormat.money(prices.lunch)} · '
        'Segundo ${OwnerFormat.money(prices.soloSecond)} · '
        'Sopa ${OwnerFormat.money(prices.soloSoup)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sell_outlined, size: 17, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    summary,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onEditSettings,
              child: const Text(
                'Editar en Ajustes >',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActionContainer extends StatelessWidget {
  const _BottomActionContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: child,
        ),
      ),
    );
  }
}

class _PermanentItemCard extends StatelessWidget {
  const _PermanentItemCard({
    required this.item,
    required this.onEditPrice,
    required this.onToggleAvailable,
  });

  final PermanentCatalogItem item;
  final VoidCallback onEditPrice;
  final ValueChanged<bool> onToggleAvailable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final priceLabel = OwnerFormat.money(item.priceCents / 100);

    return Opacity(
      opacity: item.available ? 1 : 0.65,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.available
                ? colors.outlineVariant
                : colors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        priceLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onEditPrice,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  value: item.available,
                  onChanged: onToggleAvailable,
                ),
                Text(
                  item.available ? 'Disponible' : 'Agotado',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: item.available ? b.success : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewPermanentItemSheet extends ConsumerStatefulWidget {
  const _NewPermanentItemSheet({required this.group});

  final PermanentCatalogGroup group;

  @override
  ConsumerState<_NewPermanentItemSheet> createState() =>
      _NewPermanentItemSheetState();
}

class _NewPermanentItemSheetState
    extends ConsumerState<_NewPermanentItemSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  bool _available = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del ítem.');
      return;
    }
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (price == null || price <= 0) {
      setState(() => _error = 'Ingresa un precio válido, ej. 4.50.');
      return;
    }
    ref.read(permanentCatalogProvider.notifier).addItem(
          name: name,
          priceCents: (price * 100).round(),
          group: widget.group,
          available: _available,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final (String eyebrow, String title, String hint) = switch (widget.group) {
      PermanentCatalogGroup.carta => (
          'PLATO A LA CARTA',
          'Agregar plato',
          'Ej. Parrillada mixta',
        ),
      PermanentCatalogGroup.bebidas => (
          'BEBIDAS',
          'Agregar bebida',
          'Ej. Jarra de limonada',
        ),
      PermanentCatalogGroup.extras => (
          'EXTRAS',
          'Agregar extra',
          'Ej. Porción de patacones',
        ),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerSectionLabel(eyebrow, color: colors.primary),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nombre',
                hintText: hint,
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Precio (\$)',
                prefixText: '\$ ',
                hintText: 'Ej. 4.50',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Disponible para venta',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _save,
              child: Text(title),
            ),
          ],
        ),
      ),
    );
  }
}

String _sectionSummaryCount(List<String> names, Set<String> soldOut) {
  if (names.isEmpty) return 'Sin platos elegidos';
  final sold = names.where(soldOut.contains).length;
  final totalLabel = names.length == 1 ? '1 plato' : '${names.length} platos';
  if (sold == 0) return totalLabel;
  final soldLabel = sold == 1 ? '1 agotado' : '$sold agotados';
  return '$totalLabel · $soldLabel';
}

class _AccordionSectionCard extends StatelessWidget {
  const _AccordionSectionCard({
    required this.title,
    required this.icon,
    required this.items,
    required this.soldOut,
    required this.expanded,
    required this.onToggleExpand,
    required this.onToggleDish,
    required this.onChooseDishes,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final Set<String> soldOut;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onToggleDish;
  final VoidCallback onChooseDishes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 22, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _sectionSummaryCount(items, soldOut),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 26,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Sin platos seleccionados hoy.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final name in items) ...[
                      _DishToggle(
                        name: name,
                        soldOut: soldOut.contains(name),
                        onTap: () => onToggleDish(name),
                      ),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: onChooseDishes,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('+ Agregar plato del día'),
                  ),
                ],
              ),
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

/// Interruptor de un plato: "✓ Hay" o "Agotado".
class _DishToggle extends StatelessWidget {
  const _DishToggle({
    required this.name,
    required this.soldOut,
    required this.onTap,
  });

  final String name;
  final bool soldOut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Semantics(
      button: true,
      toggled: soldOut,
      label: soldOut
          ? '$name: agotado. Toca si volvió a haber'
          : '$name: hay. Toca si se agotó',
      excludeSemantics: true,
      child: Material(
        color: soldOut
            ? b.dangerContainer.withValues(alpha: 0.55)
            : Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: soldOut ? b.danger : colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: soldOut ? colors.onSurfaceVariant : colors.onSurface,
                      decoration: soldOut ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: soldOut ? b.dangerContainer : b.successContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Text(
                    soldOut ? 'Agotado' : '✓ Hay',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: soldOut ? b.onDangerContainer : b.success,
                    ),
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

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Selector de opciones del día por sección.
class _OptionsSheet extends ConsumerStatefulWidget {
  const _OptionsSheet({
    required this.kind,
    required this.initial,
    required this.onChanged,
  });

  final DishKind kind;
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends ConsumerState<_OptionsSheet> {
  late final List<String> _selected = widget.initial;
  final _quick = TextEditingController();

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  void _toggle(String name) {
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
    widget.onChanged(List.of(_selected));
  }

  Future<void> _addQuick() async {
    final name = _quick.text.trim();
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final prices = ref.read(executivePricesProvider);
    final double? price = switch (widget.kind) {
      DishKind.sopa => prices.soloSoup,
      DishKind.segundo => prices.soloSecond,
      _ => null,
    };

    try {
      await ref.read(ownerCatalogRepositoryProvider).addDish(
            ref.read(ownerRestaurantIdProvider),
            name: name,
            kind: widget.kind,
            price: price,
          );
      if (!mounted) return;
      ref.invalidate(catalogDishesProvider);
      _quick.clear();
      if (!_selected.contains(name)) _toggle(name);
    } on ApiException catch (e) {
      if (mounted) showInfoSnackBar(messenger, e.userMessage);
    } catch (_) {
      if (mounted) showInfoSnackBar(messenger, 'No se pudo agregar el plato.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final dishes = [
      for (final d
          in ref.watch(catalogDishesProvider).value ?? const <CatalogDish>[])
        if (d.kind == widget.kind && !d.archived) d,
    ];
    final heading = 'Elegir ${_plural(widget.kind)}';
    final hint = switch (widget.kind) {
      DishKind.sopa => 'Ej. Caldo de bola',
      DishKind.bebida => 'Ej. Jugo de maracuyá',
      DishKind.postre => 'Ej. Flan de coco',
      _ => 'Ej. Chivo al hueco',
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerSectionLabel('Almuerzo de hoy', color: colors.primary),
            Text(
              heading,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            if (dishes.isEmpty)
              const _EmptyLine('Aún no tienes platos guardados en esta sección.')
            else
              for (final d in dishes) ...[
                _OptionTile(
                  name: d.name,
                  included: _selected.contains(d.name),
                  onTap: () => _toggle(d.name),
                ),
                const SizedBox(height: 8),
              ],
            Divider(height: 20, color: colors.outlineVariant),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quick,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Nuevo plato',
                      hintText: hint,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addQuick(),
                  ),
                ),
                const SizedBox(width: 8),
                OwnerSmallButton(label: 'Agregar', onPressed: _addQuick),
              ],
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Listo para hoy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.name,
    required this.included,
    required this.onTap,
  });

  final String name;
  final bool included;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: included
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: included ? colors.primary : colors.outlineVariant,
          width: included ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                included
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: included ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
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
