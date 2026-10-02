# Roam Together backend

> This is the optional local/offline development backend. The app now defaults to the hosted Supabase backend documented in `../supabase/README.md`, which provides the remote server component.

Carter's server component for the Flutter project. The product reference is
`web/home.html`: traveler profiles, destination/date/style discovery, connections,
and chat. This is a runnable **local/classroom MVP**, using Python 3.12+ and SQLite
with no pip packages or hosted accounts required. The Flutter app now includes
home, sign-up/login, and search-to-matches screens with connection requests;
`lib/services/roam_api.dart` supplies the local API integration layer. See the
[current app status](../README.md#current-status) for remaining frontend work.

## Run from the repository root

```sh
python3 -m backend.server --origin http://localhost:5173
```

API: `http://127.0.0.1:8080/api/`. Health: `GET /api/health`.
Data persists in `backend/data/roam.sqlite3` (ignored by Git). Override with
`--database PATH` or `ROAM_DATABASE`. Back up the SQLite database with SQLite's
backup tooling, including pending WAL state; do not copy only a live main file.

Use a separate database for the synthetic demo:

```sh
python3 -m backend.manage --database backend/data/demo.sqlite3 seed-demo
python3 -m backend.server --database backend/data/demo.sqlite3 --origin http://localhost:5173
```

The seed command prints a generated password for `alex@example.test`,
`sam@example.test`, and `jordan@example.test`. Alex and Sam have matching Tokyo
trips 30 days from the seed date. Jordan has a Kyoto trip. Seeding refuses a
nonempty database. These are fictional users; their verification flags are
**test fixtures**, not real identity verification.

## Flutter handoff

```sh
flutter run -d chrome --web-hostname localhost --web-port 5173 \
  --dart-define=USE_LOCAL_BACKEND=true --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/
```

The home screen loads travel styles from the selected backend, with loading and
retry states. The app shares one API instance across home, auth, and matches
screens. Additional screens can use the same `RoamApi` contract:

```dart
import 'package:shepproj4/services/roam_api.dart';

final api = RoamApi();
await api.login('alex@example.test', demoPassword);
final ownTrips = await api.trips(filters: {'mine': 'true'});
final tripId = (ownTrips['items'] as List).first['id'] as String;
final matches = await api.matches(tripId);
final travelerId = (matches['items'] as List).first['owner_id'] as String;
final connection = await api.connect(travelerId);
// The recipient logs in on a separate client, lists connections, and calls:
// await recipientApi.respond(connection['id'] as String, accept: true);
await api.sendMessage(connection['id'] as String, 'Want to explore together?');
// Poll messages with the previous response's next_after to fetch only new rows.
// Catch RoamApiException to display API errors. Dispose with api.close().
```

Keep the token in memory (the supplied client does). Passwords are required at
registration even though the reference HTML signup mockup omits the field.
When `RoamApiException.statusCode == 401`, return to sign-in; a protected-endpoint
401 clears the client's expired token. A 403 can mean verification, consent, or
blocking is required; show the server's message.

For Android emulator development use `http://10.0.2.2:8080/api/`; a physical device
needs the development machine's reachable LAN address. Bind the server with
`--host 0.0.0.0` only on a trusted development network and permit the port locally.
Android debug builds may require an INTERNET permission and a **debug-only**
cleartext network configuration for local HTTP. macOS requires an outgoing-network
entitlement. Use HTTPS for deployed clients; never enable general release
cleartext access just to run a demo. WSL networking/firewall settings may affect
host or device reachability. A web deployment and this Python API are separate
services; the Flutter web build alone does not deploy the backend.

## API contract

Send JSON with `Content-Type: application/json` for bodies. Every endpoint except
health, styles, register, and login requires `Authorization: Bearer TOKEN`.
IDs are strings except message IDs, which are increasing integers. Dates are
`YYYY-MM-DD`. Errors consistently use
`{"error":{"status":400,"message":"..."}}`.

| Method/path under `/api` | Request / behavior |
| --- | --- |
| `GET /health` | `{"status":"ok"}` |
| `GET /styles` | `{"items":["solo","chill","adventure","luxury","budget","food"]}` |
| `POST /auth/register` | `name`, `email`, `password` (12–128 characters), optional `style`; returns 201 with `token`, Unix `expires_at`, `user` |
| `POST /auth/login` | `email`, `password`; returns same session shape |
| `POST /auth/logout` | Revokes current token |
| `GET /me` | Own profile plus email |
| `PATCH /me` | Any of `name`, `bio`, `style`; verification and identity fields cannot be changed here |
| `POST /trips` | `title`, `country`, `city`, `start`, `end`, `style`, optional `description`; returns saved trip, 201 |
| `GET /trips` | Optional `country`, `city`, `start`, `end`, `style`, `q`, `mine=true`, `limit`, `offset` |
| `DELETE /trips/{id}` | Owner only; returns `{"deleted":true}` |
| `GET /matches?trip_id=ID` | Matches for your trip; requires your verification; same destination and overlapping dates, same-style trips first |
| `POST /connections` | `recipient_id`; creates a pending connection (201); both users must be verified |
| `GET /connections` | Your incoming/outgoing connections, including status; supports `limit`, `offset` |
| `PATCH /connections/{id}` | Recipient chooses `status`: `accepted` or `declined`, once while pending |
| `POST /connections/{id}/messages` | `body`; accepted connection participants only; returns saved message (201) |
| `GET /connections/{id}/messages` | Optional `after` message ID and `limit`; returns `items` and `next_after` |
| `POST /blocks` | `user_id`; idempotent; prevents discovery and messaging in either direction |
| `POST /reports` | `user_id`, `reason`; saves for manual review; returns report `id` and `status: received` (201) |

Trip and connection lists return `items` and nullable `next_offset`. Default page
size is 20, maximum 100. Message polling uses `next_after`, initially 0; stop
polling on logout, block, or screen disposal. Messages are plain text: render them
as text, not HTML. Chat is polling-based, not WebSocket delivery or end-to-end
encryption.

Trip creation example:

```json
{
  "title": "Tokyo food tour",
  "country": "Japan",
  "city": "Tokyo",
  "start": "2027-06-14",
  "end": "2027-06-21",
  "style": "food",
  "description": "Looking for a companion to explore local food markets."
}
```

Use future dates when trying this example. Search dates mean **overlap**, inclusive
of both ends, not exact equality. Country/city equality ignores ASCII case; use
consistent location-picker spellings, including accents. The `q` filter searches
trip title, country, city, and owner name. Only active trips appear in searches
(including `mine=true`). Unverified owners can save/view their own plans but do
not appear in other users' discovery. Matching returns trips, so a traveler with
multiple plans can occur more than once. Email, password hashes, and sessions
never appear in search or match results. Connection requests are unique per pair;
declined requests cannot be resent in this MVP. Trip editing is delete/recreate.

## Verification and moderation

No endpoint accepts a client-supplied verified flag. After actually performing an
external/manual identity check, an operator with database access can record it:

```sh
python3 -m backend.manage --database backend/data/roam.sqlite3 verify \
  --email traveler@example.com --confirmed-external-check
python3 -m backend.manage --database backend/data/roam.sqlite3 revoke-verification \
  --email traveler@example.com
python3 -m backend.manage --database backend/data/roam.sqlite3 reports
```

The operator commands are local, not exposed through HTTP. Reports are stored;
there is no staffed safety line, automatic moderation, or notification service.
Blocking hides the pair from discovery/connections and disables access to their
chat history and new messages, while retaining records for review.

## Scope and deployment limits

Implemented: registration/login/logout, editable profiles, persistent trip plans,
search and matching, consent-based connections, persistent chat, block/report,
server-controlled verification state, Flutter client, and automated tests.

The marketing page also advertises payments, premium benefits, government-ID
verification, location maps, group bookings, insurance/referrals, check-ins and a
24/7 safety line. Those require separate product decisions/providers and are
**not implemented or simulated as real services**. No payment or ID data is
collected. The static HTML remains a design reference; the Flutter app implements
the home, auth, trip creation, matches, and connection-request flow. Profile,
saved-trip management, connection-response, and chat screens remain frontend work.

This standard-library HTTP server is for local/classroom use. Before public use,
add a production server/TLS proxy, authentication rate limiting, account recovery,
email verification, operational monitoring, automated moderation workflows and a
real verification provider. Use a protected persistent volume for SQLite. Session
tokens expire in seven days, are stored hashed, and are revocable by logout;
passwords use salted scrypt hashes. CORS is an exact allowlist (`--origin` may be
repeated); no browser origins are allowed by default. Request bodies are limited
to 64 KiB. CORS does not replace authentication or network access controls.

## Validation

```sh
python3 -m unittest discover -s backend/tests -v
flutter analyze
flutter test
flutter build web --release
```

Backend tests use temporary databases and an ephemeral HTTP port. They exercise
persistence, authentication, ownership, search, matching, consent, message
privacy, blocking/report storage, pagination, CORS and malformed requests.
Client tests cover request serialization, authentication state, and error handling.
