import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/daily_menu.dart';
import '../domain/repositories/i_owner_repository.dart';
import 'owner_controller.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final _menuNotifierProvider =
    AsyncNotifierProvider<_MenuNotifier, DailyMenu?>(_MenuNotifier.new);

class _MenuNotifier extends AsyncNotifier<DailyMenu?> {
  IOwnerMenuRepository get _repo => ref.read(ownerMenuRepositoryProvider);
  String get _restaurantId => ref.read(ownerRestaurantIdProvider);

  @override
  Future<DailyMenu?> build() => _repo.getTodayMenu(_restaurantId);

  Future<void> repeatYesterday() async {
    state = const AsyncLoading();
    final yesterday = await _repo.getYesterdayMenu(_restaurantId);
    if (yesterday == null) {
      state = const AsyncData(null);
      return;
    }
    state = AsyncData(yesterday.copyWith(
      date: DateTime.now(),
      isPublished: false,
    ));
  }

  Future<void> publish() async {
    final current = state.value;
    if (current == null) return;
    state = const AsyncLoading();
    final ok = await _repo.publishMenu(current);
    state = ok
        ? AsyncData(current.copyWith(isPublished: true))
        : AsyncError('No se pudo publicar.', StackTrace.current);
  }

  Future<void> markSoldOut() async {
    final ok = await _repo.markSoldOut(_restaurantId);
    if (!ok) return;
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(isPublished: false));
    }
  }

  void updateCourse(int index, DailyMenuCourse updated) {
    final current = state.value;
    if (current == null) return;
    final courses = List<DailyMenuCourse>.from(current.courses);
    if (index < 0 || index >= courses.length) return;
    courses[index] = updated;
    state = AsyncData(current.copyWith(courses: courses, isPublished: false));
  }
}

// ── Pantalla ───────────────────────────────────────────────────────────────

/// Gestión operativa del menú del día: redactar, publicar y marcar agotado.
class OwnerMenuScreen extends ConsumerWidget {
  const OwnerMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_menuNotifierProvider);
    final notifier = ref.read(_menuNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú del día'),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/owner/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBanner(
            message: '$e',
            onRetry: () => ref.invalidate(_menuNotifierProvider),
          ),
          data: (menu) => menu == null
              ? _EmptyState(onRepeatYesterday: notifier.repeatYesterday)
              : _MenuBody(menu: menu, notifier: notifier),
        ),
      ),
    );
  }
}

// ── Estado vacío ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRepeatYesterday});

  final Future<void> Function() onRepeatYesterday;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.restaurant_menu_outlined,
                size: 40,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sin menú hoy',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Publica el menú para que los comensales lo vean.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRepeatYesterday,
              icon: const Icon(Icons.replay_outlined),
              label: const Text('Repetir ayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cuerpo del menú ─────────────────────────────────────────────────────────

class _MenuBody extends StatelessWidget {
  const _MenuBody({required this.menu, required this.notifier});

  final DailyMenu menu;
  final _MenuNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _StatusChip(isPublished: menu.isPublished),
        const SizedBox(height: 16),
        for (int i = 0; i < menu.courses.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CourseCard(
              course: menu.courses[i],
              onNameChanged: (name) => notifier.updateCourse(
                i,
                menu.courses[i].copyWith(name: name),
              ),
              onSoldOutToggle: () => notifier.updateCourse(
                i,
                menu.courses[i].copyWith(isSoldOut: !menu.courses[i].isSoldOut),
              ),
            ),
          ),
        const SizedBox(height: 8),
        _ActionBar(menu: menu, notifier: notifier),
      ],
    );
  }
}

// ── Chip de estado ──────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isPublished});

  final bool isPublished;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bocadooColors;
    final (Color bg, Color fg, String label, IconData icon) = isPublished
        ? (
            tokens.successContainer,
            tokens.onSuccessContainer,
            'Publicado',
            Icons.check_circle_outline,
          )
        : (
            context.colorScheme.secondaryContainer,
            context.colorScheme.onSecondaryContainer,
            'Sin publicar',
            Icons.edit_outlined,
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tarjeta de un plato ─────────────────────────────────────────────────────

class _CourseCard extends StatefulWidget {
  const _CourseCard({
    required this.course,
    required this.onNameChanged,
    required this.onSoldOutToggle,
  });

  final DailyMenuCourse course;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onSoldOutToggle;

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.course.name);

  @override
  void didUpdateWidget(_CourseCard old) {
    super.didUpdateWidget(old);
    if (old.course.name != widget.course.name &&
        _ctrl.text != widget.course.name) {
      _ctrl.text = widget.course.name;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final theme = Theme.of(context);
    final tokens = context.bocadooColors;
    final soldOut = widget.course.isSoldOut;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.course.category,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onSoldOutToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: soldOut
                        ? tokens.dangerContainer
                        : scheme.primaryContainer,
                    borderRadius:
                        BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Text(
                    soldOut ? 'Agotado' : 'Libre',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: soldOut
                          ? tokens.onDangerContainer
                          : scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            enabled: !soldOut,
            textInputAction: TextInputAction.done,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Plato ${widget.course.category.toLowerCase()}…',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
            ),
            onChanged: widget.onNameChanged,
          ),
        ],
      ),
    );
  }
}

// ── Barra de acciones ────────────────────────────────────────────────────────

class _ActionBar extends StatefulWidget {
  const _ActionBar({required this.menu, required this.notifier});

  final DailyMenu menu;
  final _MenuNotifier notifier;

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bocadooColors;
    final theme = Theme.of(context);
    final scheme = context.colorScheme;
    final published = widget.menu.isPublished;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _busy || published
              ? null
              : () => _run(widget.notifier.publish),
          icon: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : Icon(published
                  ? Icons.check_circle_outline
                  : Icons.send_outlined),
          label: Text(published ? 'Publicado' : 'Publicar'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed:
              _busy ? null : () => _run(widget.notifier.repeatYesterday),
          icon: const Icon(Icons.replay_outlined),
          label: const Text('Repetir ayer'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed:
              _busy ? null : () => _run(widget.notifier.markSoldOut),
          style: TextButton.styleFrom(
            foregroundColor: tokens.danger,
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.cancel_outlined),
          label: Text(
            'Se acabó',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: tokens.danger),
          ),
        ),
      ],
    );
  }
}

// ── Banner de error ──────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
