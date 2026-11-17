import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/polling.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart' show CustomerErrorView;
import 'social_widgets.dart';

const _times = ['12:30', '13:00', '13:30', '14:00'];

/// C9 · Mesa con amigos: un QR de caja para toda la mesa e invitación por WhatsApp.
class TableSheet extends ConsumerStatefulWidget {
  const TableSheet({super.key, this.restaurantId});

  /// Local de la mesa. Sin él se usa el del pase en pantalla.
  final String? restaurantId;

  @override
  ConsumerState<TableSheet> createState() => _TableSheetState();
}

class _TableSheetState extends ConsumerState<TableSheet> {
  late String _time = ref.read(customerControllerProvider).state.activeTable?.time ?? '13:00';
  String? _selectedRestaurantId;
  SharedTable? _table;
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;
  bool _copied = false;
  String? _errorMsg;
  Timer? _copiedTimer;
  LifecyclePollingController? _poller;

  String? get _restaurantId {
    final s = ref.read(customerControllerProvider).state;
    return widget.restaurantId ??
        _selectedRestaurantId ??
        s.activeTable?.restaurantId ??
        s.currentPass?.restaurantId ??
        (s.restaurants.length == 1 ? s.restaurants.first.id : null);
  }

  @override
  void initState() {
    super.initState();
    if (_restaurantId != null) {
      _open();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _poller?.dispose();
    super.dispose();
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
      ref.read(customerControllerProvider).syncTable(latest);
      setState(() => _table = latest);
    } catch (_) {}
  }

  bool _isPastSlot(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return false;
    return EcuadorTime.todayAtUtc(hhmm).isBefore(DateTime.now().toUtc());
  }

  Future<void> _open() async {
    final restaurantId = _restaurantId;
    if (restaurantId == null) {
      setState(() {
        _loading = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
      _errorMsg = null;
    });
    try {
      final repo = ref.read(customerRepositoryProvider);
      final active = ref.read(customerControllerProvider).state.activeTable;
      SharedTable? table;
      if (active != null &&
          (widget.restaurantId == null || _table == null) &&
          active.time == _time) {
        table = await repo.getSharedTable(active.id);
      }
      table ??= await repo.openSharedTable(
        restaurantId: restaurantId,
        time: _time,
      );
      if (!mounted) return;
      ref.read(customerControllerProvider).syncTable(table);
      setState(() {
        _table = table;
        _time = table!.time;
        _loading = false;
      });
      _startPolling();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _errorMsg = e.userMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _errorMsg = 'No pudimos preparar tu mesa.';
        });
      }
    }
  }

  Future<void> _run(Future<SharedTable> Function() action, {String? done}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final table = await action();
      if (!mounted) return;
      ref.read(customerControllerProvider).syncTable(table);
      setState(() => _table = table);
      if (done != null) {
        messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(done)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(e.userMessage),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('No se pudo actualizar la mesa. Inténtalo de nuevo.'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invite(SharedTable t) {
    final text = '¡Vamos a almorzar juntos en ${t.restaurantName} a las ${t.time}! '
        'Únete a nuestra mesa: ${t.shareUrl} (código: ${t.id})';
    openExternal(context, whatsAppUri(text), failMessage: 'No se pudo abrir WhatsApp');
  }

  Future<void> _copy(SharedTable t) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: t.shareUrl));
    if (!mounted) return;
    setState(() => _copied = true);
    messenger.showSnackBar(
      const SnackBar(behavior: SnackBarBehavior.floating, content: Text('¡Enlace copiado al portapapeles!')),
    );
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final repo = ref.read(customerRepositoryProvider);
    final t = _table;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Mesa con amigos',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.onSurface)),
        ),
        Expanded(
          child: _loading && t == null
              ? const SocialLoading('Preparando tu mesa')
              : _restaurantId == null && t == null
                  ? _RestaurantPicker(
                      restaurants: ref.read(customerControllerProvider).state.restaurants,
                      onSelect: (id) {
                        setState(() => _selectedRestaurantId = id);
                        _open();
                      },
                    )
                  : _failed || t == null
                      ? CustomerErrorView(
                          title: 'Error al crear mesa',
                          message: _errorMsg ?? 'No pudimos preparar tu mesa.',
                          onRetry: _open,
                        )
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                      _LocalHeader(table: t),
                      const SizedBox(height: 16),
                      const SocialLabel('Hora de encuentro'),
                      const SizedBox(height: 8),
                      Row(children: [
                        for (final time in _times) ...[
                          if (time != _times.first) const SizedBox(width: 8),
                          Expanded(
                            child: SocialChoice(
                              label: time,
                              selected: _time == time,
                              radius: AppTheme.buttonRadius,
                              onTap: _busy ||
                                      _loading ||
                                      (!AppMode.useMock &&
                                          _times.any((slot) => !_isPastSlot(slot)) &&
                                          _isPastSlot(time))
                                  ? null
                                  : () {
                                      setState(() => _time = time);
                                      _open();
                                    },
                            ),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 16),
                      _QrCard(table: t),
                      const SizedBox(height: 14),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: _ModeOption(
                            title: 'Cada quien lo suyo',
                            hint: 'Cada amigo con plan descuenta el suyo.',
                            selected: t.mode == TableMode.eachOwn,
                            onTap: _busy || !ApiCapabilities.sharedTableModeChange
                                ? null
                                : () => _run(() => repo.setTableMode(t.id, TableMode.eachOwn)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModeOption(
                            title: 'Yo invito la mesa',
                            hint: 'Se descuentan de mi plan y gano un sello por cada uno.',
                            selected: t.mode == TableMode.hostPays,
                            onTap: _busy || !ApiCapabilities.sharedTableModeChange
                                ? null
                                : () => _run(() => repo.setTableMode(t.id, TableMode.hostPays)),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: compactButtonStyle(context),
                            onPressed: () => _invite(t),
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text('Invitar por WhatsApp', maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: compactButtonStyle(context),
                            onPressed: () => _copy(t),
                            icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                            label: Text(_copied ? 'Copiado' : 'Copiar link'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => context.push('/customer/mesa/${t.id}'),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Ver la invitación como invitado'),
                      ),
                      Divider(height: 24, color: colors.outlineVariant),
                      _Members(table: t),
                      if (ApiCapabilities.sharedTableNotifyKitchen && !t.onTheWay) ...[
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                    () => repo.notifyKitchen(t.id),
                                    done: '¡Avisado a cocina! El restaurante sabe que van en camino.',
                                  ),
                          child: Text('Avisar a cocina: ¡Vamos ${t.members.length} en camino!',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ]),
        ),
      ]),
    );
  }
}

class _LocalHeader extends StatelessWidget {
  const _LocalHeader({required this.table});

  final SharedTable table;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(children: [
        SocialBadge(
          label: 'Almuerzo compartido',
          icon: Icons.restaurant_rounded,
          background: colors.primaryContainer,
          foreground: colors.primary,
        ),
        const SizedBox(height: 8),
        Text(table.restaurantName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
        const SizedBox(height: 2),
        Text('Tus amigos eligen su plato y la mesa se sincroniza al instante',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
      ]),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.table});

  final SharedTable table;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final n = table.members.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Theme.of(context).scaffoldBackgroundColor, colors.primaryContainer],
        ),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.qr_code_2_rounded, size: 18, color: colors.primary),
          const SizedBox(width: 6),
          Text('QR de la mesa #${table.id}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.primary)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: b.qrBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(children: [
            SocialQr(value: table.qrPayload, size: 150),
            const SizedBox(height: 6),
            Text(n == 1 ? '1 comensal' : '$n comensales',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: b.qrForeground)),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
          'Muestra este único QR en caja: se valida el almuerzo de todos en 1 segundo. '
          'Invita a tus amigos con WhatsApp.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4, color: colors.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.title, required this.hint, required this.selected, required this.onTap});

  final String title;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onSurface)),
                ),
                if (selected) Icon(Icons.check_circle_rounded, size: 18, color: colors.primary),
              ]),
              const SizedBox(height: 2),
              Text(hint,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3, color: colors.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Members extends StatelessWidget {
  const _Members({required this.table});

  final SharedTable table;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.group_outlined, size: 18, color: colors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text('En la mesa (${table.members.length})',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
        ),
        SocialBadge(
          label: table.onTheWay ? 'En camino a cocina' : 'Mesa activa',
          background: b.successContainer,
          foreground: b.success,
        ),
      ]),
      const SizedBox(height: 10),
      for (final m in table.members)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(m.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.onSurface)),
                  if (m.isHost)
                    SocialBadge(
                      label: 'Anfitrión',
                      background: colors.primaryContainer,
                      foreground: colors.onPrimaryContainer,
                    ),
                ]),
                Text(m.main == null ? 'Eligiendo plato...' : 'Plato: ${m.main}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(m.takeaway ? 'Para llevar' : 'En local',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
          ]),
        ),
    ]);
  }
}

class _RestaurantPicker extends StatelessWidget {
  const _RestaurantPicker({required this.restaurants, required this.onSelect});

  final List<Restaurant> restaurants;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    if (restaurants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No hay restaurantes disponibles en este momento para crear una mesa.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const SocialLabel('Elige dónde van a almorzar'),
        const SizedBox(height: 10),
        for (final r in restaurants) ...[
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelect(r.id),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(children: [
                  Icon(Icons.restaurant_rounded, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
                      if (r.zone.isNotEmpty)
                        Text(r.zone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
