import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';

/// Modos del formulario de acceso.
enum _AuthMode { login, register }

/// Pantalla oficial de Inicio de Sesión y Registro de Bocadoo.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _restaurantController = TextEditingController();
  final _basePriceController = TextEditingController(text: '2,75');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  static const List<String> _zones = [
    'La Floresta',
    'González Suárez',
    'Iñaquito',
    'Centro Histórico',
    'Cumbayá',
  ];

  _AuthMode _mode = _AuthMode.login;
  AuthRole _selectedRole = AuthRole.customer;
  String _selectedZone = _zones.first;
  bool _obscurePassword = true;
  String? _localError;

  @override
  void dispose() {
    _nameController.dispose();
    _restaurantController.dispose();
    _basePriceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showForgotPasswordModal() {
    final resetEmail = TextEditingController(text: _emailController.text.trim());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final colors = theme.colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recuperar contraseña',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Ingresa el correo de tu cuenta y te enviaremos un enlace para restablecer tu acceso.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: resetEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 20),
              BocadooButton(
                label: 'Enviar enlace',
                icon: Icons.send_rounded,
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Si tu correo está registrado, recibirás instrucciones en breve.',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    ).whenComplete(resetEmail.dispose);
  }

  void _switchMode(_AuthMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _localError = null;
    });
  }

  void _selectRole(AuthRole role) {
    if (_selectedRole == role) return;
    setState(() {
      _selectedRole = role;
      _localError = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _localError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final useRemote = ref.read(useRemoteApiProvider);
    final notifier = ref.read(authProvider.notifier);

    if (!useRemote) {
      await notifier.loginDemo(
        _selectedRole,
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      context.go(
        _selectedRole.isStaff ? '/owner/scanner' : '/customer/pase',
      );
      return;
    }

    final bool ok;
    if (_mode == _AuthMode.login) {
      ok = await notifier.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } else {
      ok = await notifier.register(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _selectedRole,
        restaurantName: _selectedRole == AuthRole.owner
            ? _restaurantController.text.trim()
            : null,
      );
    }

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _localError = ref.read(authProvider).errorMessage;
      });
      return;
    }

    final user = ref.read(authProvider).user;
    if (user != null) {
      context.go(user.role.isStaff ? '/owner/scanner' : '/customer/pase');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;
    final authState = ref.watch(authProvider);
    final isRegister = _mode == _AuthMode.register;
    final errorText = _localError ?? authState.errorMessage;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerRight,
                  child: ThemeToggle.compact(),
                ),
                const SizedBox(height: 8),

                // Marca oficial Bocadoo
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
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'tu almuerzo, más fácil',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Selector Iniciar sesión / Crear cuenta
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      _SegmentPill(
                        label: 'Iniciar sesión',
                        selected: !isRegister,
                        onTap: () => _switchMode(_AuthMode.login),
                      ),
                      _SegmentPill(
                        label: 'Crear cuenta',
                        selected: isRegister,
                        onTap: () => _switchMode(_AuthMode.register),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Tarjeta principal de acceso
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tu rol',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _RoleOption(
                              label: 'Comensal',
                              icon: Icons.person_outline_rounded,
                              selected: _selectedRole == AuthRole.customer,
                              onTap: () => _selectRole(AuthRole.customer),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _RoleOption(
                              label: 'Dueño',
                              icon: Icons.storefront_rounded,
                              selected: _selectedRole == AuthRole.owner,
                              onTap: () => _selectRole(AuthRole.owner),
                            ),
                          ),
                        ],
                      ),

                      if (isRegister) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Nombre completo',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Ej. Carlos Mejía',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            if (!isRegister) return null;
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu nombre.';
                            }
                            return null;
                          },
                        ),
                        if (_selectedRole == AuthRole.owner) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Nombre del local',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _restaurantController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'Ej. La Cuchara de San Blas',
                              prefixIcon: Icon(Icons.store_outlined),
                            ),
                            validator: (value) {
                              if (!isRegister ||
                                  _selectedRole != AuthRole.owner) {
                                return null;
                              }
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingresa el nombre de tu local.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Precio habitual del almuerzo (USD)',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _basePriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'Ej. 2,75',
                              prefixIcon: Icon(Icons.attach_money_rounded),
                            ),
                            validator: (value) {
                              if (!isRegister ||
                                  _selectedRole != AuthRole.owner) {
                                return null;
                              }
                              final parsed = double.tryParse(
                                (value ?? '').trim().replaceAll(',', '.'),
                              );
                              if (parsed == null || parsed <= 0) {
                                return 'Ingresa un precio válido (ej. 2,75).';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          _selectedRole == AuthRole.owner
                              ? 'Zona del local'
                              : 'Tu zona habitual',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _zones
                              .map(
                                (z) => ChoiceChip(
                                  label: Text(z),
                                  selected: _selectedZone == z,
                                  onSelected: (_) =>
                                      setState(() => _selectedZone = z),
                                ),
                              )
                              .toList(),
                        ),
                      ],

                      const SizedBox(height: 18),
                      Text(
                        'Correo',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: _selectedRole == AuthRole.customer
                              ? 'tu.correo@puce.edu.ec'
                              : 'dueno@tulocal.ec',
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'Ingresa tu correo.';
                          }
                          if (!trimmed.contains('@') ||
                              !trimmed.contains('.')) {
                            return 'Ingresa un correo válido.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),
                      Text(
                        'Contraseña',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'Mínimo 6 caracteres',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa tu contraseña.';
                          }
                          if (value.length < 6) {
                            return 'Mínimo 6 caracteres.';
                          }
                          return null;
                        },
                      ),

                      if (errorText != null && errorText.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bColor.dangerContainer,
                            borderRadius:
                                BorderRadius.circular(AppTheme.inputRadius),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 20,
                                color: bColor.onDangerContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  errorText,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: bColor.onDangerContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 22),
                      BocadooButton(
                        label: isRegister ? 'Crear cuenta' : 'Iniciar sesión',
                        icon: Icons.arrow_forward_rounded,
                        isLoading: authState.isLoading,
                        onPressed: _submit,
                      ),
                      if (!isRegister) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: _showForgotPasswordModal,
                            child: Text(
                              '¿Olvidaste tu contraseña?',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Expanded(
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
