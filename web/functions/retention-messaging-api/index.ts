/**
 * Apple Retention Messaging API — Get Retention Message endpoint.
 * https://developer.apple.com/documentation/retentionmessaging
 *
 * The App Store POSTs { signedPayload: <compact JWS> } when a subscriber
 * enters the cancellation flow. We must answer 200 within 700 ms with a
 * RealtimeResponseBody choosing which APPROVED retention message to show;
 * an empty object {} means "show the default retention message".
 *
 * Response is driven by env vars on the Pages project (none set → {}):
 *   RETENTION_MESSAGE_ID          message id for production requests
 *   RETENTION_MESSAGE_ID_SANDBOX  message id for sandbox requests
 *   STRICT_VERIFY=1               enforce JWS signature + root pin (off by
 *                                 default until validated against Apple's
 *                                 sandbox performance test; failures are
 *                                 logged either way)
 */

interface Env {
  RETENTION_MESSAGE_ID?: string;
  RETENTION_MESSAGE_ID_SANDBOX?: string;
  STRICT_VERIFY?: string;
}

const APP_APPLE_ID = 6783034270; // Bible Crossword Challenge

// SHA-256 fingerprint of Apple Root CA - G3 (DER), the root of the x5c chain
// Apple uses to sign App Store server JWS payloads.
const APPLE_ROOT_G3_FP =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

function b64urlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64.padEnd(b64.length + ((4 - (b64.length % 4)) % 4), "="));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function b64ToBytes(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Locates the uncompressed P-256 public key inside a DER certificate by its
// SPKI AlgorithmIdentifier (id-ecPublicKey + prime256v1) and returns the SPKI
// block for WebCrypto import. Not a general ASN.1 parser — enough to verify
// the JWS leaf signature; full x5c chain validation is deliberately out of
// scope for this endpoint (the response only names a pre-approved message,
// so a forged request can't extract or change anything sensitive).
const P256_SPKI_PREFIX = [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
  0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
];

function extractP256Spki(der: Uint8Array): Uint8Array | null {
  outer: for (let i = 0; i + 91 <= der.length; i++) {
    for (let j = 0; j < P256_SPKI_PREFIX.length; j++) {
      if (der[i + j] !== P256_SPKI_PREFIX[j]) continue outer;
    }
    return der.slice(i, i + 91); // 2 + 0x59 bytes
  }
  return null;
}

async function verifyJws(
  header: { alg?: string; x5c?: string[] },
  signedPart: string,
  signature: Uint8Array,
): Promise<string | null> {
  if (header.alg !== "ES256") return "alg is not ES256";
  if (!header.x5c?.length) return "missing x5c chain";
  const rootFp = hex(
    await crypto.subtle.digest("SHA-256", b64ToBytes(header.x5c[header.x5c.length - 1]).buffer as ArrayBuffer),
  );
  if (rootFp !== APPLE_ROOT_G3_FP) return `x5c root fingerprint mismatch (${rootFp})`;
  const spki = extractP256Spki(b64ToBytes(header.x5c[0]));
  if (!spki) return "no P-256 key in leaf certificate";
  const key = await crypto.subtle.importKey(
    "spki",
    spki.buffer as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    signature.buffer as ArrayBuffer,
    new TextEncoder().encode(signedPart),
  );
  return ok ? null : "signature verification failed";
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });

  let payload: {
    appAppleId?: number;
    environment?: string;
    productId?: string;
    requestIdentifier?: string;
  };
  let verifyError: string | null = "not attempted";
  try {
    const { signedPayload } = (await request.json()) as { signedPayload?: string };
    const parts = (signedPayload ?? "").split(".");
    if (parts.length !== 3) return json({}, 400);
    const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));
    try {
      verifyError = await verifyJws(
        header,
        `${parts[0]}.${parts[1]}`,
        b64urlToBytes(parts[2]),
      );
    } catch (e) {
      verifyError = `verifier threw: ${e}`;
    }
  } catch {
    return json({}, 400);
  }

  if (verifyError) {
    console.log(`retention-messaging: JWS not verified: ${verifyError}`);
    if (env.STRICT_VERIFY === "1") return json({}, 401);
  }

  // Per Apple: if appAppleId doesn't match your app, don't respond.
  if (payload.appAppleId !== APP_APPLE_ID) return json({}, 401);

  const messageId =
    payload.environment === "Sandbox"
      ? env.RETENTION_MESSAGE_ID_SANDBOX ?? env.RETENTION_MESSAGE_ID
      : env.RETENTION_MESSAGE_ID;

  console.log(
    `retention-messaging: env=${payload.environment} product=${payload.productId} ` +
      `req=${payload.requestIdentifier} -> ${messageId ?? "default"}`,
  );

  // {} = show the default retention message configured in App Store Connect.
  return json(messageId ? { message: { id: messageId } } : {});
};

// Anything but POST: report the endpoint is alive without leaking detail.
export const onRequest: PagesFunction<Env> = async (ctx) => {
  if (ctx.request.method === "POST") return ctx.next();
  return new Response(JSON.stringify({ status: "ok" }), {
    status: ctx.request.method === "GET" ? 200 : 405,
    headers: { "content-type": "application/json" },
  });
};
