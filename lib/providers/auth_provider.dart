import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthState {
  final bool isAuthenticated;
  final String? email;
  final String? name;
  final String? role;

  AuthState({
    required this.isAuthenticated,
    this.email,
    this.name,
    this.role,
  });

  factory AuthState.initial() => AuthState(isAuthenticated: false);
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.initial());

  void login(String email, String password) {
    state = AuthState(
      isAuthenticated: true,
      email: email,
      name: 'Engineer John Doe',
      role: 'Lead Inspections Officer',
    );
  }

  void loginWithGoogle() {
    state = AuthState(
      isAuthenticated: true,
      email: 'john.doe@city.gov',
      name: 'Engineer John Doe',
      role: 'Lead Inspections Officer',
    );
  }

  void logout() {
    state = AuthState.initial();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
