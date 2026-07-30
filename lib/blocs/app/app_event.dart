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

class ThinkTickEvent extends AppEvent {
  const ThinkTickEvent();
}

class FinishThinkingEvent extends AppEvent {
  const FinishThinkingEvent(this.filteredLocations);
  final List<Location> filteredLocations;

  @override
  List<Object?> get props => [filteredLocations];
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
  const AskQuestionEvent(this.question, this.answer);
  final String question;
  final String answer;

  @override
  List<Object?> get props => [question, answer];
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
