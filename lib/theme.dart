import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Sahara Modern" — a warm, editorial palette built for a North-Africa
/// travel app: sun-baked terracotta, warm paper neutrals, a muted teal for
/// quiet accents. Rounded, soft-shadowed, restrained.
class AppTheme {
  // Core palette
  static const Color bg = Color(0xFFFAF6F0); // warm paper background
  static const Color surface = Color(0xFFFFFFFF); // card surface
  static const Color surfaceAlt = Color(0xFFF2EBE0); // sunken fill (inputs, chips)
  static const Color ink = Color(0xFF2B241E); // warm near-black
  static const Color text = ink;
  static const Color textSecondary = Color(0xFF8C8175); // warm grey
  static const Color divider = Color(0xFFE8E0D2); // hairline border

  static const Color accent = Color(0xFFC1602C); // terracotta — primary CTA
  static const Color accentDark = Color(0xFF9C4B21); // pressed state
  static const Color accentSoft = Color(0xFFF3DCC5); // tint bg for chips/selection
  static const Color onAccent = Color(0xFFFFF8F1); // text/icon on accent fill

  static const Color teal = Color(0xFF3E6B62); // secondary accent, used sparingly
  static const Color tealSoft = Color(0xFFDEEAE5); // soft teal tint bg

  static const Color success = Color(0xFF3F8F5F);

  // Legacy aliases (kept so existing call sites don't need renaming)
  static const Color primary = bg;
  static const Color secondary = Color(0xFFD6CBBB); // muted line/rule color
  static const Color tertiary = ink; // dark chip / nav background
  static const Color neutral = accent;
  static const Color surfaceSky = tealSoft;
  static const Color accentSky = accentSoft;
  static const Color steelGrey = Color(0xFF6B6055);
  static const Color neutral100 = Color(0xFFF1EAE0);
  static const Color neutral300 = Color(0xFFD8CFC1);
  static const Color neutral400 = Color(0xFFB2A594);
  static const Color neutral900 = Color(0xFF1C1712);
  static const Color accent100 = accentSoft;
  static const Color accent700 = accentDark;
  static const Color accent800 = Color(0xFF7A3A19);
  static const Color accent2700 = success;

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

  // Soft, warm-tinted elevation — no hard black shadows
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
      bodySmall: GoogleFonts.inter(color: steelGrey, fontWeight: FontWeight.w500, letterSpacing: 0.1),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        primary: accent,
        secondary: teal,
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
          disabledBackgroundColor: neutral300,
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
