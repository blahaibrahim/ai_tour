import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Fennec Compass" — the palette is lifted straight off the app icon
/// (assets/icon/app-icon.png): the sleeping fennec's sand-and-cream fur, the
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

  // Soft, navy-tinted elevation — no hard black shadows
  static List<BoxShadow> get shadowSm => [
        BoxShadow(color: ink.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 3)),
      ];
  static List<BoxShadow> get shadowMd => [
        BoxShadow(color: ink.withOpacity(0.09), blurRadius: 20, offset: const Offset(0, 8)),
      ];
  static List<BoxShadow> get shadowLg => [
        BoxShadow(color: ink.withOpacity(0.16), blurRadius: 32, offset: const Offset(0, 12)),
      ];

  static ThemeData get theme {
    final displayFont = GoogleFonts.plusJakartaSansTextTheme();
    final bodyFont = GoogleFonts.interTextTheme();

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
      bodyLarge: GoogleFonts.inter(color: text, fontWeight: FontWeight.w400),
      bodyMedium: GoogleFonts.inter(color: text, fontWeight: FontWeight.w400),
      bodySmall: GoogleFonts.inter(color: textSecondary, fontWeight: FontWeight.w500, letterSpacing: 0.1),
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
        background: bg,
        onBackground: text,
        onSurface: text,
      ),
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: divider,
          elevation: 0,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
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
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: brMd),
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
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
        overlayColor: accent.withOpacity(0.12),
        trackHeight: 4,
      ),
    );
  }
}
