import '../models/route.dart';

/// What a free-text prompt was understood to mean.
class PromptInterpretation {
  const PromptInterpretation({
    this.themeKey,
    this.categoryKeys = const {},
  });

  /// The theme the prompt maps to, or null if nothing matched — in which case
  /// the caller should keep whatever theme was already selected rather than
  /// clearing the request.
  final String? themeKey;

  /// Categories to narrow the theme with. May be empty: "somewhere historic"
  /// is a theme with no further narrowing, and inventing one would filter the
  /// catalogue harder than the traveller asked for.
  final Set<String> categoryKeys;

  bool get isEmpty => themeKey == null && categoryKeys.isEmpty;
}

/// Turns what the traveller typed into a theme plus categories.
///
/// **This is a local placeholder, not the real interpreter.** The intended
/// implementation is a server round trip — an LLM given the prompt and the
/// city's actual theme/category vocabulary, returning a structured selection.
/// That endpoint does not exist yet, so this matches keywords instead.
///
/// The seam is deliberate: [interpret] already takes the server-supplied
/// vocabulary rather than a hardcoded list, and is already async, so replacing
/// the body with an `ApiClient.post('/api/interpret', …)` changes nothing above
/// it. Two things the real version must keep:
///
///   * **It may only return keys that exist in the passed vocabulary.** The
///     module selects POIs by category key; a hallucinated key silently
///     matches nothing and produces an empty route, which the traveller reads
///     as "there is nothing here" rather than "the model made that up".
///   * **No match is a valid answer.** Returning an arbitrary theme for an
///     unparseable prompt is worse than returning nothing, because the
///     traveller cannot tell it was a guess.
class PromptInterpretationRepository {
  const PromptInterpretationRepository._();

  /// Keyword → theme. Ordered by specificity: the first theme with a hit wins,
  /// so "ottoman palace food market" reads as history rather than food.
  static const Map<String, List<String>> _themeKeywords = {
    'history': [
      'history', 'historic', 'historical', 'ancient', 'ruin', 'ruins', 'roman',
      'ottoman', 'colonial', 'heritage', 'old town', 'casbah', 'kasbah',
      'medina', 'fort', 'fortress', 'palace', 'war', 'independence', 'archaeo',
    ],
    'culture': [
      'culture', 'cultural', 'art', 'arts', 'museum', 'museums', 'gallery',
      'music', 'craft', 'crafts', 'architecture', 'mosque', 'church',
      'cathedral', 'religious', 'traditional', 'local life',
    ],
    'nature': [
      'nature', 'natural', 'park', 'parks', 'garden', 'gardens', 'green',
      'coast', 'coastal', 'sea', 'beach', 'mountain', 'hike', 'hiking',
      'walk in', 'outdoor', 'view', 'views', 'viewpoint', 'scenic', 'sunset',
    ],
    'food': [
      'food', 'eat', 'eating', 'cuisine', 'restaurant', 'restaurants', 'cafe',
      'coffee', 'street food', 'market', 'markets', 'souk', 'tasting',
      'culinary', 'bakery', 'sweets', 'dinner', 'lunch',
    ],
  };

  /// Keyword → category. Independent of the theme match, because narrowing and
  /// theme are different questions — "museums and viewpoints" is one theme and
  /// two categories.
  static const Map<String, List<String>> _categoryKeywords = {
    'heritage': ['heritage', 'historic', 'ancient', 'ruin', 'ruins', 'palace',
        'fort', 'fortress', 'ottoman', 'roman', 'colonial', 'casbah', 'medina'],
    'religious': ['mosque', 'church', 'cathedral', 'religious', 'shrine',
        'basilica', 'sacred', 'worship'],
    'museum': ['museum', 'museums', 'gallery', 'galleries', 'exhibition',
        'collection', 'art'],
    'viewpoint': ['view', 'views', 'viewpoint', 'viewpoints', 'panorama',
        'scenic', 'overlook', 'sunset', 'skyline', 'rooftop', 'terrace'],
    'market': ['market', 'markets', 'souk', 'bazaar', 'street food', 'shopping',
        'stalls', 'spices'],
  };

  /// Interprets [prompt] against the vocabulary the server actually offers.
  ///
  /// [availableThemes] and [availableCategories] are the live lists from
  /// `/api/categories`, so a theme this file knows about but the server has
  /// retired is never returned.
  static Future<PromptInterpretation> interpret({
    required String prompt,
    required List<RouteTheme> availableThemes,
    required List<RouteCategory> availableCategories,
  }) async {
    final text = prompt.toLowerCase().trim();
    if (text.isEmpty) return const PromptInterpretation();

    // Stands in for the round trip, so the UI's pending state is exercised
    // rather than completing in the same frame and never being seen.
    await Future<void>.delayed(const Duration(milliseconds: 650));

    final themeKeys = {for (final t in availableThemes) t.key};
    final categoryKeys = {for (final c in availableCategories) c.key};

    String? matchedTheme;
    var bestThemeScore = 0;
    for (final entry in _themeKeywords.entries) {
      if (!themeKeys.contains(entry.key)) continue;
      final score = _score(text, entry.value);
      if (score > bestThemeScore) {
        bestThemeScore = score;
        matchedTheme = entry.key;
      }
    }

    final matchedCategories = <String>{};
    for (final entry in _categoryKeywords.entries) {
      if (!categoryKeys.contains(entry.key)) continue;
      if (_score(text, entry.value) > 0) matchedCategories.add(entry.key);
    }

    // Every category matching means the prompt narrowed nothing — "show me
    // everything" phrased at length. Sending them all is the same request as
    // sending none, and the shorter one is easier to read back to the user.
    if (matchedCategories.length == categoryKeys.length) matchedCategories.clear();

    return PromptInterpretation(
      themeKey: matchedTheme,
      categoryKeys: matchedCategories,
    );
  }

  /// Number of distinct keywords present. Counting rather than short-circuiting
  /// on the first hit is what lets a prompt mentioning several history words
  /// outrank one that mentions "market" once.
  static int _score(String text, List<String> keywords) {
    var hits = 0;
    for (final keyword in keywords) {
      if (text.contains(keyword)) hits++;
    }
    return hits;
  }
}
