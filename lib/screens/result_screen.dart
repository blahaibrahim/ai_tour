import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/app_backdrop.dart';
import '../widgets/glass_surface.dart';
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
  bool _showCalendar = false;

  DateTime? _getEndDate(AppState state) {
    if (state.tripDate == null) return null;
    return state.tripEndDate ?? state.tripDate;
  }

  String _getDateText(AppState state) {
    if (state.tripDate == null) {
      int days = (state.accepted.length / 2).ceil();
      if (days < 1) days = 1;
      return '$days day${days > 1 ? 's' : ''}';
    }
    final start = state.tripDate!;
    final end = _getEndDate(state)!;
    
    String startStr = '${start.month}/${start.day}';
    if (isSameDay(start, end)) return startStr;
    String endStr = '${end.month}/${end.day}';
    return '$startStr - $endStr';
  }

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
        body: AppBackdrop(child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.deepNavy,
                  ),
                  child: const Icon(Icons.check_circle_outline, color: AppTheme.onNavy, size: 34),
                ),
                const SizedBox(height: 16),
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
        )),
      );
    }



    return Scaffold(
      body: AppBackdrop(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      PressableScale(
                        onTap: () => state.setScreen('map'),
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
                      const SizedBox(width: 16),
                      Text('Your route', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentSoft,
                            borderRadius: AppTheme.brPill,
                          ),
                          child: Text(
                            '${state.accepted.length} stops',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.accentDark),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressableScale(
                          onTap: () {
                            setState(() {
                              _showCalendar = !_showCalendar;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: _showCalendar ? AppTheme.accentSoft : AppTheme.surfaceAlt,
                              borderRadius: AppTheme.brPill,
                              border: Border.all(
                                color: _showCalendar ? AppTheme.accent.withOpacity(0.5) : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 12, color: _showCalendar ? AppTheme.accentDark : AppTheme.text),
                                const SizedBox(width: 6),
                                Text(
                                  state.tripDate == null ? 'Schedule trip' : _getDateText(state),
                                  style: TextStyle(
                                    fontSize: 12.5, 
                                    fontWeight: FontWeight.w700, 
                                    color: _showCalendar ? AppTheme.accentDark : AppTheme.text
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (state.tripDate != null) ...[
                          const SizedBox(width: 8),
                          PressableScale(
                            onTap: () => state.setTripDate(null, null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.error.withOpacity(0.12),
                                borderRadius: AppTheme.brPill,
                              ),
                              child: const Text(
                                'Clear',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.error,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_showCalendar) ...[
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceAlt,
                        borderRadius: AppTheme.brMd,
                      ),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TableCalendar(
                        firstDay: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                        lastDay: DateTime.now().add(const Duration(days: 365 * 5)),
                        focusedDay: state.tripDate != null && !state.tripDate!.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) 
                            ? state.tripDate! 
                            : DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                        rangeStartDay: state.tripDate,
                        rangeEndDay: state.tripEndDate,
                        rangeSelectionMode: RangeSelectionMode.toggledOn,
                        onRangeSelected: (start, end, focusedDay) {
                          state.setTripDate(start, end);
                        },
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                        ),
                        calendarStyle: CalendarStyle(
                          rangeHighlightColor: AppTheme.accent.withOpacity(0.2),
                          rangeStartDecoration: const BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          rangeEndDecoration: const BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          todayDecoration: BoxDecoration(
                            color: AppTheme.accentSoft,
                            shape: BoxShape.circle,
                          ),
                          todayTextStyle: const TextStyle(color: AppTheme.accentDark),
                        ),
                      ),
                    ),
                  ],
                  Builder(
                    builder: (context) {
                      bool isUnrealistic = false;
                      int currentDays = 1;
                      if (state.tripDate != null) {
                        final end = _getEndDate(state)!;
                        currentDays = end.difference(state.tripDate!).inDays + 1;
                        isUnrealistic = (currentDays * 3) < state.accepted.length;
                      }
                      if (!isUnrealistic) return const SizedBox(height: 16);
                      
                      return Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.15),
                            borderRadius: AppTheme.brMd,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 18),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  currentDays == 1 
                                      ? 'This might be too packed for 1 day. Try extending the trip or removing stops.'
                                      : 'This might be too packed for a $currentDays-day trip. Try extending the trip or removing stops.',
                                  style: const TextStyle(fontSize: 12.5, color: AppTheme.error, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  ),

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
                  ReorderableListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.accepted.length,
                    onReorder: state.reorderStops,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        color: Colors.transparent,
                        elevation: 0,
                        child: child,
                      );
                    },
                    itemBuilder: (context, i) {
                      final loc = state.accepted[i];
                      return StaggeredEntrance(
                        key: ValueKey(loc.id),
                        index: i,
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Content
                          Expanded(
                            child: PressableScale(
                              onTap: () => state.openDetail(loc),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Row(
                                children: [
                                  if (state.modifyMode)
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 14),
                                        child: Container(
                                          width: 36,
                                          height: 36,
                                          decoration: const BoxDecoration(
                                            color: AppTheme.surfaceAlt,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.drag_indicator, size: 20, color: AppTheme.text),
                                        ),
                                      ),
                                    ),
                                  NetImage(
                                    url: loc.thumbUrl,
                                    width: 90,
                                    height: 65,
                                    fit: BoxFit.cover,
                                    borderRadius: AppTheme.brMd,
                                  ),
                                  const SizedBox(width: 14),
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
                                        ? const SizedBox(height: 65)
                                        : AnimatedOpacity(
                                            opacity: state.modifyMode ? 1 : 0,
                                            duration: const Duration(milliseconds: 220),
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 12),
                                              child: PressableScale(
                                                onTap: () => state.removeStop(i),
                                                child: Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.error.withOpacity(0.12),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(Icons.delete_outline, size: 20, color: AppTheme.error),
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ),
                        ],
                        ),
                      );
                    },
                  ),


                ],
              ),
            ),
          ),
          
          // Static Chat Prompt
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: AppTheme.brMd,
              ),
              child: Stack(
                children: [
                  TextField(
                    controller: _aiController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        state.setPrompt(val);
                        state.onGenerate();
                        _aiController.clear();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'e.g. swap in a coastal stop',
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
                        if (_aiController.text.trim().isNotEmpty) {
                          state.setPrompt(_aiController.text);
                          state.onGenerate();
                          _aiController.clear();
                        }
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_upward_rounded, color: AppTheme.onAccent, size: 15),
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
      ),
    );
  }
}
