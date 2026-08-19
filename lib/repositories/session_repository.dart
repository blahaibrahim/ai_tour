import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../blocs/app/app_state.dart';

class SessionRepository {
  static const String _kSessionKey = 'ai_tour_session_state';

  static Future<void> saveSession(AppState state) async {
    final prefs = await SharedPreferences.getInstance();
    
    // We only save the fields necessary to resume a generated route.
    final Map<String, dynamic> data = {
      'screen': state.screen,
      'route': state.route?.toJson(),
      'progress': state.progress?.toJson(),
      'queue': state.queue.map((l) => l.toJson()).toList(),
      'currentIndex': state.currentIndex,
      'accepted': state.accepted.map((l) => l.toJson()).toList(),
      'rejected': state.rejected.map((l) => l.toJson()).toList(),
      'routeAccepted': state.routeAccepted,
      'tasks': state.tasks.map((t) => t.toJson()).toList(),
      'currentStopIdx': state.currentStopIdx,
      'points': state.points,
      'taskRegenerationsLeft': state.taskRegenerationsLeft,
      // Which quests each stop has already offered. Without this a restored
      // session forgets, and a traveller who already refused the fennec hunt
      // at a stop can be handed it again.
      'offeredQuestTypes': state.offeredQuestTypes.map((s) => s.toList()).toList(),
      // Offline support: how many outbox entries await sync.
      'pendingSyncCount': state.pendingSyncCount,
    };
    
    await prefs.setString(_kSessionKey, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kSessionKey);
    if (jsonStr == null) return null;
    
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
  }
}
