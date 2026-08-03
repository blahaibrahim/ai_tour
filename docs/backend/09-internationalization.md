# 09 — Internationalization

> **Status: Not started.** No ARB files, no RTL work, no Flutter changes.
> Worth flagging: the new backend (docs 02, 08, 12) hardcodes `locale='en'`
> throughout — `location_translations`/`location_task_translations` support
> multiple locales in schema, but only English rows exist, and the LLM
> endpoints don't yet accept a locale parameter. Everything below is still
> plan.

## Target languages

The app's content is Algerian heritage — the Casbah, Constantine, Djemila,
Timgad, Tassili. That determines the language set:

| Locale | Language | Direction | Priority |
| --- | --- | --- | --- |
| `ar` | Arabic (Modern Standard) | **RTL** | Official language; largest domestic audience |
| `fr` | French | LTR | Widely used in Algeria; large tourist audience |
| `en` | English | LTR | Current default; international tourists |

Arabic is not a nice-to-have here — it's the first language of the market the
app is about, and it brings RTL with it. Build for RTL from the start; retrofitting
it is materially harder than including it.

## Two distinct problems

**UI strings** — buttons, labels, errors. Live in the app, translated at build
time, must work offline.

**Content** — location names, blurbs, task labels, AI responses. Live in the
database, translated once, fetched per locale.

They need different mechanisms. Conflating them is the usual mistake.

---

## Part 1 — UI strings

### Setup

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: any

flutter:
  generate: true
```

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

```
lib/l10n/
  app_en.arb      # template — the one you edit
  app_fr.arb
  app_ar.arb
```

```dart
MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: state.locale,          // null → follow the device
  ...
)
```

### Extraction

There are ~20 literal `Text('…')` calls across `lib/screens/`, plus strings in
widgets and snackbars. Small enough to do by hand in an afternoon, which is
lucky — the automated extractors are all mediocre.

Sources to sweep:

- `lib/screens/settings/settings_screen.dart` — every section header and tile
  title (lines 27–64)
- `lib/screens/ar_hunt/ar_hunt_screen.dart:604-610` — the capture snackbars
- `AppState.thinkingMessages` (`app_state.dart:86`) — six strings, and they're
  the most personality-carrying copy in the app; translate them with care
- `lib/models/location_data.dart` — **not** here; this is content, see Part 2

### ARB conventions

```json
{
  "@@locale": "en",
  "leaveTour": "Leave Current Tour",
  "@leaveTour": {
    "description": "Destructive settings action that abandons the active tour"
  },
  "pointsEarned": "{count, plural, =0{No points yet} =1{1 point} other{{count} points}}",
  "@pointsEarned": {
    "placeholders": { "count": { "type": "int" } }
  },
  "distanceKm": "{value} km",
  "@distanceKm": {
    "placeholders": { "value": { "type": "int", "format": "decimalPattern" } }
  }
}
```

Three rules that prevent most i18n bugs:

1. **Never concatenate.** `'$count points'` breaks in languages with different
   plural rules. Arabic has six plural forms (`zero`, `one`, `two`, `few`,
   `many`, `other`) — ICU plural syntax handles this; string interpolation
   cannot.
2. **Always write `description`.** A translator seeing `"leave"` with no
   context cannot know if it's a verb or a noun.
3. **Format numbers and dates through `intl`.** Arabic may render
   Eastern Arabic numerals (٠١٢٣) depending on locale conventions; hardcoded
   `'$n km'` won't. `Location.distanceLabel` in
   `lib/models/location.dart:64` builds its string manually — it needs to move
   to `NumberFormat`.

### RTL

Flutter handles most of this if the code is written directionally rather than
physically.

**Audit these across the codebase:**

```dart
// Wrong — physical
EdgeInsets.only(left: 16, right: 8)
Alignment.centerLeft
Positioned(left: 12, ...)
Icons.arrow_back
BorderRadius.only(topLeft: ...)

// Right — directional
EdgeInsetsDirectional.only(start: 16, end: 8)
AlignmentDirectional.centerStart
PositionedDirectional(start: 12, ...)
Icons.arrow_back  // Flutter auto-flips this one; Icons.chevron_right does NOT
BorderRadiusDirectional.only(topStart: ...)
```

`lib/screens/settings/settings_screen.dart:123` uses `Icons.chevron_right` as a
disclosure indicator. In RTL it must point left. `Directionality.of(context)`
or `Transform.flip` — but the cleanest fix is
`Icons.chevron_right` wrapped so it mirrors, or use `Icons.arrow_forward_ios`
which Flutter's icon-mirroring handles.

**What must NOT flip:**

- The **map** (`lib/screens/map/map_screen.dart`) — geography is not
  directional. Wrap `FlutterMap` in `Directionality(textDirection: TextDirection.ltr, ...)`.
- The **compass spinner** (`lib/widgets/compass_spinner.dart`) — a compass that
  spins backwards is wrong.
- The **3D cube** and AR views — world space, not layout space.
- **Swipe gesture semantics** (`lib/screens/swipe/`) — this one is a judgement
  call. Physical right-swipe-to-accept is a learned convention from dating apps
  that Arabic users know equally well. **Recommendation: don't flip it.** But
  do flip the accompanying arrow icons and the progress bar direction.

Test with `flutter run --dart-define=flutter.locale=ar` and by forcing
`Directionality` in widget tests.

### Fonts

`lib/theme.dart:90-91` uses Plus Jakarta Sans and Inter via `google_fonts`.
Neither covers Arabic script. Without a fallback, Arabic renders as tofu boxes.

```dart
static TextTheme textThemeFor(Locale locale) {
  final isArabic = locale.languageCode == 'ar';
  final body = isArabic
      ? GoogleFonts.notoSansArabicTextTheme()   // or Cairo, or Tajawal
      : GoogleFonts.interTextTheme();
  ...
}
```

**Cairo** and **Tajawal** are good geometric Arabic faces that sit reasonably
next to Plus Jakarta Sans. **Noto Sans Arabic** is the safe, complete choice.

Two practical notes:

- Arabic text runs taller than Latin at the same point size. Check that
  `swipe_card.dart`, `current_stop_card.dart`, and the nav bar don't clip.
  Increase `height` in the Arabic text theme by roughly 0.15.
- `google_fonts` downloads at runtime by default. That fails offline — which is
  this app's core scenario. **Bundle the font files as assets** and register
  them in `pubspec.yaml` instead. This is worth doing for the Latin faces too.

---

## Part 2 — Content

The translation tables in [02](02-cloud-database-schema.md) —
`location_translations`, `location_task_translations`, `region_translations` —
hold this. `nearby_locations` already takes `p_locale` and falls back to
English via a double left join.

### Translating the seed content

8 locations × (name + blurb) + 8 task labels + 5 region names. Small.

1. Run the English through Gemini or Claude with a prompt that preserves proper
   nouns: *"Maqam Echahid", "Djemila", "Sidi M'Cid" are place names — keep them
   in their conventional Arabic/French forms, don't translate literally.*
2. **Have a native speaker review.** This is heritage content in the country
   it's about; a machine-translated blurb about the Casbah that reads slightly
   off will be noticed immediately by exactly the audience you most want.
3. Commit as `supabase/seed.sql`.

Note that many of these places have established Arabic names that are the
*original* — قصبة الجزائر, مقام الشهيد, جميلة. Reverse-translating the English
gloss would be a mistake. Source the Arabic names properly.

### AI responses

Pass the locale in the system prompt ([08](08-llm-and-ai-features.md)):
`Answer in {locale}.` Gemini and Llama 3.3 both handle Arabic and French well.

Cache AI responses **keyed by locale** — the same question in French and Arabic
are different cache entries.

### User-generated content

Artifact titles the user types stay in whatever language they typed. Don't
translate them. Do store `locale` on the row if you ever want to.

---

## Locale selection and persistence

```
Device locale  ──►  first launch default (if supported, else 'en')
       │
User picks in Settings ──► profiles.locale (cloud) + Preferences (local)
       │
Local value wins on startup so the app renders correctly before any network
```

The settings screen already has the row —
`settings_screen.dart:55` shows `Language / English` with no handler. Wire it
to a picker listing languages **in their own script** (English / Français /
العربية), never translated into the current UI language. A user who
accidentally set Arabic must be able to find their way back.

Changing locale must not require a restart. `MaterialApp.locale` driven from
bloc state handles this, but content already fetched needs a refetch — clear
the catalogue cache on locale change.

---

## Rollout

1. Set up `flutter_localizations`, `l10n.yaml`, `app_en.arb` with every string
   extracted. Ship it — nothing visibly changes, and the codebase is now
   translatable.
2. Add `app_fr.arb`. French is LTR, so this validates the plumbing without RTL
   risk.
3. Directional-widget audit and font fallback. Ship with `ar` behind a flag and
   test hard.
4. Enable `ar`.
5. Content translations into the database.

Doing French before Arabic is deliberate: it separates "does my i18n plumbing
work" from "does my RTL layout work", so you debug one thing at a time.

## Testing checklist

- [ ] Every user-visible string comes from `AppLocalizations` (grep for `Text('`)
- [ ] Arabic plurals correct for 0, 1, 2, 3, 11, 100 points
- [ ] Map does not mirror in RTL; compass rotates correctly
- [ ] Chevrons, back arrows, and the swipe progress bar mirror in RTL
- [ ] No tofu boxes anywhere in Arabic
- [ ] Long German-style compounds and long Arabic strings don't clip cards
- [ ] Locale change takes effect without restart and refetches content
- [ ] Missing Arabic translation falls back to English, not to a blank
- [ ] Fonts render with no network (bundled, not downloaded)
- [ ] `intl` number formatting used for distances and points
