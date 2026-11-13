import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/customer/presentation/customer_plans_screen.dart';
import '../../features/customer/presentation/customer_profile_screen.dart';
import '../../features/customer/presentation/pase_screen.dart';
import '../../features/customer/presentation/restaurants_screen.dart';
import '../../features/owner/presentation/cash_closing_screen.dart';
import '../../features/owner/presentation/owner_menu_screen.dart';
import '../../features/owner/presentation/owner_metrics_screen.dart';
import '../../features/owner/presentation/owner_orders_screen.dart';
import '../../features/owner/presentation/owner_plans_screen.dart';
import '../../features/owner/presentation/owner_settings_screen.dart';
import '../../features/owner/presentation/scan_result_screen.dart';
import '../../features/owner/presentation/scanner_screen.dart';
import '../auth/auth_models.dart';
import '../auth/auth_provider.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// Provider de GoRouter protegido por estado de autenticación y rol.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen<AuthState>(authProvider, (_, _) => refreshNotifier.refresh());

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final user = authState.user;
      final location = state.matchedLocation;
      final isLoggingIn = location == '/login' || location == '/';

      if (user == null) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggingIn) {
        return user.role.isStaff ? '/owner/scanner' : '/customer/pase';
      }

      if (location.startsWith('/customer') && user.role.isStaff) {
        return '/owner/scanner';
      }

      if (location.startsWith('/owner') && !user.role.isStaff) {
        return '/customer/pase';
      }

      return null;
    },
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
      GoRoute(
        path: '/customer/plans',
        name: 'customer_plans',
        builder: (context, state) => const CustomerPlansScreen(),
      ),
      GoRoute(
        path: '/customer/profile',
        name: 'customer_profile',
        builder: (context, state) => const CustomerProfileScreen(),
      ),
      // Rutas Dueño / Caja (Owner / Cashier)
      GoRoute(
        path: '/owner/scanner',
        name: 'owner_scanner',
        builder: (context, state) => const ScannerScreen(),
      ),
      GoRoute(
        path: '/owner/menu',
        name: 'owner_menu',
        builder: (context, state) => const OwnerMenuScreen(),
      ),
      GoRoute(
        path: '/owner/plans',
        name: 'owner_plans',
        builder: (context, state) => const OwnerPlansScreen(),
      ),
      GoRoute(
        path: '/owner/metrics',
        name: 'owner_metrics',
        builder: (context, state) => const OwnerMetricsScreen(),
      ),
      GoRoute(
        path: '/owner/orders',
        name: 'owner_orders',
        builder: (context, state) => const OwnerOrdersScreen(),
      ),
      GoRoute(
        path: '/owner/settings',
        name: 'owner_settings',
        builder: (context, state) => const OwnerSettingsScreen(),
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
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Ruta no encontrada: ${state.uri}'),
      ),
    ),
  );
});
