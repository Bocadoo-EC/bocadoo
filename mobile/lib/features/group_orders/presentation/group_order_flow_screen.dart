import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/contracts/qr_parser.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/polling.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../customer/presentation/customer_controller.dart';
import '../../customer/presentation/customer_widgets.dart' show CustomerErrorView;
import '../../customer/presentation/social_widgets.dart';
import 'group_order_models.dart';
import 'group_order_simulation_provider.dart';
import 'guest_group_order_screen.dart';

part 'group_order_steps.dart';

/// Flujo progresivo en 3 pasos de Pedido Grupal con máquina de estados estricta.
class GroupOrderFlowScreen extends ConsumerStatefulWidget {
  const GroupOrderFlowScreen({
    super.key,
    this.restaurantId,
    this.groupOrderId,
  });

  final String? restaurantId;
  final String? groupOrderId;

  @override
  ConsumerState<GroupOrderFlowScreen> createState() =>
      _GroupOrderFlowScreenState();
}

class _GroupOrderFlowScreenState extends ConsumerState<GroupOrderFlowScreen>
    with WidgetsBindingObserver {
  GroupOrderStatus _status = GroupOrderStatus.draft;
  String? _selectedRestaurantId;
  Restaurant? _hydratedRestaurant;
  SharedTable? _table;

  // Paso 1 (draft)
  int _partySize = 2;
  String _selectedTimeLabel = 'En 15 min';
  String? _customTimeLabel;
  late DateTime _estimatedConsumptionTime =
      DateTime.now().add(const Duration(minutes: 15));
  TableMode _selectedMode = TableMode.eachOwn;
  GroupOrderDishSelection _dishSelection = const GroupOrderDishSelection();

  // Ciclo de vida, timers y estado de red
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  bool _copied = false;
  String? _errorMsg;
  Timer? _countdownTimer;
  Timer? _copiedTimer;
  LifecyclePollingController? _poller;
  late final GroupOrderSimulationStore _simStore;

  String? get _restaurantId {
    final s = ref.read(customerControllerProvider).state;
    return widget.restaurantId ??
        _selectedRestaurantId ??
        _table?.restaurantId ??
        s.currentPass?.restaurantId ??
        (s.restaurants.length == 1 ? s.restaurants.first.id : null);
  }

  Restaurant? _restaurantFor(String? id) {
    if (id == null) return null;
    if (_hydratedRestaurant?.id == id) return _hydratedRestaurant;
    return ref.read(customerControllerProvider).state.restaurantById(id);
  }

  bool _isRestaurantFull(String? id) {
    if (id == null) return false;
    return ref.read(restaurantPublicStatusProvider(id)).isFull;
  }

  DailyMenu _dailyMenuFor(Restaurant? r) {
    final s = ref.read(customerControllerProvider).state;
    final override =
        r != null ? s.todayMenuAvailabilityByRest[r.id] : null;
    return DailyMenu.fromRestaurant(r, availabilityOverride: override);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _simStore = ref.read(groupOrderSimulationProvider);
    _simStore.addListener(_onSimulationUpdated);
    _startTicker();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _simStore.removeListener(_onSimulationUpdated);
    _countdownTimer?.cancel();
    _copiedTimer?.cancel();
    _poller?.dispose();
    super.dispose();
  }

  void _onSimulationUpdated() {
    if (!mounted || _table == null) return;
    final session = _simStore.sessionById(_table!.id);
    if (session == null) return;
    setState(() {
      _status = session.status;
      _partySize = session.totalParticipants;
      _selectedMode = session.mode;
      _estimatedConsumptionTime = session.estimatedConsumptionTime;
      if (session.status == GroupOrderStatus.confirmed) {
        _poller?.stop();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluateTransitions();
      if (_status == GroupOrderStatus.collecting && _table != null) {
        unawaited(_pollTable());
      }
    }
  }

  void _startTicker() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_status == GroupOrderStatus.collecting) {
        _evaluateTransitions();
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _bootstrap() async {
    final targetGroupId = widget.groupOrderId;
    final requestedRid = widget.restaurantId;
    if (requestedRid != null) {
      unawaited(_hydrateRestaurantMenu(requestedRid));
    }

    // 1. Revisa primero por groupOrderId explícito o sesión activa en el simulador.
    final simSession = targetGroupId != null
        ? (_simStore.sessionById(targetGroupId) ?? _simStore.activeSession)
        : _simStore.activeSession;
    final matchesSim = simSession != null &&
        simSession.status != GroupOrderStatus.cancelled &&
        (targetGroupId != null ||
            requestedRid == null ||
            simSession.restaurantId == requestedRid);
    if (matchesSim) {
      _selectedRestaurantId = simSession.restaurantId;
      _partySize = simSession.totalParticipants;
      _selectedMode = simSession.mode;
      _estimatedConsumptionTime = simSession.estimatedConsumptionTime;
      _table = SharedTable(
        id: simSession.tableId,
        restaurantId: simSession.restaurantId,
        restaurantName: simSession.restaurantName,
        hostName: simSession.hostName,
        time: simSession.timeHhmm,
        mode: simSession.mode,
        members: [
          for (final p in simSession.participants)
            TableMember(
              id: p.id,
              name: p.name,
              isHost: p.isHost,
              soup: p.selection.soup,
              main: p.selection.main,
              takeaway: p.selection.takeaway,
            ),
        ],
        onTheWay: simSession.status == GroupOrderStatus.confirmed,
        partySize: simSession.totalParticipants,
        scheduledAt: simSession.estimatedConsumptionTime,
        occupancyLabel: '',
        soups: simSession.dailyMenu.soups,
        mains: const [],
        qrPayload: simSession.qrPayload,
        shareUrl: simSession.shareUrl,
      );
      _status = simSession.status;
      unawaited(_hydrateRestaurantMenu(simSession.restaurantId));
      if (_status == GroupOrderStatus.collecting) {
        _evaluateTransitions();
        if (_status == GroupOrderStatus.collecting) _startPolling();
      }
      if (mounted) setState(() => _loading = false);
      return;
    }

    final rid = _restaurantId;
    if (rid != null && requestedRid == null) {
      unawaited(_hydrateRestaurantMenu(rid));
    }

    // 2. Recupera mesa activa desde repositorio remoto si existe.
    final active = ref.read(customerControllerProvider).state.activeTable;
    final activeRest = _restaurantFor(requestedRid);
    final lookupTableId = targetGroupId ?? active?.id;
    final matchesActive = lookupTableId != null &&
        (targetGroupId != null ||
            requestedRid == null ||
            (active != null &&
                activeRest != null &&
                active.restaurantName == activeRest.name));

    if (matchesActive) {
      try {
        final existing = await ref
            .read(customerRepositoryProvider)
            .getSharedTable(lookupTableId);
        if (!mounted) return;
        if (existing != null) {
          final targetTime =
              existing.scheduledAt ?? _dateTimeFromHhmm(existing.time);
          final party = existing.effectivePartySize;
          final confirmed = existing.members.length.clamp(1, party);
          final now = DateTime.now();

          _table = existing;
          _partySize = party;
          _selectedMode = existing.mode;
          _estimatedConsumptionTime = targetTime;
          _selectedRestaurantId = existing.restaurantId;
          unawaited(_hydrateRestaurantMenu(existing.restaurantId));

          final menu = _dailyMenuFor(
            _restaurantFor(existing.restaurantId),
          );
          final hostName = existing.hostName.isNotEmpty
              ? existing.hostName
              : (ref.read(sessionProvider).userName ?? 'Anfitrión');

          _simStore.startCollecting(
            tableId: existing.id,
            shortCode: existing.shortId,
            restaurantId: existing.restaurantId,
            restaurantName: existing.restaurantName,
            hostName: hostName,
            totalParticipants: party,
            estimatedConsumptionTime: targetTime,
            timeHhmm: existing.time,
            mode: existing.mode,
            dailyMenu: menu,
            hostSelection: _dishSelection,
            qrPayload: existing.qrPayload,
          );
          _simStore.syncRemoteMembers(existing.id, existing.members);

          if (now.isAfter(targetTime) && confirmed < party && !existing.onTheWay) {
            _transitionToExpired(existing);
          } else if (confirmed >= party || existing.onTheWay) {
            _simStore.confirmNow(existing.id);
            _status = GroupOrderStatus.confirmed;
          } else {
            _status = GroupOrderStatus.collecting;
            _startPolling();
          }
          setState(() => _loading = false);
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _status = GroupOrderStatus.draft;
        _loading = false;
      });
    }
  }

  Future<void> _hydrateRestaurantMenu(String rid) async {
    try {
      final detail =
          await ref.read(customerRepositoryProvider).getRestaurantById(rid);
      if (!mounted || detail == null) return;
      ref.read(customerControllerProvider).syncRestaurantSummary(detail);
      setState(() {
        _hydratedRestaurant = detail;
        _syncDefaultDishes(detail);
      });
    } catch (_) {}
  }

  void _syncDefaultDishes(Restaurant? r) {
    final menu = _dailyMenuFor(r);
    final isFull = _isRestaurantFull(r?.id);
    _dishSelection = GroupOrderDishSelection(
      soup: menu.soups.contains(_dishSelection.soup)
          ? _dishSelection.soup
          : menu.soups.firstOrNull,
      main: menu.mains.contains(_dishSelection.main)
          ? _dishSelection.main
          : menu.mains.firstOrNull,
      drink: menu.drinks.contains(_dishSelection.drink)
          ? _dishSelection.drink
          : menu.drinks.firstOrNull,
      takeaway: isFull ? true : _dishSelection.takeaway,
    );
  }

  DateTime _dateTimeFromHhmm(String hhmm) {
    final parts = hhmm.split(':');
    final now = DateTime.now();
    if (parts.length != 2) return now.add(const Duration(minutes: 15));
    final h = int.tryParse(parts[0]) ?? now.hour;
    final m = int.tryParse(parts[1]) ?? now.minute;
    return DateTime(now.year, now.month, now.day, h, m);
  }

  String _formatHhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  bool get _isEstimatedTimeValid => _estimatedConsumptionTime
      .isAfter(DateTime.now().add(const Duration(minutes: 10)));

  int _hostRemainingLunches(String? rid) {
    final s = ref.read(customerControllerProvider).state;
    if (rid != null) {
      final pass = s.passFor(rid);
      if (pass != null) return pass.remainingLunches;
    }
    return s.currentPass?.remainingLunches ?? 0;
  }

  void _selectQuickMinutes(int minutes) {
    setState(() {
      _selectedTimeLabel = minutes == 15 ? 'En 15 min' : 'En 30 min';
      _customTimeLabel = null;
      _estimatedConsumptionTime = DateTime.now().add(Duration(minutes: minutes));
    });
  }

  Future<void> _pickCustomTime(Restaurant? r) async {
    final schedule = r?.schedule ?? '12:00 - 15:30';
    final now = DateTime.now();
    final initial = TimeOfDay.fromDateTime(now.add(const Duration(minutes: 25)));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Hora estimada ($schedule)',
    );
    if (picked == null || !mounted) return;
    final candidate =
        DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (!candidate.isAfter(now.add(const Duration(minutes: 10)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Elige una hora al menos 10 minutos mayor a la hora actual.',
          ),
        ),
      );
      return;
    }
    final formatted = _formatHhmm(candidate);
    setState(() {
      _customTimeLabel = formatted;
      _selectedTimeLabel = 'custom';
      _estimatedConsumptionTime = candidate;
    });
  }

  Future<void> _createGroupAndMoveToLobby() async {
    final rid = _restaurantId;
    final restaurant = _restaurantFor(rid);
    final menu = _dailyMenuFor(restaurant);
    if (rid == null || !_isEstimatedTimeValid || !menu.hasActiveDishes) return;

    final hostLunches = _hostRemainingLunches(rid);
    if (_selectedMode == TableMode.hostPays && hostLunches < _partySize) {
      return;
    }

    setState(() {
      _busy = true;
      _failed = false;
      _errorMsg = null;
    });

    try {
      final repo = ref.read(customerRepositoryProvider);
      final isFull = _isRestaurantFull(rid);
      final targetHhmm = _formatHhmm(_estimatedConsumptionTime);
      final table = await repo.openSharedTable(
        restaurantId: rid,
        time: targetHhmm,
        partySize: _partySize,
        takeaway: isFull || _dishSelection.takeaway,
        mode: _selectedMode,
      );
      if (!mounted) return;

      final hostName =
          (ref.read(sessionProvider).userName ?? table.hostName).trim();
      final effectiveHost = hostName.isNotEmpty ? hostName : 'Anfitrión';
      final synced = table.copyWith(
        partySize: _partySize,
        mode: _selectedMode,
        scheduledAt: _estimatedConsumptionTime,
        takeaway: isFull || _dishSelection.takeaway,
      );

      _simStore.startCollecting(
        tableId: synced.id,
        shortCode: synced.shortId,
        restaurantId: synced.restaurantId,
        restaurantName: synced.restaurantName,
        hostName: effectiveHost,
        totalParticipants: _partySize,
        estimatedConsumptionTime: _estimatedConsumptionTime,
        timeHhmm: synced.time,
        mode: _selectedMode,
        dailyMenu: menu,
        hostSelection: _dishSelection.copyWith(
          takeaway: isFull || _dishSelection.takeaway,
        ),
        qrPayload: synced.qrPayload,
      );
      ref.read(customerControllerProvider).syncTable(synced);

      setState(() {
        _table = synced;
        _status = GroupOrderStatus.collecting;
        _busy = false;
      });
      _startPolling();
      _evaluateTransitions();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _errorMsg = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _errorMsg = 'No pudimos crear la mesa grupal. Inténtalo de nuevo.';
      });
    }
  }

  void _startPolling() {
    _poller ??= LifecyclePollingController(
      interval: const Duration(seconds: 8),
      onTick: _pollTable,
    );
    if (!_poller!.isRunning) {
      try {
        _poller!.start();
      } catch (_) {}
    }
  }

  Future<void> _pollTable() async {
    final current = _table;
    if (current == null || !mounted) return;
    try {
      final latest = await ref
          .read(customerRepositoryProvider)
          .getSharedTable(current.id);
      if (!mounted) return;
      if (latest == null) {
        _poller?.stop();
        _simStore.clearActive();
        await ref.read(customerControllerProvider).refreshLive();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('La mesa fue cerrada en caja'),
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return;
      }
      _simStore.syncRemoteMembers(current.id, latest.members);
      final merged = latest.copyWith(
        partySize: _partySize,
        scheduledAt: _estimatedConsumptionTime,
      );
      ref.read(customerControllerProvider).syncTable(merged);
      setState(() => _table = merged);
      _evaluateTransitions();
    } catch (_) {}
  }

  void _evaluateTransitions() {
    if (_status != GroupOrderStatus.collecting) return;
    final t = _table;
    if (t == null) return;

    final session = _simStore.sessionById(t.id);
    final confirmedCount =
        session?.confirmedCount ?? t.members.length.clamp(1, _partySize);
    final now = DateTime.now();

    if (now.isAfter(_estimatedConsumptionTime) && confirmedCount < _partySize) {
      _transitionToExpired(t);
      return;
    }

    if (confirmedCount >= _partySize && now.isBefore(_estimatedConsumptionTime)) {
      _transitionToConfirmed(t.id);
    }
  }

  void _transitionToConfirmed(String tableId) {
    if (_status == GroupOrderStatus.confirmed) return;
    _poller?.stop();
    _simStore.confirmNow(tableId);
    setState(() => _status = GroupOrderStatus.confirmed);
  }

  void _transitionToExpired(SharedTable t) {
    if (_status == GroupOrderStatus.expired) return;
    _poller?.stop();
    _simStore.markExpired(t.id);
    setState(() => _status = GroupOrderStatus.expired);
    unawaited(ref.read(customerControllerProvider).cancelSharedTable(t.id));
  }

  Future<void> _confirmEarlySend() async {
    final t = _table;
    if (t == null) return;
    final session = _simStore.sessionById(t.id);
    final confirmedCount =
        session?.confirmedCount ?? t.members.length.clamp(1, _partySize);
    if (confirmedCount < 2) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar mesa y enviar ahora?'),
        content: Text(
          'Se enviará la comanda con los $confirmedCount comensales que ya confirmaron su plato y se generará el QR único de mesa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir esperando'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enviar pedido'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    _transitionToConfirmed(t.id);
  }

  Future<void> _cancelTable(SharedTable t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar mesa?'),
        content: const Text(
          'Se cerrará esta mesa compartida y tus amigos ya no podrán unirse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir en la mesa'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Cancelar mesa',
              style: TextStyle(color: ctx.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    final controller = ref.read(customerControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.cancelSharedTable(t.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            controller.lastActionError ?? 'No pudimos cancelar la mesa.',
          ),
        ),
      );
      return;
    }
    _poller?.stop();
    _simStore.markCancelled(t.id);
    _status = GroupOrderStatus.cancelled;
    messenger.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Mesa cancelada'),
      ),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _resetToDraft() {
    _poller?.stop();
    _simStore.clearActive();
    setState(() {
      _table = null;
      _status = GroupOrderStatus.draft;
      _failed = false;
      _errorMsg = null;
      _selectedTimeLabel = 'En 15 min';
      _customTimeLabel = null;
      _estimatedConsumptionTime =
          DateTime.now().add(const Duration(minutes: 15));
    });
  }

  bool _canCancelTable(SharedTable t) {
    final st = t.status.toUpperCase();
    final isInitial = st == 'ABIERTA' || st == 'EN_ESPERA';
    if (!isInitial || t.onTheWay) return false;
    final arrivalUtc = t.scheduledAt?.toUtc() ?? EcuadorTime.todayAtUtc(t.time);
    return arrivalUtc.difference(DateTime.now().toUtc()) >=
        const Duration(minutes: 15);
  }

  Future<void> _shareWhatsApp(SharedTable t, GroupOrderSession? session) async {
    final hostName = session?.hostName ?? t.hostName;
    final message = buildGroupWhatsAppMessage(
      hostName: hostName,
      restaurantName: t.restaurantName,
      tableCode: t.shortId,
    );
    final waUri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
    await openExternal(
      context,
      waUri,
      failMessage: 'WhatsApp no disponible; mensaje copiado al portapapeles.',
    );
    await Clipboard.setData(ClipboardData(text: message));
  }

  Future<void> _copyLink(SharedTable t) async {
    final messenger = ScaffoldMessenger.of(context);
    final link = buildGroupInviteLink(t.shortId);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    setState(() => _copied = true);
    messenger.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Link copiado'),
      ),
    );
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _openGuestPreview(SharedTable t) async {
    await context.push('/customer/mesa/${t.id}');
    if (!mounted) return;
    _onSimulationUpdated();
    _evaluateTransitions();
  }

  Future<void> _editParticipantDishInLobby(
    SharedTable t,
    DailyMenu menu,
    GroupOrderParticipant participant,
  ) async {
    final session = _simStore.sessionById(t.id);
    if (session?.isOrderFrozen == true) return;
    var draft = participant.selection;

    final saved = await showModalBottomSheet<GroupOrderDishSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cambiar elección · ${participant.name}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: ctx.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GroupDailyMenuSelector(
                    dailyMenu: menu,
                    selection: draft,
                    onChanged: (next) => setModalState(() => draft = next),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(draft),
                    child: const Text('Guardar elección'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == null || !mounted) return;
    _simStore.updateDish(
      tableId: t.id,
      participantId: participant.id,
      selection: saved,
    );
    if (participant.isHost) {
      setState(() => _dishSelection = saved);
    }
  }

  Future<void> _editTableConfigInLobby(
    SharedTable t,
    GroupOrderSession? session,
    Restaurant? restaurant,
  ) async {
    if (session?.isOrderFrozen == true) return;
    final minAllowed =
        (session?.participants.length ?? t.members.length).clamp(2, 12);
    final maxSeats = (restaurant?.seats ?? 12).clamp(minAllowed, 12);

    var draftParty = _partySize.clamp(minAllowed, maxSeats);
    var draftMode = _selectedMode;
    var draftTime = _estimatedConsumptionTime;

    final saved = await showModalBottomSheet<
        ({int party, TableMode mode, DateTime time})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final colors = ctx.colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Editar datos de mesa',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Personas (mín. $minAllowed)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: draftParty > minAllowed
                            ? () => setModalState(() => draftParty--)
                            : null,
                        icon: const Icon(Icons.remove_rounded, size: 18),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$draftParty',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: draftParty < maxSeats
                            ? () => setModalState(() => draftParty++)
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SocialLabel('Hora estimada de consumo'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('En 15 min'),
                        selected: false,
                        onSelected: (_) => setModalState(
                          () => draftTime =
                              DateTime.now().add(const Duration(minutes: 15)),
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('En 30 min'),
                        selected: false,
                        onSelected: (_) => setModalState(
                          () => draftTime =
                              DateTime.now().add(const Duration(minutes: 30)),
                        ),
                      ),
                      ChoiceChip(
                        label: Text('Hora (${_formatHhmm(draftTime)})'),
                        selected: true,
                        onSelected: (_) async {
                          final now = DateTime.now();
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(draftTime),
                          );
                          if (picked == null) return;
                          final next = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            picked.hour,
                            picked.minute,
                          );
                          if (next.isAfter(now.add(const Duration(minutes: 10)))) {
                            setModalState(() => draftTime = next);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SocialLabel('Modalidad de pago'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _PaymentModeCard(
                          title: 'Cada quien lo suyo',
                          hint: 'Cada amigo paga lo suyo.',
                          selected: draftMode == TableMode.eachOwn,
                          onTap: () => setModalState(
                            () => draftMode = TableMode.eachOwn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (ctx) {
                            final pass = ref
                                .read(customerControllerProvider)
                                .state
                                .passFor(t.restaurantId);
                            final canHostInvite = pass != null &&
                                !pass.isExpired &&
                                pass.remainingLunches >= draftParty;
                            return _PaymentModeCard(
                              title: 'Yo invito la mesa',
                              hint: pass == null || pass.isExpired
                                  ? 'Requiere plan prepagado activo.'
                                  : '$draftParty almuerzos de mi plan (${pass.remainingLunches} disp.).',
                              disabled: !canHostInvite,
                              disabledBadge: pass == null || pass.isExpired
                                  ? 'Primero adquiere un plan'
                                  : (!canHostInvite ? 'Saldo insuficiente' : null),
                              selected:
                                  canHostInvite && draftMode == TableMode.hostPays,
                              onTap: canHostInvite
                                  ? () => setModalState(
                                        () => draftMode = TableMode.hostPays,
                                      )
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(
                      (party: draftParty, mode: draftMode, time: draftTime),
                    ),
                    child: const Text('Guardar cambios'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (saved == null || !mounted) return;
    _simStore.updateTableConfig(
      tableId: t.id,
      totalParticipants: saved.party,
      estimatedConsumptionTime: saved.time,
      timeHhmm: _formatHhmm(saved.time),
      mode: saved.mode,
    );
  }

  List<({String name, int qty})> _consolidateDishes(
    List<GroupOrderParticipant> participants,
  ) {
    final counts = <String, int>{};
    for (final p in participants) {
      final dishName = (p.selection.main ?? '').trim().isNotEmpty
          ? p.selection.main!.trim()
          : 'Almuerzo del día';
      counts[dishName] = (counts[dishName] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      counts[_dishSelection.main ?? 'Almuerzo del día'] = 1;
    }
    return [
      for (final e in counts.entries) (name: e.key, qty: e.value),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rid = _restaurantId;
    final restaurant = _restaurantFor(rid);
    final maxSeats = (restaurant?.seats ?? 12).clamp(2, 12);
    final effectiveParty = _partySize.clamp(2, maxSeats);
    final isFull = rid != null && ref.watch(restaurantPublicStatusProvider(rid)).isFull;
    final activePassForRest = rid != null
        ? ref.read(customerControllerProvider).state.passFor(rid)
        : null;
    final hasActivePlanForRestaurant = activePassForRest != null &&
        !activePassForRest.isExpired &&
        activePassForRest.remainingLunches > 0;
    final hostLunches = activePassForRest?.remainingLunches ?? 0;
    final effectiveMode = !hasActivePlanForRestaurant && _selectedMode == TableMode.hostPays
        ? TableMode.eachOwn
        : _selectedMode;
    final hasInsufficientLunches =
        effectiveMode == TableMode.hostPays && hostLunches < effectiveParty;
    final dailyMenu = _dailyMenuFor(restaurant);

    final canSubmitStep1 = rid != null &&
        _isEstimatedTimeValid &&
        !hasInsufficientLunches &&
        dailyMenu.hasActiveDishes;

    final dishSelection = GroupOrderDishSelection(
      soup: _dishSelection.soup ?? dailyMenu.soups.firstOrNull,
      main: _dishSelection.main ?? dailyMenu.mains.firstOrNull,
      drink: _dishSelection.drink ?? dailyMenu.drinks.firstOrNull,
      takeaway: isFull ? true : _dishSelection.takeaway,
    );

    final t = _table;
    final simSession = t != null ? _simStore.sessionById(t.id) : null;
    final participants = simSession?.participants ??
        [
          GroupOrderParticipant(
            id: 'host',
            name: (ref.read(sessionProvider).userName ?? t?.hostName ?? 'Anfitrión'),
            isHost: true,
            selection: dishSelection,
          ),
        ];

    final stepNumber = switch (_status) {
      GroupOrderStatus.draft => 1,
      GroupOrderStatus.collecting => 2,
      GroupOrderStatus.confirmed => 3,
      GroupOrderStatus.expired || GroupOrderStatus.cancelled => 3,
    };

    final remaining = _estimatedConsumptionTime.difference(DateTime.now());

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepProgressHeader(
            restaurantName:
                t?.restaurantName ?? restaurant?.name ?? 'Selecciona restaurante',
            stepNumber: stepNumber,
            isExpired: _status == GroupOrderStatus.expired,
            showOverflowMenu: _status == GroupOrderStatus.collecting && t != null,
            onOpenGuestView: t != null ? () => _openGuestPreview(t) : null,
            onCancelTable: t != null && _canCancelTable(t)
                ? () => _cancelTable(t)
                : null,
          ),
          Expanded(
            child: _loading
                ? const SocialLoading('Preparando tu pedido grupal')
                : rid == null && t == null
                    ? _RestaurantPickerView(
                        restaurants:
                            ref.read(customerControllerProvider).state.restaurants,
                        onSelect: (id) {
                          setState(() => _selectedRestaurantId = id);
                          unawaited(_hydrateRestaurantMenu(id));
                        },
                      )
                    : _failed
                        ? CustomerErrorView(
                            title: 'Error al crear pedido grupal',
                            message:
                                _errorMsg ?? 'No pudimos preparar tu pedido grupal.',
                            onRetry: _createGroupAndMoveToLobby,
                          )
                        : switch (_status) {
                            GroupOrderStatus.draft => _StepOneConfigView(
                                partySize: effectiveParty,
                                minSeats: 2,
                                maxSeats: maxSeats,
                                onPartySizeChanged: (next) =>
                                    setState(() => _partySize = next),
                                selectedTimeLabel: _selectedTimeLabel,
                                customTimeLabel: _customTimeLabel,
                                estimatedTimeHhmm:
                                    _formatHhmm(_estimatedConsumptionTime),
                                isTimeValid: _isEstimatedTimeValid,
                                onSelectQuickMinutes: _selectQuickMinutes,
                                onPickCustomTime: () => _pickCustomTime(restaurant),
                                selectedMode: effectiveMode,
                                onModeChanged: (m) =>
                                    setState(() => _selectedMode = m),
                                hasActivePlanForRestaurant:
                                    hasActivePlanForRestaurant,
                                onBlockedHostPaysTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      content: Text(
                                        'Necesitas tener un plan prepagado activo en este restaurante para invitar la mesa.',
                                      ),
                                    ),
                                  );
                                },
                                hostRemainingLunches: hostLunches,
                                hasInsufficientHostLunches:
                                    hasInsufficientLunches,
                                isFull: isFull,
                                dailyMenu: dailyMenu,
                                dishSelection: dishSelection,
                                onDishChanged: (d) =>
                                    setState(() => _dishSelection = d),
                                busy: _busy,
                                canSubmit: canSubmitStep1,
                                onSubmit: _createGroupAndMoveToLobby,
                              ),
                            GroupOrderStatus.collecting => t == null
                                ? const SocialLoading('Sincronizando mesa')
                                : _StepTwoLobbyView(
                                    totalParticipants: effectiveParty,
                                    participants: participants,
                                    remainingDuration: remaining,
                                    copied: _copied,
                                    busy: _busy,
                                    onShareWhatsApp: () =>
                                        _shareWhatsApp(t, simSession),
                                    onCopyLink: () => _copyLink(t),
                                    onOpenGuestPreview: () =>
                                        _openGuestPreview(t),
                                    onEditTableConfig: () =>
                                        _editTableConfigInLobby(
                                      t,
                                      simSession,
                                      restaurant,
                                    ),
                                    onEditParticipantDish: (participant) =>
                                        _editParticipantDishInLobby(
                                      t,
                                      dailyMenu,
                                      participant,
                                    ),
                                    onCloseAndSendNow: _confirmEarlySend,
                                  ),
                            GroupOrderStatus.confirmed => t == null
                                ? const SocialLoading('Generando QR')
                                : _StepThreeConfirmedQrView(
                                    table: t,
                                    participants: participants,
                                    consolidatedDishes:
                                        _consolidateDishes(participants),
                                    canCancel: _canCancelTable(t),
                                    busy: _busy,
                                    onDone: () {
                                      if (Navigator.of(context).canPop()) {
                                        Navigator.of(context).pop();
                                      }
                                      context.go('/customer/pase');
                                    },
                                    onCancelTable: () => _cancelTable(t),
                                  ),
                            GroupOrderStatus.expired ||
                            GroupOrderStatus.cancelled =>
                              _ExpiredOrderView(
                                limitTimeHhmm:
                                    _formatHhmm(_estimatedConsumptionTime),
                                onCreateNew: _resetToDraft,
                              ),
                          },
          ),
        ],
      ),
    );
  }
}
