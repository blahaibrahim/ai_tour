import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/app/app_bloc.dart';
import '../blocs/app/app_event.dart';
import '../blocs/app/app_state.dart';
import '../theme.dart';
import '../models/location.dart';
import 'glass_surface.dart';
import 'net_image.dart';
import 'pressable_scale.dart';

class LocationDetailOverlay extends StatefulWidget {
  const LocationDetailOverlay({super.key});

  @override
  State<LocationDetailOverlay> createState() => _LocationDetailOverlayState();
}

class _LocationDetailOverlayState extends State<LocationDetailOverlay> {
  Location? _lastDetailLoc;
  final TextEditingController _chatController = TextEditingController();

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final detailVisible = state.detailLoc != null;
    if (detailVisible) _lastDetailLoc = state.detailLoc;
    final loc = _lastDetailLoc;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !detailVisible,
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: detailVisible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: GestureDetector(
                onTap: () => context.read<AppBloc>().add(const CloseDetailEvent()),
                child: Container(
                  color: AppTheme.text.withOpacity(0.65),
                ),
              ),
            ),
            if (loc != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {}, // consume taps inside bottom sheet
                  child: AnimatedSlide(
                    offset: detailVisible ? Offset.zero : const Offset(0, 1.2),
                    duration: const Duration(milliseconds: 350),
                    curve: detailVisible ? Curves.easeOutCubic : Curves.easeIn,
                    child: _buildDetailPanel(loc, state),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel(Location loc, AppState state) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        boxShadow: AppTheme.shadowLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.divider, borderRadius: AppTheme.brPill),
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1 / 1.25,
                      child: Container(
                        decoration: BoxDecoration(borderRadius: AppTheme.brLg),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: NetImage(url: loc.detailPhotoUrl, fit: BoxFit.cover),
                            ),
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [AppTheme.photoScrim, AppTheme.photoScrimFade],
                                  stops: [0.0, 0.6],
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.name,
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 21),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, color: Colors.white, size: 14),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          loc.region,
                                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    loc.blurb,
                                    style: TextStyle(fontSize: 12.5, color: AppTheme.onNavy.withOpacity(0.9), height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                            // Save button
                            Positioned(
                              top: 12,
                              right: 12,
                              child: _SaveButton(loc: loc, state: state),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: AppTheme.divider, height: 1),
                    const SizedBox(height: 16),

                    Text(
                      'ASK THE AI',
                      style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withOpacity(0.55)),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => context.read<AppBloc>().add(const AskQuestionEvent("Best time to visit?")),
                          style: OutlinedButton.styleFrom(
                            textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 12.5),
                          ),
                          child: const Text('Best time to visit?'),
                        ),
                        OutlinedButton(
                          onPressed: () => context.read<AppBloc>().add(const AskQuestionEvent("How long to explore?")),
                          style: OutlinedButton.styleFrom(
                            textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 12.5),
                          ),
                          child: const Text('How long to explore?'),
                        ),
                      ],
                    ),

                    if (state.detailConversation.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...state.detailConversation.map((msg) {
                        final isAi = msg.role == 'ai';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isAi) ...[
                                const Icon(Icons.auto_awesome, color: AppTheme.accent, size: 16),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isAi ? AppTheme.surfaceAlt : AppTheme.accentSoft,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(AppTheme.radiusLg),
                                      topRight: const Radius.circular(AppTheme.radiusLg),
                                      bottomLeft: Radius.circular(isAi ? 0 : AppTheme.radiusLg),
                                      bottomRight: Radius.circular(isAi ? AppTheme.radiusLg : 0),
                                    ),
                                  ),
                                  child: Text(
                                    msg.text,
                                    style: TextStyle(fontSize: 13, height: 1.4, color: isAi ? AppTheme.text : AppTheme.accentDark),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ],
                ),
              ),
            ),

            // Chat input
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Container(
                decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: AppTheme.brMd),
                child: Stack(
                  children: [
                    TextField(
                      controller: _chatController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          context.read<AppBloc>().add(AskQuestionEvent(val));
                          _chatController.clear();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: "Ask anything about this spot...",
                        hintStyle: TextStyle(color: AppTheme.text.withOpacity(0.4), fontSize: 13),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(16, 14, 50, 14),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: PressableScale(
                        onTap: () {
                          if (_chatController.text.trim().isNotEmpty) {
                            context.read<AppBloc>().add(AskQuestionEvent(_chatController.text));
                            _chatController.clear();
                          }
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                          child: state.isChatLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onAccent),
                                )
                              : const Icon(Icons.arrow_upward_rounded, color: AppTheme.onAccent, size: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Row(
                children: [
                  if (state.screen == 'swipe') ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.read<AppBloc>().add(const OnDetailRejectEvent()),
                        child: const Text('Skip this spot'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<AppBloc>().add(const OnDetailAcceptEvent()),
                        child: const Text('Add to route'),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.read<AppBloc>().add(const CloseDetailEvent()),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.loc, required this.state});

  final Location loc;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final isSaved = state.savedLocationIds.contains(loc.id);
    return PressableScale(
      onTap: () => context.read<AppBloc>().add(ToggleSavedLocationEvent(loc.id)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSaved ? AppTheme.accent : AppTheme.photoScrim,
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            isSaved ? Icons.bookmark : Icons.bookmark_border,
            key: ValueKey(isSaved),
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
