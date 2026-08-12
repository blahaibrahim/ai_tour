import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth/auth_bloc.dart';
import '../blocs/auth/auth_state.dart';
import '../repositories/onboarding_repository.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../theme.dart';
import 'app_shell.dart';

/// What the app shows first: the intro, then the sign-in screen, then the app.
///
/// Sits above [AppShell] rather than inside it so the intro is not a `screen`
/// value in [AppBloc]. Nothing about the intro belongs in tour state — it is
/// not restored by the session repository, not reachable from the nav bar, and
/// shown once per install rather than once per route.
///
/// The blocs are already running underneath: anonymous sign-in, the city list
/// and the saved-artifact load all happen while the traveller is reading, so
/// finishing the intro lands on an app that is warm rather than one that then
/// starts loading.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

/// Where the traveller is in the first-run sequence.
enum _GateStage {
  /// Reading the persisted flag. A frame or two on a warm install.
  checking,
  intro,
  auth,
  app,
}

class _OnboardingGateState extends State<OnboardingGate> {
  _GateStage _stage = _GateStage.checking;

  @override
  void initState() {
    super.initState();
    _resolveStage();
  }

  Future<void> _resolveStage() async {
    final seen = await OnboardingRepository.hasSeenIntro();
    if (!mounted) return;
    setState(() => _stage = seen ? _GateStage.app : _GateStage.intro);
  }

  /// The flag is written here rather than when the last page is reached, so a
  /// traveller who backgrounds the app mid-intro still gets it next launch.
  /// Skipping counts as finishing — it is an answer, not a postponement.
  void _onIntroFinished() {
    OnboardingRepository.markIntroSeen();
    setState(() => _stage = _GateStage.auth);
  }

  void _onAuthFinished() => setState(() => _stage = _GateStage.app);

  @override
  Widget build(BuildContext context) {
    final child = switch (_stage) {
      // Matches AppShell's own splash exactly, so the two can hand over
      // without a visible change of screen.
      _GateStage.checking => const Scaffold(
        backgroundColor: AppTheme.ink,
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      ),
      _GateStage.intro => OnboardingScreen(onFinish: _onIntroFinished),
      _GateStage.auth => AuthScreen(
        onContinue: _onAuthFinished,
        // The app signs everyone in anonymously at launch, so a session
        // existing proves nothing. Only `authenticated` means a real account
        // — anything else is someone who has never had one, and should be
        // looking at the signup tab rather than a login form they cannot
        // fill in.
        initialMode:
            context.watch<AuthBloc>().state.status == AuthStatus.authenticated
            ? AuthMode.login
            : AuthMode.signup,
      ),
      _GateStage.app => const AppShell(),
    };

    return AnimatedSwitcher(
      duration: AppTheme.motionSlow,
      switchInCurve: AppTheme.motionCurve,
      switchOutCurve: Curves.easeInCubic,
      // Both stages are opaque and full-bleed; the default builder would size
      // the stack to whichever one it picked.
      layoutBuilder: (currentChild, previousChildren) =>
          Stack(children: [...previousChildren, ?currentChild]),
      child: KeyedSubtree(key: ValueKey(_stage), child: child),
    );
  }
}
