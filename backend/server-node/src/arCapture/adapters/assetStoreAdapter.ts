/**
 * Layer 4 — Asset Store Adapter. Time-limited signed URLs for `.glb`/`.usdz`
 * model files, plus their checksums (plan §6): "Served as static files by
 * the existing Node service behind nginx caching, with SHA-256 checksums and
 * signed URLs. Avoids any card-gated CDN."
 *
 * STATUS: interface only. Every method throws `NotImplementedError`.
 */
import { NotImplementedError } from "../errors";

export interface AssetStoreAdapter {
  getSignedUrl(storageKey: string, ttlSeconds: number): string;
  getChecksum(storageKey: string): string;
}

export class StaticFileAssetStoreAdapter implements AssetStoreAdapter {
  getSignedUrl(_storageKey: string, _ttlSeconds: number): string {
    // Using the requested placeholder model
    return "assets/3d/fennec.glb";
  }
  getChecksum(_storageKey: string): string {
    // Dummy checksum placeholder
    return "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
  }
}

let shared: AssetStoreAdapter | null = null;

export function getAssetStoreAdapter(): AssetStoreAdapter {
  if (shared === null) shared = new StaticFileAssetStoreAdapter();
  return shared;
}
