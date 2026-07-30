import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';
import 'visit_count_chips.dart';

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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Where do you want to explore?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18, height: 1.1),
              ),
              const SizedBox(height: 10),

              // Radius label + value
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Search radius',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.text.withOpacity(0.65)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: AppTheme.brPill,
                    ),
                    child: Text(
                      '${state.radiusKm.toInt()} km',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentDark,
                      ),
                    ),
                  ),
                ],
              ),

              // Radius slider
              SizedBox(
                height: 32,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: state.radiusKm,
                    min: 5,
                    max: 60,
                    divisions: 11,
                    onChanged: (v) => bloc.add(SetRadiusEvent(v)),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              Text(
                "TELL THE AI WHAT YOU'RE AFTER",
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 8),

              // Text area + visit chips
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: AppTheme.brMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      maxLines: 2,
                      onChanged: (v) => bloc.add(SetPromptEvent(v)),
                      decoration: InputDecoration(
                        hintText: "quiet Roman ruins, coastal viewpoints...",
                        hintStyle: TextStyle(color: AppTheme.text.withOpacity(0.4), fontSize: 13),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      ),
                    ),
                    const VisitCountChips(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),

              const SizedBox(height: 14),
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
