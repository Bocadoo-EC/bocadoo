import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailCtrl;
  bool _loading = false;
  bool _sent = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _emailError = 'Ingresa el correo para continuar.');
      return;
    }
    setState(() {
      _loading = true;
      _emailError = null;
    });
    // TODO: Conectar con provider de backend
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final bColors = context.bocadooColors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.lock_outline_rounded, size: 24, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  'Recuperar contraseña',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                  onPressed: () => context.pop(),
                ),
              ]),

              const SizedBox(height: 24),

              if (!_sent) ...[
                Text(
                  'Ingresa el correo asociado a tu cuenta de restaurante y te enviaremos instrucciones inmediatas.',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
                    hintText: 'ejemplo@correo.ec',
                    errorText: _emailError,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _send,
                  child: _loading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                        )
                      : const Text('Enviar instrucciones'),
                ),
              ] else ...[
                const SizedBox(height: 32),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: bColors.successContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded, size: 36, color: bColors.success),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '¡Correo enviado!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Hemos enviado un enlace y código de verificación a ${_emailCtrl.text.trim()} para restablecer tu contraseña.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Entendido, volver'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
