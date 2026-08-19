import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_backdrop.dart';

/// What the verification page popped back with.
///
/// Three outcomes rather than a bool because a recovery code being accepted is
/// not the end of anything — the caller still has to collect a new password,
/// and treating that as "verified" would wave the traveller into the app with
/// an account they still cannot log into.
enum OtpOutcome { verified, needsNewPassword, cancelled }

/// How many digits the emailed code has.
///
/// Must match **Authentication → Sign In / Providers → Email → Email OTP
/// Length** in the Supabase dashboard, which allows 6–10.
///
/// Not a cosmetic setting. The field stops accepting input at this many
/// characters and submits itself there, so a value shorter than the real code
/// makes it impossible to enter a valid one at all, and a longer one never
/// auto-submits.
const int otpCodeLength = 6;

/// Where a signup goes to be confirmed: the code from the email, and nothing
/// else on the page.
///
/// A page of its own rather than a third state of the sign-up form. The
/// traveller has finished with the form — leaving it on screen behind an
/// overlay invites them to edit fields that have already been submitted, and
/// makes "what am I waiting for" the least prominent thing in view.
///
/// Pops an [OtpOutcome]. The caller — [AuthScreen] — is what decides where that
/// leads, because this screen is also reachable from Settings, where finishing
/// means going back to Settings rather than into the app.
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.purpose,
  });

  final String email;
  final VerificationPurpose purpose;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const _codeLength = otpCodeLength;

  /// Supabase's own resend throttle is 60s; matching it here turns a server
  /// rejection into a disabled button with a countdown on it.
  static const _resendCooldown = Duration(seconds: 60);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  Timer? _cooldownTimer;
  int _secondsUntilResend = 0;

  /// Stops the auto-submit firing repeatedly while a verification is in flight
  /// — the field still holds a full code until the traveller edits it.
  String? _submittedCode;

  /// Guards against popping twice. See [_close].
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    // The code is the only thing this page wants; open the keyboard on it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsUntilResend = _resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsUntilResend--);
      if (_secondsUntilResend <= 0) timer.cancel();
    });
  }

  void _onCodeChanged(String value) {
    setState(() {});
    // Submitting on the last digit saves a tap that has no decision in it —
    // there is nothing else the traveller could mean by typing a full code.
    if (value.length == _codeLength && value != _submittedCode) {
      _submittedCode = value;
      _submit();
    }
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.length != _codeLength) return;
    _focusNode.unfocus();
    context.read<AuthBloc>().add(VerifyOtpEvent(code));
  }

  void _resend() {
    context.read<AuthBloc>().add(const ResendOtpEvent());
    _controller.clear();
    _submittedCode = null;
    _startCooldown();
    setState(() {});
  }

  /// The single way off this page.
  ///
  /// Every exit clears `pendingVerification`, and the listener below also fires
  /// on that going null — so leaving had two callers racing to pop: this one
  /// with the real outcome, and the listener a moment later with a second pop
  /// that took the screen underneath with it. Backing out appeared to do
  /// nothing because the app was popping past the page it was returning to.
  void _close(OtpOutcome outcome) {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop(outcome);
  }

  void _cancel() {
    context.read<AuthBloc>().add(const CancelVerificationEvent());
    _close(OtpOutcome.cancelled);
  }

  bool get _isRecovery =>
      widget.purpose == VerificationPurpose.passwordRecovery;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          current.feedback?.id != previous.feedback?.id ||
          (current.pendingVerification == null &&
              previous.pendingVerification != null),
      listener: (context, auth) {
        final feedback = auth.feedback;
        if (feedback != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(feedback.text(l10n)),
                backgroundColor: feedback.isError
                    ? AppTheme.error
                    : AppTheme.ink,
              ),
            );
          if (feedback.isError) {
            // Clearing on failure is the difference between "try again" and
            // "delete the whole code, then try again".
            _controller.clear();
            _submittedCode = null;
            _focusNode.requestFocus();
          }
        }
        // Also reached on cancel, which clears the same field — [_close] is
        // what stops that second pop from landing.
        if (auth.pendingVerification == null) {
          _close(
            _isRecovery ? OtpOutcome.needsNewPassword : OtpOutcome.verified,
          );
        }
      },
      builder: (context, auth) {
        return PopScope(
          // Backing out has to tell the bloc, or the sign-up screen reopens
          // this page the moment it rebuilds.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _cancel();
          },
          child: Scaffold(
            body: AppBackdrop(
              variant: AppBackdropVariant.duotone,
              child: SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space3,
                        ),
                        child: IconButton(
                          onPressed: auth.isBusy ? null : _cancel,
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: AppTheme.ink.withValues(alpha: 0.72),
                          tooltip: l10n.authUseDifferentEmail,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space6,
                          vertical: AppTheme.space4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isRecovery
                                  ? l10n.authResetYourPassword
                                  : l10n.authCheckYourEmail,
                              textAlign: TextAlign.center,
                              style: textTheme.headlineMedium?.copyWith(
                                fontSize: 26,
                              ),
                            ),
                            AppTheme.gap3,
                            Text.rich(
                              TextSpan(
                                children: [
                                  // Reads the length off the same constant the
                                  // field enforces, so the two cannot disagree.
                                  TextSpan(
                                    text: l10n.authCodeSentTo(_codeLength),
                                  ),
                                  TextSpan(
                                    text: widget.email,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                height: 1.5,
                                color: AppTheme.ink.withValues(alpha: 0.72),
                              ),
                            ),
                            AppTheme.gap6,

                            _CodeField(
                              controller: _controller,
                              focusNode: _focusNode,
                              length: _codeLength,
                              enabled: !auth.isBusy,
                              onChanged: _onCodeChanged,
                              onSubmitted: (_) => _submit(),
                            ),
                            AppTheme.gap6,

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    auth.isBusy ||
                                        _controller.text.length != _codeLength
                                    ? null
                                    : _submit,
                                child: auth.isBusy
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.onAccent,
                                        ),
                                      )
                                    : Text(l10n.authConfirm),
                              ),
                            ),
                            AppTheme.gap4,

                            Center(
                              child: TextButton(
                                onPressed:
                                    auth.isBusy || _secondsUntilResend > 0
                                    ? null
                                    : _resend,
                                child: Text(
                                  _secondsUntilResend > 0
                                      ? l10n.authResendIn(_secondsUntilResend)
                                      : l10n.authSendNewCode,
                                ),
                              ),
                            ),
                            AppTheme.gap2,
                            Text(
                              l10n.authCodeExpiryNote,
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: 11.5,
                                height: 1.5,
                                color: AppTheme.ink.withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Six boxes fed by one hidden field.
///
/// Six real `TextField`s would mean six controllers, six focus nodes, and
/// hand-written focus movement on every keystroke and backspace — which is
/// also what breaks paste and SMS autofill. One field owns the text; the boxes
/// are just a rendering of it.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final code = controller.text;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized from the space actually available rather than a fixed width.
        // The boxes were 46px each, which fits six on a phone and overflows at
        // eight — and [length] is a dashboard setting that can be anything from
        // 6 to 10, so no fixed width is safe. There is deliberately no minimum:
        // the boxes give up width before the row gives up fitting.
        const gap = 7.0;
        final boxWidth = math.min(
          52.0,
          (constraints.maxWidth - gap * (length - 1)) / length,
        );
        final boxHeight = (boxWidth * 1.2).clamp(42.0, 58.0);
        final fontSize = (boxWidth * 0.44).clamp(15.0, 22.0);

        return Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < length; i++)
                  Padding(
                    padding: EdgeInsetsDirectional.only(end: i == length - 1 ? 0 : gap),
                    child: _CodeBox(
                      character: i < code.length ? code[i] : null,
                      // The "current" box is the next empty one, and stays on
                      // the last box once the code is full.
                      isActive:
                          focusNode.hasFocus &&
                          (i == code.length ||
                              (i == length - 1 && code.length == length)),
                      width: boxWidth,
                      height: boxHeight,
                      fontSize: fontSize,
                    ),
                  ),
              ],
            ),
            // The real field, invisible but hit-testable, laid over the boxes
            // so tapping anywhere on the row opens the keyboard.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: length,
                  // One-time-code unlocks the OS offering the code straight
                  // from the notification on both platforms.
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(length),
                  ],
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.character,
    required this.isActive,
    required this.width,
    required this.height,
    required this.fontSize,
  });

  final String? character;
  final bool isActive;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final filled = character != null;

    return AnimatedContainer(
      duration: AppTheme.motionFast,
      curve: AppTheme.motionCurve,
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: AppTheme.brMd,
        border: Border.all(
          color: isActive
              ? AppTheme.accent
              : filled
              ? AppTheme.accent.withValues(alpha: 0.4)
              : AppTheme.divider,
          width: isActive ? 2 : 1.4,
        ),
      ),
      child: Text(
        character ?? '',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: AppTheme.ink,
        ),
      ),
    );
  }
}
