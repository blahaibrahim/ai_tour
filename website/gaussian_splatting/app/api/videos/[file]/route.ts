import { createReadStream } from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";

import { MIME_TYPES } from "@/lib/config";
import { absolutePathOf, resolveVideo } from "@/lib/videos";

export const dynamic = "force-dynamic";

/**
 * Serve a clip straight off disk, with byte ranges — a `<video>` element seeks
 * by asking for one, and without a 206 the scrubber is dead and Safari will not
 * play the file at all.
 */
export async function GET(
  request: Request,
  { params }: { params: Promise<{ file: string }> },
) {
  const { file } = await params;
  const video = await resolveVideo(decodeURIComponent(file));
  if (!video) {
    return new Response("not found", { status: 404 });
  }

  const filePath = absolutePathOf(video);
  const size = video.sizeBytes;
  const type =
    MIME_TYPES[path.extname(video.file).toLowerCase()] ?? "application/octet-stream";

  const range = request.headers.get("range");
  const match = range?.match(/bytes=(\d*)-(\d*)/);

  if (!match) {
    const stream = Readable.toWeb(
      createReadStream(filePath),
    ) as ReadableStream<Uint8Array>;
    return new Response(stream, {
      headers: {
        "content-type": type,
        "content-length": String(size),
        "accept-ranges": "bytes",
      },
    });
  }

  const start = match[1] ? Number(match[1]) : 0;
  const end = match[2] ? Number(match[2]) : size - 1;

  if (Number.isNaN(start) || Number.isNaN(end) || start >= size || start > end) {
    return new Response("range not satisfiable", {
      status: 416,
      headers: { "content-range": `bytes */${size}` },
    });
  }

  const last = Math.min(end, size - 1);
  const stream = Readable.toWeb(
    createReadStream(filePath, { start, end: last }),
  ) as ReadableStream<Uint8Array>;

  return new Response(stream, {
    status: 206,
    headers: {
      "content-type": type,
      "content-length": String(last - start + 1),
      "content-range": `bytes ${start}-${last}/${size}`,
      "accept-ranges": "bytes",
    },
  });
}
