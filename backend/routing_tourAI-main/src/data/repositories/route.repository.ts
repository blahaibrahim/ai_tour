import { randomUUID } from 'node:crypto';
import type { PersistedRoute, RouteResponse, Waypoint } from '../../domain/models/route.model.js';
import type { RouteRepository } from '../../domain/ports/route-repository.port.js';

/**
 * In-memory RouteRepository — stores immutable route definitions
 * (Section 3/7). Each call to `save` assigns a UUID and `generatedAt`,
 * mirroring what the DB would do via `DEFAULT gen_random_uuid()` and
 * `DEFAULT now()`.
 */
export class InMemoryRouteRepository implements RouteRepository {
  private readonly routes = new Map<string, PersistedRoute>();

  async save(
    route: RouteResponse,
    context: { sessionId?: string; userId?: string },
  ): Promise<PersistedRoute> {
    const persisted: PersistedRoute = {
      ...route,
      id: randomUUID(),
      sessionId: context.sessionId ?? null,
      userId: context.userId ?? null,
      generatedAt: new Date(),
    };
    this.routes.set(persisted.id, persisted);
    return persisted;
  }

  async findById(id: string): Promise<PersistedRoute | null> {
    return this.routes.get(id) ?? null;
  }
}
