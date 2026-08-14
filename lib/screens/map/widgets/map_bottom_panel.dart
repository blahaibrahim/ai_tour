import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/location_search_bar.dart';
import '../../../utils/geojson_parser.dart';
import 'time_budget_picker.dart';

/// The slide-up glass panel at the bottom of the map screen that lets the user
/// configure radius, prompt, and number of stops before generating a route.
class MapBottomPanel extends StatelessWidget {
  const MapBottomPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final bloc = context.read<AppBloc>();

    return GlassSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      boxShadow: AppTheme.shadowLg,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Where do you want to explore?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18, height: 1.1),
              ),
              const SizedBox(height: 16),

              const LocationSearchBar(),
              const SizedBox(height: 16),

              // Selected Wilayas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected Wilayas',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.text.withOpacity(0.65)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: AppTheme.brPill,
                    ),
                    child: Text(
                      '${state.selectedWilayas.length} selected',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              
              FutureBuilder<List<WilayaPolygon>>(
                future: loadWilayasGeoJson(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox(height: 32, child: Text('Loading wilayas...', style: TextStyle(fontSize: 12)));

                  final List<String> selectedNames = [];
                  for (final wilayaId in state.selectedWilayas) {
                    final wp = snapshot.data!.firstWhere(
                      (w) => w.id == wilayaId, 
                      orElse: () => WilayaPolygon(id: '', name: 'Unknown', polygons: [])
                    );
                    if (wp.id.isNotEmpty) {
                      selectedNames.add(wp.name);
                    }
                  }

                  if (selectedNames.isEmpty) {
                    return const SizedBox(
                      height: 32,
                      child: Text(
                        'Tap on the map to select wilayas.',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final name in selectedNames)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                borderRadius: AppTheme.brPill,
                                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accentDark,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
              const TimeBudgetPicker(),

              const SizedBox(height: 16),
              Text(
                "TELL THE AI WHAT YOU'RE AFTER",
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 6),

              // One line, not two. The prompt is a phrase — "quiet Roman
              // ruins" — not a paragraph, and the second line was empty in
              // every state except an unusually long sentence, which scrolls
              // within the field anyway.
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: AppTheme.brMd,
                ),
                child: TextField(
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => bloc.add(SetPromptEvent(v)),
                  decoration: InputDecoration(
                    hintText: "quiet Roman ruins, coastal viewpoints...",
                    hintStyle: TextStyle(color: AppTheme.text.withValues(alpha: 0.4), fontSize: 13),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => bloc.add(const GenerateRouteEvent()),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: const Text('Generate my route', style: TextStyle(fontSize: 14.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
