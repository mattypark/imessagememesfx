-- MemeFX: friends, rooms, and the device tokens a sound is pushed to.

-- One person. `id` is unguessable and doubles as their bearer token (v1 auth), so it never
-- leaves the device that owns it except in the Authorization header.
CREATE TABLE IF NOT EXISTS users (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

-- A person's current push target. One row per user; re-registering replaces it.
CREATE TABLE IF NOT EXISTS devices (
  user_id    TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL,
  env        TEXT NOT NULL DEFAULT 'production',   -- 'sandbox' | 'production'
  updated_at INTEGER NOT NULL
);

-- A room: everyone in it hears what anyone in it sends. `code` is the short join code.
CREATE TABLE IF NOT EXISTS rooms (
  id         TEXT PRIMARY KEY,
  code       TEXT NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  owner      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS memberships (
  room_id   TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS memberships_by_user ON memberships(user_id);

-- One-to-one links from an invite link. Stored both ways so either friend can send to the other.
CREATE TABLE IF NOT EXISTS friends (
  user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  since     INTEGER NOT NULL,
  PRIMARY KEY (user_id, friend_id)
);

-- A pending invite link's code → who created it.
CREATE TABLE IF NOT EXISTS invites (
  code       TEXT PRIMARY KEY,
  owner      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
);

-- Contact matching: sha256(normalized phone or email) → the user who claimed it. Only the hash
-- is stored, never the number itself, so a match needs both sides to already know the contact.
CREATE TABLE IF NOT EXISTS contact_hashes (
  hash    TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE
);
