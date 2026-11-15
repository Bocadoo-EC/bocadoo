import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

/// "Continuar con Google": sin pantalla intermedia de cuentas. Entra directo al
/// inicio de sesión de Google del teléfono y, al volver, enruta según el rol.
///
/// [role] es `customer` u `owner`.
// TODO: Conectar con provider de backend. Con el paquete `google_sign_in` (aún
// sin aprobar) este método abre el selector de cuentas nativo de Android y
// manda el token a la API; hoy simula el inicio de sesión y entra.
Future<void> continueWithGoogle(BuildContext context, {required String role}) async {
  final router = GoRouter.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const _GoogleProgress(),
  );
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (navigator.mounted && navigator.canPop()) navigator.pop();
  router.go(role == 'customer' ? '/customer/pase' : '/owner/caja');
}

class _GoogleProgress extends StatelessWidget {
  const _GoogleProgress();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Flexible(
              child: Text('Conectando con Google',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.onSurface)),
            ),
          ]),
        ),
      ),
    );
  }
}
