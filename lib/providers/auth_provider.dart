import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthState {
  final bool isAuthenticated;
  final String? email;
  final String? name;
  final String? role;

  AuthState({required this.isAuthenticated, this.email, this.name, this.role});

  String get firstName {
    if (name == null || name!.trim().isEmpty) return 'Operator';
    final parts = name!.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 &&
        (parts.first.toLowerCase() == 'engineer' ||
            parts.first.toLowerCase() == 'dr' ||
            parts.first.toLowerCase() == 'officer')) {
      return parts[1];
    }
    return parts.first;
  }

  factory AuthState.initial() => AuthState(
    isAuthenticated: false,
    email: 'rahul@aerialeye.ai',
    name: 'Rahul',
    role: 'Lead Inspections Officer',
  );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.initial());

  void login(String email, String password) {
    String username = 'Rahul';
    if (email.contains('@')) {
      final prefix = email.split('@').first;
      if (prefix.isNotEmpty) {
        username =
            prefix[0].toUpperCase() + prefix.substring(1).replaceAll('.', ' ');
      }
    }
    state = AuthState(
      isAuthenticated: true,
      email: email,
      name: username.isEmpty ? 'Rahul' : username,
      role: 'Lead Inspections Officer',
    );
  }

  void loginWithGoogle() {
    state = AuthState(
      isAuthenticated: true,
      email: 'rahul@aerialeye.ai',
      name: 'Rahul',
      role: 'Lead Inspections Officer',
    );
  }

  void updateProfileName(String newName) {
    state = AuthState(
      isAuthenticated: state.isAuthenticated,
      email: state.email,
      name: newName,
      role: state.role,
    );
  }

  void logout() {
    state = AuthState(isAuthenticated: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
