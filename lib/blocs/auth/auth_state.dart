import 'package:equatable/equatable.dart';

enum AuthStatus { unknown, anonymous, authenticated, signedOut }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.email,
    this.isAnonymous = true,
  });

  final AuthStatus status;
  final String? userId;
  final String? email;
  final bool isAnonymous;

  static const initial = AuthState();

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? email,
    bool? isAnonymous,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      isAnonymous: isAnonymous ?? this.isAnonymous,
    );
  }

  @override
  List<Object?> get props => [status, userId, email, isAnonymous];
}
