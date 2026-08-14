import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/location.dart';
import '../../models/location_data.dart';
import '../../models/quest_type.dart';
import '../../models/route.dart';

/// A single message in a chat conversation (detail panel).
class ChatMessage extends Equatable {
  const ChatMessage(this.role, this.text);

  final String role;
  final String text;

  @override
  List<Object?> get props => [role, text];
}

/// Immutable application state consumed by [AppBloc].
///
/// All fields are final. Mutations produce a new [AppState] via [copyWith].
class AppState extends Equatable {
  const AppState({
    this.screen = 'map',
    this.mapCenter = const LatLng(36.7538, 3.0588),
    List<String>? selectedRegions,
    // --- route request ---
    this.cities = const [],
    this.themes = const [],
    this.categories = const [],
    this.selectedCityId,
    this.selectedTheme,
    Set<String>? selectedCategoryKeys,
    this.selectedWilayas = const {},
    this.prompt = '',
    this.isInterpretingPrompt = false,
    this.promptInterpreted = false,
    this.tripDays = 1,
    this.hoursPerDay = defaultHoursPerDay,
    this.transportMode = TransportMode.hybrid,
    this.isLoadingOptions = false,
    // --- generated route ---
    this.route,
    this.progress,
    this.thinkIdx = 0,
    this.queue = const [],
    this.currentIndex = 0,
    this.accepted = const [],
    this.rejected = const [],
    this.detailLoc,
    this.detailConversation = const [],
    this.modifyMode = false,
    this.routeAccepted = false,
    this.tasks = const [],
    this.currentStopIdx = 0,
    this.points = 0,
    this.lifetimePoints,
    this.taskRegenerationsLeft = 3,
    this.offeredQuestTypes = const [],
    this.videoPlaying = false,
    this.folderSearch = '',
    this.capturedArtifacts = const [],
    Set<String>? savedLocationIds,
    this.tripDate,
    this.tripEndDate,
    this.isGeneratingRoute = false,
    this.isChatLoading = false,
    this.routeError,
    this.routeErrorCode,
    this.arTestingMode = true,
    this.testMascotSpawn,
    this.reviewExhausted = false,
    this.isRestoringSession = true,
  })  : selectedRegions = selectedRegions ?? regions,
        selectedCategoryKeys = selectedCategoryKeys ?? const {},
        savedLocationIds = savedLocationIds ?? const {};

  /// How much of a day a traveller actually spends touring.
  ///
  /// The request the server takes is in minutes, but nobody plans a trip in
  /// minutes — they plan it in days. A "day" here is eight hours of walking
  /// and looking, not twenty-four: budgeting a full calendar day would tell
  /// the module a traveller is available through the night and produce a
  /// route that only fits if they never sleep.
  static const int minutesPerTouringDay = defaultHoursPerDay * 60;

  /// Trip lengths the picker offers, in days. Capped at 4 because
  /// 4 × 8 h = 1920 min is comfortably inside the server's 3-day
  /// (4320-minute) ceiling, and past that the day-count flag is the honest
  /// answer rather than a longer single route.
  static const List<int> tripDayOptions = [1, 2, 3, 4];

  /// Touring hours in one of those days.
  ///
  /// Days alone were too coarse to say what people actually have: "I land at
  /// two and fly out tomorrow" is half a day, and rounding it up to eight
  /// hours produces a route they cannot finish — which the traveller reads as
  /// the app being wrong rather than as their own budget being optimistic.
  ///
  /// Two is the floor because the server refuses anything under 30 minutes and
  /// most single stops here run 20–45 minutes of dwell alone. Twelve is the
  /// ceiling because past that it stops being a touring day.
  static const List<int> hoursPerDayOptions = [2, 4, 6, 8, 10, 12];
  static const int defaultHoursPerDay = 8;

  static const double minRadiusKm = 5;
  static const double maxRadiusKm = 60;

  final String screen;
  final LatLng mapCenter;
  final List<String> selectedRegions;

  // --- route request ---------------------------------------------------------
  final List<City> cities;
  final List<RouteTheme> themes;
  final List<RouteCategory> categories;
  final String? selectedCityId;
  final String? selectedTheme;

  /// Optional narrowing within a theme. Empty means "the whole theme".
  final Set<String> selectedCategoryKeys;

  /// Radius of the region circle drawn around [mapCenter], in km.
  ///
  /// The server does not take a radius — routes are scoped to a city's
  /// published POI catalogue — so this is not forwarded. It is how the
  /// traveller says *where*, and [cityForRegion] turns that into the
  /// `city_id` the request actually carries.
  final Set<String> selectedWilayas;

  /// What the traveller typed. Interpreted into a theme and categories rather
  /// than sent as-is: the module selects from a curated catalogue by category,
  /// and has no free-text ranking to hand a prompt to.
  final String prompt;

  final bool isInterpretingPrompt;

  /// True once a prompt has been turned into a theme + categories, so the UI
  /// can show what it understood instead of a bare list of filters.
  final bool promptInterpreted;

  final int tripDays;

  /// Touring hours in each of [tripDays]. See [hoursPerDayOptions].
  final int hoursPerDay;

  final TransportMode transportMode;
  final bool isLoadingOptions;

  /// The wire value. Derived, because days and hours are what the traveller
  /// chose and minutes are only what the request happens to be expressed in —
  /// storing the total alongside its parts invites them to disagree.
  int get timeBudgetMinutes => tripDays * hoursPerDay * 60;

  // --- generated route -------------------------------------------------------

  /// The route as generated: stops, mode-tagged segments, estimated duration
  /// and day-count flag. Null before the first generation.
  final GeneratedRoute? route;

  /// Walk state, once the route is accepted and started. Deliberately separate
  /// from [route] — the route never changes as it is walked.
  final RouteProgress? progress;

  final int thinkIdx;

  /// The review queue: the generated route's stops, as displayable places.
  /// [Location] rather than [RouteStop] so the swipe card, the detail overlay
  /// and the bookmark flow — all of which are about places, not routes — keep
  /// working unchanged.
  final List<Location> queue;
  final int currentIndex;
  final List<Location> accepted;
  final List<Location> rejected;

  final Location? detailLoc;
  final List<ChatMessage> detailConversation;
  final bool modifyMode;
  final bool routeAccepted;
  final List<Task> tasks;
  final int currentStopIdx;

  /// Points earned on *this* tour. Reset by [LeaveTourEvent], because the
  /// overview screen's pill is a readout of the walk in progress.
  final int points;

  /// The traveller's score across every tour they have ever done, mirrored
  /// from `profiles.total_points`.
  ///
  /// Null means "not known yet" rather than zero — this device may never have
  /// synced, and showing a real 400-point traveller a 0 while the network
  /// answers is worse than showing nothing.
  ///
  /// Kept separate from [points] because they answer different questions and
  /// have different lifetimes: leaving a tour zeroes one and must not touch
  /// the other.
  final int? lifetimePoints;

  /// True when the review ran out of stops to offer before the budget was
  /// filled. Distinguishes "keep swiping" from "this city has no more", which
  /// are the same empty deck and very different messages.
  final bool reviewExhausted;

  final int taskRegenerationsLeft;

  /// Quest types already offered at each stop, indexed alongside [tasks].
  ///
  /// This is what "no do-overs" is enforced against: regenerating a quest
  /// picks a type that has never been shown at that stop, so a traveller who
  /// starts on the fennec hunt cannot be handed it again. History rather than
  /// a counter, because the rule is about *which* ones were seen, and a count
  /// cannot answer that.
  final List<Set<String>> offeredQuestTypes;

  // --- review budget gate ----------------------------------------------------

  /// Minutes of travel the generated route spends per stop.
  ///
  /// Derived rather than assumed: the route's own estimate minus the dwell it
  /// accounts for is its travel, and dividing by its stop count gives what one
  /// stop costs to reach. Using the server's own numbers means the gate agrees
  /// with the route the server actually built, instead of a constant that
  /// drifts from it.
  double get _travelPerStopMinutes {
    final r = route;
    if (r == null || r.stops.isEmpty) return 0;
    final dwell = r.stops.fold<int>(0, (sum, s) => sum + s.dwellMinutes);
    final travel = r.estimatedTotalDurationMinutes - dwell;
    if (travel <= 0) return 0;
    return travel / r.stops.length;
  }

  /// What the stops kept so far add up to, in the same accounting the route
  /// itself uses: dwell plus that stop's share of the travel.
  int get acceptedMinutes {
    if (accepted.isEmpty) return 0;
    final dwell = accepted.fold<int>(0, (sum, l) => sum + l.dwellMinutes);
    return (dwell + _travelPerStopMinutes * accepted.length).round();
  }

  /// The bar the review has to clear.
  ///
  /// Not the raw budget. A city's catalogue frequently cannot fill a whole day
  /// — Constantine's "culture" theme has one POI in it — so requiring the full
  /// budget would leave the traveller stuck behind a button that can never
  /// unlock. The route the module produced is the most it could offer, so
  /// clearing *that* is the honest test of "you kept enough".
  int get requiredMinutes {
    final r = route;
    if (r == null) return 0;
    return r.estimatedTotalDurationMinutes < timeBudgetMinutes
        ? r.estimatedTotalDurationMinutes
        : timeBudgetMinutes;
  }

  /// True once the kept stops fill the time the traveller asked for.
  bool get budgetFilled => route == null || acceptedMinutes >= requiredMinutes;

  /// Whether the route can lose one more stop and still fill the budget.
  ///
  /// The review screen's delete is the same decision the swipe screen's reject
  /// is, one screen later, so it answers to the same rule: a traveller may trim
  /// their day, but not below the day they asked for.
  bool canRemoveStop(int dwellMinutes) {
    final r = route;
    if (r == null || r.stops.length <= 1) return false;
    final after = r.estimatedTotalDurationMinutes - dwellMinutes - _travelPerStopMinutes;
    return after >= requiredMinutes;
  }

  /// Stops that have not been offered yet — the deck plus anything held back.
  bool get hasMoreCandidates =>
      currentIndex < queue.length || (route?.alternates.isNotEmpty ?? false);

  /// Quest types still unoffered at the current stop.
  Set<String> get remainingQuestTypes {
    if (currentStopIdx >= offeredQuestTypes.length) return kQuestTypes.toSet();
    return kQuestTypes.toSet().difference(offeredQuestTypes[currentStopIdx]);
  }

  /// Whether the current stop's quest can still be swapped. Two limits, and
  /// either one ends it: the per-tour regeneration budget, and having run out
  /// of types this stop has not already shown.
  bool get canRegenerateQuest =>
      taskRegenerationsLeft > 0 &&
      remainingQuestTypes.isNotEmpty &&
      currentStopIdx < tasks.length &&
      tasks[currentStopIdx].state == 'pending';
  final bool videoPlaying;
  final String folderSearch;
  final List<Artifact> capturedArtifacts;
  final Set<String> savedLocationIds;
  final DateTime? tripDate;
  final DateTime? tripEndDate;
  // Async loading & error state
  final bool isGeneratingRoute;
  final bool isChatLoading;
  final String? routeError;

  /// The server's machine-readable error code, so the UI can distinguish
  /// `city_not_available` from `no_eligible_pois` from a transport failure.
  final String? routeErrorCode;

  /// Whether the mascot hunt spawns near the device's own position instead of
  /// a route stop's real coordinates. Seeded from [AppConfig.arTestingMode]
  /// at startup; toggleable live from Settings.
  final bool arTestingMode;

  /// A mascot spawn point generated near wherever the app was at launch, for
  /// [arTestingMode]. Null until [AppBloc] resolves a GPS fix.
  final LatLng? testMascotSpawn;

  /// True from construction until [AppBloc]'s startup [RestoreSessionEvent]
  /// handler has run to completion (found nothing, restored a session, or hit
  /// an error — any outcome counts as "done").
  ///
  /// Two things depend on this being accurate: [AppShell] holds up rendering
  /// while it is true, so the map never flashes before a swap to a restored
  /// screen; and [AppBloc.onChange] refuses to clear the persisted session
  /// while it is true, because the other startup events ([LoadRouteOptionsEvent]
  /// etc.) run concurrently with the restore and would otherwise routinely
  /// win the race and wipe the saved session out from under it before it's
  /// ever read.
  final bool isRestoringSession;

  /// The location currently being reviewed, or null if the queue is exhausted.
  Location? get currentLoc {
    if (currentIndex >= 0 && currentIndex < queue.length) {
      return queue[currentIndex];
    }
    return null;
  }

  City? get selectedCity {
    for (final c in cities) {
      if (c.id == selectedCityId) return c;
    }
    return null;
  }

  /// What the region circle currently picks out.
  ///
  /// Two different cities, deliberately kept apart:
  ///
  ///   * [nearest] is the city the circle is *over*, whatever its rollout
  ///     status. This is what the readout names, so dragging the map actually
  ///     changes what the panel says. Reporting only the routable city made the
  ///     label constant — there is one routable city in the pilot, so it read
  ///     "Algiers" no matter where you dragged, which looks broken.
  ///   * [routable] is the city the request will carry, since a `planning`
  ///     city cannot be generated for.
  ///
  /// When they differ, the UI says so rather than silently routing somewhere
  /// the traveller is not looking at.
  RegionSelection get regionSelection {
    City? nearest;
    var nearestKm = double.infinity;
    City? routable;
    var routableKm = double.infinity;

    for (final city in cities) {
      final centre = city.centre;
      if (centre == null) continue;

      final km = _haversineKm(mapCenter, centre);
      if (km < nearestKm) {
        nearestKm = km;
        nearest = city;
      }
      if (city.rolloutStatus.isRoutable && km < routableKm) {
        routableKm = km;
        routable = city;
      }
    }

    return RegionSelection(
      nearest: nearest,
      nearestDistanceKm: nearest == null ? 0 : nearestKm,
      nearestContained: nearest != null && nearestKm <= 15.0, // fallback
      routable: routable,
      routableDistanceKm: routable == null ? 0 : routableKm,
      routableContained: routable != null && routableKm <= 15.0, // fallback
    );
  }

  /// The theme the request will carry.
  ///
  /// The server rejects a request without one, but the traveller is no longer
  /// required to produce one: describing the trip is optional, and an empty
  /// description falls back to the first theme the server offers. Refusing to
  /// plan anything until someone types a sentence would make the prompt a
  /// mandatory form field dressed up as a convenience.
  String? get effectiveTheme => selectedTheme ?? (themes.isEmpty ? null : themes.first.key);

  /// Whether the request can be generated.
  ///
  /// Deliberately does *not* require prompt text. It still requires a routable
  /// city and a loaded vocabulary, because without those the request would fail
  /// at the server rather than merely be unrefined — an always-enabled button
  /// that always errors is worse than a disabled one that says why.
  bool get canGenerate =>
      selectedCityId != null &&
      effectiveTheme != null &&
      (selectedCity?.rolloutStatus.isRoutable ?? false);

  /// The categories currently narrowing the theme, resolved to their labels.
  List<RouteCategory> get selectedCategories => [
        for (final c in categories)
          if (selectedCategoryKeys.contains(c.key)) c,
      ];

  RouteTheme? get selectedThemeModel {
    for (final t in themes) {
      if (t.key == selectedTheme) return t;
    }
    return null;
  }

  /// The route stops still in the itinerary after the review step, in order.
  List<RouteStop> get routeStops => route?.stops ?? const [];

  static const List<String> thinkingMessages = [
    "Reading your time budget…",
    "Picking published stops for your theme…",
    "Grouping them into walkable clusters…",
    "Ordering the drive between clusters…",
    "Ordering the walk inside each one…",
    "Checking it all fits your day…",
  ];

  AppState copyWith({
    String? screen,
    LatLng? mapCenter,
    List<String>? selectedRegions,
    List<City>? cities,
    List<RouteTheme>? themes,
    List<RouteCategory>? categories,
    Object? selectedCityId = _sentinel,
    Object? selectedTheme = _sentinel,
    Set<String>? selectedCategoryKeys,
    Set<String>? selectedWilayas,
    String? prompt,
    bool? isInterpretingPrompt,
    bool? promptInterpreted,
    int? tripDays,
    int? hoursPerDay,
    TransportMode? transportMode,
    bool? isLoadingOptions,
    Object? route = _sentinel,
    Object? progress = _sentinel,
    int? thinkIdx,
    List<Location>? queue,
    int? currentIndex,
    List<Location>? accepted,
    List<Location>? rejected,
    Object? detailLoc = _sentinel,
    List<ChatMessage>? detailConversation,
    bool? modifyMode,
    bool? routeAccepted,
    List<Task>? tasks,
    int? currentStopIdx,
    int? points,
    Object? lifetimePoints = _sentinel,
    bool? reviewExhausted,
    int? taskRegenerationsLeft,
    List<Set<String>>? offeredQuestTypes,
    bool? videoPlaying,
    String? folderSearch,
    List<Artifact>? capturedArtifacts,
    Set<String>? savedLocationIds,
    Object? tripDate = _sentinel,
    Object? tripEndDate = _sentinel,
    bool? isGeneratingRoute,
    bool? isChatLoading,
    Object? routeError = _sentinel,
    Object? routeErrorCode = _sentinel,
    bool? arTestingMode,
    Object? testMascotSpawn = _sentinel,
    bool? isRestoringSession,
  }) {
    return AppState(
      screen: screen ?? this.screen,
      mapCenter: mapCenter ?? this.mapCenter,
      selectedRegions: selectedRegions ?? this.selectedRegions,
      cities: cities ?? this.cities,
      themes: themes ?? this.themes,
      categories: categories ?? this.categories,
      selectedCityId:
          selectedCityId == _sentinel ? this.selectedCityId : selectedCityId as String?,
      selectedTheme: selectedTheme == _sentinel ? this.selectedTheme : selectedTheme as String?,
      selectedCategoryKeys: selectedCategoryKeys ?? this.selectedCategoryKeys,
      selectedWilayas: selectedWilayas ?? this.selectedWilayas,
      prompt: prompt ?? this.prompt,
      isInterpretingPrompt: isInterpretingPrompt ?? this.isInterpretingPrompt,
      promptInterpreted: promptInterpreted ?? this.promptInterpreted,
      tripDays: tripDays ?? this.tripDays,
      hoursPerDay: hoursPerDay ?? this.hoursPerDay,
      transportMode: transportMode ?? this.transportMode,
      isLoadingOptions: isLoadingOptions ?? this.isLoadingOptions,
      route: route == _sentinel ? this.route : route as GeneratedRoute?,
      progress: progress == _sentinel ? this.progress : progress as RouteProgress?,
      thinkIdx: thinkIdx ?? this.thinkIdx,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      accepted: accepted ?? this.accepted,
      rejected: rejected ?? this.rejected,
      detailLoc: detailLoc == _sentinel ? this.detailLoc : detailLoc as Location?,
      detailConversation: detailConversation ?? this.detailConversation,
      modifyMode: modifyMode ?? this.modifyMode,
      routeAccepted: routeAccepted ?? this.routeAccepted,
      tasks: tasks ?? this.tasks,
      currentStopIdx: currentStopIdx ?? this.currentStopIdx,
      points: points ?? this.points,
      lifetimePoints:
          lifetimePoints == _sentinel ? this.lifetimePoints : lifetimePoints as int?,
      reviewExhausted: reviewExhausted ?? this.reviewExhausted,
      taskRegenerationsLeft: taskRegenerationsLeft ?? this.taskRegenerationsLeft,
      offeredQuestTypes: offeredQuestTypes ?? this.offeredQuestTypes,
      videoPlaying: videoPlaying ?? this.videoPlaying,
      folderSearch: folderSearch ?? this.folderSearch,
      capturedArtifacts: capturedArtifacts ?? this.capturedArtifacts,
      savedLocationIds: savedLocationIds ?? this.savedLocationIds,
      tripDate: tripDate == _sentinel ? this.tripDate : tripDate as DateTime?,
      tripEndDate: tripEndDate == _sentinel ? this.tripEndDate : tripEndDate as DateTime?,
      isGeneratingRoute: isGeneratingRoute ?? this.isGeneratingRoute,
      isChatLoading: isChatLoading ?? this.isChatLoading,
      routeError: routeError == _sentinel ? this.routeError : routeError as String?,
      routeErrorCode:
          routeErrorCode == _sentinel ? this.routeErrorCode : routeErrorCode as String?,
      arTestingMode: arTestingMode ?? this.arTestingMode,
      testMascotSpawn:
          testMascotSpawn == _sentinel ? this.testMascotSpawn : testMascotSpawn as LatLng?,
      isRestoringSession: isRestoringSession ?? this.isRestoringSession,
    );
  }

  @override
  List<Object?> get props => [
        screen,
        mapCenter,
        selectedRegions,
        cities,
        themes,
        categories,
        selectedCityId,
        selectedTheme,
        selectedCategoryKeys,
        selectedWilayas,
        prompt,
        isInterpretingPrompt,
        promptInterpreted,
        tripDays,
        hoursPerDay,
        transportMode,
        isLoadingOptions,
        route,
        progress,
        thinkIdx,
        queue,
        currentIndex,
        accepted,
        rejected,
        detailLoc,
        detailConversation,
        modifyMode,
        routeAccepted,
        tasks,
        currentStopIdx,
        points,
        lifetimePoints,
        reviewExhausted,
        taskRegenerationsLeft,
        offeredQuestTypes,
        videoPlaying,
        folderSearch,
        capturedArtifacts,
        savedLocationIds,
        tripDate,
        tripEndDate,
        isGeneratingRoute,
        isChatLoading,
        routeError,
        routeErrorCode,
        arTestingMode,
        testMascotSpawn,
        isRestoringSession,
      ];
}

/// What the region circle resolves to.
///
/// Separates "the city you are looking at" from "the city that will be
/// routed", because the phased rollout means those are not always the same and
/// collapsing them hides the difference from the traveller.
class RegionSelection extends Equatable {
  const RegionSelection({
    required this.nearest,
    required this.nearestDistanceKm,
    required this.nearestContained,
    required this.routable,
    required this.routableDistanceKm,
    required this.routableContained,
  });

  /// Closest city of any rollout status — what the readout names.
  final City? nearest;
  final double nearestDistanceKm;
  final bool nearestContained;

  /// Closest city that can actually be generated for — what the request
  /// carries.
  final City? routable;
  final double routableDistanceKm;
  final bool routableContained;

  /// True when the circle is over a city that exists but isn't open yet, so the
  /// route will be built somewhere else.
  bool get isDivertedToOtherCity =>
      nearest != null && routable != null && nearest!.id != routable!.id;

  @override
  List<Object?> get props => [
        nearest,
        nearestDistanceKm,
        nearestContained,
        routable,
        routableDistanceKm,
        routableContained,
      ];
}

/// Sentinel so [copyWith] can distinguish "caller passed null" from "caller
/// didn't pass anything" for nullable fields.
const Object _sentinel = Object();

/// Great-circle distance in km.
///
/// Written out rather than pulled from latlong2's `Distance`, which allocates
/// a calculator per call site; this runs on every rebuild of the region
/// readout while the map is being dragged.
double _haversineKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0;
  final dLat = _radians(b.latitude - a.latitude);
  final dLng = _radians(b.longitude - a.longitude);
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);

  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1) * math.cos(lat2);
  return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
}

double _radians(double degrees) => degrees * math.pi / 180;
