# Hosted Supabase backend

## Project and course requirement

**Roam Together** runs in the `hndrxc` organization on Supabase, US East (Ohio),
project reference `ylrgpykdsayuhwbaadij`. The project was created at a quoted
$0/month on the requested free tier. No paid branch, add-on, or upgrade was created.

- Dashboard: https://supabase.com/dashboard/project/ylrgpykdsayuhwbaadij
- HTTPS API: https://ylrgpykdsayuhwbaadij.supabase.co
- Application client: `lib/services/supabase_roam_api.dart`
- Migration: `migrations/20260930235657_roam_together_backend.sql`

This fulfills the described external-server architecture: the Flutter client
contacts Supabase over HTTPS and the database/Auth execute on remote machines.
The app's entry screen reads `travel_styles` from this project at startup. It has
no hardcoded fallback catalog, so connection failures show a retry state.

## Run and configuration

`flutter run -d chrome` uses this hosted project by default. The URL and
**publishable** key are intentionally public client configuration. To use another
project after applying the migration, set `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` using `--dart-define`. Never place a service-role key,
secret key, database password, or management access token in Flutter or Git.

Android's main manifest includes INTERNET permission; macOS debug/release
entitlements allow outgoing network connections. The API uses HTTPS. Android and
macOS runtime builds have not been tested on physical devices in this environment.

`USE_LOCAL_BACKEND=true` explicitly selects the old Python/SQLite adapter. It is
an independent offline fixture environment; it does not share users or data with
Supabase and is not the deployed server.

## Frontend handoff

Use one `SupabaseRoamApi()` instance for the application and call `close()` when
disposing it. It implements the existing `RoamApi` method contract for profiles,
trips, matching, connections, messages, blocking and reporting. The Flutter UI
now includes the mobile home screen, sign-up/login with email-confirmation
handling, trip creation from the search form, paginated matches, and connection
requests. Profile editing, saved-trip management, connection responses, chat,
block/report controls, and logout UI remain to be built; see the
[current app status](../README.md#current-status).

```dart
final api = SupabaseRoamApi();
final signup = await api.register(
  name: name, email: email, password: password, style: 'food',
);
if (signup['confirmation_required'] == true) {
  // Show: confirm your email, then return to the app and sign in.
  return;
}
// Or sign into an already confirmed account:
await api.login(email, password);
final profile = await api.profile();
final trip = await api.createTrip({
  'title': 'Tokyo food tour', 'country': 'Japan', 'city': 'Tokyo',
  'start': futureStartDate, 'end': futureEndDate, 'style': 'food',
});
final savedTrips = await api.trips(filters: {'mine': 'true'});
```

Email confirmation is left enabled. Signup may return `confirmation_required`
instead of a session; this is a normal outcome. After confirming email, users
sign in with their password. The adapter uses the SDK's implicit auth mode and
in-memory sessions; it does not implement deep-link token ingestion or persistent
login. Configure Supabase's Site URL/allowed redirect URLs when the full frontend
is deployed. Supabase's built-in email delivery limits apply; configure your own
SMTP provider before broader use. Email confirmation does **not** verify identity.

Profiles are created lazily on first authenticated login/profile read, with
`verified=false`. Display name/style can come from user metadata, but verification
never does. The SDK handles token refresh in the running app. Logout revokes the
refresh session; already-issued access JWTs can remain valid until expiry.

Cloud differences from the local development API:

- Supabase Auth manages passwords/sessions. Auth result contains `user`,
  `expires_at`, and `confirmation_required`; UI code should not depend on raw tokens.
- `q` searches trip titles; use country/city filters for destination search.
- RLS can hide unauthorized rows as empty lists or not-found results. Do not
  interpret an empty message list as permission to send; writes are checked too.
- Profiles have no stored email column; only the signed-in user gets their own
  Auth email in `profile()`. Public discovery cannot read email addresses.
- IDs use UUIDs, except messages use integer IDs.

## Database access model

All eight public tables have Row Level Security enabled. Privileges and policies
are both restricted:

- `travel_styles`: public read-only catalog.
- `profiles`: owner edits name/bio/style; discovery sees verified, unblocked
  profiles. Clients cannot write verification status or reassign identities.
- `trips`: owner creates/deletes; other users see verified, unblocked owners.
- `connections`: both travelers must be verified; sender requests and recipient
  accepts/declines once. Only status is client-updatable.
- `messages`: accepted, verified, unblocked participants only; sender cannot be
  impersonated. Message ordering is explicitly ascending for cursor polling.
- `blocks`: owner writes; the relationship excludes both directions from discovery
  and chat. There is no unblock flow in this MVP.
- `reports`: reporter inserts/reads; the target cannot see the report. Review via
  the authenticated project dashboard/operator tools.

`find_travel_matches` runs as the caller under RLS. It matches city/country and
inclusive overlapping dates, ranks same-style trips first, and paginates.
Internal `roam_private` policy helpers are security-definer only to avoid recursive
policy lookups; they require an authenticated caller, have an empty search path,
return only access decisions, and are not in the exposed API schema.

Only a trusted project operator may mark a profile verified after a real external
identity check. Do not use signup metadata or client edits for this. Government-ID
verification services, payments/premium features, safety staffing, maps/check-ins,
and group booking remain outside this MVP.

## Verification evidence and rerunning checks

Completed against the actual hosted project:

1. Applied the migration and verified its remote history. The local filename was
   aligned to the version assigned by Supabase, avoiding duplicate application.
2. Ran `tests/rls.sql` on the hosted database. It creates temporary synthetic Auth
   users and profiles inside a transaction, then executes writes as `authenticated`
   with test JWT subject settings. Assertions cover trip persistence, matching,
   ownership spoofing, verification escalation, consent, private messages, blocking
   in both directions, report privacy, and anonymous denial. **ROLLBACK removes
   every test user/row**. No emails are sent. These tests exercise database policy
   behavior, not the hosted signup/email-delivery flow.
3. Ran `dart run tool/verify_cloud.dart`: the actual Dart client read all six
   catalog rows over the public HTTPS API using the publishable key.
4. Supabase security advisor returned no findings. Performance advisor only noted
   newly created unused indexes, retained to support FK lookups and access rules:
   https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index
5. Flutter unit/widget/integration tests cover both adapters, and static analysis
   and the web release build pass.

To rerun the database assertions, execute the complete `tests/rls.sql` in the
Supabase SQL editor as the project operator. Do not remove the final ROLLBACK.
The live Dart verification is read-only and can run at any time:

```sh
dart run tool/verify_cloud.dart
```

Cloud authentication with a real confirmed user and the complete frontend journey
still need testing with confirmed, verified accounts and the deployed email
configuration. No real users, demo passwords, service-role keys, or private
records were added to Git.
