import { SignJWT, importPKCS8 } from "jose";
import type { Env } from "./types";

// APNs over HTTP/2 with token auth. The same shape as Nudgy's sender, trimmed to alert pushes
// that carry a sound. Deployed Workers speak HTTP/2 to Apple; local `wrangler dev` on macOS does
// not, so a real push is only testable once deployed.

let cachedToken: { value: string; issuedAt: number } | null = null;
const TOKEN_LIFETIME_MS = 40 * 60 * 1000; // Apple accepts 20–60 min; refreshing more often is throttled.

async function providerToken(env: Env): Promise<string | null> {
  if (!env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_KEY_P8) return null;
  if (cachedToken && Date.now() - cachedToken.issuedAt < TOKEN_LIFETIME_MS) return cachedToken.value;
  const key = await importAppleKey(env.APNS_KEY_P8);
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env.APNS_KEY_ID })
    .setIssuer(env.APNS_TEAM_ID)
    .setIssuedAt()
    .sign(key);
  cachedToken = { value, issuedAt: Date.now() };
  return value;
}

/// An Apple .p8 key however it was pasted, rebuilt as the PEM `importPKCS8` wants.
async function importAppleKey(raw: string): Promise<CryptoKey> {
  const body = raw.replace(/\\n/g, "\n").replace(/-----(BEGIN|END) [A-Z ]*PRIVATE KEY-----/g, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  const lines = body.match(/.{1,64}/g) ?? [];
  const pem = ["-----BEGIN PRIVATE KEY-----", ...lines, "-----END PRIVATE KEY-----"].join("\n");
  return importPKCS8(pem, "ES256");
}

export type PushEnv = "sandbox" | "production";

export interface Target {
  token: string;
  env: PushEnv;
}

export interface PushResult {
  ok: boolean;
  status: number;
  reason?: string;
}

/// Apple's answers that mean this token is dead for the app: the app was deleted (410), or the
/// token is for another app/environment (400). The caller forgets the device; it re-registers
/// next launch.
export function tokenIsDead(result: PushResult): boolean {
  return result.status === 410
    || (result.status === 400 && (result.reason === "BadDeviceToken" || result.reason === "DeviceTokenNotForTopic"));
}

/// One alert push that names a sound. iOS plays `sound` (a .caf bundled in the app) on its own
/// when the push arrives — Lock Screen, no tap — unless the phone is on silent or Focus.
export async function sendSound(
  env: Env, target: Target, sound: string, alert: { title: string; body: string }
): Promise<PushResult> {
  const jwt = await providerToken(env);
  if (!jwt) return { ok: false, status: 0, reason: "APNs not configured" };
  const host = target.env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const payload = { aps: { alert, sound, "interruption-level": "time-sensitive" } };
  const response = await fetch(`https://${host}/3/device/${target.token}`, {
    method: "POST",
    redirect: "manual",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (response.ok) return { ok: true, status: response.status };
  const reason = ((await response.json().catch(() => ({}))) as { reason?: string }).reason;
  return { ok: false, status: response.status, reason };
}
