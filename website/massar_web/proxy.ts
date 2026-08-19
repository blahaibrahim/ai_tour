import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Session refresh and the signed-out redirect.
 *
 * `proxy.ts`, not `middleware.ts`: Next 16 deprecated the middleware file
 * convention and renamed it — same behaviour, same matcher, different export.
 *
 * The one rule worth restating from Supabase's own guide: nothing may run
 * between `createServerClient` and `getUser()`. The call is what refreshes an
 * expiring token and writes the rotated cookie onto the response, and logic
 * wedged in front of it produces cross-browser session bugs that are miserable
 * to track down.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user && !isPublic(request.nextUrl.pathname)) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    return NextResponse.redirect(url);
  }

  return response;
}

/**
 * The two pages a visitor with no session is allowed to see: the landing page
 * and the form.
 *
 * `/` is matched exactly rather than by prefix, which every path shares — the
 * whole site would be public. Everything else still bounces to `/login`, so a
 * deep link to a route survives sign-in as a link somebody can retry, rather
 * than dumping the visitor on the marketing page with no idea what happened.
 */
function isPublic(pathname: string): boolean {
  return pathname === "/" || pathname.startsWith("/login");
}

export const config = {
  matcher: [
    /*
     * Pages, but not static assets and not `/api`.
     *
     * `/api` is excluded on purpose. It is rewritten to the Node service, which
     * answers an expired session with its own `401` — whereas this proxy would
     * answer it with a redirect to `/login`, and a `fetch` that quietly follows
     * one comes back as a 200 full of HTML. A JSON caller deserves a status it
     * can branch on, not a sign-in page it will fail to parse.
     */
    /*
     * `apk` is in the extension list for the same reason the images are: the
     * landing page's download button is public, and a session check on it
     * answers a signed-out visitor with a redirect to `/login`. A browser
     * following that saves the sign-in page under the name of the APK.
     */
    "/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|geojson|apk)$).*)",
  ],
};
