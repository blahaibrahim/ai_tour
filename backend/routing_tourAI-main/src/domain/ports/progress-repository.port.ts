export type ProgressStatus = 'in_progress' | 'completed' | 'abandoned';

export interface Progress {
  id: string;
  routeId: string;
  status: ProgressStatus;
  startedAt: Date;
  lastUpdatedAt: Date;
  completedAt: Date | null;
}

export interface ProgressEvent {
  id: string;
  progressId: string;
  poiId: string;
  arrivedAt: Date;
}

/**
 * Access to the mutable `progress` + `progress_events` tables (Section
 * 7), kept separate from the immutable RouteRepository per Section 3's
 * explicit instruction. NOT called by the Route Generation
 * Orchestrator's request flow (Section 4) — this exists because the
 * Data layer owns these tables now, ready for the separate AR trigger
 * service (Section 8) or a future progress-tracking endpoint to write
 * checkpoint arrivals through it later.
 */
export interface ProgressRepository {
  start(routeId: string): Promise<Progress>;
  recordCheckpoint(progressId: string, poiId: string): Promise<ProgressEvent>;
  findByRouteId(routeId: string): Promise<Progress | null>;
}
