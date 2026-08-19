import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Massar'**
  String get appTitle;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get actionDismiss;

  /// No description provided for @actionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgain;

  /// No description provided for @actionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get actionAllow;

  /// No description provided for @actionSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get actionSettings;

  /// No description provided for @actionRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get actionRetake;

  /// No description provided for @actionDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get actionDiscard;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get navFolder;

  /// A duration under an hour, as shown on route legs and time budgets.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMinutes(int minutes);

  /// A whole number of hours, with no leftover minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String durationHours(int hours);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @homePointsSyncing.
  ///
  /// In en, this message translates to:
  /// **'Points balance syncing'**
  String get homePointsSyncing;

  /// No description provided for @homePointsToSpend.
  ///
  /// In en, this message translates to:
  /// **'{count} points to spend'**
  String homePointsToSpend(int count);

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Where to next?'**
  String get homeGreeting;

  /// No description provided for @homeYourRoutes.
  ///
  /// In en, this message translates to:
  /// **'YOUR ROUTES'**
  String get homeYourRoutes;

  /// No description provided for @homeRoutesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Routes you generate will collect here, ready to pick up again.'**
  String get homeRoutesEmpty;

  /// No description provided for @homePlanNewRoute.
  ///
  /// In en, this message translates to:
  /// **'Plan a new route'**
  String get homePlanNewRoute;

  /// No description provided for @homePlanNewRouteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a city, a theme, and how long you have'**
  String get homePlanNewRouteSubtitle;

  /// No description provided for @relativeToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get relativeToday;

  /// No description provided for @relativeYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get relativeYesterday;

  /// Compact age of a saved route, in days. Kept short: it sits in a tight row.
  ///
  /// In en, this message translates to:
  /// **'{days}d'**
  String relativeDays(int days);

  /// No description provided for @relativeWeeks.
  ///
  /// In en, this message translates to:
  /// **'{weeks}w'**
  String relativeWeeks(int weeks);

  /// No description provided for @relativeYears.
  ///
  /// In en, this message translates to:
  /// **'{years}y'**
  String relativeYears(int years);

  /// No description provided for @mapGenerateRoute.
  ///
  /// In en, this message translates to:
  /// **'Generate my route'**
  String get mapGenerateRoute;

  /// No description provided for @mapTripDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day} other{{count} days}}'**
  String mapTripDays(int count);

  /// No description provided for @mapExpandTripOptions.
  ///
  /// In en, this message translates to:
  /// **'Expand or collapse trip options'**
  String get mapExpandTripOptions;

  /// No description provided for @mapHideTripOptions.
  ///
  /// In en, this message translates to:
  /// **'Hide trip options'**
  String get mapHideTripOptions;

  /// No description provided for @mapTapToPickWilaya.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to pick a wilaya'**
  String get mapTapToPickWilaya;

  /// No description provided for @mapTapAnotherToSwitch.
  ///
  /// In en, this message translates to:
  /// **'Tap another to switch'**
  String get mapTapAnotherToSwitch;

  /// No description provided for @mapPromptHeading.
  ///
  /// In en, this message translates to:
  /// **'TELL THE AI WHAT YOU\'RE AFTER'**
  String get mapPromptHeading;

  /// No description provided for @mapPromptHint.
  ///
  /// In en, this message translates to:
  /// **'quiet Roman ruins, coastal viewpoints...'**
  String get mapPromptHint;

  /// No description provided for @mapTapPinForDetails.
  ///
  /// In en, this message translates to:
  /// **'Tap a pin to see more details'**
  String get mapTapPinForDetails;

  /// No description provided for @mapNoRouteYet.
  ///
  /// In en, this message translates to:
  /// **'No route generated yet.'**
  String get mapNoRouteYet;

  /// No description provided for @timeBudgetHeading.
  ///
  /// In en, this message translates to:
  /// **'HOW MUCH TIME DO YOU HAVE?'**
  String get timeBudgetHeading;

  /// Unit shown beside the day wheel. The number is rendered separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{day} other{days}}'**
  String timeBudgetDays(int count);

  /// Unit shown beside the hours wheel. The number is rendered separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{hour} other{hours}}'**
  String timeBudgetHours(int count);

  /// No description provided for @timeBudgetTripLength.
  ///
  /// In en, this message translates to:
  /// **'Trip length in days'**
  String get timeBudgetTripLength;

  /// No description provided for @timeBudgetHoursPerDay.
  ///
  /// In en, this message translates to:
  /// **'Touring hours per day'**
  String get timeBudgetHoursPerDay;

  /// No description provided for @timeBudgetWholeTrip.
  ///
  /// In en, this message translates to:
  /// **'for the whole trip'**
  String get timeBudgetWholeTrip;

  /// No description provided for @timeBudgetEachDay.
  ///
  /// In en, this message translates to:
  /// **'on each of those days'**
  String get timeBudgetEachDay;

  /// No description provided for @searchWilayaHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a wilaya...'**
  String get searchWilayaHint;

  /// No description provided for @searchMyLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get searchMyLocation;

  /// No description provided for @searchNoWilayas.
  ///
  /// In en, this message translates to:
  /// **'No wilayas found.'**
  String get searchNoWilayas;

  /// No description provided for @locationServicesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Location services disabled.'**
  String get locationServicesDisabled;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permissions denied.'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permissions permanently denied.'**
  String get locationPermissionPermanentlyDenied;

  /// No description provided for @locationLocating.
  ///
  /// In en, this message translates to:
  /// **'Locating...'**
  String get locationLocating;

  /// No description provided for @locationRestartRequired.
  ///
  /// In en, this message translates to:
  /// **'Please completely STOP and restart the app.'**
  String get locationRestartRequired;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String genericError(String message);

  /// No description provided for @thinkingAlmostThere.
  ///
  /// In en, this message translates to:
  /// **'Almost there...'**
  String get thinkingAlmostThere;

  /// No description provided for @thinkingStepBudget.
  ///
  /// In en, this message translates to:
  /// **'Reading your time budget…'**
  String get thinkingStepBudget;

  /// No description provided for @thinkingStepStops.
  ///
  /// In en, this message translates to:
  /// **'Picking published stops for your theme…'**
  String get thinkingStepStops;

  /// No description provided for @thinkingStepClusters.
  ///
  /// In en, this message translates to:
  /// **'Grouping them into walkable clusters…'**
  String get thinkingStepClusters;

  /// No description provided for @thinkingStepDrive.
  ///
  /// In en, this message translates to:
  /// **'Ordering the drive between clusters…'**
  String get thinkingStepDrive;

  /// No description provided for @thinkingStepWalk.
  ///
  /// In en, this message translates to:
  /// **'Ordering the walk inside each one…'**
  String get thinkingStepWalk;

  /// No description provided for @thinkingStepFit.
  ///
  /// In en, this message translates to:
  /// **'Checking it all fits your day…'**
  String get thinkingStepFit;

  /// No description provided for @thinkingNotifyMe.
  ///
  /// In en, this message translates to:
  /// **'Notify me'**
  String get thinkingNotifyMe;

  /// No description provided for @thinkingWillLetYouKnow.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know when it\'s ready'**
  String get thinkingWillLetYouKnow;

  /// No description provided for @thinkingTurnOnNotifications.
  ///
  /// In en, this message translates to:
  /// **'Turn on Notifications to find out\nwhen it\'s ready'**
  String get thinkingTurnOnNotifications;

  /// No description provided for @notifyEnabled.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know the moment it\'s ready.'**
  String get notifyEnabled;

  /// No description provided for @notifyLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Notifications are on while the app is open in the background.'**
  String get notifyLocalOnly;

  /// No description provided for @notifyLocalOnlySettings.
  ///
  /// In en, this message translates to:
  /// **'On, but only while the app is running — push is not set up on this build.'**
  String get notifyLocalOnlySettings;

  /// No description provided for @notifyDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off for this app — enable them in Settings.'**
  String get notifyDenied;

  /// No description provided for @notifyDeniedSettings.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off for this app in your system settings.'**
  String get notifyDeniedSettings;

  /// No description provided for @notifyOffline.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that right now. Try again once you\'re back online.'**
  String get notifyOffline;

  /// No description provided for @swipeKeepTheRest.
  ///
  /// In en, this message translates to:
  /// **'Keep the rest ({reviewed}/{total})'**
  String swipeKeepTheRest(int reviewed, int total);

  /// How far under the requested time budget the kept stops fall. The duration is already formatted, e.g. 1h 20m.
  ///
  /// In en, this message translates to:
  /// **'{duration} short'**
  String swipeShortBy(String duration);

  /// No description provided for @swipeAllSeen.
  ///
  /// In en, this message translates to:
  /// **'That\'s everything here'**
  String get swipeAllSeen;

  /// No description provided for @swipeEmptyAllRejected.
  ///
  /// In en, this message translates to:
  /// **'You turned every stop down, and this city has no others to suggest. Go back to change the theme or give yourself less time.'**
  String get swipeEmptyAllRejected;

  /// No description provided for @swipeEmptyNoMore.
  ///
  /// In en, this message translates to:
  /// **'This city has no more stops to fill the rest of your time. Carry on with what you kept, or go back and try a different theme.'**
  String get swipeEmptyNoMore;

  /// No description provided for @swipeUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo the last swipe'**
  String get swipeUndo;

  /// No description provided for @swipeDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop this stop'**
  String get swipeDrop;

  /// No description provided for @swipeAbout.
  ///
  /// In en, this message translates to:
  /// **'About this stop'**
  String get swipeAbout;

  /// No description provided for @swipeKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep this stop'**
  String get swipeKeep;

  /// No description provided for @swipeBadgeLike.
  ///
  /// In en, this message translates to:
  /// **'LIKE'**
  String get swipeBadgeLike;

  /// No description provided for @swipeBadgeNope.
  ///
  /// In en, this message translates to:
  /// **'NOPE'**
  String get swipeBadgeNope;

  /// No description provided for @swipeBadgeMoreInfo.
  ///
  /// In en, this message translates to:
  /// **'MORE INFO ↓'**
  String get swipeBadgeMoreInfo;

  /// No description provided for @resultBackToPlanning.
  ///
  /// In en, this message translates to:
  /// **'Back to planning'**
  String get resultBackToPlanning;

  /// No description provided for @resultOpenMap.
  ///
  /// In en, this message translates to:
  /// **'Open map'**
  String get resultOpenMap;

  /// No description provided for @resultYourRoute.
  ///
  /// In en, this message translates to:
  /// **'Your route'**
  String get resultYourRoute;

  /// No description provided for @resultItinerary.
  ///
  /// In en, this message translates to:
  /// **'ITINERARY'**
  String get resultItinerary;

  /// No description provided for @resultRemoveStops.
  ///
  /// In en, this message translates to:
  /// **'Remove stops'**
  String get resultRemoveStops;

  /// No description provided for @resultStopCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} stop} other{{count} stops}}'**
  String resultStopCount(int count);

  /// No description provided for @resultStartRoute.
  ///
  /// In en, this message translates to:
  /// **'Start this route'**
  String get resultStartRoute;

  /// No description provided for @resultNoStopsLeft.
  ///
  /// In en, this message translates to:
  /// **'No stops left'**
  String get resultNoStopsLeft;

  /// No description provided for @resultNoRouteYet.
  ///
  /// In en, this message translates to:
  /// **'No route yet'**
  String get resultNoRouteYet;

  /// No description provided for @resultDroppedEveryStop.
  ///
  /// In en, this message translates to:
  /// **'You dropped every stop on this route. Try another theme, a longer time budget, or a different city.'**
  String get resultDroppedEveryStop;

  /// No description provided for @resultPickCityAndTheme.
  ///
  /// In en, this message translates to:
  /// **'Pick a city and a theme to plan your first route.'**
  String get resultPickCityAndTheme;

  /// No description provided for @resultChangeThePlan.
  ///
  /// In en, this message translates to:
  /// **'Change the plan'**
  String get resultChangeThePlan;

  /// No description provided for @transportWalking.
  ///
  /// In en, this message translates to:
  /// **'Walking'**
  String get transportWalking;

  /// No description provided for @transportDriving.
  ///
  /// In en, this message translates to:
  /// **'Driving'**
  String get transportDriving;

  /// No description provided for @transportHybrid.
  ///
  /// In en, this message translates to:
  /// **'Drive + walk'**
  String get transportHybrid;

  /// No description provided for @routeFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get routeFallbackTitle;

  /// No description provided for @itineraryDrive.
  ///
  /// In en, this message translates to:
  /// **'Drive'**
  String get itineraryDrive;

  /// No description provided for @itineraryWalk.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get itineraryWalk;

  /// No description provided for @itineraryLeg.
  ///
  /// In en, this message translates to:
  /// **'{duration} · {distance}'**
  String itineraryLeg(String duration, String distance);

  /// How long the route expects the traveller to linger at a stop.
  ///
  /// In en, this message translates to:
  /// **'{duration} here'**
  String itineraryDwell(String duration);

  /// No description provided for @routeHeaderTotal.
  ///
  /// In en, this message translates to:
  /// **'total'**
  String get routeHeaderTotal;

  /// Unit under the stop count in the route header; the number is rendered separately.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{stop} other{stops}}'**
  String routeHeaderStops(int count);

  /// No description provided for @routeHeaderOverBudgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Longer than your {budget}'**
  String routeHeaderOverBudgetTitle(String budget);

  /// No description provided for @routeHeaderOverBudgetBody.
  ///
  /// In en, this message translates to:
  /// **'This route needs about {duration}. Plan on {days} days, or remove a few stops below.'**
  String routeHeaderOverBudgetBody(String duration, int days);

  /// No description provided for @routeHeaderSomethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get routeHeaderSomethingWrong;

  /// No description provided for @routeSummaryStopSemantic.
  ///
  /// In en, this message translates to:
  /// **'Stop {index}, {name}'**
  String routeSummaryStopSemantic(int index, String name);

  /// No description provided for @routeSummaryCurrentStop.
  ///
  /// In en, this message translates to:
  /// **', current stop'**
  String get routeSummaryCurrentStop;

  /// No description provided for @routeSummaryVisited.
  ///
  /// In en, this message translates to:
  /// **', visited'**
  String get routeSummaryVisited;

  /// No description provided for @routeLegendDrive.
  ///
  /// In en, this message translates to:
  /// **'Drive · {duration}'**
  String routeLegendDrive(String duration);

  /// No description provided for @routeLegendWalk.
  ///
  /// In en, this message translates to:
  /// **'Walk · {duration}'**
  String routeLegendWalk(String duration);

  /// No description provided for @routeMapSummary.
  ///
  /// In en, this message translates to:
  /// **'{stops} · {duration}'**
  String routeMapSummary(String stops, String duration);

  /// No description provided for @overviewYourRoute.
  ///
  /// In en, this message translates to:
  /// **'YOUR ROUTE'**
  String get overviewYourRoute;

  /// No description provided for @overviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overviewTitle;

  /// No description provided for @overviewPointsEarned.
  ///
  /// In en, this message translates to:
  /// **'{count} points earned on this route'**
  String overviewPointsEarned(int count);

  /// No description provided for @overviewRouteCompleteBanner.
  ///
  /// In en, this message translates to:
  /// **'ROUTE COMPLETE'**
  String get overviewRouteCompleteBanner;

  /// No description provided for @overviewStopOfBanner.
  ///
  /// In en, this message translates to:
  /// **'STOP {index} OF {total}'**
  String overviewStopOfBanner(int index, int total);

  /// No description provided for @overviewStopOf.
  ///
  /// In en, this message translates to:
  /// **'Stop {index} of {total}'**
  String overviewStopOf(int index, int total);

  /// No description provided for @overviewAllDone.
  ///
  /// In en, this message translates to:
  /// **'All done!'**
  String get overviewAllDone;

  /// No description provided for @overviewRouteCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Route complete!'**
  String get overviewRouteCompleteTitle;

  /// No description provided for @overviewRouteCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'You visited every stop. Your captures are waiting in the folder.'**
  String get overviewRouteCompleteBody;

  /// No description provided for @overviewEndVisit.
  ///
  /// In en, this message translates to:
  /// **'End visit'**
  String get overviewEndVisit;

  /// No description provided for @overviewEndOfRoute.
  ///
  /// In en, this message translates to:
  /// **'End of route'**
  String get overviewEndOfRoute;

  /// No description provided for @overviewUpcoming.
  ///
  /// In en, this message translates to:
  /// **'UPCOMING'**
  String get overviewUpcoming;

  /// No description provided for @taskCurrentTask.
  ///
  /// In en, this message translates to:
  /// **'CURRENT TASK'**
  String get taskCurrentTask;

  /// The count is how many task swaps the traveller has left on this tour.
  ///
  /// In en, this message translates to:
  /// **'Regenerate ({count})'**
  String taskRegenerate(int count);

  /// No description provided for @taskPoints.
  ///
  /// In en, this message translates to:
  /// **'+{points} pts'**
  String taskPoints(int points);

  /// No description provided for @taskHunt.
  ///
  /// In en, this message translates to:
  /// **'Hunt'**
  String get taskHunt;

  /// No description provided for @taskStopHunt.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get taskStopHunt;

  /// No description provided for @taskShoot.
  ///
  /// In en, this message translates to:
  /// **'Shoot'**
  String get taskShoot;

  /// No description provided for @taskFilm.
  ///
  /// In en, this message translates to:
  /// **'Film'**
  String get taskFilm;

  /// No description provided for @taskScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get taskScan;

  /// No description provided for @questPhoto1.
  ///
  /// In en, this message translates to:
  /// **'Take a photo that shows why this place is worth stopping at.'**
  String get questPhoto1;

  /// No description provided for @questPhoto2.
  ///
  /// In en, this message translates to:
  /// **'Frame one detail here that a passing tourist would miss.'**
  String get questPhoto2;

  /// No description provided for @questPhoto3.
  ///
  /// In en, this message translates to:
  /// **'Photograph this stop the way you would describe it to someone.'**
  String get questPhoto3;

  /// No description provided for @questVideo1.
  ///
  /// In en, this message translates to:
  /// **'Hold the shutter and film a slow pan across this place.'**
  String get questVideo1;

  /// No description provided for @questVideo2.
  ///
  /// In en, this message translates to:
  /// **'Film a short clip walking up to it — hold the shutter to record.'**
  String get questVideo2;

  /// No description provided for @questVideo3.
  ///
  /// In en, this message translates to:
  /// **'Hold the shutter for a few seconds of this place with its sound.'**
  String get questVideo3;

  /// No description provided for @questMascot1.
  ///
  /// In en, this message translates to:
  /// **'A fennec is hiding somewhere here — find it and photograph it.'**
  String get questMascot1;

  /// No description provided for @questMascot2.
  ///
  /// In en, this message translates to:
  /// **'There is a fennec nearby. Follow the signal and catch it.'**
  String get questMascot2;

  /// No description provided for @questMascot3.
  ///
  /// In en, this message translates to:
  /// **'Hunt down the fennec hiding at this stop.'**
  String get questMascot3;

  /// No description provided for @huntLoadingArData.
  ///
  /// In en, this message translates to:
  /// **'Loading AR data…'**
  String get huntLoadingArData;

  /// No description provided for @huntFindingPosition.
  ///
  /// In en, this message translates to:
  /// **'Finding your position…'**
  String get huntFindingPosition;

  /// No description provided for @huntGettingFix.
  ///
  /// In en, this message translates to:
  /// **'Getting a fix on your position…'**
  String get huntGettingFix;

  /// No description provided for @huntTurnOnLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services to start the hunt.'**
  String get huntTurnOnLocation;

  /// No description provided for @huntNeedsLocation.
  ///
  /// In en, this message translates to:
  /// **'The hunt needs your location to guide you to the fennec.'**
  String get huntNeedsLocation;

  /// No description provided for @huntLocationOffForApp.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off for this app. Enable it in Settings to hunt.'**
  String get huntLocationOffForApp;

  /// No description provided for @huntTestingModeNote.
  ///
  /// In en, this message translates to:
  /// **'Testing mode — this fennec was spawned near you, not at the stop.'**
  String get huntTestingModeNote;

  /// No description provided for @huntRightUnderYourNose.
  ///
  /// In en, this message translates to:
  /// **'Right under your nose'**
  String get huntRightUnderYourNose;

  /// No description provided for @huntMetersAway.
  ///
  /// In en, this message translates to:
  /// **'{meters} m away'**
  String huntMetersAway(int meters);

  /// The distance is already formatted to one decimal place.
  ///
  /// In en, this message translates to:
  /// **'{km} km away'**
  String huntKilometersAway(String km);

  /// Appended to a distance when the GPS fix is loose. Keeps its leading space.
  ///
  /// In en, this message translates to:
  /// **' ±{meters} m'**
  String huntAccuracyNote(int meters);

  /// No description provided for @huntOpenCamera.
  ///
  /// In en, this message translates to:
  /// **'Open camera'**
  String get huntOpenCamera;

  /// No description provided for @huntGetCloser.
  ///
  /// In en, this message translates to:
  /// **'Get closer to unlock the camera'**
  String get huntGetCloser;

  /// No description provided for @huntBandFrozen.
  ///
  /// In en, this message translates to:
  /// **'Ice cold'**
  String get huntBandFrozen;

  /// No description provided for @huntBandCold.
  ///
  /// In en, this message translates to:
  /// **'Cold'**
  String get huntBandCold;

  /// No description provided for @huntBandWarm.
  ///
  /// In en, this message translates to:
  /// **'Getting warmer'**
  String get huntBandWarm;

  /// No description provided for @huntBandHot.
  ///
  /// In en, this message translates to:
  /// **'Hot!'**
  String get huntBandHot;

  /// No description provided for @huntBandBurning.
  ///
  /// In en, this message translates to:
  /// **'It\'s right here!'**
  String get huntBandBurning;

  /// No description provided for @huntHintFrozen.
  ///
  /// In en, this message translates to:
  /// **'Somewhere out there — follow the arrow'**
  String get huntHintFrozen;

  /// No description provided for @huntHintCold.
  ///
  /// In en, this message translates to:
  /// **'Keep exploring in that direction'**
  String get huntHintCold;

  /// No description provided for @huntHintWarm.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the right track'**
  String get huntHintWarm;

  /// No description provided for @huntHintHot.
  ///
  /// In en, this message translates to:
  /// **'So close now — a few more steps'**
  String get huntHintHot;

  /// No description provided for @huntHintBurning.
  ///
  /// In en, this message translates to:
  /// **'Open the camera to catch it'**
  String get huntHintBurning;

  /// No description provided for @arModeMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get arModeMedia;

  /// No description provided for @arModeScan.
  ///
  /// In en, this message translates to:
  /// **'3D Scan'**
  String get arModeScan;

  /// No description provided for @arNoCamera.
  ///
  /// In en, this message translates to:
  /// **'No camera on this device'**
  String get arNoCamera;

  /// No description provided for @arCameraNeedsPermission.
  ///
  /// In en, this message translates to:
  /// **'The camera needs permission before it can open.'**
  String get arCameraNeedsPermission;

  /// No description provided for @arCameraDidNotOpen.
  ///
  /// In en, this message translates to:
  /// **'The camera didn\'t open: {error}'**
  String arCameraDidNotOpen(String error);

  /// No description provided for @arCouldNotReadModel.
  ///
  /// In en, this message translates to:
  /// **'Could not read the mascot model.'**
  String get arCouldNotReadModel;

  /// No description provided for @arCouldNotPlaceFennec.
  ///
  /// In en, this message translates to:
  /// **'Could not place the fennec. Try again in a moment.'**
  String get arCouldNotPlaceFennec;

  /// No description provided for @arHuntNeedsCamera.
  ///
  /// In en, this message translates to:
  /// **'The hunt needs the camera to see the room around you.'**
  String get arHuntNeedsCamera;

  /// No description provided for @arPhotoNeedsCamera.
  ///
  /// In en, this message translates to:
  /// **'Taking a photo needs the camera.'**
  String get arPhotoNeedsCamera;

  /// No description provided for @arAllowCamera.
  ///
  /// In en, this message translates to:
  /// **'Allow camera'**
  String get arAllowCamera;

  /// No description provided for @arKeepThisClip.
  ///
  /// In en, this message translates to:
  /// **'Keep this clip?'**
  String get arKeepThisClip;

  /// No description provided for @arScanThis.
  ///
  /// In en, this message translates to:
  /// **'Scan this?'**
  String get arScanThis;

  /// No description provided for @arKeepThisPhoto.
  ///
  /// In en, this message translates to:
  /// **'Keep this photo?'**
  String get arKeepThisPhoto;

  /// No description provided for @arFindTheFennec.
  ///
  /// In en, this message translates to:
  /// **'Find the fennec'**
  String get arFindTheFennec;

  /// No description provided for @arScanAnObject.
  ///
  /// In en, this message translates to:
  /// **'Scan an object'**
  String get arScanAnObject;

  /// No description provided for @arPhotoOrVideo.
  ///
  /// In en, this message translates to:
  /// **'Photo or video'**
  String get arPhotoOrVideo;

  /// No description provided for @arClipLooping.
  ///
  /// In en, this message translates to:
  /// **'It\'s looping — watch it before you decide'**
  String get arClipLooping;

  /// No description provided for @arCheckObjectSharp.
  ///
  /// In en, this message translates to:
  /// **'Check the object is sharp and whole'**
  String get arCheckObjectSharp;

  /// No description provided for @arCheckItCameOut.
  ///
  /// In en, this message translates to:
  /// **'Check it came out how you wanted'**
  String get arCheckItCameOut;

  /// No description provided for @arSomewhereAroundYou.
  ///
  /// In en, this message translates to:
  /// **'Somewhere around you'**
  String get arSomewhereAroundYou;

  /// No description provided for @arComesBackAs3d.
  ///
  /// In en, this message translates to:
  /// **'It comes back as a 3D model'**
  String get arComesBackAs3d;

  /// No description provided for @arGoesToYourFolder.
  ///
  /// In en, this message translates to:
  /// **'It goes straight to your folder'**
  String get arGoesToYourFolder;

  /// No description provided for @arFillTheFrame.
  ///
  /// In en, this message translates to:
  /// **'Fill the frame with one object, then shoot'**
  String get arFillTheFrame;

  /// No description provided for @arTapToShootHoldToFilm.
  ///
  /// In en, this message translates to:
  /// **'Tap to shoot · hold to film'**
  String get arTapToShootHoldToFilm;

  /// No description provided for @arStageReadingRoom.
  ///
  /// In en, this message translates to:
  /// **'Reading the room'**
  String get arStageReadingRoom;

  /// No description provided for @arStageReadingRoomHint.
  ///
  /// In en, this message translates to:
  /// **'Hold the phone up and move it slowly'**
  String get arStageReadingRoomHint;

  /// No description provided for @arStageLettingOut.
  ///
  /// In en, this message translates to:
  /// **'Letting the fennec out'**
  String get arStageLettingOut;

  /// No description provided for @arStageLettingOutHint.
  ///
  /// In en, this message translates to:
  /// **'Hold steady for a second'**
  String get arStageLettingOutHint;

  /// No description provided for @arStageThereItIs.
  ///
  /// In en, this message translates to:
  /// **'There it is — tap it'**
  String get arStageThereItIs;

  /// No description provided for @arStageItIsOutThere.
  ///
  /// In en, this message translates to:
  /// **'It is out there — follow the arrow'**
  String get arStageItIsOutThere;

  /// No description provided for @arStageWalkAround.
  ///
  /// In en, this message translates to:
  /// **'Walk around it to see it from any side'**
  String get arStageWalkAround;

  /// No description provided for @arStageFoundIt.
  ///
  /// In en, this message translates to:
  /// **'Found it'**
  String get arStageFoundIt;

  /// No description provided for @arStageFrameTheShot.
  ///
  /// In en, this message translates to:
  /// **'Frame the shot and take your photo'**
  String get arStageFrameTheShot;

  /// The distance is already formatted to one decimal place.
  ///
  /// In en, this message translates to:
  /// **'{meters} m away'**
  String arDistanceAway(String meters);

  /// No description provided for @arFloorEstimated.
  ///
  /// In en, this message translates to:
  /// **'Floor estimated — it settles itself as the room is mapped'**
  String get arFloorEstimated;

  /// No description provided for @arQuestNeedsClip.
  ///
  /// In en, this message translates to:
  /// **'This one wants a clip — hold the shutter for {seconds} seconds or more'**
  String arQuestNeedsClip(int seconds);

  /// No description provided for @arClipTooShort.
  ///
  /// In en, this message translates to:
  /// **'That clip was {actual}s — this quest needs at least {required}. Hold for longer.'**
  String arClipTooShort(int actual, int required);

  /// No description provided for @arHoldToFilm.
  ///
  /// In en, this message translates to:
  /// **'Hold the shutter for a moment to film'**
  String get arHoldToFilm;

  /// No description provided for @arHoldToFilmMinimum.
  ///
  /// In en, this message translates to:
  /// **'Hold to film · {seconds}s minimum'**
  String arHoldToFilmMinimum(int seconds);

  /// No description provided for @arClipCapped.
  ///
  /// In en, this message translates to:
  /// **'Clip capped at {seconds}s'**
  String arClipCapped(int seconds);

  /// No description provided for @arKeepClip.
  ///
  /// In en, this message translates to:
  /// **'Keep {seconds}s clip'**
  String arKeepClip(int seconds);

  /// No description provided for @arScanIt.
  ///
  /// In en, this message translates to:
  /// **'Scan it'**
  String get arScanIt;

  /// No description provided for @arUsePhoto.
  ///
  /// In en, this message translates to:
  /// **'Use photo'**
  String get arUsePhoto;

  /// No description provided for @arSecondsLeft.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s left'**
  String arSecondsLeft(int seconds);

  /// No description provided for @arTapToTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to take the photo'**
  String get arTapToTakePhoto;

  /// No description provided for @arClipWontPlayBack.
  ///
  /// In en, this message translates to:
  /// **'That clip won\'t play back. Discard it and film again.'**
  String get arClipWontPlayBack;

  /// No description provided for @arCouldNotTakeShot.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t take that shot: {error}'**
  String arCouldNotTakeShot(String error);

  /// No description provided for @arCouldNotStartFilming.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start filming: {error}'**
  String arCouldNotStartFilming(String error);

  /// No description provided for @arClipDidNotSave.
  ///
  /// In en, this message translates to:
  /// **'The clip didn\'t save: {error}'**
  String arClipDidNotSave(String error);

  /// No description provided for @arCouldNotSaveClip.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that clip: {error}'**
  String arCouldNotSaveClip(String error);

  /// No description provided for @arCouldNotSaveShot.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that shot: {error}'**
  String arCouldNotSaveShot(String error);

  /// No description provided for @arCouldNotScanShot.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t scan that shot: {error}'**
  String arCouldNotScanShot(String error);

  /// No description provided for @arClipSaved.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s clip saved to your folder'**
  String arClipSaved(int seconds);

  /// No description provided for @arFennecCaught.
  ///
  /// In en, this message translates to:
  /// **'Fennec caught!'**
  String get arFennecCaught;

  /// No description provided for @arPhotoSaved.
  ///
  /// In en, this message translates to:
  /// **'Photo saved to your folder'**
  String get arPhotoSaved;

  /// No description provided for @arNoClearObject.
  ///
  /// In en, this message translates to:
  /// **'No clear object in that shot — nothing scanned. Try filling more of the frame with the subject.'**
  String get arNoClearObject;

  /// No description provided for @arGenerating3dModel.
  ///
  /// In en, this message translates to:
  /// **'Generating 3D model — check your folder in a moment'**
  String get arGenerating3dModel;

  /// No description provided for @folderYourFolder.
  ///
  /// In en, this message translates to:
  /// **'YOUR FOLDER'**
  String get folderYourFolder;

  /// No description provided for @folderTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved & Scanned'**
  String get folderTitle;

  /// No description provided for @folderSearchScans.
  ///
  /// In en, this message translates to:
  /// **'Search your scans'**
  String get folderSearchScans;

  /// No description provided for @folderSearchSaved.
  ///
  /// In en, this message translates to:
  /// **'Search saved locations'**
  String get folderSearchSaved;

  /// No description provided for @folderNoScans.
  ///
  /// In en, this message translates to:
  /// **'No scans yet'**
  String get folderNoScans;

  /// No description provided for @folderNoScansBody.
  ///
  /// In en, this message translates to:
  /// **'Complete scan and video tasks on your route to fill this folder.'**
  String get folderNoScansBody;

  /// No description provided for @folderNoSavedLocations.
  ///
  /// In en, this message translates to:
  /// **'No saved locations'**
  String get folderNoSavedLocations;

  /// No description provided for @artifactGenerating3d.
  ///
  /// In en, this message translates to:
  /// **'Generating 3D…'**
  String get artifactGenerating3d;

  /// No description provided for @artifact3dFailed.
  ///
  /// In en, this message translates to:
  /// **'3D Failed'**
  String get artifact3dFailed;

  /// No description provided for @artifact3dModel.
  ///
  /// In en, this message translates to:
  /// **'3D Model'**
  String get artifact3dModel;

  /// No description provided for @artifactPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get artifactPhoto;

  /// No description provided for @artifactVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get artifactVideo;

  /// No description provided for @artifactYourCapture.
  ///
  /// In en, this message translates to:
  /// **'Your capture'**
  String get artifactYourCapture;

  /// No description provided for @artifactGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get artifactGenerationFailed;

  /// No description provided for @modelFailNoSubject.
  ///
  /// In en, this message translates to:
  /// **'No clear object found — try a different angle'**
  String get modelFailNoSubject;

  /// No description provided for @modelFailTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out — tap to retry'**
  String get modelFailTimeout;

  /// No description provided for @modelFailGpuOom.
  ///
  /// In en, this message translates to:
  /// **'Server busy — tap to retry'**
  String get modelFailGpuOom;

  /// No description provided for @modelFailInternal.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong — tap to retry'**
  String get modelFailInternal;

  /// No description provided for @viewerCouldNotLoadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not load 3D model file'**
  String get viewerCouldNotLoadFile;

  /// No description provided for @viewerLoadingModel.
  ///
  /// In en, this message translates to:
  /// **'Loading 3D model…'**
  String get viewerLoadingModel;

  /// No description provided for @viewerCouldNotDisplay.
  ///
  /// In en, this message translates to:
  /// **'Could not display 3D model'**
  String get viewerCouldNotDisplay;

  /// No description provided for @viewerCouldNotDisplayError.
  ///
  /// In en, this message translates to:
  /// **'Could not display 3D model — {error}'**
  String viewerCouldNotDisplayError(String error);

  /// No description provided for @viewerHintInteractive3d.
  ///
  /// In en, this message translates to:
  /// **'Interactive 3D model — touch to rotate'**
  String get viewerHintInteractive3d;

  /// No description provided for @viewerHintVideo.
  ///
  /// In en, this message translates to:
  /// **'Tap the video to play or pause'**
  String get viewerHintVideo;

  /// No description provided for @viewerHintPinchZoom.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom · drag to pan'**
  String get viewerHintPinchZoom;

  /// No description provided for @viewerHintDragRotate.
  ///
  /// In en, this message translates to:
  /// **'Drag to rotate · pinch to zoom'**
  String get viewerHintDragRotate;

  /// No description provided for @viewerClipUnplayable.
  ///
  /// In en, this message translates to:
  /// **'This clip can\'t be played — the file may have been removed.'**
  String get viewerClipUnplayable;

  /// No description provided for @viewerPhotoUnloadable.
  ///
  /// In en, this message translates to:
  /// **'This photo couldn\'t be loaded.'**
  String get viewerPhotoUnloadable;

  /// No description provided for @rewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get rewardsTitle;

  /// No description provided for @rewardsOnlyOnRoute.
  ///
  /// In en, this message translates to:
  /// **'Available once you are walking a route.'**
  String get rewardsOnlyOnRoute;

  /// No description provided for @rewardsNothingToSpendOn.
  ///
  /// In en, this message translates to:
  /// **'Nothing to spend on right now'**
  String get rewardsNothingToSpendOn;

  /// No description provided for @rewardsPullDownToRetry.
  ///
  /// In en, this message translates to:
  /// **'Pull down to check again once you have a connection.'**
  String get rewardsPullDownToRetry;

  /// No description provided for @rewardsVoucherGranted.
  ///
  /// In en, this message translates to:
  /// **'Voucher {code} is in your rewards. Show it to collect.'**
  String rewardsVoucherGranted(String code);

  /// No description provided for @rewardsCreditsGranted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{One scan credit added. It does not expire.} other{{count} scan credits added. They do not expire.}}'**
  String rewardsCreditsGranted(int count);

  /// No description provided for @rewardsRerollsGranted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{One more quest swap on this tour.} other{{count} more quest swaps on this tour.}}'**
  String rewardsRerollsGranted(int count);

  /// No description provided for @rewardsGranted.
  ///
  /// In en, this message translates to:
  /// **'{title} is yours.'**
  String rewardsGranted(String title);

  /// No description provided for @balanceToSpend.
  ///
  /// In en, this message translates to:
  /// **'TO SPEND'**
  String get balanceToSpend;

  /// No description provided for @balanceSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get balanceSyncing;

  /// No description provided for @balancePoints.
  ///
  /// In en, this message translates to:
  /// **'{count} points'**
  String balancePoints(int count);

  /// No description provided for @rewardKindDigital.
  ///
  /// In en, this message translates to:
  /// **'For the app'**
  String get rewardKindDigital;

  /// No description provided for @rewardKindPartner.
  ///
  /// In en, this message translates to:
  /// **'Along the way'**
  String get rewardKindPartner;

  /// No description provided for @rewardKindPhysical.
  ///
  /// In en, this message translates to:
  /// **'Things to keep'**
  String get rewardKindPhysical;

  /// No description provided for @rewardKindDigitalBlurb.
  ///
  /// In en, this message translates to:
  /// **'Spend points on what Massar itself can do.'**
  String get rewardKindDigitalBlurb;

  /// No description provided for @rewardKindPartnerBlurb.
  ///
  /// In en, this message translates to:
  /// **'Redeemed at a place on one of your routes.'**
  String get rewardKindPartnerBlurb;

  /// No description provided for @rewardKindPhysicalBlurb.
  ///
  /// In en, this message translates to:
  /// **'Collected in person. Needs an account.'**
  String get rewardKindPhysicalBlurb;

  /// No description provided for @rewardOwned.
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get rewardOwned;

  /// No description provided for @rewardSoldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold out'**
  String get rewardSoldOut;

  /// No description provided for @rewardStockLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String rewardStockLeft(int count);

  /// No description provided for @rewardPointsUnit.
  ///
  /// In en, this message translates to:
  /// **'points'**
  String get rewardPointsUnit;

  /// No description provided for @rewardFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Reward'**
  String get rewardFallbackTitle;

  /// No description provided for @redeemCosts.
  ///
  /// In en, this message translates to:
  /// **'Costs'**
  String get redeemCosts;

  /// No description provided for @redeemYouAreShort.
  ///
  /// In en, this message translates to:
  /// **'You are short'**
  String get redeemYouAreShort;

  /// No description provided for @redeemLeftAfterwards.
  ///
  /// In en, this message translates to:
  /// **'Left afterwards'**
  String get redeemLeftAfterwards;

  /// No description provided for @redeemNoteInstant.
  ///
  /// In en, this message translates to:
  /// **'Bought once and kept. There is no way to sell it back.'**
  String get redeemNoteInstant;

  /// No description provided for @redeemNoteVoucher.
  ///
  /// In en, this message translates to:
  /// **'A code to show in person. It lasts 14 days, then the points come back to you.'**
  String get redeemNoteVoucher;

  /// No description provided for @redeemNoteManual.
  ///
  /// In en, this message translates to:
  /// **'Needs an account — this is something we hand you.'**
  String get redeemNoteManual;

  /// No description provided for @redeemNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get redeemNotYet;

  /// No description provided for @redeemNotEnoughPoints.
  ///
  /// In en, this message translates to:
  /// **'Not enough points'**
  String get redeemNotEnoughPoints;

  /// No description provided for @redeemConfirm.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get redeemConfirm;

  /// No description provided for @redeemFailSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in first so this stays with you.'**
  String get redeemFailSignIn;

  /// No description provided for @redeemFailOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Redeeming needs a connection so your balance stays right.'**
  String get redeemFailOffline;

  /// No description provided for @redeemFailNotEnough.
  ///
  /// In en, this message translates to:
  /// **'Not enough points yet — finish another task or two.'**
  String get redeemFailNotEnough;

  /// No description provided for @redeemFailUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This one is no longer available.'**
  String get redeemFailUnavailable;

  /// No description provided for @redeemFailOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'The last one just went. More are on the way.'**
  String get redeemFailOutOfStock;

  /// No description provided for @redeemFailAlreadyOwned.
  ///
  /// In en, this message translates to:
  /// **'You already have this one.'**
  String get redeemFailAlreadyOwned;

  /// No description provided for @redeemFailNeedsAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account to claim something we have to hand you in person.'**
  String get redeemFailNeedsAccount;

  /// No description provided for @redeemFailRateLimited.
  ///
  /// In en, this message translates to:
  /// **'That is a lot of redeeming at once. Try again in a few minutes.'**
  String get redeemFailRateLimited;

  /// No description provided for @redeemFailGeneric.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t go through. Your points are untouched — try again.'**
  String get redeemFailGeneric;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionTour.
  ///
  /// In en, this message translates to:
  /// **'TOUR'**
  String get settingsSectionTour;

  /// No description provided for @settingsLeaveTour.
  ///
  /// In en, this message translates to:
  /// **'Leave Current Tour'**
  String get settingsLeaveTour;

  /// No description provided for @settingsSectionArHunt.
  ///
  /// In en, this message translates to:
  /// **'AR HUNT'**
  String get settingsSectionArHunt;

  /// No description provided for @settingsTestingMode.
  ///
  /// In en, this message translates to:
  /// **'Testing mode'**
  String get settingsTestingMode;

  /// No description provided for @settingsTestingModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Spawn the mascot near your current location'**
  String get settingsTestingModeSubtitle;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get settingsSectionAccount;

  /// No description provided for @settingsSectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get settingsSectionNotifications;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow device'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageSystemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use whatever language your phone is set to'**
  String get settingsLanguageSystemSubtitle;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get settingsSectionAbout;

  /// No description provided for @settingsReplayIntro.
  ///
  /// In en, this message translates to:
  /// **'Replay intro'**
  String get settingsReplayIntro;

  /// No description provided for @settingsReplayIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The tour of what Massar does'**
  String get settingsReplayIntroSubtitle;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Massar v{version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsTotalPoints.
  ///
  /// In en, this message translates to:
  /// **'Total points'**
  String get settingsTotalPoints;

  /// No description provided for @settingsSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get settingsSyncing;

  /// No description provided for @settingsEarnedAcrossTours.
  ///
  /// In en, this message translates to:
  /// **'Earned across every tour'**
  String get settingsEarnedAcrossTours;

  /// No description provided for @settingsSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get settingsSignedIn;

  /// No description provided for @settingsCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get settingsCreateAccount;

  /// No description provided for @settingsAccountFollows.
  ///
  /// In en, this message translates to:
  /// **'Your points and souvenirs follow this account'**
  String get settingsAccountFollows;

  /// No description provided for @settingsGuestOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Guest — your progress lives only on this device'**
  String get settingsGuestOnDevice;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsOn.
  ///
  /// In en, this message translates to:
  /// **'Routes, 3D models, and nearby fennecs'**
  String get settingsNotificationsOn;

  /// No description provided for @settingsNotificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Off — you will not be told when anything is ready'**
  String get settingsNotificationsOff;

  /// No description provided for @settingsRouteReady.
  ///
  /// In en, this message translates to:
  /// **'Route ready'**
  String get settingsRouteReady;

  /// No description provided for @settingsRouteReadySubtitle.
  ///
  /// In en, this message translates to:
  /// **'When a route you asked for has finished generating'**
  String get settingsRouteReadySubtitle;

  /// No description provided for @settings3dCaptures.
  ///
  /// In en, this message translates to:
  /// **'3D captures'**
  String get settings3dCaptures;

  /// No description provided for @settings3dCapturesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When a model you photographed is ready, or failed'**
  String get settings3dCapturesSubtitle;

  /// No description provided for @settingsFennecNearby.
  ///
  /// In en, this message translates to:
  /// **'Fennec nearby'**
  String get settingsFennecNearby;

  /// No description provided for @settingsFennecNearbySubtitle.
  ///
  /// In en, this message translates to:
  /// **'While a hunt is on, when you get close to one'**
  String get settingsFennecNearbySubtitle;

  /// No description provided for @settingsPushNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Push is not configured, so these arrive only while the app is open or in the background.'**
  String get settingsPushNotConfigured;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// No description provided for @authCreateYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateYourAccount;

  /// No description provided for @authLogIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLogIn;

  /// No description provided for @authSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get authEmailHint;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authPasswordHintSignup.
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters'**
  String get authPasswordHintSignup;

  /// No description provided for @authPasswordHintLogin.
  ///
  /// In en, this message translates to:
  /// **'••••••••'**
  String get authPasswordHintLogin;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authCreateAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccountButton;

  /// No description provided for @authContinueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as guest'**
  String get authContinueAsGuest;

  /// No description provided for @authGuestKeepsProgress.
  ///
  /// In en, this message translates to:
  /// **'Everything you have already collected stays yours — signing up saves it to your account.'**
  String get authGuestKeepsProgress;

  /// No description provided for @authCanSignUpLater.
  ///
  /// In en, this message translates to:
  /// **'You can create an account later from Settings.'**
  String get authCanSignUpLater;

  /// No description provided for @authResetYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authResetYourPassword;

  /// No description provided for @authResetEmailBlurb.
  ///
  /// In en, this message translates to:
  /// **'We will email you a link to set a new one.'**
  String get authResetEmailBlurb;

  /// No description provided for @authSendLink.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get authSendLink;

  /// No description provided for @authEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address.'**
  String get authEnterEmail;

  /// No description provided for @authInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'That does not look like a valid email address.'**
  String get authInvalidEmail;

  /// No description provided for @authEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get authEnterPassword;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 characters.'**
  String get authPasswordTooShort;

  /// No description provided for @authUseDifferentEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get authUseDifferentEmail;

  /// No description provided for @authCheckYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get authCheckYourEmail;

  /// Followed immediately by the email address in bold, so it keeps its trailing newline.
  ///
  /// In en, this message translates to:
  /// **'We sent a {length}-digit code to\n'**
  String authCodeSentTo(int length);

  /// No description provided for @authConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get authConfirm;

  /// No description provided for @authResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {seconds}s'**
  String authResendIn(int seconds);

  /// No description provided for @authSendNewCode.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get authSendNewCode;

  /// No description provided for @authCodeExpiryNote.
  ///
  /// In en, this message translates to:
  /// **'The code expires after an hour. Check your spam folder if it has not arrived.'**
  String get authCodeExpiryNote;

  /// No description provided for @authChooseNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get authChooseNewPassword;

  /// No description provided for @authNewPasswordBlurb.
  ///
  /// In en, this message translates to:
  /// **'This replaces the old one everywhere. You will stay signed in on this device.'**
  String get authNewPasswordBlurb;

  /// No description provided for @authNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPassword;

  /// No description provided for @authConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPassword;

  /// No description provided for @authTypeItAgain.
  ///
  /// In en, this message translates to:
  /// **'Type it again'**
  String get authTypeItAgain;

  /// No description provided for @authEnterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a new password.'**
  String get authEnterNewPassword;

  /// No description provided for @authPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'These do not match.'**
  String get authPasswordsDoNotMatch;

  /// No description provided for @authSavePassword.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get authSavePassword;

  /// No description provided for @authAccountCreatedWithProgress.
  ///
  /// In en, this message translates to:
  /// **'Account created. Everything you have collected is now saved to it.'**
  String get authAccountCreatedWithProgress;

  /// No description provided for @authAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created.'**
  String get authAccountCreated;

  /// No description provided for @authCodeAcceptedChoosePassword.
  ///
  /// In en, this message translates to:
  /// **'Code accepted. Choose a new password.'**
  String get authCodeAcceptedChoosePassword;

  /// No description provided for @authEmailConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Email confirmed. Your account is ready.'**
  String get authEmailConfirmed;

  /// No description provided for @authNewCodeSent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way to {email}.'**
  String authNewCodeSent(String email);

  /// No description provided for @authWelcomeBackNotice.
  ///
  /// In en, this message translates to:
  /// **'Welcome back.'**
  String get authWelcomeBackNotice;

  /// No description provided for @authPasswordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated. You are signed in.'**
  String get authPasswordUpdated;

  /// No description provided for @authErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and try again.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorEmailNotSending.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send your code — email is not going out right now. This is on our side; try again in a few minutes.'**
  String get authErrorEmailNotSending;

  /// No description provided for @authErrorBadCredentials.
  ///
  /// In en, this message translates to:
  /// **'That email and password do not match an account.'**
  String get authErrorBadCredentials;

  /// No description provided for @authErrorAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'That email already has an account. Try logging in instead.'**
  String get authErrorAlreadyRegistered;

  /// No description provided for @authErrorPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Passwords need to be at least 6 characters.'**
  String get authErrorPasswordTooShort;

  /// No description provided for @authErrorTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a minute and try again.'**
  String get authErrorTooManyAttempts;

  /// No description provided for @authErrorCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Ask for a new one.'**
  String get authErrorCodeExpired;

  /// No description provided for @authErrorCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code isn\'t right. Check the email and try again.'**
  String get authErrorCodeInvalid;

  /// No description provided for @authErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get authErrorGeneric;

  /// No description provided for @authAnonymousSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Anonymous sign-in failed'**
  String get authAnonymousSignInFailed;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingIllustration.
  ///
  /// In en, this message translates to:
  /// **'Illustration'**
  String get onboardingIllustration;

  /// No description provided for @onboardingPageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {index} of {count}'**
  String onboardingPageOf(int index, int count);

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'This is Massar'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Plan where you go, find something to do when you get there, and take a piece of it home.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'A route built around you'**
  String get onboardingRoutesTitle;

  /// No description provided for @onboardingRoutesBody.
  ///
  /// In en, this message translates to:
  /// **'Pick a city, say what you are in the mood for, and get a plan that fits your day — with a small task waiting at every stop.'**
  String get onboardingRoutesBody;

  /// No description provided for @onboardingCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Catch fennecs, keep souvenirs'**
  String get onboardingCaptureTitle;

  /// No description provided for @onboardingCaptureBody.
  ///
  /// In en, this message translates to:
  /// **'Raise your camera to find the fennecs hiding at your stops — and to scan real objects into 3D souvenirs for your folder.'**
  String get onboardingCaptureBody;

  /// No description provided for @onboardingRewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn your points into something real'**
  String get onboardingRewardsTitle;

  /// No description provided for @onboardingRewardsBody.
  ///
  /// In en, this message translates to:
  /// **'Spend what you earn on rewards from the places along the way.'**
  String get onboardingRewardsBody;

  /// No description provided for @detailAskTheAi.
  ///
  /// In en, this message translates to:
  /// **'ASK THE AI'**
  String get detailAskTheAi;

  /// No description provided for @detailBestTimeToVisit.
  ///
  /// In en, this message translates to:
  /// **'Best time to visit?'**
  String get detailBestTimeToVisit;

  /// No description provided for @detailHowLongToExplore.
  ///
  /// In en, this message translates to:
  /// **'How long to explore?'**
  String get detailHowLongToExplore;

  /// No description provided for @detailAskAnything.
  ///
  /// In en, this message translates to:
  /// **'Ask anything about this spot...'**
  String get detailAskAnything;

  /// No description provided for @detailSkipThisSpot.
  ///
  /// In en, this message translates to:
  /// **'Skip this spot'**
  String get detailSkipThisSpot;

  /// No description provided for @detailAddToRoute.
  ///
  /// In en, this message translates to:
  /// **'Add to route'**
  String get detailAddToRoute;

  /// No description provided for @detailGuideUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Sorry, I couldn\'t reach the guide right now — try again.'**
  String get detailGuideUnreachable;

  /// No description provided for @offlineBackOnline.
  ///
  /// In en, this message translates to:
  /// **'Back online — syncing…'**
  String get offlineBackOnline;

  /// No description provided for @offlinePendingSync.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Offline — {count} item will sync when online} other{Offline — {count} items will sync when online}}'**
  String offlinePendingSync(int count);

  /// No description provided for @offlineProgressSaved.
  ///
  /// In en, this message translates to:
  /// **'Offline — your progress is saved'**
  String get offlineProgressSaved;

  /// No description provided for @backendConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected to the server'**
  String get backendConnected;

  /// No description provided for @backendUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server — showing demo data'**
  String get backendUnreachable;

  /// No description provided for @routeErrorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the route service.'**
  String get routeErrorUnreachable;

  /// No description provided for @routeErrorCityNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This city isn\'t open for routes yet.'**
  String get routeErrorCityNotAvailable;

  /// No description provided for @routeErrorNoEligiblePois.
  ///
  /// In en, this message translates to:
  /// **'No published stops match that theme here yet.'**
  String get routeErrorNoEligiblePois;

  /// No description provided for @routeErrorTimeBudgetTooShort.
  ///
  /// In en, this message translates to:
  /// **'That time budget is too short for any stop here.'**
  String get routeErrorTimeBudgetTooShort;

  /// No description provided for @routeErrorProviderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The routing service is unavailable right now.'**
  String get routeErrorProviderUnavailable;

  /// No description provided for @routeErrorNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Route generation is not built yet on this server.'**
  String get routeErrorNotImplemented;

  /// No description provided for @routeErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong generating your route.'**
  String get routeErrorGeneric;

  /// No description provided for @routeErrorDropStopsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t drop those stops — showing the route as generated.'**
  String get routeErrorDropStopsFailed;

  /// No description provided for @routeErrorBelowBudget.
  ///
  /// In en, this message translates to:
  /// **'Removing that would leave less than the time you asked for.'**
  String get routeErrorBelowBudget;

  /// No description provided for @routeErrorRemoveStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove that stop — try again.'**
  String get routeErrorRemoveStopFailed;

  /// No description provided for @notifChannelRoutesName.
  ///
  /// In en, this message translates to:
  /// **'Routes and models'**
  String get notifChannelRoutesName;

  /// No description provided for @notifChannelRoutesDescription.
  ///
  /// In en, this message translates to:
  /// **'When a route is ready, or a 3D capture has finished.'**
  String get notifChannelRoutesDescription;

  /// No description provided for @notifChannelHuntName.
  ///
  /// In en, this message translates to:
  /// **'Fennec hunt'**
  String get notifChannelHuntName;

  /// No description provided for @notifChannelHuntDescription.
  ///
  /// In en, this message translates to:
  /// **'When you are getting close to a hidden fennec.'**
  String get notifChannelHuntDescription;

  /// No description provided for @notifRouteReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your route is ready'**
  String get notifRouteReadyTitle;

  /// No description provided for @notifRouteReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap to see where you are going.'**
  String get notifRouteReadyBody;

  /// No description provided for @notifRouteReadyBodyNamed.
  ///
  /// In en, this message translates to:
  /// **'{title} is planned and waiting for you.'**
  String notifRouteReadyBodyNamed(String title);

  /// No description provided for @notifModelReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your 3D model is ready'**
  String get notifModelReadyTitle;

  /// No description provided for @notifModelFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'That capture didn\'t work out'**
  String get notifModelFailedTitle;

  /// No description provided for @notifModelReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap to see it in your folder.'**
  String get notifModelReadyBody;

  /// No description provided for @notifModelFailNoSubject.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a clear object — try filling more of the frame with it.'**
  String get notifModelFailNoSubject;

  /// No description provided for @notifModelFailTimeout.
  ///
  /// In en, this message translates to:
  /// **'It took too long to build. Tap to try that photo again.'**
  String get notifModelFailTimeout;

  /// No description provided for @notifModelFailQuota.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used all your model credits for today.'**
  String get notifModelFailQuota;

  /// No description provided for @notifModelFailGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong building it. Tap to try again.'**
  String get notifModelFailGeneric;

  /// No description provided for @notifMascotHereTitle.
  ///
  /// In en, this message translates to:
  /// **'A fennec is right here!'**
  String get notifMascotHereTitle;

  /// No description provided for @notifMascotWarmTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re getting warm'**
  String get notifMascotWarmTitle;

  /// No description provided for @notifMascotHereBody.
  ///
  /// In en, this message translates to:
  /// **'Tap to open the camera and catch it.'**
  String get notifMascotHereBody;

  /// No description provided for @notifMascotNearbyBody.
  ///
  /// In en, this message translates to:
  /// **'A fennec is hiding somewhere close by.'**
  String get notifMascotNearbyBody;

  /// No description provided for @notifMascotNearbyBodyNamed.
  ///
  /// In en, this message translates to:
  /// **'A fennec is hiding near {stopName}.'**
  String notifMascotNearbyBodyNamed(String stopName);

  /// No description provided for @settingsSplatReady.
  ///
  /// In en, this message translates to:
  /// **'3D scenes from your footage'**
  String get settingsSplatReady;

  /// No description provided for @settingsSplatReadySubtitle.
  ///
  /// In en, this message translates to:
  /// **'When a clip you recorded is turned into a scene you can walk around'**
  String get settingsSplatReadySubtitle;

  /// No description provided for @notifInboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifInboxTitle;

  /// No description provided for @notifInboxUnread.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Notifications, 1 unread} other{Notifications, {count} unread}}'**
  String notifInboxUnread(int count);

  /// No description provided for @notifInboxEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get notifInboxEmptyTitle;

  /// No description provided for @notifInboxEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'When a route is planned, a capture becomes a 3D model, or your footage helps build a scene, it will show up here.'**
  String get notifInboxEmptyBody;

  /// No description provided for @notifInboxClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get notifInboxClearAll;

  /// No description provided for @notifInboxClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all notifications?'**
  String get notifInboxClearTitle;

  /// No description provided for @notifInboxClearBody.
  ///
  /// In en, this message translates to:
  /// **'They will be deleted for good. Anything they point to — a route, a model, a scene — stays where it is.'**
  String get notifInboxClearBody;

  /// No description provided for @notifInboxClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get notifInboxClearConfirm;

  /// No description provided for @notifInboxDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get notifInboxDelete;

  /// No description provided for @notifInboxDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete that right now. Try again once you\'re back online.'**
  String get notifInboxDeleteFailed;

  /// No description provided for @notifInboxNothingToOpen.
  ///
  /// In en, this message translates to:
  /// **'There\'s nothing left to open for this one.'**
  String get notifInboxNothingToOpen;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 min ago} other{{count} min ago}}'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{yesterday} other{{count} days ago}}'**
  String timeDaysAgo(int count);

  /// No description provided for @splatViewerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Built from your footage'**
  String get splatViewerSubtitle;

  /// No description provided for @splatViewerHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to look around · pinch to zoom · double-tap to reset'**
  String get splatViewerHint;

  /// No description provided for @splatViewerOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening the scene…'**
  String get splatViewerOpening;

  /// No description provided for @splatViewerDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading the scene…'**
  String get splatViewerDownloading;

  /// No description provided for @splatViewerFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the scene'**
  String get splatViewerFailed;

  /// No description provided for @splatViewerCounts.
  ///
  /// In en, this message translates to:
  /// **'{shown} of {trained} gaussians'**
  String splatViewerCounts(int shown, int trained);

  /// No description provided for @splatDetailLow.
  ///
  /// In en, this message translates to:
  /// **'Smooth'**
  String get splatDetailLow;

  /// No description provided for @splatDetailMedium.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get splatDetailMedium;

  /// No description provided for @splatDetailHigh.
  ///
  /// In en, this message translates to:
  /// **'Detailed'**
  String get splatDetailHigh;

  /// No description provided for @splatDetailSemantic.
  ///
  /// In en, this message translates to:
  /// **'Detail: {level}'**
  String splatDetailSemantic(String level);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
