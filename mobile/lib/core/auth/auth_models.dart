import 'package:flutter/foundation.dart';

/// Roles oficiales soportados por el backend `bck-bocadoo`.
enum AuthRole {
  customer('customer'),
  owner('owner'),
  cashier('cashier');

  final String apiValue;
  const AuthRole(this.apiValue);

  bool get isStaff => this == owner || this == cashier;

  static AuthRole fromApi(String? value) {
    return switch (value?.toLowerCase()) {
      'owner' => AuthRole.owner,
      'cashier' => AuthRole.cashier,
      _ => AuthRole.customer,
    };
  }
}

/// Usuario autenticado identificado por su `publicId` (UUID).
@immutable
class AuthUser {
  final String publicId;
  final String email;
  final String fullName;
  final AuthRole role;
  final String? restaurantId;
  final bool isOfflineDemo;

  const AuthUser({
    required this.publicId,
    required this.email,
    required this.fullName,
    required this.role,
    this.restaurantId,
    this.isOfflineDemo = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawPublicId =
        (json['publicId'] ?? json['public_id'] ?? json['id'] ?? '') as String;
    return AuthUser(
      publicId: rawPublicId,
      email: (json['email'] as String?) ?? '',
      fullName: (json['fullName'] ?? json['full_name'] ?? 'Usuario') as String,
      role: AuthRole.fromApi(json['role'] as String?),
      restaurantId: (json['restaurantId'] ?? json['restaurant_id']) as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'publicId': publicId,
        'email': email,
        'fullName': fullName,
        'role': role.apiValue,
        'restaurantId': restaurantId,
        'isOfflineDemo': isOfflineDemo,
      };
}

/// Estado global de autenticación en Riverpod.
@immutable
class AuthState {
  final bool isInitialized;
  final bool isLoading;
  final AuthUser? user;
  final String? errorMessage;

  const AuthState({
    this.isInitialized = false,
    this.isLoading = false,
    this.user,
    this.errorMessage,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    bool? isInitialized,
    bool? isLoading,
    AuthUser? user,
    bool clearUser = false,
    String? errorMessage,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: errorMessage,
    );
  }
}

