import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Typed exception carrying the HTTP status code and machine-readable error code.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.errorCode, [this.message]);
  final int statusCode;
  final String errorCode;
  final String? message;

  @override
  String toString() => 'ApiException($statusCode, $errorCode, $message)';
}

/// Low-level HTTP client for the Flask backend.
///
/// Attaches the current Supabase JWT on every request so all routes receive
/// the user's identity — not just /api/models/generate. Routes that don't
/// require auth simply ignore the header.
class ApiClient {
  ApiClient._();

  static final _client = http.Client();

  static Future<Map<String, String>> _headers() async {
    var session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      print("DEBUG [ApiClient] Session is NULL. Attempting to sign in anonymously now...");
      try {
        final res = await Supabase.instance.client.auth.signInAnonymously();
        session = res.session;
        print("DEBUG [ApiClient] Sign in success. Session: ${session != null}");
      } catch (e) {
        print("DEBUG [ApiClient] Anonymous sign-in failed: $e");
      }
    }
    return {
      'Content-Type': 'application/json',
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  /// POST request returning the decoded JSON body.
  static Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final response = await _client.post(
      uri,
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(response.statusCode, 'invalid_json', response.body);
    }

    if (response.statusCode >= 400) {
      final code = decoded['error'] as String? ?? 'unknown';
      final msg = decoded['message'] as String?;
      throw ApiException(response.statusCode, code, msg);
    }
    return decoded;
  }

  /// GET request returning the decoded JSON body.
  static Future<Map<String, dynamic>> get(String path) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final response = await _client.get(
      uri,
      headers: await _headers(),
    );

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(response.statusCode, 'invalid_json', response.body);
    }

    if (response.statusCode >= 400) {
      final code = decoded['error'] as String? ?? 'unknown';
      final msg = decoded['message'] as String?;
      throw ApiException(response.statusCode, code, msg);
    }
    return decoded;
  }
}
