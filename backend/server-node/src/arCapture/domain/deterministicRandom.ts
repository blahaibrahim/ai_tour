/**
 * xoshiro128** — the seeded PRNG plan §5.1 names for spawn-point generation.
 *
 * Determinism buys three things (plan §5.1): the same user reopening the app
 * gets the same spawn without a DB read; a spawn is reproducible for
 * debugging a support report; and the seed is unguessable by a client
 * (derived from an HMAC, see `spawnPointGenerator.ts`), so spawn points
 * cannot be predicted before the manifest is issued.
 *
 * 32-bit variant: fast, and the spatial precision it buys over a 32-bit
 * float is already far finer than GPS accuracy, so there is nothing to gain
 * from the 64-bit form.
 */

/** Seeds a xoshiro128** generator's four state words from an arbitrary-length
 * seed via splitmix32 — the standard way to turn one seed integer into a full
 * xoshiro state without the "all zero" trap a naive seeding can fall into. */
function splitmix32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x9e3779b9) | 0;
    let t = a ^ (a >>> 16);
    t = Math.imul(t, 0x21f0aaad);
    t ^= t >>> 15;
    t = Math.imul(t, 0x735a2d97);
    t ^= t >>> 15;
    return t >>> 0;
  };
}

function rotl(x: number, k: number): number {
  return ((x << k) | (x >>> (32 - k))) >>> 0;
}

/** A deterministic `() => number` in `[0, 1)`, seeded from `seed`. Only the
 * first 4 bytes of `seed` are read directly; the rest of the entropy comes
 * from splitmix32 expanding that into the full 128-bit state. */
export function xoshiro128ss(seed: Buffer): () => number {
  const seedWord = seed.length >= 4 ? seed.readUInt32LE(0) : seed.readUInt8(0) || 1;
  const sm = splitmix32(seedWord);
  let s0 = sm();
  let s1 = sm();
  let s2 = sm();
  let s3 = sm();

  return () => {
    const result = (Math.imul(rotl(Math.imul(s1, 5) >>> 0, 7), 9) >>> 0) / 4294967296;

    const t = (s1 << 9) >>> 0;
    s2 ^= s0;
    s3 ^= s1;
    s1 ^= s2;
    s0 ^= s3;
    s2 ^= t;
    s3 = rotl(s3, 11);

    return result;
  };
}
