import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../blocs/app/app_state.dart';
import '../../../models/route.dart' show formatMinutes;
import '../../../theme.dart';

/// How much time the traveller actually has, set the way an alarm is set.
///
/// The route module plans against this budget — how many stops fit, and whether
/// the answer needs more than one day — so it is not a cosmetic filter.
///
/// Two wheels rather than one, because they answer questions people know the
/// answers to separately: *how long is the trip* and *how much of each day is
/// spent walking around*. The minutes on the wire stay derived from both (see
/// [AppState.timeBudgetMinutes]) so there is no third number to disagree.
///
/// One selection band runs behind both wheels rather than each having its own,
/// which is what makes the pair read as a single setting — the same reason a
/// clock's hours and minutes sit under one highlight.
class TimeBudgetPicker extends StatelessWidget {
  const TimeBudgetPicker({super.key});

  /// Tall enough to show a value either side of the selection, short enough to
  /// leave the prompt and the button above the fold.
  static const double _rowExtent = 34;
  static const double _height = _rowExtent * 3.4;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final bloc = context.read<AppBloc>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'HOW MUCH TIME DO YOU HAVE?',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: AppTheme.text.withValues(alpha: 0.5),
              ),
            ),
            // The derived total, shown because it is what the server is
            // actually asked for — seeing the product makes "2 days × 4 h"
            // legible as eight hours of touring rather than something the
            // traveller has to work out.
            Text(
              formatMinutes(state.timeBudgetMinutes),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _height,
          child: Stack(
            children: [
              // The band sits under both wheels and is not part of either, so
              // the two columns cannot drift out of alignment with it.
              Center(
                child: Container(
                  height: _rowExtent,
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft.withValues(alpha: 0.55),
                    borderRadius: AppTheme.brMd,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: WheelPicker(
                      values: AppState.tripDayOptions,
                      selected: state.tripDays,
                      unit: (v) => v == 1 ? 'day' : 'days',
                      semanticLabel: 'Trip length in days',
                      rowExtent: _rowExtent,
                      onChanged: (v) => bloc.add(SetTripDaysEvent(v)),
                    ),
                  ),
                  Expanded(
                    child: WheelPicker(
                      values: AppState.hoursPerDayOptions,
                      selected: state.hoursPerDay,
                      unit: (_) => 'hours',
                      semanticLabel: 'Touring hours per day',
                      rowExtent: _rowExtent,
                      onChanged: (v) => bloc.add(SetHoursPerDayEvent(v)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // What each wheel is counting.
        //
        // "8 hours" on its own is genuinely ambiguous — eight hours of touring
        // in total, or eight on each of the days set beside it? The second is
        // what the budget means, and nothing on the wheel said so. Captions
        // rather than a longer unit ("hours/day") because the unit sits inches
        // from the number and has to stay short enough not to crowd it.
        const Row(
          children: [
            Expanded(child: _WheelCaption('for the whole trip')),
            Expanded(child: _WheelCaption('on each of those days')),
          ],
        ),
      ],
    );
  }
}

class _WheelCaption extends StatelessWidget {
  const _WheelCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.text.withValues(alpha: 0.5),
      ),
    );
  }
}

/// The index of [value] in [values], or the nearest one to it.
///
/// A restored budget can carry a value the picker no longer offers — the
/// options are a const list and a saved session is not. Snapping to the
/// nearest is the honest reading; `indexOf`'s -1 would scroll the wheel off
/// its own top.
int nearestIndex(List<int> values, int value) {
  if (values.isEmpty) return 0;
  final exact = values.indexOf(value);
  if (exact != -1) return exact;

  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if ((values[i] - value).abs() < (values[best] - value).abs()) best = i;
  }
  return best;
}

/// One spinning column of numbers, with its unit standing still beside it.
///
/// The unit does not scroll with the number: on an alarm picker the label is
/// part of the frame, not part of the list, and scrolling it would make the
/// wheel look like it holds twelve different words rather than twelve values
/// of one thing. It also keeps the digits in a straight column, which
/// "1 day" and "12 hours" would not.
class WheelPicker extends StatefulWidget {
  const WheelPicker({
    super.key,
    required this.values,
    required this.selected,
    required this.unit,
    required this.onChanged,
    required this.semanticLabel,
    this.rowExtent = 34,
  });

  final List<int> values;
  final int selected;

  /// The label beside the number, given the selected value so it can be
  /// singular or plural.
  final String Function(int) unit;

  final ValueChanged<int> onChanged;
  final String semanticLabel;
  final double rowExtent;

  @override
  State<WheelPicker> createState() => _WheelPickerState();
}

class _WheelPickerState extends State<WheelPicker> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: nearestIndex(widget.values, widget.selected));

  @override
  void didUpdateWidget(covariant WheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The value can also change from outside the wheel — a restored session,
    // or a reset. Follow it, but only when it is not already where it should
    // be, or this fights the settling scroll that produced the change.
    final target = nearestIndex(widget.values, widget.selected);
    if (_controller.hasClients && _controller.selectedItem != target) {
      _controller.animateToItem(
        target,
        duration: AppTheme.motionBase,
        curve: AppTheme.motionCurve,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSelected(int index) {
    final value = widget.values[index];
    if (value == widget.selected) return;
    HapticFeedback.selectionClick();
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      value: '${widget.selected} ${widget.unit(widget.selected)}',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 46,
            child: ListWheelScrollView.useDelegate(
              controller: _controller,
              itemExtent: widget.rowExtent,
              physics: const FixedExtentScrollPhysics(),
              // The drum curve. Kept shallow — a pronounced barrel looks like
              // a slot machine at this size rather than a clock.
              diameterRatio: 1.5,
              perspective: 0.003,
              overAndUnderCenterOpacity: 0.38,
              onSelectedItemChanged: _onSelected,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: widget.values.length,
                builder: (context, index) {
                  final isSelected = widget.values[index] == widget.selected;
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${widget.values[index]}',
                      style: TextStyle(
                        fontSize: 21,
                        height: 1,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? AppTheme.accentDark : AppTheme.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(
              widget.unit(widget.selected),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.text.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
