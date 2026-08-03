import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/location.dart';
import '../../models/location_data.dart';

/// A single message in a chat conversation (detail panel or AI modify panel).
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
    this.radiusKm = 5.0,
    this.wantedVisits,
    this.mapCenter = const LatLng(36.7538, 3.0588),
    this.prompt = '',
    List<String>? selectedRegions,
    this.thinkIdx = 0,
    this.queue = const [],
    this.currentIndex = 0,
    this.accepted = const [],
    this.rejected = const [],
    this.detailLoc,
    this.detailConversation = const [],
    this.modifyMode = false,
    this.askPanelOpen = false,
    this.aiConversation = const [],
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
  })  : selectedRegions = selectedRegions ?? regions,
        savedLocationIds = savedLocationIds ?? const {};

  final String screen;
  final double radiusKm;
  final int? wantedVisits;
  final LatLng mapCenter;
  final String prompt;
  final List<String> selectedRegions;
  final int thinkIdx;
  final List<Location> queue;
  final int currentIndex;
  final List<Location> accepted;
  final List<Location> rejected;
  final Location? detailLoc;
  final List<ChatMessage> detailConversation;
  final bool modifyMode;
  final bool askPanelOpen;
  final List<ChatMessage> aiConversation;
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

  /// The location currently being swiped on, or null if the queue is exhausted.
  Location? get currentLoc {
    if (currentIndex >= 0 && currentIndex < queue.length) {
      return queue[currentIndex];
    }
    return null;
  }

  static const List<String> thinkingMessages = [
    "Reading your radius…",
    "Checking the Casbah's alleys…",
    "Cross-referencing Constantine's bridges…",
    "Matching Djemila and Timgad's ruins…",
    "Scanning the Tassili plateau…",
    "Ranking spots against your prompt…"
  ];

  AppState copyWith({
    String? screen,
    double? radiusKm,
    Object? wantedVisits = _sentinel,
    LatLng? mapCenter,
    String? prompt,
    List<String>? selectedRegions,
    int? thinkIdx,
    List<Location>? queue,
    int? currentIndex,
    List<Location>? accepted,
    List<Location>? rejected,
    Object? detailLoc = _sentinel,
    List<ChatMessage>? detailConversation,
    bool? modifyMode,
    bool? askPanelOpen,
    List<ChatMessage>? aiConversation,
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
  }) {
    return AppState(
      screen: screen ?? this.screen,
      radiusKm: radiusKm ?? this.radiusKm,
      wantedVisits: wantedVisits == _sentinel ? this.wantedVisits : wantedVisits as int?,
      mapCenter: mapCenter ?? this.mapCenter,
      prompt: prompt ?? this.prompt,
      selectedRegions: selectedRegions ?? this.selectedRegions,
      thinkIdx: thinkIdx ?? this.thinkIdx,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      accepted: accepted ?? this.accepted,
      rejected: rejected ?? this.rejected,
      detailLoc: detailLoc == _sentinel ? this.detailLoc : detailLoc as Location?,
      detailConversation: detailConversation ?? this.detailConversation,
      modifyMode: modifyMode ?? this.modifyMode,
      askPanelOpen: askPanelOpen ?? this.askPanelOpen,
      aiConversation: aiConversation ?? this.aiConversation,
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
    );
  }

  @override
  List<Object?> get props => [
        screen,
        radiusKm,
        wantedVisits,
        mapCenter,
        prompt,
        selectedRegions,
        thinkIdx,
        queue,
        currentIndex,
        accepted,
        rejected,
        detailLoc,
        detailConversation,
        modifyMode,
        askPanelOpen,
        aiConversation,
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
      ];
}

/// Sentinel so [copyWith] can distinguish "caller passed null" from "caller
/// didn't pass anything" for nullable fields.
const Object _sentinel = Object();
