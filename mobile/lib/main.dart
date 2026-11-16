import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/analytics/events_service.dart';
import 'core/router/app_router.dart';
import 'core/session/session_notifier.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final prevFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    eventsService.trackError(
      'app.error_flutter',
      dedupeKey: details.exception.runtimeType.toString(),
      props: {
        'tipo_error': details.exception.runtimeType.toString(),
        'origen': ?details.library,
      },
    );
    prevFlutterError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    eventsService.trackError(
      'app.error_async',
      dedupeKey: error.runtimeType.toString(),
      props: {'tipo_error': error.runtimeType.toString()},
    );
    return false;
  };
  eventsService.startLifecycleMonitoring();
  unawaited(sessionNotifier.loadFromStorage());
  runApp(
    const ProviderScope(
      child: BocadooApp(),
    ),
  );
}

class BocadooApp extends ConsumerWidget {
  const BocadooApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Bocadoo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
