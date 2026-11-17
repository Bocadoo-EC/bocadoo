import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/api_owner_repo.dart';
import '../domain/models/daily_menu.dart';
import '../domain/models/menu_models.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

const _weekdays = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const _months = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];
const _lunchKinds = [DishKind.sopa, DishKind.segundo, DishKind.bebida, DishKind.postre];

enum _PlatosTab { almuerzos, desayunos, carta }

String _plural(DishKind k) => switch (k) {
      DishKind.sopa => 'sopas',
      DishKind.segundo => 'segundos',
      DishKind.bebida => 'bebidas',
      DishKind.postre => 'postres',
      DishKind.desayuno => 'desayunos',
      DishKind.carta => 'platos a la carta',
    };

/// O7 · Menú de hoy (segmento Hoy) y catálogo de la casa (segmento Mis platos).
class OwnerMenuScreen extends ConsumerStatefulWidget {
  const OwnerMenuScreen({super.key});

  @override
  ConsumerState<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends ConsumerState<OwnerMenuScreen> {
  bool _catalogView = false;
  _PlatosTab _platosTab = _PlatosTab.almuerzos;

  final Map<DishKind, List<String>> _today = {
    DishKind.sopa: ['Locro de papa con queso', 'Sopa de lenteja'],
    DishKind.segundo: ['Pollo a la plancha', 'Seco de pollo con maduro', 'Bowl de quinoa'],
    DishKind.bebida: ['Jugo de naranjilla'],
    DishKind.postre: ['Higos con queso'],
  };
  final List<String> _breakfastIds = ['b-1'];
  final Set<String> _soldOut = {};
  final Set<DishKind> _activeSections = {DishKind.sopa, DishKind.segundo, DishKind.bebida};
  bool _published = false;
  bool _menuLoaded = false;
  bool _publishing = false;

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
        final names = [for (final c in menu.courses) if (c.category == k.courseCategory) c.name];
        if (names.isNotEmpty) _today[k] = names;
      }
      _breakfastIds
        ..clear()
        ..addAll([for (final c in menu.courses) if (c.category == 'Desayuno') c.id]);
      _soldOut
        ..clear()
        ..addAll([for (final c in menu.courses) if (c.isSoldOut) c.name]);
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
    // Se avisa al instante al POS y al comensal, sin volver a publicar.
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
          ? (repo.consumeLastError() ?? 'No se pudo actualizar el estado del plato.')
          : 'No se pudo actualizar el estado del plato.';
      showInfoSnackBar(messenger, msg);
      return;
    }
    ref.invalidate(posMenuProvider);
  }

  DailyMenu _buildMenu(List<CatalogDish> dishes) {
    final courses = <DailyMenuCourse>[];
    for (final k in _lunchKinds) {
      final names = _today[k] ?? const <String>[];
      for (var i = 0; i < names.length; i++) {
        final matched = dishes
            .where((d) =>
                d.kind == k &&
                d.name.trim().toLowerCase() == names[i].trim().toLowerCase())
            .firstOrNull;
        courses.add(DailyMenuCourse(
          id: matched?.id ?? '${k.name}-$i',
          name: names[i],
          category: k.courseCategory,
          price: matched?.price,
          isSoldOut: _soldOut.contains(names[i]),
        ));
      }
    }
    for (final id in _breakfastIds) {
      final dish = dishes.where((d) => d.id == id).firstOrNull;
      if (dish == null) continue;
      courses.add(DailyMenuCourse(
        id: dish.id,
        name: dish.name,
        category: 'Desayuno',
        price: dish.price,
        isSoldOut: _soldOut.contains(dish.name),
      ));
    }
    return DailyMenu(restaurantId: _rid, date: DateTime.now(), courses: courses, isPublished: true);
  }

  Future<void> _publish(List<CatalogDish> dishes) async {
    final messenger = ScaffoldMessenger.of(context);
    final menu = _buildMenu(dishes);
    if (menu.courses.isEmpty) {
      showInfoSnackBar(messenger, 'Agrega al menos un plato antes de publicar el menú.');
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
          ? (repo.consumeLastError() ?? 'Error al publicar · No se pudo actualizar el menú de hoy.')
          : 'Error al publicar · No se pudo actualizar el menú de hoy.';
      showInfoSnackBar(messenger, msg);
      return;
    }
    container.invalidate(posMenuProvider);
    showUndoSnackBar(messenger, label: 'Menú publicado con éxito', onUndo: () async {
      final undone = await repo.unpublishMenu(rid);
      if (undone) {
        container.invalidate(posMenuProvider);
        if (mounted) setState(() => _published = false);
      } else {
        final err = repo is ApiOwnerRepository
            ? (repo.consumeLastError() ?? 'No se pudo deshacer la publicación.')
            : 'No se pudo deshacer la publicación.';
        showInfoSnackBar(messenger, err);
      }
    });
  }

  Future<void> _openOptions(DishKind kind) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OptionsSheet(
        kind: kind,
        initial: List.of(_today[kind] ?? const <String>[]),
        onChanged: (names) => setState(() => _today[kind] = names),
      ),
    );
  }

  Future<void> _openBreakfasts() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BreakfastSheet(
        initial: List.of(_breakfastIds),
        onChanged: (ids) => setState(() => _breakfastIds
          ..clear()
          ..addAll(ids)),
      ),
    );
  }

  Future<void> _openNewDish(DishKind kind) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewDishSheet(
        initialKind: kind,
        sections: [for (final k in _lunchKinds) if (_activeSections.contains(k) || k == kind) k],
      ),
    );
  }

  Future<void> _openNewCarta() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewCartaSheet(),
    );
  }

  Future<void> _setArchived(CatalogDish dish, bool archived) async {
    await ref.read(ownerCatalogRepositoryProvider).setDishArchived(_rid, dish.id, archived: archived);
    if (!mounted) return;
    if (archived && dish.kind == DishKind.desayuno) setState(() => _breakfastIds.remove(dish.id));
    ref.invalidate(catalogDishesProvider);
  }

  void _backToToday(String message) {
    setState(() => _catalogView = false);
    showInfoSnackBar(ScaffoldMessenger.of(context), message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final catalog = ref.watch(catalogDishesProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(catalog.value?.length ?? 0),
          Expanded(
            child: !_menuLoaded
                ? const OwnerLoadingView('Cargando platos')
                : catalog.when(
                    loading: () => const OwnerLoadingView('Cargando platos'),
                    error: (_, _) => OwnerErrorView(
                      title: 'No se pudo cargar el menú',
                      message: 'Revisa tu conexión e inténtalo de nuevo.',
                      onRetry: () => ref.invalidate(catalogDishesProvider),
                    ),
                    data: (dishes) => _catalogView ? _catalogBody(dishes) : _todayBody(dishes),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _header(int dishCount) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_catalogView)
          OwnerBackHeader(
            title: 'Platos de la casa',
            onBack: () => setState(() => _catalogView = false),
            eyebrow: Text(ref.watch(ownerRestaurantNameProvider),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
            trailing: Text('$dishCount platos',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.primary)),
          )
        else
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Menú del día',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
                Text('${_weekdays[now.weekday - 1]} ${now.day}',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.15, color: colors.onSurface)),
                Text('${_months[now.month - 1]} · ${now.year}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            ),
            IconButton.filledTonal(
              tooltip: 'Agregar platos',
              onPressed: () => setState(() => _catalogView = true),
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          _published
              ? OwnerBadge(label: 'Publicado', background: b.successContainer, foreground: b.success)
              : OwnerBadge(
                  label: 'Borrador',
                  background: Theme.of(context).scaffoldBackgroundColor,
                  foreground: colors.onSurfaceVariant,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: OwnerSegmented(
              labels: const ['Hoy', 'Mis platos'],
              index: _catalogView ? 1 : 0,
              onChanged: (i) => setState(() => _catalogView = i == 1),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Segmento Hoy ──────────────────────────────────────────────────────────

  Widget _todayBody(List<CatalogDish> dishes) {
    final colors = context.colorScheme;
    final veggieNames = {for (final d in dishes) if (d.veggie) d.name};
    final mains = _today[DishKind.segundo] ?? const <String>[];
    final cards = [
      (title: 'Sopa', icon: Icons.soup_kitchen_outlined, kind: DishKind.sopa, items: _today[DishKind.sopa] ?? const <String>[]),
      (title: 'Segundo', icon: Icons.restaurant_rounded, kind: DishKind.segundo, items: [for (final m in mains) if (!veggieNames.contains(m)) m]),
      (title: 'Opción veggie', icon: Icons.eco_outlined, kind: DishKind.segundo, items: [for (final m in mains) if (veggieNames.contains(m)) m]),
      (title: 'Bebida', icon: Icons.local_drink_outlined, kind: DishKind.bebida, items: _today[DishKind.bebida] ?? const <String>[]),
    ];
    final breakfasts = [
      for (final id in _breakfastIds) ?dishes.where((d) => d.id == id).firstOrNull,
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      const _OrdersStrip(),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '¿Se acabó un plato? Tócalo y solo ese deja de ofrecerse. Los demás siguen.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final card in cards)
            SizedBox(
              width: w,
              child: _SectionCard(
                title: card.title,
                icon: card.icon,
                items: card.items,
                soldOut: _soldOut,
                onToggle: _toggleSoldOut,
                onOptions: () => _openOptions(card.kind),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 12),
      _BreakfastToday(
        items: breakfasts,
        soldOut: _soldOut,
        onToggle: _toggleSoldOut,
        onAdd: _openBreakfasts,
      ),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: _publishing ? null : () => _publish(dishes),
        icon: _publishing
            ? SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary))
            : const Icon(Icons.visibility_outlined),
        label: Text(_published ? 'Actualizar menú' : 'Publicar menú'),
      ),
    ]);
  }

  // ── Segmento Mis platos ───────────────────────────────────────────────────

  Widget _catalogBody(List<CatalogDish> dishes) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      OwnerSegmented(
        labels: const ['Almuerzos', 'Desayunos', 'A la carta'],
        index: _platosTab.index,
        onChanged: (i) => setState(() => _platosTab = _PlatosTab.values[i]),
      ),
      const SizedBox(height: 16),
      ...switch (_platosTab) {
        _PlatosTab.almuerzos => _lunchCatalog(dishes),
        _PlatosTab.desayunos => _breakfastCatalog(dishes),
        _PlatosTab.carta => _cartaCatalog(dishes),
      },
    ]);
  }

  List<Widget> _lunchCatalog(List<CatalogDish> dishes) {
    final colors = context.colorScheme;
    const sections = [
      (kind: DishKind.bebida, label: 'Jugo'),
      (kind: DishKind.sopa, label: 'Sopa'),
      (kind: DishKind.segundo, label: 'Plato fuerte'),
      (kind: DishKind.postre, label: 'Postre'),
    ];
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(24)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colors.primary,
            child: Icon(Icons.restaurant_rounded, size: 18, color: colors.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tus platos nunca se pierden',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onPrimaryContainer)),
              const SizedBox(height: 2),
              Text(
                'Conserva siempre el historial de ventas y favoritos. Si dejas de preparar un plato '
                'temporalmente, usa Archivar para ocultarlo del selector sin borrar sus datos.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onPrimaryContainer),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: OwnerSectionLabel('Secciones activas')),
            Text('${_activeSections.length} activas',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in _lunchKinds)
              OwnerChoice(
                label: k.label,
                selected: _activeSections.contains(k),
                onTap: () => setState(() {
                  if (!_activeSections.remove(k)) _activeSections.add(k);
                }),
              ),
          ]),
        ]),
      ),
      for (final s in sections) ...[
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Text(s.label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
          ),
          OwnerSmallButton(label: 'Agregar', icon: Icons.add_rounded, onPressed: () => _openNewDish(s.kind)),
        ]),
        const SizedBox(height: 8),
        ..._dishRows(
          [for (final d in dishes) if (d.kind == s.kind) d],
          empty: 'Aún no hay platos en ${s.label.toLowerCase()}.',
          activeText: 'Activo en opciones de almuerzo',
          archivedText: 'Archivado · Oculto de hoy',
        ),
      ],
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: () => _backToToday('Platos de la casa guardados'),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Guardar platos de la casa'),
      ),
    ];
  }

  List<Widget> _breakfastCatalog(List<CatalogDish> dishes) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final items = [for (final d in dishes) if (d.kind == DishKind.desayuno) d];
    return [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Desayunos de la casa',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
            Text('Marca cuáles ofreces hoy y publícalos con el menú.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        OwnerSmallButton(label: 'Nuevo desayuno', icon: Icons.add_rounded, onPressed: _openBreakfasts),
      ]),
      const SizedBox(height: 12),
      if (items.isEmpty)
        _EmptyLine('Aún no hay desayunos. Agrega el primero.')
      else
        for (final d in items)
          _CatalogRow(
            dish: d,
            subtitle: Text(OwnerFormat.money(d.price ?? 0),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: b.success)),
            actions: [
              if (!d.archived)
                OwnerChoice(
                  label: _breakfastIds.contains(d.id) ? 'En hoy' : 'Ofrecer hoy',
                  selected: _breakfastIds.contains(d.id),
                  onTap: () => setState(() {
                    if (!_breakfastIds.remove(d.id)) _breakfastIds.add(d.id);
                  }),
                ),
              OwnerSmallButton(
                label: d.archived ? 'Activar' : 'Archivar',
                tonal: false,
                onPressed: () => _setArchived(d, !d.archived),
              ),
            ],
          ),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: () => _backToToday('Desayunos guardados'),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Guardar desayunos'),
      ),
    ];
  }

  List<Widget> _cartaCatalog(List<CatalogDish> dishes) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final items = [for (final d in dishes) if (d.kind == DishKind.carta) d];
    return [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Especialidades de la casa',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
            Text('Platos individuales que se venden a precio libre fuera del combo de almuerzo.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        OwnerSmallButton(label: 'Nuevo plato', icon: Icons.add_rounded, onPressed: _openNewCarta),
      ]),
      const SizedBox(height: 12),
      if (items.isEmpty)
        _EmptyLine('Aún no hay platos a la carta. Agrega el primero.')
      else
        for (final d in items)
          _CatalogRow(
            dish: d,
            badge: OwnerBadge(
              label: OwnerFormat.money(d.price ?? 0),
              background: b.successContainer,
              foreground: b.success,
            ),
            subtitle: Text(d.description,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
            actions: [
              OwnerSmallButton(
                label: d.archived ? 'Activar' : 'Archivar',
                tonal: false,
                onPressed: () => _setArchived(d, !d.archived),
              ),
            ],
          ),
    ];
  }

  List<Widget> _dishRows(
    List<CatalogDish> items, {
    required String empty,
    required String activeText,
    required String archivedText,
  }) {
    final colors = context.colorScheme;
    if (items.isEmpty) return [_EmptyLine(empty)];
    return [
      for (final d in items)
        _CatalogRow(
          dish: d,
          badge: d.topPick ? const _TopPickChip() : null,
          subtitle: Text(d.archived ? archivedText : activeText,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
          actions: [
            OwnerSmallButton(
              label: d.archived ? 'Activar' : 'Archivar',
              tonal: false,
              onPressed: () => _setArchived(d, !d.archived),
            ),
          ],
        ),
    ];
  }
}

// ── Piezas del segmento Hoy ──────────────────────────────────────────────────

class _OrdersStrip extends ConsumerWidget {
  const _OrdersStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final n = ref.watch(ordersOnTheWayProvider).value ?? 0;
    return Material(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/owner/pedidos'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.primary,
              child: Icon(Icons.schedule_rounded, size: 16, color: colors.onPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                n == 1 ? '1 preorden en camino' : '$n preórdenes en camino',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onPrimaryContainer),
              ),
            ),
            Text('Ver pedidos',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
            Icon(Icons.chevron_right_rounded, color: colors.primary),
          ]),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.items,
    required this.soldOut,
    required this.onToggle,
    required this.onOptions,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final Set<String> soldOut;
  final ValueChanged<String> onToggle;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 72,
          color: colors.primaryContainer,
          padding: const EdgeInsets.all(8),
          child: Stack(children: [
            Align(alignment: Alignment.center, child: Icon(icon, size: 30, color: colors.primary)),
            Align(
              alignment: Alignment.topRight,
              child: Material(
                color: colors.surface,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onOptions,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.tune_rounded, size: 14, color: colors.primary),
                      const SizedBox(width: 4),
                      Text('Opciones (${items.length})',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('$title (${items.length})',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.primary)),
            const SizedBox(height: 6),
            if (items.isEmpty)
              Text('Sin opciones hoy', style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant))
            else
              for (final name in items) ...[
                _DishToggle(name: name, soldOut: soldOut.contains(name), onTap: () => onToggle(name)),
                const SizedBox(height: 6),
              ],
          ]),
        ),
      ]),
    );
  }
}

/// Interruptor de un plato: "Hay" o "Se acabó". Solo afecta a ese plato.
class _DishToggle extends StatelessWidget {
  const _DishToggle({required this.name, required this.soldOut, required this.onTap, this.price});

  final String name;
  final bool soldOut;
  final VoidCallback onTap;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Semantics(
      button: true,
      toggled: soldOut,
      label: soldOut ? '$name: se acabó. Toca si volvió a haber' : '$name: hay. Toca si se acabó',
      excludeSemantics: true,
      child: Material(
        color: soldOut ? b.dangerContainer : Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: soldOut ? b.danger : colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: soldOut ? colors.onSurfaceVariant : colors.onSurface,
                      decoration: soldOut ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(soldOut ? Icons.close_rounded : Icons.check_rounded,
                        size: 14, color: soldOut ? b.onDangerContainer : b.success),
                    const SizedBox(width: 3),
                    Text(soldOut ? 'Se acabó' : 'Hay',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: soldOut ? b.onDangerContainer : b.success,
                        )),
                  ]),
                ]),
              ),
              if (price != null)
                Text(OwnerFormat.money(price!),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BreakfastToday extends StatelessWidget {
  const _BreakfastToday({
    required this.items,
    required this.soldOut,
    required this.onToggle,
    required this.onAdd,
  });

  final List<CatalogDish> items;
  final Set<String> soldOut;
  final ValueChanged<String> onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.wb_sunny_outlined, size: 18, color: colors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Desayunos (${items.length})',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.primary)),
          ),
          OwnerSmallButton(label: 'Agregar', icon: Icons.add_rounded, onPressed: onAdd),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty)
          _EmptyLine('Hoy no ofreces desayunos. Toca Agregar para sumarlos al menú.')
        else
          for (final d in items) ...[
            _DishToggle(name: d.name, price: d.price, soldOut: soldOut.contains(d.name), onTap: () => onToggle(d.name)),
            const SizedBox(height: 6),
          ],
      ]),
    );
  }
}

// ── Piezas de Mis platos ─────────────────────────────────────────────────────

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.dish, required this.subtitle, required this.actions, this.badge});

  final CatalogDish dish;
  final Widget subtitle;
  final Widget? badge;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Opacity(
      opacity: dish.archived ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(dish.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.onSurface)),
            ?badge,
          ]),
          const SizedBox(height: 2),
          subtitle,
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
        ]),
      ),
    );
  }
}

class _TopPickChip extends StatelessWidget {
  const _TopPickChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: 14, color: colors.primary),
        const SizedBox(width: 3),
        Text('Más pedido',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
      ]),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.colorScheme.onSurfaceVariant)),
    );
  }
}

// ── Hojas ───────────────────────────────────────────────────────────────────

/// Selector de opciones del día por sección. Siempre queda al menos una.
class _OptionsSheet extends ConsumerStatefulWidget {
  const _OptionsSheet({required this.kind, required this.initial, required this.onChanged});

  final DishKind kind;
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends ConsumerState<_OptionsSheet> {
  late final List<String> _selected = widget.initial;
  final _quick = TextEditingController();
  final _quickPrice = TextEditingController();

  bool get _needsPrice =>
      widget.kind == DishKind.sopa || widget.kind == DishKind.segundo;

  @override
  void dispose() {
    _quick.dispose();
    _quickPrice.dispose();
    super.dispose();
  }

  void _toggle(String name) {
    setState(() {
      if (_selected.contains(name)) {
        if (_selected.length > 1) _selected.remove(name);
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
    double? price;
    if (_needsPrice) {
      price = double.tryParse(_quickPrice.text.trim().replaceAll(',', '.'));
      if (price == null || price <= 0) {
        showInfoSnackBar(messenger, 'Ingresa un precio válido (ej. 2.50).');
        return;
      }
    }
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
      _quickPrice.clear();
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
      for (final d in ref.watch(catalogDishesProvider).value ?? const <CatalogDish>[])
        if (d.kind == widget.kind && !d.archived) d,
    ];
    final singular = widget.kind.label.toLowerCase();
    final hint = switch (widget.kind) {
      DishKind.sopa => 'Ej. Caldo de bola',
      DishKind.bebida => 'Ej. Jugo de maracuyá',
      _ => 'Ej. Chivo al hueco',
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OwnerSectionLabel('Almuerzo de hoy', color: colors.primary),
          Text('Elegir ${_plural(widget.kind)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 6),
          Text('Selecciona las opciones que ofreces hoy (puedes marcar varias):',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
          const SizedBox(height: 10),
          for (final d in dishes) ...[
            _OptionTile(
              name: d.name,
              topPick: d.topPick,
              included: _selected.contains(d.name),
              onTap: () => _toggle(d.name),
            ),
            const SizedBox(height: 8),
          ],
          Divider(height: 20, color: colors.outlineVariant),
          Text('¿Preparaste una nueva $singular?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _quick,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: hint, isDense: true),
                onSubmitted: (_) => _addQuick(),
              ),
            ),
            if (_needsPrice) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _quickPrice,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Precio \$', isDense: true),
                  onSubmitted: (_) => _addQuick(),
                ),
              ),
            ],
            const SizedBox(width: 8),
            OwnerSmallButton(label: 'Agregar', onPressed: _addQuick),
          ]),
          const SizedBox(height: 18),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Listo para hoy')),
        ]),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.name, required this.topPick, required this.included, required this.onTap});

  final String name;
  final bool topPick;
  final bool included;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: included ? colors.primaryContainer : Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: included ? colors.primary : colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: included ? colors.onPrimaryContainer : colors.onSurface,
                    )),
                if (topPick) const _TopPickChip(),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(included ? Icons.check_rounded : Icons.add_rounded,
                size: 18, color: included ? colors.primary : colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(included ? 'Incluido' : 'Agregar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: included ? colors.primary : colors.onSurfaceVariant,
                )),
          ]),
        ),
      ),
    );
  }
}

/// Desayunos de hoy: marcar los que se ofrecen o crear uno nuevo con precio.
class _BreakfastSheet extends ConsumerStatefulWidget {
  const _BreakfastSheet({required this.initial, required this.onChanged});

  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<_BreakfastSheet> createState() => _BreakfastSheetState();
}

class _BreakfastSheetState extends ConsumerState<_BreakfastSheet> {
  late final List<String> _selected = widget.initial;
  final _name = TextEditingController();
  final _price = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
    widget.onChanged(List.of(_selected));
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del desayuno.');
      return;
    }
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (price == null || price <= 0) {
      setState(() => _error = 'Escribe un precio válido, por ejemplo 2.50.');
      return;
    }
    try {
      final dish = await ref.read(ownerCatalogRepositoryProvider).addDish(
            ref.read(ownerRestaurantIdProvider),
            name: name,
            kind: DishKind.desayuno,
            price: price,
          );
      if (!mounted) return;
      ref.invalidate(catalogDishesProvider);
      _name.clear();
      _price.clear();
      setState(() => _error = null);
      _toggle(dish.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar el desayuno.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final items = [
      for (final d in ref.watch(catalogDishesProvider).value ?? const <CatalogDish>[])
        if (d.kind == DishKind.desayuno && !d.archived) d,
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Desayunos de hoy',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 10),
          if (items.isEmpty) _EmptyLine('Aún no tienes desayunos guardados.'),
          for (final d in items) ...[
            _OptionTile(
              name: '${d.name} · ${OwnerFormat.money(d.price ?? 0)}',
              topPick: false,
              included: _selected.contains(d.id),
              onTap: () => _toggle(d.id),
            ),
            const SizedBox(height: 8),
          ],
          Divider(height: 20, color: colors.outlineVariant),
          Text('¿Un desayuno nuevo?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Ej. Empanada de viento + Café', isDense: true),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(hintText: 'Precio, ej. 2.50', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            OwnerSmallButton(label: 'Agregar', onPressed: _create),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.bocadooColors.danger)),
          ],
          const SizedBox(height: 18),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Listo')),
        ]),
      ),
    );
  }
}

class _NewDishSheet extends ConsumerStatefulWidget {
  const _NewDishSheet({required this.initialKind, required this.sections});

  final DishKind initialKind;
  final List<DishKind> sections;

  @override
  ConsumerState<_NewDishSheet> createState() => _NewDishSheetState();
}

class _NewDishSheetState extends ConsumerState<_NewDishSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  late DishKind _kind = widget.initialKind;
  String? _error;

  bool get _needsPrice => _kind == DishKind.sopa || _kind == DishKind.segundo;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del plato.');
      return;
    }
    double? price;
    if (_needsPrice) {
      price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
      if (price == null || price <= 0) {
        setState(() => _error = 'Ingresa un precio válido para ${_kind.label.toLowerCase()}, ej. 3.00.');
        return;
      }
    }
    final navigator = Navigator.of(context);
    try {
      await ref.read(ownerCatalogRepositoryProvider).addDish(
            ref.read(ownerRestaurantIdProvider),
            name: name,
            kind: _kind,
            price: price,
          );
      if (!mounted) return;
      ref.invalidate(catalogDishesProvider);
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar el plato.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nuevo plato', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nombre del plato',
              hintText: 'Ej. Seco de carne con arroz',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 14),
          const OwnerSectionLabel('Sección'),
          const SizedBox(height: 8),
          Row(children: [
            for (final k in widget.sections) ...[
              if (k != widget.sections.first) const SizedBox(width: 6),
              Expanded(
                child: OwnerChoice(label: k.label, selected: _kind == k, onTap: () => setState(() => _kind = k)),
              ),
            ],
          ]),
          if (_needsPrice) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio (\$)',
                hintText: 'Ej. 3.00',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
          const SizedBox(height: 18),
          ElevatedButton(onPressed: _save, child: const Text('Guardar plato')),
        ]),
      ),
    );
  }
}

class _NewCartaSheet extends ConsumerStatefulWidget {
  const _NewCartaSheet();

  @override
  ConsumerState<_NewCartaSheet> createState() => _NewCartaSheetState();
}

class _NewCartaSheetState extends ConsumerState<_NewCartaSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del plato.');
      return;
    }
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 5.0;
    final desc = _desc.text.trim();
    final navigator = Navigator.of(context);
    try {
      await ref.read(ownerCatalogRepositoryProvider).addDish(
            ref.read(ownerRestaurantIdProvider),
            name: name,
            kind: DishKind.carta,
            price: price,
            description: desc.isEmpty ? 'Especialidad de la casa preparada al momento' : desc,
          );
      if (!mounted) return;
      ref.invalidate(catalogDishesProvider);
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar el plato.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Plato a la carta',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nombre del plato',
              hintText: 'Ej. Parrillada mixta',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(labelText: 'Precio en dólares', hintText: 'Ej. 6.50'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descripción', hintText: 'Ej. Con patacones y ensalada'),
          ),
          const SizedBox(height: 18),
          ElevatedButton(onPressed: _save, child: const Text('Guardar especialidad')),
        ]),
      ),
    );
  }
}
