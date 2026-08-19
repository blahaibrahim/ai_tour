import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../blocs/app/app_state.dart';
import '../../../models/route.dart' show formatMinutes;
import '../../../l10n/app_localizations.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/location_search_bar.dart';
import '../../../utils/geojson_parser.dart';
import 'time_budget_picker.dart';

/// The route request builder, docked to the bottom of the map screen.
///
/// The panel is collapsed by default and deliberately short, because the
/// decision it exists to serve — *which part of the country* — is made on the
/// map behind it, and a sheet tall enough to hold every control was covering
/// the thing the user was being asked to point at. Collapsed it carries only
/// what is needed to make that choice and act on it: search, what is currently
/// selected, and the generate button.
///
/// Time budget and prompt live one tap away rather than being cut. Both have
/// working defaults, so a traveller who does not care never opens the drawer;
/// a traveller who does gets them without leaving the screen. The collapsed
/// state summarises them ("2 days · 4h · quiet Roman ruins") so what is hidden
/// is never a mystery.
class MapBottomPanel extends StatefulWidget {
  const MapBottomPanel({super.key});

  @override
  State<MapBottomPanel> createState() => _MapBottomPanelState();
}

class _MapBottomPanelState extends State<MapBottomPanel> {
  bool _expanded = false;

  /// Ceiling on the panel's share of the screen, expanded.
  ///
  /// Even opened, the map has to stay the larger half — the panel is a control
  /// surface over a map, not a page with a map behind it. Anything past this
  /// scrolls inside the panel.
  static const double _maxHeightFraction = 0.52;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final bloc = context.read<AppBloc>();
    final maxHeight = MediaQuery.sizeOf(context).height * _maxHeightFraction;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        boxShadow: AppTheme.shadowLg,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tapping the handle toggles the drawer as well as the row
                // below it, since a grabber that does nothing when pulled is
                // the usual complaint about sheets that only look draggable.
                _GrabHandle(onTap: () => setState(() => _expanded = !_expanded)),
                const SizedBox(height: 10),

                const LocationSearchBar(),
                const SizedBox(height: 10),

                _SelectedWilayas(selected: state.selectedWilayas),

                // AnimatedSize rather than a swap, so opening the drawer reads
                // as the panel growing from the bottom edge instead of the map
                // being replaced.
                AnimatedSize(
                  duration: AppTheme.motionBase,
                  curve: AppTheme.motionCurve,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            const TimeBudgetPicker(),
                            const SizedBox(height: 12),
                            _PromptField(onChanged: (v) => bloc.add(SetPromptEvent(v))),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),

                const SizedBox(height: 8),
                _DetailsToggle(
                  expanded: _expanded,
                  summary: _summarise(AppLocalizations.of(context), state),
                  onTap: () => setState(() => _expanded = !_expanded),
                ),

                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => bloc.add(const GenerateRouteEvent()),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Text(AppLocalizations.of(context).mapGenerateRoute,
                      style: const TextStyle(fontSize: 14.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One line standing in for everything the collapsed panel hides.
  static String _summarise(AppLocalizations l10n, AppState state) {
    final parts = <String>[
      l10n.mapTripDays(state.tripDays),
      formatMinutes(l10n, state.hoursPerDay * 60),
    ];
    final prompt = state.prompt.trim();
    if (prompt.isNotEmpty) parts.add(prompt);
    return parts.join(' · ');
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).mapExpandTripOptions,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.3),
              borderRadius: AppTheme.brPill,
            ),
          ),
        ),
      ),
    );
  }
}

/// The wilaya readout: which one wilaya the trip is being planned in.
///
/// Singular throughout, matching what the app can actually route. There is no
/// count badge because a count that only ever reads 0 or 1 is noise, and no
/// plural copy because it would advertise a multi-select the map refuses to
/// perform. See `AppBloc._onToggleWilaya` for why the restriction exists and
/// what has to change to lift it.
class _SelectedWilayas extends StatelessWidget {
  const _SelectedWilayas({required this.selected});

  final Set<String> selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: FutureBuilder<List<WilayaPolygon>>(
        future: loadWilayasGeoJson(),
        builder: (context, snapshot) {
          final name = _selectedName(snapshot.data);

          if (name == null) {
            return Row(
              children: [
                const Icon(Icons.touch_app_outlined, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).mapTapToPickWilaya,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: AppTheme.brPill,
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Says how to change it, since tapping a second wilaya swapping
              // out the first is the one thing about single-select that isn't
              // guessable from looking at it.
              Flexible(
                child: Text(
                  AppLocalizations.of(context).mapTapAnotherToSwitch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _selectedName(List<WilayaPolygon>? wilayas) {
    if (wilayas == null || selected.isEmpty) return null;
    for (final w in wilayas) {
      if (selected.contains(w.id)) return w.name;
    }
    return null;
  }
}

class _PromptField extends StatelessWidget {
  const _PromptField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLocalizations.of(context).mapPromptHeading,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: AppTheme.text.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: AppTheme.brMd,
          ),
          child: TextField(
            maxLines: 1,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).mapPromptHint,
              hintStyle: TextStyle(color: AppTheme.text.withValues(alpha: 0.4), fontSize: 13),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({
    required this.expanded,
    required this.summary,
    required this.onTap,
  });

  final bool expanded;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.brMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                // Collapsed, the row has to say what is behind it; expanded,
                // the controls themselves say it and repeating the summary
                // would just be a second, staler copy of them.
                expanded ? AppLocalizations.of(context).mapHideTripOptions : summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text.withValues(alpha: 0.62),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: AppTheme.motionBase,
              curve: AppTheme.motionCurve,
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: AppTheme.accentDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
