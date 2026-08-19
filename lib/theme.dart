import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Fennec Compass" — the palette is lifted straight off the app icon
/// (assets/icon/app-icon-ios.png): the sleeping fennec's sand-and-cream fur, the
/// brass compass with its deep blue face, and the navy field it sits on.
/// Flat fills only — no gradients anywhere in the app's chrome.
class AppTheme {
  // ---------------------------------------------------------------------
  // Raw colors sampled from the icon
  // ---------------------------------------------------------------------
  /// Compass face — the primary brand color.
  static const Color compassBlue = Color(0xFF2F549A);

  /// The navy field the icon sits on — dark surfaces and headers.
  static const Color deepNavy = Color(0xFF14254A);

  /// Fennec fur — the secondary brand color.
  static const Color sand = Color(0xFFF8D59B);

  /// Compass rim and needle — the warm accent.
  static const Color amber = Color(0xFFEBA664);

  /// Fur highlight / inner ear.
  static const Color cream = Color(0xFFFBE7C4);

  /// The icon's outline stroke.
  static const Color cocoa = Color(0xFF783B1E);

  // ---------------------------------------------------------------------
  // Semantic tokens
  // ---------------------------------------------------------------------
  static const Color bg = Color(0xFFFCF6EC); // cream paper background
  static const Color surface = Color(0xFFFFFFFF); // card surface
  static const Color surfaceAlt = Color(0xFFF3ECDE); // sunken fill (inputs, chips)
  static const Color ink = deepNavy; // near-black, on the blue side
  static const Color text = ink;
  static const Color textSecondary = Color(0xFF6E7A93); // navy-grey
  static const Color divider = Color(0xFFE6DCC9); // hairline border

  static const Color accent = compassBlue; // primary CTA
  static const Color accentDark = Color(0xFF22406F); // pressed state
  static const Color accentSoft = Color(0xFFDEE6F4); // tint bg for chips/selection
  static const Color onAccent = Color(0xFFFFFFFF); // text/icon on accent fill

  /// Secondary accent — used for rewards, highlights, warm emphasis.
  static const Color secondaryAccent = amber;
  static const Color secondarySoft = Color(0xFFFAEBD5); // soft sand tint bg

  /// Text/icon color on top of [deepNavy] panels.
  static const Color onNavy = cream;

  static const Color success = Color(0xFF2F7D5B);
  static const Color error = Color(0xFFC8452F);

  /// Amber rather than red: a route needing a second day is information the
  /// traveller should act on, not a failure. Rendering it in [error] made a
  /// perfectly good route look broken.
  static const Color warning = Color(0xFF9A6212);
  static const Color warningSoft = Color(0xFFFBEEDA);
  static const Color errorSoft = Color(0xFFFAE4E0);
  static const Color successSoft = Color(0xFFDFF0E7);

  // ---------------------------------------------------------------------
  // Route semantics
  // ---------------------------------------------------------------------
  // A route is drive legs between walkable clusters and walk legs inside them.
  // The two modes get their own fixed colors so the map polyline, the leg row
  // in the itinerary and the summary chips all agree — the mode is the same
  // fact in three places, and it should not be three different blues.

  /// Inter-cluster travel. The heavier of the two, because it is the part of
  /// the route you cannot do on foot.
  static const Color driveColor = compassBlue;

  /// Travel within a cluster.
  static const Color walkColor = Color(0xFFB5651D);

  /// Scrim laid over photos so overlaid white text stays legible. Fades to
  /// [photoScrimFade] — a transparent navy rather than transparent black, so
  /// the midtones of the fade don't go grey.
  static const Color photoScrim = Color(0xC714254A);
  static const Color photoScrimFade = Color(0x0014254A);

  // Legacy alias (kept so existing call sites don't need renaming)
  static const Color primary = bg;

  // Corner radii — the app's rounded, soft-edged shape language
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  static BorderRadius get brSm => BorderRadius.circular(radiusSm);
  static BorderRadius get brMd => BorderRadius.circular(radiusMd);
  static BorderRadius get brLg => BorderRadius.circular(radiusLg);
  static BorderRadius get brXl => BorderRadius.circular(radiusXl);
  static BorderRadius get brPill => BorderRadius.circular(radiusPill);

  // ---------------------------------------------------------------------
  // Spacing — a 4pt scale
  // ---------------------------------------------------------------------
  // Gaps were previously written as literals at every call site, which is how
  // 10/12/14/16/18/20/26 all ended up in use for the same visual step. Naming
  // the rungs is what makes vertical rhythm reviewable.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  static const SizedBox gap1 = SizedBox(height: space1, width: space1);
  static const SizedBox gap2 = SizedBox(height: space2, width: space2);
  static const SizedBox gap3 = SizedBox(height: space3, width: space3);
  static const SizedBox gap4 = SizedBox(height: space4, width: space4);
  static const SizedBox gap5 = SizedBox(height: space5, width: space5);
  static const SizedBox gap6 = SizedBox(height: space6, width: space6);

  /// The smallest square a finger can reliably hit. Material and the iOS HIG
  /// both put this at 44-48dp; several of the app's icon buttons were drawn
  /// smaller, so this is the floor to enforce with a `SizedBox`/`constraints`
  /// rather than a number to re-derive.
  static const double minTapTarget = 48;

  // ---------------------------------------------------------------------
  // Motion
  // ---------------------------------------------------------------------
  /// Feedback on a press — must be under a tenth of a second to feel attached
  /// to the finger.
  static const Duration motionFast = Duration(milliseconds: 120);

  /// The default for state changes: chips selecting, panels resizing.
  static const Duration motionBase = Duration(milliseconds: 240);

  /// Screen-level transitions and anything crossing a large distance.
  static const Duration motionSlow = Duration(milliseconds: 420);

  static const Curve motionCurve = Curves.easeOutCubic;

  // Soft, navy-tinted elevation — no hard black shadows
  static List<BoxShadow> get shadowSm => [
        BoxShadow(color: ink.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3)),
      ];
  static List<BoxShadow> get shadowMd => [
        BoxShadow(color: ink.withValues(alpha: 0.09), blurRadius: 20, offset: const Offset(0, 8)),
      ];
  static List<BoxShadow> get shadowLg => [
        BoxShadow(color: ink.withValues(alpha: 0.16), blurRadius: 32, offset: const Offset(0, 12)),
      ];

  /// The Latin-script theme, for the handful of call sites that have no locale
  /// to hand. Anything built under a MaterialApp should prefer [themeFor].
  static ThemeData get theme => themeFor(const Locale('en'));

  /// [locale] picks the typefaces and nothing else — the palette, radii and
  /// shadows are the same in every language.
  ///
  /// Neither Inter nor Plus Jakarta Sans has a single Arabic glyph, so in
  /// Arabic they fall through to whatever the platform substitutes: Noto Naskh
  /// on one phone, Droid Arabic on another, nothing at all on a stripped ROM.
  /// Naming Arabic faces outright is what makes the app look the same on every
  /// device. IBM Plex Sans Arabic is Inter's sibling by construction, and Cairo
  /// carries the same geometric warmth as Plus Jakarta Sans.
  static ThemeData themeFor(Locale locale) {
    final arabic = locale.languageCode == 'ar';
    final displayFont =
        arabic ? GoogleFonts.cairoTextTheme() : GoogleFonts.plusJakartaSansTextTheme();
    final bodyFont =
        arabic ? GoogleFonts.ibmPlexSansArabicTextTheme() : GoogleFonts.interTextTheme();

    TextStyle bodyStyle({Color? color, FontWeight? fontWeight, double? letterSpacing}) =>
        arabic
            ? GoogleFonts.ibmPlexSansArabic(
                color: color, fontWeight: fontWeight, letterSpacing: letterSpacing)
            : GoogleFonts.inter(
                color: color, fontWeight: fontWeight, letterSpacing: letterSpacing);

    TextStyle displayStyle({FontWeight? fontWeight}) => arabic
        ? GoogleFonts.cairo(fontWeight: fontWeight)
        : GoogleFonts.plusJakartaSans(fontWeight: fontWeight);

    final textTheme = bodyFont.copyWith(
      headlineLarge: displayFont.headlineLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: displayFont.headlineMedium?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: displayFont.headlineSmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      bodyLarge: bodyStyle(color: text, fontWeight: FontWeight.w400),
      bodyMedium: bodyStyle(color: text, fontWeight: FontWeight.w400),
      bodySmall: bodyStyle(color: textSecondary, fontWeight: FontWeight.w500, letterSpacing: 0.1),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        primary: accent,
        secondary: secondaryAccent,
        surface: surface,
        onSurface: text,
        error: error,
      ),
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: divider,
          elevation: 0,
          textStyle: displayStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: brLg),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: divider, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: brLg),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: displayStyle(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: brMd),
          textStyle: displayStyle(fontWeight: FontWeight.w600),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: brLg),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: brMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: brMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: brMd,
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: divider,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),

      // Toasts are the app's only transient feedback channel; left to the
      // Material default they arrive as a square black bar that belongs to no
      // part of this palette.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: bodyStyle(color: onNavy, fontWeight: FontWeight.w500),
        actionTextColor: sand,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(space4),
        shape: RoundedRectangleBorder(borderRadius: brMd),
      ),
    );
  }
}
