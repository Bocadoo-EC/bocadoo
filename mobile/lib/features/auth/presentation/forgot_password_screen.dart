import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/support_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/external_links.dart';
import '../data/auth_repository.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
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

    final ok = await ref
        .read(authRepositoryProvider)
        .requestPasswordReset(_emailCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sent = ok;
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
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 24, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Recuperar contraseña',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!ApiCapabilities.forgotPassword) ...[
                Text(
                  'Por ahora escríbenos y te ayudamos.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Nuestro equipo verificará tu cuenta y te ayudará a restablecer el acceso.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    hintText: 'ejemplo@correo.ec',
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: SupportConfig.isConfigured
                      ? () {
                          final email = _emailCtrl.text.trim();
                          final msg = email.isEmpty
                              ? 'Hola, necesito recuperar mi contraseña de Bocadoo.'
                              : 'Hola, necesito recuperar mi contraseña de Bocadoo para el correo $email.';
                          final link = SupportConfig.link(msg);
                          if (link != null) {
                            openExternal(
                              context,
                              link,
                              failMessage: 'No se pudo abrir el enlace de soporte.',
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.support_agent_rounded, size: 20),
                  label: const Text('Escribir a soporte'),
                ),
                if (!SupportConfig.isConfigured) ...[
                  const SizedBox(height: 10),
                  Text(
                    'El enlace de soporte aún no está configurado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Volver'),
                ),
              ] else if (!_sent) ...[
                Text(
                  'Ingresa el correo asociado a tu cuenta de restaurante y te enviaremos instrucciones inmediatas.',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: cs.onSurfaceVariant,
                    ),
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
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
                    child: Icon(
                      Icons.check_rounded,
                      size: 36,
                      color: bColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '¡Correo enviado!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
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
