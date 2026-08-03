import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Fired once from main on startup — restores session or signs in anonymously.
class AppStartedEvent extends AuthEvent {
  const AppStartedEvent();
}

class SignInAnonymouslyEvent extends AuthEvent {
  const SignInAnonymouslyEvent();
}

class LinkEmailEvent extends AuthEvent {
  const LinkEmailEvent(this.email, this.password);
  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

class SignOutEvent extends AuthEvent {
  const SignOutEvent();
}

class DeleteAccountEvent extends AuthEvent {
  const DeleteAccountEvent();
}

class AuthUpdatedEvent extends AuthEvent {
  const AuthUpdatedEvent(this.session);
  final Object? session; // Session from Supabase

  @override
  List<Object?> get props => [session];
}
