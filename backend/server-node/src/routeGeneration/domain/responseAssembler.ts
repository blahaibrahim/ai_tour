/**
 * Layer 3 — Response Assembler.
 *
 * Builds the final route object: segments, mode tags, checkpoint radii
 * (spec §3). Pure — no dependencies, so it is one of the two components built
 * first (spec §9 step 4).
 *
 * STATUS: stub.
 *
 * The one output rule that matters downstream: **every segment carries its own
 * mode tag**. That tagging is what lets the AR/UI layer render "drive here,
 * then walk this loop" without knowing how the segment was generated
 * (spec §5). A client that has to infer the mode from cluster ids is a client
 * that will get it wrong the first time a cluster has one stop in it.
 *
 * Segment shape, per the hybrid transport model:
 *   • inter-cluster leg → mode 'drive', anchor point to anchor point,
 *     `clusterId: null`
 *   • intra-cluster leg → mode 'walk', stop to stop, `clusterId` set
 *
 * Parking availability and one-way / restricted-zone streets are explicitly
 * out of scope for the demo phase, and are isolated to the driving-segment
 * handling here and in the Adapter so that adding them later does not require
 * a redesign (spec §10). Keep that isolation.
 */
import { NotImplementedError } from "../errors";
import { Cluster, RouteRequest, RouteResponse, Segment, TimeEstimate } from "../types";

export interface AssembleInput {
  request: RouteRequest;
  orderedClusters: Cluster[];
  segments: Segment[];
  estimate: TimeEstimate;
}

/** Spec §7, transcribed: `ResponseAssembler.assemble(...)`. */
export function assemble(_input: AssembleInput): RouteResponse {
  throw new NotImplementedError("ResponseAssembler.assemble");
}

/**
 * Builds the mode-tagged segment list from the ordered clusters and the
 * provider's per-leg geometry.
 *
 * Split out from `assemble` because it is the part with the real branching,
 * and because the "correct segment count, mode tags present" end-to-end
 * assertion in spec §11 is easiest to write against it directly.
 */
export function buildSegments(
  _orderedClusters: Cluster[],
  _driveLegs: Segment[],
  _walkLegs: Segment[],
): Segment[] {
  throw new NotImplementedError("ResponseAssembler.buildSegments");
}
