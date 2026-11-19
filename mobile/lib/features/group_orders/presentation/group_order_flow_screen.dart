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
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../customer/presentation/customer_controller.dart';
import '../../customer/presentation/customer_widgets.dart' show CustomerErrorView;
import '../../customer/presentation/social_widgets.dart';
import 'group_order_models.dart';

part 'group_order_steps.dart';

/// Flujo progresivo en 3 pasos de Pedido Grupal con máquina de estados estricta.
class GroupOrderFlowScreen extends ConsumerStatefulWidget {
  const GroupOrderFlowScreen({super.key, this.restaurantId});

  final String? restaurantId;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _copiedTimer?.cancel();
    _poller?.dispose();
    super.dispose();
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
    final rid = _restaurantId;
    if (rid != null) {
      unawaited(_hydrateRestaurantMenu(rid));
    }

    final active = ref.read(customerControllerProvider).state.activeTable;
    final activeRest = _restaurantFor(rid);
    final matchesActive = active != null &&
        (rid == null ||
            (activeRest != null && active.restaurantName == activeRest.name));

    if (matchesActive) {
      try {
        final existing = await ref
            .read(customerRepositoryProvider)
            .getSharedTable(active.id);
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

          if (now.isAfter(targetTime) && confirmed < party && !existing.onTheWay) {
            _transitionToExpired(existing);
          } else if (confirmed >= party || existing.onTheWay) {
            _status = GroupOrderStatus.confirmed;
          } else {
            _status = GroupOrderStatus.collecting;
            _startPolling();
          }
          setState(() => _loading = false);
          return;
        }
      } catch (_) {
        // Si no se pudo recuperar mesa previa, inicia limpio en Paso 1.
      }
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
      setState(() {
        _hydratedRestaurant = detail;
        _syncDefaultDishes(detail);
      });
    } catch (_) {}
  }

  void _syncDefaultDishes(Restaurant? r) {
    final soups = _soupOptions(r);
    final mains = _mainOptions(r);
    final drinks = _drinkOptions(r);
    _dishSelection = GroupOrderDishSelection(
      soup: soups.contains(_dishSelection.soup)
          ? _dishSelection.soup
          : soups.firstOrNull,
      main: mains.contains(_dishSelection.main)
          ? _dishSelection.main
          : mains.firstOrNull,
      drink: drinks.contains(_dishSelection.drink)
          ? _dishSelection.drink
          : drinks.firstOrNull,
    );
  }

  List<String> _soupOptions(Restaurant? r) {
    final fromMenu = r?.soups
            .where((m) => !m.isSoldOut)
            .map((m) => m.name)
            .toList() ??
        const <String>[];
    if (fromMenu.isNotEmpty) return fromMenu;
    return const ['Sopa del día', 'Consomé'];
  }

  List<String> _mainOptions(Restaurant? r) {
    final fromMenu = r?.mains
            .where((m) => !m.isSoldOut)
            .map((m) => m.name)
            .toList() ??
        const <String>[];
    if (fromMenu.isNotEmpty) return fromMenu;
    return const ['Plato fuerte del día', 'Opción Fit'];
  }

  List<String> _drinkOptions(Restaurant? r) {
    final fromMenu = r?.todayMenu
            .where(
              (m) =>
                  !m.isSoldOut &&
                  (m.category.toLowerCase().contains('bebida') ||
                      m.category.toLowerCase().contains('jugo')),
            )
            .map((m) => m.name)
            .toList() ??
        const <String>[];
    if (fromMenu.isNotEmpty) return fromMenu;
    return const ['Jugo del día', 'Limonada', 'Agua'];
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
    if (rid == null || !_isEstimatedTimeValid) return;

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
        takeaway: isFull,
        mode: _selectedMode,
      );
      if (!mounted) return;

      final synced = table.copyWith(
        partySize: _partySize,
        mode: _selectedMode,
        scheduledAt: _estimatedConsumptionTime,
        takeaway: isFull || table.takeaway,
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

    final confirmedCount = t.members.length.clamp(1, _partySize);
    final now = DateTime.now();

    if (now.isAfter(_estimatedConsumptionTime) && confirmedCount < _partySize) {
      _transitionToExpired(t);
      return;
    }

    if (confirmedCount >= _partySize && now.isBefore(_estimatedConsumptionTime)) {
      _transitionToConfirmed();
    }
  }

  void _transitionToConfirmed() {
    if (_status == GroupOrderStatus.confirmed) return;
    _poller?.stop();
    setState(() => _status = GroupOrderStatus.confirmed);
  }

  void _transitionToExpired(SharedTable t) {
    if (_status == GroupOrderStatus.expired) return;
    _poller?.stop();
    setState(() => _status = GroupOrderStatus.expired);
    // Libera el hold en segundo plano sin exponer el estado como "cancelada".
    unawaited(ref.read(customerControllerProvider).cancelSharedTable(t.id));
  }

  Future<void> _confirmEarlySend() async {
    final t = _table;
    if (t == null) return;
    final confirmedCount = t.members.length.clamp(1, _partySize);
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
    _transitionToConfirmed();
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

  void _shareWhatsApp(SharedTable t) {
    final text =
        '¡Vamos a almorzar juntos en ${t.restaurantName} a las ${t.time}! '
        'Elige tu plato y únete aquí: ${t.shareUrl} (código: ${t.shortId})';
    openExternal(
      context,
      whatsAppUri(text),
      failMessage: 'No se pudo abrir WhatsApp',
    );
  }

  Future<void> _copyLink(SharedTable t) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: t.shareUrl));
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

  List<({String name, int qty})> _consolidateDishes(SharedTable t) {
    final counts = <String, int>{};
    for (final m in t.members) {
      final dishName = m.isHost
          ? (_dishSelection.main ?? 'Almuerzo del día')
          : ((m.main ?? '').trim().isNotEmpty
              ? m.main!.trim()
              : 'Almuerzo del día');
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
    final hostLunches = _hostRemainingLunches(rid);
    final hasInsufficientLunches =
        _selectedMode == TableMode.hostPays && hostLunches < effectiveParty;
    final canSubmitStep1 =
        rid != null && _isEstimatedTimeValid && !hasInsufficientLunches;

    final t = _table;
    final stepNumber = switch (_status) {
      GroupOrderStatus.draft => 1,
      GroupOrderStatus.collecting => 2,
      GroupOrderStatus.confirmed => 3,
      GroupOrderStatus.expired || GroupOrderStatus.cancelled => 3,
    };

    final soups = _soupOptions(restaurant);
    final mains = _mainOptions(restaurant);
    final drinks = _drinkOptions(restaurant);
    final dishSelection = GroupOrderDishSelection(
      soup: _dishSelection.soup ?? soups.firstOrNull,
      main: _dishSelection.main ?? mains.firstOrNull,
      drink: _dishSelection.drink ?? drinks.firstOrNull,
    );

    final confirmedCount =
        t != null ? t.members.length.clamp(1, effectiveParty) : 1;
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
            onOpenGuestView: t != null
                ? () => context.push('/customer/mesa/${t.id}')
                : null,
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
                                selectedMode: _selectedMode,
                                onModeChanged: (m) =>
                                    setState(() => _selectedMode = m),
                                hostRemainingLunches: hostLunches,
                                hasInsufficientHostLunches:
                                    hasInsufficientLunches,
                                isFull: isFull,
                                soups: soups,
                                mains: mains,
                                drinks: drinks,
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
                                    table: t,
                                    totalParticipants: effectiveParty,
                                    confirmedCount: confirmedCount,
                                    remainingDuration: remaining,
                                    hostDishSummary: dishSelection.summary,
                                    copied: _copied,
                                    busy: _busy,
                                    onShareWhatsApp: () => _shareWhatsApp(t),
                                    onCopyLink: () => _copyLink(t),
                                    onCloseAndSendNow: _confirmEarlySend,
                                  ),
                            GroupOrderStatus.confirmed => t == null
                                ? const SocialLoading('Generando QR')
                                : _StepThreeConfirmedQrView(
                                    table: t,
                                    confirmedCount: confirmedCount,
                                    consolidatedDishes: _consolidateDishes(t),
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
