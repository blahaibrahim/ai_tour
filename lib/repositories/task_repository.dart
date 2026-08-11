import '../models/location.dart';
import '../services/api_client.dart';
import '../services/backend_monitor.dart';
import '../services/demo_data.dart';

/// Wraps POST /api/tasks/generate.
class TaskRepository {
  const TaskRepository._();

  static Future<Task> generateTask({
    required String locationId,
    required String locationName,
  }) async {
    try {
      final data = await ApiClient.post('/api/tasks/generate', body: {
        'location_id': locationId,
        'location_name': locationName,
      });
      return Task.fromJson(data);
    } catch (e) {
      if ((e is ApiException && e.isTransport) || isConnectivityError(e)) {
        return DemoData.task(seed: locationId.hashCode);
      }
      rethrow;
    }
  }
}
