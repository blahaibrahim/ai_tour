// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مسار';

  @override
  String get actionCancel => 'إلغاء';

  @override
  String get actionDone => 'تم';

  @override
  String get actionSkip => 'تخطّي';

  @override
  String get actionNext => 'التالي';

  @override
  String get actionClose => 'إغلاق';

  @override
  String get actionDismiss => 'تجاهل';

  @override
  String get actionTryAgain => 'أعد المحاولة';

  @override
  String get actionAllow => 'السماح';

  @override
  String get actionSettings => 'الإعدادات';

  @override
  String get actionRetake => 'إعادة الالتقاط';

  @override
  String get actionDiscard => 'حذف';

  @override
  String get actionBack => 'رجوع';

  @override
  String get navMap => 'الخريطة';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navFolder => 'المجلّد';

  @override
  String durationMinutes(int minutes) {
    return '$minutes د';
  }

  @override
  String durationHours(int hours) {
    return '$hours س';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours س $minutes د';
  }

  @override
  String get homePointsSyncing => 'جارٍ مزامنة رصيد النقاط';

  @override
  String homePointsToSpend(int count) {
    return '$count نقطة للإنفاق';
  }

  @override
  String get homeGreeting => 'إلى أين بعد؟';

  @override
  String get homeYourRoutes => 'مساراتك';

  @override
  String get homeRoutesEmpty =>
      'المسارات التي تنشئها ستتجمّع هنا، جاهزة لاستئنافها.';

  @override
  String get homePlanNewRoute => 'خطّط لمسار جديد';

  @override
  String get homePlanNewRouteSubtitle => 'اختر مدينة وموضوعًا والوقت المتاح لك';

  @override
  String get relativeToday => 'اليوم';

  @override
  String get relativeYesterday => 'أمس';

  @override
  String relativeDays(int days) {
    return '$days يوم';
  }

  @override
  String relativeWeeks(int weeks) {
    return '$weeks أسبوع';
  }

  @override
  String relativeYears(int years) {
    return '$years سنة';
  }

  @override
  String get mapGenerateRoute => 'أنشئ مساري';

  @override
  String mapTripDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
      zero: '$count يوم',
    );
    return '$_temp0';
  }

  @override
  String get mapExpandTripOptions => 'إظهار خيارات الرحلة أو إخفاؤها';

  @override
  String get mapHideTripOptions => 'إخفاء خيارات الرحلة';

  @override
  String get mapTapToPickWilaya => 'انقر على الخريطة لاختيار ولاية';

  @override
  String get mapTapAnotherToSwitch => 'انقر على ولاية أخرى للتبديل';

  @override
  String get mapPromptHeading => 'أخبر الذكاء الاصطناعي بما تبحث عنه';

  @override
  String get mapPromptHint => 'آثار رومانية هادئة، إطلالات ساحلية...';

  @override
  String get mapTapPinForDetails => 'انقر على علامة لعرض التفاصيل';

  @override
  String get mapNoRouteYet => 'لم يتم إنشاء أي مسار بعد.';

  @override
  String get timeBudgetHeading => 'كم من الوقت لديك؟';

  @override
  String timeBudgetDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'يوم',
      many: 'يومًا',
      few: 'أيام',
      two: 'يومان',
      one: 'يوم',
      zero: 'يوم',
    );
    return '$_temp0';
  }

  @override
  String timeBudgetHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ساعة',
      many: 'ساعة',
      few: 'ساعات',
      two: 'ساعتان',
      one: 'ساعة',
      zero: 'ساعة',
    );
    return '$_temp0';
  }

  @override
  String get timeBudgetTripLength => 'مدة الرحلة بالأيام';

  @override
  String get timeBudgetHoursPerDay => 'ساعات التجوّل في اليوم';

  @override
  String get timeBudgetWholeTrip => 'للرحلة كاملة';

  @override
  String get timeBudgetEachDay => 'في كل يوم منها';

  @override
  String get searchWilayaHint => 'ابحث عن ولاية...';

  @override
  String get searchMyLocation => 'موقعي';

  @override
  String get searchNoWilayas => 'لم يتم العثور على أي ولاية.';

  @override
  String get locationServicesDisabled => 'خدمات الموقع معطّلة.';

  @override
  String get locationPermissionDenied => 'تم رفض إذن الموقع.';

  @override
  String get locationPermissionPermanentlyDenied =>
      'تم رفض إذن الموقع نهائيًا.';

  @override
  String get locationLocating => 'جارٍ تحديد الموقع...';

  @override
  String get locationRestartRequired =>
      'يرجى إيقاف التطبيق تمامًا ثم تشغيله من جديد.';

  @override
  String genericError(String message) {
    return 'خطأ: $message';
  }

  @override
  String get thinkingAlmostThere => 'أوشكنا على الانتهاء...';

  @override
  String get thinkingStepBudget => 'قراءة الوقت المتاح لديك…';

  @override
  String get thinkingStepStops => 'اختيار المحطات المنشورة المناسبة لموضوعك…';

  @override
  String get thinkingStepClusters =>
      'تجميعها في مجموعات يمكن التنقّل بينها سيرًا…';

  @override
  String get thinkingStepDrive => 'ترتيب التنقّل بالسيارة بين المجموعات…';

  @override
  String get thinkingStepWalk => 'ترتيب المسير داخل كل مجموعة…';

  @override
  String get thinkingStepFit => 'التأكّد من أن كل شيء يناسب يومك…';

  @override
  String get thinkingNotifyMe => 'أعلمني';

  @override
  String get thinkingWillLetYouKnow => 'سنعلمك حين يصبح جاهزًا';

  @override
  String get thinkingTurnOnNotifications =>
      'فعّل الإشعارات لتعرف\nمتى يصبح جاهزًا';

  @override
  String get notifyEnabled => 'سنعلمك فور أن يصبح جاهزًا.';

  @override
  String get notifyLocalOnly =>
      'الإشعارات تعمل ما دام التطبيق مفتوحًا في الخلفية.';

  @override
  String get notifyLocalOnlySettings =>
      'مفعّلة، لكن فقط أثناء تشغيل التطبيق — الإشعارات الفورية غير مهيّأة في هذه النسخة.';

  @override
  String get notifyDenied =>
      'الإشعارات معطّلة لهذا التطبيق — فعّلها من الإعدادات.';

  @override
  String get notifyDeniedSettings =>
      'الإشعارات معطّلة لهذا التطبيق في إعدادات هاتفك.';

  @override
  String get notifyOffline =>
      'تعذّر الحفظ الآن. أعد المحاولة عند عودة الاتصال.';

  @override
  String swipeKeepTheRest(int reviewed, int total) {
    return 'الاحتفاظ بالبقية ($reviewed/$total)';
  }

  @override
  String swipeShortBy(String duration) {
    return 'أقل بـ $duration';
  }

  @override
  String get swipeAllSeen => 'هذا كل ما لدينا هنا';

  @override
  String get swipeEmptyAllRejected =>
      'لقد رفضت كل المحطات، وليس لدى هذه المدينة غيرها لتقترحه. ارجع لتغيير الموضوع أو لتخصيص وقت أقل.';

  @override
  String get swipeEmptyNoMore =>
      'لم تعد في هذه المدينة محطات تملأ بقية وقتك. تابع بما احتفظت به، أو ارجع وجرّب موضوعًا آخر.';

  @override
  String get swipeUndo => 'تراجع عن آخر اختيار';

  @override
  String get swipeDrop => 'استبعاد هذه المحطة';

  @override
  String get swipeAbout => 'عن هذه المحطة';

  @override
  String get swipeKeep => 'الاحتفاظ بهذه المحطة';

  @override
  String get swipeBadgeLike => 'نعم';

  @override
  String get swipeBadgeNope => 'لا';

  @override
  String get swipeBadgeMoreInfo => 'تفاصيل أكثر ↓';

  @override
  String get resultBackToPlanning => 'العودة إلى التخطيط';

  @override
  String get resultOpenMap => 'فتح الخريطة';

  @override
  String get resultYourRoute => 'مسارك';

  @override
  String get resultItinerary => 'خط السير';

  @override
  String get resultRemoveStops => 'إزالة محطات';

  @override
  String resultStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محطة',
      many: '$count محطة',
      few: '$count محطات',
      two: 'محطتان',
      one: 'محطة واحدة',
      zero: '$count محطة',
    );
    return '$_temp0';
  }

  @override
  String get resultStartRoute => 'ابدأ هذا المسار';

  @override
  String get resultNoStopsLeft => 'لم تبقَ أي محطة';

  @override
  String get resultNoRouteYet => 'لا يوجد مسار بعد';

  @override
  String get resultDroppedEveryStop =>
      'لقد استبعدت كل محطات هذا المسار. جرّب موضوعًا آخر، أو وقتًا أطول، أو مدينة مختلفة.';

  @override
  String get resultPickCityAndTheme =>
      'اختر مدينة وموضوعًا لتخطيط مسارك الأول.';

  @override
  String get resultChangeThePlan => 'تعديل الخطة';

  @override
  String get transportWalking => 'سيرًا على الأقدام';

  @override
  String get transportDriving => 'بالسيارة';

  @override
  String get transportHybrid => 'سيارة ومشي';

  @override
  String get routeFallbackTitle => 'مسار';

  @override
  String get itineraryDrive => 'بالسيارة';

  @override
  String get itineraryWalk => 'سيرًا';

  @override
  String itineraryLeg(String duration, String distance) {
    return '$duration · $distance';
  }

  @override
  String itineraryDwell(String duration) {
    return '$duration هنا';
  }

  @override
  String get routeHeaderTotal => 'الإجمالي';

  @override
  String routeHeaderStops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'محطة',
      many: 'محطة',
      few: 'محطات',
      two: 'محطتان',
      one: 'محطة',
      zero: 'محطة',
    );
    return '$_temp0';
  }

  @override
  String routeHeaderOverBudgetTitle(String budget) {
    return 'أطول من $budget المتاحة لديك';
  }

  @override
  String routeHeaderOverBudgetBody(String duration, int days) {
    return 'يحتاج هذا المسار إلى $duration تقريبًا. خطّط لـ $days أيام، أو أزل بعض المحطات أدناه.';
  }

  @override
  String get routeHeaderSomethingWrong => 'حدث خطأ ما';

  @override
  String routeSummaryStopSemantic(int index, String name) {
    return 'المحطة $index، $name';
  }

  @override
  String get routeSummaryCurrentStop => '، المحطة الحالية';

  @override
  String get routeSummaryVisited => '، تمت زيارتها';

  @override
  String routeLegendDrive(String duration) {
    return 'بالسيارة · $duration';
  }

  @override
  String routeLegendWalk(String duration) {
    return 'سيرًا · $duration';
  }

  @override
  String routeMapSummary(String stops, String duration) {
    return '$stops · $duration';
  }

  @override
  String get overviewYourRoute => 'مسارك';

  @override
  String get overviewTitle => 'نظرة عامة';

  @override
  String overviewPointsEarned(int count) {
    return '$count نقطة مكتسبة في هذا المسار';
  }

  @override
  String get overviewRouteCompleteBanner => 'اكتمل المسار';

  @override
  String overviewStopOfBanner(int index, int total) {
    return 'المحطة $index من $total';
  }

  @override
  String overviewStopOf(int index, int total) {
    return 'المحطة $index من $total';
  }

  @override
  String get overviewAllDone => 'انتهى كل شيء!';

  @override
  String get overviewRouteCompleteTitle => 'اكتمل المسار!';

  @override
  String get overviewRouteCompleteBody =>
      'لقد زرت كل المحطات. لقطاتك بانتظارك في المجلّد.';

  @override
  String get overviewEndVisit => 'إنهاء الزيارة';

  @override
  String get overviewEndOfRoute => 'نهاية المسار';

  @override
  String get overviewUpcoming => 'القادم';

  @override
  String get taskCurrentTask => 'المهمة الحالية';

  @override
  String taskRegenerate(int count) {
    return 'تغيير ($count)';
  }

  @override
  String taskPoints(int points) {
    return '+$points نقطة';
  }

  @override
  String get taskHunt => 'ابدأ الصيد';

  @override
  String get taskStopHunt => 'إيقاف';

  @override
  String get taskShoot => 'تصوير';

  @override
  String get taskFilm => 'فيديو';

  @override
  String get taskScan => 'مسح';

  @override
  String get questPhoto1 =>
      'التقط صورة تُظهر لماذا يستحق هذا المكان التوقّف عنده.';

  @override
  String get questPhoto2 =>
      'صوّر هنا تفصيلًا واحدًا قد لا ينتبه إليه سائح عابر.';

  @override
  String get questPhoto3 => 'صوّر هذه المحطة كما لو كنت تصفها لأحدهم.';

  @override
  String get questVideo1 =>
      'اضغط مطوّلًا على زر التصوير وصوّر لقطة بانورامية بطيئة للمكان.';

  @override
  String get questVideo2 =>
      'صوّر مقطعًا قصيرًا وأنت تقترب منه — اضغط مطوّلًا للتسجيل.';

  @override
  String get questVideo3 => 'اضغط مطوّلًا بضع ثوانٍ لتصوير المكان بأصواته.';

  @override
  String get questMascot1 => 'يختبئ فنك في مكان ما هنا — اعثر عليه وصوّره.';

  @override
  String get questMascot2 => 'هناك فنك قريب. تتبّع الإشارة والتقطه.';

  @override
  String get questMascot3 => 'تعقّب الفنك المختبئ في هذه المحطة.';

  @override
  String get huntLoadingArData => 'جارٍ تحميل بيانات الواقع المعزّز…';

  @override
  String get huntFindingPosition => 'جارٍ تحديد موقعك…';

  @override
  String get huntGettingFix => 'جارٍ ضبط موقعك…';

  @override
  String get huntTurnOnLocation => 'فعّل خدمات الموقع لبدء الصيد.';

  @override
  String get huntNeedsLocation => 'يحتاج الصيد إلى موقعك ليرشدك نحو الفنك.';

  @override
  String get huntLocationOffForApp =>
      'الموقع معطّل لهذا التطبيق. فعّله من الإعدادات لتتمكّن من الصيد.';

  @override
  String get huntTestingModeNote =>
      'وضع الاختبار — ظهر هذا الفنك بالقرب منك، لا عند المحطة.';

  @override
  String get huntRightUnderYourNose => 'تحت أنفك تمامًا';

  @override
  String huntMetersAway(int meters) {
    return 'على بعد $meters م';
  }

  @override
  String huntKilometersAway(String km) {
    return 'على بعد $km كم';
  }

  @override
  String huntAccuracyNote(int meters) {
    return ' ±$meters م';
  }

  @override
  String get huntOpenCamera => 'فتح الكاميرا';

  @override
  String get huntGetCloser => 'اقترب أكثر لفتح الكاميرا';

  @override
  String get huntBandFrozen => 'بارد جدًا';

  @override
  String get huntBandCold => 'بارد';

  @override
  String get huntBandWarm => 'بدأ يسخن';

  @override
  String get huntBandHot => 'ساخن!';

  @override
  String get huntBandBurning => 'إنه هنا تمامًا!';

  @override
  String get huntHintFrozen => 'في مكان ما هناك — تتبّع السهم';

  @override
  String get huntHintCold => 'واصل الاستكشاف في هذا الاتجاه';

  @override
  String get huntHintWarm => 'أنت على الطريق الصحيح';

  @override
  String get huntHintHot => 'قريب جدًا — بضع خطوات أخرى';

  @override
  String get huntHintBurning => 'افتح الكاميرا لالتقاطه';

  @override
  String get arModeMedia => 'وسائط';

  @override
  String get arModeScan => 'مسح ثلاثي الأبعاد';

  @override
  String get arNoCamera => 'لا توجد كاميرا في هذا الجهاز';

  @override
  String get arCameraNeedsPermission => 'تحتاج الكاميرا إلى إذن قبل أن تفتح.';

  @override
  String arCameraDidNotOpen(String error) {
    return 'لم تفتح الكاميرا: $error';
  }

  @override
  String get arCouldNotReadModel => 'تعذّرت قراءة مجسّم التميمة.';

  @override
  String get arCouldNotPlaceFennec =>
      'تعذّر وضع الفنك. أعد المحاولة بعد لحظات.';

  @override
  String get arHuntNeedsCamera =>
      'يحتاج الصيد إلى الكاميرا ليرى المكان من حولك.';

  @override
  String get arPhotoNeedsCamera => 'التقاط صورة يتطلّب الكاميرا.';

  @override
  String get arAllowCamera => 'السماح بالكاميرا';

  @override
  String get arKeepThisClip => 'الاحتفاظ بهذا المقطع؟';

  @override
  String get arScanThis => 'مسح هذا؟';

  @override
  String get arKeepThisPhoto => 'الاحتفاظ بهذه الصورة؟';

  @override
  String get arFindTheFennec => 'اعثر على الفنك';

  @override
  String get arScanAnObject => 'امسح جسمًا';

  @override
  String get arPhotoOrVideo => 'صورة أو فيديو';

  @override
  String get arClipLooping => 'يُعاد تشغيله — شاهده قبل أن تقرّر';

  @override
  String get arCheckObjectSharp => 'تأكّد أن الجسم واضح وكامل';

  @override
  String get arCheckItCameOut => 'تأكّد أن النتيجة كما أردت';

  @override
  String get arSomewhereAroundYou => 'في مكان ما حولك';

  @override
  String get arComesBackAs3d => 'سيعود مجسّمًا ثلاثي الأبعاد';

  @override
  String get arGoesToYourFolder => 'سيذهب مباشرة إلى مجلّدك';

  @override
  String get arFillTheFrame => 'املأ الإطار بجسم واحد، ثم صوّر';

  @override
  String get arTapToShootHoldToFilm => 'انقر للتصوير · اضغط مطوّلًا للفيديو';

  @override
  String get arStageReadingRoom => 'قراءة المكان';

  @override
  String get arStageReadingRoomHint => 'ارفع الهاتف وحرّكه ببطء';

  @override
  String get arStageLettingOut => 'إخراج الفنك';

  @override
  String get arStageLettingOutHint => 'ثبّت الهاتف لثانية';

  @override
  String get arStageThereItIs => 'ها هو — انقر عليه';

  @override
  String get arStageItIsOutThere => 'إنه هناك — تتبّع السهم';

  @override
  String get arStageWalkAround => 'در حوله لتراه من كل الجهات';

  @override
  String get arStageFoundIt => 'وجدته';

  @override
  String get arStageFrameTheShot => 'اضبط الإطار والتقط صورتك';

  @override
  String arDistanceAway(String meters) {
    return 'على بعد $meters م';
  }

  @override
  String get arFloorEstimated =>
      'الأرضية تقديرية — تتحسّن تلقائيًا كلما تم مسح المكان';

  @override
  String arQuestNeedsClip(int seconds) {
    return 'هذه المهمة تتطلّب مقطعًا — اضغط مطوّلًا $seconds ثوانٍ أو أكثر';
  }

  @override
  String arClipTooShort(int actual, int required) {
    return 'طول المقطع $actual ث — تتطلّب هذه المهمة $required على الأقل. اضغط لمدة أطول.';
  }

  @override
  String get arHoldToFilm => 'اضغط مطوّلًا للحظة لبدء التصوير';

  @override
  String arHoldToFilmMinimum(int seconds) {
    return 'اضغط مطوّلًا للتصوير · $seconds ث كحد أدنى';
  }

  @override
  String arClipCapped(int seconds) {
    return 'تم تحديد المقطع عند $seconds ث';
  }

  @override
  String arKeepClip(int seconds) {
    return 'الاحتفاظ بمقطع $seconds ث';
  }

  @override
  String get arScanIt => 'امسحه';

  @override
  String get arUsePhoto => 'استخدام الصورة';

  @override
  String arSecondsLeft(int seconds) {
    return 'بقيت $seconds ث';
  }

  @override
  String get arTapToTakePhoto => 'انقر لالتقاط الصورة';

  @override
  String get arClipWontPlayBack =>
      'لا يمكن تشغيل هذا المقطع. احذفه وصوّر من جديد.';

  @override
  String arCouldNotTakeShot(String error) {
    return 'تعذّر التقاط الصورة: $error';
  }

  @override
  String arCouldNotStartFilming(String error) {
    return 'تعذّر بدء التصوير: $error';
  }

  @override
  String arClipDidNotSave(String error) {
    return 'لم يُحفظ المقطع: $error';
  }

  @override
  String arCouldNotSaveClip(String error) {
    return 'تعذّر حفظ هذا المقطع: $error';
  }

  @override
  String arCouldNotSaveShot(String error) {
    return 'تعذّر حفظ هذه الصورة: $error';
  }

  @override
  String arCouldNotScanShot(String error) {
    return 'تعذّر مسح هذه الصورة: $error';
  }

  @override
  String arClipSaved(int seconds) {
    return 'تم حفظ مقطع $seconds ث في مجلّدك';
  }

  @override
  String get arFennecCaught => 'تم التقاط الفنك!';

  @override
  String get arPhotoSaved => 'تم حفظ الصورة في مجلّدك';

  @override
  String get arNoClearObject =>
      'لا يوجد جسم واضح في هذه الصورة — لم يتم مسح شيء. حاول أن تملأ الإطار أكثر بالجسم.';

  @override
  String get arGenerating3dModel =>
      'جارٍ إنشاء المجسّم ثلاثي الأبعاد — تفقّد مجلّدك بعد قليل';

  @override
  String get folderYourFolder => 'مجلّدك';

  @override
  String get folderTitle => 'المحفوظات والمسوحات';

  @override
  String get folderSearchScans => 'ابحث في عمليات المسح';

  @override
  String get folderSearchSaved => 'ابحث في الأماكن المحفوظة';

  @override
  String get folderNoScans => 'لا توجد عمليات مسح بعد';

  @override
  String get folderNoScansBody =>
      'أنجز مهام المسح والفيديو في مسارك لملء هذا المجلّد.';

  @override
  String get folderNoSavedLocations => 'لا توجد أماكن محفوظة';

  @override
  String get artifactGenerating3d => 'جارٍ الإنشاء…';

  @override
  String get artifact3dFailed => 'فشل الإنشاء';

  @override
  String get artifact3dModel => 'مجسّم ثلاثي الأبعاد';

  @override
  String get artifactPhoto => 'صورة';

  @override
  String get artifactVideo => 'فيديو';

  @override
  String get artifactYourCapture => 'لقطتك';

  @override
  String get artifactGenerationFailed => 'فشل الإنشاء';

  @override
  String get modelFailNoSubject => 'لم يُعثر على جسم واضح — جرّب زاوية أخرى';

  @override
  String get modelFailTimeout => 'انتهت المهلة — انقر لإعادة المحاولة';

  @override
  String get modelFailGpuOom => 'الخادم مشغول — انقر لإعادة المحاولة';

  @override
  String get modelFailInternal => 'حدث خطأ ما — انقر لإعادة المحاولة';

  @override
  String get viewerCouldNotLoadFile => 'تعذّر تحميل ملف المجسّم ثلاثي الأبعاد';

  @override
  String get viewerLoadingModel => 'جارٍ تحميل المجسّم…';

  @override
  String get viewerCouldNotDisplay => 'تعذّر عرض المجسّم ثلاثي الأبعاد';

  @override
  String viewerCouldNotDisplayError(String error) {
    return 'تعذّر عرض المجسّم ثلاثي الأبعاد — $error';
  }

  @override
  String get viewerHintInteractive3d =>
      'مجسّم ثلاثي الأبعاد تفاعلي — المسه لتدويره';

  @override
  String get viewerHintVideo => 'انقر على الفيديو للتشغيل أو الإيقاف';

  @override
  String get viewerHintPinchZoom => 'قرّص للتكبير · اسحب للتحريك';

  @override
  String get viewerHintDragRotate => 'اسحب للتدوير · قرّص للتكبير';

  @override
  String get viewerClipUnplayable =>
      'لا يمكن تشغيل هذا المقطع — ربما حُذف الملف.';

  @override
  String get viewerPhotoUnloadable => 'تعذّر تحميل هذه الصورة.';

  @override
  String get rewardsTitle => 'المكافآت';

  @override
  String get rewardsOnlyOnRoute => 'متاحة بمجرّد أن تبدأ بقطع مسار.';

  @override
  String get rewardsNothingToSpendOn => 'لا شيء لإنفاق النقاط عليه الآن';

  @override
  String get rewardsPullDownToRetry =>
      'اسحب للأسفل للتحقق مرة أخرى عند توفّر اتصال.';

  @override
  String rewardsVoucherGranted(String code) {
    return 'القسيمة $code في مكافآتك. اعرضها لاستلامها.';
  }

  @override
  String rewardsCreditsGranted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إضافة $count رصيد مسح. لا تنتهي صلاحيتها.',
      many: 'تمت إضافة $count رصيد مسح. لا تنتهي صلاحيتها.',
      few: 'تمت إضافة $count أرصدة مسح. لا تنتهي صلاحيتها.',
      two: 'تمت إضافة رصيدَي مسح. لا تنتهي صلاحيتهما.',
      one: 'تمت إضافة رصيد مسح واحد. لا تنتهي صلاحيته.',
      zero: 'تمت إضافة $count رصيد مسح. لا تنتهي صلاحيتها.',
    );
    return '$_temp0';
  }

  @override
  String rewardsRerollsGranted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تغيير إضافي للمهام في هذه الجولة.',
      many: '$count تغييرًا إضافيًا للمهام في هذه الجولة.',
      few: '$count تغييرات إضافية للمهام في هذه الجولة.',
      two: 'تغييران إضافيان للمهام في هذه الجولة.',
      one: 'تغيير إضافي واحد للمهام في هذه الجولة.',
      zero: '$count تغيير إضافي للمهام في هذه الجولة.',
    );
    return '$_temp0';
  }

  @override
  String rewardsGranted(String title) {
    return '$title أصبحت لك.';
  }

  @override
  String get balanceToSpend => 'للإنفاق';

  @override
  String get balanceSyncing => 'جارٍ المزامنة…';

  @override
  String balancePoints(int count) {
    return '$count نقطة';
  }

  @override
  String get rewardKindDigital => 'داخل التطبيق';

  @override
  String get rewardKindPartner => 'على الطريق';

  @override
  String get rewardKindPhysical => 'أشياء تحتفظ بها';

  @override
  String get rewardKindDigitalBlurb => 'أنفق نقاطك على ما يقدّمه مسار نفسه.';

  @override
  String get rewardKindPartnerBlurb => 'تُستبدل في مكان يقع على أحد مساراتك.';

  @override
  String get rewardKindPhysicalBlurb => 'تُستلم شخصيًا. تتطلّب حسابًا.';

  @override
  String get rewardOwned => 'مملوكة';

  @override
  String get rewardSoldOut => 'نفدت';

  @override
  String rewardStockLeft(int count) {
    return 'بقيت $count';
  }

  @override
  String get rewardPointsUnit => 'نقطة';

  @override
  String get rewardFallbackTitle => 'مكافأة';

  @override
  String get redeemCosts => 'التكلفة';

  @override
  String get redeemYouAreShort => 'ينقصك';

  @override
  String get redeemLeftAfterwards => 'المتبقي بعدها';

  @override
  String get redeemNoteInstant =>
      'تُشترى مرة واحدة وتبقى لك. لا يمكن إعادة بيعها.';

  @override
  String get redeemNoteVoucher =>
      'رمز تعرضه على أرض الواقع. صالح 14 يومًا، ثم تعود إليك النقاط.';

  @override
  String get redeemNoteManual =>
      'تتطلّب حسابًا — هذه مكافأة نسلّمها لك يدويًا.';

  @override
  String get redeemNotYet => 'ليس الآن';

  @override
  String get redeemNotEnoughPoints => 'النقاط غير كافية';

  @override
  String get redeemConfirm => 'استبدال';

  @override
  String get redeemFailSignIn => 'سجّل الدخول أولًا لتبقى هذه المكافأة لك.';

  @override
  String get redeemFailOffline =>
      'أنت غير متصل. الاستبدال يتطلّب اتصالًا ليبقى رصيدك صحيحًا.';

  @override
  String get redeemFailNotEnough =>
      'النقاط غير كافية بعد — أنجز مهمة أو مهمتين إضافيتين.';

  @override
  String get redeemFailUnavailable => 'هذه المكافأة لم تعد متاحة.';

  @override
  String get redeemFailOutOfStock => 'نفدت آخر واحدة للتو. المزيد في الطريق.';

  @override
  String get redeemFailAlreadyOwned => 'لديك هذه المكافأة بالفعل.';

  @override
  String get redeemFailNeedsAccount =>
      'أنشئ حسابًا للمطالبة بمكافأة يجب أن نسلّمها لك شخصيًا.';

  @override
  String get redeemFailRateLimited =>
      'هذا عدد كبير من عمليات الاستبدال دفعة واحدة. أعد المحاولة بعد بضع دقائق.';

  @override
  String get redeemFailGeneric =>
      'لم تتم العملية. نقاطك لم تُمسّ — أعد المحاولة.';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsSectionTour => 'الجولة';

  @override
  String get settingsLeaveTour => 'مغادرة الجولة الحالية';

  @override
  String get settingsSectionArHunt => 'صيد الواقع المعزّز';

  @override
  String get settingsTestingMode => 'وضع الاختبار';

  @override
  String get settingsTestingModeSubtitle =>
      'إظهار التميمة بالقرب من موقعك الحالي';

  @override
  String get settingsSectionAccount => 'الحساب';

  @override
  String get settingsSectionNotifications => 'الإشعارات';

  @override
  String get settingsSectionLanguage => 'اللغة';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsLanguageSystem => 'حسب إعدادات الجهاز';

  @override
  String get settingsLanguageSystemSubtitle =>
      'استخدام اللغة المضبوطة على هاتفك';

  @override
  String get settingsSectionAbout => 'حول التطبيق';

  @override
  String get settingsReplayIntro => 'إعادة عرض المقدمة';

  @override
  String get settingsReplayIntroSubtitle => 'جولة تعريفية بما يفعله مسار';

  @override
  String settingsVersion(String version) {
    return 'مسار الإصدار $version';
  }

  @override
  String get settingsTotalPoints => 'مجموع النقاط';

  @override
  String get settingsSyncing => 'جارٍ المزامنة…';

  @override
  String get settingsEarnedAcrossTours => 'المكتسبة عبر كل جولاتك';

  @override
  String get settingsSignedIn => 'مسجّل الدخول';

  @override
  String get settingsCreateAccount => 'إنشاء حساب';

  @override
  String get settingsAccountFollows => 'نقاطك وتذكاراتك مرتبطة بهذا الحساب';

  @override
  String get settingsGuestOnDevice => 'ضيف — تقدّمك محفوظ على هذا الجهاز فقط';

  @override
  String get settingsSignOut => 'تسجيل الخروج';

  @override
  String get settingsNotifications => 'الإشعارات';

  @override
  String get settingsNotificationsOn => 'المسارات والمجسّمات والفنك القريب';

  @override
  String get settingsNotificationsOff =>
      'معطّلة — لن تُعلَم حين يصبح أي شيء جاهزًا';

  @override
  String get settingsRouteReady => 'جاهزية المسار';

  @override
  String get settingsRouteReadySubtitle => 'حين ينتهي إنشاء مسار طلبته';

  @override
  String get settings3dCaptures => 'اللقطات ثلاثية الأبعاد';

  @override
  String get settings3dCapturesSubtitle =>
      'حين يصبح مجسّم صوّرته جاهزًا، أو يفشل';

  @override
  String get settingsFennecNearby => 'فنك قريب';

  @override
  String get settingsFennecNearbySubtitle => 'أثناء الصيد، حين تقترب من أحدها';

  @override
  String get settingsPushNotConfigured =>
      'الإشعارات الفورية غير مهيّأة، لذا تصل هذه الإشعارات فقط أثناء فتح التطبيق أو وجوده في الخلفية.';

  @override
  String get authWelcomeBack => 'أهلًا بعودتك';

  @override
  String get authCreateYourAccount => 'أنشئ حسابك';

  @override
  String get authLogIn => 'تسجيل الدخول';

  @override
  String get authSignUp => 'إنشاء حساب';

  @override
  String get authEmail => 'البريد الإلكتروني';

  @override
  String get authEmailHint => 'you@example.com';

  @override
  String get authPassword => 'كلمة المرور';

  @override
  String get authPasswordHintSignup => '6 أحرف على الأقل';

  @override
  String get authPasswordHintLogin => '••••••••';

  @override
  String get authForgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get authCreateAccountButton => 'إنشاء حساب';

  @override
  String get authContinueAsGuest => 'المتابعة كضيف';

  @override
  String get authGuestKeepsProgress =>
      'كل ما جمعته يبقى لك — إنشاء حساب يحفظه في حسابك.';

  @override
  String get authCanSignUpLater => 'يمكنك إنشاء حساب لاحقًا من الإعدادات.';

  @override
  String get authResetYourPassword => 'إعادة تعيين كلمة المرور';

  @override
  String get authResetEmailBlurb =>
      'سنرسل لك رابطًا بالبريد لتعيين كلمة مرور جديدة.';

  @override
  String get authSendLink => 'إرسال الرابط';

  @override
  String get authEnterEmail => 'أدخل بريدك الإلكتروني.';

  @override
  String get authInvalidEmail => 'لا يبدو هذا بريدًا إلكترونيًا صالحًا.';

  @override
  String get authEnterPassword => 'أدخل كلمة المرور.';

  @override
  String get authPasswordTooShort => 'استخدم 6 أحرف على الأقل.';

  @override
  String get authUseDifferentEmail => 'استخدام بريد آخر';

  @override
  String get authCheckYourEmail => 'تفقّد بريدك';

  @override
  String authCodeSentTo(int length) {
    return 'أرسلنا رمزًا من $length أرقام إلى\n';
  }

  @override
  String get authConfirm => 'تأكيد';

  @override
  String authResendIn(int seconds) {
    return 'إعادة إرسال الرمز بعد $seconds ث';
  }

  @override
  String get authSendNewCode => 'إرسال رمز جديد';

  @override
  String get authCodeExpiryNote =>
      'تنتهي صلاحية الرمز بعد ساعة. تفقّد مجلّد الرسائل غير المرغوب فيها إن لم يصلك.';

  @override
  String get authChooseNewPassword => 'اختر كلمة مرور جديدة';

  @override
  String get authNewPasswordBlurb =>
      'ستحل محل القديمة في كل مكان. وستبقى مسجّل الدخول على هذا الجهاز.';

  @override
  String get authNewPassword => 'كلمة المرور الجديدة';

  @override
  String get authConfirmPassword => 'تأكيد كلمة المرور';

  @override
  String get authTypeItAgain => 'أدخلها مرة أخرى';

  @override
  String get authEnterNewPassword => 'أدخل كلمة مرور جديدة.';

  @override
  String get authPasswordsDoNotMatch => 'الكلمتان غير متطابقتين.';

  @override
  String get authSavePassword => 'حفظ كلمة المرور';

  @override
  String get authAccountCreatedWithProgress =>
      'تم إنشاء الحساب. كل ما جمعته أصبح محفوظًا فيه الآن.';

  @override
  String get authAccountCreated => 'تم إنشاء الحساب.';

  @override
  String get authCodeAcceptedChoosePassword =>
      'تم قبول الرمز. اختر كلمة مرور جديدة.';

  @override
  String get authEmailConfirmed => 'تم تأكيد البريد. حسابك جاهز.';

  @override
  String authNewCodeSent(String email) {
    return 'رمز جديد في طريقه إلى $email.';
  }

  @override
  String get authWelcomeBackNotice => 'أهلًا بعودتك.';

  @override
  String get authPasswordUpdated =>
      'تم تحديث كلمة المرور. أنت مسجّل الدخول الآن.';

  @override
  String get authErrorNetwork =>
      'تعذّر الوصول إلى الخادم. تحقّق من اتصالك وأعد المحاولة.';

  @override
  String get authErrorEmailNotSending =>
      'تعذّر إرسال الرمز — إرسال البريد متوقّف حاليًا. المشكلة من جانبنا؛ أعد المحاولة بعد بضع دقائق.';

  @override
  String get authErrorBadCredentials =>
      'لا يطابق هذا البريد وكلمة المرور أي حساب.';

  @override
  String get authErrorAlreadyRegistered =>
      'هذا البريد له حساب بالفعل. جرّب تسجيل الدخول بدلًا من ذلك.';

  @override
  String get authErrorPasswordTooShort =>
      'يجب أن تتكوّن كلمة المرور من 6 أحرف على الأقل.';

  @override
  String get authErrorTooManyAttempts =>
      'محاولات كثيرة. انتظر دقيقة ثم أعد المحاولة.';

  @override
  String get authErrorCodeExpired =>
      'انتهت صلاحية هذا الرمز. اطلب رمزًا جديدًا.';

  @override
  String get authErrorCodeInvalid =>
      'هذا الرمز غير صحيح. تحقّق من البريد وأعد المحاولة.';

  @override
  String get authErrorGeneric => 'حدث خطأ ما. أعد المحاولة.';

  @override
  String get authAnonymousSignInFailed => 'فشل تسجيل الدخول كضيف';

  @override
  String get onboardingGetStarted => 'لنبدأ';

  @override
  String get onboardingIllustration => 'رسم توضيحي';

  @override
  String onboardingPageOf(int index, int count) {
    return 'الصفحة $index من $count';
  }

  @override
  String get onboardingWelcomeTitle => 'هذا هو مسار';

  @override
  String get onboardingWelcomeBody =>
      'خطّط لوجهتك، واعثر على ما تفعله حين تصل، وخذ معك جزءًا منها إلى البيت.';

  @override
  String get onboardingRoutesTitle => 'مسار مصمّم على مقاسك';

  @override
  String get onboardingRoutesBody =>
      'اختر مدينة، وقل ما يحلو لك، واحصل على خطة تناسب يومك — مع مهمة صغيرة في كل محطة.';

  @override
  String get onboardingCaptureTitle => 'التقط الفنك، واحتفظ بالتذكارات';

  @override
  String get onboardingCaptureBody =>
      'ارفع كاميرتك للعثور على الفنك المختبئ في محطاتك — ولمسح أجسام حقيقية وتحويلها إلى تذكارات ثلاثية الأبعاد في مجلّدك.';

  @override
  String get onboardingRewardsTitle => 'حوّل نقاطك إلى شيء ملموس';

  @override
  String get onboardingRewardsBody =>
      'أنفق ما تكسبه على مكافآت من الأماكن التي تمرّ بها.';

  @override
  String get detailAskTheAi => 'اسأل الذكاء الاصطناعي';

  @override
  String get detailBestTimeToVisit => 'ما أفضل وقت للزيارة؟';

  @override
  String get detailHowLongToExplore => 'كم من الوقت يلزم لاستكشافه؟';

  @override
  String get detailAskAnything => 'اسأل أي شيء عن هذا المكان...';

  @override
  String get detailSkipThisSpot => 'تخطّي هذا المكان';

  @override
  String get detailAddToRoute => 'إضافة إلى المسار';

  @override
  String get detailGuideUnreachable =>
      'عذرًا، تعذّر الوصول إلى الدليل الآن — أعد المحاولة.';

  @override
  String get offlineBackOnline => 'عاد الاتصال — جارٍ المزامنة…';

  @override
  String offlinePendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'غير متصل — ستتم مزامنة $count عنصر عند عودة الاتصال',
      many: 'غير متصل — ستتم مزامنة $count عنصرًا عند عودة الاتصال',
      few: 'غير متصل — ستتم مزامنة $count عناصر عند عودة الاتصال',
      two: 'غير متصل — ستتم مزامنة عنصرين عند عودة الاتصال',
      one: 'غير متصل — ستتم مزامنة عنصر واحد عند عودة الاتصال',
      zero: 'غير متصل — ستتم مزامنة $count عنصر عند عودة الاتصال',
    );
    return '$_temp0';
  }

  @override
  String get offlineProgressSaved => 'غير متصل — تقدّمك محفوظ';

  @override
  String get backendConnected => 'تم الاتصال بالخادم';

  @override
  String get backendUnreachable =>
      'تعذّر الوصول إلى الخادم — يتم عرض بيانات تجريبية';

  @override
  String get routeErrorUnreachable => 'تعذّر الوصول إلى خدمة المسارات.';

  @override
  String get routeErrorCityNotAvailable =>
      'هذه المدينة غير متاحة للمسارات بعد.';

  @override
  String get routeErrorNoEligiblePois =>
      'لا توجد محطات منشورة تطابق هذا الموضوع هنا بعد.';

  @override
  String get routeErrorTimeBudgetTooShort =>
      'هذا الوقت أقصر من أن يكفي لأي محطة هنا.';

  @override
  String get routeErrorProviderUnavailable =>
      'خدمة حساب المسارات غير متاحة حاليًا.';

  @override
  String get routeErrorNotImplemented =>
      'إنشاء المسارات غير مفعّل بعد على هذا الخادم.';

  @override
  String get routeErrorGeneric => 'حدث خطأ ما أثناء إنشاء مسارك.';

  @override
  String get routeErrorDropStopsFailed =>
      'تعذّر استبعاد تلك المحطات — يتم عرض المسار كما أُنشئ.';

  @override
  String get routeErrorBelowBudget => 'إزالتها ستترك وقتًا أقل مما طلبت.';

  @override
  String get routeErrorRemoveStopFailed =>
      'تعذّرت إزالة هذه المحطة — أعد المحاولة.';

  @override
  String get notifChannelRoutesName => 'المسارات والمجسّمات';

  @override
  String get notifChannelRoutesDescription =>
      'حين يصبح مسار جاهزًا، أو تنتهي لقطة ثلاثية الأبعاد.';

  @override
  String get notifChannelHuntName => 'صيد الفنك';

  @override
  String get notifChannelHuntDescription => 'حين تقترب من فنك مختبئ.';

  @override
  String get notifRouteReadyTitle => 'مسارك جاهز';

  @override
  String get notifRouteReadyBody => 'انقر لترى إلى أين ستذهب.';

  @override
  String notifRouteReadyBodyNamed(String title) {
    return '$title مخطّط وبانتظارك.';
  }

  @override
  String get notifModelReadyTitle => 'مجسّمك ثلاثي الأبعاد جاهز';

  @override
  String get notifModelFailedTitle => 'لم تنجح تلك اللقطة';

  @override
  String get notifModelReadyBody => 'انقر لتراه في مجلّدك.';

  @override
  String get notifModelFailNoSubject =>
      'لم نعثر على جسم واضح — حاول أن تملأ الإطار به أكثر.';

  @override
  String get notifModelFailTimeout =>
      'استغرق بناؤه وقتًا طويلًا. انقر لتجربة تلك الصورة من جديد.';

  @override
  String get notifModelFailQuota =>
      'لقد استهلكت كل أرصدة المجسّمات لهذا اليوم.';

  @override
  String get notifModelFailGeneric =>
      'حدث خطأ ما أثناء بنائه. انقر لإعادة المحاولة.';

  @override
  String get notifMascotHereTitle => 'هناك فنك هنا تمامًا!';

  @override
  String get notifMascotWarmTitle => 'بدأت تقترب';

  @override
  String get notifMascotHereBody => 'انقر لفتح الكاميرا والتقاطه.';

  @override
  String get notifMascotNearbyBody => 'يختبئ فنك في مكان قريب.';

  @override
  String notifMascotNearbyBodyNamed(String stopName) {
    return 'يختبئ فنك بالقرب من $stopName.';
  }

  @override
  String get settingsSplatReady => 'مشاهد ـ 3D من تصويرك';

  @override
  String get settingsSplatReadySubtitle =>
      'عندما يتحول مقطع صورته إلى مشهد يمكنك التجول فيه';

  @override
  String get notifInboxTitle => 'الإشعارات';

  @override
  String notifInboxUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الإشعارات، $count غير مقروءة',
      one: 'الإشعارات، واحد غير مقروء',
    );
    return '$_temp0';
  }

  @override
  String get notifInboxEmptyTitle => 'لا شيء بعد';

  @override
  String get notifInboxEmptyBody =>
      'عندما يجهز مسار، أو تتحول صورة إلى مجسم ـ 3D، أو يساعد تصويرك في بناء مشهد، سيظهر هنا.';

  @override
  String get notifInboxClearAll => 'محو الكل';

  @override
  String get notifInboxClearTitle => 'محو كل الإشعارات؟';

  @override
  String get notifInboxClearBody =>
      'ستُحذف نهائيًا. أما ما تشير إليه — مسار أو مجسم أو مشهد — فيبقى كما هو.';

  @override
  String get notifInboxClearConfirm => 'محو الكل';

  @override
  String get notifInboxDelete => 'حذف';

  @override
  String get notifInboxDeleteFailed =>
      'تعذر الحذف الآن. حاول مرة أخرى بعد عودة الاتصال.';

  @override
  String get notifInboxNothingToOpen => 'لم يبق شيء لفتحه من هذا الإشعار.';

  @override
  String get timeJustNow => 'الآن';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count دقيقة',
      one: 'قبل دقيقة',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count ساعة',
      one: 'قبل ساعة',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count يوم',
      one: 'أمس',
    );
    return '$_temp0';
  }

  @override
  String get splatViewerSubtitle => 'مبني من تصويرك';

  @override
  String get splatViewerHint =>
      'اسحب للنظر حولك · قرّب بإصبعين · انقر مرتين لإعادة الضبط';

  @override
  String get splatViewerOpening => 'جارٍ فتح المشهد…';

  @override
  String get splatViewerDownloading => 'جارٍ تنزيل المشهد…';

  @override
  String get splatViewerFailed => 'تعذر فتح المشهد';

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

    return '$shownString من $trainedString غاوسية';
  }

  @override
  String get splatDetailLow => 'سلس';

  @override
  String get splatDetailMedium => 'متوازن';

  @override
  String get splatDetailHigh => 'دقيق';

  @override
  String splatDetailSemantic(String level) {
    return 'التفاصيل: $level';
  }
}
