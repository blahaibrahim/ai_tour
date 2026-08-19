import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One choice in a [SegmentedControl].
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
    this.semanticLabel,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Needed when [label] alone is ambiguous out of context — "2" reads as
  /// nothing useful without "days" attached.
  final String? semanticLabel;
}

/// A single-choice control where the options are few, fixed, and ordered.
///
/// Exists because the planner previously expressed *every* choice as the same
/// row of wrapping pills — region, theme, length, transport — which made four
/// unrelated decisions look like one long undifferentiated form and gave no
/// clue that the options within a group are mutually exclusive. A segmented
/// track is bounded and obviously single-choice, which is the right shape for
/// "how many days" and "how are you getting around" and the wrong shape for
/// the open-ended lists that stay as chips.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexWhere((o) => o.value == value);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Laid out by hand rather than with an Expanded row per segment,
        // because the selected indicator has to slide between positions and a
        // Flex gives no stable geometry to animate against.
        const padding = 4.0;
        final trackWidth = constraints.maxWidth;
        final segmentWidth = (trackWidth - padding * 2) / options.length;

        return Container(
          height: 46,
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: AppTheme.brPill,
          ),
          child: Stack(
            children: [
              if (selectedIndex >= 0)
                // Directional, not `left`: the Row of segments below already
                // reverses under an RTL Directionality, so a thumb positioned
                // from the physical left would slide to the opposite segment
                // from the one that is selected.
                AnimatedPositionedDirectional(
                  duration: AppTheme.motionBase,
                  curve: AppTheme.motionCurve,
                  start: segmentWidth * selectedIndex,
                  width: segmentWidth,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: AppTheme.brPill,
                      boxShadow: AppTheme.shadowSm,
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final option in options)
                    SizedBox(
                      width: segmentWidth,
                      child: _Segment<T>(
                        option: option,
                        isSelected: option.value == value,
                        onTap: () {
                          if (option.value == value) return;
                          HapticFeedback.selectionClick();
                          onChanged(option.value);
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final SegmentOption<T> option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? AppTheme.accentDark
        : AppTheme.text.withValues(alpha: 0.6);

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      label: option.semanticLabel ?? option.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        // The indicator sits behind, so only the painted glyph would be
        // hittable without this.
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 16, color: color),
                if (option.label.isNotEmpty) const SizedBox(width: AppTheme.space1 + 2),
              ],
              if (option.label.isNotEmpty)
                Flexible(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
