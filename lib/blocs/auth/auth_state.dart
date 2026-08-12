import 'package:equatable/equatable.dart';

enum AuthStatus { unknown, anonymous, authenticated, signedOut }

/// A one-shot message for the UI to show once — a failed login, a "check your
/// email" confirmation.
///
/// Carries an [id] because bloc states are compared by value: two identical
/// failures in a row ("wrong password", twice) would otherwise be the same
/// state, and the listener would never fire the second time. The id makes
/// every occurrence distinct, so the screen can key on it changing.
class AuthFeedback extends Equatable {
  const AuthFeedback({
    required this.id,
    required this.message,
    required this.isError,
  });

  final int id;
  final String message;
  final bool isError;

  @override
  List<Object?> get props => [id, message, isError];
}

/// Why a code was sent — which decides the `OtpType` it must be verified
/// against, and what the verification page says.
///
/// The three are not interchangeable. Supabase issues each code against a
/// specific type, and submitting it under the wrong one is rejected as invalid
/// — which reads to the traveller as though they mistyped a code that was
/// perfectly correct.
enum VerificationPurpose {
  /// Attaching an address to the anonymous user the app already created. The
  /// common path, since signing up is an upgrade rather than a fresh start.
  emailChange,

  /// A signup with no anonymous session to upgrade.
  signup,

  /// A forgotten password. Verifying this one grants a session, which is what
  /// makes setting a new password possible without the old one.
  passwordRecovery,
}

/// A verification waiting on the one-time code emailed to [email].
class PendingVerification extends Equatable {
  const PendingVerification({required this.email, required this.purpose});

  final String email;
  final VerificationPurpose purpose;

  @override
  List<Object?> get props => [email, purpose];
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.email,
    this.isAnonymous = true,
    this.isBusy = false,
    this.feedback,
    this.pendingVerification,
    this.awaitingNewPassword = false,
  });

  final AuthStatus status;
  final String? userId;
  final String? email;
  final bool isAnonymous;

  /// An auth request is in flight. The sign-in screen disables its form on
  /// this, so a slow network cannot be turned into three parallel signups by
  /// an impatient thumb.
  final bool isBusy;

  final AuthFeedback? feedback;

  /// Non-null while a code is outstanding. The sign-in screen opens the
  /// verification page on this becoming set, and that page closes on it being
  /// cleared — so it has to be clearable, hence the sentinel in [copyWith].
  final PendingVerification? pendingVerification;

  /// True between a recovery code being accepted and a new password being set.
  ///
  /// This is the one window where a session exists but the account is not
  /// really usable yet: Supabase grants a session on verifying a recovery
  /// code, and the traveller still cannot log in next time until they choose a
  /// password. The flag is what keeps them on the set-password step instead of
  /// being waved into the app by the "authenticated" listener.
  final bool awaitingNewPassword;

  static const initial = AuthState();

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? email,
    bool? isAnonymous,
    bool? isBusy,
    AuthFeedback? feedback,
    Object? pendingVerification = _sentinel,
    bool? awaitingNewPassword,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      isBusy: isBusy ?? this.isBusy,
      feedback: feedback ?? this.feedback,
      pendingVerification: pendingVerification == _sentinel
          ? this.pendingVerification
          : pendingVerification as PendingVerification?,
      awaitingNewPassword: awaitingNewPassword ?? this.awaitingNewPassword,
    );
  }

  @override
  List<Object?> get props => [
        status,
        userId,
        email,
        isAnonymous,
        isBusy,
        feedback,
        pendingVerification,
        awaitingNewPassword,
      ];
}

/// Lets [AuthState.copyWith] tell "clear this" from "leave it alone".
const Object _sentinel = Object();
