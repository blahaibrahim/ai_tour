import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/glass_surface.dart';
import 'widgets/pressable_scale.dart';
import 'screens/map_screen.dart';
import 'screens/thinking_screen.dart';
import 'screens/swipe_screen.dart';
import 'screens/result_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/folder_screen.dart';
import 'screens/areas_map_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const AITourApp(),
    ),
  );
}

class AITourApp extends StatelessWidget {
  const AITourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Tour',
      theme: AppTheme.theme,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  Future<void> _openCamera(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file == null) return; // user cancelled
      state.addCapturedArtifact(file.path);
      messenger.showSnackBar(const SnackBar(content: Text('Added to your folder')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Camera unavailable on this device')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: currentScreen,
            ),
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
                          _NavButton(
                            icon: Icons.map_outlined,
                            label: 'Map',
                            isActive: state.screen == 'areasMap',
                            onTap: () => state.setScreen('areasMap'),
                          ),
                          const SizedBox(width: 4),
                          _NavButton(
                            icon: Icons.home_outlined,
                            label: 'Home',
                            isActive: state.screen == 'overview',
                            onTap: state.onNavHome,
                          ),
                          const SizedBox(width: 4),
                          _NavButton(
                            icon: Icons.folder_outlined,
                            label: 'Folder',
                            isActive: state.screen == 'folder',
                            onTap: () => state.setScreen('folder'),
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
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.brPill,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        padding: EdgeInsets.symmetric(horizontal: isActive ? 20 : 16, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accent : Colors.transparent,
          borderRadius: AppTheme.brPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isActive ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Icon(
                icon,
                size: 22,
                color: isActive ? AppTheme.onAccent : AppTheme.ink.withOpacity(0.5),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: isActive
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: AppTheme.theme.textTheme.headlineSmall?.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onAccent,
                        ),
                      ),
                    )
                  : const SizedBox(height: 22),
            ),
          ],
        ),
      ),
    );
  }
}
