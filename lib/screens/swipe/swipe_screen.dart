import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/pressable_scale.dart';
import 'widgets/swipe_card.dart';
import 'widgets/swipe_progress_bar.dart';
import 'widgets/swipe_actions_bar.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  final Map<String, GlobalKey> _cardKeys = {};

  GlobalKey _getCardKey(String id) {
    return _cardKeys.putIfAbsent(id, () => GlobalKey());
  }

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

  void _onPanEnd(DragEndDetails details) {
    setState(() => _isDragging = false);

    final dx = _dragOffset.dx;
    final dy = _dragOffset.dy;

    if (dx > 110) {
      _flingAndCommit(true);
    } else if (dx < -110) {
      _flingAndCommit(false);
    } else if (dy > 110 && dx.abs() < 70) {
      final loc = context.read<AppBloc>().state.currentLoc;
      if (loc != null) context.read<AppBloc>().add(OpenDetailEvent(loc));
      setState(() => _dragOffset = Offset.zero);
    } else {
      setState(() => _dragOffset = Offset.zero);
    }
  }

  void _flingAndCommit(bool isAccept) {
    // Confirms the card is gone before it has finished leaving, which is what
    // makes a flick feel decided rather than merely started.
    HapticFeedback.lightImpact();

    final flyX = isAccept ? 700.0 : -700.0;

    _flyAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(flyX, _dragOffset.dy),
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _animationController.forward(from: 0).then((_) {
      if (!mounted) return;
      context.read<AppBloc>().add(CommitSwipeEvent(isAccept));
      setState(() => _dragOffset = Offset.zero);
    });
  }

  void _onBtnReject() { if (!_isDragging) _flingAndCommit(false); }
  void _onBtnAccept() { if (!_isDragging) _flingAndCommit(true); }

  void _onBtnUndo() {
    HapticFeedback.selectionClick();
    context.read<AppBloc>().add(const UndoSwipeEvent());
  }

  void _onBtnInfo() {
    final loc = context.read<AppBloc>().state.currentLoc;
    if (loc != null) context.read<AppBloc>().add(OpenDetailEvent(loc));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final currentLoc = state.currentLoc;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop(child: SizedBox.expand())),
          Column(
            children: [
              // Header
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Row(
                    children: [
                      PressableScale(
                        onTap: () => context.read<AppBloc>().add(const BackToMapEvent()),
                        child: GlassSurface(
                          borderRadius: AppTheme.brPill,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.arrow_back, size: 18),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // The route is already generated; this step only drops
                      // stops from it. "Skip review" therefore keeps all of
                      // them, which is a valid answer — unlike the old flow,
                      // where nothing was chosen until you swiped.
                      Builder(builder: (context) {
                        final reviewed = state.currentIndex;
                        final total = state.queue.length;
                        return ElevatedButton(
                          onPressed: () => context
                              .read<AppBloc>()
                              .add(const ConfirmReviewedStopsEvent()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.onAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                reviewed >= total ? 'Done' : 'Keep the rest ($reviewed/$total)',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded, size: 16),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // Main Content
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const cardAspectRatio = 1 / 1.45;
                    double maxW = constraints.maxWidth - 40;
                    double maxH = constraints.maxHeight - 28;
                    if (maxW < 0) maxW = 0;
                    if (maxH < 0) maxH = 0;

                    double cardW, cardH;
                    if (maxW / cardAspectRatio <= maxH) {
                      cardW = maxW;
                      cardH = maxW / cardAspectRatio;
                    } else {
                      cardH = maxH;
                      cardW = maxH * cardAspectRatio;
                    }
                    final topGap = (constraints.maxHeight - cardH) / 2;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Progress Bar
                        Positioned(
                          top: topGap / 2 - 2,
                          width: cardW,
                          child: SwipeProgressBar(width: cardW),
                        ),

                        // Cards Stack
                        Center(
                          child: SizedBox(
                            width: cardW,
                            height: cardH,
                            child: Stack(
                              children: [
                                // Background cards
                                ...(() {
                                  final bgCards = <Widget>[];
                                  const maxDepth = 3;
                                  final startIndex = math.min(
                                    state.queue.length - 1,
                                    state.currentIndex + maxDepth,
                                  );
                                  for (int i = startIndex; i > state.currentIndex; i--) {
                                    final loc = state.queue[i];
                                    final depth = i - state.currentIndex;
                                    final scale = 1.0 - (depth * 0.04);
                                    final dy = depth * 14.0;
                                    final dx = (depth.isEven ? 1 : -1) * depth * 6.0;
                                    final angle = (depth.isEven ? -1 : 1) * depth * 2.5 * (math.pi / 180);

                                    bgCards.add(
                                      Positioned.fill(
                                        key: ValueKey('bg_${loc.id}'),
                                        child: AnimatedContainer(
                                          key: _getCardKey(loc.id),
                                          duration: const Duration(milliseconds: 350),
                                          curve: Curves.easeOutCubic,
                                          transform: Matrix4.identity()
                                            ..translateByDouble(dx, dy, 0, 1)
                                            ..scaleByDouble(scale, scale, 1, 1)
                                            ..rotateZ(angle),
                                          transformAlignment: Alignment.center,
                                          child: SwipeCard(loc: loc, isBackground: true),
                                        ),
                                      ),
                                    );
                                  }
                                  return bgCards;
                                })(),

                                // Current card
                                if (currentLoc != null)
                                  Positioned.fill(
                                    key: ValueKey('fg_${currentLoc.id}'),
                                    child: (() {
                                      Widget cardNode = AnimatedContainer(
                                        key: _getCardKey(currentLoc.id),
                                        duration: const Duration(milliseconds: 350),
                                        curve: Curves.easeOutCubic,
                                        transform: Matrix4.identity(),
                                        transformAlignment: Alignment.center,
                                        child: SwipeCard(
                                          loc: currentLoc,
                                          dx: _dragOffset.dx,
                                          dy: _dragOffset.dy,
                                        ),
                                      );

                                      if (_animationController.isAnimating) {
                                        return AnimatedBuilder(
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
                                          child: cardNode,
                                        );
                                      } else {
                                        return GestureDetector(
                                          onPanStart: _onPanStart,
                                          onPanUpdate: _onPanUpdate,
                                          onPanEnd: _onPanEnd,
                                          child: Transform.translate(
                                            offset: _dragOffset,
                                            child: Transform.rotate(
                                              angle: _dragOffset.dx / 14 * (math.pi / 180),
                                              child: cardNode,
                                            ),
                                          ),
                                        );
                                      }
                                    })(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Actions
              SwipeActionsBar(
                onReject: _onBtnReject,
                onInfo: _onBtnInfo,
                onAccept: _onBtnAccept,
                onUndo: _onBtnUndo,
                canUndo: state.currentIndex > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
