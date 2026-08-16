import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/location.dart';
import '../../models/route.dart';

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

class SetMapCenterEvent extends AppEvent {
  const SetMapCenterEvent(this.center);
  final LatLng center;

  @override
  List<Object?> get props => [center];
}

// ---------------------------------------------------------------------------
// Route request building
//
// What goes on the wire is (city, theme, time budget, transport mode) — the
// module selects from a curated, published POI catalogue per city.
//
// What the traveller *manipulates* is a region circle, a sentence, and a trip
// length. Those are not the same thing, and the gap between them is closed
// here rather than by making the traveller think in the server's terms: the
// circle resolves to a city (AppState.cityForRegion), the sentence is
// interpreted into a theme plus categories (InterpretPromptEvent), and days
// convert to minutes (AppState.timeBudgetMinutes).
// ---------------------------------------------------------------------------

/// Loads the city list plus the theme/category vocabulary. Dispatched once at
/// startup and again after sign-in.
class LoadRouteOptionsEvent extends AppEvent {
  const LoadRouteOptionsEvent();
}

class SelectCityEvent extends AppEvent {
  const SelectCityEvent(this.cityId);
  final String cityId;

  @override
  List<Object?> get props => [cityId];
}

class SelectThemeEvent extends AppEvent {
  const SelectThemeEvent(this.themeKey);
  final String themeKey;

  @override
  List<Object?> get props => [themeKey];
}

/// Categories narrow a theme. Optional — a theme on its own is a valid request.
class ToggleCategoryEvent extends AppEvent {
  const ToggleCategoryEvent(this.categoryKey);
  final String categoryKey;

  @override
  List<Object?> get props => [categoryKey];
}

/// Tapping a wilaya on the map: selects it, or clears it if it was already the
/// selected one.
class ToggleWilayaEvent extends AppEvent {
  const ToggleWilayaEvent(this.wilayaId);
  final String wilayaId;

  @override
  List<Object?> get props => [wilayaId];
}

/// Selects a wilaya outright, with no toggle-off.
///
/// Search needs this and the map tap does not. Picking "Oran" from a list of
/// search results is a statement about what the traveller wants, not a switch
/// being flipped — routing it through [ToggleWilayaEvent] meant searching for
/// the wilaya you already had selected silently deselected it.
class SelectWilayaEvent extends AppEvent {
  const SelectWilayaEvent(this.wilayaId);
  final String wilayaId;

  @override
  List<Object?> get props => [wilayaId];
}

/// Records what the traveller is typing. Does not interpret it — that costs a
/// round trip and should happen when they are done, not per keystroke.
class SetPromptEvent extends AppEvent {
  const SetPromptEvent(this.text);
  final String text;

  @override
  List<Object?> get props => [text];
}

/// Turns the prompt into a theme and categories.
class InterpretPromptEvent extends AppEvent {
  const InterpretPromptEvent();
}

/// Trip length in days. Converted to the minutes the request carries by
/// [AppState.timeBudgetMinutes] — a traveller plans in days, and the module
/// takes minutes.
class SetTripDaysEvent extends AppEvent {
  const SetTripDaysEvent(this.days);
  final int days;

  @override
  List<Object?> get props => [days];
}

/// Touring hours within each of those days.
///
/// The other half of the time budget: days say how long the trip is, this says
/// how much of each one is actually spent walking around. Half a day is a
/// common, real answer that days alone could not express.
class SetHoursPerDayEvent extends AppEvent {
  const SetHoursPerDayEvent(this.hours);
  final int hours;

  @override
  List<Object?> get props => [hours];
}

class SetTransportModeEvent extends AppEvent {
  const SetTransportModeEvent(this.mode);
  final TransportMode mode;

  @override
  List<Object?> get props => [mode];
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

class GenerateRouteEvent extends AppEvent {
  const GenerateRouteEvent();
}

class ThinkTickEvent extends AppEvent {
  const ThinkTickEvent();
}

/// A route came back. Carries the whole route, not just a stop list — the
/// segments, the estimated duration and the day-count flag are all part of
/// what the result screen renders.
class RouteGeneratedEvent extends AppEvent {
  const RouteGeneratedEvent(this.route);
  final GeneratedRoute route;

  @override
  List<Object?> get props => [route];
}

/// Reopen an already-generated route by its id.
///
/// Exists for the "your route is ready" notification. That push is sent for
/// the case where the app was killed while a route generated — the request
/// finishes on the server either way — so by the time the traveller taps it,
/// this process has no memory of the route at all. The id in the notification
/// is the only way back, and `GET /api/routes/:id` is where it leads.
class OpenRouteByIdEvent extends AppEvent {
  const OpenRouteByIdEvent(this.routeId);
  final String routeId;

  @override
  List<Object?> get props => [routeId];
}

/// Generation failed. `code` is the server's machine-readable error, so the UI
/// can tell "this city isn't open yet" from "nothing matched" from "the
/// backend is down" — three states the old repository collapsed into an empty
/// list.
class RouteGenerationFailedEvent extends AppEvent {
  const RouteGenerationFailedEvent(this.code, this.message);
  final String code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}

class BackToMapEvent extends AppEvent {
  const BackToMapEvent();
}

// ---------------------------------------------------------------------------
// Review step (swipe)
// ---------------------------------------------------------------------------

class CommitSwipeEvent extends AppEvent {
  const CommitSwipeEvent(this.isAccept);
  final bool isAccept;

  @override
  List<Object?> get props => [isAccept];
}

/// Takes back the last swipe.
///
/// A flick is easy to misjudge and there is no other way to recover one: a
/// rejected stop is dropped from the route and, at the end of the review, the
/// route is re-generated without it. Re-planning the whole trip because of a
/// slip of the thumb is not a reasonable price, and every swipe interface the
/// gesture is borrowed from offers this.
class UndoSwipeEvent extends AppEvent {
  const UndoSwipeEvent();
}

/// Refills the review deck from the route's held-back candidates when the
/// stops kept so far do not fill the traveller's budget.
///
/// Dispatched when the deck empties short of the budget, so a rejection costs
/// the traveller a choice rather than costing them their day.
class OfferAlternateStopsEvent extends AppEvent {
  const OfferAlternateStopsEvent();
}

/// The review is done. If anything was dropped, the route is re-generated
/// without those stops so the ordering, segments and duration are all correct
/// for what's left — removing a stop from the list client-side would leave the
/// drive/walk legs and the total describing a route that no longer exists.
class ConfirmReviewedStopsEvent extends AppEvent {
  const ConfirmReviewedStopsEvent();
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

// ---------------------------------------------------------------------------
// Result screen
// ---------------------------------------------------------------------------

class ToggleModifyEvent extends AppEvent {
  const ToggleModifyEvent();
}

/// Drops a stop from the result screen and re-generates, for the same reason
/// [ConfirmReviewedStopsEvent] does.
class RemoveStopEvent extends AppEvent {
  const RemoveStopEvent(this.index);
  final int index;

  @override
  List<Object?> get props => [index];
}

class TogglePlayEvent extends AppEvent {
  const TogglePlayEvent();
}

class AcceptRouteEvent extends AppEvent {
  const AcceptRouteEvent();
}

// ---------------------------------------------------------------------------
// Walking the route
// ---------------------------------------------------------------------------

/// Records an arrival at the current stop. Whether the traveller was actually
/// inside the stop's checkpoint radius is the AR trigger service's call; this
/// only logs what it reports.
class RecordCheckpointEvent extends AppEvent {
  const RecordCheckpointEvent(this.poiId);
  final String poiId;

  @override
  List<Object?> get props => [poiId];
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
  const AddCapturedArtifactEvent(this.filePath, {this.kindLabel, this.kind});
  final String filePath;

  /// What the folder should call this one. Left null, the label is inferred
  /// from the task in progress — right for a capture that answers a task, but
  /// a plain photo taken from the nav bar answers nothing and would inherit
  /// "Scan" from the fallback.
  final String? kindLabel;

  /// What was actually captured — one of the quest types in [kQuestTypes], or
  /// `'scan'`.
  ///
  /// This is what decides whether the capture *answers the current quest*.
  /// Before it existed, any capture finished whatever quest happened to be
  /// open: a photo closed a video quest, and a snapshot taken from the nav bar
  /// hundreds of metres from a stop closed whichever quest was next. Null
  /// means "this capture answers nothing" and leaves the quest alone.
  final String? kind;

  @override
  List<Object?> get props => [filePath, kindLabel, kind];
}

/// A fennec was caught.
///
/// Separate from [AddCapturedArtifactEvent] because a catch is no longer filed
/// in the folder — the fennec belongs in the collection album, not among the
/// traveller's own photographs. All this carries is the fact of the catch, so
/// the mascot quest at the current stop can be finished.
class MascotCaughtEvent extends AppEvent {
  const MascotCaughtEvent();
}

class LeaveTourEvent extends AppEvent {
  const LeaveTourEvent();
}

/// Loads the user's persisted bookmarks from Supabase into state.
class LoadSavedLocationsEvent extends AppEvent {
  const LoadSavedLocationsEvent();

  @override
  List<Object?> get props => [];
}

/// Brings [AppState.lifetimePoints] up to date, and drains any task
/// completions that were recorded while offline.
///
/// Dispatched at startup and again whenever the session changes — the bloc is
/// built before anonymous sign-in lands, and a login swaps the identity the
/// score belongs to, so neither moment can be the only one.
class LoadPointsEvent extends AppEvent {
  const LoadPointsEvent();

  @override
  List<Object?> get props => [];
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
    this.title,
  });
  final String artifactId;
  final String localImagePath;
  final List<int> imageBytes;
  final String sha256;

  /// Stored on the `artifacts` row so a capture is identifiable server-side.
  final String? title;

  @override
  List<Object?> get props => [artifactId, localImagePath, sha256];
}

/// Rehydrates the folder from the `artifacts` table at startup, so models
/// generated in an earlier session are still there after the app is closed.
class LoadArtifactsEvent extends AppEvent {
  const LoadArtifactsEvent();

  @override
  List<Object?> get props => [];
}

// ---------------------------------------------------------------------------
// AR mascot hunt — testing mode
// ---------------------------------------------------------------------------

/// Generates [AppState.testMascotSpawn] near the device's current position.
/// Dispatched once at startup when [AppState.arTestingMode] is on, and again
/// whenever testing mode is switched on with no spawn yet.
class InitTestMascotSpawnEvent extends AppEvent {
  const InitTestMascotSpawnEvent();
}

/// Flips [AppState.arTestingMode] — whether the hunt spawns near the device
/// instead of a stop's real coordinates.
class ToggleArTestingModeEvent extends AppEvent {
  const ToggleArTestingModeEvent();
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

/// Restores the route generation session from SharedPreferences on startup.
class RestoreSessionEvent extends AppEvent {
  const RestoreSessionEvent();
}

