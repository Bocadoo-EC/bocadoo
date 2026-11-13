import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

/// Pantalla de Autenticación / Selección de Rol para Bocadoo
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum UserRole { customer, owner }

class _LoginScreenState extends State<LoginScreen> {
  UserRole _selectedRole = UserRole.customer;
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _fillDemoCredentials(UserRole.customer);
  }

  void _fillDemoCredentials(UserRole role) {
    if (role == UserRole.customer) {
      _identifierController.text = 'carlos.mejia@email.com';
      _passwordController.text = 'Password123!';
    } else {
      _identifierController.text = 'maria@lacuchara.ec';
      _passwordController.text = 'Password123!';
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onRoleChanged(UserRole role) {
    setState(() {
      _selectedRole = role;
      _fillDemoCredentials(role);
    });
  }

  void _onLogin() {
    if (_selectedRole == UserRole.customer) {
      context.go('/customer/pase');
    } else {
      context.go('/owner/scanner');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;
    final isCustomer = _selectedRole == UserRole.customer;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Logo Bocadoo con identidad visual oficial
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.restaurant_menu_rounded,
                        color: colors.onPrimary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'bocadoo',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          'tu almuerzo, más fácil',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // Selector de rol (Comensal / Dueño)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _onRoleChanged(UserRole.customer),
                        borderRadius:
                            BorderRadius.circular(AppTheme.buttonRadius),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isCustomer ? colors.primary : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(AppTheme.buttonRadius),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.school_rounded,
                                size: 18,
                                color: isCustomer
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Comensal',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isCustomer
                                      ? colors.onPrimary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _onRoleChanged(UserRole.owner),
                        borderRadius:
                            BorderRadius.circular(AppTheme.buttonRadius),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !isCustomer ? colors.primary : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(AppTheme.buttonRadius),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.storefront_rounded,
                                size: 18,
                                color: !isCustomer
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Dueño',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: !isCustomer
                                      ? colors.onPrimary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Tarjeta informativa del rol
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.primary,
                      radius: 20,
                      child: Icon(
                        isCustomer
                            ? Icons.qr_code_2_rounded
                            : Icons.point_of_sale_rounded,
                        color: colors.onPrimary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCustomer
                                ? 'Pase de Almuerzos Digital'
                                : 'Punto de Venta y Arqueo',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                          Text(
                            isCustomer
                                ? 'Canjea en segundos sin filas ni tarjetas'
                                : 'Escanea códigos QR y cuadra tu caja diaria',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Formulario de ingreso
              Text(
                'Correo o usuario',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _identifierController,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.alternate_email_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                  hintText: isCustomer
                      ? 'carlos.mejia@email.com'
                      : 'maria@lacuchara.ec',
                ),
              ),

              const SizedBox(height: 18),

              Text(
                'Contraseña',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Botón de ingreso principal
              ElevatedButton(
                onPressed: _onLogin,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isCustomer
                          ? 'Ingresar como Comensal'
                          : 'Ingresar como Dueño',
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Acceso rápido de demostración
              Row(
                children: [
                  Expanded(child: Divider(color: colors.outlineVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Acceso rápido demo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: colors.outlineVariant)),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _onRoleChanged(UserRole.customer);
                        _onLogin();
                      },
                      icon: const Icon(Icons.person_rounded, size: 18),
                      label: const Text(
                        'Demo Carlos',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _onRoleChanged(UserRole.owner);
                        _onLogin();
                      },
                      icon: const Icon(Icons.store_rounded, size: 18),
                      label: const Text(
                        'Demo María',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Pie con términos y protección
              Center(
                child: Text(
                  'Bocadoo · Red Universitaria de Almuerzos',
                  style: TextStyle(
                    fontSize: 12,
                    color: bColor.mutedForegroundIfAny(colors.onSurfaceVariant),
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

extension _ColorHelper on BocadooColors {
  Color mutedForegroundIfAny(Color fallback) => fallback;
}

