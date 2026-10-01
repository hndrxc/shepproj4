# Roam Together

Flutter travel-companion project, with a hosted Supabase backend. Product context:
`web/home.html`. The app uses the remote backend by default; no local Python
server is required.

## Run

```sh
flutter pub get
flutter run -d chrome
```

The entry screen fetches its travel styles over HTTPS from the hosted database.
Full profile, search, matching, and chat screens remain the frontend team's work.

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
dart run tool/verify_cloud.dart
flutter build web --release
```

The live verification script performs a real read from Supabase. Ordinary tests
use mocks or the local Python fixture server (Python 3.12+ required).

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
