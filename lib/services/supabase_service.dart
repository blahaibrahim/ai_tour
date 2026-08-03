import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Initializes and exposes the Supabase client with secure session storage.
///
/// Call [SupabaseService.initialize] once from main() before runApp.
/// Everywhere else use [supabase] or [Supabase.instance.client] directly.
class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    final url = AppConfig.supabaseUrl;
    final key = AppConfig.supabaseAnonKey;
    await Supabase.initialize(
      url: url,
      anonKey: key,
      authOptions: FlutterAuthClientOptions(
        // Stores the session in platform keychain / keystore instead of
        // SharedPreferences (plain XML on Android). Per doc 01 requirements.
        localStorage: _SecureStorage(),
        autoRefreshToken: true,
      ),
    );
  }

  /// Convenience accessor — identical to Supabase.instance.client.
  static SupabaseClient get client => Supabase.instance.client;
}

/// Wraps flutter_secure_storage to implement LocalStorage for supabase_flutter.
class _SecureStorage implements LocalStorage {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _key = 'supabase_session_v2';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async {
    return await _storage.read(key: _key);
  }

  @override
  Future<bool> hasAccessToken() async => await _storage.containsKey(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
