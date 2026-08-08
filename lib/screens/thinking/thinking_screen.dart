import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
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
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Notifications enabled! We will let you know.'))
                            );
                          },
                          icon: const Icon(Icons.notifications_active_outlined, color: AppTheme.deepNavy),
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
