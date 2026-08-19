import { createClient } from "@/utils/supabase/client";

/**
 * Calls the Route Generation API from the browser.
 *
 * Same-origin `/api/...`, which `next.config.ts` rewrites onto the Node
 * service. The access token is read from the Supabase session here rather than
 * handed down from a Server Component, so the JWT never has to be serialised
 * into the page's RSC payload to make a client-side request possible.
 */
export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const supabase = createClient();
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;

  const response = await fetch(path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init?.headers ?? {}),
    },
  });

  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as {
      error?: string;
      message?: string;
    };
    throw new ApiError(body.error ?? "server_error", body.message ?? response.statusText);
  }

  return (await response.json()) as T;
}

/** Carries the module's own error code, which the copy in `messageForCode`
 *  turns into something a traveller can act on. */
export class ApiError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}
