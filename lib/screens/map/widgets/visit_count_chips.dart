import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';

/// A horizontally-scrolling row of chips for selecting the desired stop count.
class VisitCountChips extends StatelessWidget {
  const VisitCountChips({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _VisitChip(
            label: 'Any',
            isSelected: state.wantedVisits == null,
            onTap: () => context.read<AppBloc>().add(const SetWantedVisitsEvent(null)),
          ),
          for (final v in [3, 5, 8, 10, 15, 20])
            _VisitChip(
              label: '$v stops',
              isSelected: state.wantedVisits == v,
              onTap: () => context.read<AppBloc>().add(SetWantedVisitsEvent(v)),
            ),
        ],
      ),
    );
  }
}

class _VisitChip extends StatelessWidget {
  const _VisitChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentSoft : Colors.transparent,
          borderRadius: AppTheme.brPill,
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.text.withOpacity(0.15),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? AppTheme.accentDark : AppTheme.text.withOpacity(0.65),
          ),
        ),
      ),
    );
  }
}
