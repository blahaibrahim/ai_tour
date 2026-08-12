import 'package:flutter/material.dart';

import '../../theme.dart';

/// How a slide stacks its art and its words.
///
/// Six slides built to one template read as one screen that won't advance, no
/// matter how different the copy is. Moving the art between the top, the
/// middle and the bottom is what makes each page land as a new page.
enum OnboardingLayout {
  /// Art, then title, then body. The most conventional, and what the opener
  /// and the two most visual features use.
  artFirst,

  /// Title, then art, then body — the headline leads and the art sits inside
  /// the text block, illustrating the sentence beneath it.
  titleArtBody,

  /// Title and body, then art beneath. Reads as a caption above its picture.
  textFirst,
}

/// One slide of the first-run intro.
///
/// Content lives here rather than inline in the widget so the copy, the art
/// slots and the ordering are all reviewable in one place — and so dropping in
/// the real illustrations later is a change to [artAsset] strings, not a change
/// to layout code.
class OnboardingPageContent {
  const OnboardingPageContent({
    required this.id,
    required this.title,
    required this.body,
    required this.artAsset,
    required this.icon,
    required this.tint,
    required this.layout,
  });

  /// Stable key for the page — used for widget keys and analytics, and never
  /// derived from the index, which shifts whenever a page is inserted.
  final String id;

  final String title;

  /// One sentence, two at the most. This is a poster, not documentation: the
  /// app itself explains the detail at the moment it matters.
  final String body;

  /// Where the artwork for this page will live. Nothing is there yet — see
  /// `assets/onboarding/README.md`; until a file exists at this path the art
  /// slot draws a plain labelled stand-in instead.
  final String artAsset;

  /// Stands in for the artwork until it arrives.
  final IconData icon;

  /// The page's accent, used by the advance button and the progress dots. Two
  /// of the five features are warm (the hunt, the rewards) and the rest are the
  /// app's blue.
  final Color tint;

  final OnboardingLayout layout;
}

/// The intro, in order: a welcome, then one page per thing the app does.
const List<OnboardingPageContent> onboardingPages = [
  OnboardingPageContent(
    id: 'welcome',
    title: 'This is Massar',
    body:
        'Plan where you go, find something to do when you get there, and take a '
        'piece of it home.',
    artAsset: 'assets/onboarding/01_welcome.png',
    icon: Icons.explore_outlined,
    tint: AppTheme.compassBlue,
    layout: OnboardingLayout.artFirst,
  ),
  // The route and its tasks are one page because they are one experience: a
  // route with nothing to do on it is a map, and a task with no route to hang
  // it off is a quiz. Splitting them made slide 3 read as a feature the app
  // had bolted on.
  OnboardingPageContent(
    id: 'routes',
    title: 'A route built around you',
    body:
        'Pick a city, say what you are in the mood for, and get a plan that '
        'fits your day — with a small task waiting at every stop.',
    artAsset: 'assets/onboarding/02_routes_tasks.png',
    icon: Icons.route_outlined,
    tint: AppTheme.compassBlue,
    layout: OnboardingLayout.titleArtBody,
  ),
  // Likewise the hunt and the scanner: both are "raise your camera at the
  // place you are standing in", and the traveller reaches them through the
  // same button.
  OnboardingPageContent(
    id: 'capture',
    title: 'Catch fennecs, keep souvenirs',
    body:
        'Raise your camera to find the fennecs hiding at your stops — and to '
        'scan real objects into 3D souvenirs for your folder.',
    artAsset: 'assets/onboarding/03_camera.png',
    icon: Icons.view_in_ar_outlined,
    tint: AppTheme.amber,
    layout: OnboardingLayout.textFirst,
  ),
  OnboardingPageContent(
    id: 'rewards',
    title: 'Turn your points into something real',
    body: 'Spend what you earn on rewards from the places along the way.',
    artAsset: 'assets/onboarding/04_rewards.png',
    icon: Icons.card_giftcard_outlined,
    tint: AppTheme.amber,
    layout: OnboardingLayout.artFirst,
  ),
];
