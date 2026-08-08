/**
 * Layer 5 — City Config Repository.
 *
 * Per-city settings, cached in memory with a short refresh interval (spec §3).
 * This is the mechanism behind the phased city rollout: cluster radius, active
 * routing provider and rollout status all change behaviour without a code
 * change or a deploy (spec §2).
 *
 * STATUS: query stubbed. The caching wrapper around it is implemented, because
 * it is the part the "no code changes to add a city" property depends on and
 * it has no external dependencies.
 */
import { getLogger } from "../../logger";
import { NotImplementedError } from "../errors";
import { CityConfig } from "../types";

const logger = getLogger("routeGeneration.cityConfig");

/** Short enough that flipping a city to `active` takes effect within a minute,
 * long enough that the config is not re-read on every request. */
export const CITY_CONFIG_TTL_MS = 60_000;

export interface CityConfigRepository {
  findById(cityId: string): Promise<CityConfig | null>;
  /** Every city that is not soft-deleted, for the city picker. */
  listAll(): Promise<CityConfig[]>;
}

class SupabaseCityConfigRepository implements CityConfigRepository {
  findById(_cityId: string): Promise<CityConfig | null> {
    throw new NotImplementedError("CityConfigRepository.findById");
  }
  listAll(): Promise<CityConfig[]> {
    throw new NotImplementedError("CityConfigRepository.listAll");
  }
}

/** In-memory TTL cache in front of whatever repository it wraps. */
export class CachedCityConfigRepository implements CityConfigRepository {
  private readonly byId = new Map<string, { value: CityConfig | null; storedAt: number }>();
  private all: { value: CityConfig[]; storedAt: number } | null = null;

  constructor(private readonly inner: CityConfigRepository) {}

  async findById(cityId: string): Promise<CityConfig | null> {
    const hit = this.byId.get(cityId);
    if (hit && Date.now() - hit.storedAt < CITY_CONFIG_TTL_MS) {
      return hit.value;
    }
    const value = await this.inner.findById(cityId);
    this.byId.set(cityId, { value, storedAt: Date.now() });
    return value;
  }

  async listAll(): Promise<CityConfig[]> {
    if (this.all && Date.now() - this.all.storedAt < CITY_CONFIG_TTL_MS) {
      return this.all.value;
    }
    const value = await this.inner.listAll();
    this.all = { value, storedAt: Date.now() };
    return value;
  }

  invalidate(): void {
    this.byId.clear();
    this.all = null;
    logger.info("City config cache invalidated");
  }
}

let shared: CityConfigRepository | null = null;

export function getCityConfigRepository(): CityConfigRepository {
  if (shared === null) {
    shared = new CachedCityConfigRepository(new SupabaseCityConfigRepository());
  }
  return shared;
}
