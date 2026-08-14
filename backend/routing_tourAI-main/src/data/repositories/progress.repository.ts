import { randomUUID } from 'node:crypto';
import type {
  Progress,
  ProgressEvent,
  ProgressRepository,
} from '../../domain/ports/progress-repository.port.js';

/**
 * In-memory ProgressRepository — mutable progress state kept separate
 * from the immutable RouteRepository per Section 3. Not called during
 * route generation itself; exists so the Data layer schema is ready for
 * the AR trigger service or a future progress-tracking endpoint.
 */
export class InMemoryProgressRepository implements ProgressRepository {
  private readonly progressRecords = new Map<string, Progress>();
  private readonly events: ProgressEvent[] = [];

  async start(routeId: string): Promise<Progress> {
    const now = new Date();
    const progress: Progress = {
      id: randomUUID(),
      routeId,
      status: 'in_progress',
      startedAt: now,
      lastUpdatedAt: now,
      completedAt: null,
    };
    this.progressRecords.set(progress.id, progress);
    return progress;
  }

  async recordCheckpoint(progressId: string, poiId: string): Promise<ProgressEvent> {
    const progress = this.progressRecords.get(progressId);
    if (progress) {
      progress.lastUpdatedAt = new Date();
    }
    const event: ProgressEvent = {
      id: randomUUID(),
      progressId,
      poiId,
      arrivedAt: new Date(),
    };
    this.events.push(event);
    return event;
  }

  async findByRouteId(routeId: string): Promise<Progress | null> {
    for (const p of this.progressRecords.values()) {
      if (p.routeId === routeId) return p;
    }
    return null;
  }
}
