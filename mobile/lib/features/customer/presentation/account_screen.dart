import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/support_config.dart';
import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/appearance_selector.dart';
import '../../../core/widgets/bocadoo_logo.dart';
import 'customer_controller.dart';
import 'customer_widgets.dart' show CustomerErrorView;
import 'social_widgets.dart';

final customerProfileProvider = FutureProvider.autoDispose<CustomerProfile>((ref) {
  return ref.watch(customerRepositoryProvider).getProfile();
});

IconData _includeIcon(String item) => switch (item.toLowerCase()) {
      'sopa' => Icons.soup_kitchen_outlined,
      'segundo' => Icons.restaurant_rounded,
      'bebida' || 'jugo' => Icons.local_drink_outlined,
      'postre' => Icons.icecream_outlined,
      _ => Icons.check_rounded,
    };

/// C6 · Mi cuenta: perfil, plan habitual, apariencia y ayuda por WhatsApp.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final profile = ref.watch(customerProfileProvider);

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text('Mi cuenta', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: colors.onSurface)),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: profile.when(
            loading: () => const SocialLoading('Cargando tu perfil'),
            error: (_, _) => CustomerErrorView(
              title: 'Error al cargar perfil',
              message: 'No pudimos cargar tus datos.',
              onRetry: () => ref.invalidate(customerProfileProvider),
            ),
            data: (p) => _Body(profile: p),
          ),
        ),
      ]),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.profile});

  final CustomerProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final support = profile.supportWhatsApp.isNotEmpty
        ? whatsAppUri('Hola Bocadoo, necesito ayuda con mi plan en mi restaurante habitual.',
            phone: profile.supportWhatsApp)
        : SupportConfig.link('Hola Bocadoo, necesito ayuda con mi plan.');
    final initial = profile.name.trim().isEmpty ? '?' : profile.name.trim()[0].toUpperCase();

    BoxDecoration card({bool tinted = false}) => BoxDecoration(
          color: tinted ? colors.primaryContainer.withValues(alpha: 0.35) : colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: card(tinted: true),
        child: Row(children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: colors.primary,
            child: Text(initial, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: colors.onPrimary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(profile.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface)),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.phone_outlined, size: 15, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(profile.phone,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SocialLabel('Tu plan habitual'),
          const SizedBox(height: 6),
          Text(profile.habitualPlanName ?? 'Todavía no tienes un plan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface)),
          if (profile.habitualPlanIncludes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final item in profile.habitualPlanIncludes)
                SocialBadge(
                  label: item,
                  icon: _includeIcon(item),
                  background: colors.primaryContainer,
                  foreground: colors.onPrimaryContainer,
                ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SocialLabel('Apariencia'),
          const SizedBox(height: 10),
          const AppearanceSelector(),
        ]),
      ),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: support == null
            ? null
            : () => openExternal(context, support, failMessage: 'No se pudo abrir la ayuda'),
        icon: const Icon(Icons.chat_outlined),
        label: const Text('Ayuda por WhatsApp'),
      ),
      if (support == null) ...[
        const SizedBox(height: 6),
        Text('El contacto de soporte todavía no está configurado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
      ],
      const SizedBox(height: 24),
      const Center(child: BocadooLogo.wordmark(size: 24)),
    ]);
  }
}
