# 01 — Auth & Accounts

## Goal

Every user has an identity from the first launch, without being asked to sign
up before they've seen what the app does. Progress, captures, and generated 3D
models belong to that identity and survive a reinstall once the account is
claimed.

## Design decision: anonymous-first

The app's opening screen is a map with a radius slider
(`lib/screens/map/map_screen.dart`). Putting a login wall in front of that
kills the demo. Supabase supports anonymous sign-in, which issues a real user
row and a real JWT with no credentials.

```
First launch ──► signInAnonymously() ──► user row + JWT
                                            │
                        user swipes, accepts a route, captures a fennec
                                            │
        prompted to save progress ──► linkIdentity / updateUser(email)
                                            │
                              same user_id, now recoverable
```

The critical property: **claiming an account is an upgrade of the existing
user, not a new user**. `auth.uid()` is unchanged, so every row already
written stays attached. Never implement this as "create new account, then copy
rows across" — that path loses data the moment it half-fails.

**Must:** enable anonymous sign-ins in the Supabase dashboard
(Authentication → Providers), and turn on CAPTCHA or rate limiting alongside
it. An open anonymous endpoint is a free user-row generator for anyone who
finds it. See [11](11-security-checklist.md).

## Package

```yaml
dependencies:
  supabase_flutter: ^2.8.0     # verify latest before pinning
  flutter_secure_storage: ^9.2.4
```

`supabase_flutter` persists the session itself. Its default store is
`SharedPreferences`, which on Android is plain XML readable on a rooted
device. Override it with secure storage:

```dart
await Supabase.initialize(
  url: Env.supabaseUrl,
  anonKey: Env.supabaseAnonKey,
  authOptions: FlutterAuthClientOptions(
    localStorage: SecureLocalStorage(), // wraps flutter_secure_storage
    autoRefreshToken: true,
  ),
);
```

The `anonKey` is *designed* to be public — it's a JWT identifying the project
with the `anon` role, and RLS is what protects the data. Shipping it is
expected. The `service_role` key is the opposite: it bypasses RLS entirely and
must never appear anywhere in `lib/`, in `android/`, or in any committed file.

## Sign-in methods

| Method | When | Notes |
| --- | --- | --- |
| Anonymous | First launch, automatic | No UI |
| Email + password | "Save my progress" | Requires email confirmation; handle the deep link |
| Google | Recommended second option | Android setup needs a SHA-1 fingerprint per build variant |
| Apple | **Required** to ship on iOS if you offer Google | App Store rule 4.8 |
| Magic link / OTP | Optional | Simplest to implement, no password reset flow to build |

Starting with anonymous + email covers the product need. Add OAuth when you
have a real user base to keep.

## Auth state in the app

Auth does not belong in `AppBloc`. That bloc already carries 27 fields of tour
state and mixing session lifecycle into it makes both harder to reason about.
Add a sibling:

```
lib/blocs/auth/
  auth_bloc.dart
  auth_event.dart     AppStarted, SignInAnonymously, LinkEmail, SignOut, DeleteAccount
  auth_state.dart     status: unknown | anonymous | authenticated | signedOut
                      userId, email, isAnonymous
```

`AuthBloc` subscribes to `Supabase.instance.client.auth.onAuthStateChange` and
translates it into states. `AppShell` (`lib/app/app_shell.dart`) gates on
`status == unknown` to show a splash while the session restores.

The two blocs communicate one way only: `AuthBloc` emits, and a
`BlocListener` in the shell tells `AppBloc` to reload from the repository on
sign-in and to clear on sign-out. `AppBloc` must not import `AuthBloc`.

### Sign-out must clear local data

```dart
Future<void> signOut() async {
  await _supabase.auth.signOut();
  await _localDb.clearUserScopedTables();   // trips, saved, artifacts, jobs
  await _mediaCache.evictUserFiles();       // captured photos, downloaded .glb
  // Catalogue tables (locations, regions) are not user-scoped — keep them.
}
```

Skipping this leaks one user's captures into the next user's folder screen on
a shared device.

## Profile row

`auth.users` is managed by Supabase and shouldn't be extended directly. Mirror
it with a `profiles` table (schema in [02](02-cloud-database-schema.md))
created by a trigger:

```sql
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', 'Explorer'),
    coalesce(new.raw_user_meta_data->>'locale', 'en')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

`set search_path = ''` on a `security definer` function is not optional —
without it the function is vulnerable to search-path hijacking. Fully qualify
every object name inside such functions.

## Account deletion

Needed for both app stores and for GDPR. A user cannot delete their own
`auth.users` row from the client, so this is an Edge Function using the
service role key:

```
POST /functions/v1/delete-account
  verify caller JWT  →  extract uid
  delete storage objects under captures/{uid}/ and models/{uid}/
  delete from public tables (cascades from profiles)
  supabase.auth.admin.deleteUser(uid)
  return 204
```

The app then wipes local storage and returns to a fresh anonymous session.
Offer an in-app entry point under the existing ACCOUNT section of
`lib/screens/settings/settings_screen.dart:44`.

## Anonymous account expiry

Anonymous users accumulate: every reinstall makes a new one. Schedule a
cleanup (`pg_cron`) that removes anonymous users with no activity for 90 days
and no linked identity. Storage objects go first, then rows.

```sql
select cron.schedule('purge-stale-anon', '0 3 * * *', $$
  select public.purge_anonymous_users(interval '90 days');
$$);
```

Document this in the privacy policy — the settings screen already links to one
(`settings_screen.dart:63`), which currently goes nowhere.

## Quota identity

Per-user GPU quota ([07](07-securing-the-3d-endpoint.md)) keys off
`auth.uid()`. Anonymous users can therefore farm free generations by
reinstalling. Mitigations, in increasing order of friction:

1. Lower quota for anonymous users than for claimed accounts — this doubles as
   a conversion incentive.
2. Require a claimed account for 3D generation entirely.
3. Device attestation (Play Integrity / App Attest) as a secondary signal.

Start with (1). It's the least hostile and the abuse ceiling is low while the
user base is small.

## Testing checklist

- [ ] Cold launch offline → anonymous session restores from secure storage, app usable
- [ ] Link email → `auth.uid()` unchanged, all prior rows still visible
- [ ] Sign out → folder screen empty, catalogue still browsable
- [ ] Sign in as user B on user A's device → none of A's artifacts visible
- [ ] Delete account → storage objects gone, rows gone, app returns to fresh state
- [ ] JWT expiry mid-session → silent refresh, no user-visible error
- [ ] Refresh token rejected (password changed elsewhere) → clean sign-out, not a crash loop
