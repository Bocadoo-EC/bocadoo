import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/customer/presentation/pase_screen.dart';
import '../../features/customer/presentation/restaurants_screen.dart';

/// Configuración central de rutas de navegación con GoRouter.
/// Las rutas de Comensal (/customer/*) y Dueño (/owner/*) apuntan inicialmente a
/// placeholders limpios mientras James y Carlos implementan sus fases en sus respectivas ramas.
final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      redirect: (context, state) => '/login',
    ),
    // Rutas Comensal (Customer)
    GoRoute(
      path: '/customer/pase',
      name: 'customer_pase',
      builder: (context, state) => const PaseScreen(),
    ),
    GoRoute(
      path: '/customer/restaurants',
      name: 'customer_restaurants',
      builder: (context, state) => const RestaurantsScreen(),
    ),
    // Rutas Dueño (Owner)
    GoRoute(
      path: '/owner/scanner',
      name: 'owner_scanner',
      builder: (context, state) => const _RoutePlaceholder(
        title: 'Escáner QR Dueño',
        routePath: '/owner/scanner',
        subtitle: 'Fase O3 (Carlos): scanner_screen.dart',
      ),
    ),
    GoRoute(
      path: '/owner/scan-result',
      name: 'owner_scan_result',
      builder: (context, state) => const _RoutePlaceholder(
        title: 'Resultado de Escaneo',
        routePath: '/owner/scan-result',
        subtitle: 'Fase O4 (Carlos): scan_result_screen.dart',
      ),
    ),
    GoRoute(
      path: '/owner/cash-closing',
      name: 'owner_cash_closing',
      builder: (context, state) => const _RoutePlaceholder(
        title: 'Cierre de Caja',
        routePath: '/owner/cash-closing',
        subtitle: 'Fase O5 (Carlos): cash_closing_screen.dart',
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Ruta no encontrada: ${state.uri}'),
    ),
  ),
);

/// Placeholder temporal para rutas en desarrollo paralelo
class _RoutePlaceholder extends StatelessWidget {
  final String title;
  final String routePath;
  final String subtitle;

  const _RoutePlaceholder({
    required this.title,
    required this.routePath,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.construction_rounded,
                  size: 40,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Volver al Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

