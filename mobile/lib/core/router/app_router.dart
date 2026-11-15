import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_diner_screen.dart';
import '../../features/auth/presentation/onboarding_owner_screen.dart';
import '../../features/auth/presentation/register_diner_screen.dart';
import '../../features/auth/presentation/register_owner_screen.dart';
import '../../features/owner/presentation/add_client_sheet.dart';
import '../../features/owner/presentation/cartulina_sheet.dart';
import '../../features/owner/presentation/cash_closing_screen.dart';
import '../../features/owner/presentation/caja_screen.dart';
import '../../features/owner/presentation/cobrar_mesa_sheet.dart';
import '../../features/owner/presentation/oferta_flash_sheet.dart';
import '../../features/owner/presentation/opiniones_screen.dart';
import '../../features/owner/presentation/owner_menu_screen.dart';
import '../../features/owner/presentation/owner_metrics_screen.dart';
import '../../features/owner/presentation/owner_plans_screen.dart';
import '../../features/owner/presentation/owner_settings_screen.dart';
import '../../features/owner/presentation/owner_shell.dart';
import '../../features/owner/presentation/pedidos_screen.dart';
import '../../features/owner/presentation/plan_editor_sheet.dart';
import '../../features/owner/presentation/registrar_consumo_screen.dart';
import '../../features/owner/presentation/scanner_screen.dart';
import '../../features/owner/presentation/sell_plan_modal.dart';
import '../../features/customer/presentation/account_screen.dart';
import '../../features/customer/presentation/customer_shell.dart';
import '../../features/customer/presentation/join_table_screen.dart';
import '../../features/customer/presentation/map_screen.dart';
import '../../features/customer/presentation/order_status_sheet.dart';
import '../../features/customer/presentation/table_sheet.dart';
import '../../features/customer/presentation/pase_screen.dart';
import '../../features/customer/presentation/plan_detail_sheet.dart';
import '../../features/customer/presentation/plans_screen.dart';
import '../../features/customer/presentation/restaurant_sheet.dart';
import '../../features/customer/presentation/restaurants_screen.dart';
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Configuración central de rutas de navegación con GoRouter. Las 34 pantallas
/// del roadmap tienen su pantalla real; no quedan marcadores de "pendiente".
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
        GoRoute(
          path: '/customer/cuenta',
          name: 'customer_cuenta',
          builder: (context, state) => const AccountScreen(),
        ),
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
        GoRoute(
          path: '/owner/planes',
          name: 'owner_planes',
          builder: (context, state) => const OwnerPlansScreen(),
        ),
        GoRoute(
          path: '/owner/metricas',
          name: 'owner_metricas',
          builder: (context, state) => const OwnerMetricsScreen(),
        ),
        GoRoute(
          path: '/owner/settings',
          name: 'owner_settings',
          builder: (context, state) => const OwnerSettingsScreen(),
        ),
        // O12 · Pedidos en camino. `?cobrar=N` abre el cobro (QR BCD-ORD-…).
        GoRoute(
          path: '/owner/pedidos',
          name: 'owner_pedidos',
          builder: (context, state) => PedidosScreen(chargeNumber: state.uri.queryParameters['cobrar']),
        ),
        // O15 · Opiniones (desde Ajustes o Métricas)
        GoRoute(
          path: '/owner/opiniones',
          name: 'owner_opiniones',
          builder: (context, state) => const OpinionesScreen(),
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
    // Customer · Fase 5 (social)
    GoRoute(
      path: '/customer/mesa',
      name: 'customer_mesa',
      pageBuilder: (context, state) => BottomSheetPage(
        key: state.pageKey,
        child: TableSheet(restaurantId: state.uri.queryParameters['restaurantId']),
      ),
    ),
    GoRoute(
      path: '/customer/mesa/:mesaId',
      name: 'customer_unirme_mesa',
      builder: (context, state) => JoinTableScreen(tableId: state.pathParameters['mesaId']!),
    ),
    GoRoute(
      path: '/customer/pedido/:orderId',
      name: 'customer_pedido',
      pageBuilder: (context, state) => BottomSheetPage(
        key: state.pageKey,
        child: OrderStatusSheet(orderId: state.pathParameters['orderId']!),
      ),
    ),
    // C10 es una tarjeta sobre Mi Pase, no una pantalla propia.
    GoRoute(
      path: '/customer/calificar/:orderId',
      name: 'customer_calificar',
      redirect: (context, state) => '/customer/pase',
    ),
    // C11 · Mapa con ruta a pie dentro de la app
    GoRoute(
      path: '/customer/mapa',
      name: 'customer_mapa',
      builder: (context, state) => const MapScreen(),
    ),
    // O5 · Cobrar mesa (banner de Caja o QR BCD-MESA-… en el escáner)
    GoRoute(
      path: '/owner/cobrar-mesa/:mesaId',
      name: 'owner_cobrar_mesa',
      pageBuilder: (context, state) => OwnerSheetPage(
        key: state.pageKey,
        child: CobrarMesaSheet(tableId: state.pathParameters['mesaId']!),
      ),
    ),
    GoRoute(
      path: '/owner/planes/nuevo',
      name: 'owner_plan_nuevo',
      pageBuilder: (context, state) => OwnerSheetPage(
        key: state.pageKey,
        child: const PlanEditorSheet(),
      ),
    ),
    GoRoute(
      path: '/owner/planes/:planId/editar',
      name: 'owner_plan_editar',
      pageBuilder: (context, state) => OwnerSheetPage(
        key: state.pageKey,
        child: PlanEditorSheet(planId: state.pathParameters['planId']),
      ),
    ),
    // O8 · Agregar cliente (botón + de Clientes)
    GoRoute(
      path: '/owner/clientes/nuevo',
      name: 'owner_cliente_nuevo',
      pageBuilder: (context, state) => OwnerSheetPage<AddedClient>(
        key: state.pageKey,
        child: const AddClientSheet(),
      ),
    ),
    // O10 · Pasar cartulina (desde Ajustes)
    GoRoute(
      path: '/owner/cartulina',
      name: 'owner_cartulina',
      pageBuilder: (context, state) => OwnerSheetPage(
        key: state.pageKey,
        child: const CartulinaSheet(),
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Ruta no encontrada: ${state.uri}'),
    ),
  ),
);
