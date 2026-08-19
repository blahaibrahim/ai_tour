/**
 * Turns a trained `.ply` into the compact `.splatb` the phone can open.
 *
 * **Why a second format at all.** The Bardo run is a 468 MB `point_cloud_7000.ply`
 * holding ~1.9 M gaussians, and 90% of those bytes are spherical harmonics of
 * degree 1-3 — view-dependent colour that only a real splat rasteriser uses. The
 * app's viewer draws each gaussian as a screen-space disc from its DC colour, so
 * everything it needs per point is a position, an RGBA and a radius: 20 bytes,
 * against 248 in the source. Decimate to a couple of hundred thousand points on
 * top of that and a scene the phone can hold in memory and download over a
 * mobile connection comes out around 4 MB.
 *
 * **Why here.** This dashboard is the only thing with the `.ply` on local disk
 * (`.splats/<scene>/`), and it already holds the service-role key it takes to
 * put an object in the shared `splats` bucket. Doing it in the Modal pipeline
 * would be better — the Volume copy is the durable one — but that is a change to
 * the trainer, and the pipeline knows nothing about Supabase.
 *
 * **The layout is planar, not interleaved.** All positions, then all radii, then
 * all colours, after a 32-byte header. Every float section therefore starts at a
 * 4-byte boundary, which is what lets the Dart reader do
 * `Float32List.view(buffer, offset, n)` — one aliasing view over the downloaded
 * bytes, no per-point copy. A 20-byte interleaved stride would force 200k
 * `getFloat32` calls on the phone before the first frame.
 *
 *   offset  0   char[4]     "SPLB"
 *   offset  4   uint32      format version (1)
 *   offset  8   uint32      count — gaussians in this file
 *   offset 12   uint32      source — gaussians in the .ply it came from
 *   offset 16   float32[3]  centre of the cloud
 *   offset 28   float32     extent: the radius that frames it
 *   offset 32   float32[3 * count]  positions, xyz
 *               float32[count]      world-space radii
 *               uint8  [4 * count]  colours, rgba
 *
 * Everything is little-endian, like the `.ply` it is derived from.
 */
import { createReadStream } from "node:fs";
import fs from "node:fs/promises";

import { MIN_ALPHA, channel, parsePlyHeader, rowReaders } from "./splat";

/** `"SPLB"`, little-endian, as a uint32. */
const MAGIC = 0x424c5053;
const FORMAT_VERSION = 1;
export const SPLATB_HEADER_BYTES = 32;

/**
 * Gaussians kept, by default.
 *
 * 200k costs 4.0 MB on the wire and draws in one frame on a mid-range phone.
 * The number is a download budget, not a quality ceiling: the source has ~1.9 M
 * and every one of them dropped here is one the operator paid GPU minutes for,
 * so this is deliberately the largest count that still downloads on a hotel
 * connection rather than the smallest that looks acceptable.
 */
export const DEFAULT_TARGET_POINTS = 200_000;

/** Read this much of the payload at a time. */
const BLOCK_BYTES = 8 << 20;

export interface DecimateResult {
  bytes: Buffer;
  /** Gaussians written. */
  count: number;
  /** Gaussians in the source `.ply`. */
  source: number;
}

/**
 * Streams [plyPath] and returns a `.splatb` holding at most [target] gaussians.
 *
 * Streaming rather than reading the file in: 468 MB in a Buffer plus the JS
 * arrays built from it is most of a gigabyte of resident memory in a Next dev
 * server, and there is no reason to hold a byte longer than it takes to decide
 * whether its gaussian survives.
 *
 * Two passes over the *sampled* points, not over the file. The first (this
 * function) keeps roughly `target * 1.3` candidates, because it cannot know in
 * advance how many gaussians the trainer left transparent; the second trims to
 * exactly [target] by taking an even stride through the survivors. Trimming
 * with a stride rather than a slice matters — the `.ply` is written in the order
 * the optimiser held the gaussians, which correlates with position, so the first
 * N points are a corner of the scene rather than a thinner copy of it.
 */
export async function decimatePly(
  plyPath: string,
  target: number = DEFAULT_TARGET_POINTS,
): Promise<DecimateResult> {
  const handle = await fs.open(plyPath, "r");
  let header;
  try {
    const probe = Buffer.alloc(8192);
    await handle.read(probe, 0, probe.length, 0);
    header = parsePlyHeader(new Uint8Array(probe));
  } finally {
    await handle.close();
  }

  const { stride, dataStart } = header;
  const { size } = await fs.stat(plyPath);
  // The header's count is a claim; the file's length is a fact. A run killed
  // mid-write leaves the first short, and trusting it would read past the end.
  const source = Math.min(header.total, Math.floor((size - dataStart) / stride));
  if (source <= 0) throw new Error("this .ply has no vertices");

  // Oversampled so the alpha filter has room to reject without landing under
  // target. Capped at `source` for a draft run that has fewer points than asked.
  const wanted = Math.min(source, Math.ceil(target * 1.3));
  const step = Math.max(1, Math.floor(source / wanted));

  const positions: number[] = [];
  const colors: number[] = [];
  const radii: number[] = [];

  // A one-row DataView reused for every sampled row: `rowReaders` indexes from
  // wherever its view starts, so pointing it at row 0 of a single row is all it
  // takes to read one gaussian anywhere in the file.
  const row = Buffer.alloc(stride);
  const readers = rowReaders(
    new DataView(row.buffer, row.byteOffset, stride),
    header,
  );
  const read = (name: string) => readers.get(name)!(0);
  const hasScale = header.properties.some((p) => p.name === "scale_0");

  // Annotated: `Buffer.alloc` narrows to `Buffer<ArrayBuffer>`, while a stream
  // chunk is `Buffer<ArrayBufferLike>`, and the two do not assign to each other.
  let carry: Buffer = Buffer.alloc(0);
  // Absolute row index of the first row in `carry`, and the next row we want.
  let rowsConsumed = 0;
  let nextWanted = 0;

  const stream = createReadStream(plyPath, {
    start: dataStart,
    end: dataStart + source * stride - 1,
    highWaterMark: BLOCK_BYTES,
  });

  for await (const chunk of stream) {
    carry =
      carry.length === 0 ? (chunk as Buffer) : Buffer.concat([carry, chunk as Buffer]);
    const whole = Math.floor(carry.length / stride);

    while (nextWanted < rowsConsumed + whole) {
      carry.copy(row, 0, (nextWanted - rowsConsumed) * stride);
      keep(read, hasScale, positions, colors, radii);
      nextWanted += step;
    }

    rowsConsumed += whole;
    // Keep only the partial row at the tail; everything before it is spent.
    carry = carry.subarray(whole * stride);
  }

  const kept = radii.length;
  if (kept === 0) throw new Error("every gaussian in this file is transparent");

  return {
    bytes: encode(positions, colors, radii, target, source),
    count: Math.min(kept, target),
    source,
  };
}

/** Appends one gaussian, undoing the activations the trainer stored it under. */
function keep(
  read: (name: string) => number,
  hasScale: boolean,
  positions: number[],
  colors: number[],
  radii: number[],
): void {
  // `opacity` is the logit the optimiser worked in, not the alpha.
  const alpha = 1 / (1 + Math.exp(-read("opacity")));
  if (alpha < MIN_ALPHA) return;

  const x = read("x");
  const y = read("y");
  const z = read("z");
  if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) return;

  positions.push(x, y, z);
  colors.push(
    channel(read("f_dc_0")),
    channel(read("f_dc_1")),
    channel(read("f_dc_2")),
    Math.round(alpha * 255),
  );
  // `scale` is stored as a log. Two sigma is the radius past which a gaussian
  // is not worth drawing.
  radii.push(
    hasScale
      ? 2 *
          Math.max(
            Math.exp(read("scale_0")),
            Math.exp(read("scale_1")),
            Math.exp(read("scale_2")),
          )
      : 0.01,
  );
}

/** Trims the survivors to [target] and writes the buffer. */
function encode(
  positions: number[],
  colors: number[],
  radii: number[],
  target: number,
  source: number,
): Buffer {
  const kept = radii.length;
  const trim = kept > target ? kept / target : 1;
  const count = Math.min(kept, target);

  const bytes = Buffer.alloc(SPLATB_HEADER_BYTES + count * 20);
  const positionsAt = SPLATB_HEADER_BYTES;
  const radiiAt = positionsAt + count * 12;
  const colorsAt = radiiAt + count * 4;

  let sumX = 0;
  let sumY = 0;
  let sumZ = 0;

  for (let i = 0; i < count; i += 1) {
    // Fractional stride, floored — an integer step would quantise 1.4 to 1 and
    // overshoot the budget, or to 2 and throw away a third of the points.
    const from = Math.min(kept - 1, Math.floor(i * trim));

    const x = positions[from * 3];
    const y = positions[from * 3 + 1];
    const z = positions[from * 3 + 2];
    bytes.writeFloatLE(x, positionsAt + i * 12);
    bytes.writeFloatLE(y, positionsAt + i * 12 + 4);
    bytes.writeFloatLE(z, positionsAt + i * 12 + 8);
    sumX += x;
    sumY += y;
    sumZ += z;

    bytes.writeFloatLE(radii[from], radiiAt + i * 4);

    bytes[colorsAt + i * 4] = colors[from * 4];
    bytes[colorsAt + i * 4 + 1] = colors[from * 4 + 1];
    bytes[colorsAt + i * 4 + 2] = colors[from * 4 + 2];
    bytes[colorsAt + i * 4 + 3] = colors[from * 4 + 3];
  }

  const center: [number, number, number] = [sumX / count, sumY / count, sumZ / count];

  // The 90th-percentile distance, not the maximum: an outdoor scene is seeded
  // with background gaussians spread across a huge volume, and a camera framed
  // on the furthest one would show the subject as a dot. Same choice, and the
  // same reason, as `parsePly`.
  const distances = new Float32Array(count);
  for (let i = 0; i < count; i += 1) {
    distances[i] = Math.hypot(
      bytes.readFloatLE(positionsAt + i * 12) - center[0],
      bytes.readFloatLE(positionsAt + i * 12 + 4) - center[1],
      bytes.readFloatLE(positionsAt + i * 12 + 8) - center[2],
    );
  }
  distances.sort();
  const extent = distances[Math.floor(count * 0.9)] || 1;

  bytes.writeUInt32LE(MAGIC, 0);
  bytes.writeUInt32LE(FORMAT_VERSION, 4);
  bytes.writeUInt32LE(count, 8);
  bytes.writeUInt32LE(source, 12);
  bytes.writeFloatLE(center[0], 16);
  bytes.writeFloatLE(center[1], 20);
  bytes.writeFloatLE(center[2], 24);
  bytes.writeFloatLE(extent, 28);

  return bytes;
}
