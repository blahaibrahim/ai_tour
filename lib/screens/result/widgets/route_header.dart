import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';
import '../../../widgets/pressable_scale.dart';

/// Header row showing stop count badge and a toggleable calendar date picker.
class RouteHeader extends StatefulWidget {
  const RouteHeader({super.key});

  @override
  State<RouteHeader> createState() => _RouteHeaderState();
}

class _RouteHeaderState extends State<RouteHeader> {
  bool _showCalendar = false;

  DateTime? _getEndDate(state) {
    if (state.tripDate == null) return null;
    return state.tripEndDate ?? state.tripDate;
  }

  String _getDateText(state) {
    if (state.tripDate == null) {
      int days = (state.accepted.length / 2).ceil();
      if (days < 1) days = 1;
      return '$days day${days > 1 ? 's' : ''}';
    }
    final start = state.tripDate!;
    final end = _getEndDate(state)!;
    final startStr = '${start.month}/${start.day}';
    if (isSameDay(start, end)) return startStr;
    return '$startStr - ${end.month}/${end.day}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onTap: () => setState(() => _showCalendar = !_showCalendar),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _showCalendar ? AppTheme.accentSoft : AppTheme.surfaceAlt,
                    borderRadius: AppTheme.brPill,
                    border: Border.all(
                      color: _showCalendar ? AppTheme.accent.withOpacity(0.5) : Colors.transparent,
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
                          color: _showCalendar ? AppTheme.accentDark : AppTheme.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.tripDate != null) ...[
                const SizedBox(width: 8),
                PressableScale(
                  onTap: () => context.read<AppBloc>().add(const SetTripDateEvent(null, null)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.12),
                      borderRadius: AppTheme.brPill,
                    ),
                    child: const Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.error)),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (_showCalendar) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: AppTheme.brMd),
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
                context.read<AppBloc>().add(SetTripDateEvent(start, end));
              },
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              calendarStyle: CalendarStyle(
                rangeHighlightColor: AppTheme.accent.withOpacity(0.2),
                rangeStartDecoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                rangeEndDecoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                todayDecoration: BoxDecoration(color: AppTheme.accentSoft, shape: BoxShape.circle),
                todayTextStyle: const TextStyle(color: AppTheme.accentDark),
              ),
            ),
          ),
        ],

        // Packing warning
        Builder(builder: (context) {
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
              decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.15), borderRadius: AppTheme.brMd),
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
        }),
      ],
    );
  }
}
