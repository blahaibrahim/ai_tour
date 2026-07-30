import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/pressable_scale.dart';
import 'widgets/route_header.dart';
import 'widgets/itinerary_list.dart';
import 'widgets/ai_prompt_bar.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;
    final hasStops = state.accepted.isNotEmpty;

    if (!hasStops) {
      return Scaffold(
        body: AppBackdrop(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.deepNavy),
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
                    onPressed: () => context.read<AppBloc>().add(const SetScreenEvent('map')),
                    child: const Text('Back to map'),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                          onTap: () => context.read<AppBloc>().add(const SetScreenEvent('map')),
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

                    const RouteHeader(),

                    // Itinerary header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ITINERARY',
                          style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.text.withOpacity(0.55)),
                        ),
                        TextButton(
                          onPressed: () => context.read<AppBloc>().add(const ToggleModifyEvent()),
                          child: Text(
                            state.modifyMode ? 'Done' : 'Modify manually',
                            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    const ItineraryList(),
                  ],
                ),
              ),
            ),

            const AiPromptBar(),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
              child: ElevatedButton(
                onPressed: () => context.read<AppBloc>().add(const AcceptRouteEvent()),
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
