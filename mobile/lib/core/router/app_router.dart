import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/owner/presentation/cash_closing_screen.dart';
import '../../features/owner/presentation/owner_menu_screen.dart';
import '../../features/owner/presentation/owner_settings_screen.dart';
import '../../features/owner/presentation/scan_result_screen.dart';
import '../../features/owner/presentation/scanner_screen.dart';
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
      builder: (context, state) => const ScannerScreen(),
    ),
    GoRoute(
      path: '/owner/scan-result',
      name: 'owner_scan_result',
      builder: (context, state) => const ScanResultScreen(),
    ),
    GoRoute(
      path: '/owner/cash-closing',
      name: 'owner_cash_closing',
      builder: (context, state) => const CashClosingScreen(),
    ),
    GoRoute(
      path: '/owner/menu',
      name: 'owner_menu',
      builder: (context, state) => const OwnerMenuScreen(),
    ),
    GoRoute(
      path: '/owner/settings',
      name: 'owner_settings',
      builder: (context, state) => const OwnerSettingsScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Ruta no encontrada: ${state.uri}'),
    ),
  ),
);
