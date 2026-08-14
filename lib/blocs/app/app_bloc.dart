import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ar/spawn_point.dart';
import '../../config/app_config.dart';
import '../../models/location.dart';
import '../../models/quest_type.dart';
import '../../models/route.dart';
import '../../repositories/artifact_repository.dart';
import '../../repositories/capture_repository.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/model_repository.dart';
import '../../repositories/points_repository.dart';
import '../../repositories/prompt_interpretation_repository.dart';
import '../../repositories/route_repository.dart';
import '../../repositories/saved_locations_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/api_client.dart';
import '../../services/backend_monitor.dart';
import '../../services/demo_data.dart';
import '../../services/notification_service.dart';
import '../../utils/uuid.dart';
import 'app_event.dart';
import 'app_state.dart';

/// Central business-logic hub for the app.
///
/// All state mutations happen here in response to [AppEvent]s dispatched by
/// the UI. The thinking-screen animation timer lives here too, so the widget
/// layer stays completely stateless.
///
/// Route generation goes through [RouteRepository] and is a single synchronous
/// call — there is no job to submit, no polling loop and no resume-on-launch
/// path, all of which the previous itinerary endpoint needed.
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(AppState(arTestingMode: AppConfig.arTestingMode)) {
    on<SetScreenEvent>(_onSetScreen);
    on<ToggleRegionEvent>(_onToggleRegion);
    on<SetMapCenterEvent>(_onSetMapCenter);

    on<LoadRouteOptionsEvent>(_onLoadRouteOptions);
    on<SelectCityEvent>(_onSelectCity);
    on<SelectThemeEvent>(_onSelectTheme);
    on<ToggleCategoryEvent>(_onToggleCategory);
    on<ToggleWilayaEvent>(_onToggleWilaya);
    on<SetPromptEvent>(_onSetPrompt);
    on<InterpretPromptEvent>(_onInterpretPrompt);
    on<SetTripDaysEvent>(_onSetTripDays);
    on<SetHoursPerDayEvent>(_onSetHoursPerDay);
    on<SetTransportModeEvent>(_onSetTransportMode);

    on<GenerateRouteEvent>(_onGenerateRoute);
    on<ThinkTickEvent>(_onThinkTick);
    on<RouteGeneratedEvent>(_onRouteGenerated);
    on<OpenRouteByIdEvent>(_onOpenRouteById);
    on<RouteGenerationFailedEvent>(_onRouteGenerationFailed);
    on<BackToMapEvent>(_onBackToMap);

    on<CommitSwipeEvent>(_onCommitSwipe);
    on<UndoSwipeEvent>(_onUndoSwipe);
    on<OfferAlternateStopsEvent>(_onOfferAlternateStops);
    on<ConfirmReviewedStopsEvent>(_onConfirmReviewedStops);
    on<OpenDetailEvent>(_onOpenDetail);
    on<CloseDetailEvent>(_onCloseDetail);
    on<AskQuestionEvent>(_onAskQuestion);
    on<OnDetailAcceptEvent>(_onDetailAccept);
    on<OnDetailRejectEvent>(_onDetailReject);

    on<ToggleModifyEvent>(_onToggleModify);
    on<RemoveStopEvent>(_onRemoveStop);
    on<TogglePlayEvent>(_onTogglePlay);
    on<AcceptRouteEvent>(_onAcceptRoute);

    on<RecordCheckpointEvent>(_onRecordCheckpoint);
    on<CompleteTaskEvent>(_onCompleteTask);
    on<RegenerateTaskEvent>(_onRegenerateTask);
    on<AdvanceStopEvent>(_onAdvanceStop);
    on<NavHomeEvent>(_onNavHome);
    on<AddCapturedArtifactEvent>(_onAddCapturedArtifact);
    on<MascotCaughtEvent>(_onMascotCaught);
    on<LeaveTourEvent>(_onLeaveTour);
    on<ToggleSavedLocationEvent>(_onToggleSavedLocation);
    on<SetTripDateEvent>(_onSetTripDate);
    on<JobStatusUpdatedEvent>(_onJobStatusUpdated);
    // Without this the camera's capture flow died on its first line: bloc.add
    // throws for an unregistered event, so the optimistic insert aborted the
    // whole capture before generation was ever requested.
    on<OptimisticArtifactEvent>(_onOptimisticArtifact);
    on<RequestModelGenerationEvent>(_onRequestModelGeneration);

    on<LoadSavedLocationsEvent>(_onLoadSavedLocations);
    on<LoadArtifactsEvent>(_onLoadArtifacts);
    on<LoadPointsEvent>(_onLoadPoints);

    on<InitTestMascotSpawnEvent>(_onInitTestMascotSpawn);
    on<ToggleArTestingModeEvent>(_onToggleArTestingMode);
    on<RestoreSessionEvent>(_onRestoreSession);

    _startRealtimeSubscription();
    _watchAuth();
    add(const LoadRouteOptionsEvent());
    add(const LoadSavedLocationsEvent());
    add(const LoadArtifactsEvent());
    add(const LoadPointsEvent());
    add(const RestoreSessionEvent());
    if (state.arTestingMode) add(const InitTestMascotSpawnEvent());
  }

  Timer? _thinkTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;
  StreamSubscription<AuthState>? _authSub;

  /// The bloc is built before the (anonymous) sign-in completes, so anything
  /// keyed on `currentUser` has to be redone once a session actually exists —
  /// otherwise bookmarks silently never load and the realtime subscription
  /// never arms.
  void _watchAuth() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session == null) return;
      if (_realtimeSub == null) _startRealtimeSubscription();
      // Same reason as the rest of this method: the "Notify me" preference is
      // stored per user, so it cannot be read until there is a user. This also
      // re-registers the device's FCM token, which FCM rotates without asking.
      unawaited(NotificationService.instance.syncFromServer());
      add(const LoadRouteOptionsEvent());
      add(const LoadSavedLocationsEvent());
      add(const LoadArtifactsEvent());
      // Also drains the offline outbox — this is the first moment in a launch
      // where there is both a session and, usually, a network.
      add(const LoadPointsEvent());
    });
  }

  /// Subscribe to model_jobs rows for the current user so the folder updates
  /// automatically when the Modal worker finishes.
  void _startRealtimeSubscription() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeSub = Supabase.instance.client
        .from('model_jobs')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((rows) {
          for (final row in rows) {
            final status = row['status'] as String?;
            if (status == null) continue;
            // Only surface terminal states to the bloc — avoid excessive emits
            if (status == 'succeeded' || status == 'failed' || status == 'cancelled') {
              add(JobStatusUpdatedEvent(
                jobId: row['id'] as String,
                status: status,
                outputPath: row['output_path'] as String?,
                errorCode: row['error_code'] as String?,
              ));
            }
          }
        });
  }

  @override
  void onChange(Change<AppState> change) {
    super.onChange(change);
    final next = change.nextState;
    if (const ['swipe', 'result', 'overview'].contains(next.screen)) {
      SessionRepository.saveSession(next);
    } else if (next.screen == 'map' && next.route == null && !next.isRestoringSession) {
      // Gated on the restore having finished: LoadRouteOptionsEvent,
      // LoadSavedLocationsEvent and LoadArtifactsEvent all fire alongside
      // RestoreSessionEvent at startup and routinely emit *before* it — each
      // of those emits lands here with the state still on the initial `map`
      // screen, and without this guard would wipe the persisted session out
      // of SharedPreferences before RestoreSessionEvent ever got to read it.
      SessionRepository.clearSession();
    }
  }

  @override
  Future<void> close() {
    _thinkTimer?.cancel();
    _realtimeSub?.cancel();
    _authSub?.cancel();
    return super.close();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _onSetScreen(SetScreenEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(screen: event.screen));
  }

  void _onToggleRegion(ToggleRegionEvent event, Emitter<AppState> emit) {
    final updated = List<String>.from(state.selectedRegions);
    if (updated.contains(event.name)) {
      updated.remove(event.name);
    } else {
      updated.add(event.name);
    }
    emit(state.copyWith(selectedRegions: updated));
  }

  /// Moves the region circle, and re-resolves the city it now covers.
  ///
  /// Dispatched when a map gesture *ends*, not while it is in progress — the
  /// circle follows the finger locally, and only the committed position needs
  /// to reach the bloc.
  void _onSetMapCenter(SetMapCenterEvent event, Emitter<AppState> emit) {
    emit(_withResolvedCity(state.copyWith(mapCenter: event.center)));
  }

  // ---------------------------------------------------------------------------
  // Route request building
  // ---------------------------------------------------------------------------

  /// Loads cities plus the theme/category vocabulary.
  ///
  /// Both come from the server rather than being hardcoded: adding a city, or
  /// opening one that was in `planning`, is a config change on the server side
  /// and must not need an app release.
  Future<void> _onLoadRouteOptions(
      LoadRouteOptionsEvent event, Emitter<AppState> emit) async {
    if (state.isLoadingOptions) return;
    emit(state.copyWith(isLoadingOptions: true));

    try {
      final results = await Future.wait([
        RouteRepository.fetchCities(),
        RouteRepository.fetchThemesAndCategories(),
      ]);
      final cities = results[0] as List<City>;
      final vocab = results[1] as ({List<RouteTheme> themes, List<RouteCategory> categories});

      // Open the map over a city that can actually be routed, so the region
      // circle starts on something rather than on empty sea. A `planning` city
      // would fail generation if landed on by default, which reads as a broken
      // button.
      City? firstRoutable;
      for (final c in cities) {
        if (c.rolloutStatus.isRoutable) {
          firstRoutable = c;
          break;
        }
      }

      final alreadyPlaced =
          state.selectedCityId != null && cities.any((c) => c.id == state.selectedCityId);
      final centre = alreadyPlaced ? state.mapCenter : firstRoutable?.centre;

      // No default theme. It arrives from interpreting the prompt, and
      // preselecting one would let a traveller generate a route for a theme
      // they never chose and cannot see.
      emit(_withResolvedCity(state.copyWith(
        cities: cities,
        themes: vocab.themes,
        categories: vocab.categories,
        mapCenter: centre ?? state.mapCenter,
        isLoadingOptions: false,
      )));
    } catch (_) {
      // Not fatal — the panel shows its unavailable state and the user can
      // retry. Nothing about the rest of the app depends on this.
      emit(state.copyWith(isLoadingOptions: false));
    }
  }

  void _onSelectCity(SelectCityEvent event, Emitter<AppState> emit) {
    final city = state.cities.where((c) => c.id == event.cityId).firstOrNull;
    emit(state.copyWith(
      selectedCityId: event.cityId,
      mapCenter: city?.centre ?? state.mapCenter,
      // Categories are per-city in principle; clearing avoids carrying a
      // selection that the new city has no POIs for.
      selectedCategoryKeys: const {},
      routeError: null,
      routeErrorCode: null,
    ));
  }

  void _onSelectTheme(SelectThemeEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(selectedTheme: event.themeKey, routeError: null, routeErrorCode: null));
  }

  void _onToggleCategory(ToggleCategoryEvent event, Emitter<AppState> emit) {
    final updated = Set<String>.from(state.selectedCategoryKeys);
    if (!updated.remove(event.categoryKey)) updated.add(event.categoryKey);
    emit(state.copyWith(selectedCategoryKeys: updated));
  }

  void _onSetTripDays(SetTripDaysEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(tripDays: event.days, routeError: null, routeErrorCode: null));
  }

  void _onSetHoursPerDay(SetHoursPerDayEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(hoursPerDay: event.hours, routeError: null, routeErrorCode: null));
  }

  void _onToggleWilaya(ToggleWilayaEvent event, Emitter<AppState> emit) {
    final updated = Set<String>.from(state.selectedWilayas);
    if (updated.contains(event.wilayaId)) {
      updated.remove(event.wilayaId);
    } else {
      updated.add(event.wilayaId);
    }
    emit(state.copyWith(selectedWilayas: updated));
  }

  void _onSetPrompt(SetPromptEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(
      prompt: event.text,
      // The chips below the field describe the *interpreted* prompt. Once the
      // text has moved on from what produced them they are stale, and leaving
      // them up implies the new sentence was understood when it hasn't been
      // read yet.
      promptInterpreted: false,
    ));
  }

  Future<void> _onInterpretPrompt(
          InterpretPromptEvent event, Emitter<AppState> emit) =>
      _interpretInto(emit);

  /// Turns the prompt into a theme and categories.
  ///
  /// Anything the interpreter didn't match is left alone rather than cleared:
  /// a prompt that yields no theme should not wipe the theme already in the
  /// request, or typing an unrecognised sentence would silently narrow the
  /// trip to nothing.
  ///
  /// Takes the emitter rather than an event so the generate handler can run it
  /// inline — pressing "Plan my route" has to read the description first, and
  /// dispatching a second event from inside a handler would let generation race
  /// ahead of the interpretation it depends on.
  Future<void> _interpretInto(Emitter<AppState> emit) async {
    final prompt = state.prompt.trim();
    if (prompt.isEmpty || state.isInterpretingPrompt) return;

    emit(state.copyWith(isInterpretingPrompt: true));

    final interpretation = await PromptInterpretationRepository.interpret(
      prompt: prompt,
      availableThemes: state.themes,
      availableCategories: state.categories,
    );

    emit(state.copyWith(
      isInterpretingPrompt: false,
      promptInterpreted: !interpretation.isEmpty,
      selectedTheme: interpretation.themeKey ?? state.selectedTheme,
      selectedCategoryKeys: interpretation.categoryKeys.isEmpty
          ? state.selectedCategoryKeys
          : interpretation.categoryKeys,
      routeError: null,
      routeErrorCode: null,
    ));
  }

  /// Re-resolves which city the region circle picks out.
  ///
  /// The traveller never chooses a city directly any more — they drag a circle
  /// over a map. This is the one place that turns that gesture into the
  /// `city_id` the request carries, so it runs on every change that can move
  /// the circle or resize it.
  AppState _withResolvedCity(AppState next) {
    final routable = next.regionSelection.routable;
    if (routable == null || routable.id == next.selectedCityId) return next;
    return next.copyWith(selectedCityId: routable.id);
  }

  void _onSetTransportMode(SetTransportModeEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(transportMode: event.mode));
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _onGenerateRoute(
      GenerateRouteEvent event, Emitter<AppState> emit) async {
    // Reading the description is part of pressing the button, not a separate
    // step the traveller has to remember. There is no submit affordance on the
    // field itself any more, so if a prompt has been typed but never
    // interpreted, that happens here — otherwise the sentence would be silently
    // discarded and the route built from the fallback theme.
    if (state.prompt.trim().isNotEmpty && !state.promptInterpreted) {
      await _interpretInto(emit);
    }

    final cityId = state.selectedCityId;
    final theme = state.effectiveTheme;
    if (cityId == null || theme == null) return;

    _thinkTimer?.cancel();
    emit(state.copyWith(
      screen: 'thinking',
      thinkIdx: 0,
      isGeneratingRoute: true,
      routeError: null,
      routeErrorCode: null,
    ));

    _thinkTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      add(const ThinkTickEvent());
    });

    try {
      await Future.delayed(const Duration(seconds: 5)); // Added for testing loading screen
      final route = await RouteRepository.generateRoute(
        cityId: cityId,
        theme: theme,
        timeBudgetMinutes: state.timeBudgetMinutes,
        transportMode: state.transportMode,
        categoryKeys: state.selectedCategoryKeys.toList(),
      );
      _thinkTimer?.cancel();
      add(RouteGeneratedEvent(route));
    } on ApiException catch (e) {
      _thinkTimer?.cancel();
      add(RouteGenerationFailedEvent(e.errorCode, e.message ?? _messageForCode(e.errorCode)));
    } catch (_) {
      _thinkTimer?.cancel();
      add(const RouteGenerationFailedEvent('network_error', "Couldn't reach the route service."));
    }
  }

  /// Reopens a route the server already generated, from its id alone.
  ///
  /// Reuses the thinking screen while it loads rather than inventing a second
  /// waiting state — from the traveller's side this *is* the same wait,
  /// resumed. Once the route lands it flows through [RouteGeneratedEvent] like
  /// any other, so the swipe/result screens need to know nothing about how it
  /// arrived.
  Future<void> _onOpenRouteById(
      OpenRouteByIdEvent event, Emitter<AppState> emit) async {
    if (state.route?.id == event.routeId) {
      // Already loaded — the notification arrived while the app was alive and
      // has been sitting in the tray. Just show it.
      emit(state.copyWith(screen: state.queue.isEmpty ? 'result' : 'swipe'));
      return;
    }

    _thinkTimer?.cancel();
    emit(state.copyWith(
      screen: 'thinking',
      thinkIdx: 0,
      isGeneratingRoute: true,
      routeError: null,
      routeErrorCode: null,
    ));

    try {
      final route = await RouteRepository.fetchRoute(event.routeId);
      add(RouteGeneratedEvent(route));
    } on ApiException catch (e) {
      add(RouteGenerationFailedEvent(
          e.errorCode, e.message ?? _messageForCode(e.errorCode)));
    } catch (_) {
      add(const RouteGenerationFailedEvent(
          'network_error', "Couldn't reach the route service."));
    }
  }

  /// Copy for the failure modes the old repository collapsed into "no stops".
  static String _messageForCode(String code) => switch (code) {
        'city_not_available' => "This city isn't open for routes yet.",
        'no_eligible_pois' => 'No published stops match that theme here yet.',
        'time_budget_too_short' => 'That time budget is too short for any stop here.',
        'routing_provider_unavailable' => 'The routing service is unavailable right now.',
        'not_implemented' => 'Route generation is not built yet on this server.',
        _ => 'Something went wrong generating your route.',
      };

  /// Advances the thinking-screen step, stopping at the last one.
  ///
  /// It used to wrap with `% length`, so a generation slower than the whole
  /// sequence restarted at "Reading your time budget…" — which reads as the
  /// work having been thrown away and begun again. Holding on the final step
  /// says "still on the last thing", which is true.
  void _onThinkTick(ThinkTickEvent event, Emitter<AppState> emit) {
    final last = AppState.thinkingMessages.length - 1;
    if (state.thinkIdx >= last) return;
    emit(state.copyWith(thinkIdx: state.thinkIdx + 1));
  }

  /// True when the traveller left the thinking screen while a request was in
  /// flight. The HTTP call can't be recalled, so its result is discarded on
  /// arrival instead — without this, cancelling and then having the response
  /// land throws the traveller into the review screen for a route they backed
  /// out of, seconds after they chose not to have it.
  bool get _generationWasCancelled => !state.isGeneratingRoute;

  /// A route arrived. Its stops become the review queue.
  void _onRouteGenerated(RouteGeneratedEvent event, Emitter<AppState> emit) {
    if (_generationWasCancelled) return;
    final regionLabel = state.selectedCity?.name ?? '';

    // Trigger 1's fallback path. `POST /api/routes` sends a push the moment
    // generation finishes, and that owns the notification whenever it can be
    // delivered — it has to, because the case "Notify me" is really for is the
    // app being killed mid-generation, and a killed process cannot notify
    // anyone about anything. This call covers only a build with no Firebase
    // configuration; it is a no-op otherwise, and a no-op in the foreground.
    unawaited(NotificationService.instance.showRouteReady(
      routeTitle: state.selectedCity?.name,
      routeId: event.route.id,
    ));

    emit(state.copyWith(
      route: event.route,
      queue: event.route.stops.map((s) => s.toLocation(regionLabel: regionLabel)).toList(),
      currentIndex: 0,
      accepted: const [],
      rejected: const [],
      screen: event.route.stops.isEmpty ? 'result' : 'swipe',
      isGeneratingRoute: false,
      routeError: null,
      routeErrorCode: null,
    ));
  }

  void _onRouteGenerationFailed(
      RouteGenerationFailedEvent event, Emitter<AppState> emit) {
    // Same reasoning as [_onRouteGenerated]: a traveller who cancelled should
    // not then be shown an error about the request they abandoned.
    if (_generationWasCancelled) return;
    emit(state.copyWith(
      screen: 'map',
      isGeneratingRoute: false,
      routeError: event.message,
      routeErrorCode: event.code,
    ));
  }

  void _onBackToMap(BackToMapEvent event, Emitter<AppState> emit) {
    _thinkTimer?.cancel();
    emit(state.copyWith(screen: 'map', isGeneratingRoute: false));
  }

  // ---------------------------------------------------------------------------
  // Review step
  // ---------------------------------------------------------------------------

  void _handleSwipeNext(int nextIndex, List<Location> newAccepted,
      List<Location> newRejected, Emitter<AppState> emit) {
    final next = state.copyWith(
      accepted: newAccepted,
      rejected: newRejected,
      currentIndex: nextIndex,
    );
    emit(next);

    if (nextIndex < next.queue.length) return;

    // The deck is empty. Whether that ends the review depends on whether what
    // was kept fills the day the traveller asked for.
    if (next.budgetFilled) {
      add(const ConfirmReviewedStopsEvent());
      return;
    }

    // Short, so offer the stops the budget fit had to leave out rather than
    // pushing on with a half-empty day. Rejecting used to be free in the wrong
    // way: it made the route shorter and nothing replaced it.
    add(const OfferAlternateStopsEvent());
  }

  /// Refills the review deck from the route's held-back candidates.
  ///
  /// Only as many as the shortfall needs, so a traveller who rejected one stop
  /// is shown one more rather than the rest of the catalogue.
  void _onOfferAlternateStops(
      OfferAlternateStopsEvent event, Emitter<AppState> emit) {
    final route = state.route;
    if (route == null) return;

    final seen = {
      ...state.queue.map((l) => l.id),
      ...state.accepted.map((l) => l.id),
      ...state.rejected.map((l) => l.id),
    };
    final regionLabel = state.selectedCity?.name ?? '';
    final fresh = route.alternates
        .where((s) => !seen.contains(s.poiId))
        .map((s) => s.toLocation(regionLabel: regionLabel))
        .toList();

    if (fresh.isEmpty) {
      // Nothing left to offer. The traveller is not stuck — the review can
      // still be confirmed — but the reason the day is short is the catalogue,
      // not them, and saying so is better than a button that never enables.
      emit(state.copyWith(reviewExhausted: true));
      return;
    }

    var shortfall = state.requiredMinutes - state.acceptedMinutes;
    final take = <Location>[];
    for (final loc in fresh) {
      if (shortfall <= 0) break;
      take.add(loc);
      shortfall -= loc.dwellMinutes;
    }

    emit(state.copyWith(
      queue: [...state.queue, ...take],
      route: route.copyWithAlternates(
        route.alternates.where((s) => !take.any((l) => l.id == s.poiId)).toList(),
      ),
      reviewExhausted: false,
    ));
  }

  /// Steps the review back one card and un-files the stop it had filed.
  ///
  /// The stop is removed by identity from whichever list it went into rather
  /// than by popping the tail of both: the detail overlay can accept or reject
  /// out of band, so "the last thing added" and "the stop at the previous
  /// index" are not always the same entry.
  void _onUndoSwipe(UndoSwipeEvent event, Emitter<AppState> emit) {
    if (state.currentIndex <= 0) return;

    final previousIndex = state.currentIndex - 1;
    final loc = state.queue[previousIndex];

    final accepted = List<Location>.from(state.accepted)
      ..removeWhere((l) => l.id == loc.id);
    final rejected = List<Location>.from(state.rejected)
      ..removeWhere((l) => l.id == loc.id);

    emit(state.copyWith(
      currentIndex: previousIndex,
      accepted: accepted,
      rejected: rejected,
    ));
  }

  void _onCommitSwipe(CommitSwipeEvent event, Emitter<AppState> emit) {
    final loc = state.currentLoc;
    if (loc == null) return;

    final newAccepted = event.isAccept ? [...state.accepted, loc] : state.accepted;
    final newRejected = !event.isAccept ? [...state.rejected, loc] : state.rejected;

    _handleSwipeNext(state.currentIndex + 1, newAccepted, newRejected, emit);
  }

  /// Re-generates without the dropped stops.
  ///
  /// Dropping them client-side would leave the segments, the total duration and
  /// the day-count flag describing a route that no longer exists — the ordering
  /// and the drive/walk split are properties of the whole stop set, not of each
  /// stop. So the server re-runs clustering and ordering for what's left.
  Future<void> _onConfirmReviewedStops(
      ConfirmReviewedStopsEvent event, Emitter<AppState> emit) async {
    final route = state.route;
    if (route == null) {
      emit(state.copyWith(screen: 'result'));
      return;
    }

    if (state.rejected.isEmpty) {
      emit(state.copyWith(screen: 'result'));
      return;
    }

    emit(state.copyWith(screen: 'thinking', thinkIdx: 0, isGeneratingRoute: true));

    try {
      final refined = await RouteRepository.refineRoute(
        routeId: route.id,
        dropPoiIds: state.rejected.map((l) => l.id).toList(),
        cityId: route.cityId,
        theme: route.theme,
        timeBudgetMinutes: route.timeBudgetMinutes,
        transportMode: route.transportMode,
        categoryKeys: state.selectedCategoryKeys.toList(),
      );
      emit(state.copyWith(route: refined, screen: 'result', isGeneratingRoute: false));
    } catch (_) {
      // Keep the route as generated rather than showing a stale one that
      // claims stops the traveller dropped.
      emit(state.copyWith(
        screen: 'result',
        isGeneratingRoute: false,
        routeError: "Couldn't drop those stops — showing the route as generated.",
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Location detail overlay
  // ---------------------------------------------------------------------------

  void _onOpenDetail(OpenDetailEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(detailLoc: event.loc, detailConversation: const []));
  }

  void _onCloseDetail(CloseDetailEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(detailLoc: null, detailConversation: const []));
  }

  /// Sends the question to /api/chat and emits the real response.
  Future<void> _onAskQuestion(
      AskQuestionEvent event, Emitter<AppState> emit) async {
    if (event.question.trim().isEmpty) return;

    final loc = state.detailLoc;
    if (loc == null) return;

    // Optimistically add the user message and a loading placeholder.
    emit(state.copyWith(
      isChatLoading: true,
      detailConversation: [
        ...state.detailConversation,
        ChatMessage('user', event.question),
      ],
    ));

    try {
      final answer = await ChatRepository.askAboutPlace(
        locationId: loc.id,
        locationName: loc.name,
        blurb: loc.blurb,
        category: loc.category,
        region: loc.region,
        question: event.question,
        history: state.detailConversation,
      );
      emit(state.copyWith(
        isChatLoading: false,
        detailConversation: [
          ...state.detailConversation,
          ChatMessage('ai', answer),
        ],
      ));
    } catch (_) {
      emit(state.copyWith(
        isChatLoading: false,
        detailConversation: [
          ...state.detailConversation,
          const ChatMessage('ai',
              "Sorry, I couldn't reach the guide right now — try again."),
        ],
      ));
    }
  }

  void _onDetailAccept(OnDetailAcceptEvent event, Emitter<AppState> emit) {
    final loc = state.currentLoc;
    if (loc == null) return;

    final newAccepted = [...state.accepted, loc];
    emit(state.copyWith(detailLoc: null, detailConversation: const []));
    _handleSwipeNext(state.currentIndex + 1, newAccepted, state.rejected, emit);
  }

  void _onDetailReject(OnDetailRejectEvent event, Emitter<AppState> emit) {
    final loc = state.currentLoc;
    if (loc == null) return;

    final newRejected = [...state.rejected, loc];
    emit(state.copyWith(detailLoc: null, detailConversation: const []));
    _handleSwipeNext(state.currentIndex + 1, state.accepted, newRejected, emit);
  }

  // ---------------------------------------------------------------------------
  // Result screen
  // ---------------------------------------------------------------------------

  void _onToggleModify(ToggleModifyEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(modifyMode: !state.modifyMode));
  }

  /// Drops one stop and re-generates, for the same reason the review step does.
  ///
  /// Note there is no manual reorder any more: the order is the optimizer's
  /// output over a real travel-time matrix, and a hand-dragged order would make
  /// every segment duration and the route total wrong without saying so.
  Future<void> _onRemoveStop(RemoveStopEvent event, Emitter<AppState> emit) async {
    final route = state.route;
    if (route == null) return;
    if (event.index < 0 || event.index >= route.stops.length) return;

    final dropped = route.stops[event.index];

    // The same rule the swipe step enforces: a traveller may trim their day,
    // but not below the day they asked for. Guarded here as well as in the UI
    // because the button is not the only way in — the detail overlay rejects
    // too, and a rule enforced only where it is drawn is a rule that leaks.
    if (!state.canRemoveStop(dropped.dwellMinutes)) {
      emit(state.copyWith(
        routeError: 'Removing that would leave less than the time you asked for.',
      ));
      return;
    }

    emit(state.copyWith(isGeneratingRoute: true));

    try {
      final refined = await RouteRepository.refineRoute(
        routeId: route.id,
        dropPoiIds: [dropped.poiId],
        cityId: route.cityId,
        theme: route.theme,
        timeBudgetMinutes: route.timeBudgetMinutes,
        transportMode: route.transportMode,
        categoryKeys: state.selectedCategoryKeys.toList(),
      );
      emit(state.copyWith(route: refined, isGeneratingRoute: false));
    } catch (_) {
      emit(state.copyWith(
        isGeneratingRoute: false,
        routeError: "Couldn't remove that stop — try again.",
      ));
    }
  }

  void _onTogglePlay(TogglePlayEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(videoPlaying: !state.videoPlaying));
  }

  /// Accepts the route and starts a progress record for the walk.
  Future<void> _onAcceptRoute(AcceptRouteEvent event, Emitter<AppState> emit) async {
    final route = state.route;
    if (route == null) return;

    final regionLabel = state.selectedCity?.name ?? '';
    final stopsAsLocations =
        route.stops.map((s) => s.toLocation(regionLabel: regionLabel)).toList();

    // Each stop draws its own quest at random rather than taking whatever the
    // catalogue happened to carry — a route where every stop asks for a photo
    // is a route people stop doing by the third one. The type drawn here is
    // also the first entry in that stop's offered-history, which is what stops
    // a regeneration handing back the same quest.
    final random = math.Random();
    final tasks = <Task>[];
    final offered = <Set<String>>[];
    for (var i = 0; i < stopsAsLocations.length; i++) {
      final type = initialQuestType(random: random);
      tasks.add(Task(type: type, label: questLabel(type, seed: i), points: 30));
      offered.add({type});
    }

    emit(state.copyWith(
      accepted: stopsAsLocations,
      tasks: tasks,
      offeredQuestTypes: offered,
      screen: 'overview',
      routeAccepted: true,
      currentStopIdx: 0,
    ));

    try {
      final progress = await RouteRepository.startProgress(route.id);
      emit(state.copyWith(progress: progress));
    } catch (_) {
      // The tour still works without a server-side progress record; the
      // checkpoints simply aren't logged.
    }
  }

  // ---------------------------------------------------------------------------
  // Walking the route
  // ---------------------------------------------------------------------------

  /// Best-effort: a dropped checkpoint must never block the tour.
  Future<void> _onRecordCheckpoint(
      RecordCheckpointEvent event, Emitter<AppState> emit) async {
    final progress = state.progress;
    if (progress == null) return;
    await RouteRepository.recordCheckpoint(
      progressId: progress.id,
      poiId: event.poiId,
    );
  }

  Future<void> _onCompleteTask(
      CompleteTaskEvent event, Emitter<AppState> emit) async {
    if (state.currentStopIdx >= state.tasks.length) return;
    final t = state.tasks[state.currentStopIdx];
    if (t.state == 'done') return;

    final stopIdx = state.currentStopIdx;
    final updated = List<Task>.from(state.tasks);
    updated[stopIdx] = t.copyWith(state: 'done');
    // Emitted before the write, not after: the pill moves the instant the task
    // is finished, and the ledger catches up on its own schedule.
    emit(state.copyWith(tasks: updated, points: state.points + t.points));

    final stops = state.routeStops;
    if (stopIdx < stops.length) {
      add(RecordCheckpointEvent(stops[stopIdx].poiId));
    }

    final total = await _recordCompletion(stopIdx: stopIdx, task: t);
    // The ledger write can outlive the bloc — a task finished as the app is
    // being closed. Emitting into a closed bloc throws.
    if (total != null && !isClosed) emit(state.copyWith(lifetimePoints: total));
  }

  /// Writes one finished task to the durable per-user ledger.
  ///
  /// The key is the route plus the stop index, which is what makes this safe to
  /// call more than once for the same task — and it does get called more than
  /// once: [_onCompleteTask] and [_onAddCapturedArtifact] both finish the
  /// current stop's task, and a capture that answers a task goes through both.
  ///
  /// Returns the traveller's new lifetime total, or null when it could not be
  /// determined (no session, or a first-ever award on a device that has never
  /// synced a baseline).
  Future<int?> _recordCompletion({required int stopIdx, required Task task}) async {
    final routeId = state.route?.id ?? state.progress?.routeId;
    // Without a route there is nothing stable to key on, and an unkeyed award
    // would be counted again on every replay. Skipping is the safe direction:
    // the tour-local pill still shows the points.
    if (routeId == null || routeId.isEmpty) return null;

    final stops = state.routeStops;
    return PointsRepository.recordCompletion(
      completionKey: '$routeId:stop:$stopIdx',
      points: task.points,
      routeId: routeId,
      poiId: stopIdx < stops.length ? stops[stopIdx].poiId : null,
      taskType: task.type,
    );
  }

  /// Reads the traveller's saved score, and pushes up anything stranded offline.
  ///
  /// The cached value is emitted first so the number is on screen immediately;
  /// the network read then corrects it. With no session at all — signed out —
  /// the total goes back to unknown rather than lingering as the previous
  /// user's score.
  Future<void> _onLoadPoints(LoadPointsEvent event, Emitter<AppState> emit) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      emit(state.copyWith(lifetimePoints: null));
      return;
    }

    final cached = await PointsRepository.cachedTotal();
    if (isClosed) return;
    if (cached != null && cached != state.lifetimePoints) {
      emit(state.copyWith(lifetimePoints: cached));
    }

    await PointsRepository.flushOutbox();
    final total = await PointsRepository.fetchTotal();
    if (total != null && !isClosed) emit(state.copyWith(lifetimePoints: total));
  }

  /// Swaps the current stop's quest for one it has not offered before.
  ///
  /// The type is chosen here rather than by the server. `/api/tasks/generate`
  /// picks its own type, which cannot satisfy the no-repeat rule — and it is
  /// currently unreachable for route stops anyway, since it resolves ids
  /// against the `locations` catalogue while a route stop carries a `pois`
  /// uuid. A label written for the wrong activity is worse than a fixed one,
  /// so the labels come from [questLabel].
  ///
  /// Two independent limits stop this: the per-tour budget, and having run out
  /// of unoffered types at this stop. [AppState.canRegenerateQuest] is the
  /// single place both are expressed, so the button and this handler cannot
  /// disagree about whether a swap is possible.
  Future<void> _onRegenerateTask(
      RegenerateTaskEvent event, Emitter<AppState> emit) async {
    if (!state.canRegenerateQuest) return;

    final idx = state.currentStopIdx;
    final t = state.tasks[idx];

    final offered = idx < state.offeredQuestTypes.length
        ? state.offeredQuestTypes[idx]
        : <String>{t.type};

    final next = nextQuestType(offered);
    if (next == null) return; // Already guarded above; belt and braces.

    final updatedTasks = List<Task>.from(state.tasks);
    updatedTasks[idx] = Task(
      type: next,
      label: questLabel(next, seed: idx + offered.length),
      state: 'pending',
      points: t.points,
    );

    final updatedOffered = [
      for (var i = 0; i < state.offeredQuestTypes.length; i++)
        i == idx ? {...state.offeredQuestTypes[i], next} : state.offeredQuestTypes[i],
    ];
    // A session restored from before this field existed has no history to
    // extend; seed it from what is on screen so the rule still holds for the
    // rest of the walk.
    if (idx >= updatedOffered.length) {
      updatedOffered.addAll([
        for (var i = updatedOffered.length; i <= idx; i++)
          i == idx ? {t.type, next} : <String>{},
      ]);
    }

    emit(state.copyWith(
      tasks: updatedTasks,
      offeredQuestTypes: updatedOffered,
      taskRegenerationsLeft: state.taskRegenerationsLeft - 1,
    ));
  }

  void _onAdvanceStop(AdvanceStopEvent event, Emitter<AppState> emit) {
    if (state.currentStopIdx < state.accepted.length - 1) {
      emit(state.copyWith(currentStopIdx: state.currentStopIdx + 1));
    }
  }

  void _onNavHome(NavHomeEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(screen: state.routeAccepted ? 'overview' : 'map'));
  }

  // ---------------------------------------------------------------------------
  // AR mascot hunt — testing mode
  // ---------------------------------------------------------------------------

  /// Best-effort, mirroring `LocationSearchBar`'s permission flow: a tester
  /// who never grants location just falls back to hunting a stop's real
  /// coordinates, same as when testing mode is off.
  Future<void> _onInitTestMascotSpawn(
      InitTestMascotSpawnEvent event, Emitter<AppState> emit) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final spawn = generateTestSpawnPoint(LatLng(position.latitude, position.longitude));
      emit(state.copyWith(testMascotSpawn: spawn));
    } catch (_) {
      // No fix, no permission, plugin unavailable — the hunt falls back to
      // real POI coordinates either way.
    }
  }

  void _onToggleArTestingMode(
      ToggleArTestingModeEvent event, Emitter<AppState> emit) {
    final enabled = !state.arTestingMode;
    emit(state.copyWith(arTestingMode: enabled));
    if (enabled && state.testMascotSpawn == null) {
      add(const InitTestMascotSpawnEvent());
    }
  }

  // ---------------------------------------------------------------------------
  // Camera / folder
  // ---------------------------------------------------------------------------

  Future<void> _onAddCapturedArtifact(
      AddCapturedArtifactEvent event, Emitter<AppState> emit) async {
    Location? currentLoc;
    Task? currentTask;
    if (state.routeAccepted && state.currentStopIdx < state.accepted.length) {
      currentLoc = state.accepted[state.currentStopIdx];
      currentTask = state.currentStopIdx < state.tasks.length
          ? state.tasks[state.currentStopIdx]
          : null;
    }

    final artifact = Artifact(
      id: uuidV4(),
      name: currentLoc?.name ?? 'Your capture',
      region: currentLoc?.region ?? 'On the go',
      kindLabel: event.kindLabel ?? 'Photo',
      photoUrl: event.filePath,
      isLocalFile: true,
    );

    final newArtifacts = [artifact, ...state.capturedArtifacts];

    // Push a copy to storage behind the UI. Not awaited and never surfaced:
    // the file is already on disk and the artifact is already in the folder, so
    // an upload that fails costs the traveller nothing they can see now — only
    // the copy that would have outlived this device.
    unawaited(CaptureRepository.upload(
      artifactId: artifact.id,
      localPath: event.filePath,
      kind: event.kind == 'video' ? 'video' : 'photo',
      title: artifact.name,
    ));

    // A capture finishes the quest only when it is the thing the quest asked
    // for. Previously *any* capture finished whatever quest was open, so a
    // photo closed a video quest and a snapshot taken from the nav bar — miles
    // from the stop, answering nothing — closed the next one in line.
    final answersQuest = currentTask != null &&
        currentTask.state == 'pending' &&
        event.kind != null &&
        event.kind == currentTask.type;

    if (answersQuest) {
      final stopIdx = state.currentStopIdx;
      final updated = List<Task>.from(state.tasks);
      updated[stopIdx] = currentTask.copyWith(state: 'done');
      emit(state.copyWith(
        capturedArtifacts: newArtifacts,
        tasks: updated,
        points: state.points + currentTask.points,
      ));

      // Same ledger, same key as [_onCompleteTask] would have used for this
      // stop — a capture that answers a task is one completion, however it was
      // finished.
      final total = await _recordCompletion(stopIdx: stopIdx, task: currentTask);
      if (total != null && !isClosed) emit(state.copyWith(lifetimePoints: total));
    } else {
      emit(state.copyWith(capturedArtifacts: newArtifacts));
    }
  }

  /// Finishes a mascot quest on a catch.
  ///
  /// Nothing is added to the folder: a fennec is not one of the traveller's own
  /// captures. The catch itself is the completion, and it only counts against a
  /// stop whose quest actually asked for one — catching a fennec found while a
  /// photo quest is open is a nice moment, not an answer to that quest.
  Future<void> _onMascotCaught(
      MascotCaughtEvent event, Emitter<AppState> emit) async {
    if (!state.routeAccepted || state.currentStopIdx >= state.tasks.length) return;

    final stopIdx = state.currentStopIdx;
    final task = state.tasks[stopIdx];
    if (task.type != 'mascot' || task.state != 'pending') return;

    final updated = List<Task>.from(state.tasks);
    updated[stopIdx] = task.copyWith(state: 'done');
    emit(state.copyWith(tasks: updated, points: state.points + task.points));

    final stops = state.routeStops;
    if (stopIdx < stops.length) add(RecordCheckpointEvent(stops[stopIdx].poiId));

    final total = await _recordCompletion(stopIdx: stopIdx, task: task);
    if (total != null && !isClosed) emit(state.copyWith(lifetimePoints: total));
  }

  // ---------------------------------------------------------------------------
  // 3D model generation
  // ---------------------------------------------------------------------------

  /// Pulls every persisted artifact back into the folder.
  ///
  /// Runs at construction and again once anonymous sign-in lands (the bloc is
  /// built before there is a session, so the first attempt usually returns
  /// nothing).
  Future<void> _onLoadArtifacts(
      LoadArtifactsEvent event, Emitter<AppState> emit) async {
    final stored = await ArtifactRepository.fetchAll();
    if (stored.isEmpty) return;

    // Anything already in state is at least as fresh as the row just read — an
    // optimistic insert or a Realtime completion can land while the fetch is in
    // flight — so the in-memory copy wins on an id collision.
    final byId = {for (final a in stored) a.id: a};
    for (final a in state.capturedArtifacts) {
      byId[a.id] = a;
    }

    // One `now` for the whole sort: this session's captures have no
    // captured_at yet and belong at the top, and a comparator that re-read the
    // clock per comparison wouldn't be consistent.
    final now = DateTime.now();
    final merged = byId.values.toList()
      ..sort((a, b) => (b.capturedAt ?? now).compareTo(a.capturedAt ?? now));

    emit(state.copyWith(capturedArtifacts: merged));
  }

  /// Inserts an optimistic [Artifact] directly into the folder — called by the
  /// camera screen immediately after object detection passes, before any upload.
  void _onOptimisticArtifact(
      OptimisticArtifactEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(
      capturedArtifacts: [event.artifact, ...state.capturedArtifacts],
    ));
  }

  /// Uploads the image and kicks off the Modal generation job.
  /// The artifact is already in capturedArtifacts with modelStatus=generating
  /// (added by the AR screen before dispatching this event).
  Future<void> _onRequestModelGeneration(
      RequestModelGenerationEvent event, Emitter<AppState> emit) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Upload to Supabase Storage captures/ bucket
      final imagePath = await ModelRepository.uploadCapture(
        userId: userId,
        artifactId: event.artifactId,
        bytes: event.imageBytes,
      );

      // Persist the artifacts row before generating: the job's artifact_id is
      // a foreign key to it, so /api/models/generate fails without it.
      await ModelRepository.createArtifact(
        userId: userId,
        artifactId: event.artifactId,
        storagePath: imagePath,
        title: event.title,
      );

      // Call /api/models/generate — returns {job_id} or {cached, output_path}
      final result = await ModelRepository.requestGeneration(
        userId: userId,
        artifactId: event.artifactId,
        imagePath: imagePath,
        sha256: event.sha256,
      );

      if (result.cached) {
        // SHA-256 cache hit — already have the model, no GPU run needed
        final updated = state.capturedArtifacts.map((a) {
          if (a.id != event.artifactId) return a;
          return a.copyWith(
            modelStatus: ModelStatus.succeeded,
            modelPath: result.outputPath,
          );
        }).toList();
        emit(state.copyWith(capturedArtifacts: updated));
      } else {
        // Job submitted — Realtime will update us when it completes
        final updated = state.capturedArtifacts.map((a) {
          if (a.id != event.artifactId) return a;
          return a.copyWith(jobId: result.jobId);
        }).toList();
        emit(state.copyWith(capturedArtifacts: updated));
        // No re-subscribe: the stream is filtered by user_id, not by job, so
        // it already covers this job. Tearing it down and rebuilding it left
        // a window in which the worker's UPDATE — which for a warm GPU
        // container can land seconds after submit — arrived with nobody
        // listening, and the artifact stayed on "Generating 3D…" forever.
        if (_realtimeSub == null) _startRealtimeSubscription();
      }
    } catch (e) {
      // Neither Supabase Storage nor the Node backend is reachable without a
      // network path to either — there is no upload, no artifact row and no
      // GPU job possible. Rather than leave the capture stuck on "failed"
      // (correct when the backend is up and something genuinely broke, but
      // not when there was never a backend to reach), stand in a bundled demo
      // model so the folder still shows a completed, rotatable 3D artifact.
      final isFake = isConnectivityError(e) ||
          e is StorageException ||
          e is PostgrestException ||
          (e is ApiException && e.isTransport);
      final updated = state.capturedArtifacts.map((a) {
        if (a.id != event.artifactId) return a;
        return isFake
            ? a.copyWith(
                modelStatus: ModelStatus.succeeded,
                modelPath: DemoData.demoModelPath,
              )
            : a.copyWith(modelStatus: ModelStatus.failed, errorCode: 'internal');
      }).toList();
      emit(state.copyWith(capturedArtifacts: updated));
    }
  }

  /// Called by Realtime when a model_jobs row changes to a terminal state.
  void _onJobStatusUpdated(
      JobStatusUpdatedEvent event, Emitter<AppState> emit) {
    // Trigger 2's fallback path. The same terminal row fires a database
    // trigger that sends an FCM push, and that push owns this notification
    // whenever it can be delivered; this call is a no-op in that case. It
    // exists for builds with no Firebase configuration, where realtime is the
    // only way the app ever hears that a job finished — see
    // `NotificationService.showModelResult`.
    unawaited(NotificationService.instance.showModelResult(
      jobId: event.jobId,
      succeeded: event.status == 'succeeded',
      errorCode: event.errorCode,
    ));

    final updated = state.capturedArtifacts.map((a) {
      if (a.jobId != event.jobId) return a;
      switch (event.status) {
        case 'succeeded':
          return a.copyWith(
            modelStatus: ModelStatus.succeeded,
            modelPath: event.outputPath,
          );
        case 'failed':
        case 'cancelled':
          return a.copyWith(
            modelStatus: ModelStatus.failed,
            errorCode: event.errorCode,
          );
        default:
          return a;
      }
    }).toList();
    emit(state.copyWith(capturedArtifacts: updated));
  }

  // ---------------------------------------------------------------------------
  // Saved locations & trip date
  // ---------------------------------------------------------------------------

  /// Toggles optimistically, then persists. If the write is rejected (no
  /// session, or a location the catalogue doesn't have a row for) the local
  /// change is rolled back so the bookmark icon never claims a save that
  /// didn't happen.
  Future<void> _onToggleSavedLocation(
      ToggleSavedLocationEvent event, Emitter<AppState> emit) async {
    final wasSaved = state.savedLocationIds.contains(event.id);
    final updated = Set<String>.from(state.savedLocationIds);
    if (wasSaved) {
      updated.remove(event.id);
    } else {
      updated.add(event.id);
    }
    emit(state.copyWith(savedLocationIds: updated));

    final ok = wasSaved
        ? await SavedLocationsRepository.remove(event.id)
        : await SavedLocationsRepository.save(event.id);

    if (!ok) {
      final rolledBack = Set<String>.from(state.savedLocationIds);
      if (wasSaved) {
        rolledBack.add(event.id);
      } else {
        rolledBack.remove(event.id);
      }
      emit(state.copyWith(savedLocationIds: rolledBack));
    }
  }

  /// Pulls the persisted bookmarks in at startup, so they survive a restart
  /// and follow the account across devices.
  Future<void> _onLoadSavedLocations(
      LoadSavedLocationsEvent event, Emitter<AppState> emit) async {
    final saved = await SavedLocationsRepository.fetchAll();
    if (saved.isEmpty) return;
    emit(state.copyWith(
      savedLocationIds: {...state.savedLocationIds, ...saved},
    ));
  }

  void _onSetTripDate(SetTripDateEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(tripDate: event.start, tripEndDate: event.end));
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  Future<void> _onRestoreSession(RestoreSessionEvent event, Emitter<AppState> emit) async {
    Map<String, dynamic>? sessionData;
    try {
      sessionData = await SessionRepository.loadSession();
    } catch (e, st) {
      developer.log('Restore session error', name: 'AppBloc', error: e, stackTrace: st);
    }

    if (sessionData == null) {
      // Nothing to restore — still have to clear the flag, or AppShell's
      // splash gate (and the onChange guard above) waits on it forever.
      emit(state.copyWith(isRestoringSession: false));
      return;
    }

    try {
      final screen = sessionData['screen'] as String?;
      if (screen == null || !const ['swipe', 'result', 'overview'].contains(screen)) {
        emit(state.copyWith(isRestoringSession: false));
        return;
      }

      final routeData = sessionData['route'] as Map<String, dynamic>?;
      final progressData = sessionData['progress'] as Map<String, dynamic>?;

      final queueData = sessionData['queue'] as List<dynamic>?;
      final acceptedData = sessionData['accepted'] as List<dynamic>?;
      final rejectedData = sessionData['rejected'] as List<dynamic>?;
      final tasksData = sessionData['tasks'] as List<dynamic>?;

      emit(state.copyWith(
        screen: screen,
        route: routeData != null ? GeneratedRoute.fromJson(routeData) : null,
        progress: progressData != null ? RouteProgress.fromJson(progressData) : null,
        queue: queueData?.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
        currentIndex: (sessionData['currentIndex'] as num?)?.toInt() ?? 0,
        accepted: acceptedData?.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
        rejected: rejectedData?.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
        routeAccepted: sessionData['routeAccepted'] as bool? ?? false,
        tasks: tasksData?.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
        currentStopIdx: (sessionData['currentStopIdx'] as num?)?.toInt() ?? 0,
        points: (sessionData['points'] as num?)?.toInt() ?? 0,
        taskRegenerationsLeft: (sessionData['taskRegenerationsLeft'] as num?)?.toInt() ?? 3,
        // A session saved before quests were randomised has no history. Seed
        // it from the task each stop is currently showing, so the no-repeat
        // rule holds from here on rather than starting the walk over.
        offeredQuestTypes: (sessionData['offeredQuestTypes'] as List<dynamic>?)
                ?.map((e) => (e as List<dynamic>).cast<String>().toSet())
                .toList() ??
            (tasksData ?? const [])
                .map((e) => {((e as Map<String, dynamic>)['type'] as String?) ?? 'photo'})
                .toList(),
        isRestoringSession: false,
      ));
    } catch (e, st) {
      developer.log('Restore session error', name: 'AppBloc', error: e, stackTrace: st);
      // Malformed beyond parsing (e.g. a schema change since it was saved) —
      // drop it rather than leave it to fail the same way on every future
      // launch.
      await SessionRepository.clearSession();
      emit(state.copyWith(isRestoringSession: false));
    }
  }

  void _onLeaveTour(LeaveTourEvent event, Emitter<AppState> emit) {
    _thinkTimer?.cancel();
    emit(state.copyWith(
      screen: 'map',
      route: null,
      progress: null,
      queue: const [],
      currentIndex: 0,
      accepted: const [],
      rejected: const [],
      detailLoc: null,
      detailConversation: const [],
      modifyMode: false,
      routeAccepted: false,
      tripDate: null,
      tripEndDate: null,
      tasks: const [],
      currentStopIdx: 0,
      points: 0,
      taskRegenerationsLeft: 3,
      offeredQuestTypes: const [],
      videoPlaying: false,
      isGeneratingRoute: false,
      isChatLoading: false,
      routeError: null,
      routeErrorCode: null,
    ));
  }
}

/// `firstOrNull` without pulling in package:collection for two call sites.
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
