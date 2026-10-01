PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL,
  name TEXT NOT NULL, bio TEXT NOT NULL DEFAULT '', style TEXT NOT NULL DEFAULT 'solo',
  verified INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS trips (
  id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id),
  title TEXT NOT NULL, country TEXT NOT NULL, city TEXT NOT NULL,
  start TEXT NOT NULL, end TEXT NOT NULL, style TEXT NOT NULL,
  description TEXT NOT NULL, created_at TEXT NOT NULL, CHECK (end >= start)
);
CREATE INDEX IF NOT EXISTS trips_destination ON trips(country, city, start, end);
CREATE TABLE IF NOT EXISTS connections (
  id TEXT PRIMARY KEY, sender_id TEXT NOT NULL REFERENCES users(id),
  recipient_id TEXT NOT NULL REFERENCES users(id),
  status TEXT NOT NULL CHECK(status IN ('pending','accepted','declined')),
  created_at TEXT NOT NULL, CHECK(sender_id != recipient_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS connections_pair ON connections(
  min(sender_id, recipient_id), max(sender_id, recipient_id)
);
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT, connection_id TEXT NOT NULL REFERENCES connections(id),
  sender_id TEXT NOT NULL REFERENCES users(id), body TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS messages_connection ON messages(connection_id, id);
CREATE TABLE IF NOT EXISTS blocks (
  user_id TEXT NOT NULL REFERENCES users(id), blocked_id TEXT NOT NULL REFERENCES users(id),
  PRIMARY KEY(user_id, blocked_id), CHECK(user_id != blocked_id)
);
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY, reporter_id TEXT NOT NULL REFERENCES users(id),
  reported_id TEXT NOT NULL REFERENCES users(id), reason TEXT NOT NULL, created_at TEXT NOT NULL,
  CHECK(reporter_id != reported_id)
);
