import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/config/support_config.dart';
import '../../../core/contracts/models.dart';
import '../../../core/location/location_service.dart';
import '../../../core/session/session_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ec_validators.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/appearance_selector.dart';
import '../../../core/widgets/bocadoo_logo.dart';
import '../../../core/widgets/owner_location_picker.dart';
import '../data/api_owner_repo.dart';
import '../domain/models/extras_models.dart';
import '../domain/models/metrics_models.dart';
import 'owner_controller.dart';
import 'owner_widgets.dart';
import 'weekly_summary_preview.dart';

const _maxLogoBytes = 60 * 1024;

class _StoreOpenNotifier extends Notifier<bool> {
  @override
  bool build() {
    final pos = ref.watch(posMenuProvider).value;
    if (pos != null) return pos.isOpen;
    if (!AppMode.useMock) {
      final repo = ref.read(ownerMenuRepositoryProvider);
      if (repo is ApiOwnerRepository) {
        Future.microtask(() async {
          final open = await repo.fetchStoreOpen();
          state = open;
        });
      }
    }
    return true;
  }

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
              if (isOwner) const _IncompleteProfileBanner(),
              const SizedBox(height: 12),
              const _LocalCard(),
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
                const SizedBox(height: 12),
                const _ExecutivePricesCard(),
              ],
              const SizedBox(height: 12),
              const _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                OwnerSectionLabel('Apariencia'),
                SizedBox(height: 10),
                AppearanceSelector(),
              ])),
              const SizedBox(height: 12),
              const _SupportCard(),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(sessionProvider).logout();
                  if (context.mounted) context.go('/login');
                },
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
            child: IgnorePointer(
              ignoring: !ApiCapabilities.canSwitchToOwner,
              child: Opacity(
                opacity: ApiCapabilities.canSwitchToOwner ? 1.0 : 0.45,
                child: OwnerChoice(
                  label: 'Dueño (Todo)',
                  icon: Icons.storefront_outlined,
                  selected: role == OwnerRole.owner,
                  onTap: () => notifier.set(OwnerRole.owner),
                ),
              ),
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
          !ApiCapabilities.canSwitchToOwner
              ? 'Tu cuenta tiene rol de cajero en este local y solo ve Caja, Cobrar, Vender y Pedidos.'
              : role == OwnerRole.cashier
                  ? 'El cajero solo ve Caja, Cobrar, Vender y Pedidos en camino.'
                  : 'El dueño tiene acceso total a ventas, reportes y cierre.',
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
                  : (info?.logoUrl != null
                      ? Image.network(
                          info!.logoUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Text(
                            info.monogram,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        )
                      : Text(
                          info?.monogram ?? '',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: colors.onPrimaryContainer,
                          ),
                        )),
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
      final err = await ref.read(manualOccupancyProvider.notifier).setStatus(
            value ? ManualOccupancyStatus.libre : ManualOccupancyStatus.cerrado,
          );
      if (!context.mounted) return;
      if (err != null && err.isNotEmpty) {
        ref.read(_storeOpenProvider.notifier).set(!value);
        showInfoSnackBar(messenger, err);
        return;
      }
      ref.invalidate(posMenuProvider);
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

class _IncompleteProfileBanner extends ConsumerWidget {
  const _IncompleteProfileBanner();

  static String _labelForField(String raw) {
    final key = raw.trim().toLowerCase();
    return switch (key) {
      'cedularuc' || 'cedula_ruc' || 'ruc' => 'Cédula o RUC',
      'telefono' || 'whatsapp' => 'Teléfono',
      'mesas' => 'Mesas',
      'puestos' || 'sillas' => 'Sillas',
      'direccion' => 'Dirección',
      'ubicacion' || 'coordenadas' || 'latitud' || 'longitud' => 'Ubicación en mapa',
      'recargoparallevarcentavos' || 'recargo_para_llevar' => 'Recargo para llevar',
      'preciosueltocentavos' => 'Precio del almuerzo',
      _ => raw,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(localInfoProvider).value;
    if (info == null || info.perfilCompleto) return const SizedBox.shrink();

    final b = context.bocadooColors;
    final pendingLabels = [
      for (final p in info.datosPendientes) _labelForField(p),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: b.walletAccent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: b.onWalletAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: b.onWalletAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Completa el perfil de tu restaurante',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: b.onWalletAccent,
                    ),
                  ),
                ),
              ],
            ),
            if (pendingLabels.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Pendiente: ${pendingLabels.join(' · ')}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: b.onWalletAccent,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _LocalCard.openProfileEditor(context, ref, info),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Completar datos'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalCard extends ConsumerWidget {
  const _LocalCard();

  static Future<void> openProfileEditor(
    BuildContext context,
    WidgetRef ref,
    LocalInfo? info,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _EditLocalSheet(info: info),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(localInfoProvider);
      ref.invalidate(lunchPriceProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos del local actualizados.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final info = ref.watch(localInfoProvider).value;
    final isOwner = ref.watch(ownerRoleProvider) == OwnerRole.owner;
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
            if (info != null) ...[
              Text(
                [
                  if (info.address.trim().isNotEmpty) info.address.trim(),
                  if (info.zone.trim().isNotEmpty) info.zone.trim(),
                  if (info.tablesCount != null && info.tablesCount! > 0)
                    '${info.tablesCount} mesas',
                  '${info.seats} sillas',
                ].join(' · '),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
              ),
              if (info.phone.trim().isNotEmpty || info.maskedCedulaRuc != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      if (info.phone.trim().isNotEmpty) info.phone.trim(),
                      if (info.maskedCedulaRuc != null)
                        'RUC/CI: ${info.maskedCedulaRuc}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                  ),
                ),
              if (info.latitude != null && info.longitude != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Icon(Icons.location_on_outlined, size: 14, color: colors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${info.latitude!.toStringAsFixed(5)}, ${info.longitude!.toStringAsFixed(5)}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                      ),
                    ),
                  ]),
                )
              else if (info.address.trim().isEmpty && info.zone.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Ubicación no registrada en el servidor',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                  ),
                ),
            ],
          ]),
        ),
        if (isOwner)
          IconButton(
            tooltip: 'Editar datos del local',
            onPressed: () => openProfileEditor(context, ref, info),
            icon: Icon(Icons.edit_location_alt_outlined, color: colors.primary),
          ),
      ]),
    );
  }
}

class _ExecutivePricesCard extends ConsumerStatefulWidget {
  const _ExecutivePricesCard();

  @override
  ConsumerState<_ExecutivePricesCard> createState() =>
      _ExecutivePricesCardState();
}

class _ExecutivePricesCardState extends ConsumerState<_ExecutivePricesCard> {
  final _lunchCtrl = TextEditingController();
  final _secondCtrl = TextEditingController();
  final _soupCtrl = TextEditingController();
  final _takeawayCtrl = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _lunchCtrl.dispose();
    _secondCtrl.dispose();
    _soupCtrl.dispose();
    _takeawayCtrl.dispose();
    super.dispose();
  }

  double? _parsePrice(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  String? _errorFor(List<String> needles) {
    for (final e in _fieldErrors.entries) {
      final k = e.key.toLowerCase();
      for (final n in needles) {
        if (k.contains(n)) return e.value;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final lunch = _parsePrice(_lunchCtrl);
    final soloSecond = _parsePrice(_secondCtrl);
    final soloSoup = _parsePrice(_soupCtrl);
    final takeaway = _parsePrice(_takeawayCtrl);

    if (lunch == null ||
        lunch <= 0 ||
        soloSecond == null ||
        soloSecond <= 0 ||
        soloSoup == null ||
        soloSoup <= 0 ||
        takeaway == null ||
        takeaway < 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ingresa precios válidos en los 4 campos (ej. 3.00).'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _fieldErrors = const {};
    });
    ref.read(executivePricesProvider.notifier).setPrices(
          lunch: lunch,
          soloSecond: soloSecond,
          soloSoup: soloSoup,
          takeawaySurcharge: takeaway,
        );

    if (AppMode.useMock) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Precios actualizados en modo demo.')),
        );
      }
      return;
    }

    final repo = ref.read(apiOwnerRepositoryProvider);
    final ok = await repo.updateRestaurantProfile(
      singleLunchPriceCents: Money.toCents(lunch),
      takeawaySurchargeCents: Money.toCents(takeaway),
    );
    if (!mounted) return;
    if (ok) {
      await repo.updateSingleLunchPriceAndActivate(lunch);
      if (!mounted) return;
      setState(() => _saving = false);
      ref.invalidate(lunchPriceProvider);
      ref.invalidate(localInfoProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Precios del menú ejecutivo actualizados.'),
        ),
      );
    } else {
      final fieldErrs = repo.consumeLastFieldErrors();
      final msg = repo.consumeLastError() ??
          'No se pudo guardar el precio del almuerzo en el servidor.';
      setState(() {
        _saving = false;
        _fieldErrors = fieldErrs;
      });
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _priceField(
    String label,
    TextEditingController ctrl, {
    required String hint,
    String? errorText,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: '\$ ',
        errorText: errorText,
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final current = ref.watch(executivePricesProvider);
    final info = ref.watch(localInfoProvider).value;
    ref.listen<ExecutivePrices>(executivePricesProvider, (prev, next) {
      if (!_saving && prev != next && mounted) {
        _lunchCtrl.text = next.lunch.toStringAsFixed(2);
        _secondCtrl.text = next.soloSecond.toStringAsFixed(2);
        _soupCtrl.text = next.soloSoup.toStringAsFixed(2);
        _takeawayCtrl.text = next.takeawaySurcharge.toStringAsFixed(2);
      }
    });
    if (!_seeded) {
      _lunchCtrl.text = current.lunch.toStringAsFixed(2);
      _secondCtrl.text = current.soloSecond.toStringAsFixed(2);
      _soupCtrl.text = current.soloSoup.toStringAsFixed(2);
      final serverSurcharge = info?.takeawaySurchargeCents != null
          ? Money.fromCents(info!.takeawaySurchargeCents!)
          : current.takeawaySurcharge;
      _takeawayCtrl.text = serverSurcharge.toStringAsFixed(2);
      _seeded = true;
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OwnerSectionLabel('Precios del menú ejecutivo'),
          const SizedBox(height: 6),
          Text(
            'Se reflejan de inmediato en Menú de hoy y Registrar consumo.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _priceField(
                  'Almuerzo completo',
                  _lunchCtrl,
                  hint: '3.00',
                  errorText: _errorFor(['preciosuelto', 'precio']),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _priceField(
                  'Solo segundo',
                  _secondCtrl,
                  hint: '2.50',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _priceField(
                  'Solo sopa',
                  _soupCtrl,
                  hint: '1.50',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _priceField(
                  'Recargo para llevar',
                  _takeawayCtrl,
                  hint: '0.25',
                  errorText: _errorFor(['recargoparallevar', 'recargo']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando...' : 'Guardar precios'),
          ),
        ],
      ),
    );
  }
}

class _EditLocalSheet extends ConsumerStatefulWidget {
  const _EditLocalSheet({required this.info});

  final LocalInfo? info;

  @override
  ConsumerState<_EditLocalSheet> createState() => _EditLocalSheetState();
}

class _EditLocalSheetState extends ConsumerState<_EditLocalSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final TextEditingController _cedulaCtrl = TextEditingController();
  late final TextEditingController _addrCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _surchargeCtrl;
  late final TextEditingController _tablesCtrl;
  late final TextEditingController _seatsCtrl;

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _cedulaFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _surchargeFocus = FocusNode();
  final _tablesFocus = FocusNode();
  final _seatsFocus = FocusNode();
  final _mapController = MapController();

  late LatLng _mapCenter;
  late bool _locationConfirmed;
  bool _saving = false;
  final _touched = <String>{};
  final _errors = <String, String?>{};

  @override
  void initState() {
    super.initState();
    final info = widget.info;
    final prices = ref.read(executivePricesProvider);
    final initialName = (info?.name.trim().isNotEmpty ?? false)
        ? info!.name.trim()
        : ref.read(ownerRestaurantNameProvider);
    final rawPhone = info?.phone.trim() ?? '';
    final localPhone = rawPhone.isNotEmpty ? Phone.toLocal(rawPhone) : '';
    final surcharge = info?.takeawaySurchargeCents != null
        ? Money.fromCents(info!.takeawaySurchargeCents!)
        : prices.takeawaySurcharge;

    _nameCtrl = TextEditingController(text: initialName);
    _phoneCtrl = TextEditingController(
      text: localPhone.isNotEmpty ? localPhone : rawPhone,
    );
    _addrCtrl = TextEditingController(text: info?.address.trim() ?? '');
    _priceCtrl = TextEditingController(text: prices.lunch.toStringAsFixed(2));
    _surchargeCtrl = TextEditingController(text: surcharge.toStringAsFixed(2));
    _tablesCtrl = TextEditingController(
      text: (info?.tablesCount != null && info!.tablesCount! > 0)
          ? '${info.tablesCount}'
          : '',
    );
    _seatsCtrl = TextEditingController(
      text: (info != null && info.seats > 0) ? '${info.seats}' : '',
    );

    if (info?.latitude != null &&
        info?.longitude != null &&
        LocationService.isValidCoordinate(info!.latitude, info.longitude)) {
      _mapCenter = LatLng(info.latitude!, info.longitude!);
      _locationConfirmed = true;
    } else {
      _mapCenter = LocationService.fallbackPuce;
      _locationConfirmed = false;
    }

    _attachBlurValidation(_nameFocus, 'name');
    _attachBlurValidation(_phoneFocus, 'phone');
    _attachBlurValidation(_cedulaFocus, 'cedula');
    _attachBlurValidation(_priceFocus, 'price');
    _attachBlurValidation(_surchargeFocus, 'takeaway');
    _attachBlurValidation(_tablesFocus, 'mesas');
    _attachBlurValidation(_seatsFocus, 'puestos');
  }

  void _attachBlurValidation(FocusNode node, String key) {
    node.addListener(() {
      if (!node.hasFocus && mounted) {
        _touched.add(key);
        setState(() {
          _errors[key] = _validateField(key);
        });
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cedulaCtrl.dispose();
    _addrCtrl.dispose();
    _priceCtrl.dispose();
    _surchargeCtrl.dispose();
    _tablesCtrl.dispose();
    _seatsCtrl.dispose();

    _nameFocus.dispose();
    _phoneFocus.dispose();
    _cedulaFocus.dispose();
    _priceFocus.dispose();
    _surchargeFocus.dispose();
    _tablesFocus.dispose();
    _seatsFocus.dispose();
    super.dispose();
  }

  String? _validateField(String key) => switch (key) {
        'name' => EcValidators.validateRestaurantName(_nameCtrl.text),
        'phone' => EcValidators.validateEcuadorCellPhone(_phoneCtrl.text),
        'cedula' => EcValidators.validateCedulaRuc(
            _cedulaCtrl.text,
            required: false,
          ),
        'price' => EcValidators.validateLunchPrice(_priceCtrl.text),
        'takeaway' => EcValidators.validateTakeawaySurcharge(
            _surchargeCtrl.text,
          ),
        'mesas' => EcValidators.validateOptionalPositiveInt(_tablesCtrl.text),
        'puestos' => EcValidators.validateOptionalPositiveInt(_seatsCtrl.text),
        _ => null,
      };

  void _onFieldChanged(String key) {
    setState(() {
      if (_touched.contains(key) || _errors[key] != null) {
        _errors[key] = _validateField(key);
      }
    });
  }

  bool _isFieldValidVisual(String key, String raw) =>
      raw.trim().isNotEmpty && _validateField(key) == null;

  InputDecoration _fieldDecoration({
    required String key,
    required String rawValue,
    required String hintText,
    IconData? prefixIcon,
    String? prefixText,
  }) {
    final cs = context.colorScheme;
    final b = context.bocadooColors;
    final error = _errors[key];
    final valid = error == null && _isFieldValidVisual(key, rawValue);
    final validBorder = valid
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            borderSide: BorderSide(color: b.success, width: 1.5),
          )
        : null;
    final validFocusBorder = valid
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            borderSide: BorderSide(color: b.success, width: 2),
          )
        : null;

    return InputDecoration(
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: valid ? b.success : cs.onSurfaceVariant)
          : null,
      prefixText: prefixText,
      hintText: hintText,
      error: error == null
          ? null
          : Text(
              error,
              softWrap: true,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.error,
              ),
            ),
      errorMaxLines: 3,
      enabledBorder: validBorder,
      focusedBorder: validFocusBorder,
      suffixIcon: valid
          ? Icon(Icons.check_circle_rounded, color: b.success, size: 20)
          : null,
    );
  }

  bool _validateAll() {
    const keys = [
      'name',
      'phone',
      'cedula',
      'price',
      'takeaway',
      'mesas',
      'puestos',
    ];
    final errs = <String, String?>{};
    for (final k in keys) {
      final e = _validateField(k);
      if (e != null) errs[k] = e;
    }
    setState(() {
      _touched.addAll(keys);
      _errors
        ..clear()
        ..addAll(errs);
    });
    return errs.isEmpty && _locationConfirmed;
  }

  void _applyServerFieldErrors(Map<String, String> fieldErrors) {
    for (final entry in fieldErrors.entries) {
      final k = entry.key.toLowerCase();
      final msg = entry.value;
      if (EcValidators.isTechnicalErrorMessage(msg)) continue;
      if (k.contains('cedularuc') || k.contains('cedula') || k.contains('ruc')) {
        _errors['cedula'] = msg;
      } else if (k.contains('telefono') || k.contains('whatsapp')) {
        _errors['phone'] = msg;
      } else if (k.contains('nombre')) {
        _errors['name'] = msg;
      } else if (k.contains('direccion')) {
        _errors['address'] = msg;
      } else if (k.contains('mesas')) {
        _errors['mesas'] = msg;
      } else if (k.contains('puestos') || k.contains('sillas')) {
        _errors['puestos'] = msg;
      } else if (k.contains('preciosuelto') || k.contains('precio')) {
        _errors['price'] = msg;
      } else if (k.contains('recargoparallevar') || k.contains('recargo')) {
        _errors['takeaway'] = msg;
      }
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validateAll()) {
      if (!_locationConfirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Fija la ubicación de tu local en el mapa o usa Mi GPS.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);

    var center = _mapCenter;
    try {
      center = _mapController.camera.center;
    } catch (_) {}

    var resolvedAddress = _addrCtrl.text.trim();
    if (resolvedAddress.isEmpty) {
      resolvedAddress = await OwnerGeocoder.reverseGeocode(center);
      if (!mounted) return;
      _addrCtrl.text = resolvedAddress;
    }

    final lunch = double.parse(_priceCtrl.text.trim().replaceAll(',', '.'));
    final surcharge =
        double.parse(_surchargeCtrl.text.trim().replaceAll(',', '.'));
    final currentPrices = ref.read(executivePricesProvider);
    ref.read(executivePricesProvider.notifier).setPrices(
          lunch: lunch,
          soloSecond: currentPrices.soloSecond,
          soloSoup: currentPrices.soloSoup,
          takeawaySurcharge: surcharge,
        );

    if (AppMode.useMock) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    final repo = ref.read(apiOwnerRepositoryProvider);
    final cedulaNew = _cedulaCtrl.text.trim();
    final ok = await repo.updateRestaurantProfile(
      name: _nameCtrl.text.trim(),
      address: resolvedAddress,
      lat: center.latitude,
      lng: center.longitude,
      phone: _phoneCtrl.text.replaceAll(RegExp(r'[\s\-()]'), '').trim(),
      cedulaRuc: cedulaNew.isNotEmpty ? cedulaNew : null,
      tablesCount: int.tryParse(_tablesCtrl.text.trim()),
      seats: int.tryParse(_seatsCtrl.text.trim()),
      singleLunchPriceCents: Money.toCents(lunch),
      takeawaySurchargeCents: Money.toCents(surcharge),
    );
    if (!mounted) return;
    if (ok) {
      await repo.updateSingleLunchPriceAndActivate(lunch);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    final serverFieldErrs = repo.consumeLastFieldErrors();
    final rawMsg = repo.consumeLastError() ??
        'No se pudieron actualizar los datos del local.';
    setState(() {
      _saving = false;
      _applyServerFieldErrors(serverFieldErrs);
    });
    if (_errors.values.every((v) => v == null)) {
      final friendly = EcValidators.isTechnicalErrorMessage(rawMsg)
          ? 'No pudimos actualizar los datos por un problema técnico. Inténtalo de nuevo.'
          : rawMsg;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final info = widget.info;
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final sysNav = mq.viewPadding.bottom;
    final safeBottom = mq.padding.bottom;
    final navClearance =
        keyboard > 0 ? 0.0 : (sysNav - safeBottom).clamp(0.0, double.infinity);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, navClearance + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Datos y ubicación del local',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const _SettingFieldLabel(
                  'NOMBRE DEL RESTAURANTE / LOCAL',
                  required: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _onFieldChanged('name'),
                  onEditingComplete: () => _phoneFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'name',
                    rawValue: _nameCtrl.text,
                    prefixIcon: Icons.store_mall_directory_outlined,
                    hintText: 'Ej. La Cuchara de San Blas',
                  ),
                ),

                const SizedBox(height: 16),

                const _SettingFieldLabel('NÚMERO DE CELULAR', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) => _onFieldChanged('phone'),
                  onEditingComplete: () => _cedulaFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'phone',
                    rawValue: _phoneCtrl.text,
                    prefixIcon: Icons.phone_outlined,
                    hintText: 'Ej. 0987654321',
                  ),
                ),

                const SizedBox(height: 16),

                const _SettingFieldLabel('CÉDULA O RUC'),
                const SizedBox(height: 8),
                TextField(
                  controller: _cedulaCtrl,
                  focusNode: _cedulaFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(13),
                  ],
                  onChanged: (_) => _onFieldChanged('cedula'),
                  onEditingComplete: () => _priceFocus.requestFocus(),
                  decoration: _fieldDecoration(
                    key: 'cedula',
                    rawValue: _cedulaCtrl.text,
                    prefixIcon: Icons.badge_outlined,
                    hintText: info?.maskedCedulaRuc != null
                        ? 'Actual: ${info!.maskedCedulaRuc} (deja vacío para conservar)'
                        : 'Ej. 1710034065001',
                  ),
                ),

                const SizedBox(height: 20),

                const _SettingFieldLabel(
                  'UBICACIÓN DE TU RESTAURANTE',
                  required: true,
                ),
                const SizedBox(height: 8),

                OwnerLocationPicker(
                  addressController: _addrCtrl,
                  mapController: _mapController,
                  center: _mapCenter,
                  locationConfirmed: _locationConfirmed,
                  errorText: _errors['address'],
                  onAddressChanged: (_) {
                    if (_errors['address'] != null) {
                      setState(() => _errors.remove('address'));
                    }
                  },
                  onLocationChanged: (point, {required bool confirmed}) {
                    final needsUpdate =
                        (!_locationConfirmed && confirmed) ||
                        point.latitude != _mapCenter.latitude ||
                        point.longitude != _mapCenter.longitude;
                    _mapCenter = point;
                    if (!_locationConfirmed && confirmed) {
                      setState(() => _locationConfirmed = true);
                    } else if (needsUpdate && mounted) {
                      setState(() {});
                    }
                  },
                ),

                const SizedBox(height: 20),

                const Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _SettingFieldLabel(
                        'ALMUERZO EJECUTIVO (\$)',
                        required: true,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _SettingFieldLabel(
                        'RECARGO LLEVAR (\$)',
                        required: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        focusNode: _priceFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => _onFieldChanged('price'),
                        onEditingComplete: () => _surchargeFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'price',
                          rawValue: _priceCtrl.text,
                          prefixText: '\$ ',
                          hintText: 'Ej. 3.50',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _surchargeCtrl,
                        focusNode: _surchargeFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => _onFieldChanged('takeaway'),
                        onEditingComplete: () => _tablesFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'takeaway',
                          rawValue: _surchargeCtrl.text,
                          prefixText: '\$ ',
                          hintText: 'Ej. 0.25',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                const Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: _SettingFieldLabel('MESAS (OPCIONAL)')),
                    SizedBox(width: 12),
                    Expanded(child: _SettingFieldLabel('SILLAS (OPCIONAL)')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tablesCtrl,
                        focusNode: _tablesFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _onFieldChanged('mesas'),
                        onEditingComplete: () => _seatsFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          key: 'mesas',
                          rawValue: _tablesCtrl.text,
                          prefixIcon: Icons.table_restaurant_outlined,
                          hintText: 'Ej. 10',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _seatsCtrl,
                        focusNode: _seatsFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _onFieldChanged('puestos'),
                        onEditingComplete: () => FocusScope.of(context).unfocus(),
                        decoration: _fieldDecoration(
                          key: 'puestos',
                          rawValue: _seatsCtrl.text,
                          prefixIcon: Icons.chair_alt_outlined,
                          hintText: 'Ej. 40',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_saving ? 'Actualizando...' : 'Actualizar datos'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingFieldLabel extends StatelessWidget {
  const _SettingFieldLabel(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
            ),
        ],
      ),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}
