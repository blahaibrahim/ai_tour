import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration loader that reads from the root `.env` file first,
/// falling back to `--dart-define` build-time environment variables.
class AppConfig {
  AppConfig._();

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Degrades gracefully if .env is missing (e.g. CI build with --dart-define)
    }
  }

  static String get supabaseUrl {
    final fromDotenv = dotenv.maybeGet('SUPABASE_URL');
    if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv.trim();
    return const String.fromEnvironment('SUPABASE_URL').trim();
  }

  static String get supabaseAnonKey {
    final fromDotenv = dotenv.maybeGet('SUPABASE_ANON_KEY');
    if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv.trim();
    return const String.fromEnvironment('SUPABASE_ANON_KEY').trim();
  }

  static String get apiBaseUrl {
    final fromDotenv = dotenv.maybeGet('API_BASE_URL');
    if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv;
    return const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
  }

  /// Whether the AR mascot hunt spawns near the device's own position instead
  /// of a route stop's real coordinates.
  ///
  /// There is no way to get near the pilot city's actual POIs during ordinary
  /// development, so this defaults on: it lets the whole hunt loop (§5.3–§5.5
  /// of the AR capture plan) be exercised by walking around wherever the
  /// tester actually is. Flip off with `AR_TESTING_MODE=false` in `.env` — or
  /// toggle it live from Settings — once real POIs are reachable.
  static bool get arTestingMode {
    final fromDotenv = dotenv.maybeGet('AR_TESTING_MODE');
    if (fromDotenv != null && fromDotenv.isNotEmpty) {
      return fromDotenv.trim().toLowerCase() != 'false';
    }
    return const String.fromEnvironment('AR_TESTING_MODE', defaultValue: 'true')
            .toLowerCase() !=
        'false';
  }
}
