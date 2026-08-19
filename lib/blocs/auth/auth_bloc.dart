import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../repositories/points_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// Handles anonymous-first authentication per docs/backend/01.
///
/// Communication is one-way: AuthBloc emits states, and a BlocListener in
/// AppShell tells AppBloc to reload or clear. AppBloc must not import AuthBloc.
///
/// Sessions survive app closure without anything here doing the work:
/// `SupabaseService` hands the client a `LocalStorage` backed by the platform
/// keychain, and `autoRefreshToken` keeps it alive. [_onAppStarted] reads that
/// back, which is why a returning traveller never sees the sign-in screen.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthState.initial) {
    on<AppStartedEvent>(_onAppStarted);
    on<SignInAnonymouslyEvent>(_onSignInAnonymously);
    on<SignUpEvent>(_onSignUp);
    on<SignInEvent>(_onSignIn);
    on<VerifyOtpEvent>(_onVerifyOtp);
    on<ResendOtpEvent>(_onResendOtp);
    on<CancelVerificationEvent>(_onCancelVerification);
    on<ResetPasswordEvent>(_onResetPassword);
    on<SetNewPasswordEvent>(_onSetNewPassword);
    on<SignOutEvent>(_onSignOut);
    on<DeleteAccountEvent>(_onDeleteAccount);
    on<AuthUpdatedEvent>(_onAuthUpdated);

    // Mirror Supabase auth changes into bloc state for the lifetime of this bloc.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) => add(AuthUpdatedEvent(data.session)),
    );
  }

  late final StreamSubscription<supa.AuthState> _authSub;

  /// Makes each [AuthFeedback] distinct — see its doc comment.
  int _feedbackSeq = 0;

  /// Every network call here is bounded. Supabase's own default is long enough
  /// that a dead connection leaves the sign-in button spinning indefinitely,
  /// which reads as a broken app rather than a broken network.
  static const _requestTimeout = Duration(seconds: 20);

  @override
  Future<void> close() {
    _authSub.cancel();
    return super.close();
  }

  AuthFeedback _error(AuthMessage message) =>
      AuthFeedback(id: ++_feedbackSeq, message: message, isError: true);

  AuthFeedback _notice(AuthMessage message, {String? argument}) => AuthFeedback(
        id: ++_feedbackSeq,
        message: message,
        isError: false,
        argument: argument,
      );

  void _onAuthUpdated(AuthUpdatedEvent event, Emitter<AuthState> emit) {
    final session = event.session as Session?;
    if (session == null) {
      // Built fresh rather than copied: `copyWith` cannot set a field back to
      // null, so copying here would leave the signed-out state still carrying
      // the previous user's id and email.
      emit(AuthState(
        status: AuthStatus.signedOut,
        isBusy: state.isBusy,
        feedback: state.feedback,
      ));
      return;
    }
    final user = session.user;
    final isAnon = user.isAnonymous;
    emit(state.copyWith(
      status: isAnon ? AuthStatus.anonymous : AuthStatus.authenticated,
      userId: user.id,
      email: user.email,
      isAnonymous: isAnon,
    ));
  }

  Future<void> _onAppStarted(AppStartedEvent event, Emitter<AuthState> emit) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      add(AuthUpdatedEvent(session));
      return;
    }
    // No stored session — sign in anonymously so the user has an identity
    // from first launch, per doc 01's "anonymous-first" design.
    add(const SignInAnonymouslyEvent());
  }

  Future<void> _onSignInAnonymously(
      SignInAnonymouslyEvent event, Emitter<AuthState> emit) async {
    try {
      // Bounded rather than left on Supabase's own default: with no network
      // path to Supabase at all this call can otherwise hang far longer than
      // is reasonable, and AppShell holds the whole app on a splash screen
      // until AuthStatus leaves `unknown` — so a dead backend must resolve
      // this quickly, not eventually.
      await Supabase.instance.client.auth
          .signInAnonymously()
          .timeout(const Duration(seconds: 8));
      // _handleAuthChange will be called via the stream listener.
    } catch (error, stack) {
      developer.log(
        'Anonymous sign-in failed',
        name: 'AuthBloc',
        error: error,
        stackTrace: stack,
      );
      // Non-fatal — the app still works with no session (curated fallback data).
      emit(state.copyWith(status: AuthStatus.signedOut));
    }
  }

  // ---------------------------------------------------------------------------
  // Email accounts
  // ---------------------------------------------------------------------------

  /// Upgrades the anonymous user in place where possible.
  ///
  /// `updateUser` rather than `signUp` is the whole point: it keeps
  /// `auth.uid()`, so the profile row, the points ledger, the saved locations
  /// and the captured artifacts that already belong to this traveller stay
  /// theirs. `signUp` would issue a new uid and silently abandon all of it.
  ///
  /// Whether the account is usable immediately depends on the project's
  /// "Confirm email" setting, which the app cannot read — so both outcomes are
  /// handled: a linked user comes back non-anonymous, and one awaiting
  /// confirmation comes back still anonymous and is told to check their inbox.
  Future<void> _onSignUp(SignUpEvent event, Emitter<AuthState> emit) async {
    emit(state.copyWith(isBusy: true));
    final auth = Supabase.instance.client.auth;

    try {
      final current = auth.currentUser;

      if (current != null && current.isAnonymous) {
        final response = await auth
            .updateUser(UserAttributes(email: event.email, password: event.password))
            .timeout(_requestTimeout);
        final user = response.user;
        if (user != null && !user.isAnonymous) {
          // Verification is switched off for this project — the link landed
          // immediately and there is no code to ask for.
          emit(state.copyWith(
            isBusy: false,
            status: AuthStatus.authenticated,
            userId: user.id,
            email: user.email,
            isAnonymous: false,
            feedback: _notice(AuthMessage.accountCreatedWithProgress),
          ));
        } else {
          emit(state.copyWith(
            isBusy: false,
            pendingVerification: PendingVerification(
              email: event.email,
              purpose: VerificationPurpose.emailChange,
            ),
          ));
        }
        return;
      }

      // No anonymous session to upgrade (sign-in failed at launch, or the
      // traveller signed out): a plain signup is the only option left.
      final response = await auth
          .signUp(email: event.email, password: event.password)
          .timeout(_requestTimeout);
      if (response.session != null) {
        emit(state.copyWith(
            isBusy: false, feedback: _notice(AuthMessage.accountCreated)));
      } else {
        emit(state.copyWith(
          isBusy: false,
          pendingVerification: PendingVerification(
            email: event.email,
            purpose: VerificationPurpose.signup,
          ),
        ));
      }
    } on AuthException catch (error) {
      emit(state.copyWith(isBusy: false, feedback: _error(_messageFor(error))));
    } catch (error, stack) {
      developer.log('Sign-up failed', name: 'AuthBloc', error: error, stackTrace: stack);
      emit(state.copyWith(isBusy: false, feedback: _error(AuthMessage.errorNetwork)));
    }
  }

  /// Exchanges the emailed code for a session.
  ///
  /// On the `email_change` path this is what finally attaches the address to
  /// the anonymous user — `auth.uid()` is unchanged throughout, so the points
  /// and artifacts earned before signing up are already on the account by the
  /// time it completes.
  Future<void> _onVerifyOtp(VerifyOtpEvent event, Emitter<AuthState> emit) async {
    final pending = state.pendingVerification;
    if (pending == null) return;

    emit(state.copyWith(isBusy: true));
    try {
      await Supabase.instance.client.auth
          .verifyOTP(
            email: pending.email,
            token: event.token.trim(),
            type: _otpTypeFor(pending.purpose),
          )
          .timeout(_requestTimeout);

      final isRecovery = pending.purpose == VerificationPurpose.passwordRecovery;
      emit(state.copyWith(
        isBusy: false,
        pendingVerification: null,
        // A recovery code grants a session but leaves the account without a
        // usable password, so the flow is not over — it moves to the
        // set-password step rather than into the app.
        awaitingNewPassword: isRecovery,
        feedback: isRecovery
            ? _notice(AuthMessage.codeAcceptedChoosePassword)
            : _notice(AuthMessage.emailConfirmed),
      ));
    } on AuthException catch (error) {
      // Deliberately stays on the verification screen: a wrong code is worth
      // another try, and throwing the traveller back to the form would make
      // them retype everything.
      emit(state.copyWith(isBusy: false, feedback: _error(_messageFor(error))));
    } catch (error, stack) {
      developer.log('OTP verification failed', name: 'AuthBloc', error: error, stackTrace: stack);
      emit(state.copyWith(isBusy: false, feedback: _error(AuthMessage.errorNetwork)));
    }
  }

  Future<void> _onResendOtp(ResendOtpEvent event, Emitter<AuthState> emit) async {
    final pending = state.pendingVerification;
    if (pending == null) return;

    emit(state.copyWith(isBusy: true));
    try {
      // `resend` covers signup and email_change only. A recovery code is
      // reissued by asking for the reset again, which is the same call that
      // started the flow.
      if (pending.purpose == VerificationPurpose.passwordRecovery) {
        await Supabase.instance.client.auth
            .resetPasswordForEmail(pending.email)
            .timeout(_requestTimeout);
      } else {
        await Supabase.instance.client.auth
            .resend(email: pending.email, type: _otpTypeFor(pending.purpose))
            .timeout(_requestTimeout);
      }
      emit(state.copyWith(
        isBusy: false,
        feedback: _notice(AuthMessage.newCodeSent, argument: pending.email),
      ));
    } on AuthException catch (error) {
      emit(state.copyWith(isBusy: false, feedback: _error(_messageFor(error))));
    } catch (error, stack) {
      developer.log('OTP resend failed', name: 'AuthBloc', error: error, stackTrace: stack);
      emit(state.copyWith(isBusy: false, feedback: _error(AuthMessage.errorNetwork)));
    }
  }

  void _onCancelVerification(
      CancelVerificationEvent event, Emitter<AuthState> emit) {
    emit(state.copyWith(isBusy: false, pendingVerification: null));
  }

  Future<void> _onSignIn(SignInEvent event, Emitter<AuthState> emit) async {
    emit(state.copyWith(isBusy: true));
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: event.email, password: event.password)
          .timeout(_requestTimeout);
      // The auth stream emits the authenticated state; this only clears the
      // spinner and confirms.
      emit(state.copyWith(
          isBusy: false, feedback: _notice(AuthMessage.welcomeBack)));
    } on AuthException catch (error) {
      emit(state.copyWith(isBusy: false, feedback: _error(_messageFor(error))));
    } catch (error, stack) {
      developer.log('Sign-in failed', name: 'AuthBloc', error: error, stackTrace: stack);
      emit(state.copyWith(isBusy: false, feedback: _error(AuthMessage.errorNetwork)));
    }
  }

  /// Emails a recovery code and moves the flow onto the verification page.
  ///
  /// Nothing here reveals whether an account exists for the address. Supabase
  /// does not error on an unknown one, and the flow continues to the code
  /// screen either way — an address with no account simply never receives a
  /// code that works. Short-circuiting on "no such user" would turn this form
  /// into a way to test which emails have signed up.
  Future<void> _onResetPassword(
      ResetPasswordEvent event, Emitter<AuthState> emit) async {
    emit(state.copyWith(isBusy: true));
    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(event.email)
          .timeout(_requestTimeout);
      emit(state.copyWith(
        isBusy: false,
        pendingVerification: PendingVerification(
          email: event.email,
          purpose: VerificationPurpose.passwordRecovery,
        ),
      ));
    } on AuthException catch (error) {
      emit(state.copyWith(isBusy: false, feedback: _error(_messageFor(error))));
    } catch (error, stack) {
      developer.log('Password reset failed', name: 'AuthBloc', error: error, stackTrace: stack);
      emit(state.copyWith(isBusy: false, feedback: _error(AuthMessage.errorNetwork)));
    }
  }

  /// Sets the new password, using the session the recovery code granted.
  ///
  /// This is the whole reason the reset can finish in the app rather than on a
  /// web page: verifying a recovery code signs the traveller in, and
  /// `updateUser` can then set a password without being given the old one.
  Future<void> _onSetNewPassword(
      SetNewPasswordEvent event, Emitter<AuthState> emit) async {
    emit(state.copyWith(isBusy: true));
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: event.password))
          .timeout(_requestTimeout);
      emit(state.copyWith(
        isBusy: false,
        awaitingNewPassword: false,
        feedback: _notice(AuthMessage.passwordUpdated),
      ));
    } on AuthException catch (error) {
      // Stays on the step: the session is still valid, so another attempt at a
      // password Supabase will accept is all that is needed.
      emit(state.copyWith(isBusy: false, feedback: _error(_messageFor(error))));
    } catch (error, stack) {
      developer.log('Password update failed', name: 'AuthBloc', error: error, stackTrace: stack);
      emit(state.copyWith(isBusy: false, feedback: _error(AuthMessage.errorNetwork)));
    }
  }

  Future<void> _onSignOut(SignOutEvent event, Emitter<AuthState> emit) async {
    // Read before signing out — this is the last moment the id is available,
    // and the cached score is keyed on it. Leaving it behind would show the
    // departing traveller's total to whoever signs in on this device next.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    await Supabase.instance.client.auth.signOut();
    if (userId != null) await PointsRepository.clearFor(userId);
    // Stream listener will emit signedOut state.
    // AppShell's BlocListener will dispatch LeaveTourEvent to AppBloc.
  }

  Future<void> _onDeleteAccount(
      DeleteAccountEvent event, Emitter<AuthState> emit) async {
    // Calls the Flask endpoint which uses service_role to delete auth row + storage.
    // The endpoint is POST /api/auth/delete-account (already implemented in Flask).
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    // After deletion the auth stream will emit a signout event naturally.
    await Supabase.instance.client.auth.signOut();
  }
}

/// Supabase issues each code against a specific type and rejects it under any
/// other, so this mapping is the difference between a working code and one the
/// traveller is told is invalid.
OtpType _otpTypeFor(VerificationPurpose purpose) => switch (purpose) {
      VerificationPurpose.emailChange => OtpType.emailChange,
      VerificationPurpose.signup => OtpType.signup,
      VerificationPurpose.passwordRecovery => OtpType.recovery,
    };

/// Turns Supabase's wire messages into one of the app's own, translated ones.
///
/// Only the cases actually reachable from these forms are recognised; anything
/// else falls through to [AuthMessage.errorGeneric], which carries Supabase's
/// own text. That is the one string in the auth flow that stays untranslated,
/// and deliberately so: the alternative is throwing away the only description
/// of a failure nobody anticipated.
AuthMessage _messageFor(AuthException error) {
  final message = error.message.toLowerCase();

  // The account is fine and the password was accepted — the mail simply could
  // not be handed off, which is a server-side problem the traveller can do
  // nothing about. Supabase reports it as a bare `unexpected_failure`, and the
  // underlying SMTP rejection ("525 Unauthorized IP address" and friends) is
  // not something to put in front of anyone.
  if (error.code == 'unexpected_failure' || message.contains('error sending')) {
    return AuthMessage.errorEmailNotSending;
  }
  if (message.contains('invalid login credentials')) {
    return AuthMessage.errorBadCredentials;
  }
  if (message.contains('already registered') || message.contains('already been registered')) {
    return AuthMessage.errorAlreadyRegistered;
  }
  if (message.contains('email address') && message.contains('invalid')) {
    return AuthMessage.errorInvalidEmail;
  }
  if (message.contains('password should be at least')) {
    return AuthMessage.errorPasswordTooShort;
  }
  if (message.contains('rate limit') ||
      message.contains('too many') ||
      message.contains('security purposes')) {
    return AuthMessage.errorTooManyAttempts;
  }
  if (message.contains('token has expired') || message.contains('expired')) {
    return AuthMessage.errorCodeExpired;
  }
  if (message.contains('invalid') && message.contains('token')) {
    return AuthMessage.errorCodeInvalid;
  }
  return AuthMessage.errorGeneric;
}
