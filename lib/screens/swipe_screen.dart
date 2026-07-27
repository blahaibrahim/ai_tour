import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../models/location.dart';
import '../widgets/app_backdrop.dart';
import '../widgets/glass_surface.dart';
import '../widgets/net_image.dart';
import '../widgets/pressable_scale.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  Location? _lastDetailLoc;
  final Map<String, GlobalKey> _cardKeys = {};

  GlobalKey _getCardKey(String id) {
    return _cardKeys.putIfAbsent(id, () => GlobalKey());
  }

  late AnimationController _animationController;
  late Animation<Offset> _flyAnimation;
  final TextEditingController _chatController = TextEditingController();

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
    _chatController.dispose();
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

    _flyAnimation =
        Tween<Offset>(
          begin: _dragOffset,
          end: Offset(flyX, _dragOffset.dy),
        ).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

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
    final nextLoc = nextIndex < state.queue.length
        ? state.queue[nextIndex]
        : null;

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
                        onTap: state.onBackToMap,
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
                      if (state.accepted.length >= state.wantedVisits)
                        ElevatedButton(
                          onPressed: () {
                            state.setScreen('result');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.onAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Proceed (${state.accepted.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded, size: 16),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceAlt,
                            borderRadius: AppTheme.brPill,
                          ),
                          child: Text(
                            '${state.accepted.length} / ${state.wantedVisits} stops',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.text,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Main Content
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardAspectRatio = 1 / 1.45;
                    double maxW =
                        constraints.maxWidth - 40; // 20px padding on each side
                    double maxH =
                        constraints.maxHeight -
                        28; // 14px padding top and bottom
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

                    double topGap = (constraints.maxHeight - cardH) / 2;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Progress Bar (perfectly centered between top and card)
                        Positioned(
                          top: topGap / 2 - 2, // -2 for half the height
                          width: cardW,
                          child: Row(
                            children: List.generate(state.queue.length, (
                              index,
                            ) {
                              final isActive = index == state.currentIndex;
                              final isCompleted = index < state.currentIndex;
                              return Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.accent
                                        : (isCompleted
                                              ? AppTheme.accent.withOpacity(0.4)
                                              : AppTheme.text.withOpacity(
                                                  0.15,
                                                )),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),

                        // Cards Stack
                        Center(
                          child: SizedBox(
                            width: cardW,
                            height: cardH,
                            child: Stack(
                              children: [
                                // Background messy cards
                                ...(() {
                                  final bgCards = <Widget>[];
                                  final maxDepth = 3;
                                  final startIndex = math.min(
                                    state.queue.length - 1,
                                    state.currentIndex + maxDepth,
                                  );
                                  for (
                                    int i = startIndex;
                                    i > state.currentIndex;
                                    i--
                                  ) {
                                    final loc = state.queue[i];
                                    final depth = i - state.currentIndex;

                                    double scale = 1.0 - (depth * 0.04);
                                    double dy = depth * 14.0;
                                    double dx =
                                        (depth.isEven ? 1 : -1) * depth * 6.0;
                                    double angle =
                                        (depth.isEven ? -1 : 1) *
                                        depth *
                                        2.5 *
                                        (math.pi / 180);

                                    bgCards.add(
                                      Positioned.fill(
                                        key: ValueKey('bg_${loc.id}'),
                                        child: AnimatedContainer(
                                          key: _getCardKey(loc.id),
                                          duration: const Duration(
                                            milliseconds: 350,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          transform: Matrix4.identity()
                                            ..translate(dx, dy)
                                            ..scale(scale, scale, 1.0)
                                            ..rotateZ(angle),
                                          transformAlignment: Alignment.center,
                                          child: _buildCardContent(
                                            loc,
                                            state,
                                            isBackground: true,
                                          ),
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
                                        duration: const Duration(
                                          milliseconds: 350,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        transform: Matrix4.identity(),
                                        transformAlignment: Alignment.center,
                                        child: _buildCardContent(
                                          currentLoc,
                                          state,
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
                                                angle:
                                                    _flyAnimation.value.dx /
                                                    14 *
                                                    (math.pi / 180),
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
                                          onPanEnd: (details) =>
                                              _onPanEnd(details, state),
                                          child: Transform.translate(
                                            offset: _dragOffset,
                                            child: Transform.rotate(
                                              angle:
                                                  _dragOffset.dx /
                                                  14 *
                                                  (math.pi / 180),
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
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PressableScale(
                      onTap: () => _onBtnReject(state),
                      child: GlassSurface(
                        borderRadius: AppTheme.brPill,
                        boxShadow: AppTheme.shadowMd,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 58,
                          height: 58,
                          child: Icon(
                            Icons.close,
                            color: AppTheme.textSecondary,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 22),
                    PressableScale(
                      onTap: () => _onBtnInfo(state),
                      child: GlassSurface(
                        borderRadius: AppTheme.brPill,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.info_outline,
                            color: AppTheme.text,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 22),
                    PressableScale(
                      onTap: () => _onBtnAccept(state),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: AppTheme.heroGradient,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.shadowLg,
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: AppTheme.onAccent,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Detail View Overlay
          Builder(
            builder: (context) {
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
                          onTap: state.closeDetail,
                          child: Container(
                            color: AppTheme.text.withOpacity(
                              0.65,
                            ), // Off black overlay
                          ),
                        ),
                      ),
                      if (loc != null)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: GestureDetector(
                            onTap: () {}, // consume taps inside bottom sheet
                            child: AnimatedSlide(
                              offset: detailVisible
                                  ? Offset.zero
                                  : const Offset(
                                      0,
                                      1.2,
                                    ), // 1.2 ensures it fully clears screen including bounce
                              duration: const Duration(milliseconds: 350),
                              curve: detailVisible
                                  ? Curves.easeOutCubic
                                  : Curves.easeIn,
                              child: _buildDetailPanel(loc, state),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent(
    Location loc,
    AppState state, {
    bool isBackground = false,
    double dx = 0,
    double dy = 0,
  }) {
    final likeOpacity = (dx / 110).clamp(0.0, 1.0);
    final nopeOpacity = (-dx / 110).clamp(0.0, 1.0);
    final infoOpacity =
        ((dy / 110).clamp(0.0, 1.0) * (1 - (dx.abs() / 70).clamp(0.0, 1.0)));

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Dark background while image loads
        borderRadius: BorderRadius.circular(40),
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
                colors: [const Color(0xCC000000), const Color(0x00000000)],
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
                  Text(
                    loc.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          loc.region,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.3,
                          ),
                        ),
                      ),
                      PressableScale(
                        onTap: () => state.toggleSavedLocation(loc.id),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Icon(
                            state.savedLocationIds.contains(loc.id)
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: state.savedLocationIds.contains(loc.id)
                                ? AppTheme.accent
                                : Colors.white,
                            size: 42,
                          ),
                        ),
                      ),
                    ],
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
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color bg, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: AppTheme.brPill),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildDetailPanel(Location loc, AppState state) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXl),
        ),
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
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: AppTheme.brPill,
                ),
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1 / 1.45,
                      child: Container(
                        decoration: BoxDecoration(borderRadius: AppTheme.brLg),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: NetImage(
                                url: loc.detailPhotoUrl,
                                fit: BoxFit.cover,
                              ),
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontSize: 21,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          loc.region,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    loc.blurb,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withOpacity(0.9),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                          onPressed: () => state.askQuestion(
                            "Best time to visit?",
                            "Early morning or just before sunset — softer light, thinner crowds.",
                          ),
                          style: OutlinedButton.styleFrom(
                            textStyle: Theme.of(
                              context,
                            ).textTheme.headlineSmall?.copyWith(fontSize: 12.5),
                          ),
                          child: const Text('Best time to visit?'),
                        ),
                        OutlinedButton(
                          onPressed: () => state.askQuestion(
                            "How long to explore?",
                            "Budget 2–3 hours to explore at an easy pace.",
                          ),
                          style: OutlinedButton.styleFrom(
                            textStyle: Theme.of(
                              context,
                            ).textTheme.headlineSmall?.copyWith(fontSize: 12.5),
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
                            mainAxisAlignment: isAi
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isAi) ...[
                                const Icon(
                                  Icons.auto_awesome,
                                  color: AppTheme.accent,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isAi
                                        ? AppTheme.surfaceAlt
                                        : AppTheme.accentSoft,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(
                                        AppTheme.radiusLg,
                                      ),
                                      topRight: const Radius.circular(
                                        AppTheme.radiusLg,
                                      ),
                                      bottomLeft: Radius.circular(
                                        isAi ? 0 : AppTheme.radiusLg,
                                      ),
                                      bottomRight: Radius.circular(
                                        isAi ? AppTheme.radiusLg : 0,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    msg.text,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: isAi
                                          ? AppTheme.text
                                          : AppTheme.accentDark,
                                    ),
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

            // Static Text Area for chat prompt
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: AppTheme.brMd,
                ),
                child: Stack(
                  children: [
                    TextField(
                      controller: _chatController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          state.askQuestion(
                            val,
                            "I'm a local AI guide. This place is amazing, you should definitely visit!",
                          );
                          _chatController.clear();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: "Ask anything about this spot...",
                        hintStyle: TextStyle(
                          color: AppTheme.text.withOpacity(0.4),
                          fontSize: 13,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(
                          16,
                          14,
                          50,
                          14,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: PressableScale(
                        onTap: () {
                          if (_chatController.text.trim().isNotEmpty) {
                            state.askQuestion(
                              _chatController.text,
                              "I'm a local AI guide. This place is amazing, you should definitely visit!",
                            );
                            _chatController.clear();
                          }
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_upward_rounded,
                            color: AppTheme.onAccent,
                            size: 15,
                          ),
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
      ),
    );
  }
}
