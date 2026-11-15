import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/google_account_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_diner_screen.dart';
import '../../features/auth/presentation/onboarding_owner_screen.dart';
import '../../features/auth/presentation/register_diner_screen.dart';
import '../../features/auth/presentation/register_owner_screen.dart';
import '../../features/owner/presentation/cash_closing_screen.dart';
import '../../features/owner/presentation/caja_screen.dart';
import '../../features/owner/presentation/oferta_flash_sheet.dart';
import '../../features/owner/presentation/owner_menu_screen.dart';
import '../../features/owner/presentation/owner_settings_screen.dart';
import '../../features/owner/presentation/owner_shell.dart';
import '../../features/owner/presentation/registrar_consumo_screen.dart';
import '../../features/owner/presentation/scanner_screen.dart';
import '../../features/owner/presentation/sell_plan_modal.dart';
import '../../features/customer/presentation/customer_shell.dart';
import '../../features/customer/presentation/pase_screen.dart';
import '../../features/customer/presentation/plan_detail_sheet.dart';
import '../../features/customer/presentation/plans_screen.dart';
import '../../features/customer/presentation/restaurant_sheet.dart';
import '../../features/customer/presentation/restaurants_screen.dart';
import '../widgets/pending_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRoute _pendiente(String path, String titulo) => GoRoute(
      path: path,
      builder: (context, state) => PendingScreen(title: titulo),
    );

/// Configuración central de rutas de navegación con GoRouter.
/// Las rutas de Comensal (/customer/*) y Dueño (/owner/*) apuntan inicialmente a
/// placeholders limpios mientras James y Carlos implementan sus fases en sus respectivas ramas.
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
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
    // Comensal: Pase, Restaurantes, Planes y Yo comparten la barra inferior
    ShellRoute(
      builder: (context, state, child) => CustomerShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/customer/pase',
          name: 'customer_pase',
          builder: (context, state) => const PaseScreen(),
        ),
        GoRoute(
          path: '/customer/restaurants',
          name: 'customer_restaurants',
          builder: (context, state) => const RestaurantsScreen(),
          routes: [
            GoRoute(
              path: ':restaurantId',
              name: 'customer_restaurant_detail',
              parentNavigatorKey: _rootNavigatorKey,
              pageBuilder: (context, state) => BottomSheetPage(
                key: state.pageKey,
                child: RestaurantSheet(restaurantId: state.pathParameters['restaurantId']!),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/customer/planes',
          name: 'customer_planes',
          builder: (context, state) => const PlansScreen(),
          routes: [
            GoRoute(
              path: ':planId',
              name: 'customer_plan_detail',
              parentNavigatorKey: _rootNavigatorKey,
              pageBuilder: (context, state) => BottomSheetPage(
                key: state.pageKey,
                child: PlanDetailSheet(planId: state.pathParameters['planId']!),
              ),
            ),
          ],
        ),
        _pendiente('/customer/cuenta', 'Mi cuenta'),
      ],
    ),
    // Dueño: Caja, Menú, Planes, Métricas y Ajustes comparten la barra inferior
    ShellRoute(
      builder: (context, state, child) => OwnerShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/owner/caja',
          name: 'owner_caja',
          builder: (context, state) => const CajaScreen(),
        ),
        GoRoute(
          path: '/owner/registrar-consumo',
          name: 'owner_registrar_consumo',
          builder: (context, state) => const RegistrarConsumoScreen(),
        ),
        // "Cobro suelto" en Caja abre el POS (decisión D1 de la ficha de Fase 3)
        GoRoute(
          path: '/owner/cobro-suelto',
          name: 'owner_cobro_suelto',
          builder: (context, state) => const RegistrarConsumoScreen(),
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
        _pendiente('/owner/planes', 'Planes y clientes'),
        _pendiente('/owner/metricas', 'Métricas'),
        GoRoute(
          path: '/owner/settings',
          name: 'owner_settings',
          builder: (context, state) => const OwnerSettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/owner/scanner',
      name: 'owner_scanner',
      builder: (context, state) => const ScannerScreen(),
    ),
    // El resultado se muestra como tarjeta flotante sobre Caja (ver openScannerFlow)
    GoRoute(
      path: '/owner/scan-result',
      name: 'owner_scan_result',
      redirect: (context, state) => '/owner/caja',
    ),
    GoRoute(
      path: '/owner/vender-plan',
      name: 'owner_vender_plan',
      pageBuilder: (context, state) => OwnerSheetPage(
        key: state.pageKey,
        child: SellPlanSheet(initialClientName: state.extra as String?),
      ),
    ),
    GoRoute(
      path: '/owner/oferta-flash',
      name: 'owner_oferta_flash',
      pageBuilder: (context, state) => OwnerSheetPage(
        key: state.pageKey,
        child: const FlashOfferSheet(),
      ),
    ),
    // Auth – Fase 1 implementada
    GoRoute(
      path: '/auth/olvide-contrasena',
      name: 'auth_olvide_contrasena',
      builder: (context, state) => ForgotPasswordScreen(
        initialEmail: state.extra as String?,
      ),
    ),
    GoRoute(
      path: '/auth/google',
      name: 'auth_google',
      builder: (context, state) => GoogleAccountScreen(
        role: (state.extra as String?) ?? 'customer',
      ),
    ),
    GoRoute(
      path: '/auth/registro/comensal',
      name: 'auth_registro_comensal',
      builder: (context, state) => const RegisterDinerScreen(),
    ),
    GoRoute(
      path: '/auth/registro/dueno',
      name: 'auth_registro_dueno',
      builder: (context, state) => const RegisterOwnerScreen(),
    ),
    GoRoute(
      path: '/auth/bienvenida/comensal',
      name: 'auth_bienvenida_comensal',
      builder: (context, state) {
        final extra = state.extra as Map<String, String>?;
        return OnboardingDinerScreen(
          nombre: extra?['nombre'] ?? 'comensal',
          zona: extra?['zona'] ?? 'Quito',
        );
      },
    ),
    GoRoute(
      path: '/auth/bienvenida/dueno',
      name: 'auth_bienvenida_dueno',
      builder: (context, state) => OnboardingOwnerScreen(
        precioBase: (state.extra as double?) ?? 3.50,
      ),
    ),
    // Customer (pendientes)
    _pendiente('/customer/mesa', 'Mesa con amigos'),
    _pendiente('/customer/mesa/:mesaId', 'Unirme a mesa'),
    _pendiente('/customer/pedido/:orderId', 'Estado del pedido'),
    _pendiente('/customer/calificar/:orderId', 'Calificar almuerzo'),
    _pendiente('/customer/mapa', 'Mapa'),
    // Owner (pendientes)
    _pendiente('/owner/cobrar-mesa/:mesaId', 'Cobrar mesa'),
    _pendiente('/owner/planes/nuevo', 'Nuevo plan'),
    _pendiente('/owner/planes/:planId/editar', 'Editar plan'),
    _pendiente('/owner/cartulina', 'Pasar cartulina'),
    _pendiente('/owner/pedidos', 'Pedidos en camino'),
    _pendiente('/owner/opiniones', 'Opiniones'),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Ruta no encontrada: ${state.uri}'),
    ),
  ),
);
