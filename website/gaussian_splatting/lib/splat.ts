/**
 * Reader for the INRIA 3D Gaussian Splatting `.ply`, and the small amount of
 * linear algebra the viewer needs.
 *
 * The counterpart to `backend/gaussian_splatting/pipeline/ply.py` — read that
 * file first. The two details it warns about are exactly the two this reader
 * has to undo: **values are stored pre-activation** (opacity is a logit, scale
 * is a log, rotation is an unnormalised quaternion), and the higher-order
 * spherical harmonics are channel-major. This viewer only needs the DC term,
 * so the second one costs it nothing; the first is why there is a sigmoid and
 * an exp below rather than a straight copy.
 *
 * Browser-side on purpose: nothing here touches Node, so the whole file runs
 * in the client component that owns the canvas.
 */

export interface SplatCloud {
  count: number;
  /** xyz, 3 floats per gaussian. */
  positions: Float32Array;
  /** rgba, 4 bytes per gaussian, already through the SH DC and the sigmoid. */
  colors: Uint8Array;
  /** World-space radius, from the largest of the three exponentiated scales. */
  radii: Float32Array;
  center: [number, number, number];
  /** Distance from the centre that contains most of the cloud. */
  extent: number;
  /** Gaussians in the file, before the transparent ones were dropped. */
  total: number;
}

const SH_C0 = 0.28209479177387814;

const SIZES: Record<string, number> = {
  char: 1, uchar: 1, int8: 1, uint8: 1,
  short: 2, ushort: 2, int16: 2, uint16: 2,
  int: 4, uint: 4, int32: 4, uint32: 4, float: 4, float32: 4,
  double: 8, float64: 8,
};

export interface Property {
  name: string;
  type: string;
  offset: number;
}

/** A parsed `.ply` header: where the payload starts and how to read a row. */
export interface PlyHeader {
  properties: Property[];
  /** Bytes per vertex. */
  stride: number;
  /** Vertices the header claims. */
  total: number;
  /** Byte offset of the first vertex. */
  dataStart: number;
}

/** Gaussians kept. A draft run lands well under this; a 30k run can exceed it. */
const MAX_POINTS = 1_500_000;

/** Below this, a gaussian contributes nothing a viewer can see. */
export const MIN_ALPHA = 0.02;

/**
 * Reads the ASCII header only.
 *
 * Split out of [parsePly] so a reader that cannot hold the file in memory can
 * still learn its layout: `lib/mobileSplat.ts` streams a 468 MB point cloud
 * past a small buffer, and it needs exactly this — the stride and the property
 * offsets — before the first byte of payload goes by. [bytes] only has to be
 * long enough to contain `end_header`; the first few kilobytes always are.
 */
export function parsePlyHeader(bytes: Uint8Array): PlyHeader {
  const marker = "end_header\n";
  const head = new TextDecoder("ascii").decode(bytes.subarray(0, 8192));
  const headerEnd = head.indexOf(marker);
  if (!head.startsWith("ply") || headerEnd < 0) {
    throw new Error("not a .ply file");
  }
  const header = head.slice(0, headerEnd).split(/\r?\n/);
  const dataStart = headerEnd + marker.length;

  if (!header.some((line) => line.startsWith("format binary_little_endian"))) {
    throw new Error(
      "only binary_little_endian .ply is supported — which is what the " +
        "pipeline writes",
    );
  }

  let total = 0;
  const properties: Property[] = [];
  let stride = 0;
  let inVertex = false;

  for (const line of header) {
    const parts = line.trim().split(/\s+/);
    if (parts[0] === "element") {
      // Properties are listed under the element they belong to; anything after
      // a second element is not a vertex attribute.
      inVertex = parts[1] === "vertex";
      if (inVertex) total = Number(parts[2]);
    } else if (parts[0] === "property" && inVertex) {
      if (parts[1] === "list") throw new Error("list properties are not supported");
      const size = SIZES[parts[1]];
      if (!size) throw new Error(`unknown property type ${parts[1]}`);
      properties.push({ name: parts[2], type: parts[1], offset: stride });
      stride += size;
    }
  }

  const required = ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity"];
  for (const name of required) {
    if (!properties.some((property) => property.name === name)) {
      throw new Error(`missing property '${name}'`);
    }
  }

  return { properties, stride, total, dataStart };
}

/**
 * A per-property accessor over a buffer of whole rows.
 *
 * Reading through this rather than assuming float32 everywhere: the pipeline
 * writes floats, but the format allows otherwise and a reader that silently
 * misreads is worse than one that refuses. [view] must start at a row boundary,
 * so `row` counts from wherever it begins rather than from the file's first
 * vertex — which is what lets the streaming decimator reuse this per block.
 */
export function rowReaders(
  view: DataView,
  header: PlyHeader,
): Map<string, (row: number) => number> {
  const readers = new Map<string, (row: number) => number>();
  for (const property of header.properties) {
    const at = (row: number) => row * header.stride + property.offset;
    readers.set(
      property.name,
      {
        float: (row: number) => view.getFloat32(at(row), true),
        float32: (row: number) => view.getFloat32(at(row), true),
        double: (row: number) => view.getFloat64(at(row), true),
        float64: (row: number) => view.getFloat64(at(row), true),
        uchar: (row: number) => view.getUint8(at(row)),
        uint8: (row: number) => view.getUint8(at(row)),
        char: (row: number) => view.getInt8(at(row)),
        int8: (row: number) => view.getInt8(at(row)),
        ushort: (row: number) => view.getUint16(at(row), true),
        uint16: (row: number) => view.getUint16(at(row), true),
        short: (row: number) => view.getInt16(at(row), true),
        int16: (row: number) => view.getInt16(at(row), true),
        uint: (row: number) => view.getUint32(at(row), true),
        uint32: (row: number) => view.getUint32(at(row), true),
        int: (row: number) => view.getInt32(at(row), true),
        int32: (row: number) => view.getInt32(at(row), true),
      }[property.type]!,
    );
  }
  return readers;
}

export function parsePly(buffer: ArrayBuffer): SplatCloud {
  const bytes = new Uint8Array(buffer);
  const header = parsePlyHeader(bytes);
  const { properties, stride, dataStart } = header;
  let total = header.total;
  const find = (name: string) => properties.find((p) => p.name === name);

  const view = new DataView(buffer, dataStart);
  const available = Math.floor((buffer.byteLength - dataStart) / stride);
  if (available < total) total = available;

  const readers = rowReaders(view, header);

  const read = (name: string, row: number) => readers.get(name)!(row);
  const hasScale = Boolean(find("scale_0"));

  // A long "high" run can exceed the budget; take an even stride through the
  // file rather than the first N, which would be a spatially biased slice.
  const step = total > MAX_POINTS ? Math.ceil(total / MAX_POINTS) : 1;

  const positions: number[] = [];
  const colors: number[] = [];
  const radii: number[] = [];

  let sumX = 0;
  let sumY = 0;
  let sumZ = 0;

  for (let row = 0; row < total; row += step) {
    // opacity is the logit the trainer optimised, not the alpha.
    const alpha = 1 / (1 + Math.exp(-read("opacity", row)));
    if (alpha < MIN_ALPHA) continue;

    const x = read("x", row);
    const y = read("y", row);
    const z = read("z", row);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;

    positions.push(x, y, z);
    sumX += x;
    sumY += y;
    sumZ += z;

    colors.push(
      channel(read("f_dc_0", row)),
      channel(read("f_dc_1", row)),
      channel(read("f_dc_2", row)),
      Math.round(alpha * 255),
    );

    // scale is stored as a log. Two sigma is the radius past which a gaussian
    // is not worth drawing.
    radii.push(
      hasScale
        ? 2 *
            Math.max(
              Math.exp(read("scale_0", row)),
              Math.exp(read("scale_1", row)),
              Math.exp(read("scale_2", row)),
            )
        : 0.01,
    );
  }

  const count = radii.length;
  if (count === 0) throw new Error("every gaussian in this file is transparent");

  const center: [number, number, number] = [
    sumX / count,
    sumY / count,
    sumZ / count,
  ];

  // The 90th-percentile distance, not the maximum: outdoor scenes are seeded
  // with background gaussians spread across a huge volume, and framing on the
  // furthest one would show the subject as a dot.
  const distances = new Float32Array(count);
  for (let i = 0; i < count; i += 1) {
    const dx = positions[i * 3] - center[0];
    const dy = positions[i * 3 + 1] - center[1];
    const dz = positions[i * 3 + 2] - center[2];
    distances[i] = Math.hypot(dx, dy, dz);
  }
  distances.sort();
  const extent = distances[Math.floor(count * 0.9)] || 1;

  return {
    count,
    positions: new Float32Array(positions),
    colors: new Uint8Array(colors),
    radii: new Float32Array(radii),
    center,
    extent,
    total,
  };
}

/** The spherical-harmonic DC term -> an 8-bit colour channel. */
export function channel(dc: number): number {
  return Math.max(0, Math.min(255, Math.round((0.5 + SH_C0 * dc) * 255)));
}

/* --- the little bit of linear algebra the canvas needs -------------------- */

export type Mat4 = Float32Array;

export function perspective(fovY: number, aspect: number, near: number, far: number): Mat4 {
  const f = 1 / Math.tan(fovY / 2);
  const out = new Float32Array(16);
  out[0] = f / aspect;
  out[5] = f;
  out[10] = (far + near) / (near - far);
  out[11] = -1;
  out[14] = (2 * far * near) / (near - far);
  return out;
}

export function lookAt(
  eye: [number, number, number],
  target: [number, number, number],
  up: [number, number, number],
): Mat4 {
  const z = normalize(sub(eye, target));
  const x = normalize(cross(up, z));
  const y = cross(z, x);

  const out = new Float32Array(16);
  out[0] = x[0]; out[4] = x[1]; out[8] = x[2]; out[12] = -dot(x, eye);
  out[1] = y[0]; out[5] = y[1]; out[9] = y[2]; out[13] = -dot(y, eye);
  out[2] = z[0]; out[6] = z[1]; out[10] = z[2]; out[14] = -dot(z, eye);
  out[15] = 1;
  return out;
}

type Vec3 = [number, number, number];

const sub = (a: Vec3, b: Vec3): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot = (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a: Vec3, b: Vec3): Vec3 => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];

function normalize(v: Vec3): Vec3 {
  const length = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / length, v[1] / length, v[2] / length];
}
