import type { Env, Room, User } from "./types";
import { newCode, newId, normalizeCode } from "./ids";
import { sendSound, tokenIsDead, type Target } from "./apns";

// MemeFX backend. A person registers a device, joins rooms (or links a friend, or matches
// contacts), and sends a sound; everyone reachable gets a push that plays it on its own.
//
// Auth (v1): the user's id is an unguessable bearer token. Every call but /v1/users carries
// `Authorization: Bearer <userId>`; the handler trusts that id and no other.

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      return await route(request, env, url);
    } catch (error) {
      // User-facing errors stay one plain line; detail goes to the log.
      console.error(`${url.pathname}: ${error instanceof Error ? error.message : error}`);
      if (error instanceof HttpError) return json({ error: error.message }, error.status);
      return json({ error: "Something went wrong." }, 500);
    }
  },
};

async function route(request: Request, env: Env, url: URL): Promise<Response> {
  const path = url.pathname;

  if (path === "/health") return json({ ok: true });

  // An invite link opened in a browser: a tiny page that hands off to the app.
  if (request.method === "GET" && path.startsWith("/i/")) return invitePage(path.slice(3));

  if (request.method !== "POST") throw new HttpError(405, "Use POST.");
  const body = await readJson(request);

  // Make a user: the only call that needs no auth. Returns the id that is also the token.
  if (path === "/v1/users") return createUser(env, body);

  const userId = bearer(request);
  await requireUser(env, userId);

  switch (path) {
    case "/v1/register": return register(env, userId, body);
    case "/v1/rooms": return createRoom(env, userId, body);
    case "/v1/rooms/join": return joinRoom(env, userId, body);
    case "/v1/rooms/leave": return leaveRoom(env, userId, body);
    case "/v1/rooms/list": return listRooms(env, userId);
    case "/v1/invite": return createInvite(env, userId);
    case "/v1/invite/accept": return acceptInvite(env, userId, body);
    case "/v1/contacts/match": return matchContacts(env, userId, body);
    case "/v1/send": return send(env, userId, body);
    default: throw new HttpError(404, "No such endpoint.");
  }
}

// MARK: - Users & devices

async function createUser(env: Env, body: Record<string, unknown>): Promise<Response> {
  const name = cleanName(body.name);
  const id = newId();
  await env.DB.prepare("INSERT INTO users (id, name, created_at) VALUES (?, ?, ?)")
    .bind(id, name, Date.now()).run();
  return json({ userId: id, name });
}

async function register(env: Env, userId: string, body: Record<string, unknown>): Promise<Response> {
  const token = str(body.token, "token");
  const pushEnv = body.env === "sandbox" ? "sandbox" : "production";
  await env.DB.prepare(
    "INSERT INTO devices (user_id, token, env, updated_at) VALUES (?1, ?2, ?3, ?4) " +
    "ON CONFLICT(user_id) DO UPDATE SET token = ?2, env = ?3, updated_at = ?4"
  ).bind(userId, token, pushEnv, Date.now()).run();
  return json({ ok: true });
}

// MARK: - Rooms

async function createRoom(env: Env, userId: string, body: Record<string, unknown>): Promise<Response> {
  const name = cleanName(body.name, "Room");
  const id = newId();
  const code = await uniqueCode(env);
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO rooms (id, code, name, owner, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(id, code, name, userId, now),
    env.DB.prepare("INSERT INTO memberships (room_id, user_id, joined_at) VALUES (?, ?, ?)")
      .bind(id, userId, now),
  ]);
  return json({ roomId: id, code, name });
}

async function joinRoom(env: Env, userId: string, body: Record<string, unknown>): Promise<Response> {
  const code = normalizeCode(str(body.code, "code"));
  const room = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(code).first<Room>();
  if (!room) throw new HttpError(404, "No room with that code.");
  await env.DB.prepare(
    "INSERT INTO memberships (room_id, user_id, joined_at) VALUES (?, ?, ?) " +
    "ON CONFLICT(room_id, user_id) DO NOTHING"
  ).bind(room.id, userId, Date.now()).run();
  return json({ roomId: room.id, name: room.name });
}

async function leaveRoom(env: Env, userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomId = str(body.roomId, "roomId");
  await env.DB.prepare("DELETE FROM memberships WHERE room_id = ? AND user_id = ?")
    .bind(roomId, userId).run();
  return json({ ok: true });
}

async function listRooms(env: Env, userId: string): Promise<Response> {
  const rows = await env.DB.prepare(
    "SELECT r.id, r.code, r.name, (SELECT COUNT(*) FROM memberships m2 WHERE m2.room_id = r.id) AS members " +
    "FROM rooms r JOIN memberships m ON m.room_id = r.id WHERE m.user_id = ? ORDER BY r.created_at"
  ).bind(userId).all();
  return json({ rooms: rows.results });
}

// MARK: - Invite links (one-to-one)

async function createInvite(env: Env, userId: string): Promise<Response> {
  const code = await uniqueInvite(env);
  await env.DB.prepare("INSERT INTO invites (code, owner, created_at) VALUES (?, ?, ?)")
    .bind(code, userId, Date.now()).run();
  return json({ code, url: `https://memefx.workers.dev/i/${code}` });
}

async function acceptInvite(env: Env, userId: string, body: Record<string, unknown>): Promise<Response> {
  const code = str(body.code, "code");
  const invite = await env.DB.prepare("SELECT owner FROM invites WHERE code = ?").bind(code)
    .first<{ owner: string }>();
  if (!invite) throw new HttpError(404, "That invite link has expired.");
  if (invite.owner === userId) throw new HttpError(400, "That's your own invite.");
  await linkFriends(env, userId, invite.owner);
  await env.DB.prepare("DELETE FROM invites WHERE code = ?").bind(code).run();
  return json({ ok: true, friendId: invite.owner });
}

async function linkFriends(env: Env, a: string, b: string): Promise<void> {
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO friends (user_id, friend_id, since) VALUES (?, ?, ?) " +
      "ON CONFLICT(user_id, friend_id) DO NOTHING").bind(a, b, now),
    env.DB.prepare("INSERT INTO friends (user_id, friend_id, since) VALUES (?, ?, ?) " +
      "ON CONFLICT(user_id, friend_id) DO NOTHING").bind(b, a, now),
  ]);
}

// MARK: - Contact matching

async function matchContacts(env: Env, userId: string, body: Record<string, unknown>): Promise<Response> {
  // `mine` are hashes of the user's own numbers/emails (claim them); `others` are their
  // contacts' hashes (match them). Only hashes are stored or compared, never the raw values.
  const mine = hashList(body.mine);
  const others = hashList(body.others);
  if (mine.length) {
    await env.DB.batch(mine.slice(0, 20).map((hash) =>
      env.DB.prepare("INSERT INTO contact_hashes (hash, user_id) VALUES (?, ?) " +
        "ON CONFLICT(hash) DO UPDATE SET user_id = excluded.user_id").bind(hash, userId)));
  }
  if (!others.length) return json({ friends: [] });
  const placeholders = others.slice(0, 500).map(() => "?").join(",");
  const rows = await env.DB.prepare(
    `SELECT DISTINCT user_id FROM contact_hashes WHERE hash IN (${placeholders}) AND user_id != ?`
  ).bind(...others.slice(0, 500), userId).all<{ user_id: string }>();
  const matched = rows.results.map((r) => r.user_id);
  for (const other of matched) await linkFriends(env, userId, other);
  return json({ friends: matched });
}

// MARK: - Send

async function send(env: Env, userId: string, body: Record<string, unknown>): Promise<Response> {
  const sound = soundName(body.sound);
  const title = str(body.title ?? "MemeFX", "title").slice(0, 80);
  const sender = await env.DB.prepare("SELECT name FROM users WHERE id = ?").bind(userId)
    .first<{ name: string }>();
  const alert = { title, body: `from ${sender?.name ?? "a friend"}` };

  const recipients = await reach(env, userId, body);
  if (!recipients.size) throw new HttpError(400, "No one to send to yet.");

  const targets = await devicesFor(env, [...recipients]);
  const results = await Promise.all(targets.map((t) => deliver(env, t, sound, alert)));
  return json({ sent: results.filter((r) => r.ok).length, recipients: recipients.size });
}

/// Who a send reaches: a room's members, a single friend, or all friends — never anyone the
/// sender isn't linked to. The sender themselves is left out.
async function reach(env: Env, userId: string, body: Record<string, unknown>): Promise<Set<string>> {
  const out = new Set<string>();
  if (typeof body.roomId === "string") {
    const inRoom = await env.DB.prepare("SELECT 1 FROM memberships WHERE room_id = ? AND user_id = ?")
      .bind(body.roomId, userId).first();
    if (!inRoom) throw new HttpError(403, "You're not in that room.");
    const rows = await env.DB.prepare("SELECT user_id FROM memberships WHERE room_id = ?")
      .bind(body.roomId).all<{ user_id: string }>();
    for (const r of rows.results) out.add(r.user_id);
  } else if (typeof body.toUserId === "string") {
    const linked = await env.DB.prepare("SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ?")
      .bind(userId, body.toUserId).first();
    if (!linked) throw new HttpError(403, "You're not linked to that person.");
    out.add(body.toUserId);
  } else {
    const rows = await env.DB.prepare("SELECT friend_id FROM friends WHERE user_id = ?")
      .bind(userId).all<{ friend_id: string }>();
    for (const r of rows.results) out.add(r.friend_id);
  }
  out.delete(userId);
  return out;
}

async function devicesFor(env: Env, userIds: string[]): Promise<Array<Target & { userId: string }>> {
  if (!userIds.length) return [];
  const placeholders = userIds.map(() => "?").join(",");
  const rows = await env.DB.prepare(
    `SELECT user_id, token, env FROM devices WHERE user_id IN (${placeholders})`
  ).bind(...userIds).all<{ user_id: string; token: string; env: "sandbox" | "production" }>();
  return rows.results.map((r) => ({ userId: r.user_id, token: r.token, env: r.env }));
}

async function deliver(env: Env, target: Target & { userId: string }, sound: string, alert: { title: string; body: string }) {
  const result = await sendSound(env, target, sound, alert);
  if (tokenIsDead(result)) {
    await env.DB.prepare("DELETE FROM devices WHERE user_id = ? AND token = ?")
      .bind(target.userId, target.token).run();
  }
  return result;
}

// MARK: - helpers

class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

async function requireUser(env: Env, userId: string): Promise<User> {
  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userId).first<User>();
  if (!user) throw new HttpError(401, "Unknown user. Open MemeFX to set up again.");
  return user;
}

function bearer(request: Request): string {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(\S+)$/i);
  if (!match || !match[1]) throw new HttpError(401, "Missing credentials.");
  return match[1];
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  if (!request.headers.get("content-type")?.includes("application/json")) return {};
  return (await request.json().catch(() => ({}))) as Record<string, unknown>;
}

function str(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) throw new HttpError(400, `Missing ${field}.`);
  return value.trim();
}

function cleanName(value: unknown, fallback = "Someone"): string {
  const name = typeof value === "string" ? value.trim().slice(0, 40) : "";
  return name || fallback;
}

/// A sound name is a bare .caf file — no path, no surprises — so the push can't point iOS
/// anywhere but a bundled sound.
function soundName(value: unknown): string {
  const name = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9_-]+\.caf$/.test(name)) throw new HttpError(400, "Bad sound.");
  return name;
}

function hashList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((h): h is string => typeof h === "string" && /^[a-f0-9]{64}$/.test(h));
}

async function uniqueCode(env: Env): Promise<string> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newCode();
    const taken = await env.DB.prepare("SELECT 1 FROM rooms WHERE code = ?").bind(code).first();
    if (!taken) return code;
  }
  throw new HttpError(503, "Couldn't make a room code, try again.");
}

async function uniqueInvite(env: Env): Promise<string> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newCode(8);
    const taken = await env.DB.prepare("SELECT 1 FROM invites WHERE code = ?").bind(code).first();
    if (!taken) return code;
  }
  throw new HttpError(503, "Couldn't make an invite, try again.");
}

function invitePage(code: string): Response {
  const safe = code.replace(/[^A-Za-z0-9]/g, "").slice(0, 16);
  const deepLink = `memefx://invite?code=${safe}`;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MemeFX invite</title>
<style>:root{color-scheme:light dark}body{margin:0;min-height:100vh;display:grid;place-items:center;
font:600 17px/1.4 -apple-system,system-ui,sans-serif;background:#F3EFE6;color:#18181B;text-align:center}
@media(prefers-color-scheme:dark){body{background:#0E0E10;color:#F6F3EC}}
.card{padding:32px}a.btn{display:inline-block;margin-top:20px;padding:14px 24px;border-radius:999px;
background:#FF5A36;color:#1A0E0A;text-decoration:none;font-weight:800}.hint{margin-top:16px;opacity:.6;font-size:14px}</style>
</head><body><div class="card"><div style="font-size:44px">🔊</div>
<h1>Join on MemeFX</h1><p>Open MemeFX to add your friend and start sending sounds.</p>
<a class="btn" href="${deepLink}">Open MemeFX</a>
<p class="hint">Don't have it yet? Ask your friend for the TestFlight link.</p></div>
<script>setTimeout(function(){location.href=${JSON.stringify(deepLink)}},400)</script></body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8" } });
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
