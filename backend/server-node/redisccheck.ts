import { initCache, getCacheAdapter, InMemoryCacheAdapter } from "./src/routeGeneration/adapters/cacheAdapter";
async function main() {
  // Path 1: no REDIS_URL at all.
  console.log(">> no REDIS_URL");
  let t0 = Date.now();
  let c = await initCache();
  console.log(`   ${c instanceof InMemoryCacheAdapter ? "in-memory" : "redis"} in ${Date.now() - t0}ms`);

  // Path 2: a URL nothing is listening on. Must degrade, not hang or throw.
  process.env.REDIS_URL = "redis://127.0.0.1:6399";
  delete require.cache[require.resolve("./src/config")];
  const { Config } = await import("./src/config");
  (Config as { REDIS_URL?: string }).REDIS_URL = "redis://127.0.0.1:6399";
  console.log(">> unreachable REDIS_URL");
  t0 = Date.now();
  c = await initCache();
  console.log(`   ${c instanceof InMemoryCacheAdapter ? "in-memory" : "redis"} in ${Date.now() - t0}ms`);

  // And the pipeline still has a usable cache afterwards.
  const a = { lat: 1, lng: 1 }, b = { lat: 2, lng: 2 };
  await getCacheAdapter().setLeg(a, b, "walking", { durationSeconds: 1, distanceMeters: 2, geometry: [] });
  const hit = await getCacheAdapter().getLeg(a, b, "walking");
  console.log(`>> cache usable after fallback: ${hit ? "yes" : "no"}`);
}
main().then(() => process.exit(0), (e) => { console.error("THREW:", e); process.exit(1); });
