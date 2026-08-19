// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Massar';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDone => 'Done';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionNext => 'Next';

  @override
  String get actionClose => 'Close';

  @override
  String get actionDismiss => 'Dismiss';

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get actionAllow => 'Allow';

  @override
  String get actionSettings => 'Settings';

  @override
  String get actionRetake => 'Retake';

  @override
  String get actionDiscard => 'Discard';

  @override
  String get actionBack => 'Back';

  @override
  String get navMap => 'Map';

  @override
  String get navHome => 'Home';

  @override
  String get navFolder => 'Folder';

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationHours(int hours) {
    return '${hours}h';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get homePointsSyncing => 'Points balance syncing';

  @override
  String homePointsToSpend(int count) {
    return '$count points to spend';
  }

  @override
  String get homeGreeting => 'Where to next?';

  @override
  String get homeYourRoutes => 'YOUR ROUTES';

  @override
  String get homeRoutesEmpty =>
      'Routes you generate will collect here, ready to pick up again.';

  @override
  String get homePlanNewRoute => 'Plan a new route';

  @override
  String get homePlanNewRouteSubtitle =>
      'Pick a city, a theme, and how long you have';

  @override
  String get relativeToday => 'today';

  @override
  String get relativeYesterday => 'yesterday';

  @override
  String relativeDays(int days) {
    return '${days}d';
  }

  @override
  String relativeWeeks(int weeks) {
    return '${weeks}w';
  }

  @override
  String relativeYears(int years) {
    return '${years}y';
  }

  @override
  String get mapGenerateRoute => 'Generate my route';

  @override
  String mapTripDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String get mapExpandTripOptions => 'Expand or collapse trip options';

  @override
  String get mapHideTripOptions => 'Hide trip options';

  @override
  String get mapTapToPickWilaya => 'Tap the map to pick a wilaya';

  @override
  String get mapTapAnotherToSwitch => 'Tap another to switch';

  @override
  String get mapPromptHeading => 'TELL THE AI WHAT YOU\'RE AFTER';

  @override
  String get mapPromptHint => 'quiet Roman ruins, coastal viewpoints...';

  @override
  String get mapTapPinForDetails => 'Tap a pin to see more details';

  @override
  String get mapNoRouteYet => 'No route generated yet.';

  @override
  String get timeBudgetHeading => 'HOW MUCH TIME DO YOU HAVE?';

  @override
  String timeBudgetDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String timeBudgetHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hours',
      one: 'hour',
    );
    return '$_temp0';
  }

  @override
  String get timeBudgetTripLength => 'Trip length in days';

  @override
  String get timeBudgetHoursPerDay => 'Touring hours per day';

  @override
  String get timeBudgetWholeTrip => 'for the whole trip';

  @override
  String get timeBudgetEachDay => 'on each of those days';

  @override
  String get searchWilayaHint => 'Search for a wilaya...';

  @override
  String get searchMyLocation => 'My location';

  @override
  String get searchNoWilayas => 'No wilayas found.';

  @override
  String get locationServicesDisabled => 'Location services disabled.';

  @override
  String get locationPermissionDenied => 'Location permissions denied.';

  @override
  String get locationPermissionPermanentlyDenied =>
      'Location permissions permanently denied.';

  @override
  String get locationLocating => 'Locating...';

  @override
  String get locationRestartRequired =>
      'Please completely STOP and restart the app.';

  @override
  String genericError(String message) {
    return 'Error: $message';
  }

  @override
  String get thinkingAlmostThere => 'Almost there...';

  @override
  String get thinkingStepBudget => 'Reading your time budget…';

  @override
  String get thinkingStepStops => 'Picking published stops for your theme…';

  @override
  String get thinkingStepClusters => 'Grouping them into walkable clusters…';

  @override
  String get thinkingStepDrive => 'Ordering the drive between clusters…';

  @override
  String get thinkingStepWalk => 'Ordering the walk inside each one…';

  @override
  String get thinkingStepFit => 'Checking it all fits your day…';

  @override
  String get thinkingNotifyMe => 'Notify me';

  @override
  String get thinkingWillLetYouKnow => 'We\'ll let you know when it\'s ready';

  @override
  String get thinkingTurnOnNotifications =>
      'Turn on Notifications to find out\nwhen it\'s ready';

  @override
  String get notifyEnabled => 'We\'ll let you know the moment it\'s ready.';

  @override
  String get notifyLocalOnly =>
      'Notifications are on while the app is open in the background.';

  @override
  String get notifyLocalOnlySettings =>
      'On, but only while the app is running — push is not set up on this build.';

  @override
  String get notifyDenied =>
      'Notifications are turned off for this app — enable them in Settings.';

  @override
  String get notifyDeniedSettings =>
      'Notifications are turned off for this app in your system settings.';

  @override
  String get notifyOffline =>
      'Couldn\'t save that right now. Try again once you\'re back online.';

  @override
  String swipeKeepTheRest(int reviewed, int total) {
    return 'Keep the rest ($reviewed/$total)';
  }

  @override
  String swipeShortBy(String duration) {
    return '$duration short';
  }

  @override
  String get swipeAllSeen => 'That\'s everything here';

  @override
  String get swipeEmptyAllRejected =>
      'You turned every stop down, and this city has no others to suggest. Go back to change the theme or give yourself less time.';

  @override
  String get swipeEmptyNoMore =>
      'This city has no more stops to fill the rest of your time. Carry on with what you kept, or go back and try a different theme.';

  @override
  String get swipeUndo => 'Undo the last swipe';

  @override
  String get swipeDrop => 'Drop this stop';

  @override
  String get swipeAbout => 'About this stop';

  @override
  String get swipeKeep => 'Keep this stop';

  @override
  String get swipeBadgeLike => 'LIKE';

  @override
  String get swipeBadgeNope => 'NOPE';

  @override
  String get swipeBadgeMoreInfo => 'MORE INFO ↓';

  @override
  String get resultBackToPlanning => 'Back to planning';

  @override
  String get resultOpenMap => 'Open map';

  @override
  String get resultYourRoute => 'Your route';

  @override
  String get resultItinerary => 'ITINERARY';

  @override
  String get resultRemoveStops => 'Remove stops';

  @override
  String resultStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '$count stop',
    );
    return '$_temp0';
  }

  @override
  String get resultStartRoute => 'Start this route';

  @override
  String get resultNoStopsLeft => 'No stops left';

  @override
  String get resultNoRouteYet => 'No route yet';

  @override
  String get resultDroppedEveryStop =>
      'You dropped every stop on this route. Try another theme, a longer time budget, or a different city.';

  @override
  String get resultPickCityAndTheme =>
      'Pick a city and a theme to plan your first route.';

  @override
  String get resultChangeThePlan => 'Change the plan';

  @override
  String get transportWalking => 'Walking';

  @override
  String get transportDriving => 'Driving';

  @override
  String get transportHybrid => 'Drive + walk';

  @override
  String get routeFallbackTitle => 'Route';

  @override
  String get itineraryDrive => 'Drive';

  @override
  String get itineraryWalk => 'Walk';

  @override
  String itineraryLeg(String duration, String distance) {
    return '$duration · $distance';
  }

  @override
  String itineraryDwell(String duration) {
    return '$duration here';
  }

  @override
  String get routeHeaderTotal => 'total';

  @override
  String routeHeaderStops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'stops',
      one: 'stop',
    );
    return '$_temp0';
  }

  @override
  String routeHeaderOverBudgetTitle(String budget) {
    return 'Longer than your $budget';
  }

  @override
  String routeHeaderOverBudgetBody(String duration, int days) {
    return 'This route needs about $duration. Plan on $days days, or remove a few stops below.';
  }

  @override
  String get routeHeaderSomethingWrong => 'Something went wrong';

  @override
  String routeSummaryStopSemantic(int index, String name) {
    return 'Stop $index, $name';
  }

  @override
  String get routeSummaryCurrentStop => ', current stop';

  @override
  String get routeSummaryVisited => ', visited';

  @override
  String routeLegendDrive(String duration) {
    return 'Drive · $duration';
  }

  @override
  String routeLegendWalk(String duration) {
    return 'Walk · $duration';
  }

  @override
  String routeMapSummary(String stops, String duration) {
    return '$stops · $duration';
  }

  @override
  String get overviewYourRoute => 'YOUR ROUTE';

  @override
  String get overviewTitle => 'Overview';

  @override
  String overviewPointsEarned(int count) {
    return '$count points earned on this route';
  }

  @override
  String get overviewRouteCompleteBanner => 'ROUTE COMPLETE';

  @override
  String overviewStopOfBanner(int index, int total) {
    return 'STOP $index OF $total';
  }

  @override
  String overviewStopOf(int index, int total) {
    return 'Stop $index of $total';
  }

  @override
  String get overviewAllDone => 'All done!';

  @override
  String get overviewRouteCompleteTitle => 'Route complete!';

  @override
  String get overviewRouteCompleteBody =>
      'You visited every stop. Your captures are waiting in the folder.';

  @override
  String get overviewEndVisit => 'End visit';

  @override
  String get overviewEndOfRoute => 'End of route';

  @override
  String get overviewUpcoming => 'UPCOMING';

  @override
  String get taskCurrentTask => 'CURRENT TASK';

  @override
  String taskRegenerate(int count) {
    return 'Regenerate ($count)';
  }

  @override
  String taskPoints(int points) {
    return '+$points pts';
  }

  @override
  String get taskHunt => 'Hunt';

  @override
  String get taskStopHunt => 'Stop';

  @override
  String get taskShoot => 'Shoot';

  @override
  String get taskFilm => 'Film';

  @override
  String get taskScan => 'Scan';

  @override
  String get questPhoto1 =>
      'Take a photo that shows why this place is worth stopping at.';

  @override
  String get questPhoto2 =>
      'Frame one detail here that a passing tourist would miss.';

  @override
  String get questPhoto3 =>
      'Photograph this stop the way you would describe it to someone.';

  @override
  String get questVideo1 =>
      'Hold the shutter and film a slow pan across this place.';

  @override
  String get questVideo2 =>
      'Film a short clip walking up to it — hold the shutter to record.';

  @override
  String get questVideo3 =>
      'Hold the shutter for a few seconds of this place with its sound.';

  @override
  String get questMascot1 =>
      'A fennec is hiding somewhere here — find it and photograph it.';

  @override
  String get questMascot2 =>
      'There is a fennec nearby. Follow the signal and catch it.';

  @override
  String get questMascot3 => 'Hunt down the fennec hiding at this stop.';

  @override
  String get huntLoadingArData => 'Loading AR data…';

  @override
  String get huntFindingPosition => 'Finding your position…';

  @override
  String get huntGettingFix => 'Getting a fix on your position…';

  @override
  String get huntTurnOnLocation =>
      'Turn on location services to start the hunt.';

  @override
  String get huntNeedsLocation =>
      'The hunt needs your location to guide you to the fennec.';

  @override
  String get huntLocationOffForApp =>
      'Location is turned off for this app. Enable it in Settings to hunt.';

  @override
  String get huntTestingModeNote =>
      'Testing mode — this fennec was spawned near you, not at the stop.';

  @override
  String get huntRightUnderYourNose => 'Right under your nose';

  @override
  String huntMetersAway(int meters) {
    return '$meters m away';
  }

  @override
  String huntKilometersAway(String km) {
    return '$km km away';
  }

  @override
  String huntAccuracyNote(int meters) {
    return ' ±$meters m';
  }

  @override
  String get huntOpenCamera => 'Open camera';

  @override
  String get huntGetCloser => 'Get closer to unlock the camera';

  @override
  String get huntBandFrozen => 'Ice cold';

  @override
  String get huntBandCold => 'Cold';

  @override
  String get huntBandWarm => 'Getting warmer';

  @override
  String get huntBandHot => 'Hot!';

  @override
  String get huntBandBurning => 'It\'s right here!';

  @override
  String get huntHintFrozen => 'Somewhere out there — follow the arrow';

  @override
  String get huntHintCold => 'Keep exploring in that direction';

  @override
  String get huntHintWarm => 'You\'re on the right track';

  @override
  String get huntHintHot => 'So close now — a few more steps';

  @override
  String get huntHintBurning => 'Open the camera to catch it';

  @override
  String get arModeMedia => 'Media';

  @override
  String get arModeScan => '3D Scan';

  @override
  String get arNoCamera => 'No camera on this device';

  @override
  String get arCameraNeedsPermission =>
      'The camera needs permission before it can open.';

  @override
  String arCameraDidNotOpen(String error) {
    return 'The camera didn\'t open: $error';
  }

  @override
  String get arCouldNotReadModel => 'Could not read the mascot model.';

  @override
  String get arCouldNotPlaceFennec =>
      'Could not place the fennec. Try again in a moment.';

  @override
  String get arHuntNeedsCamera =>
      'The hunt needs the camera to see the room around you.';

  @override
  String get arPhotoNeedsCamera => 'Taking a photo needs the camera.';

  @override
  String get arAllowCamera => 'Allow camera';

  @override
  String get arKeepThisClip => 'Keep this clip?';

  @override
  String get arScanThis => 'Scan this?';

  @override
  String get arKeepThisPhoto => 'Keep this photo?';

  @override
  String get arFindTheFennec => 'Find the fennec';

  @override
  String get arScanAnObject => 'Scan an object';

  @override
  String get arPhotoOrVideo => 'Photo or video';

  @override
  String get arClipLooping => 'It\'s looping — watch it before you decide';

  @override
  String get arCheckObjectSharp => 'Check the object is sharp and whole';

  @override
  String get arCheckItCameOut => 'Check it came out how you wanted';

  @override
  String get arSomewhereAroundYou => 'Somewhere around you';

  @override
  String get arComesBackAs3d => 'It comes back as a 3D model';

  @override
  String get arGoesToYourFolder => 'It goes straight to your folder';

  @override
  String get arFillTheFrame => 'Fill the frame with one object, then shoot';

  @override
  String get arTapToShootHoldToFilm => 'Tap to shoot · hold to film';

  @override
  String get arStageReadingRoom => 'Reading the room';

  @override
  String get arStageReadingRoomHint => 'Hold the phone up and move it slowly';

  @override
  String get arStageLettingOut => 'Letting the fennec out';

  @override
  String get arStageLettingOutHint => 'Hold steady for a second';

  @override
  String get arStageThereItIs => 'There it is — tap it';

  @override
  String get arStageItIsOutThere => 'It is out there — follow the arrow';

  @override
  String get arStageWalkAround => 'Walk around it to see it from any side';

  @override
  String get arStageFoundIt => 'Found it';

  @override
  String get arStageFrameTheShot => 'Frame the shot and take your photo';

  @override
  String arDistanceAway(String meters) {
    return '$meters m away';
  }

  @override
  String get arFloorEstimated =>
      'Floor estimated — it settles itself as the room is mapped';

  @override
  String arQuestNeedsClip(int seconds) {
    return 'This one wants a clip — hold the shutter for $seconds seconds or more';
  }

  @override
  String arClipTooShort(int actual, int required) {
    return 'That clip was ${actual}s — this quest needs at least $required. Hold for longer.';
  }

  @override
  String get arHoldToFilm => 'Hold the shutter for a moment to film';

  @override
  String arHoldToFilmMinimum(int seconds) {
    return 'Hold to film · ${seconds}s minimum';
  }

  @override
  String arClipCapped(int seconds) {
    return 'Clip capped at ${seconds}s';
  }

  @override
  String arKeepClip(int seconds) {
    return 'Keep ${seconds}s clip';
  }

  @override
  String get arScanIt => 'Scan it';

  @override
  String get arUsePhoto => 'Use photo';

  @override
  String arSecondsLeft(int seconds) {
    return '${seconds}s left';
  }

  @override
  String get arTapToTakePhoto => 'Tap to take the photo';

  @override
  String get arClipWontPlayBack =>
      'That clip won\'t play back. Discard it and film again.';

  @override
  String arCouldNotTakeShot(String error) {
    return 'Couldn\'t take that shot: $error';
  }

  @override
  String arCouldNotStartFilming(String error) {
    return 'Couldn\'t start filming: $error';
  }

  @override
  String arClipDidNotSave(String error) {
    return 'The clip didn\'t save: $error';
  }

  @override
  String arCouldNotSaveClip(String error) {
    return 'Couldn\'t save that clip: $error';
  }

  @override
  String arCouldNotSaveShot(String error) {
    return 'Couldn\'t save that shot: $error';
  }

  @override
  String arCouldNotScanShot(String error) {
    return 'Couldn\'t scan that shot: $error';
  }

  @override
  String arClipSaved(int seconds) {
    return '${seconds}s clip saved to your folder';
  }

  @override
  String get arFennecCaught => 'Fennec caught!';

  @override
  String get arPhotoSaved => 'Photo saved to your folder';

  @override
  String get arNoClearObject =>
      'No clear object in that shot — nothing scanned. Try filling more of the frame with the subject.';

  @override
  String get arGenerating3dModel =>
      'Generating 3D model — check your folder in a moment';

  @override
  String get folderYourFolder => 'YOUR FOLDER';

  @override
  String get folderTitle => 'Saved & Scanned';

  @override
  String get folderSearchScans => 'Search your scans';

  @override
  String get folderSearchSaved => 'Search saved locations';

  @override
  String get folderNoScans => 'No scans yet';

  @override
  String get folderNoScansBody =>
      'Complete scan and video tasks on your route to fill this folder.';

  @override
  String get folderNoSavedLocations => 'No saved locations';

  @override
  String get artifactGenerating3d => 'Generating 3D…';

  @override
  String get artifact3dFailed => '3D Failed';

  @override
  String get artifact3dModel => '3D Model';

  @override
  String get artifactPhoto => 'Photo';

  @override
  String get artifactVideo => 'Video';

  @override
  String get artifactYourCapture => 'Your capture';

  @override
  String get artifactGenerationFailed => 'Generation failed';

  @override
  String get modelFailNoSubject =>
      'No clear object found — try a different angle';

  @override
  String get modelFailTimeout => 'Timed out — tap to retry';

  @override
  String get modelFailGpuOom => 'Server busy — tap to retry';

  @override
  String get modelFailInternal => 'Something went wrong — tap to retry';

  @override
  String get viewerCouldNotLoadFile => 'Could not load 3D model file';

  @override
  String get viewerLoadingModel => 'Loading 3D model…';

  @override
  String get viewerCouldNotDisplay => 'Could not display 3D model';

  @override
  String viewerCouldNotDisplayError(String error) {
    return 'Could not display 3D model — $error';
  }

  @override
  String get viewerHintInteractive3d =>
      'Interactive 3D model — touch to rotate';

  @override
  String get viewerHintVideo => 'Tap the video to play or pause';

  @override
  String get viewerHintPinchZoom => 'Pinch to zoom · drag to pan';

  @override
  String get viewerHintDragRotate => 'Drag to rotate · pinch to zoom';

  @override
  String get viewerClipUnplayable =>
      'This clip can\'t be played — the file may have been removed.';

  @override
  String get viewerPhotoUnloadable => 'This photo couldn\'t be loaded.';

  @override
  String get rewardsTitle => 'Rewards';

  @override
  String get rewardsOnlyOnRoute => 'Available once you are walking a route.';

  @override
  String get rewardsNothingToSpendOn => 'Nothing to spend on right now';

  @override
  String get rewardsPullDownToRetry =>
      'Pull down to check again once you have a connection.';

  @override
  String rewardsVoucherGranted(String code) {
    return 'Voucher $code is in your rewards. Show it to collect.';
  }

  @override
  String rewardsCreditsGranted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scan credits added. They do not expire.',
      one: 'One scan credit added. It does not expire.',
    );
    return '$_temp0';
  }

  @override
  String rewardsRerollsGranted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more quest swaps on this tour.',
      one: 'One more quest swap on this tour.',
    );
    return '$_temp0';
  }

  @override
  String rewardsGranted(String title) {
    return '$title is yours.';
  }

  @override
  String get balanceToSpend => 'TO SPEND';

  @override
  String get balanceSyncing => 'Syncing…';

  @override
  String balancePoints(int count) {
    return '$count points';
  }

  @override
  String get rewardKindDigital => 'For the app';

  @override
  String get rewardKindPartner => 'Along the way';

  @override
  String get rewardKindPhysical => 'Things to keep';

  @override
  String get rewardKindDigitalBlurb =>
      'Spend points on what Massar itself can do.';

  @override
  String get rewardKindPartnerBlurb =>
      'Redeemed at a place on one of your routes.';

  @override
  String get rewardKindPhysicalBlurb =>
      'Collected in person. Needs an account.';

  @override
  String get rewardOwned => 'Owned';

  @override
  String get rewardSoldOut => 'Sold out';

  @override
  String rewardStockLeft(int count) {
    return '$count left';
  }

  @override
  String get rewardPointsUnit => 'points';

  @override
  String get rewardFallbackTitle => 'Reward';

  @override
  String get redeemCosts => 'Costs';

  @override
  String get redeemYouAreShort => 'You are short';

  @override
  String get redeemLeftAfterwards => 'Left afterwards';

  @override
  String get redeemNoteInstant =>
      'Bought once and kept. There is no way to sell it back.';

  @override
  String get redeemNoteVoucher =>
      'A code to show in person. It lasts 14 days, then the points come back to you.';

  @override
  String get redeemNoteManual =>
      'Needs an account — this is something we hand you.';

  @override
  String get redeemNotYet => 'Not yet';

  @override
  String get redeemNotEnoughPoints => 'Not enough points';

  @override
  String get redeemConfirm => 'Redeem';

  @override
  String get redeemFailSignIn => 'Sign in first so this stays with you.';

  @override
  String get redeemFailOffline =>
      'You\'re offline. Redeeming needs a connection so your balance stays right.';

  @override
  String get redeemFailNotEnough =>
      'Not enough points yet — finish another task or two.';

  @override
  String get redeemFailUnavailable => 'This one is no longer available.';

  @override
  String get redeemFailOutOfStock =>
      'The last one just went. More are on the way.';

  @override
  String get redeemFailAlreadyOwned => 'You already have this one.';

  @override
  String get redeemFailNeedsAccount =>
      'Create an account to claim something we have to hand you in person.';

  @override
  String get redeemFailRateLimited =>
      'That is a lot of redeeming at once. Try again in a few minutes.';

  @override
  String get redeemFailGeneric =>
      'That didn\'t go through. Your points are untouched — try again.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionTour => 'TOUR';

  @override
  String get settingsLeaveTour => 'Leave Current Tour';

  @override
  String get settingsSectionArHunt => 'AR HUNT';

  @override
  String get settingsTestingMode => 'Testing mode';

  @override
  String get settingsTestingModeSubtitle =>
      'Spawn the mascot near your current location';

  @override
  String get settingsSectionAccount => 'ACCOUNT';

  @override
  String get settingsSectionNotifications => 'NOTIFICATIONS';

  @override
  String get settingsSectionLanguage => 'LANGUAGE';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Follow device';

  @override
  String get settingsLanguageSystemSubtitle =>
      'Use whatever language your phone is set to';

  @override
  String get settingsSectionAbout => 'ABOUT';

  @override
  String get settingsReplayIntro => 'Replay intro';

  @override
  String get settingsReplayIntroSubtitle => 'The tour of what Massar does';

  @override
  String settingsVersion(String version) {
    return 'Massar v$version';
  }

  @override
  String get settingsTotalPoints => 'Total points';

  @override
  String get settingsSyncing => 'Syncing…';

  @override
  String get settingsEarnedAcrossTours => 'Earned across every tour';

  @override
  String get settingsSignedIn => 'Signed in';

  @override
  String get settingsCreateAccount => 'Create an account';

  @override
  String get settingsAccountFollows =>
      'Your points and souvenirs follow this account';

  @override
  String get settingsGuestOnDevice =>
      'Guest — your progress lives only on this device';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsOn => 'Routes, 3D models, and nearby fennecs';

  @override
  String get settingsNotificationsOff =>
      'Off — you will not be told when anything is ready';

  @override
  String get settingsRouteReady => 'Route ready';

  @override
  String get settingsRouteReadySubtitle =>
      'When a route you asked for has finished generating';

  @override
  String get settings3dCaptures => '3D captures';

  @override
  String get settings3dCapturesSubtitle =>
      'When a model you photographed is ready, or failed';

  @override
  String get settingsFennecNearby => 'Fennec nearby';

  @override
  String get settingsFennecNearbySubtitle =>
      'While a hunt is on, when you get close to one';

  @override
  String get settingsPushNotConfigured =>
      'Push is not configured, so these arrive only while the app is open or in the background.';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authCreateYourAccount => 'Create your account';

  @override
  String get authLogIn => 'Log in';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authEmail => 'Email';

  @override
  String get authEmailHint => 'you@example.com';

  @override
  String get authPassword => 'Password';

  @override
  String get authPasswordHintSignup => 'At least 6 characters';

  @override
  String get authPasswordHintLogin => '••••••••';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authCreateAccountButton => 'Create account';

  @override
  String get authContinueAsGuest => 'Continue as guest';

  @override
  String get authGuestKeepsProgress =>
      'Everything you have already collected stays yours — signing up saves it to your account.';

  @override
  String get authCanSignUpLater =>
      'You can create an account later from Settings.';

  @override
  String get authResetYourPassword => 'Reset your password';

  @override
  String get authResetEmailBlurb =>
      'We will email you a link to set a new one.';

  @override
  String get authSendLink => 'Send link';

  @override
  String get authEnterEmail => 'Enter your email address.';

  @override
  String get authInvalidEmail =>
      'That does not look like a valid email address.';

  @override
  String get authEnterPassword => 'Enter your password.';

  @override
  String get authPasswordTooShort => 'Use at least 6 characters.';

  @override
  String get authUseDifferentEmail => 'Use a different email';

  @override
  String get authCheckYourEmail => 'Check your email';

  @override
  String authCodeSentTo(int length) {
    return 'We sent a $length-digit code to\n';
  }

  @override
  String get authConfirm => 'Confirm';

  @override
  String authResendIn(int seconds) {
    return 'Resend code in ${seconds}s';
  }

  @override
  String get authSendNewCode => 'Send a new code';

  @override
  String get authCodeExpiryNote =>
      'The code expires after an hour. Check your spam folder if it has not arrived.';

  @override
  String get authChooseNewPassword => 'Choose a new password';

  @override
  String get authNewPasswordBlurb =>
      'This replaces the old one everywhere. You will stay signed in on this device.';

  @override
  String get authNewPassword => 'New password';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authTypeItAgain => 'Type it again';

  @override
  String get authEnterNewPassword => 'Enter a new password.';

  @override
  String get authPasswordsDoNotMatch => 'These do not match.';

  @override
  String get authSavePassword => 'Save password';

  @override
  String get authAccountCreatedWithProgress =>
      'Account created. Everything you have collected is now saved to it.';

  @override
  String get authAccountCreated => 'Account created.';

  @override
  String get authCodeAcceptedChoosePassword =>
      'Code accepted. Choose a new password.';

  @override
  String get authEmailConfirmed => 'Email confirmed. Your account is ready.';

  @override
  String authNewCodeSent(String email) {
    return 'A new code is on its way to $email.';
  }

  @override
  String get authWelcomeBackNotice => 'Welcome back.';

  @override
  String get authPasswordUpdated => 'Password updated. You are signed in.';

  @override
  String get authErrorNetwork =>
      'Couldn\'t reach the server. Check your connection and try again.';

  @override
  String get authErrorEmailNotSending =>
      'We couldn\'t send your code — email is not going out right now. This is on our side; try again in a few minutes.';

  @override
  String get authErrorBadCredentials =>
      'That email and password do not match an account.';

  @override
  String get authErrorAlreadyRegistered =>
      'That email already has an account. Try logging in instead.';

  @override
  String get authErrorPasswordTooShort =>
      'Passwords need to be at least 6 characters.';

  @override
  String get authErrorTooManyAttempts =>
      'Too many attempts. Wait a minute and try again.';

  @override
  String get authErrorCodeExpired =>
      'That code has expired. Ask for a new one.';

  @override
  String get authErrorCodeInvalid =>
      'That code isn\'t right. Check the email and try again.';

  @override
  String get authErrorGeneric => 'Something went wrong. Try again.';

  @override
  String get authAnonymousSignInFailed => 'Anonymous sign-in failed';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingIllustration => 'Illustration';

  @override
  String onboardingPageOf(int index, int count) {
    return 'Page $index of $count';
  }

  @override
  String get onboardingWelcomeTitle => 'This is Massar';

  @override
  String get onboardingWelcomeBody =>
      'Plan where you go, find something to do when you get there, and take a piece of it home.';

  @override
  String get onboardingRoutesTitle => 'A route built around you';

  @override
  String get onboardingRoutesBody =>
      'Pick a city, say what you are in the mood for, and get a plan that fits your day — with a small task waiting at every stop.';

  @override
  String get onboardingCaptureTitle => 'Catch fennecs, keep souvenirs';

  @override
  String get onboardingCaptureBody =>
      'Raise your camera to find the fennecs hiding at your stops — and to scan real objects into 3D souvenirs for your folder.';

  @override
  String get onboardingRewardsTitle => 'Turn your points into something real';

  @override
  String get onboardingRewardsBody =>
      'Spend what you earn on rewards from the places along the way.';

  @override
  String get detailAskTheAi => 'ASK THE AI';

  @override
  String get detailBestTimeToVisit => 'Best time to visit?';

  @override
  String get detailHowLongToExplore => 'How long to explore?';

  @override
  String get detailAskAnything => 'Ask anything about this spot...';

  @override
  String get detailSkipThisSpot => 'Skip this spot';

  @override
  String get detailAddToRoute => 'Add to route';

  @override
  String get detailGuideUnreachable =>
      'Sorry, I couldn\'t reach the guide right now — try again.';

  @override
  String get offlineBackOnline => 'Back online — syncing…';

  @override
  String offlinePendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Offline — $count items will sync when online',
      one: 'Offline — $count item will sync when online',
    );
    return '$_temp0';
  }

  @override
  String get offlineProgressSaved => 'Offline — your progress is saved';

  @override
  String get backendConnected => 'Connected to the server';

  @override
  String get backendUnreachable =>
      'Can\'t reach the server — showing demo data';

  @override
  String get routeErrorUnreachable => 'Couldn\'t reach the route service.';

  @override
  String get routeErrorCityNotAvailable =>
      'This city isn\'t open for routes yet.';

  @override
  String get routeErrorNoEligiblePois =>
      'No published stops match that theme here yet.';

  @override
  String get routeErrorTimeBudgetTooShort =>
      'That time budget is too short for any stop here.';

  @override
  String get routeErrorProviderUnavailable =>
      'The routing service is unavailable right now.';

  @override
  String get routeErrorNotImplemented =>
      'Route generation is not built yet on this server.';

  @override
  String get routeErrorGeneric => 'Something went wrong generating your route.';

  @override
  String get routeErrorDropStopsFailed =>
      'Couldn\'t drop those stops — showing the route as generated.';

  @override
  String get routeErrorBelowBudget =>
      'Removing that would leave less than the time you asked for.';

  @override
  String get routeErrorRemoveStopFailed =>
      'Couldn\'t remove that stop — try again.';

  @override
  String get notifChannelRoutesName => 'Routes and models';

  @override
  String get notifChannelRoutesDescription =>
      'When a route is ready, or a 3D capture has finished.';

  @override
  String get notifChannelHuntName => 'Fennec hunt';

  @override
  String get notifChannelHuntDescription =>
      'When you are getting close to a hidden fennec.';

  @override
  String get notifRouteReadyTitle => 'Your route is ready';

  @override
  String get notifRouteReadyBody => 'Tap to see where you are going.';

  @override
  String notifRouteReadyBodyNamed(String title) {
    return '$title is planned and waiting for you.';
  }

  @override
  String get notifModelReadyTitle => 'Your 3D model is ready';

  @override
  String get notifModelFailedTitle => 'That capture didn\'t work out';

  @override
  String get notifModelReadyBody => 'Tap to see it in your folder.';

  @override
  String get notifModelFailNoSubject =>
      'We couldn\'t find a clear object — try filling more of the frame with it.';

  @override
  String get notifModelFailTimeout =>
      'It took too long to build. Tap to try that photo again.';

  @override
  String get notifModelFailQuota =>
      'You\'ve used all your model credits for today.';

  @override
  String get notifModelFailGeneric =>
      'Something went wrong building it. Tap to try again.';

  @override
  String get notifMascotHereTitle => 'A fennec is right here!';

  @override
  String get notifMascotWarmTitle => 'You\'re getting warm';

  @override
  String get notifMascotHereBody => 'Tap to open the camera and catch it.';

  @override
  String get notifMascotNearbyBody => 'A fennec is hiding somewhere close by.';

  @override
  String notifMascotNearbyBodyNamed(String stopName) {
    return 'A fennec is hiding near $stopName.';
  }

  @override
  String get settingsSplatReady => '3D scenes from your footage';

  @override
  String get settingsSplatReadySubtitle =>
      'When a clip you recorded is turned into a scene you can walk around';

  @override
  String get notifInboxTitle => 'Notifications';

  @override
  String notifInboxUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notifications, $count unread',
      one: 'Notifications, 1 unread',
    );
    return '$_temp0';
  }

  @override
  String get notifInboxEmptyTitle => 'Nothing yet';

  @override
  String get notifInboxEmptyBody =>
      'When a route is planned, a capture becomes a 3D model, or your footage helps build a scene, it will show up here.';

  @override
  String get notifInboxClearAll => 'Clear all';

  @override
  String get notifInboxClearTitle => 'Clear all notifications?';

  @override
  String get notifInboxClearBody =>
      'They will be deleted for good. Anything they point to — a route, a model, a scene — stays where it is.';

  @override
  String get notifInboxClearConfirm => 'Clear all';

  @override
  String get notifInboxDelete => 'Delete';

  @override
  String get notifInboxDeleteFailed =>
      'Couldn\'t delete that right now. Try again once you\'re back online.';

  @override
  String get notifInboxNothingToOpen =>
      'There\'s nothing left to open for this one.';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: 'yesterday',
    );
    return '$_temp0';
  }

  @override
  String get splatViewerSubtitle => 'Built from your footage';

  @override
  String get splatViewerHint =>
      'Drag to look around · pinch to zoom · double-tap to reset';

  @override
  String get splatViewerOpening => 'Opening the scene…';

  @override
  String get splatViewerDownloading => 'Downloading the scene…';

  @override
  String get splatViewerFailed => 'Couldn\'t open the scene';

  @override
  String splatViewerCounts(int shown, int trained) {
    final intl.NumberFormat shownNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String shownString = shownNumberFormat.format(shown);
    final intl.NumberFormat trainedNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String trainedString = trainedNumberFormat.format(trained);

    return '$shownString of $trainedString gaussians';
  }

  @override
  String get splatDetailLow => 'Smooth';

  @override
  String get splatDetailMedium => 'Balanced';

  @override
  String get splatDetailHigh => 'Detailed';

  @override
  String splatDetailSemantic(String level) {
    return 'Detail: $level';
  }
}
