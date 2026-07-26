import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/net_image.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/staggered_entrance.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final TextEditingController _aiController = TextEditingController();

  @override
  void dispose() {
    _aiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasStops = state.accepted.isNotEmpty;

    if (!hasStops) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.accent, size: 40),
                const SizedBox(height: 14),
                Text('No stops selected', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24)),
                const SizedBox(height: 8),
                Text(
                  'You passed on every suggestion. Try a wider radius or a new prompt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppTheme.text.withOpacity(0.75)),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => state.setScreen('map'),
                  child: const Text('Back to map'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalKm = state.accepted.fold<int>(0, (sum, loc) => sum + loc.distanceKm);
    final isMiles = false; // Add toggle if needed later
    final distanceLabel = isMiles ? '${(totalKm * 0.621371).round()} mi' : '$totalKm km';

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Text('Your route', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text(
                    '${state.accepted.length} stops · $distanceLabel',
                    style: TextStyle(fontSize: 13, color: AppTheme.text.withOpacity(0.75)),
                  ),
                  const SizedBox(height: 16),

                  // Trailer video stub
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.brLg,
                      boxShadow: AppTheme.shadowMd,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: NetImage(url: 'https://picsum.photos/seed/aitour-route-trailer/720/380', fit: BoxFit.cover),
                        ),
                        Positioned.fill(
                          child: Center(
                            child: PressableScale(
                              onTap: state.togglePlay,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppTheme.bg.withOpacity(0.92),
                                  shape: BoxShape.circle,
                                  boxShadow: AppTheme.shadowMd,
                                ),
                                child: const Icon(Icons.play_arrow, color: AppTheme.text, size: 26),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.text.withOpacity(0.65),
                              borderRadius: AppTheme.brPill,
                            ),
                            child: Text(
                              state.videoPlaying ? 'Playing preview…' : 'Tap to preview',
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Itinerary header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ITINERARY',
                        style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withOpacity(0.55)),
                      ),
                      TextButton(
                        onPressed: state.toggleModify,
                        child: Text(state.modifyMode ? 'Done' : 'Modify manually', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Stops list
                  ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.accepted.length,
                    itemBuilder: (context, i) {
                      final loc = state.accepted[i];
                      final isLast = i == state.accepted.length - 1;
                      return StaggeredEntrance(
                        index: i,
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Number and line
                          Column(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  color: AppTheme.tertiary,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(color: AppTheme.bg, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (!isLast)
                                Container(
                                  width: 2,
                                  height: 48,
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  color: AppTheme.secondary,
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          // Content
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                children: [
                                  NetImage(
                                    url: loc.thumbUrl,
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                    borderRadius: AppTheme.brMd,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(loc.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        Text(
                                          loc.region,
                                          style: TextStyle(fontSize: 12, color: AppTheme.text.withOpacity(0.65)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                    alignment: Alignment.centerRight,
                                    child: !state.modifyMode
                                        ? const SizedBox(height: 52)
                                        : AnimatedOpacity(
                                            opacity: state.modifyMode ? 1 : 0,
                                            duration: const Duration(milliseconds: 220),
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 8),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  PressableScale(
                                                    onTap: () => state.moveStop(i, -1),
                                                    child: Container(
                                                      width: 28,
                                                      height: 24,
                                                      margin: const EdgeInsets.only(bottom: 4),
                                                      decoration: BoxDecoration(color: AppTheme.surfaceSky, borderRadius: AppTheme.brSm),
                                                      child: const Icon(Icons.keyboard_arrow_up, size: 16, color: AppTheme.text),
                                                    ),
                                                  ),
                                                  PressableScale(
                                                    onTap: () => state.moveStop(i, 1),
                                                    child: Container(
                                                      width: 28,
                                                      height: 24,
                                                      decoration: BoxDecoration(color: AppTheme.surfaceSky, borderRadius: AppTheme.brSm),
                                                      child: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.text),
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
                        ],
                        ),
                      );
                    },
                  ),

                  // AI Chat panel
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: state.toggleAskPanel,
                    style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                    child: Text(
                      state.askPanelOpen ? 'Hide AI chat ▲' : 'Ask AI for changes ▼',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: !state.askPanelOpen
                        ? const SizedBox.shrink()
                        : Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceAlt,
                        borderRadius: AppTheme.brLg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (state.aiConversation.isNotEmpty)
                            ...state.aiConversation.map((msg) {
                              final isUser = msg.role == 'user';
                              return Align(
                                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isUser ? AppTheme.accentSky : AppTheme.neutral100,
                                    borderRadius: AppTheme.brMd,
                                  ),
                                  child: Text(msg.text, style: const TextStyle(fontSize: 12.5)),
                                ),
                              );
                            }),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _aiController,
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. swap in a coastal stop',
                                    filled: true,
                                    fillColor: AppTheme.bg,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PressableScale(
                                onTap: () {
                                  state.sendAIChange(_aiController.text);
                                  _aiController.clear();
                                },
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.tertiary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.send, color: AppTheme.bg, size: 16),
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
            ),
          ),
          
          // Accept Route Button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
            child: ElevatedButton(
              onPressed: state.onAcceptRoute,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('Accept this route'),
            ),
          ),
        ],
      ),
    );
  }
}
