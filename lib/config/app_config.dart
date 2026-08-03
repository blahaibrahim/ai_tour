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
}
