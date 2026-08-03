# 10 — Theming: Light & Dark

> **Status: Not started.** No Flutter changes. Everything below is still plan.

## The obstacle

`lib/theme.dart` is a class of `static const Color` fields, and there are **224
references to `AppTheme.` across 34 files**. A static const cannot change at
runtime. Dark mode is therefore not a toggle you add — it's a migration of
every one of those references.

```dart
// Today — resolved at compile time, same value forever
static const Color bg = Color(0xFFFCF6EC);
...
color: AppTheme.surfaceAlt          // settings_screen.dart:96
```

Two paths out. Pick one and commit; mixing them is worse than either.

---

## Option A — `ThemeExtension` (recommended)

Flutter's supported mechanism. Colors live in a `ThemeExtension` resolved from
`BuildContext`, so `MaterialApp` swaps the whole palette when brightness
changes, with free lerping during the transition.

```dart
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg, required this.surface, required this.surfaceAlt,
    required this.ink, required this.textSecondary, required this.divider,
    required this.accent, required this.accentDark, required this.accentSoft,
    required this.onAccent, required this.secondaryAccent, required this.secondarySoft,
    required this.onNavy, required this.success, required this.error,
    required this.photoScrim, required this.photoScrimFade,
  });

  final Color bg, surface, surfaceAlt, ink, textSecondary, divider;
  final Color accent, accentDark, accentSoft, onAccent;
  final Color secondaryAccent, secondarySoft, onNavy, success, error;
  final Color photoScrim, photoScrimFade;

  static const light = AppColors(
    bg: Color(0xFFFCF6EC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF3ECDE),
    ink: Color(0xFF14254A),
    // … exactly the values in theme.dart today
  );

  static const dark = AppColors(/* see palette below */);

  @override AppColors copyWith({Color? bg, /* … */}) => AppColors(/* … */);

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      // … one line per field
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
```

```dart
MaterialApp(
  theme: AppTheme.light,        // .. extensions: [AppColors.light]
  darkTheme: AppTheme.dark,     // .. extensions: [AppColors.dark]
  themeMode: state.themeMode,   // system | light | dark
)
```

Call sites become:

```dart
- color: AppTheme.surfaceAlt
+ color: context.colors.surfaceAlt
```

`copyWith` and `lerp` are tedious to hand-write for 17 fields. `theme_tailor`
generates both from an annotated class if you'd rather not.

### Migration is mostly mechanical

```bash
# One token at a time, verifying as you go
rg -l 'AppTheme\.surfaceAlt' lib | xargs sed -i 's/AppTheme\.surfaceAlt/context.colors.surfaceAlt/g'
```

Two categories won't convert automatically and need hand attention:

**`const` constructors.** `context.colors.x` isn't const, so any widget built
with `const` and a theme color breaks. Drop the `const`. This is a small
rebuild-cost regression and it is not worth fighting.

**No `BuildContext` in scope.** `AppTheme.shadowSm`, `brLg`, and the radius
constants are context-free — **leave those as statics**. Radii and shadow
geometry don't change between themes. Only *colors* move; shadow *opacity*
might, so parameterize `shadowSm(context)` if the dark palette needs a
different value.

Do the migration token by token, not file by file. `rg -c 'AppTheme\.' lib`
should go monotonically to near zero, and you can stop and ship at any point.

---

## Option B — `InheritedWidget`

Roll your own palette provider. Slightly less boilerplate than `ThemeExtension`
(no `lerp`), but you lose the free cross-fade, and you're outside what other
Flutter developers expect. Only worth it if you want something `ThemeExtension`
can't express.

**Recommendation: Option A.**

---

## The dark palette

`lib/theme.dart` documents its own origin: colors sampled from the app icon —
compass blue `#2F549A`, deep navy `#14254A`, fennec sand `#F8D59B`, amber
`#EBA664`, cream `#FBE7C4`. The comment says "flat fills only — no gradients
anywhere in the app's chrome."

**Do not invert the light theme.** Inverting `#FCF6EC` gives `#030913`, a
near-black with a green cast that has nothing to do with the fennec or the
compass. The dark theme should come from the same icon — specifically, from the
navy field the icon already sits on. That's the whole point of having sampled a
palette in the first place.

```dart
static const dark = AppColors(
  // The navy field, darkened — the icon's own ground
  bg:         Color(0xFF0D172E),
  surface:    Color(0xFF152744),   // cards lift toward the compass face
  surfaceAlt: Color(0xFF1D3255),   // sunken fills, inputs, chips

  ink:           Color(0xFFF3E9D8), // cream, not white — matches `onNavy`
  textSecondary: Color(0xFF9CAAC6), // the light theme's navy-grey, lightened
  divider:       Color(0xFF27385C),

  // Compass blue is too dark to read on navy. Lift it toward the rim.
  accent:      Color(0xFF6C93DC),
  accentDark:  Color(0xFF8FB0E8),   // "pressed" = brighter in the dark
  accentSoft:  Color(0xFF1E3560),
  onAccent:    Color(0xFF0B1223),   // dark text on a light accent

  // Sand and amber already work on navy — that's how the icon is built
  secondaryAccent: Color(0xFFEBA664),
  secondarySoft:   Color(0xFF3A2A1B),
  onNavy:          Color(0xFFFBE7C4),

  success: Color(0xFF5FBF92),
  error:   Color(0xFFF07A63),

  photoScrim:     Color(0xE00D172E),
  photoScrimFade: Color(0x000D172E),
);
```

Four things this palette does deliberately:

1. **Surfaces get lighter as they come forward.** In dark themes, elevation is
   expressed with lightness, not shadow — a raised card with a drop shadow on a
   dark ground reads as a hole, not a lift. The existing `shadowSm/Md/Lg` need
   their opacity dropped substantially or replaced with a subtle border in dark
   mode.
2. **`accentDark` gets *lighter*.** The light theme's pressed state darkens
   `#2F549A` → `#22406F`. On a dark ground, darkening reads as *disabled*.
   Pressed states must brighten.
3. **Text is cream, not white.** `#FFFFFF` on navy is harsh and it abandons the
   palette. The theme already has the right color — `onNavy: cream` — for
   exactly this situation.
4. **Sand and amber are unchanged.** They were sampled from a fennec sitting on
   navy. They already have the contrast.

### Contrast

Check every text/background pair against WCAG AA — 4.5:1 for body, 3:1 for
large text and UI boundaries. The pairs most likely to fail:

- `textSecondary` on `surfaceAlt` (both mid-tone in both themes)
- `accent` on `bg` in **light** mode — `#2F549A` on `#FCF6EC` is fine for text
  but check it as a UI boundary
- `secondaryAccent` (amber) on `surface` in light mode — warm on cream is the
  classic failure

Automate it: a unit test that asserts a minimum contrast ratio for every
declared pair. It runs in milliseconds and catches regressions when someone
tweaks a hex value.

---

## Photo scrims

`photoScrim` (`theme.dart:59`) is a transparent navy laid over photos so white
text stays legible — a good detail. In dark mode it needs to be *stronger*, not
weaker: dark UI makes users expect a dim screen, so they run lower brightness,
and a bright photo behind text is more jarring by contrast.

The swipe card (`lib/screens/swipe/widgets/swipe_card.dart`) and the overview
cards are the surfaces to check. `net_image` content is arbitrary, so the scrim
is the only thing guaranteeing legibility.

---

## The backdrop

`lib/widgets/app_backdrop.dart` and `lib/widgets/noise_texture.dart` render the
animated background (commit `f16c4d0`). Both need dark variants. Two notes:

- Noise/grain that reads as subtle texture on cream can read as **compression
  artifacts** on navy. Reduce the opacity in dark mode, don't just recolor it.
- If the backdrop paints with a `Shader` or hardcoded `Color` values inside a
  `CustomPainter`, those won't be caught by the `AppTheme.` grep. Search
  specifically for `Color(0x` literals across `lib/widgets/`.

---

## System integration

```dart
SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
  statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
  systemNavigationBarColor: colors.bg,
  systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
));
```

`lib/app/app_shell.dart` uses `extendBodyBehindAppBar` with white icon theming
(`settings_screen.dart:19`) — that's hardcoded for the current dark-navy
header and will need to follow the theme.

Also check the **AR screens**. `ar_hunt_screen.dart` overlays UI on a camera
feed, which is neither light nor dark. Those overlays should stay
scrim-on-white regardless of theme — the camera feed is the background, not
your surface.

---

## Persistence

Preference order at startup:

```
Preferences table (local, instant)  →  profiles.theme_mode (cloud, syncs)  →  system
```

The local read must be synchronous-ish and happen before the first frame, or
users see a flash of the wrong theme on every cold start. Read it in `main()`
before `runApp`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final mode = await db.preferences.themeMode();   // defaults to system
  runApp(AITourApp(initialThemeMode: mode));
}
```

Settings UI: a three-way segmented control — System / Light / Dark. Default to
System. It belongs in the PREFERENCES section of
`lib/screens/settings/settings_screen.dart:50`, next to Language.

---

## Sequencing

This is independent of the backend work and can proceed in parallel — nothing
in phases 1–3 blocks it. But do it **before** the i18n string extraction if you
can: both touch the same widget files, and doing them together means one round
of merge conflicts instead of two.

## Testing checklist

- [ ] `rg -c 'AppTheme\.[a-z]' lib` returns only radii and shadow geometry
- [ ] `rg 'Color\(0x' lib/widgets lib/screens` returns only intentional one-offs
- [ ] Toggling theme updates every screen with no restart and no flash
- [ ] Cold start in dark mode shows no light-theme flash
- [ ] Every declared color pair passes WCAG AA (automated test)
- [ ] Pressed and disabled states are distinguishable in both themes
- [ ] Photo-overlaid text is legible on a white-heavy image in both themes
- [ ] Status bar and navigation bar icons are visible in both themes
- [ ] AR overlays remain legible against a bright camera feed in dark mode
- [ ] Backdrop noise doesn't read as artifacting on the dark ground
