import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/app/app_bloc.dart';
import '../blocs/app/app_event.dart';
import '../blocs/app/app_state.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/location_detail_overlay.dart';
import '../screens/ar_hunt/ar_hunt_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/thinking/thinking_screen.dart';
import '../screens/swipe/swipe_screen.dart';
import '../screens/result/result_screen.dart';
import '../screens/overview/overview_screen.dart';
import '../screens/folder/folder_screen.dart';
import '../screens/areas_map/areas_map_screen.dart';
import 'screen_switcher.dart';
import 'nav_bar.dart';

/// Root widget that selects which screen to display and hosts the persistent
/// nav bar and location-detail overlay.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  /// Opens the app's own camera — the same viewfinder, chrome and shutter the
  /// fennec hunt uses, minus the fennec. It files the shot through
  /// [AddCapturedArtifactEvent] itself, so there is nothing to do here but push it.
  void _openCamera(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ArHuntScreen(mode: ArCameraMode.capture),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    Widget currentScreen;
    switch (state.screen) {
      case 'map':
        currentScreen = const MapScreen();
        break;
      case 'thinking':
        currentScreen = const ThinkingScreen();
        break;
      case 'swipe':
        currentScreen = const SwipeScreen();
        break;
      case 'result':
        currentScreen = const ResultScreen();
        break;
      case 'overview':
        currentScreen = const OverviewScreen();
        break;
      case 'folder':
        currentScreen = const FolderScreen();
        break;
      case 'areasMap':
        currentScreen = const AreasMapScreen();
        break;
      default:
        currentScreen = const MapScreen();
    }

    final showNavBar = ['overview', 'folder', 'areasMap'].contains(state.screen);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ScreenSwitcher(screen: state.screen, child: currentScreen),
          ),

          if (showNavBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassSurface(
                      borderRadius: AppTheme.brPill,
                      padding: const EdgeInsets.all(8),
                      boxShadow: AppTheme.shadowLg,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NavButton(
                            icon: Icons.map_outlined,
                            label: 'Map',
                            isActive: state.screen == 'areasMap',
                            onTap: () => context.read<AppBloc>().add(const SetScreenEvent('areasMap')),
                          ),
                          const SizedBox(width: 4),
                          NavButton(
                            icon: Icons.home_outlined,
                            label: 'Home',
                            isActive: state.screen == 'overview',
                            onTap: () => context.read<AppBloc>().add(const NavHomeEvent()),
                          ),
                          const SizedBox(width: 4),
                          NavButton(
                            icon: Icons.folder_outlined,
                            label: 'Folder',
                            isActive: state.screen == 'folder',
                            onTap: () => context.read<AppBloc>().add(const SetScreenEvent('folder')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    PressableScale(
                      onTap: () => _openCamera(context),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.shadowLg,
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: AppTheme.onAccent, size: 26),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const LocationDetailOverlay(),
        ],
      ),
    );
  }
}
