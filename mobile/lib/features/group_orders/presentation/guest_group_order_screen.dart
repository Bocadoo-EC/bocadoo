import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../customer/presentation/customer_controller.dart';
import '../../customer/presentation/customer_widgets.dart'
    show CustomerErrorView, formatMoney;
import '../../customer/presentation/social_widgets.dart';
import 'group_order_models.dart';
import 'group_order_simulation_provider.dart';
import 'widgets/daily_menu_accordion_selector.dart';

/// Selector compartido de menú diario + modalidad obligatoria (Paso 1 e Invitado).
class GroupDailyMenuSelector extends StatelessWidget {
  const GroupDailyMenuSelector({
    super.key,
    required this.dailyMenu,
    required this.selection,
    required this.onChanged,
    this.enabled = true,
    this.lockTakeaway = false,
  });

  final DailyMenu dailyMenu;
  final GroupOrderDishSelection selection;
  final ValueChanged<GroupOrderDishSelection> onChanged;
  final bool enabled;
  final bool lockTakeaway;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DailyMenuAccordionSelector(
          dailyMenu: dailyMenu,
          selection: selection,
          onChanged: onChanged,
          enabled: enabled,
        ),
        const SizedBox(height: 12),
        const SocialLabel('Modalidad de consumo'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SocialChoice(
                label: 'Para comer aquí',
                icon: Icons.restaurant_rounded,
                selected: !selection.takeaway,
                radius: AppTheme.buttonRadius,
                onTap: !enabled || lockTakeaway
                    ? null
                    : () => onChanged(selection.copyWith(takeaway: false)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SocialChoice(
                label:
                    'Para llevar (+${formatMoney(dailyMenu.takeawaySurcharge)})',
                icon: Icons.takeout_dining_outlined,
                selected: selection.takeaway,
                radius: AppTheme.buttonRadius,
                onTap: !enabled || lockTakeaway
                    ? null
                    : () => onChanged(selection.copyWith(takeaway: true)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// C7 · Vista "Ver como invitado": muestra la mesa bloqueada y el menú del día.
class GuestGroupOrderScreen extends ConsumerStatefulWidget {
  const GuestGroupOrderScreen({super.key, required this.tableId});

  final String tableId;

  @override
  ConsumerState<GuestGroupOrderScreen> createState() =>
      _GuestGroupOrderScreenState();
}

class _GuestGroupOrderScreenState extends ConsumerState<GuestGroupOrderScreen> {
  final _nameCtrl = TextEditingController();
  GroupOrderSession? _session;
  SharedTable? _remoteTable;
  DailyMenu? _menu;
  GroupOrderDishSelection _selection = const GroupOrderDishSelection();
  bool _loading = true;
  bool _failed = false;
  bool _submitting = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final sessionName = ref.read(sessionProvider).userName?.trim() ?? '';
    _nameCtrl.text = sessionName.isNotEmpty
        ? sessionName
        : (AppMode.useMock ? 'Invitado Prueba' : '');
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });

    final sim = ref.read(groupOrderSimulationProvider);
    final localSession = sim.sessionById(widget.tableId);
    if (localSession != null) {
      _session = localSession;
      _menu = localSession.dailyMenu;
      _selection = const GroupOrderDishSelection();
      setState(() => _loading = false);
      return;
    }

    try {
      final table = await ref
          .read(customerRepositoryProvider)
          .getSharedTable(widget.tableId);
      if (!mounted) return;
      if (table == null) {
        setState(() => _loading = false);
        return;
      }
      final rest = ref
          .read(customerControllerProvider)
          .state
          .restaurantById(table.restaurantId);
      final menu = rest != null
          ? DailyMenu.fromRestaurant(rest)
          : DailyMenu(
              restaurantId: table.restaurantId,
              restaurantName: table.restaurantName,
              soups: table.soups,
              mains: table.mains.map((m) => m.name).toList(),
              drinks: const ['Jugo del día', 'Limonada', 'Agua'],
              isPublished: table.soups.isNotEmpty || table.mains.isNotEmpty,
              takeawaySurcharge: table.takeawaySurcharge,
            );
      setState(() {
        _remoteTable = table;
        _menu = menu;
        _selection = const GroupOrderDishSelection();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _confirmAndJoin() async {
    final guestName = _nameCtrl.text.trim();
    if (guestName.isEmpty) {
      setState(() => _nameError = 'Escribe tu nombre.');
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final sim = ref.read(groupOrderSimulationProvider);

    try {
      if (_session != null) {
        sim.confirmGuestJoin(
          tableId: _session!.tableId,
          guestName: guestName,
          selection: _selection,
        );
      }

      if (_remoteTable != null || (_session != null && !AppMode.useMock)) {
        final repo = ref.read(customerRepositoryProvider);
        try {
          // Flujo Entrega C en 2 llamadas: 1) unirse, 2) PUT /v1/mis/mesas/{id}/seleccion.
          var updated = await repo.joinTable(
            _session?.tableId ?? _remoteTable!.id,
            name: guestName,
            soup: _selection.cleanSoup ?? '',
            main: _selection.main ?? '',
            takeaway: _selection.takeaway,
          );
          var rest = ref
              .read(customerControllerProvider)
              .state
              .restaurantById(updated.restaurantId);
          if (rest == null || rest.todayMenu.isEmpty) {
            rest = await repo.getRestaurantById(updated.restaurantId);
          }
          final lunchDishIds = _selection.resolveLunchDishIds(rest);
          if (lunchDishIds.isNotEmpty) {
            try {
              updated = await repo.updateTableSelection(
                updated.id,
                lunchDishIds: lunchDishIds,
              );
            } catch (_) {
              // Mantiene la unión confirmada si el backend aún no acepta selección para este caso.
            }
          }
          if (mounted) {
            ref.read(customerControllerProvider).syncTable(updated);
          }
        } on ApiException catch (e) {
          // Si ya es anfitrión probando su propia invitación en simulación, permite continuar la demo.
          if (_session == null) {
            rethrow;
          }
          if (e.status == 404 || e.status == 410 || e.status == 409) rethrow;
        }
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '¡Plato confirmado para $guestName! (${_selection.modalityLabel})',
          ),
        ),
      );
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/customer/pase');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'LOCAL_LLENO_SOLO_LLEVAR') {
        setState(() => _selection = _selection.copyWith(takeaway: true));
        messenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'El salón está lleno ahora. Activamos "Para llevar" para que puedas unirte.',
            ),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.userMessage),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Error al confirmar tu plato. Inténtalo de nuevo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/customer/pase');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final session = _session;
    final remote = _remoteTable;

    final hostName = session?.hostName ?? remote?.hostName ?? 'Anfitrión';
    final restaurantName =
        session?.restaurantName ?? remote?.restaurantName ?? 'Restaurante';
    final shortCode = session?.shortCode ?? remote?.shortId ?? '';
    final timeStr = session?.timeHhmm ?? remote?.time ?? '--:--';
    final notFound = !_loading && !_failed && session == null && remote == null;
    final isFrozen = session?.isOrderFrozen ?? false;
    final menu = _menu;
    final canConfirm =
        !_submitting && menu != null && _selection.isCompleteFor(menu);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Unirme a pedido grupal'),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const SocialLoading('Cargando invitación')
            : _failed
                ? CustomerErrorView(
                    title: 'Error al cargar mesa',
                    message: 'No pudimos cargar la invitación.',
                    onRetry: _load,
                  )
                : notFound
                    ? SocialEmpty(
                        icon: Icons.group_off_outlined,
                        title: 'Mesa no encontrada',
                        message: 'El enlace de la mesa expiró o fue cerrado.',
                        actionLabel: 'Ver locales',
                        onAction: () => context.go('/customer/restaurants'),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                        children: [
                          // 1. Identificador inmutable de la mesa (Read-Only, sin TextFormField)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: colors.outlineVariant),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Theme.of(context).scaffoldBackgroundColor,
                                  colors.primaryContainer.withValues(alpha: 0.55),
                                ],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.lock_outline_rounded,
                                      size: 16,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Identificador de la mesa',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: colors.primary,
                                        ),
                                      ),
                                    ),
                                    SocialBadge(
                                      label: '#$shortCode · $timeStr',
                                      background: colors.primaryContainer,
                                      foreground: colors.onPrimaryContainer,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Mesa de $hostName',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                    color: colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  restaurantName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                if (remote != null && remote.members.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  for (final m in remote.members)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        m.selection != null &&
                                                m.selection!.summary.isNotEmpty
                                            ? '• ${m.name}: ${m.selection!.summary}'
                                            : '• ${m.name}${m.isHost ? ' (Anfitrión)' : ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          if (isFrozen) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: colors.outlineVariant),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 18,
                                    color: colors.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Pedido cerrado · No admite modificaciones',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: colors.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),

                            // 2. Nombre del invitado (campo editable independiente)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: colors.outlineVariant),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SocialLabel('Tu nombre en la orden'),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _nameCtrl,
                                    enabled: !_submitting,
                                    textCapitalization: TextCapitalization.words,
                                    decoration: InputDecoration(
                                      hintText: 'Escribe tu nombre',
                                      isDense: true,
                                      errorText: _nameError,
                                    ),
                                    onChanged: (_) {
                                      if (_nameError != null) {
                                        setState(() => _nameError = null);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 3. Mismo selector del menú diario + modalidad obligatoria
                            const SocialLabel('Elige tu almuerzo de hoy'),
                            const SizedBox(height: 8),
                            if (menu != null)
                              GroupDailyMenuSelector(
                                dailyMenu: menu,
                                selection: _selection,
                                onChanged: (next) =>
                                    setState(() => _selection = next),
                                enabled: !_submitting,
                              ),
                            const SizedBox(height: 22),

                            // 4. CTA único
                            ElevatedButton(
                              onPressed: canConfirm ? _confirmAndJoin : null,
                              child: _submitting
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: colors.onPrimary,
                                      ),
                                    )
                                  : const Text(
                                      'Confirmar mi plato y unirme a la mesa',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ],
                      ),
      ),
    );
  }
}
