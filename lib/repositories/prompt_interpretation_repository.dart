import '../services/api_client.dart';
import '../services/backend_monitor.dart';

/// What a free-text prompt was understood to mean.
class PromptInterpretation {
  const PromptInterpretation({
    this.themeKey,
    this.categoryKeys = const {},
    this.understood = false,
  });

  /// The theme the prompt maps to, or null if nothing matched — in which case
  /// the caller should keep whatever theme was already selected rather than
  /// clearing the request.
  final String? themeKey;

  /// Categories the prompt called out — a ranking preference the server
  /// biases stop selection with, never a hard filter. "Show me beaches" means
  /// beach-like stops sort to the top and survive a tight budget first, not
  /// that every non-beach stop in the theme becomes invisible; the server's
  /// `poiSelector` only ever narrows on `RouteRequest.categoryKeys`, the
  /// separate hard filter the (currently unused) category chips would send.
  /// See `preferredCategoryKeys` on `RouteRepository.generateRoute`.
  final Set<String> categoryKeys;

  /// True once at least one real theme or category was found in the prompt.
  /// False covers both "nothing recognisable was said" and "the interpreter
  /// couldn't be reached" — from the traveller's side these are the same
  /// outcome: nothing was narrowed, and the route still generates from
  /// whatever theme is already selected.
  final bool understood;
}

/// Turns what the traveller typed into a theme plus preferred categories, via
/// `POST /api/routes/interpret` — an LLM (Groq) call grounded against the
/// requested city's real theme and category vocabulary
/// (`backend/server-node/src/routeGeneration/domain/promptInterpreter.ts`).
///
/// Two guarantees the server enforces, not this file:
///
///   * **Every category key returned is real and answerable in this city.**
///     The server only offers the model categories with at least one
///     published POI behind them (`categories_available`), and drops
///     anything hallucinated before it ever reaches this response.
///   * **No match is a valid answer.** An unparseable prompt or a Groq outage
///     both come back as `understood: false` with the theme left untouched —
///     never a guess dressed up as a real read.
class PromptInterpretationRepository {
  const PromptInterpretationRepository._();

  /// Interprets [prompt] for [cityId] — the city decides which theme and
  /// category vocabulary the server grounds the model against, so this must
  /// not be called before a city is resolved.
  static Future<PromptInterpretation> interpret({
    required String prompt,
    required String cityId,
    String locale = 'en',
  }) async {
    final text = prompt.trim();
    if (text.isEmpty) return const PromptInterpretation();

    try {
      final data = await ApiClient.post('/api/routes/interpret', body: {
        'prompt': text,
        'city_id': cityId,
        'locale': locale,
      });
      return PromptInterpretation(
        themeKey: data['theme'] as String?,
        categoryKeys: (data['category_keys'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toSet(),
        understood: data['understood'] as bool? ?? false,
      );
    } catch (e) {
      // The backend being unreachable is not a failure to explain — it is
      // the same "nothing narrowed" outcome as a prompt with nothing
      // recognisable in it. Anything else (a real 4xx/5xx from a reachable
      // server) is a bug worth surfacing rather than swallowing.
      if ((e is ApiException && e.isTransport) || isConnectivityError(e)) {
        return const PromptInterpretation();
      }
      rethrow;
    }
  }
}
