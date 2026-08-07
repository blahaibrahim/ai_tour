import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/location.dart';
import '../../models/location_data.dart';
import '../../repositories/artifact_repository.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/location_repository.dart';
import '../../repositories/model_repository.dart';
import '../../repositories/saved_locations_repository.dart';
import '../../repositories/task_repository.dart';
import '../../utils/uuid.dart';
import 'app_event.dart';
import 'app_state.dart';

/// Central business-logic hub for the app.
///
/// All state mutations happen here in response to [AppEvent]s dispatched by
/// the UI. The thinking-screen animation timer lives here too, so the widget
/// layer stays completely stateless.
///
/// Backend calls now go through repository classes rather than inline HTTP —
/// see lib/repositories/. The Supabase Realtime subscription for model_jobs
/// is started here and torn down in [close].
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
    on<RefreshQueueEvent>(_onRefreshQueue);
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
    on<RestoreAcceptedRouteEvent>(_onRestoreAcceptedRoute);
    on<CompleteTaskEvent>(_onCompleteTask);
    on<RegenerateTaskEvent>(_onRegenerateTask);
    on<AdvanceStopEvent>(_onAdvanceStop);
    on<NavHomeEvent>(_onNavHome);
    on<AddCapturedArtifactEvent>(_onAddCapturedArtifact);
    on<LeaveTourEvent>(_onLeaveTour);
    on<ToggleSavedLocationEvent>(_onToggleSavedLocation);
    on<SetTripDateEvent>(_onSetTripDate);
    on<JobStatusUpdatedEvent>(_onJobStatusUpdated);
    // Without this the camera's capture flow died on its first line: bloc.add
    // throws for an unregistered event, so the optimistic insert aborted the
    // whole capture before generation was ever requested.
    on<OptimisticArtifactEvent>(_onOptimisticArtifact);
    on<RequestModelGenerationEvent>(_onRequestModelGeneration);
    on<ResumeRouteEvent>(_onResumeRoute);

    on<LoadSavedLocationsEvent>(_onLoadSavedLocations);
    on<LoadArtifactsEvent>(_onLoadArtifacts);

    _startRealtimeSubscription();
    _watchAuth();
    add(const ResumeRouteEvent());
    add(const LoadSavedLocationsEvent());
    add(const LoadArtifactsEvent());
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
      add(const LoadSavedLocationsEvent());
      add(const LoadArtifactsEvent());
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
  Future<void> close() {
    _thinkTimer?.cancel();
    _realtimeSub?.cancel();
    _authSub?.cancel();
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
  // Route generation (thinking screen) — now calls real backend
  // ---------------------------------------------------------------------------

  Future<void> _onGenerateRoute(
      GenerateRouteEvent event, Emitter<AppState> emit) async {
    _thinkTimer?.cancel();
    emit(state.copyWith(screen: 'thinking', thinkIdx: 0, isGeneratingRoute: true));

    _thinkTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      add(const ThinkTickEvent());
    });

    // Fetch from the real backend while the thinking animation plays.
    final locations = await LocationRepository.generateItinerary(
      lat: state.mapCenter.latitude,
      lng: state.mapCenter.longitude,
      radiusKm: state.radiusKm,
      prompt: state.prompt.isNotEmpty ? state.prompt : null,
      wantedVisits: state.wantedVisits,
    );

    _thinkTimer?.cancel();
    add(FinishThinkingEvent(locations));
  }

  Future<void> _onResumeRoute(
      ResumeRouteEvent event, Emitter<AppState> emit) async {
    final job = await LocationRepository.checkLatestJob();
    if (job == null) return;
    
    final status = job['status'] as String?;
    if (status == 'succeeded') {
      final resultData = job['result_data'] as Map<String, dynamic>?;
      final stops = resultData?['stops'] as List<dynamic>?;
      if (stops != null && stops.isNotEmpty) {
        final parsed = stops.whereType<Map<String, dynamic>>().map(Location.fromJson).toList();
        add(FinishThinkingEvent(parsed));
      }
    } else if (status == 'accepted') {
      final resultData = job['result_data'] as Map<String, dynamic>?;
      final stops = resultData?['stops'] as List<dynamic>?;
      if (stops != null && stops.isNotEmpty) {
        final parsed = stops.whereType<Map<String, dynamic>>().map(Location.fromJson).toList();
        add(RestoreAcceptedRouteEvent(parsed));
      }
    } else if (status == 'processing' || status == 'queued') {
      _thinkTimer?.cancel();
      emit(state.copyWith(screen: 'thinking', thinkIdx: 0, isGeneratingRoute: true));
      _thinkTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
        add(const ThinkTickEvent());
      });
      
      final parsed = await LocationRepository.pollJob(job['id'] as String);
      
      _thinkTimer?.cancel();
      add(FinishThinkingEvent(parsed));
    }
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
      accepted: event.isRefresh ? state.accepted : const [],
      rejected: event.isRefresh ? state.rejected : const [],
      screen: 'swipe',
      isGeneratingRoute: false,
    ));
  }

  Future<void> _onRefreshQueue(
      RefreshQueueEvent event, Emitter<AppState> emit) async {
    _thinkTimer?.cancel();
    emit(state.copyWith(screen: 'thinking', thinkIdx: 0));

    _thinkTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      add(const ThinkTickEvent());
    });

    final all = await LocationRepository.generateItinerary(
      lat: state.mapCenter.latitude,
      lng: state.mapCenter.longitude,
      radiusKm: state.radiusKm,
      prompt: state.prompt.isNotEmpty ? state.prompt : null,
      rejectedIds: state.rejected.map((e) => e.id).toList(),
      acceptedIds: state.accepted.map((e) => e.id).toList(),
    );

    _thinkTimer?.cancel();
    final newQueue = all.where((l) => 
        !state.accepted.any((a) => a.id == l.id) &&
        !state.rejected.any((r) => r.id == l.id)
    ).toList();
    
    add(FinishThinkingEvent(
      newQueue,
      isRefresh: true,
    ));
  }

  void _onBackToMap(BackToMapEvent event, Emitter<AppState> emit) {
    _thinkTimer?.cancel();
    emit(state.copyWith(screen: 'map'));
  }

  // ---------------------------------------------------------------------------
  // Swipe screen
  // ---------------------------------------------------------------------------

  void _handleSwipeNext(int nextIndex, List<Location> newAccepted,
      List<Location> newRejected, Emitter<AppState> emit) {
    if (nextIndex >= state.queue.length) {
      final target = state.wantedVisits;
      final canProceed = newAccepted.isNotEmpty &&
          (target == null || newAccepted.length >= target);
      if (!canProceed) {
        emit(state.copyWith(
          accepted: newAccepted,
          rejected: newRejected,
          currentIndex: nextIndex,
        ));
        add(const RefreshQueueEvent());
        return;
      } else {
        emit(state.copyWith(
          accepted: newAccepted,
          rejected: newRejected,
          currentIndex: nextIndex,
          screen: 'result',
        ));
        return;
      }
    }

    emit(state.copyWith(
      accepted: newAccepted,
      rejected: newRejected,
      currentIndex: nextIndex,
    ));
  }

  void _onCommitSwipe(CommitSwipeEvent event, Emitter<AppState> emit) {
    final loc = state.currentLoc;
    if (loc == null) return;

    final newAccepted =
        event.isAccept ? [...state.accepted, loc] : state.accepted;
    final newRejected =
        !event.isAccept ? [...state.rejected, loc] : state.rejected;

    _handleSwipeNext(state.currentIndex + 1, newAccepted, newRejected, emit);
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

  void _onToggleAskPanel(ToggleAskPanelEvent event, Emitter<AppState> emit) {
    emit(state.copyWith(askPanelOpen: !state.askPanelOpen));
  }

  /// Calls /api/itinerary/modify and updates the accepted stop list.
  Future<void> _onSendAIChange(
      SendAIChangeEvent event, Emitter<AppState> emit) async {
    if (event.text.trim().isEmpty) return;

    emit(state.copyWith(
      aiConversation: [
        ...state.aiConversation,
        ChatMessage('user', event.text),
      ],
    ));

    try {
      final newStops = await ChatRepository.modifyRoute(
        lat: state.mapCenter.latitude,
        lng: state.mapCenter.longitude,
        existingStops: state.accepted,
        changeRequest: event.text,
        radiusKm: state.radiusKm,
      );
      emit(state.copyWith(
        accepted: newStops,
        aiConversation: [
          ...state.aiConversation,
          const ChatMessage('ai', 'Done — I\'ve adjusted your route.'),
        ],
      ));
    } catch (_) {
      emit(state.copyWith(
        aiConversation: [
          ...state.aiConversation,
          const ChatMessage('ai',
              "Couldn't reach the AI right now — your route is unchanged."),
        ],
      ));
    }
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
    LocationRepository.acceptLatestItinerary(state.accepted);
  }

  void _onRestoreAcceptedRoute(RestoreAcceptedRouteEvent event, Emitter<AppState> emit) {
    final tasks = event.acceptedLocations
        .map((l) => Task(type: l.task.type, label: l.task.label, points: 30))
        .toList();
    emit(state.copyWith(
      accepted: event.acceptedLocations,
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

  /// Calls /api/tasks/generate for a real LLM-generated task.
  Future<void> _onRegenerateTask(
      RegenerateTaskEvent event, Emitter<AppState> emit) async {
    if (state.currentStopIdx >= state.tasks.length) return;
    final t = state.tasks[state.currentStopIdx];
    if (t.state != 'pending' || state.taskRegenerationsLeft <= 0) return;

    try {
      final loc = state.accepted.length > state.currentStopIdx
          ? state.accepted[state.currentStopIdx]
          : null;
      final newTask = await TaskRepository.generateTask(
        locationId: loc?.id ?? 'unknown',
        locationName: loc?.name ?? 'this location',
      );
      final updated = List<Task>.from(state.tasks);
      updated[state.currentStopIdx] = newTask.copyWith(state: 'pending', points: t.points);
      emit(state.copyWith(
        tasks: updated,
        taskRegenerationsLeft: state.taskRegenerationsLeft - 1,
      ));
    } catch (_) {
      // Fall back to the existing cycling behaviour on network failure.
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
      id: uuidV4(),
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
    } catch (_) {
      // Mark the artifact as failed so the folder shows the retry UI
      final updated = state.capturedArtifacts.map((a) {
        if (a.id != event.artifactId) return a;
        return a.copyWith(modelStatus: ModelStatus.failed, errorCode: 'internal');
      }).toList();
      emit(state.copyWith(capturedArtifacts: updated));
    }
  }

  /// Called by Realtime when a model_jobs row changes to a terminal state.
  void _onJobStatusUpdated(
      JobStatusUpdatedEvent event, Emitter<AppState> emit) {
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
      isGeneratingRoute: false,
      isChatLoading: false,
      routeError: null,
    ));
  }
}
