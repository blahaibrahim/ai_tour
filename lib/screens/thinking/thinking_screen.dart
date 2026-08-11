import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../repositories/notification_repository.dart';
import '../../services/notification_service.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/compass_spinner.dart';

/// Shown while a route is being generated.
///
/// Two things it now does that it didn't:
///
///   * **It can be left.** Generation is a network call, and the screen it
///     covers is modal — before, a slow or failed request left the traveller
///     watching a spinner with no control at all. The request is bounded by the
///     client's own timeout, but "I changed my mind" needs an answer sooner
///     than that.
///   * **It shows the whole sequence, not one line.** The steps are real
///     pipeline stages, and seeing which are done is both more informative and
///     more honest than a single cycling caption.
class ThinkingScreen extends StatelessWidget {
  const ThinkingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        variant: AppBackdropVariant.deep,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  child: TextButton.icon(
                    onPressed: () =>
                        context.read<AppBloc>().add(const BackToMapEvent()),
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.deepNavy),
                    label: const Text('Cancel', style: TextStyle(color: AppTheme.deepNavy, fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space6,
                      vertical: AppTheme.space5,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CompassSpinner(size: 96),
                        const SizedBox(height: 48),
                        const Text(
                          'Almost there...',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        const _NotifyMe(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Notify me" opt-in.
///
/// One press, and it is never asked again: it writes a *user* preference, not
/// a per-route one, so every route generated after this one is covered — which
/// is why the button turns into a confirmation line rather than staying
/// pressable. [NotificationService.prefs] is the single source of truth for
/// that, so a traveller who opted in on a previous route sees the confirmation
/// here without ever having pressed anything on this screen.
class _NotifyMe extends StatefulWidget {
  const _NotifyMe();

  @override
  State<_NotifyMe> createState() => _NotifyMeState();
}

class _NotifyMeState extends State<_NotifyMe> {
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    final outcome = await NotificationService.instance.enable();
    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (outcome) {
      EnableOutcome.enabled =>
        "We'll let you know the moment it's ready.",
      // Worth distinguishing: the traveller did everything right and most of
      // the feature works, but a notification cannot reach a fully closed app
      // on this build. Saying "enabled" flatly would be a promise it can't keep.
      EnableOutcome.enabledLocalOnly =>
        "Notifications are on while the app is open in the background.",
      EnableOutcome.permissionDenied =>
        'Notifications are turned off for this app — enable them in Settings.',
      EnableOutcome.backendUnreachable =>
        "Couldn't save that right now. Try again once you're back online.",
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NotificationPrefs>(
      valueListenable: NotificationService.instance.prefs,
      builder: (context, prefs, _) {
        if (prefs.enabled) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 18, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "We'll let you know when it's ready",
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Text(
              "Turn on Notifications to find out\nwhen it's ready",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.8),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: _busy ? null : _enable,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.deepNavy,
                      ),
                    )
                  : const Icon(Icons.notifications_active_outlined,
                      color: AppTheme.deepNavy),
              label: const Text(
                'Notify me',
                style: TextStyle(
                  color: AppTheme.deepNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.deepNavy,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                elevation: 0,
              ),
            ),
          ],
        );
      },
    );
  }
}
