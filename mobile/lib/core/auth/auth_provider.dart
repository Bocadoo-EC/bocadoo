import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

/// Repositorio global de autenticación.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final storage = ref.watch(tokenStorageProvider);
  return AuthRepository(dio: dio, tokenStorage: storage);
});

/// Provider global del estado de sesión y rol del usuario.
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  bool _disposed = false;

  @override
  AuthState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    final restored = await ref.read(authRepositoryProvider).restoreSession();
    if (_disposed) return;
    state = state.copyWith(
      isInitialized: true,
      user: restored,
    );
  }

  Future<bool> login({
    required String email,
    required String password,
    AuthRole? demoFallbackRole,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await ref.read(authRepositoryProvider).login(
            email: email,
            password: password,
            demoFallbackRole: demoFallbackRole,
          );
      if (_disposed) return true;
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        user: user,
        errorMessage: null,
      );
      return true;
    } on NetworkException catch (e) {
      if (_disposed) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
      return false;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No pudimos iniciar sesión. Intenta de nuevo.',
      );
      return false;
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required AuthRole role,
    String? restaurantName,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await ref.read(authRepositoryProvider).register(
            fullName: fullName,
            email: email,
            password: password,
            role: role,
            restaurantName: restaurantName,
          );
      if (_disposed) return true;
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        user: user,
        errorMessage: null,
      );
      return true;
    } on NetworkException catch (e) {
      if (_disposed) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
      return false;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No pudimos crear tu cuenta. Intenta de nuevo.',
      );
      return false;
    }
  }

  Future<void> loginDemo(AuthRole role, {String? email}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final user = await ref.read(authRepositoryProvider).loginDemo(
          role: role,
          email: email,
        );
    if (_disposed) return;
    state = state.copyWith(
      isInitialized: true,
      isLoading: false,
      user: user,
      errorMessage: null,
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    if (_disposed) return;
    state = state.copyWith(
      isInitialized: true,
      isLoading: false,
      clearUser: true,
      errorMessage: null,
    );
  }
}

