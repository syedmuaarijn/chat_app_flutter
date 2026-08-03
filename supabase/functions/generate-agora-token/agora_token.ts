/**
 * Agora AccessToken2 (RTC Token) builder for Deno / Supabase Edge Functions.
 *
 * Based on Agora's open-source token builder specification.
 * Generates tokens compatible with agora_rtc_engine 6.x.
 *
 * Reference: https://github.com/AgoraIO/Tools/tree/master/DynamicKey/AgoraDynamicKey
 */

// ── Privilege constants ───────────────────────────────────────────────────────
const PRIVILEGES = {
  joinChannel: 1,
  publishAudioStream: 2,
  publishVideoStream: 3,
  publishDataStream: 4,
};

// ── Utility: big-endian byte writers ─────────────────────────────────────────
function packUint16(value: number): Uint8Array {
  const buf = new Uint8Array(2);
  buf[0] = (value >> 8) & 0xff;
  buf[1] = value & 0xff;
  return buf;
}

function packUint32(value: number): Uint8Array {
  const buf = new Uint8Array(4);
  buf[0] = (value >> 24) & 0xff;
  buf[1] = (value >> 16) & 0xff;
  buf[2] = (value >> 8) & 0xff;
  buf[3] = value & 0xff;
  return buf;
}

function packString(str: string): Uint8Array {
  const encoded = new TextEncoder().encode(str);
  const lenBuf = packUint16(encoded.length);
  const result = new Uint8Array(lenBuf.length + encoded.length);
  result.set(lenBuf, 0);
  result.set(encoded, lenBuf.length);
  return result;
}

function packPrivileges(privileges: Map<number, number>): Uint8Array {
  const parts: Uint8Array[] = [];
  // Pack count
  parts.push(packUint16(privileges.size));
  // Pack each privilege as (key: uint16, expireTs: uint32)
  for (const [key, val] of privileges) {
    parts.push(packUint16(key));
    parts.push(packUint32(val));
  }
  return concat(parts);
}

function concat(arrays: Uint8Array[]): Uint8Array {
  const totalLength = arrays.reduce((sum, a) => sum + a.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const arr of arrays) {
    result.set(arr, offset);
    offset += arr.length;
  }
  return result;
}

// ── Base64 helpers ────────────────────────────────────────────────────────────
function base64Encode(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data));
}

// ── HMAC-SHA256 ───────────────────────────────────────────────────────────────
async function hmacSha256(key: string, data: Uint8Array): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    encoder.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", keyMaterial, data);
  return new Uint8Array(signature);
}

// ── Token builder ─────────────────────────────────────────────────────────────

/**
 * Builds an Agora RTC Token (AccessToken2).
 *
 * @param appId      - Agora App ID (from console)
 * @param appCert    - Agora Primary App Certificate (keep server-side only!)
 * @param channelName - The channel the user wants to join
 * @param uid        - The user's integer UID. Pass 0 for wildcard (any uid).
 * @param role       - "publisher" | "subscriber"
 * @param tokenExpireSeconds  - Token validity in seconds (e.g. 3600 = 1 hour)
 * @param privilegeExpireSeconds - Privilege validity (same or less than tokenExpireSeconds)
 */
export async function buildTokenWithUid(
  appId: string,
  appCert: string,
  channelName: string,
  uid: number,
  role: "publisher" | "subscriber",
  tokenExpireSeconds: number,
  privilegeExpireSeconds: number,
): Promise<string> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const tokenExpireTs = nowSeconds + tokenExpireSeconds;
  const privilegeExpireTs = nowSeconds + privilegeExpireSeconds;

  // ── Build privileges map ──────────────────────────────────────────────────
  const privileges = new Map<number, number>();
  if (role === "publisher") {
    privileges.set(PRIVILEGES.joinChannel, privilegeExpireTs);
    privileges.set(PRIVILEGES.publishAudioStream, privilegeExpireTs);
    privileges.set(PRIVILEGES.publishVideoStream, privilegeExpireTs);
    privileges.set(PRIVILEGES.publishDataStream, privilegeExpireTs);
  } else {
    privileges.set(PRIVILEGES.joinChannel, privilegeExpireTs);
  }

  // ── Compute salt (random 32-bit) ──────────────────────────────────────────
  const saltArray = new Uint8Array(4);
  crypto.getRandomValues(saltArray);
  const salt = new DataView(saltArray.buffer).getUint32(0, false);

  // ── Pack message ──────────────────────────────────────────────────────────
  const uidStr = uid === 0 ? "" : uid.toString();
  const message = concat([
    packUint16(2),              // version = 2 (AccessToken2)
    packUint32(salt),
    packUint32(tokenExpireTs),
    packPrivileges(privileges),
  ]);

  // ── Build signing content ─────────────────────────────────────────────────
  const signingContent = concat([
    new TextEncoder().encode(appId),
    new TextEncoder().encode(channelName),
    new TextEncoder().encode(uidStr),
    message,
  ]);

  // ── Sign ──────────────────────────────────────────────────────────────────
  const signature = await hmacSha256(appCert, signingContent);

  // ── Pack final token content ──────────────────────────────────────────────
  const tokenContent = concat([
    packString(appId),
    packString(channelName),
    packString(uidStr),
    message,
    packUint16(signature.length),
    signature,
  ]);

  // ── Encode as base64 and prefix with version ──────────────────────────────
  return "007" + base64Encode(tokenContent);
}
