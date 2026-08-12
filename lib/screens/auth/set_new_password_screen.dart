import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';

/// The last step of a password reset: choose the new one.
///
/// Reached only after a recovery code has been accepted, which is what makes it
/// possible at all — that verification grants a session, and `updateUser` can
/// then set a password without being given the old one. That is the whole
/// mechanism behind the reset finishing here instead of on a web page.
///
/// Pops `true` once the password is set. There is no way back: the traveller is
/// already signed in by this point, so "cancel" would leave them holding an
/// account whose password they still do not know.
class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(SetNewPasswordEvent(_passwordController.text));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          current.feedback?.id != previous.feedback?.id ||
          (!current.awaitingNewPassword && previous.awaitingNewPassword),
      listener: (context, auth) {
        final feedback = auth.feedback;
        if (feedback != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(feedback.message),
              backgroundColor: feedback.isError ? AppTheme.error : AppTheme.ink,
            ));
        }
        // The bloc clears the flag only once the password has actually been set.
        if (!auth.awaitingNewPassword) Navigator.of(context).pop(true);
      },
      builder: (context, auth) {
        return PopScope(
          // Backing out here would strand the traveller signed in to an account
          // whose password is still the one they could not remember.
          canPop: false,
          child: Scaffold(
            body: AppBackdrop(
              variant: AppBackdropVariant.duotone,
              child: SafeArea(
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
                              'Choose a new password',
                              textAlign: TextAlign.center,
                              style: textTheme.headlineMedium?.copyWith(fontSize: 26),
                            ),
                            AppTheme.gap3,
                            Text(
                              'This replaces the old one everywhere. You will stay '
                              'signed in on this device.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                height: 1.5,
                                color: AppTheme.ink.withValues(alpha: 0.72),
                              ),
                            ),
                            AppTheme.gap6,

                            _PasswordField(
                              controller: _passwordController,
                              label: 'New password',
                              hint: 'At least 6 characters',
                              obscure: _obscure,
                              enabled: !auth.isBusy,
                              onToggleObscure: () => setState(() => _obscure = !_obscure),
                              validator: (value) {
                                if ((value ?? '').isEmpty) return 'Enter a new password.';
                                if ((value ?? '').length < 6) return 'Use at least 6 characters.';
                                return null;
                              },
                            ),
                            AppTheme.gap3,
                            _PasswordField(
                              controller: _confirmController,
                              label: 'Confirm password',
                              hint: 'Type it again',
                              obscure: _obscure,
                              enabled: !auth.isBusy,
                              onToggleObscure: () => setState(() => _obscure = !_obscure),
                              onSubmitted: (_) => _submit(),
                              // Confirming catches the typo that would otherwise
                              // lock them out again the moment they sign out.
                              validator: (value) => value == _passwordController.text
                                  ? null
                                  : 'These do not match.',
                            ),
                            AppTheme.gap5,

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
                                    : const Text('Save password'),
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
          ),
        );
      },
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscure,
    required this.enabled,
    required this.onToggleObscure,
    required this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final bool enabled;
  final VoidCallback onToggleObscure;
  final FormFieldValidator<String> validator;
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
          obscureText: obscure,
          enabled: enabled,
          autofillHints: const [AutofillHints.newPassword],
          validator: validator,
          onFieldSubmitted: onSubmitted,
          textInputAction:
              onSubmitted == null ? TextInputAction.next : TextInputAction.done,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                size: 20, color: AppTheme.textSecondary),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onPressed: onToggleObscure,
            ),
          ),
        ),
      ],
    );
  }
}
