import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';
import '../../../widgets/net_image.dart';
import '../../../widgets/pressable_scale.dart';
import '../../../widgets/staggered_entrance.dart';

/// Reorderable list of accepted stops for the result screen.
class ItineraryList extends StatelessWidget {
  const ItineraryList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final bloc = context.read<AppBloc>();

    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.accepted.length,
      onReorder: (oldIndex, newIndex) =>
          bloc.add(ReorderStopsEvent(oldIndex, newIndex)),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) =>
          Material(color: Colors.transparent, elevation: 0, child: child),
      itemBuilder: (context, i) {
        final loc = state.accepted[i];
        return StaggeredEntrance(
          key: ValueKey(loc.id),
          index: i,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PressableScale(
                  onTap: () => bloc.add(OpenDetailEvent(loc)),
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
                                      onTap: () => bloc.add(RemoveStopEvent(i)),
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
    );
  }
}
