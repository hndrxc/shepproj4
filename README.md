# Roam Together

Flutter travel-companion app with a hosted Supabase backend. The mobile home
screen is based on the design reference in [`web/home.html`](web/home.html).
The app uses the remote backend by default; no local Python server is required.

## Current status

The app now includes a mobile home screen, sign-up/login, and a working
search-to-matches flow wired to the shared API client.

| Area | Status |
| --- | --- |
| Home screen | Hero image, destination/date/style form, feature sections, and travel styles fetched from the backend with loading and retry states. |
| Authentication | Sign-up and login screens, travel-style selection, validation, API errors, and an email-confirmation notice. The session is shared across screens and held in memory. |
| Trip creation and matching | Submitting the search form signs the user in if needed, saves a trip, and opens matches for the same destination and overlapping dates, with same-style trips ranked first. |
| Match results | Loading, empty, error/retry, and pagination states; traveler/trip details and a Connect action that sends a connection request. |
| Backend | Hosted database/Auth, profiles, trip creation/listing/deletion, search/matching, connection requests/responses, messages, blocking/reporting, and Row Level Security. Both cloud and optional local adapters are implemented. |

Still to build: profile editing, saved-trip listing/deletion, incoming/outgoing
connection management and accept/decline screens, chat, block/report controls,
and logout UI. Their API methods exist, but they are not yet exposed through
dedicated Flutter screens. Persistent login and email-confirmation deep links
are also not implemented.

Matching requires a verified profile, and connection requests require both
travelers to be verified. New profiles start unverified; only a trusted operator
can record verification after an external identity check. Email confirmation
does not verify identity, and there is no automated ID-verification service yet.

The marketing copy includes planned services such as premium memberships,
payments, maps/check-ins, group bookings, and a staffed safety line. These are
not implemented. The complete hosted signup-to-connection journey still needs
testing with confirmed, verified accounts; Android/macOS runtime builds have
not been tested on physical devices in this environment.

## Run

Use a Flutter SDK that includes Dart compatible with `^3.13.1`, as required by
[`pubspec.yaml`](pubspec.yaml).

```sh
flutter pub get
flutter run -d chrome
```

To try the flow, enter a country and city, pick future travel dates, choose a
travel style, and submit the search form. Complete sign-up/login when prompted.
If sign-up requires email confirmation, confirm your email, then log in and
submit the form again. Each submission saves a new trip before loading matches;
an unverified account can save a trip but will receive a verification error when
loading matches.

To use a different hosted project after applying the migration, supply
`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` with `--dart-define`. See the
[hosted backend guide](supabase/README.md) for configuration and access rules.

## External server component

- Project: **Roam Together**, organization **hndrxc**, region **US East (Ohio)**.
- Free-tier project, quoted **$0/month** when created; no paid resources added.
- API: `https://ylrgpykdsayuhwbaadij.supabase.co`.
- [Supabase dashboard](https://supabase.com/dashboard/project/ylrgpykdsayuhwbaadij).
- Database/Auth run on Supabase's machines, independently of the Flutter device.
- [Hosted backend setup, security and test evidence](supabase/README.md).

The implementation is `lib/services/supabase_roam_api.dart`. Database migration
and rollback-only authorization tests are versioned in `supabase/`.

## Checks

```sh
flutter analyze
flutter test
python3 -m unittest discover -s backend/tests -v
dart run tool/verify_cloud.dart
flutter build web --release
```

The live verification script performs a read-only catalog request to Supabase.
Flutter tests cover the API adapters, local-server integration, and the home
screen's catalog/retry behavior; they do not yet cover the full auth/search/
connection UI flow. Ordinary tests use mocks or the local Python fixture server
(Python 3.12+ required). Backend tests exercise persistence and authorization in
temporary databases. Hosted RLS test instructions and earlier verification
evidence are in the [hosted backend guide](supabase/README.md).

## Optional local development backend

The earlier Python/SQLite backend is retained for offline development and tests.
See [its guide](backend/README.md). Select it explicitly:

```sh
python3 -m backend.server --origin http://localhost:5173
flutter run -d chrome --web-hostname localhost --web-port 5173 \
  --dart-define=USE_LOCAL_BACKEND=true \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/
```

Local and cloud databases/users are separate. Do not use the local-only mode as
proof of the course's remote-server requirement.
