import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/location.dart';
import '../../models/location_data.dart';
import 'app_event.dart';
import 'app_state.dart';

/// Central business-logic hub for the app.
///
/// All state mutations happen here in response to [AppEvent]s dispatched by
/// the UI. The thinking-screen animation timer lives here too, so the widget
/// layer stays completely stateless.
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(const AppState()) {
    on<SetScreenEvent>(_onSetScreen);
    on<ToggleRegionEvent>(_onToggleRegion);
    on<SetRadiusEvent>(_onSetRadius);
    on<SetWantedVisitsEvent>(_onSetWantedVisits);
    on<SetMapCenterEvent>(_onSetMapCenter);
    on<SetPromptEvent>(_onSetPrompt);
    on<GenerateRouteEvent>(_onGenerateRoute);
    on<ThinkTickEvent>(_onThinkTick);
    on<FinishThinkingEvent>(_onFinishThinking);
    on<BackToMapEvent>(_onBackToMap);
    on<CommitSwipeEvent>(_onCommitSwipe);
    on<OpenDetailEvent>(_onOpenDetail);
    on<CloseDetailEvent>(_onCloseDetail);
    on<AskQuestionEvent>(_onAskQuestion);
    on<OnDetailAcceptEvent>(_onDetailAccept);
    on<OnDetailRejectEvent>(_onDetailReject);
    on<ToggleModifyEvent>(_onToggleModify);
    on<ToggleAskPanelEvent>(_onToggleAskPanel);
    on<SendAIChangeEvent>(_onSendAIChange);
    on<MoveStopEvent>(_onMoveStop);
    on<RemoveStopEvent>(_onRemoveStop);
    on<ReorderStopsEvent>(_onReorderStops);
    on<TogglePlayEvent>(_onTogglePlay);
    on<AcceptRouteEvent>(_onAcceptRoute);
    on<CompleteTaskEvent>(_onCompleteTask);
    on<RegenerateTaskEvent>(_onRegenerateTask);
    on<AdvanceStopEvent>(_onAdvanceStop);
    on<NavHomeEvent>(_onNavHome);
    on<AddCapturedArtifactEvent>(_onAddCapturedArtifact);
    on<LeaveTourEvent>(_onLeaveTour);
    on<ToggleSavedLocationEvent>(_onToggleSavedLocation);
    on<SetTripDateEvent>(_onSetTripDate);
  }

  Timer? _thinkTimer;

  @override
  Future<void> close() {
    _thinkTimer?.cancel();
    return super.close();
  }

  // ---------------------------------------------------------------------------
  // Navigation & settings
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

  void _onSetRadius(SetRadiusEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(radiusKm: event.value));
  }

  void _onSetWantedVisits(SetWantedVisitsEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(wantedVisits: event.value));
  }

  void _onSetMapCenter(SetMapCenterEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(mapCenter: event.center));
  }

  void _onSetPrompt(SetPromptEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(prompt: event.value));
  }

  // ---------------------------------------------------------------------------
  // Route generation (thinking screen)
  // ---------------------------------------------------------------------------

  void _onGenerateRoute(GenerateRouteEvent event, Emitter<AppState> emit) {
    _thinkTimer?.cancel();
    emit(state.copyWith(screen: 'thinking', thinkIdx: 0));

    _thinkTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      add(const ThinkTickEvent());
    });

    // Filter locations by selected regions, then transition to swipe screen.
    final filtered = state.selectedRegions.isNotEmpty
        ? allLocations.where((l) => state.selectedRegions.contains(l.region)).toList()
        : List<Location>.from(allLocations);

    Timer(const Duration(milliseconds: 3200), () {
      _thinkTimer?.cancel();
      add(FinishThinkingEvent(filtered.isNotEmpty ? filtered : List<Location>.from(allLocations)));
    });
  }

  void _onThinkTick(ThinkTickEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(
      thinkIdx: (state.thinkIdx + 1) % AppState.thinkingMessages.length,
    ));
  }

  void _onFinishThinking(FinishThinkingEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(
      queue: event.filteredLocations,
      currentIndex: 0,
      accepted: const [],
      rejected: const [],
      screen: 'swipe',
    ));
  }

  void _onBackToMap(BackToMapEvent event, Emitter<AppState> emit) {
    _thinkTimer?.cancel();
    emit(state.copyWith(screen: 'map'));
  }

  // ---------------------------------------------------------------------------
  // Swipe screen
  // ---------------------------------------------------------------------------

  void _onCommitSwipe(CommitSwipeEvent event, Emitter<AppState> emit) {
    final loc = state.currentLoc;
    if (loc == null) return;

    final newAccepted = event.isAccept
        ? [...state.accepted, loc]
        : state.accepted;
    final newRejected = !event.isAccept
        ? [...state.rejected, loc]
        : state.rejected;

    final newIndex = state.currentIndex + 1;
    final newScreen = newIndex >= state.queue.length ? 'result' : state.screen;

    emit(state.copyWith(
      accepted: newAccepted,
      rejected: newRejected,
      currentIndex: newIndex,
      screen: newScreen,
    ));
  }

  // ---------------------------------------------------------------------------
  // Location detail overlay
  // ---------------------------------------------------------------------------

  void _onOpenDetail(OpenDetailEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(
      detailLoc: event.loc,
      detailConversation: const [],
    ));
  }

  void _onCloseDetail(CloseDetailEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(
      detailLoc: null,
      detailConversation: const [],
    ));
  }

  void _onAskQuestion(AskQuestionEvent event, Emitter<AppState> emit) {
    if (event.question.trim().isEmpty) return;
    emit(state.copyWith(
      detailConversation: [
        ...state.detailConversation,
        ChatMessage('user', event.question),
        ChatMessage('ai', event.answer),
      ],
    ));
  }

  void _onDetailAccept(OnDetailAcceptEvent event, Emitter<AppState> emit) {
    // Commit the swipe as accept, then close the detail.
    final loc = state.currentLoc;
    if (loc == null) return;

    final newIndex = state.currentIndex + 1;
    final newScreen = newIndex >= state.queue.length ? 'result' : state.screen;

    emit(state.copyWith(
      accepted: [...state.accepted, loc],
      currentIndex: newIndex,
      screen: newScreen,
      detailLoc: null,
      detailConversation: const [],
    ));
  }

  void _onDetailReject(OnDetailRejectEvent event, Emitter<AppState> emit) {
    final loc = state.currentLoc;
    if (loc == null) return;

    final newIndex = state.currentIndex + 1;
    final newScreen = newIndex >= state.queue.length ? 'result' : state.screen;

    emit(state.copyWith(
      rejected: [...state.rejected, loc],
      currentIndex: newIndex,
      screen: newScreen,
      detailLoc: null,
      detailConversation: const [],
    ));
  }

  // ---------------------------------------------------------------------------
  // Result screen
  // ---------------------------------------------------------------------------

  void _onToggleModify(ToggleModifyEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(modifyMode: !state.modifyMode));
  }

  void _onToggleAskPanel(ToggleAskPanelEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(askPanelOpen: !state.askPanelOpen));
  }

  void _onSendAIChange(SendAIChangeEvent event, Emitter<AppState> emit) {
    if (event.text.trim().isEmpty) return;
    emit(state.copyWith(
      aiConversation: [
        ...state.aiConversation,
        ChatMessage('user', event.text),
        ChatMessage('ai', "Noted — I'll weight the next suggestions toward that."),
      ],
    ));
  }

  void _onMoveStop(MoveStopEvent event, Emitter<AppState> emit) {
    final j = event.index + event.direction;
    if (j < 0 || j >= state.accepted.length) return;
    final list = List<Location>.from(state.accepted);
    final tmp = list[event.index];
    list[event.index] = list[j];
    list[j] = tmp;
    emit(state.copyWith(accepted: list));
  }

  void _onRemoveStop(RemoveStopEvent event, Emitter<AppState> emit) {
    if (event.index < 0 || event.index >= state.accepted.length) return;
    final list = List<Location>.from(state.accepted)..removeAt(event.index);
    emit(state.copyWith(accepted: list));
  }

  void _onReorderStops(ReorderStopsEvent event, Emitter<AppState> emit) {
    int newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final list = List<Location>.from(state.accepted);
    final item = list.removeAt(event.oldIndex);
    list.insert(newIndex, item);
    emit(state.copyWith(accepted: list));
  }

  void _onTogglePlay(TogglePlayEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(videoPlaying: !state.videoPlaying));
  }

  void _onAcceptRoute(AcceptRouteEvent event, Emitter<AppState> emit) {
    final tasks = state.accepted
        .map((l) => Task(type: l.task.type, label: l.task.label, points: 30))
        .toList();
    emit(state.copyWith(
      tasks: tasks,
      screen: 'overview',
      routeAccepted: true,
      currentStopIdx: 0,
    ));
  }

  // ---------------------------------------------------------------------------
  // Overview / task management
  // ---------------------------------------------------------------------------

  void _onCompleteTask(CompleteTaskEvent event, Emitter<AppState> emit) {
    if (state.currentStopIdx >= state.tasks.length) return;
    final t = state.tasks[state.currentStopIdx];
    if (t.state == 'done') return;

    final updated = List<Task>.from(state.tasks);
    updated[state.currentStopIdx] = t.copyWith(state: 'done');
    emit(state.copyWith(
      tasks: updated,
      points: state.points + t.points,
    ));
  }

  void _onRegenerateTask(RegenerateTaskEvent event, Emitter<AppState> emit) {
    if (state.currentStopIdx >= state.tasks.length) return;
    final t = state.tasks[state.currentStopIdx];
    if (t.state != 'pending' || state.taskRegenerationsLeft <= 0) return;

    const cycle = {'video': 'scan', 'scan': 'mascot', 'mascot': 'video'};
    const labels = {
      'video': 'Record a quick panoramic video of your surroundings.',
      'scan': 'Scan the surrounding area to uncover a hidden historical detail.',
      'mascot': 'A fennec is hiding somewhere here — find it and photograph it.',
    };
    final next = cycle[t.type] ?? 'video';
    final updated = List<Task>.from(state.tasks);
    updated[state.currentStopIdx] = Task(
      type: next,
      label: labels[next]!,
      state: 'pending',
      points: t.points,
    );
    emit(state.copyWith(
      tasks: updated,
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
  // Camera / folder
  // ---------------------------------------------------------------------------

  void _onAddCapturedArtifact(
      AddCapturedArtifactEvent event, Emitter<AppState> emit) {
    Location? currentLoc;
    Task? currentTask;
    if (state.routeAccepted && state.currentStopIdx < state.accepted.length) {
      currentLoc = state.accepted[state.currentStopIdx];
      currentTask = state.currentStopIdx < state.tasks.length
          ? state.tasks[state.currentStopIdx]
          : null;
    }

    final artifact = Artifact(
      id: 'capture-${DateTime.now().millisecondsSinceEpoch}',
      name: currentLoc?.name ?? 'Your capture',
      region: currentLoc?.region ?? 'On the go',
      kindLabel: switch (currentTask?.type) {
        'video' => 'Video',
        'mascot' => 'Fennec',
        _ => 'Scan',
      },
      photoUrl: event.filePath,
      isLocalFile: true,
    );

    final newArtifacts = [artifact, ...state.capturedArtifacts];

    // If there is a pending task at the current stop, complete it now.
    if (currentTask != null && currentTask.state == 'pending') {
      final updated = List<Task>.from(state.tasks);
      updated[state.currentStopIdx] = currentTask.copyWith(state: 'done');
      emit(state.copyWith(
        capturedArtifacts: newArtifacts,
        tasks: updated,
        points: state.points + currentTask.points,
      ));
    } else {
      emit(state.copyWith(capturedArtifacts: newArtifacts));
    }
  }

  // ---------------------------------------------------------------------------
  // Saved locations & trip date
  // ---------------------------------------------------------------------------

  void _onToggleSavedLocation(
      ToggleSavedLocationEvent event, Emitter<AppState> emit) {
    final updated = Set<String>.from(state.savedLocationIds);
    if (updated.contains(event.id)) {
      updated.remove(event.id);
    } else {
      updated.add(event.id);
    }
    emit(state.copyWith(savedLocationIds: updated));
  }

  void _onSetTripDate(SetTripDateEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(tripDate: event.start, tripEndDate: event.end));
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  void _onLeaveTour(LeaveTourEvent event, Emitter<AppState> emit) {
    _thinkTimer?.cancel();
    emit(state.copyWith(
      screen: 'map',
      prompt: '',
      queue: const [],
      currentIndex: 0,
      accepted: const [],
      rejected: const [],
      detailLoc: null,
      detailConversation: const [],
      modifyMode: false,
      askPanelOpen: false,
      aiConversation: const [],
      routeAccepted: false,
      tripDate: null,
      tripEndDate: null,
      tasks: const [],
      currentStopIdx: 0,
      points: 0,
      taskRegenerationsLeft: 3,
      videoPlaying: false,
    ));
  }
}
