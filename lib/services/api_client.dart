import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Typed exception carrying the HTTP status code and machine-readable error code.
///
/// [message] is the server's human-readable text when it sent one. Callers that
/// show it to a user should fall back to their own copy when it is null — the
/// server does not send a message for every code.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.errorCode, [this.message]);

  final int statusCode;
  final String errorCode;
  final String? message;

  /// Nothing reached the server, or it never answered. Distinct from a 4xx/5xx
  /// with a body: there is nothing to explain to the user beyond "offline", and
  /// retrying is worth offering.
  bool get isTransport =>
      errorCode == 'network_error' || errorCode == 'timeout';

  /// Worth showing a retry affordance for. 5xx and 429 are the server asking to
  /// be tried again; a 4xx is the request itself being wrong, so retrying the
  /// identical request cannot help.
  bool get isRetryable => isTransport || statusCode >= 500 || statusCode == 429;

  @override
  String toString() => 'ApiException($statusCode, $errorCode, $message)';
}

/// Low-level HTTP client for the Node backend.
///
/// Attaches the current Supabase JWT on every request so all routes receive the
/// user's identity — every route-generation endpoint authenticates, so a
/// request without one is a guaranteed 401.
class ApiClient {
  ApiClient._();

  static final _client = http.Client();

  /// Deadline for a single request.
  ///
  /// Route generation is the slowest call the app makes and the module budgets
  /// it at 1.5 s cold, so 20 s is generous rather than tight. It exists because
  /// the default is *no* deadline: on a captive portal or a dropped mobile
  /// connection the future never completes, and the thinking screen spins
  /// forever with no error and no way back.
  static const Duration _timeout = Duration(seconds: 20);

  static Future<Map<String, String>> _headers() async {
    var session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // The bloc is constructed before anonymous sign-in completes, so the
      // first few calls of a cold start legitimately land here.
      try {
        final res = await Supabase.instance.client.auth.signInAnonymously();
        session = res.session;
      } catch (error, stack) {
        developer.log(
          'Anonymous sign-in failed; request will go out unauthenticated',
          name: 'ApiClient',
          error: error,
          stackTrace: stack,
        );
      }
    }
    return {
      'Content-Type': 'application/json',
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  /// POST returning the decoded JSON body.
  static Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _send(
      'POST',
      path,
      (uri, headers) => _client.post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  /// GET returning the decoded JSON body.
  static Future<Map<String, dynamic>> get(String path) {
    return _send(
      'GET',
      path,
      (uri, headers) => _client.get(uri, headers: headers),
    );
  }

  /// The one place a response becomes either a decoded body or an
  /// [ApiException]. Both verbs shared this logic by copy before; the timeout
  /// and transport-error handling are exactly the kind of thing that gets added
  /// to one copy and not the other.
  static Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Future<http.Response> Function(Uri uri, Map<String, String> headers) issue,
  ) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');

    final http.Response response;
    try {
      response = await issue(uri, await _headers()).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(0, 'timeout', 'The server took too long to answer.');
    } on SocketException {
      throw const ApiException(0, 'network_error', "Couldn't reach the server.");
    } on http.ClientException {
      throw const ApiException(0, 'network_error', "Couldn't reach the server.");
    }

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      // Falls through to the non-JSON handling below.
    }

    if (decoded == null) {
      // A proxy, a captive portal or a crashed process answers with HTML, not
      // JSON. Reporting that as `invalid_json` with the raw body as the message
      // would put a page of markup in front of the user.
      developer.log(
        '$method $path returned ${response.statusCode} with a non-JSON body',
        name: 'ApiClient',
      );
      throw ApiException(
        response.statusCode,
        response.statusCode >= 400 ? 'server_error' : 'invalid_json',
        'The server sent an unexpected response.',
      );
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        decoded['error'] as String? ?? 'unknown',
        decoded['message'] as String?,
      );
    }
    return decoded;
  }
}
