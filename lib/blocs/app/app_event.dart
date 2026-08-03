import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/location.dart';

/// Every user-intent action is represented as a discrete event dispatched to
/// [AppBloc]. UI widgets never mutate state directly.
abstract class AppEvent extends Equatable {
  const AppEvent();

  @override
  List<Object?> get props => [];
}

class SetScreenEvent extends AppEvent {
  const SetScreenEvent(this.screen);
  final String screen;

  @override
  List<Object?> get props => [screen];
}

class ToggleRegionEvent extends AppEvent {
  const ToggleRegionEvent(this.name);
  final String name;

  @override
  List<Object?> get props => [name];
}

class SetRadiusEvent extends AppEvent {
  const SetRadiusEvent(this.value);
  final double value;

  @override
  List<Object?> get props => [value];
}

class SetWantedVisitsEvent extends AppEvent {
  const SetWantedVisitsEvent(this.value);
  final int? value;

  @override
  List<Object?> get props => [value];
}

class SetMapCenterEvent extends AppEvent {
  const SetMapCenterEvent(this.center);
  final LatLng center;

  @override
  List<Object?> get props => [center];
}

class SetPromptEvent extends AppEvent {
  const SetPromptEvent(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

class GenerateRouteEvent extends AppEvent {
  const GenerateRouteEvent();
}

/// Dispatched on app startup to resume any async route generation.
class ResumeRouteEvent extends AppEvent {
  const ResumeRouteEvent();
}

class ThinkTickEvent extends AppEvent {
  const ThinkTickEvent();
}

class FinishThinkingEvent extends AppEvent {
  const FinishThinkingEvent(this.filteredLocations, {this.isRefresh = false});
  final List<Location> filteredLocations;
  final bool isRefresh;

  @override
  List<Object?> get props => [filteredLocations, isRefresh];
}

class RefreshQueueEvent extends AppEvent {
  const RefreshQueueEvent();
}

class BackToMapEvent extends AppEvent {
  const BackToMapEvent();
}

class CommitSwipeEvent extends AppEvent {
  const CommitSwipeEvent(this.isAccept);
  final bool isAccept;

  @override
  List<Object?> get props => [isAccept];
}

class OpenDetailEvent extends AppEvent {
  const OpenDetailEvent(this.loc);
  final Location loc;

  @override
  List<Object?> get props => [loc];
}

class CloseDetailEvent extends AppEvent {
  const CloseDetailEvent();
}

class AskQuestionEvent extends AppEvent {
  /// Sends the question to /api/chat. The bloc fetches the answer asynchronously.
  const AskQuestionEvent(this.question, {this.locationId});
  final String question;
  /// Optional: if null the bloc uses state.detailLoc.id
  final String? locationId;

  @override
  List<Object?> get props => [question, locationId];
}

class OnDetailAcceptEvent extends AppEvent {
  const OnDetailAcceptEvent();
}

class OnDetailRejectEvent extends AppEvent {
  const OnDetailRejectEvent();
}

class ToggleModifyEvent extends AppEvent {
  const ToggleModifyEvent();
}

class ToggleAskPanelEvent extends AppEvent {
  const ToggleAskPanelEvent();
}

class SendAIChangeEvent extends AppEvent {
  const SendAIChangeEvent(this.text);
  final String text;

  @override
  List<Object?> get props => [text];
}

class MoveStopEvent extends AppEvent {
  const MoveStopEvent(this.index, this.direction);
  final int index;
  final int direction;

  @override
  List<Object?> get props => [index, direction];
}

class RemoveStopEvent extends AppEvent {
  const RemoveStopEvent(this.index);
  final int index;

  @override
  List<Object?> get props => [index];
}

class ReorderStopsEvent extends AppEvent {
  const ReorderStopsEvent(this.oldIndex, this.newIndex);
  final int oldIndex;
  final int newIndex;

  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class TogglePlayEvent extends AppEvent {
  const TogglePlayEvent();
}

class AcceptRouteEvent extends AppEvent {
  const AcceptRouteEvent();
}

class RestoreAcceptedRouteEvent extends AppEvent {
  const RestoreAcceptedRouteEvent(this.acceptedLocations);
  final List<Location> acceptedLocations;

  @override
  List<Object?> get props => [acceptedLocations];
}

class CompleteTaskEvent extends AppEvent {
  const CompleteTaskEvent();
}

class RegenerateTaskEvent extends AppEvent {
  const RegenerateTaskEvent();
}

class AdvanceStopEvent extends AppEvent {
  const AdvanceStopEvent();
}

class NavHomeEvent extends AppEvent {
  const NavHomeEvent();
}

class AddCapturedArtifactEvent extends AppEvent {
  const AddCapturedArtifactEvent(this.filePath);
  final String filePath;

  @override
  List<Object?> get props => [filePath];
}

class LeaveTourEvent extends AppEvent {
  const LeaveTourEvent();
}

class ToggleSavedLocationEvent extends AppEvent {
  const ToggleSavedLocationEvent(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

class SetTripDateEvent extends AppEvent {
  const SetTripDateEvent(this.start, [this.end]);
  final DateTime? start;
  final DateTime? end;

  @override
  List<Object?> get props => [start, end];
}

/// Fired when a model_jobs Realtime update arrives.
class JobStatusUpdatedEvent extends AppEvent {
  const JobStatusUpdatedEvent({
    required this.jobId,
    required this.status,
    this.outputPath,
    this.errorCode,
  });
  final String jobId;
  final String status;
  final String? outputPath;
  final String? errorCode;

  @override
  List<Object?> get props => [jobId, status, outputPath, errorCode];
}

/// Triggers the full 3D capture flow: compress → upload → call /api/models/generate.
class RequestModelGenerationEvent extends AppEvent {
  const RequestModelGenerationEvent({
    required this.artifactId,
    required this.localImagePath,
    required this.imageBytes,
    required this.sha256,
  });
  final String artifactId;
  final String localImagePath;
  final List<int> imageBytes;
  final String sha256;

  @override
  List<Object?> get props => [artifactId, localImagePath, sha256];
}

/// Inserts a fully-formed [Artifact] (with modelStatus etc.) into the folder
/// without going through the AddCapturedArtifactEvent path-only constructor.
/// Used by the camera screen after object detection passes.
class OptimisticArtifactEvent extends AppEvent {
  const OptimisticArtifactEvent(this.artifact);
  final Artifact artifact;

  @override
  List<Object?> get props => [artifact];
}
