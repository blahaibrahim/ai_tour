import '../models/location.dart';
import '../services/api_client.dart';

/// Wraps POST /api/tasks/generate.
class TaskRepository {
  const TaskRepository._();

  static Future<Task> generateTask({
    required String locationId,
    required String locationName,
  }) async {
    final data = await ApiClient.post('/api/tasks/generate', body: {
      'location_id': locationId,
      'location_name': locationName,
    });
    return Task.fromJson(data);
  }
}
