import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/location.dart';
import '../../models/location_data.dart';
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
    this.taskRegenerationsLeft = 3,
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
  static const int minutesPerTouringDay = 8 * 60;

  /// Trip lengths the picker offers, in days. Capped at 4 because
  /// 4 × 8 h = 1920 min is comfortably inside the server's 3-day
  /// (4320-minute) ceiling, and past that the day-count flag is the honest
  /// answer rather than a longer single route.
  static const List<int> tripDayOptions = [1, 2, 3, 4];

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
  final TransportMode transportMode;
  final bool isLoadingOptions;

  /// The wire value. Derived, because days are what the traveller chose and
  /// minutes are only what the request happens to be expressed in — storing
  /// both invites them to disagree.
  int get timeBudgetMinutes => tripDays * minutesPerTouringDay;

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
  final int points;
  final int taskRegenerationsLeft;
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
    int? taskRegenerationsLeft,
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
      taskRegenerationsLeft: taskRegenerationsLeft ?? this.taskRegenerationsLeft,
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
        taskRegenerationsLeft,
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
