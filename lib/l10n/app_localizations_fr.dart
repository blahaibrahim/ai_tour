// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Massar';

  @override
  String get actionCancel => 'Annuler';

  @override
  String get actionDone => 'Terminé';

  @override
  String get actionSkip => 'Passer';

  @override
  String get actionNext => 'Suivant';

  @override
  String get actionClose => 'Fermer';

  @override
  String get actionDismiss => 'Ignorer';

  @override
  String get actionTryAgain => 'Réessayer';

  @override
  String get actionAllow => 'Autoriser';

  @override
  String get actionSettings => 'Réglages';

  @override
  String get actionRetake => 'Reprendre';

  @override
  String get actionDiscard => 'Supprimer';

  @override
  String get actionBack => 'Retour';

  @override
  String get navMap => 'Carte';

  @override
  String get navHome => 'Accueil';

  @override
  String get navFolder => 'Dossier';

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get homePointsSyncing => 'Synchronisation du solde de points';

  @override
  String homePointsToSpend(int count) {
    return '$count points à dépenser';
  }

  @override
  String get homeGreeting => 'On va où ensuite ?';

  @override
  String get homeYourRoutes => 'VOS ITINÉRAIRES';

  @override
  String get homeRoutesEmpty =>
      'Les itinéraires que vous générez s\'accumuleront ici, prêts à être repris.';

  @override
  String get homePlanNewRoute => 'Planifier un itinéraire';

  @override
  String get homePlanNewRouteSubtitle =>
      'Choisissez une ville, un thème et le temps dont vous disposez';

  @override
  String get relativeToday => 'aujourd\'hui';

  @override
  String get relativeYesterday => 'hier';

  @override
  String relativeDays(int days) {
    return '$days j';
  }

  @override
  String relativeWeeks(int weeks) {
    return '$weeks sem';
  }

  @override
  String relativeYears(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years ans',
      one: '$years an',
    );
    return '$_temp0';
  }

  @override
  String get mapGenerateRoute => 'Générer mon itinéraire';

  @override
  String mapTripDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '$count jour',
    );
    return '$_temp0';
  }

  @override
  String get mapExpandTripOptions =>
      'Afficher ou masquer les options du voyage';

  @override
  String get mapHideTripOptions => 'Masquer les options';

  @override
  String get mapTapToPickWilaya => 'Touchez la carte pour choisir une wilaya';

  @override
  String get mapTapAnotherToSwitch => 'Touchez-en une autre pour changer';

  @override
  String get mapPromptHeading => 'DITES À L\'IA CE QUE VOUS CHERCHEZ';

  @override
  String get mapPromptHint =>
      'ruines romaines tranquilles, points de vue sur la côte...';

  @override
  String get mapTapPinForDetails => 'Touchez un repère pour en savoir plus';

  @override
  String get mapNoRouteYet => 'Aucun itinéraire généré pour l\'instant.';

  @override
  String get timeBudgetHeading => 'COMBIEN DE TEMPS AVEZ-VOUS ?';

  @override
  String timeBudgetDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'jours',
      one: 'jour',
    );
    return '$_temp0';
  }

  @override
  String timeBudgetHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'heures',
      one: 'heure',
    );
    return '$_temp0';
  }

  @override
  String get timeBudgetTripLength => 'Durée du voyage en jours';

  @override
  String get timeBudgetHoursPerDay => 'Heures de visite par jour';

  @override
  String get timeBudgetWholeTrip => 'pour tout le voyage';

  @override
  String get timeBudgetEachDay => 'sur chacun de ces jours';

  @override
  String get searchWilayaHint => 'Rechercher une wilaya...';

  @override
  String get searchMyLocation => 'Ma position';

  @override
  String get searchNoWilayas => 'Aucune wilaya trouvée.';

  @override
  String get locationServicesDisabled => 'Services de localisation désactivés.';

  @override
  String get locationPermissionDenied =>
      'Autorisation de localisation refusée.';

  @override
  String get locationPermissionPermanentlyDenied =>
      'Autorisation de localisation refusée définitivement.';

  @override
  String get locationLocating => 'Localisation...';

  @override
  String get locationRestartRequired =>
      'Veuillez ARRÊTER complètement l\'application et la relancer.';

  @override
  String genericError(String message) {
    return 'Erreur : $message';
  }

  @override
  String get thinkingAlmostThere => 'On y est presque...';

  @override
  String get thinkingStepBudget => 'Lecture de votre temps disponible…';

  @override
  String get thinkingStepStops =>
      'Sélection des étapes publiées pour votre thème…';

  @override
  String get thinkingStepClusters =>
      'Regroupement en secteurs praticables à pied…';

  @override
  String get thinkingStepDrive =>
      'Organisation des trajets en voiture entre les secteurs…';

  @override
  String get thinkingStepWalk => 'Organisation du parcours à pied dans chacun…';

  @override
  String get thinkingStepFit =>
      'Vérification que tout tient dans votre journée…';

  @override
  String get thinkingNotifyMe => 'Me prévenir';

  @override
  String get thinkingWillLetYouKnow =>
      'Nous vous préviendrons dès que ce sera prêt';

  @override
  String get thinkingTurnOnNotifications =>
      'Activez les notifications pour savoir\nquand ce sera prêt';

  @override
  String get notifyEnabled => 'Nous vous préviendrons dès que ce sera prêt.';

  @override
  String get notifyLocalOnly =>
      'Les notifications fonctionnent tant que l\'application reste ouverte en arrière-plan.';

  @override
  String get notifyLocalOnlySettings =>
      'Activées, mais seulement quand l\'application tourne — le push n\'est pas configuré sur cette version.';

  @override
  String get notifyDenied =>
      'Les notifications sont désactivées pour cette application — activez-les dans les réglages.';

  @override
  String get notifyDeniedSettings =>
      'Les notifications sont désactivées pour cette application dans les réglages de votre téléphone.';

  @override
  String get notifyOffline =>
      'Impossible d\'enregistrer pour le moment. Réessayez une fois de retour en ligne.';

  @override
  String swipeKeepTheRest(int reviewed, int total) {
    return 'Garder le reste ($reviewed/$total)';
  }

  @override
  String swipeShortBy(String duration) {
    return '$duration de moins';
  }

  @override
  String get swipeAllSeen => 'Vous avez tout vu';

  @override
  String get swipeEmptyAllRejected =>
      'Vous avez refusé toutes les étapes, et cette ville n\'en a pas d\'autres à proposer. Revenez en arrière pour changer de thème ou vous accorder moins de temps.';

  @override
  String get swipeEmptyNoMore =>
      'Cette ville n\'a plus d\'étapes pour remplir le temps qu\'il vous reste. Continuez avec ce que vous avez gardé, ou revenez essayer un autre thème.';

  @override
  String get swipeUndo => 'Annuler le dernier choix';

  @override
  String get swipeDrop => 'Écarter cette étape';

  @override
  String get swipeAbout => 'À propos de cette étape';

  @override
  String get swipeKeep => 'Garder cette étape';

  @override
  String get swipeBadgeLike => 'OUI';

  @override
  String get swipeBadgeNope => 'NON';

  @override
  String get swipeBadgeMoreInfo => 'PLUS D\'INFOS ↓';

  @override
  String get resultBackToPlanning => 'Retour à la planification';

  @override
  String get resultOpenMap => 'Ouvrir la carte';

  @override
  String get resultYourRoute => 'Votre itinéraire';

  @override
  String get resultItinerary => 'ITINÉRAIRE';

  @override
  String get resultRemoveStops => 'Retirer des étapes';

  @override
  String resultStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count étapes',
      one: '$count étape',
    );
    return '$_temp0';
  }

  @override
  String get resultStartRoute => 'Démarrer cet itinéraire';

  @override
  String get resultNoStopsLeft => 'Plus aucune étape';

  @override
  String get resultNoRouteYet => 'Pas encore d\'itinéraire';

  @override
  String get resultDroppedEveryStop =>
      'Vous avez écarté toutes les étapes de cet itinéraire. Essayez un autre thème, plus de temps, ou une autre ville.';

  @override
  String get resultPickCityAndTheme =>
      'Choisissez une ville et un thème pour planifier votre premier itinéraire.';

  @override
  String get resultChangeThePlan => 'Modifier le plan';

  @override
  String get transportWalking => 'À pied';

  @override
  String get transportDriving => 'En voiture';

  @override
  String get transportHybrid => 'Voiture + marche';

  @override
  String get routeFallbackTitle => 'Itinéraire';

  @override
  String get itineraryDrive => 'Voiture';

  @override
  String get itineraryWalk => 'À pied';

  @override
  String itineraryLeg(String duration, String distance) {
    return '$duration · $distance';
  }

  @override
  String itineraryDwell(String duration) {
    return '$duration sur place';
  }

  @override
  String get routeHeaderTotal => 'au total';

  @override
  String routeHeaderStops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'étapes',
      one: 'étape',
    );
    return '$_temp0';
  }

  @override
  String routeHeaderOverBudgetTitle(String budget) {
    return 'Plus long que vos $budget';
  }

  @override
  String routeHeaderOverBudgetBody(String duration, int days) {
    return 'Cet itinéraire demande environ $duration. Prévoyez $days jours, ou retirez quelques étapes ci-dessous.';
  }

  @override
  String get routeHeaderSomethingWrong => 'Un problème est survenu';

  @override
  String routeSummaryStopSemantic(int index, String name) {
    return 'Étape $index, $name';
  }

  @override
  String get routeSummaryCurrentStop => ', étape en cours';

  @override
  String get routeSummaryVisited => ', visitée';

  @override
  String routeLegendDrive(String duration) {
    return 'Voiture · $duration';
  }

  @override
  String routeLegendWalk(String duration) {
    return 'À pied · $duration';
  }

  @override
  String routeMapSummary(String stops, String duration) {
    return '$stops · $duration';
  }

  @override
  String get overviewYourRoute => 'VOTRE ITINÉRAIRE';

  @override
  String get overviewTitle => 'Aperçu';

  @override
  String overviewPointsEarned(int count) {
    return '$count points gagnés sur cet itinéraire';
  }

  @override
  String get overviewRouteCompleteBanner => 'ITINÉRAIRE TERMINÉ';

  @override
  String overviewStopOfBanner(int index, int total) {
    return 'ÉTAPE $index SUR $total';
  }

  @override
  String overviewStopOf(int index, int total) {
    return 'Étape $index sur $total';
  }

  @override
  String get overviewAllDone => 'C\'est terminé !';

  @override
  String get overviewRouteCompleteTitle => 'Itinéraire terminé !';

  @override
  String get overviewRouteCompleteBody =>
      'Vous avez visité toutes les étapes. Vos captures vous attendent dans le dossier.';

  @override
  String get overviewEndVisit => 'Terminer la visite';

  @override
  String get overviewEndOfRoute => 'Fin de l\'itinéraire';

  @override
  String get overviewUpcoming => 'À VENIR';

  @override
  String get taskCurrentTask => 'TÂCHE EN COURS';

  @override
  String taskRegenerate(int count) {
    return 'Changer ($count)';
  }

  @override
  String taskPoints(int points) {
    return '+$points pts';
  }

  @override
  String get taskHunt => 'Chasser';

  @override
  String get taskStopHunt => 'Arrêter';

  @override
  String get taskShoot => 'Photo';

  @override
  String get taskFilm => 'Filmer';

  @override
  String get taskScan => 'Scanner';

  @override
  String get questPhoto1 =>
      'Prenez une photo qui montre pourquoi cet endroit mérite qu\'on s\'y arrête.';

  @override
  String get questPhoto2 =>
      'Cadrez ici un détail qu\'un touriste de passage ne remarquerait pas.';

  @override
  String get questPhoto3 =>
      'Photographiez cette étape comme vous la décririez à quelqu\'un.';

  @override
  String get questVideo1 =>
      'Maintenez le déclencheur et filmez un panoramique lent de l\'endroit.';

  @override
  String get questVideo2 =>
      'Filmez un court clip en vous en approchant — maintenez le déclencheur pour enregistrer.';

  @override
  String get questVideo3 =>
      'Maintenez le déclencheur quelques secondes pour capter l\'endroit avec ses sons.';

  @override
  String get questMascot1 =>
      'Un fennec se cache quelque part ici — trouvez-le et photographiez-le.';

  @override
  String get questMascot2 =>
      'Il y a un fennec tout près. Suivez le signal et attrapez-le.';

  @override
  String get questMascot3 => 'Débusquez le fennec caché à cette étape.';

  @override
  String get huntLoadingArData => 'Chargement des données RA…';

  @override
  String get huntFindingPosition => 'Recherche de votre position…';

  @override
  String get huntGettingFix => 'Calage de votre position…';

  @override
  String get huntTurnOnLocation =>
      'Activez la localisation pour commencer la chasse.';

  @override
  String get huntNeedsLocation =>
      'La chasse a besoin de votre position pour vous guider vers le fennec.';

  @override
  String get huntLocationOffForApp =>
      'La localisation est désactivée pour cette application. Activez-la dans les réglages pour chasser.';

  @override
  String get huntTestingModeNote =>
      'Mode test — ce fennec est apparu près de vous, pas à l\'étape.';

  @override
  String get huntRightUnderYourNose => 'Juste sous votre nez';

  @override
  String huntMetersAway(int meters) {
    return 'à $meters m';
  }

  @override
  String huntKilometersAway(String km) {
    return 'à $km km';
  }

  @override
  String huntAccuracyNote(int meters) {
    return ' ±$meters m';
  }

  @override
  String get huntOpenCamera => 'Ouvrir l\'appareil photo';

  @override
  String get huntGetCloser => 'Approchez-vous pour débloquer l\'appareil photo';

  @override
  String get huntBandFrozen => 'Glacial';

  @override
  String get huntBandCold => 'Froid';

  @override
  String get huntBandWarm => 'Ça se réchauffe';

  @override
  String get huntBandHot => 'Chaud !';

  @override
  String get huntBandBurning => 'Il est juste là !';

  @override
  String get huntHintFrozen => 'Quelque part par là — suivez la flèche';

  @override
  String get huntHintCold => 'Continuez à explorer dans cette direction';

  @override
  String get huntHintWarm => 'Vous êtes sur la bonne piste';

  @override
  String get huntHintHot => 'Tout près — encore quelques pas';

  @override
  String get huntHintBurning => 'Ouvrez l\'appareil photo pour l\'attraper';

  @override
  String get arModeMedia => 'Média';

  @override
  String get arModeScan => 'Scan 3D';

  @override
  String get arNoCamera => 'Aucun appareil photo sur cet appareil';

  @override
  String get arCameraNeedsPermission =>
      'L\'appareil photo a besoin d\'une autorisation avant de s\'ouvrir.';

  @override
  String arCameraDidNotOpen(String error) {
    return 'L\'appareil photo ne s\'est pas ouvert : $error';
  }

  @override
  String get arCouldNotReadModel =>
      'Impossible de lire le modèle de la mascotte.';

  @override
  String get arCouldNotPlaceFennec =>
      'Impossible de placer le fennec. Réessayez dans un instant.';

  @override
  String get arHuntNeedsCamera =>
      'La chasse a besoin de l\'appareil photo pour voir la pièce autour de vous.';

  @override
  String get arPhotoNeedsCamera =>
      'Prendre une photo nécessite l\'appareil photo.';

  @override
  String get arAllowCamera => 'Autoriser l\'appareil photo';

  @override
  String get arKeepThisClip => 'Garder ce clip ?';

  @override
  String get arScanThis => 'Scanner ceci ?';

  @override
  String get arKeepThisPhoto => 'Garder cette photo ?';

  @override
  String get arFindTheFennec => 'Trouver le fennec';

  @override
  String get arScanAnObject => 'Scanner un objet';

  @override
  String get arPhotoOrVideo => 'Photo ou vidéo';

  @override
  String get arClipLooping =>
      'Il tourne en boucle — regardez-le avant de décider';

  @override
  String get arCheckObjectSharp => 'Vérifiez que l\'objet est net et entier';

  @override
  String get arCheckItCameOut => 'Vérifiez que le rendu vous convient';

  @override
  String get arSomewhereAroundYou => 'Quelque part autour de vous';

  @override
  String get arComesBackAs3d => 'Cela revient en modèle 3D';

  @override
  String get arGoesToYourFolder => 'Cela va directement dans votre dossier';

  @override
  String get arFillTheFrame =>
      'Remplissez le cadre avec un seul objet, puis déclenchez';

  @override
  String get arTapToShootHoldToFilm =>
      'Touchez pour photographier · maintenez pour filmer';

  @override
  String get arStageReadingRoom => 'Lecture de la pièce';

  @override
  String get arStageReadingRoomHint =>
      'Levez le téléphone et bougez-le lentement';

  @override
  String get arStageLettingOut => 'Le fennec arrive';

  @override
  String get arStageLettingOutHint => 'Restez stable une seconde';

  @override
  String get arStageThereItIs => 'Le voilà — touchez-le';

  @override
  String get arStageItIsOutThere => 'Il est quelque part — suivez la flèche';

  @override
  String get arStageWalkAround =>
      'Tournez autour pour le voir sous tous les angles';

  @override
  String get arStageFoundIt => 'Trouvé';

  @override
  String get arStageFrameTheShot => 'Cadrez et prenez votre photo';

  @override
  String arDistanceAway(String meters) {
    return 'à $meters m';
  }

  @override
  String get arFloorEstimated =>
      'Sol estimé — il s\'ajuste au fur et à mesure que la pièce est cartographiée';

  @override
  String arQuestNeedsClip(int seconds) {
    return 'Celle-ci demande un clip — maintenez le déclencheur $seconds secondes ou plus';
  }

  @override
  String arClipTooShort(int actual, int required) {
    return 'Ce clip faisait $actual s — cette quête en demande au moins $required. Maintenez plus longtemps.';
  }

  @override
  String get arHoldToFilm => 'Maintenez le déclencheur un instant pour filmer';

  @override
  String arHoldToFilmMinimum(int seconds) {
    return 'Maintenez pour filmer · $seconds s minimum';
  }

  @override
  String arClipCapped(int seconds) {
    return 'Clip limité à $seconds s';
  }

  @override
  String arKeepClip(int seconds) {
    return 'Garder le clip de $seconds s';
  }

  @override
  String get arScanIt => 'Le scanner';

  @override
  String get arUsePhoto => 'Utiliser la photo';

  @override
  String arSecondsLeft(int seconds) {
    return '$seconds s restantes';
  }

  @override
  String get arTapToTakePhoto => 'Touchez pour prendre la photo';

  @override
  String get arClipWontPlayBack =>
      'Ce clip ne se lit pas. Supprimez-le et filmez à nouveau.';

  @override
  String arCouldNotTakeShot(String error) {
    return 'Impossible de prendre cette photo : $error';
  }

  @override
  String arCouldNotStartFilming(String error) {
    return 'Impossible de commencer à filmer : $error';
  }

  @override
  String arClipDidNotSave(String error) {
    return 'Le clip n\'a pas été enregistré : $error';
  }

  @override
  String arCouldNotSaveClip(String error) {
    return 'Impossible d\'enregistrer ce clip : $error';
  }

  @override
  String arCouldNotSaveShot(String error) {
    return 'Impossible d\'enregistrer cette photo : $error';
  }

  @override
  String arCouldNotScanShot(String error) {
    return 'Impossible de scanner cette photo : $error';
  }

  @override
  String arClipSaved(int seconds) {
    return 'Clip de $seconds s enregistré dans votre dossier';
  }

  @override
  String get arFennecCaught => 'Fennec attrapé !';

  @override
  String get arPhotoSaved => 'Photo enregistrée dans votre dossier';

  @override
  String get arNoClearObject =>
      'Aucun objet net sur cette photo — rien n\'a été scanné. Essayez de remplir davantage le cadre avec le sujet.';

  @override
  String get arGenerating3dModel =>
      'Génération du modèle 3D — regardez votre dossier dans un instant';

  @override
  String get folderYourFolder => 'VOTRE DOSSIER';

  @override
  String get folderTitle => 'Enregistrés et scannés';

  @override
  String get folderSearchScans => 'Rechercher dans vos scans';

  @override
  String get folderSearchSaved => 'Rechercher dans vos lieux enregistrés';

  @override
  String get folderNoScans => 'Aucun scan pour l\'instant';

  @override
  String get folderNoScansBody =>
      'Réalisez les tâches de scan et de vidéo de votre itinéraire pour remplir ce dossier.';

  @override
  String get folderNoSavedLocations => 'Aucun lieu enregistré';

  @override
  String get artifactGenerating3d => 'Génération 3D…';

  @override
  String get artifact3dFailed => 'Échec 3D';

  @override
  String get artifact3dModel => 'Modèle 3D';

  @override
  String get artifactPhoto => 'Photo';

  @override
  String get artifactVideo => 'Vidéo';

  @override
  String get artifactYourCapture => 'Votre capture';

  @override
  String get artifactGenerationFailed => 'Échec de la génération';

  @override
  String get modelFailNoSubject =>
      'Aucun objet net trouvé — essayez un autre angle';

  @override
  String get modelFailTimeout => 'Délai dépassé — touchez pour réessayer';

  @override
  String get modelFailGpuOom => 'Serveur occupé — touchez pour réessayer';

  @override
  String get modelFailInternal =>
      'Un problème est survenu — touchez pour réessayer';

  @override
  String get viewerCouldNotLoadFile =>
      'Impossible de charger le fichier du modèle 3D';

  @override
  String get viewerLoadingModel => 'Chargement du modèle 3D…';

  @override
  String get viewerCouldNotDisplay => 'Impossible d\'afficher le modèle 3D';

  @override
  String viewerCouldNotDisplayError(String error) {
    return 'Impossible d\'afficher le modèle 3D — $error';
  }

  @override
  String get viewerHintInteractive3d =>
      'Modèle 3D interactif — touchez pour faire pivoter';

  @override
  String get viewerHintVideo => 'Touchez la vidéo pour lire ou mettre en pause';

  @override
  String get viewerHintPinchZoom =>
      'Pincez pour zoomer · glissez pour déplacer';

  @override
  String get viewerHintDragRotate =>
      'Glissez pour faire pivoter · pincez pour zoomer';

  @override
  String get viewerClipUnplayable =>
      'Ce clip ne peut pas être lu — le fichier a peut-être été supprimé.';

  @override
  String get viewerPhotoUnloadable => 'Cette photo n\'a pas pu être chargée.';

  @override
  String get rewardsTitle => 'Récompenses';

  @override
  String get rewardsOnlyOnRoute =>
      'Disponible une fois que vous parcourez un itinéraire.';

  @override
  String get rewardsNothingToSpendOn => 'Rien à acheter pour le moment';

  @override
  String get rewardsPullDownToRetry =>
      'Tirez vers le bas pour réessayer une fois connecté.';

  @override
  String rewardsVoucherGranted(String code) {
    return 'Le bon $code est dans vos récompenses. Présentez-le pour le retirer.';
  }

  @override
  String rewardsCreditsGranted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count crédits de scan ajoutés. Ils n\'expirent pas.',
      one: 'Un crédit de scan ajouté. Il n\'expire pas.',
    );
    return '$_temp0';
  }

  @override
  String rewardsRerollsGranted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changements de quête de plus sur ce parcours.',
      one: 'Un changement de quête de plus sur ce parcours.',
    );
    return '$_temp0';
  }

  @override
  String rewardsGranted(String title) {
    return '$title est à vous.';
  }

  @override
  String get balanceToSpend => 'À DÉPENSER';

  @override
  String get balanceSyncing => 'Synchronisation…';

  @override
  String balancePoints(int count) {
    return '$count points';
  }

  @override
  String get rewardKindDigital => 'Pour l\'application';

  @override
  String get rewardKindPartner => 'En chemin';

  @override
  String get rewardKindPhysical => 'À garder';

  @override
  String get rewardKindDigitalBlurb =>
      'Dépensez vos points sur ce que Massar sait faire.';

  @override
  String get rewardKindPartnerBlurb =>
      'À utiliser dans un lieu situé sur l\'un de vos itinéraires.';

  @override
  String get rewardKindPhysicalBlurb =>
      'Retiré en personne. Nécessite un compte.';

  @override
  String get rewardOwned => 'Obtenu';

  @override
  String get rewardSoldOut => 'Épuisé';

  @override
  String rewardStockLeft(int count) {
    return '$count restants';
  }

  @override
  String get rewardPointsUnit => 'points';

  @override
  String get rewardFallbackTitle => 'Récompense';

  @override
  String get redeemCosts => 'Coûte';

  @override
  String get redeemYouAreShort => 'Il vous manque';

  @override
  String get redeemLeftAfterwards => 'Restant ensuite';

  @override
  String get redeemNoteInstant =>
      'Acheté une fois et conservé. Impossible de le revendre.';

  @override
  String get redeemNoteVoucher =>
      'Un code à présenter sur place. Il dure 14 jours, puis les points vous reviennent.';

  @override
  String get redeemNoteManual =>
      'Nécessite un compte — c\'est quelque chose que nous vous remettons en main propre.';

  @override
  String get redeemNotYet => 'Pas encore';

  @override
  String get redeemNotEnoughPoints => 'Points insuffisants';

  @override
  String get redeemConfirm => 'Échanger';

  @override
  String get redeemFailSignIn =>
      'Connectez-vous d\'abord pour que cela vous reste.';

  @override
  String get redeemFailOffline =>
      'Vous êtes hors ligne. L\'échange nécessite une connexion pour que votre solde reste juste.';

  @override
  String get redeemFailNotEnough =>
      'Pas encore assez de points — terminez une ou deux tâches de plus.';

  @override
  String get redeemFailUnavailable => 'Celle-ci n\'est plus disponible.';

  @override
  String get redeemFailOutOfStock =>
      'La dernière vient de partir. D\'autres arrivent.';

  @override
  String get redeemFailAlreadyOwned => 'Vous avez déjà celle-ci.';

  @override
  String get redeemFailNeedsAccount =>
      'Créez un compte pour réclamer quelque chose que nous devons vous remettre en personne.';

  @override
  String get redeemFailRateLimited =>
      'Cela fait beaucoup d\'échanges d\'un coup. Réessayez dans quelques minutes.';

  @override
  String get redeemFailGeneric =>
      'Cela n\'a pas abouti. Vos points sont intacts — réessayez.';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsSectionTour => 'PARCOURS';

  @override
  String get settingsLeaveTour => 'Quitter le parcours en cours';

  @override
  String get settingsSectionArHunt => 'CHASSE RA';

  @override
  String get settingsTestingMode => 'Mode test';

  @override
  String get settingsTestingModeSubtitle =>
      'Faire apparaître la mascotte près de votre position';

  @override
  String get settingsSectionAccount => 'COMPTE';

  @override
  String get settingsSectionNotifications => 'NOTIFICATIONS';

  @override
  String get settingsSectionLanguage => 'LANGUE';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSystem => 'Suivre l\'appareil';

  @override
  String get settingsLanguageSystemSubtitle =>
      'Utiliser la langue configurée sur votre téléphone';

  @override
  String get settingsSectionAbout => 'À PROPOS';

  @override
  String get settingsReplayIntro => 'Revoir l\'introduction';

  @override
  String get settingsReplayIntroSubtitle =>
      'La présentation de ce que fait Massar';

  @override
  String settingsVersion(String version) {
    return 'Massar v$version';
  }

  @override
  String get settingsTotalPoints => 'Total des points';

  @override
  String get settingsSyncing => 'Synchronisation…';

  @override
  String get settingsEarnedAcrossTours =>
      'Gagnés sur l\'ensemble de vos parcours';

  @override
  String get settingsSignedIn => 'Connecté';

  @override
  String get settingsCreateAccount => 'Créer un compte';

  @override
  String get settingsAccountFollows =>
      'Vos points et souvenirs suivent ce compte';

  @override
  String get settingsGuestOnDevice =>
      'Invité — votre progression n\'existe que sur cet appareil';

  @override
  String get settingsSignOut => 'Se déconnecter';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsOn =>
      'Itinéraires, modèles 3D et fennecs à proximité';

  @override
  String get settingsNotificationsOff =>
      'Désactivées — vous ne serez pas prévenu quand quelque chose est prêt';

  @override
  String get settingsRouteReady => 'Itinéraire prêt';

  @override
  String get settingsRouteReadySubtitle =>
      'Quand un itinéraire demandé a fini d\'être généré';

  @override
  String get settings3dCaptures => 'Captures 3D';

  @override
  String get settings3dCapturesSubtitle =>
      'Quand un modèle photographié est prêt, ou a échoué';

  @override
  String get settingsFennecNearby => 'Fennec à proximité';

  @override
  String get settingsFennecNearbySubtitle =>
      'Pendant une chasse, quand vous vous approchez d\'un fennec';

  @override
  String get settingsPushNotConfigured =>
      'Le push n\'est pas configuré : ces notifications n\'arrivent que si l\'application est ouverte ou en arrière-plan.';

  @override
  String get authWelcomeBack => 'Bon retour';

  @override
  String get authCreateYourAccount => 'Créez votre compte';

  @override
  String get authLogIn => 'Connexion';

  @override
  String get authSignUp => 'Inscription';

  @override
  String get authEmail => 'E-mail';

  @override
  String get authEmailHint => 'vous@exemple.com';

  @override
  String get authPassword => 'Mot de passe';

  @override
  String get authPasswordHintSignup => 'Au moins 6 caractères';

  @override
  String get authPasswordHintLogin => '••••••••';

  @override
  String get authForgotPassword => 'Mot de passe oublié ?';

  @override
  String get authCreateAccountButton => 'Créer un compte';

  @override
  String get authContinueAsGuest => 'Continuer en invité';

  @override
  String get authGuestKeepsProgress =>
      'Tout ce que vous avez déjà collecté vous appartient — l\'inscription l\'enregistre sur votre compte.';

  @override
  String get authCanSignUpLater =>
      'Vous pourrez créer un compte plus tard depuis les réglages.';

  @override
  String get authResetYourPassword => 'Réinitialiser votre mot de passe';

  @override
  String get authResetEmailBlurb =>
      'Nous vous enverrons un lien par e-mail pour en définir un nouveau.';

  @override
  String get authSendLink => 'Envoyer le lien';

  @override
  String get authEnterEmail => 'Saisissez votre adresse e-mail.';

  @override
  String get authInvalidEmail =>
      'Cela ne ressemble pas à une adresse e-mail valide.';

  @override
  String get authEnterPassword => 'Saisissez votre mot de passe.';

  @override
  String get authPasswordTooShort => 'Utilisez au moins 6 caractères.';

  @override
  String get authUseDifferentEmail => 'Utiliser une autre adresse';

  @override
  String get authCheckYourEmail => 'Vérifiez vos e-mails';

  @override
  String authCodeSentTo(int length) {
    return 'Nous avons envoyé un code à $length chiffres à\n';
  }

  @override
  String get authConfirm => 'Confirmer';

  @override
  String authResendIn(int seconds) {
    return 'Renvoyer le code dans $seconds s';
  }

  @override
  String get authSendNewCode => 'Envoyer un nouveau code';

  @override
  String get authCodeExpiryNote =>
      'Le code expire au bout d\'une heure. Vérifiez vos spams s\'il n\'est pas arrivé.';

  @override
  String get authChooseNewPassword => 'Choisissez un nouveau mot de passe';

  @override
  String get authNewPasswordBlurb =>
      'Il remplace l\'ancien partout. Vous resterez connecté sur cet appareil.';

  @override
  String get authNewPassword => 'Nouveau mot de passe';

  @override
  String get authConfirmPassword => 'Confirmer le mot de passe';

  @override
  String get authTypeItAgain => 'Saisissez-le à nouveau';

  @override
  String get authEnterNewPassword => 'Saisissez un nouveau mot de passe.';

  @override
  String get authPasswordsDoNotMatch => 'Ils ne correspondent pas.';

  @override
  String get authSavePassword => 'Enregistrer le mot de passe';

  @override
  String get authAccountCreatedWithProgress =>
      'Compte créé. Tout ce que vous avez collecté y est désormais enregistré.';

  @override
  String get authAccountCreated => 'Compte créé.';

  @override
  String get authCodeAcceptedChoosePassword =>
      'Code accepté. Choisissez un nouveau mot de passe.';

  @override
  String get authEmailConfirmed => 'E-mail confirmé. Votre compte est prêt.';

  @override
  String authNewCodeSent(String email) {
    return 'Un nouveau code est en route vers $email.';
  }

  @override
  String get authWelcomeBackNotice => 'Bon retour.';

  @override
  String get authPasswordUpdated =>
      'Mot de passe mis à jour. Vous êtes connecté.';

  @override
  String get authErrorNetwork =>
      'Impossible de joindre le serveur. Vérifiez votre connexion et réessayez.';

  @override
  String get authErrorEmailNotSending =>
      'Nous n\'avons pas pu envoyer votre code — l\'envoi d\'e-mails ne fonctionne pas actuellement. Cela vient de chez nous ; réessayez dans quelques minutes.';

  @override
  String get authErrorBadCredentials =>
      'Cet e-mail et ce mot de passe ne correspondent à aucun compte.';

  @override
  String get authErrorAlreadyRegistered =>
      'Cet e-mail a déjà un compte. Essayez plutôt de vous connecter.';

  @override
  String get authErrorPasswordTooShort =>
      'Les mots de passe doivent faire au moins 6 caractères.';

  @override
  String get authErrorTooManyAttempts =>
      'Trop de tentatives. Attendez une minute et réessayez.';

  @override
  String get authErrorCodeExpired =>
      'Ce code a expiré. Demandez-en un nouveau.';

  @override
  String get authErrorCodeInvalid =>
      'Ce code n\'est pas correct. Vérifiez l\'e-mail et réessayez.';

  @override
  String get authErrorGeneric => 'Un problème est survenu. Réessayez.';

  @override
  String get authAnonymousSignInFailed => 'Échec de la connexion anonyme';

  @override
  String get onboardingGetStarted => 'Commencer';

  @override
  String get onboardingIllustration => 'Illustration';

  @override
  String onboardingPageOf(int index, int count) {
    return 'Page $index sur $count';
  }

  @override
  String get onboardingWelcomeTitle => 'Voici Massar';

  @override
  String get onboardingWelcomeBody =>
      'Planifiez où aller, trouvez quoi y faire une fois sur place, et rapportez-en un morceau chez vous.';

  @override
  String get onboardingRoutesTitle => 'Un itinéraire à votre mesure';

  @override
  String get onboardingRoutesBody =>
      'Choisissez une ville, dites ce dont vous avez envie, et recevez un plan qui tient dans votre journée — avec une petite tâche à chaque étape.';

  @override
  String get onboardingCaptureTitle =>
      'Attrapez des fennecs, gardez des souvenirs';

  @override
  String get onboardingCaptureBody =>
      'Levez votre appareil photo pour trouver les fennecs cachés à vos étapes — et pour scanner de vrais objets en souvenirs 3D dans votre dossier.';

  @override
  String get onboardingRewardsTitle =>
      'Transformez vos points en quelque chose de réel';

  @override
  String get onboardingRewardsBody =>
      'Dépensez ce que vous gagnez en récompenses offertes par les lieux rencontrés en chemin.';

  @override
  String get detailAskTheAi => 'DEMANDER À L\'IA';

  @override
  String get detailBestTimeToVisit => 'Meilleur moment pour visiter ?';

  @override
  String get detailHowLongToExplore => 'Combien de temps pour explorer ?';

  @override
  String get detailAskAnything =>
      'Posez n\'importe quelle question sur ce lieu...';

  @override
  String get detailSkipThisSpot => 'Passer ce lieu';

  @override
  String get detailAddToRoute => 'Ajouter à l\'itinéraire';

  @override
  String get detailGuideUnreachable =>
      'Désolé, je n\'ai pas pu joindre le guide pour le moment — réessayez.';

  @override
  String get offlineBackOnline => 'De retour en ligne — synchronisation…';

  @override
  String offlinePendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hors ligne — $count éléments seront synchronisés une fois en ligne',
      one: 'Hors ligne — $count élément sera synchronisé une fois en ligne',
    );
    return '$_temp0';
  }

  @override
  String get offlineProgressSaved =>
      'Hors ligne — votre progression est enregistrée';

  @override
  String get backendConnected => 'Connecté au serveur';

  @override
  String get backendUnreachable =>
      'Serveur injoignable — affichage des données de démonstration';

  @override
  String get routeErrorUnreachable =>
      'Impossible de joindre le service d\'itinéraires.';

  @override
  String get routeErrorCityNotAvailable =>
      'Cette ville n\'est pas encore ouverte aux itinéraires.';

  @override
  String get routeErrorNoEligiblePois =>
      'Aucune étape publiée ne correspond à ce thème ici pour l\'instant.';

  @override
  String get routeErrorTimeBudgetTooShort =>
      'Ce temps est trop court pour la moindre étape ici.';

  @override
  String get routeErrorProviderUnavailable =>
      'Le service de calcul d\'itinéraires est indisponible pour le moment.';

  @override
  String get routeErrorNotImplemented =>
      'La génération d\'itinéraires n\'est pas encore en place sur ce serveur.';

  @override
  String get routeErrorGeneric =>
      'Un problème est survenu lors de la génération de votre itinéraire.';

  @override
  String get routeErrorDropStopsFailed =>
      'Impossible d\'écarter ces étapes — affichage de l\'itinéraire tel que généré.';

  @override
  String get routeErrorBelowBudget =>
      'La retirer laisserait moins de temps que ce que vous avez demandé.';

  @override
  String get routeErrorRemoveStopFailed =>
      'Impossible de retirer cette étape — réessayez.';

  @override
  String get notifChannelRoutesName => 'Itinéraires et modèles';

  @override
  String get notifChannelRoutesDescription =>
      'Quand un itinéraire est prêt, ou qu\'une capture 3D est terminée.';

  @override
  String get notifChannelHuntName => 'Chasse au fennec';

  @override
  String get notifChannelHuntDescription =>
      'Quand vous approchez d\'un fennec caché.';

  @override
  String get notifRouteReadyTitle => 'Votre itinéraire est prêt';

  @override
  String get notifRouteReadyBody => 'Touchez pour voir où vous allez.';

  @override
  String notifRouteReadyBodyNamed(String title) {
    return '$title est planifié et vous attend.';
  }

  @override
  String get notifModelReadyTitle => 'Votre modèle 3D est prêt';

  @override
  String get notifModelFailedTitle => 'Cette capture n\'a pas abouti';

  @override
  String get notifModelReadyBody => 'Touchez pour le voir dans votre dossier.';

  @override
  String get notifModelFailNoSubject =>
      'Nous n\'avons pas trouvé d\'objet net — essayez d\'en remplir davantage le cadre.';

  @override
  String get notifModelFailTimeout =>
      'La construction a pris trop de temps. Touchez pour réessayer avec cette photo.';

  @override
  String get notifModelFailQuota =>
      'Vous avez utilisé tous vos crédits de modèles pour aujourd\'hui.';

  @override
  String get notifModelFailGeneric =>
      'Un problème est survenu pendant la construction. Touchez pour réessayer.';

  @override
  String get notifMascotHereTitle => 'Un fennec est juste là !';

  @override
  String get notifMascotWarmTitle => 'Ça se réchauffe';

  @override
  String get notifMascotHereBody =>
      'Touchez pour ouvrir l\'appareil photo et l\'attraper.';

  @override
  String get notifMascotNearbyBody => 'Un fennec se cache tout près.';

  @override
  String notifMascotNearbyBodyNamed(String stopName) {
    return 'Un fennec se cache près de $stopName.';
  }

  @override
  String get settingsSplatReady => 'Scènes 3D issues de vos vidéos';

  @override
  String get settingsSplatReadySubtitle =>
      'Quand une vidéo que vous avez filmée devient une scène où se promener';

  @override
  String get notifInboxTitle => 'Notifications';

  @override
  String notifInboxUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notifications, $count non lues',
      one: 'Notifications, 1 non lue',
    );
    return '$_temp0';
  }

  @override
  String get notifInboxEmptyTitle => 'Rien pour l\'instant';

  @override
  String get notifInboxEmptyBody =>
      'Quand un itinéraire est prêt, qu\'une capture devient un modèle 3D ou que vos vidéos aident à construire une scène, cela apparaîtra ici.';

  @override
  String get notifInboxClearAll => 'Tout effacer';

  @override
  String get notifInboxClearTitle => 'Effacer toutes les notifications ?';

  @override
  String get notifInboxClearBody =>
      'Elles seront supprimées définitivement. Ce vers quoi elles pointent — un itinéraire, un modèle, une scène — reste en place.';

  @override
  String get notifInboxClearConfirm => 'Tout effacer';

  @override
  String get notifInboxDelete => 'Supprimer';

  @override
  String get notifInboxDeleteFailed =>
      'Impossible de supprimer pour le moment. Réessayez dès que vous serez de nouveau en ligne.';

  @override
  String get notifInboxNothingToOpen =>
      'Il n\'y a plus rien à ouvrir pour celle-ci.';

  @override
  String get timeJustNow => 'à l\'instant';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count min',
      one: 'il y a 1 min',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count heures',
      one: 'il y a 1 heure',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count jours',
      one: 'hier',
    );
    return '$_temp0';
  }

  @override
  String get splatViewerSubtitle => 'Construite à partir de vos vidéos';

  @override
  String get splatViewerHint =>
      'Faites glisser pour regarder · pincez pour zoomer · double-tapez pour réinitialiser';

  @override
  String get splatViewerOpening => 'Ouverture de la scène…';

  @override
  String get splatViewerDownloading => 'Téléchargement de la scène…';

  @override
  String get splatViewerFailed => 'Impossible d\'ouvrir la scène';

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

    return '$shownString gaussiennes sur $trainedString';
  }

  @override
  String get splatDetailLow => 'Fluide';

  @override
  String get splatDetailMedium => 'Équilibré';

  @override
  String get splatDetailHigh => 'Détaillé';

  @override
  String splatDetailSemantic(String level) {
    return 'Détail : $level';
  }
}
