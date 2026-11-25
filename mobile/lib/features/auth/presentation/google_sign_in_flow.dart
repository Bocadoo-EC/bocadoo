import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';

/// "Continuar con Google": sin pantalla intermedia de cuentas.
///
/// [role] es `customer` u `owner`.
Future<void> continueWithGoogle(
  BuildContext context, {
  required String role,
}) async {
  final repo = ProviderScope.containerOf(context, listen: false).read(
    authRepositoryProvider,
  );

  if (!ApiCapabilities.googleSignIn) {
    final result = await repo.signInWithGoogle(role: role);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.errorMessage ??
              'El acceso con Google estará disponible pronto. Entra con tu correo.',
        ),
      ),
    );
    return;
  }

  final router = GoRouter.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const _GoogleProgress(),
  );
  final result = await repo.signInWithGoogle(role: role);
  if (navigator.mounted && navigator.canPop()) {
    navigator.pop();
  }
  if (!context.mounted) return;
  if (result.ok) {
    router.go(
      role == 'customer'
          ? resolvePostDinerAuthLocation(router)
          : '/owner/caja',
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.errorMessage ??
              'El acceso con Google estará disponible pronto. Entra con tu correo.',
        ),
      ),
    );
  }
}

class _GoogleProgress extends StatelessWidget {
  const _GoogleProgress();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  'Conectando con Google',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
