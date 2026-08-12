import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/segmented_control.dart';
import 'otp_verification_screen.dart';
import 'set_new_password_screen.dart';

enum AuthMode { login, signup }

/// Sign-in and sign-up, shown once at the end of the intro.
///
/// The app is anonymous-first: a session already exists by the time this
/// appears and every screen behind it works without an email. So this screen
/// is never a wall — "Continue as guest" is a first-class exit, and the account
/// it offers to create is an *upgrade* of the identity the traveller already
/// has, not a replacement for it. [SignUpEvent] does that in place, keeping
/// `auth.uid()` and with it every point, bookmark and artifact already earned.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onContinue,
    this.initialMode = AuthMode.signup,
  });

  /// Called once the traveller is through — signed in, signed up, or carrying
  /// on as a guest.
  final VoidCallback onContinue;

  /// Which tab the screen opens on.
  ///
  /// Signup by default, because this screen sits at the end of the first-run
  /// intro: almost everyone reaching it has just installed the app and has no
  /// account to log into. The caller passes [AuthMode.login] for the one case
  /// where that is wrong — a returning traveller whose session is a real
  /// account rather than the anonymous one the app creates at launch.
  final AuthMode initialMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late AuthMode _mode = widget.initialMode;
  bool _obscurePassword = true;

  /// Guards [AuthScreen.onContinue] against firing twice — the authenticated
  /// transition and a guest tap could otherwise both land.
  bool _continued = false;

  /// True while the verification page is on top of this one.
  ///
  /// Suppresses this screen's own "authenticated, so move on" listener for as
  /// long as it is: the pushed route has to come off the navigator before the
  /// gate swaps the whole subtree underneath it, or it is left stranded on top
  /// of the app.
  bool _verifying = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isSignup => _mode == AuthMode.signup;

  void _continue() {
    if (_continued) return;
    _continued = true;
    widget.onContinue();
  }

  /// Hands the traveller over to the verification page, and acts on the verdict
  /// it pops back.
  ///
  /// A password reset takes one more step than the other two: the recovery code
  /// signs them in but leaves the account with a password they still do not
  /// know, so it chains straight into choosing a new one before anybody is let
  /// through.
  Future<void> _openVerification(PendingVerification pending) async {
    setState(() => _verifying = true);

    final outcome = await Navigator.of(context).push<OtpOutcome>(
      MaterialPageRoute<OtpOutcome>(
        builder: (_) => OtpVerificationScreen(
          email: pending.email,
          purpose: pending.purpose,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;

    var done = outcome == OtpOutcome.verified;
    if (outcome == OtpOutcome.needsNewPassword) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const SetNewPasswordScreen()),
      );
      if (!mounted) return;
      done = saved == true;
    }

    setState(() => _verifying = false);
    // Cancelled, or backed out of: they are returned to the form with what
    // they typed still in it.
    if (done) _continue();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Gets the keyboard out of the way of the snackbar the result arrives in.
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    context.read<AuthBloc>().add(
          _isSignup ? SignUpEvent(email, password) : SignInEvent(email, password),
        );
  }

  /// Asks which address to send to rather than reusing whatever is in the form
  /// — someone who has forgotten their password has often mistyped the email
  /// too, and sending a reset to the wrong address silently is worse than
  /// asking.
  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.brLg),
        title: const Text('Reset your password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We will email you a link to set a new one.',
              style: TextStyle(fontSize: 13, color: AppTheme.ink.withValues(alpha: 0.7)),
            ),
            AppTheme.gap4,
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'you@example.com'),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || email == null || email.isEmpty) return;
    if (_emailError(email) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That does not look like a valid email address.')),
      );
      return;
    }
    context.read<AuthBloc>().add(ResetPasswordEvent(email));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          current.feedback?.id != previous.feedback?.id ||
          (current.status == AuthStatus.authenticated &&
              previous.status != AuthStatus.authenticated) ||
          (current.pendingVerification != null &&
              previous.pendingVerification == null),
      listener: (context, auth) {
        // A signup that needs confirming leaves this form entirely rather than
        // sitting on it with a "check your email" toast — the traveller is
        // done here, and the next thing they have to do belongs on its own page.
        final pending = auth.pendingVerification;
        if (pending != null && !_verifying) {
          _openVerification(pending);
          return;
        }

        final feedback = auth.feedback;
        if (feedback != null && !_verifying) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(feedback.message),
              backgroundColor: feedback.isError ? AppTheme.error : AppTheme.ink,
            ));
        }
        // Suppressed while the verification page is up — that page pops a
        // verdict, and acting on the session here as well would move the app
        // on with a route still stacked on top of it.
        if (auth.status == AuthStatus.authenticated && !_verifying) _continue();
      },
      builder: (context, auth) {
        return Scaffold(
          body: AppBackdrop(
            // Same ground as the intro it follows — the sign-in screen is the
            // last beat of the first-run sequence, not the first beat of the app.
            variant: AppBackdropVariant.duotone,
            child: SafeArea(
              // Centred rather than top-aligned, and still scrollable: the form
              // is short enough to sit in the middle of a phone screen, but it
              // has to survive the keyboard opening — which halves the height it
              // is centred in — and large system text. `minHeight` is what makes
              // the Column tall enough to have somewhere to centre itself;
              // without it the scroll view lets it shrink-wrap and the alignment
              // does nothing.
              //
              // There is no Skip in the corner: "Continue as guest", at the foot
              // of the form, is the same exit named for what it actually does.
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space6,
                    vertical: AppTheme.space6,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - AppTheme.space6 * 2,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isSignup ? 'Create your account' : 'Welcome back',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineMedium?.copyWith(fontSize: 26),
                          ),
                          AppTheme.gap6,

                          // Disabled mid-request: switching tabs while a signup
                          // is in flight would relabel the button under the
                          // result that is about to arrive.
                          IgnorePointer(
                            ignoring: auth.isBusy,
                            child: SegmentedControl<AuthMode>(
                              value: _mode,
                              onChanged: (mode) => setState(() => _mode = mode),
                              options: const [
                                SegmentOption(value: AuthMode.login, label: 'Log in'),
                                SegmentOption(value: AuthMode.signup, label: 'Sign up'),
                              ],
                            ),
                          ),
                          AppTheme.gap5,

                          _Field(
                            controller: _emailController,
                            label: 'Email',
                            hint: 'you@example.com',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            enabled: !auth.isBusy,
                            autofillHints: const [AutofillHints.email],
                            validator: (value) => _emailError(value?.trim() ?? ''),
                          ),
                          AppTheme.gap3,
                          _Field(
                            controller: _passwordController,
                            label: 'Password',
                            hint: _isSignup ? 'At least 6 characters' : '••••••••',
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscurePassword,
                            enabled: !auth.isBusy,
                            autofillHints: [
                              _isSignup ? AutofillHints.newPassword : AutofillHints.password,
                            ],
                            onSubmitted: (_) => _submit(),
                            validator: (value) => _passwordError(value ?? '', _isSignup),
                            trailing: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),

                          if (!_isSignup)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: auth.isBusy ? null : _forgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            )
                          else
                            AppTheme.gap4,

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: auth.isBusy ? null : _submit,
                              child: auth.isBusy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.onAccent,
                                      ),
                                    )
                                  : Text(_isSignup ? 'Create account' : 'Log in'),
                            ),
                          ),
                          AppTheme.gap5,

                          Center(
                            child: TextButton(
                              onPressed: auth.isBusy ? null : _continue,
                              child: const Text('Continue as guest'),
                            ),
                          ),
                          AppTheme.gap2,
                          Text(
                            _isSignup
                                ? 'Everything you have already collected stays yours — '
                                    'signing up saves it to your account.'
                                : 'You can create an account later from Settings.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              height: 1.5,
                              // Lands near the blue corner, so it takes the same
                              // navy treatment as the rest of this page's prose.
                              color: AppTheme.ink.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Deliberately loose. The only authority on whether an address is real is the
/// confirmation email; a stricter pattern here would reject valid addresses
/// (long TLDs, plus-addressing, unicode domains) to catch typos it cannot
/// actually detect.
String? _emailError(String value) {
  if (value.isEmpty) return 'Enter your email address.';
  final at = value.indexOf('@');
  final dot = value.lastIndexOf('.');
  if (at <= 0 || dot < at + 2 || dot == value.length - 1 || value.contains(' ')) {
    return 'That does not look like a valid email address.';
  }
  return null;
}

/// Six characters is Supabase's own default minimum. Checking it here turns a
/// round trip and a server error message into an instant inline one.
String? _passwordError(String value, bool isSignup) {
  if (value.isEmpty) return 'Enter your password.';
  if (isSignup && value.length < 6) return 'Use at least 6 characters.';
  return null;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.trailing,
    this.validator,
    this.enabled = true,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? trailing;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          enabled: enabled,
          autofillHints: autofillHints,
          validator: validator,
          onFieldSubmitted: onSubmitted,
          textInputAction:
              onSubmitted == null ? TextInputAction.next : TextInputAction.done,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary),
            suffixIcon: trailing,
          ),
        ),
      ],
    );
  }
}
