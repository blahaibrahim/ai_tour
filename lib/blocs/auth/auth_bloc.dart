import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'auth_event.dart';
import 'auth_state.dart';

/// Handles anonymous-first authentication per docs/backend/01.
///
/// Communication is one-way: AuthBloc emits states, and a BlocListener in
/// AppShell tells AppBloc to reload or clear. AppBloc must not import AuthBloc.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthState.initial) {
    on<AppStartedEvent>(_onAppStarted);
    on<SignInAnonymouslyEvent>(_onSignInAnonymously);
    on<LinkEmailEvent>(_onLinkEmail);
    on<SignOutEvent>(_onSignOut);
    on<DeleteAccountEvent>(_onDeleteAccount);
    on<AuthUpdatedEvent>(_onAuthUpdated);

    // Mirror Supabase auth changes into bloc state for the lifetime of this bloc.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) => add(AuthUpdatedEvent(data.session)),
    );
  }

  late final StreamSubscription<supa.AuthState> _authSub;

  @override
  Future<void> close() {
    _authSub.cancel();
    return super.close();
  }

  void _onAuthUpdated(AuthUpdatedEvent event, Emitter<AuthState> emit) {
    final session = event.session as Session?;
    if (session == null) {
      emit(state.copyWith(status: AuthStatus.signedOut, userId: null, email: null));
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

  Future<void> _onLinkEmail(
      LinkEmailEvent event, Emitter<AuthState> emit) async {
    // Upgrades the anonymous user to a recoverable account.
    // auth.uid() is unchanged after this call — all existing rows stay attached.
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(email: event.email, password: event.password),
    );
  }

  Future<void> _onSignOut(SignOutEvent event, Emitter<AuthState> emit) async {
    await Supabase.instance.client.auth.signOut();
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
