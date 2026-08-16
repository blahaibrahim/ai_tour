"use client";

import { useEffect, useRef, useState } from "react";

import { lookAt, parsePly, perspective, type SplatCloud } from "@/lib/splat";

import styles from "./SplatCanvas.module.css";

/**
 * An orbitable view of a trained splat, drawn from the `.ply` itself.
 *
 * Each gaussian is drawn as a screen-space disc, sized by its own scale and
 * alpha-blended back-to-front. That is the cheap half of 3D Gaussian
 * Splatting: the real rasteriser projects each gaussian's covariance to an
 * oriented ellipse, so a thin surface reads as a thin surface rather than a
 * round dab. The difference shows on flat walls and at grazing angles.
 *
 * It is deliberately the cheap half. This is a "did the capture reconstruct"
 * view, and it is drawn with no dependencies — the button next to it opens the
 * same file in SuperSplat, which does the full thing.
 */

const VERTEX = `#version 300 es
precision highp float;

in vec3 aPosition;
in vec4 aColor;
in float aRadius;

uniform mat4 uView;
uniform mat4 uProjection;
uniform float uFocal;
uniform float uMaxSize;

out vec4 vColor;

void main() {
  vec4 view = uView * vec4(aPosition, 1.0);
  gl_Position = uProjection * view;

  // A world-space radius at distance d covers radius * focal / d pixels.
  float distance = max(-view.z, 1e-3);
  gl_PointSize = clamp(aRadius * uFocal / distance, 1.0, uMaxSize);

  vColor = aColor;
}`;

const FRAGMENT = `#version 300 es
precision highp float;

in vec4 vColor;
out vec4 fragment;

void main() {
  vec2 offset = gl_PointCoord * 2.0 - 1.0;
  float squared = dot(offset, offset);
  if (squared > 1.0) discard;

  // A gaussian falloff across the disc, not a flat dab — this is what stops
  // the cloud reading as a pile of confetti.
  float alpha = vColor.a * exp(-4.0 * squared);
  fragment = vec4(vColor.rgb * alpha, alpha);
}`;

type Phase =
  | { kind: "idle" }
  | { kind: "loading"; loaded: number; total: number }
  | { kind: "parsing" }
  | { kind: "ready"; cloud: SplatCloud }
  | { kind: "error"; message: string };

export function SplatCanvas({ url }: { url: string }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [phase, setPhase] = useState<Phase>({ kind: "idle" });

  // Download and parse. Kept separate from the render effect so orbiting never
  // touches the fetch, and a changed URL is the only thing that re-downloads.
  useEffect(() => {
    const controller = new AbortController();

    void (async () => {
      try {
        setPhase({ kind: "loading", loaded: 0, total: 0 });
        const response = await fetch(url, { signal: controller.signal });
        if (!response.ok) {
          throw new Error(
            response.status === 404
              ? "not fetched from the Volume yet"
              : `HTTP ${response.status}`,
          );
        }

        // A splat is tens to hundreds of MB, so the progress is worth showing.
        const total = Number(response.headers.get("content-length") ?? 0);
        const reader = response.body?.getReader();
        let buffer: ArrayBuffer;

        if (reader) {
          const chunks: Uint8Array[] = [];
          let loaded = 0;
          for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            chunks.push(value);
            loaded += value.length;
            setPhase({ kind: "loading", loaded, total });
          }
          const joined = new Uint8Array(loaded);
          let at = 0;
          for (const chunk of chunks) {
            joined.set(chunk, at);
            at += chunk.length;
          }
          buffer = joined.buffer as ArrayBuffer;
        } else {
          buffer = await response.arrayBuffer();
        }

        setPhase({ kind: "parsing" });
        // Yield once so the "parsing" frame actually paints before the main
        // thread disappears into a million-point loop.
        await new Promise((resolve) => setTimeout(resolve, 0));
        setPhase({ kind: "ready", cloud: parsePly(buffer) });
      } catch (err) {
        if (controller.signal.aborted) return;
        setPhase({ kind: "error", message: (err as Error).message });
      }
    })();

    return () => controller.abort();
  }, [url]);

  const cloud = phase.kind === "ready" ? phase.cloud : null;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !cloud) return;

    const gl = canvas.getContext("webgl2", {
      alpha: false,
      antialias: false,
      // Frames are drawn on demand, not in a loop: without this the browser is
      // free to discard the buffer after compositing and the canvas goes black
      // the moment the user stops dragging.
      preserveDrawingBuffer: true,
    });
    if (!gl) {
      setPhase({ kind: "error", message: "this browser has no WebGL2" });
      return;
    }

    const program = link(gl);
    if (typeof program === "string") {
      setPhase({ kind: "error", message: program });
      return;
    }

    const buffers = {
      position: attribute(gl, program, "aPosition", cloud.positions, 3, gl.FLOAT, false),
      color: attribute(gl, program, "aColor", cloud.colors, 4, gl.UNSIGNED_BYTE, true),
      radius: attribute(gl, program, "aRadius", cloud.radii, 1, gl.FLOAT, false),
    };

    const order = gl.createBuffer()!;
    const indices = new Uint32Array(cloud.count);

    const uniforms = {
      view: gl.getUniformLocation(program, "uView"),
      projection: gl.getUniformLocation(program, "uProjection"),
      focal: gl.getUniformLocation(program, "uFocal"),
      maxSize: gl.getUniformLocation(program, "uMaxSize"),
    };

    // Orbit state. Framed on the cloud's 90th-percentile extent, so an outdoor
    // scene's background seeds don't push the subject into the distance.
    const camera = {
      yaw: 0.6,
      pitch: 0.25,
      distance: cloud.extent * 2.6,
      target: [...cloud.center] as [number, number, number],
    };

    let sortedFrom: [number, number, number] | null = null;
    let disposed = false;

    /**
     * Back-to-front order, by a counting sort on quantised view depth.
     * Alpha blending is not commutative, so drawing in file order gives a
     * washed-out cloud with the far side bleeding through the near one.
     */
    function sort(view: Float32Array) {
      const { positions, count } = cloud!;
      const depths = new Int32Array(count);
      let min = Infinity;
      let max = -Infinity;

      for (let i = 0; i < count; i += 1) {
        // Third row of the view matrix: everything else is thrown away.
        const depth =
          view[2] * positions[i * 3] +
          view[6] * positions[i * 3 + 1] +
          view[10] * positions[i * 3 + 2] +
          view[14];
        const quantised = (depth * 4096) | 0;
        depths[i] = quantised;
        if (quantised < min) min = quantised;
        if (quantised > max) max = quantised;
      }

      const BUCKETS = 65_536;
      const scale = max > min ? (BUCKETS - 1) / (max - min) : 0;
      const counts = new Uint32Array(BUCKETS);
      for (let i = 0; i < count; i += 1) {
        counts[((depths[i] - min) * scale) | 0] += 1;
      }
      // Prefix sums over the buckets in increasing depth. In view space -z is
      // forward, so increasing z is *nearer* — and near must be drawn last.
      const starts = new Uint32Array(BUCKETS);
      for (let b = 1; b < BUCKETS; b += 1) {
        starts[b] = starts[b - 1] + counts[b - 1];
      }
      for (let i = 0; i < count; i += 1) {
        const bucket = ((depths[i] - min) * scale) | 0;
        indices[starts[bucket]++] = i;
      }

      gl!.bindBuffer(gl!.ELEMENT_ARRAY_BUFFER, order);
      gl!.bufferData(gl!.ELEMENT_ARRAY_BUFFER, indices, gl!.DYNAMIC_DRAW);
    }

    function eye(): [number, number, number] {
      const cosPitch = Math.cos(camera.pitch);
      return [
        camera.target[0] + camera.distance * cosPitch * Math.sin(camera.yaw),
        camera.target[1] + camera.distance * Math.sin(camera.pitch),
        camera.target[2] + camera.distance * cosPitch * Math.cos(camera.yaw),
      ];
    }

    function draw() {
      if (disposed || !gl || !canvas) return;

      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
      const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }

      const position = eye();
      // A splat is upside down relative to the usual convention: COLMAP's
      // camera looks down +y, so +y is *down* in the reconstructed world.
      const view = lookAt(position, camera.target, [0, -1, 0]);

      // Re-sort only when the camera has moved a meaningful fraction of the
      // scene. Sorting a million points every frame during a drag would drop
      // the framerate for an ordering nobody can see change.
      const moved =
        !sortedFrom ||
        Math.hypot(
          position[0] - sortedFrom[0],
          position[1] - sortedFrom[1],
          position[2] - sortedFrom[2],
        ) >
          cloud!.extent * 0.08;
      if (moved) {
        sort(view);
        sortedFrom = position;
      }

      const fov = Math.PI / 4;
      const projection = perspective(
        fov,
        width / height,
        Math.max(cloud!.extent * 0.002, 1e-3),
        cloud!.extent * 40,
      );

      gl.viewport(0, 0, width, height);
      gl.clearColor(0.078, 0.145, 0.29, 1); // --deep-navy
      gl.clear(gl.COLOR_BUFFER_BIT);

      gl.enable(gl.BLEND);
      // Premultiplied source, which is what the fragment shader writes.
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      gl.disable(gl.DEPTH_TEST);

      gl.useProgram(program as WebGLProgram);
      gl.uniformMatrix4fv(uniforms.view, false, view);
      gl.uniformMatrix4fv(uniforms.projection, false, projection);
      gl.uniform1f(uniforms.focal, height / (2 * Math.tan(fov / 2)));
      gl.uniform1f(uniforms.maxSize, Math.min(64, height / 8));

      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, order);
      gl.drawElements(gl.POINTS, cloud!.count, gl.UNSIGNED_INT, 0);
    }

    let frame = 0;
    const schedule = () => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        draw();
      });
    };

    /* --- orbit controls --------------------------------------------------- */

    let dragging: { x: number; y: number; pan: boolean } | null = null;

    const onPointerDown = (event: PointerEvent) => {
      canvas.setPointerCapture(event.pointerId);
      dragging = {
        x: event.clientX,
        y: event.clientY,
        pan: event.shiftKey || event.button === 1 || event.button === 2,
      };
    };

    const onPointerMove = (event: PointerEvent) => {
      if (!dragging) return;
      // A release this canvas never heard about would otherwise leave the
      // model stuck to the cursor with no button held.
      if (event.buttons === 0) {
        dragging = null;
        return;
      }
      const dx = event.clientX - dragging.x;
      const dy = event.clientY - dragging.y;
      dragging.x = event.clientX;
      dragging.y = event.clientY;

      if (dragging.pan) {
        // Pan in the camera's own plane, scaled so a drag moves the same
        // fraction of the view whatever the zoom level is.
        const speed = (camera.distance * 0.002);
        const right: [number, number, number] = [
          Math.cos(camera.yaw),
          0,
          -Math.sin(camera.yaw),
        ];
        camera.target[0] -= right[0] * dx * speed;
        camera.target[2] -= right[2] * dx * speed;
        camera.target[1] -= dy * speed;
      } else {
        camera.yaw -= dx * 0.006;
        camera.pitch = Math.max(
          -1.5,
          Math.min(1.5, camera.pitch - dy * 0.006),
        );
      }
      schedule();
    };

    const onPointerUp = (event: PointerEvent) => {
      dragging = null;
      canvas.releasePointerCapture(event.pointerId);
    };

    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      camera.distance = Math.max(
        cloud!.extent * 0.05,
        Math.min(cloud!.extent * 12, camera.distance * Math.exp(event.deltaY * 0.001)),
      );
      schedule();
    };

    const onContextMenu = (event: Event) => event.preventDefault();

    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerup", onPointerUp);
    canvas.addEventListener("pointercancel", onPointerUp);
    canvas.addEventListener("wheel", onWheel, { passive: false });
    canvas.addEventListener("contextmenu", onContextMenu);

    const observer = new ResizeObserver(schedule);
    observer.observe(canvas);
    schedule();

    return () => {
      disposed = true;
      if (frame) cancelAnimationFrame(frame);
      observer.disconnect();
      canvas.removeEventListener("pointerdown", onPointerDown);
      canvas.removeEventListener("pointermove", onPointerMove);
      canvas.removeEventListener("pointerup", onPointerUp);
      canvas.removeEventListener("pointercancel", onPointerUp);
      canvas.removeEventListener("wheel", onWheel);
      canvas.removeEventListener("contextmenu", onContextMenu);
      gl.deleteBuffer(order);
      for (const buffer of Object.values(buffers)) gl.deleteBuffer(buffer);
      gl.deleteProgram(program as WebGLProgram);
    };
  }, [cloud]);

  return (
    <div className={styles.stage}>
      <canvas ref={canvasRef} className={styles.canvas} />
      {phase.kind === "ready" ? (
        <>
          <p className={styles.hint}>drag to orbit · shift-drag to pan · scroll to zoom</p>
          <p className={styles.count}>
            {phase.cloud.count.toLocaleString("en-US")} gaussians
            {phase.cloud.total > phase.cloud.count
              ? ` of ${phase.cloud.total.toLocaleString("en-US")}`
              : ""}
          </p>
        </>
      ) : (
        <p className={styles.status}>
          {phase.kind === "loading"
            ? phase.total
              ? `downloading — ${Math.round((phase.loaded / phase.total) * 100)}%`
              : `downloading — ${(phase.loaded / 1e6).toFixed(1)} MB`
            : phase.kind === "parsing"
              ? "reading gaussians…"
              : phase.kind === "error"
                ? phase.message
                : "…"}
        </p>
      )}
    </div>
  );
}

function link(gl: WebGL2RenderingContext): WebGLProgram | string {
  const compile = (type: number, source: string) => {
    const shader = gl.createShader(type)!;
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(shader) ?? "shader failed to compile";
      gl.deleteShader(shader);
      return log;
    }
    return shader;
  };

  const vertex = compile(gl.VERTEX_SHADER, VERTEX);
  if (typeof vertex === "string") return vertex;
  const fragment = compile(gl.FRAGMENT_SHADER, FRAGMENT);
  if (typeof fragment === "string") return fragment;

  const program = gl.createProgram()!;
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    return gl.getProgramInfoLog(program) ?? "program failed to link";
  }
  return program;
}

function attribute(
  gl: WebGL2RenderingContext,
  program: WebGLProgram | string,
  name: string,
  data: Float32Array | Uint8Array,
  size: number,
  type: number,
  normalized: boolean,
): WebGLBuffer {
  const buffer = gl.createBuffer()!;
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);

  const location = gl.getAttribLocation(program as WebGLProgram, name);
  gl.enableVertexAttribArray(location);
  gl.vertexAttribPointer(location, size, type, normalized, 0, 0);
  return buffer;
}
