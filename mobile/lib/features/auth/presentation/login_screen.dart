import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

enum _UserRole { customer, owner }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _UserRole _role = _UserRole.customer;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _emailError;
  String? _passError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _changeRole(_UserRole r) {
    setState(() {
      _role = r;
      _emailError = null;
      _passError = null;
    });
  }

  bool _validate() {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final eErr = email.isEmpty
        ? 'Ingresa tu correo electrónico para continuar.'
        : !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
            ? 'Por favor ingresa un correo electrónico válido (ej: nombre@correo.ec)'
            : null;
    final pErr = pass.isEmpty ? 'Por favor ingresa tu contraseña.' : null;
    setState(() {
      _emailError = eErr;
      _passError = pErr;
    });
    return eErr == null && pErr == null;
  }

  Future<void> _login() async {
    if (!_validate()) return;
    setState(() => _loading = true);
    // TODO: Conectar con provider de backend
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _loading = false);
    if (_role == _UserRole.customer) {
      context.go('/customer/pase');
    } else {
      context.go('/owner/caja');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final isCustomer = _role == _UserRole.customer;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Espacio reservado para el logo oficial de Bocadoo
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.restaurant_menu_rounded, color: cs.onPrimary, size: 26),
                ),
              ),

              const SizedBox(height: 20),

              Center(
                child: Column(children: [
                  Text(
                    'Tu almuerzo,',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: cs.onSurface),
                  ),
                  Text(
                    'sin cartulinas.',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: cs.primary),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              Center(
                child: Text(
                  isCustomer
                      ? 'Planes simples. Valida tu almuerzo con QR en Quito.'
                      : 'Gestiona comensales, planes prepagados y cobros QR.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                ),
              ),

              const SizedBox(height: 24),

              // Tabs Comensal / Dueño
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Row(children: [
                  _Tab(
                    label: 'Comensal',
                    icon: Icons.person_rounded,
                    selected: isCustomer,
                    onTap: () => _changeRole(_UserRole.customer),
                  ),
                  _Tab(
                    label: 'Dueño',
                    icon: Icons.storefront_rounded,
                    selected: !isCustomer,
                    onTap: () => _changeRole(_UserRole.owner),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              // Badge de rol
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      isCustomer ? Icons.credit_card_rounded : Icons.point_of_sale_rounded,
                      size: 15,
                      color: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isCustomer ? 'PASE COMENSAL' : 'TERMINAL RESTAURANTE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'CORREO ELECTRÓNICO',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
                  hintText: isCustomer ? 'carlos@email.com' : 'maria@lacuchara.ec',
                  errorText: _emailError,
                  suffixIcon: _emailCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                          onPressed: () => setState(() => _emailCtrl.clear()),
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 16),

              Text(
                'CONTRASEÑA',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
                  hintText: '••••••••',
                  errorText: _passError,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/auth/olvide-contrasena', extra: _emailCtrl.text.trim()),
                  child: Text(
                    '¿Olvidaste tu contraseña?',
                    style: TextStyle(fontSize: 13, color: cs.primary),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                      )
                    : const Text('Iniciar sesión'),
              ),

              const SizedBox(height: 20),

              Row(children: [
                Expanded(child: Divider(color: cs.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ó', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                ),
                Expanded(child: Divider(color: cs.outlineVariant)),
              ]),

              const SizedBox(height: 16),

              OutlinedButton.icon(
                onPressed: () => context.push('/auth/google', extra: isCustomer ? 'customer' : 'owner'),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Continuar con Google'),
              ),

              const SizedBox(height: 24),

              Center(
                child: Wrap(alignment: WrapAlignment.center, children: [
                  Text(
                    '¿Primera vez en Bocadoo? ',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  GestureDetector(
                    onTap: () => isCustomer
                        ? context.push('/auth/registro/comensal')
                        : context.push('/auth/registro/dueno'),
                    child: Text(
                      isCustomer ? 'Crear cuenta de Comensal' : 'Registrar mi Restaurante',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 20),

              Center(
                child: Text(
                  'BCD-PASS •••• 9412        QUITO · 2026',
                  style: TextStyle(fontSize: 11, color: cs.outlineVariant),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primary : null,
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: selected ? cs.onPrimary : cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
