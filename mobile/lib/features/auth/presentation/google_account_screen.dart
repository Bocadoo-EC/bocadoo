import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

class GoogleAccountScreen extends StatelessWidget {
  final String role; // 'customer' or 'owner'

  const GoogleAccountScreen({super.key, required this.role});

  static const _accounts = [
    _Account('Carlos Mejía', 'carlos.mejia@gmail.com', 'customer', 'Comensal Bocadoo'),
    _Account('María Toapanta', 'maria.toapanta@gmail.com', 'owner', 'La Cuchara de San Blas'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    void navigate() {
      // TODO: Conectar con provider de backend (autenticación con Google)
      if (role == 'customer') {
        context.go('/customer/pase');
      } else {
        context.go('/owner/caja');
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      'G',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Acceder con Google',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                  onPressed: () => context.pop(),
                ),
              ]),

              const SizedBox(height: 8),

              Text(
                'Selecciona una cuenta para continuar en Bocadoo Ecuador',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),

              const SizedBox(height: 20),

              ...(_accounts.map((acc) => _AccountTile(
                    account: acc,
                    isRecommended: acc.role == role,
                    onTap: navigate,
                  ))),

              const SizedBox(height: 8),

              OutlinedButton.icon(
                onPressed: navigate,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Usar otra cuenta de Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Account {
  final String name;
  final String email;
  final String role;
  final String label;

  const _Account(this.name, this.email, this.role, this.label);
}

class _AccountTile extends StatelessWidget {
  final _Account account;
  final bool isRecommended;
  final VoidCallback onTap;

  const _AccountTile({required this.account, required this.isRecommended, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRecommended ? cs.primaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            border: Border.all(
              color: isRecommended ? cs.primary : cs.outlineVariant,
              width: isRecommended ? 2 : 1,
            ),
          ),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: cs.primary,
              radius: 20,
              child: Text(
                account.name[0],
                style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  account.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                Text(
                  account.email,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                Text(
                  account.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
                ),
              ]),
            ),
            if (isRecommended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Text(
                  'Recomendada',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimary),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
