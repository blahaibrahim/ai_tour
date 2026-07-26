import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../models/location.dart';
import '../widgets/net_image.dart';
import '../widgets/pressable_scale.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  Location? _lastDetailLoc;

  late AnimationController _animationController;
  late Animation<Offset> _flyAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffset = Offset.zero;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details, AppState state) {
    setState(() {
      _isDragging = false;
    });

    final dx = _dragOffset.dx;
    final dy = _dragOffset.dy;

    if (dx > 110) {
      _flingAndCommit(true, state);
    } else if (dx < -110) {
      _flingAndCommit(false, state);
    } else if (dy > 110 && dx.abs() < 70) {
      final loc = state.getCurrentLoc();
      if (loc != null) state.openDetail(loc);
      setState(() {
        _dragOffset = Offset.zero;
      });
    } else {
      // Snap back
      setState(() {
        _dragOffset = Offset.zero;
      });
    }
  }

  void _flingAndCommit(bool isAccept, AppState state) {
    final flyX = isAccept ? 700.0 : -700.0;
    
    _flyAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(flyX, _dragOffset.dy),
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _animationController.forward(from: 0).then((_) {
      state.commitSwipe(isAccept);
      setState(() {
        _dragOffset = Offset.zero;
      });
    });
  }

  void _onBtnReject(AppState state) {
    if (!_isDragging) {
      _flingAndCommit(false, state);
    }
  }

  void _onBtnAccept(AppState state) {
    if (!_isDragging) {
      _flingAndCommit(true, state);
    }
  }

  void _onBtnInfo(AppState state) {
    final loc = state.getCurrentLoc();
    if (loc != null) state.openDetail(loc);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentLoc = state.getCurrentLoc();
    
    final nextIndex = state.currentIndex + 1;
    final nextLoc = nextIndex < state.queue.length ? state.queue[nextIndex] : null;

    final swipeProgressLabel = currentLoc != null ? '${state.currentIndex + 1} of ${state.queue.length}' : '';

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PressableScale(
                        onTap: state.onBackToMap,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            shape: BoxShape.circle,
                            boxShadow: AppTheme.shadowSm,
                          ),
                          child: const Icon(Icons.arrow_back, size: 18),
                        ),
                      ),
                      Text(
                        swipeProgressLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.text.withOpacity(0.65),
                        ),
                      ),
                      const SizedBox(width: 40), // Balance header
                    ],
                  ),
                ),
              ),

              // Cards
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Stack(
                    children: [
                      // Next card
                      if (nextLoc != null)
                        Positioned.fill(
                          child: Transform.scale(
                            scale: 0.95,
                            child: Transform.translate(
                              offset: const Offset(0, 14),
                              child: _buildCardContent(nextLoc, isBackground: true),
                            ),
                          ),
                        ),
                      
                      // Current card
                      if (currentLoc != null)
                        Positioned.fill(
                          child: _animationController.isAnimating
                              ? AnimatedBuilder(
                                  animation: _flyAnimation,
                                  builder: (context, child) {
                                    return Transform.translate(
                                      offset: _flyAnimation.value,
                                      child: Transform.rotate(
                                        angle: _flyAnimation.value.dx / 14 * (math.pi / 180),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _buildCardContent(currentLoc, dx: _dragOffset.dx, dy: _dragOffset.dy),
                                )
                              : GestureDetector(
                                  onPanStart: _onPanStart,
                                  onPanUpdate: _onPanUpdate,
                                  onPanEnd: (details) => _onPanEnd(details, state),
                                  child: Transform.translate(
                                    offset: _dragOffset,
                                    child: Transform.rotate(
                                      angle: _dragOffset.dx / 14 * (math.pi / 180),
                                      child: _buildCardContent(currentLoc, dx: _dragOffset.dx, dy: _dragOffset.dy),
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PressableScale(
                      onTap: () => _onBtnReject(state),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.shadowMd,
                        ),
                        child: const Icon(Icons.close, color: AppTheme.textSecondary, size: 28),
                      ),
                    ),
                    const SizedBox(width: 22),
                    PressableScale(
                      onTap: () => _onBtnInfo(state),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.shadowSm,
                        ),
                        child: const Icon(Icons.info_outline, color: AppTheme.text, size: 22),
                      ),
                    ),
                    const SizedBox(width: 22),
                    PressableScale(
                      onTap: () => _onBtnAccept(state),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.shadowLg,
                        ),
                        child: const Icon(Icons.favorite, color: AppTheme.onAccent, size: 28),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Detail View Overlay
          Builder(builder: (context) {
            final detailVisible = state.detailLoc != null;
            if (detailVisible) _lastDetailLoc = state.detailLoc;
            final loc = _lastDetailLoc;

            return Positioned.fill(
              child: IgnorePointer(
                ignoring: !detailVisible,
                child: AnimatedOpacity(
                  opacity: detailVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: loc == null
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: state.closeDetail,
                          child: Container(
                            color: AppTheme.text.withOpacity(0.65), // Off black overlay
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: GestureDetector(
                                onTap: () {}, // consume taps inside bottom sheet
                                child: AnimatedSlide(
                                  offset: detailVisible ? Offset.zero : const Offset(0, 0.05),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  child: _buildDetailPanel(loc, state),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCardContent(Location loc, {bool isBackground = false, double dx = 0, double dy = 0}) {
    final likeOpacity = (dx / 110).clamp(0.0, 1.0);
    final nopeOpacity = (-dx / 110).clamp(0.0, 1.0);
    final infoOpacity = ((dy / 110).clamp(0.0, 1.0) * (1 - (dx.abs() / 70).clamp(0.0, 1.0)));

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppTheme.brXl,
        boxShadow: AppTheme.shadowLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImage(url: loc.photoUrl, fit: BoxFit.cover),

          // Soft gradient for legibility of overlaid text
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomRight,
                end: Alignment.topLeft,
                colors: [
                  const Color(0xCC000000),
                  const Color(0x00000000),
                ],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
          
          // Labels (LIKE, NOPE, MORE INFO)
          if (!isBackground) ...[
            Positioned(
              top: 16,
              left: 16,
              child: Opacity(
                opacity: likeOpacity,
                child: Transform.rotate(
                  angle: -14 * (math.pi / 180),
                  child: _buildBadge('LIKE', AppTheme.accent),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Opacity(
                opacity: nopeOpacity,
                child: Transform.rotate(
                  angle: 14 * (math.pi / 180),
                  child: _buildBadge('NOPE', AppTheme.textSecondary),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Opacity(
                  opacity: infoOpacity,
                  child: _buildBadge('MORE INFO ↓', AppTheme.text),
                ),
              ),
            ),
          ],
          
          // Content
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          loc.name,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 20),
                        ),
                      ),
                      Text(
                        loc.distanceLabel(false), // Assuming km
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTag(loc.category, AppTheme.surfaceSky, AppTheme.text),
                      const SizedBox(width: 6),
                      _buildTag(loc.region, AppTheme.bg, AppTheme.text),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    loc.blurb,
                    style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: AppTheme.brPill,
        boxShadow: AppTheme.shadowSm,
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _buildTag(String text, Color bg, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppTheme.brPill,
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, letterSpacing: 0.2, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildDetailPanel(Location loc, AppState state) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        boxShadow: AppTheme.shadowLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: AppTheme.brPill,
              ),
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.brLg,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: NetImage(url: loc.detailPhotoUrl, fit: BoxFit.cover),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                const Color(0xC7140E08),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.6],
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
                                  _buildTag(loc.category, AppTheme.surfaceSky, AppTheme.text),
                                  const SizedBox(width: 6),
                                  _buildTag(loc.region, AppTheme.bg, AppTheme.text),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loc.blurb,
                    style: TextStyle(fontSize: 13.5, color: AppTheme.text.withOpacity(0.85), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.divider, height: 1),
                  const SizedBox(height: 16),
                  
                  Text(
                    'ASK THE AI',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      color: AppTheme.text.withOpacity(0.55),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => state.askQuestion("Early morning or just before sunset — softer light, thinner crowds."),
                        style: OutlinedButton.styleFrom(
                          textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 12.5),
                        ),
                        child: const Text('Best time to visit?'),
                      ),
                      OutlinedButton(
                        onPressed: () => state.askQuestion("Budget 2–3 hours to explore at an easy pace."),
                        style: OutlinedButton.styleFrom(
                          textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 12.5),
                        ),
                        child: const Text('How long to explore?'),
                      ),
                    ],
                  ),
                  
                  if (state.detailAnswer != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceAlt,
                        borderRadius: AppTheme.brLg,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.send, color: AppTheme.accent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.detailAnswer!,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: state.onDetailReject,
                    child: const Text('Skip this spot'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: state.onDetailAccept,
                    child: const Text('Add to route'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
