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

/// Creates an account for the traveller.
///
/// Named for what the user is doing, not for how it is implemented — for the
/// common case it is `updateUser`, not `signUp`, because everyone arrives here
/// already holding an anonymous session and that call is the one that keeps
/// `auth.uid()` unchanged. Points, artifacts and bookmarks are all keyed on
/// that uid, so signing up must not mint a new one.
class SignUpEvent extends AuthEvent {
  const SignUpEvent(this.email, this.password);
  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

/// Signs in to an account that already exists — a returning traveller on a new
/// device. This *replaces* the current anonymous session, so anything earned
/// under it stays behind; that is the correct outcome, since the two are
/// different people as far as the database is concerned.
class SignInEvent extends AuthEvent {
  const SignInEvent(this.email, this.password);
  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

/// Submits the code from the verification email.
///
/// The address and the verification type come from
/// [AuthState.pendingVerification] rather than the caller — there is exactly
/// one signup in flight, and letting the screen pass its own copy is how the
/// two drift apart.
class VerifyOtpEvent extends AuthEvent {
  const VerifyOtpEvent(this.token);
  final String token;

  @override
  List<Object?> get props => [token];
}

/// Sends a fresh code to the same address.
class ResendOtpEvent extends AuthEvent {
  const ResendOtpEvent();
}

/// Abandons the outstanding verification and returns to the form — the
/// traveller mistyped their address, or changed their mind.
class CancelVerificationEvent extends AuthEvent {
  const CancelVerificationEvent();
}

/// Starts a password reset: emails a one-time code and puts the flow into
/// [VerificationPurpose.passwordRecovery].
class ResetPasswordEvent extends AuthEvent {
  const ResetPasswordEvent(this.email);
  final String email;

  @override
  List<Object?> get props => [email];
}

/// Finishes a password reset.
///
/// Only meaningful while [AuthState.awaitingNewPassword] — the session that
/// makes this possible is the one the recovery code just granted, and it is
/// the only reason `updateUser` can set a password without being given the old
/// one.
class SetNewPasswordEvent extends AuthEvent {
  const SetNewPasswordEvent(this.password);
  final String password;

  @override
  List<Object?> get props => [password];
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
