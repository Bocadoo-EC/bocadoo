import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart' show CustomerErrorView, formatMoney;
import 'social_widgets.dart';

/// C7 · Unirme a mesa: el invitado elige su almuerzo antes de llegar.
class JoinTableScreen extends ConsumerStatefulWidget {
  const JoinTableScreen({super.key, required this.tableId});

  final String tableId;

  @override
  ConsumerState<JoinTableScreen> createState() => _JoinTableScreenState();
}

class _JoinTableScreenState extends ConsumerState<JoinTableScreen> {
  final _name = TextEditingController();
  SharedTable? _table;
  bool _loading = true;
  bool _failed = false;
  bool _joining = false;
  bool _joined = false;
  String? _soup;
  String? _main;
  bool _takeaway = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    if (!AppMode.useMock) {
      final sessionName = ref.read(sessionProvider).userName?.trim() ?? '';
      if (sessionName.isNotEmpty) {
        _name.text = sessionName;
      }
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final table = await ref.read(customerRepositoryProvider).getSharedTable(widget.tableId);
      if (!mounted) return;
      setState(() {
        _table = table;
        _soup = table?.soups.firstOrNull;
        _main = table?.mains.firstOrNull?.name;
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

  Future<void> _join(SharedTable t) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Escribe tu nombre.');
      return;
    }
    setState(() => _joining = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref.read(customerRepositoryProvider).joinTable(
            t.id,
            name: name,
            soup: _soup ?? '',
            main: _main ?? '',
            takeaway: _takeaway,
          );
      if (!mounted) return;
      ref.read(customerControllerProvider).syncTable(updated);
      setState(() {
        _table = updated;
        _joined = true;
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(e.userMessage),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Error al unirse. Inténtalo de nuevo.'),
      ));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/customer/pase');

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final t = _table;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: IconButton(tooltip: 'Volver', onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
        title: const Text('Mesa compartida'),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const SocialLoading('Cargando invitación')
            : _failed
                ? CustomerErrorView(
                    title: 'Error al unirse',
                    message: 'No pudimos cargar la invitación.',
                    onRetry: _load,
                  )
                : t == null
                    ? SocialEmpty(
                        icon: Icons.group_off_outlined,
                        title: 'Mesa no encontrada',
                        message: 'El enlace de la mesa ya expiró.',
                        actionLabel: 'Ver locales',
                        onAction: () => context.go('/customer/restaurants'),
                      )
                    : _content(t),
      ),
    );
  }

  Widget _content(SharedTable t) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      _Invitation(table: t),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SocialLabel('Tu nombre en la mesa'),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            enabled: !_joined,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: 'Escribe tu nombre', isDense: true, errorText: _nameError),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
        ]),
      ),
      const SizedBox(height: 18),
      if (ApiCapabilities.sharedTableDishChoice) ...[
        Text('Elige tu almuerzo de hoy',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
        const SizedBox(height: 10),
        const SocialLabel('1. Sopa del día'),
        const SizedBox(height: 6),
        for (final s in t.soups) ...[
          _OptionTile(
            title: s,
            selected: _soup == s,
            onTap: _joined ? null : () => setState(() => _soup = s),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        const SocialLabel('2. Plato fuerte'),
        const SizedBox(height: 6),
        for (final m in t.mains) ...[
          _OptionTile(
            title: m.name,
            price: formatMoney(m.price),
            imageUrl: m.imageUrl,
            veggie: m.isVeggie,
            selected: _main == m.name,
            onTap: _joined ? null : () => setState(() => _main = m.name),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
      ],
      Row(children: [
        Expanded(
          child: SocialChoice(
            label: 'Para comer aquí',
            icon: Icons.restaurant_rounded,
            selected: !_takeaway,
            radius: AppTheme.buttonRadius,
            onTap: _joined ? null : () => setState(() => _takeaway = false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SocialChoice(
            label: 'Para llevar (+ ${formatMoney(t.takeawaySurcharge)})',
            icon: Icons.takeout_dining_outlined,
            selected: _takeaway,
            radius: AppTheme.buttonRadius,
            onTap: _joined ? null : () => setState(() => _takeaway = true),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SocialLabel('Compañeros en la mesa (${t.members.length})'),
          const SizedBox(height: 8),
          for (final m in t.members)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Text(m.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.onSurface)),
                if (m.isHost) ...[
                  const SizedBox(width: 6),
                  SocialBadge(
                    label: 'Anfitrión',
                    background: colors.primaryContainer,
                    foreground: colors.onPrimaryContainer,
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.main ?? 'Confirmado',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 20),
      if (_joined)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: b.successContainer, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_outline_rounded, color: b.success),
              const SizedBox(width: 8),
              Flexible(
                child: Text('¡Te has unido a la mesa!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: b.success)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              (_main != null && _main!.isNotEmpty)
                  ? 'Tu almuerzo ($_main) está reservado para las ${t.time}.'
                  : 'Tu lugar en la mesa quedó reservado para las ${t.time}.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.onSuccessContainer),
            ),
            Text('Se sumó al QR de la mesa de ${t.hostName}. No necesitas hacer fila en caja.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b.onSuccessContainer)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              style: compactButtonStyle(context),
              onPressed: () => context.go('/customer/pase'),
              child: const Text('Volver al inicio'),
            ),
          ]),
        )
      else
        ElevatedButton(
          onPressed: _joining ||
                  (ApiCapabilities.sharedTableDishChoice &&
                      ((t.soups.isNotEmpty && _soup == null) ||
                          (t.mains.isNotEmpty && _main == null)))
              ? null
              : () => _join(t),
          child: _joining
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                )
              : const Text('Unirme a la mesa'),
        ),
    ]);
  }
}

class _Invitation extends StatelessWidget {
  const _Invitation({required this.table});

  final SharedTable table;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Container(
      padding: const EdgeInsets.all(20),
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
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(18)),
          child: Icon(Icons.group_outlined, size: 28, color: colors.primary),
        ),
        const SizedBox(height: 8),
        SocialBadge(
          label: 'Mesa #${table.id}',
          icon: Icons.auto_awesome_rounded,
          background: colors.surface,
          foreground: colors.primary,
        ),
        const SizedBox(height: 6),
        Text(table.restaurantName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Invitación creada por '),
            TextSpan(text: table.hostName, style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurface)),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          SocialBadge(
            label: 'Almuerzo a las ${table.time}',
            icon: Icons.schedule_rounded,
            background: colors.surface,
            foreground: colors.onSurface,
          ),
          if (table.occupancyLabel.isNotEmpty)
            SocialBadge(
              label: table.occupancyLabel,
              icon: Icons.circle,
              background: colors.surface,
              foreground: b.success,
            ),
        ]),
      ]),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.price,
    this.imageUrl,
    this.veggie = false,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;
  final String? price;
  final String? imageUrl;
  final bool veggie;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    return Material(
      color: selected ? colors.primaryContainer : Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? colors.primary : colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (price != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: imageUrl == null
                      ? ColoredBox(
                          color: colors.primaryContainer,
                          child: Icon(Icons.restaurant_rounded, size: 20, color: colors.primary),
                        )
                      : Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: colors.primaryContainer,
                            child: Icon(Icons.restaurant_rounded, size: 20, color: colors.primary),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: selected ? colors.onPrimaryContainer : colors.onSurface,
                      )),
                  if (veggie)
                    SocialBadge(
                      label: 'Veggie',
                      icon: Icons.eco_outlined,
                      background: b.successContainer,
                      foreground: b.success,
                    ),
                ]),
                if (price != null)
                  Text(price!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.primary)),
              ]),
            ),
            if (selected) Icon(Icons.check_rounded, color: colors.primary),
          ]),
        ),
      ),
    );
  }
}
