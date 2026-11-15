import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/support_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/widgets/appearance_selector.dart';
import '../../../core/widgets/bocadoo_logo.dart';
import '../domain/models/extras_models.dart';
import '../domain/models/metrics_models.dart';
import 'owner_controller.dart';
import 'owner_widgets.dart';
import 'weekly_summary_preview.dart';

const _maxLogoBytes = 60 * 1024;

class _StoreOpenNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool value) => state = value;
}

/// Estado de apertura del local para esta sesión.
final _storeOpenProvider = NotifierProvider<_StoreOpenNotifier, bool>(_StoreOpenNotifier.new);

/// O16 · Ajustes del dueño: rol del dispositivo, números, opiniones, cartulina,
/// resumen semanal, logo, apariencia, soporte y sesión. En modo cajero solo
/// quedan rol, apariencia, soporte y sesión ("Turno").
class OwnerSettingsScreen extends ConsumerWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final role = ref.watch(ownerRoleProvider);
    final isOwner = role == OwnerRole.owner;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 10),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: OwnerBackHeader(
              title: isOwner ? 'Ajustes' : 'Turno',
              onBack: () => context.go('/owner/caja'),
              trailing: Text(isOwner ? 'Modo dueño' : 'Modo cajero',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
              _RoleCard(role: role),
              if (isOwner) ...[
                const SizedBox(height: 12),
                _LinkCard(
                  icon: Icons.bar_chart_rounded,
                  title: 'Tus números',
                  subtitle: 'Hoy, dinero y clientes por renovar',
                  action: 'Ver',
                  onTap: () => context.go('/owner/metricas'),
                ),
                const SizedBox(height: 12),
                _LinkCard(
                  icon: Icons.forum_outlined,
                  title: 'Opiniones',
                  subtitle: 'Lo que dicen tus comensales',
                  action: _pendingLabel(ref),
                  onTap: () => context.push('/owner/opiniones'),
                ),
                const SizedBox(height: 12),
                _LinkCard(
                  icon: Icons.style_outlined,
                  title: 'Pasar cartulina',
                  subtitle: 'Registra clientes de cartulina física a digital',
                  action: 'Abrir',
                  onTap: () => context.push('/owner/cartulina'),
                ),
                const SizedBox(height: 12),
                const _WeeklySummaryCard(),
                const SizedBox(height: 12),
                const _LogoCard(),
                const SizedBox(height: 12),
                const _StoreOpenCard(),
              ],
              const SizedBox(height: 12),
              const _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                OwnerSectionLabel('Apariencia'),
                SizedBox(height: 10),
                AppearanceSelector(),
              ])),
              const SizedBox(height: 12),
              const _SupportCard(),
              const SizedBox(height: 12),
              const _LocalCard(),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => context.go('/login'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.bocadooColors.danger,
                  side: BorderSide(color: context.bocadooColors.dangerContainer),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  String _pendingLabel(WidgetRef ref) {
    final n = ref.watch(opinionsProvider).value?.where((o) => o.isPending).length;
    if (n == null || n == 0) return 'Ver';
    return n == 1 ? '1 nueva' : '$n nuevas';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _RoleCard extends ConsumerWidget {
  const _RoleCard({required this.role});

  final OwnerRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final notifier = ref.read(ownerRoleProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const OwnerSectionLabel('Rol del dispositivo'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OwnerChoice(
              label: 'Dueño (Todo)',
              icon: Icons.storefront_outlined,
              selected: role == OwnerRole.owner,
              onTap: () => notifier.set(OwnerRole.owner),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OwnerChoice(
              label: 'Cajero / Ayudante',
              icon: Icons.badge_outlined,
              selected: role == OwnerRole.cashier,
              onTap: () => notifier.set(OwnerRole.cashier),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          role == OwnerRole.cashier
              ? 'El cajero solo ve Caja, Cobrar, Vender y Pedidos en camino.'
              : 'El dueño tiene acceso total a ventas, comisiones y cierre.',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colors.primaryContainer,
              child: Icon(icon, size: 20, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
                Text(subtitle,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            OwnerBadge(label: action, background: colors.primaryContainer, foreground: colors.onPrimaryContainer),
          ]),
        ),
      ),
    );
  }
}

class _WeeklySummaryCard extends ConsumerWidget {
  const _WeeklySummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final metrics = ref.watch(metricsProvider(MetricsPeriod.semana)).value;
    final on = metrics?.weeklySummaryEnabled ?? true;

    Future<void> toggle(bool value) async {
      await ref
          .read(ownerMetricsRepositoryProvider)
          .setWeeklySummary(ref.read(ownerRestaurantIdProvider), enabled: value);
      ref.invalidate(metricsProvider);
    }

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.primaryContainer,
            child: Icon(Icons.chat_outlined, size: 20, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resumen semanal por WhatsApp',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
              Text('Cada lunes a las 8:00 te llega cómo te fue la semana.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            ]),
          ),
          Switch(value: on, onChanged: metrics == null ? null : toggle),
        ]),
        if (metrics != null && on) ...[
          const SizedBox(height: 12),
          const OwnerSectionLabel('Así se verá · Activado'),
          const SizedBox(height: 8),
          WeeklySummaryPreview(metrics: metrics, localName: ref.watch(ownerRestaurantNameProvider)),
        ],
      ]),
    );
  }
}

class _LogoCard extends ConsumerStatefulWidget {
  const _LogoCard();

  @override
  ConsumerState<_LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends ConsumerState<_LogoCard> {
  bool _busy = false;

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxLogoBytes) {
        showInfoSnackBar(messenger, 'La imagen pesa más de 60 KB. Elige una más liviana.');
        return;
      }
      await ref.read(ownerSettingsRepositoryProvider).setLogo(ref.read(ownerRestaurantIdProvider), bytes);
      ref.invalidate(localInfoProvider);
      showInfoSnackBar(messenger, 'Logo actualizado');
    } catch (_) {
      showInfoSnackBar(messenger, 'No se pudo abrir la galería');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await ref.read(ownerSettingsRepositoryProvider).setLogo(ref.read(ownerRestaurantIdProvider), null);
    ref.invalidate(localInfoProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final info = ref.watch(localInfoProvider).value;
    final logo = info?.logo;

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const OwnerSectionLabel('Logo del local'),
        const SizedBox(height: 12),
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 60,
              height: 60,
              color: colors.primaryContainer,
              alignment: Alignment.center,
              child: logo != null
                  ? Image.memory(logo, width: 60, height: 60, fit: BoxFit.cover)
                  : Text(info?.monogram ?? '',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onPrimaryContainer)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OwnerSmallButton(
                  label: logo == null ? 'Subir logo' : 'Cambiar logo',
                  icon: Icons.upload_rounded,
                  onPressed: _busy ? null : _pick,
                ),
                if (logo != null)
                  TextButton(
                    onPressed: _remove,
                    style: TextButton.styleFrom(foregroundColor: context.bocadooColors.danger),
                    child: const Text('Quitar'),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('Cuadrado · Máx. 60 KB',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _StoreOpenCard extends ConsumerWidget {
  const _StoreOpenCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final isOpen = ref.watch(_storeOpenProvider);

    Future<void> toggle(bool value) async {
      final messenger = ScaffoldMessenger.of(context);
      ref.read(_storeOpenProvider.notifier).set(value);
      await ref.read(ownerMenuRepositoryProvider).setStoreOpen(ref.read(ownerRestaurantIdProvider), isOpen: value);
      showInfoSnackBar(messenger, value ? 'Local abierto' : 'Local cerrado');
    }

    return _Card(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isOpen ? 'Local abierto' : 'Local cerrado',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
            Text(isOpen ? 'Los comensales pueden ver el menú.' : 'El local no recibe pedidos ahora.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          ]),
        ),
        Switch(value: isOpen, onChanged: toggle),
      ]),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final link = SupportConfig.link('Hola Bocadoo, necesito ayuda con la caja de mi local.');
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const BocadooLogo.isotipo(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Soporte Bocadoo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
              Text(
                link == null
                    ? 'El contacto de soporte todavía no está configurado.'
                    : 'Escríbenos si algo no funciona en tu caja.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: link == null ? null : () => openExternal(context, link, failMessage: 'No se pudo abrir el soporte'),
          icon: const Icon(Icons.support_agent_rounded),
          label: const Text('Contactar soporte'),
        ),
      ]),
    );
  }
}

class _LocalCard extends ConsumerWidget {
  const _LocalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final info = ref.watch(localInfoProvider).value;
    return _Card(
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          ),
          child: Icon(Icons.storefront_outlined, size: 20, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(info?.name ?? ref.watch(ownerRestaurantNameProvider),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.onSurface)),
            if (info != null)
              Text('${info.address} · ${info.seats} puestos',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}
