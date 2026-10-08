/// Unguessable ids and short human codes.

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1 — easy to read aloud

/// A long opaque id (also used as a user's bearer token): 32 url-safe chars from the CSPRNG.
export function newId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// A short room or invite code, e.g. "K7P2QX". Collisions are retried by the caller.
export function newCode(length = 6): string {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

/// What the client typed, cleaned to the code alphabet: upper-cased, the look-alikes folded to
/// their counterparts (O→0 isn't in the set, so O→0 can't help — fold the other way: a typed
/// 0/O both drop, since the alphabet has neither; keep only real code letters and digits).
export function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, "").slice(0, 12);
}
