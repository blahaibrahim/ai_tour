import { fetchCities, fetchThemesAndCategories, requireSession } from "@/lib/api";

import GeneratePlanner from "./GeneratePlanner";

/**
 * The planning surface.
 *
 * The vocabulary is loaded here, on the server, because it is the same for
 * everybody and there is no reason to make the browser wait for two round trips
 * before it can draw the map. Which themes a *city* can answer is narrower than
 * this union, and the planner re-reads that per selection.
 */
export default async function GeneratePage() {
  const session = await requireSession();
  const [cities, vocabulary] = await Promise.all([
    fetchCities(session.token),
    fetchThemesAndCategories(session.token),
  ]);

  return (
    <GeneratePlanner
      // A city still in `planning` is listed by the API but cannot be routed.
      // Offering it here would be offering a request the server will refuse.
      cities={cities.filter((city) => city.rollout_status !== "planning")}
      themes={vocabulary.themes}
    />
  );
}
