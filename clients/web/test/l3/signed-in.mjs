// L3, driven by ci/signed-in.sh: the client, in Node.js as a browser would run it, through the front in
// front of a real Core's routable channel. A browser keeps the cookie; here the fetch and the WebSocket
// handed to the client keep it, and nothing else differs.
//
// Usage: signed-in.mjs <channel> <channel roots> <front cert> <front key> <port to listen on>

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { Attachment, signIn } from "../../public/attachment.js";
import { createFront } from "../../server.mjs";

const [channel, roots, cert, key, port] = process.argv.slice(2);
const front = createFront({ channel, roots: readFileSync(roots), cert: readFileSync(cert), key: readFileSync(key) });
await new Promise((resolve) => front.listen(Number(port), "127.0.0.1", resolve));
const base = `https://127.0.0.1:${port}`;

// The cookie jar of a browser, for one origin.
const jar = new Map();
const cookies = () => [...jar].map(([name, value]) => `${name}=${value}`).join("; ");
const fetching = async (url, init) => {
  const response = await fetch(url, { ...init, headers: { ...init.headers, ...(jar.size ? { Cookie: cookies() } : {}) } });
  for (const line of response.headers.getSetCookie()) {
    const [pair] = line.split(";");
    const at = pair.indexOf("=");
    jar.set(pair.slice(0, at), pair.slice(at + 1));
  }
  return response;
};
const Socket = class extends WebSocket {
  constructor(url) {
    super(url, { headers: jar.size ? { Cookie: cookies() } : {} });
  }
};
const opened = () => Attachment.open({ base, fetch: fetching, WebSocket: Socket });

try {
  await assert.rejects(opened(), /closed before its opening/, "an attachment with no cookie is refused before any opening");

  const answered = await signIn({ account: "alice", secret: "hunter2x" }, { base, fetch: fetching });
  assert.equal(answered.account, "alice");
  assert.deepEqual(Object.keys(answered).sort(), ["account", "expires"], "the answer holds no token");
  assert.ok(jar.has("yoke-session"), "the sign-in set yoke-session");

  const attachment = await opened();
  const record = attachment.picture.channel;
  assert.equal(record?.declared?.addressClass, "routable");
  assert.equal(record?.observed?.client, "alice");
  attachment.close();
} finally {
  front.close();
  front.closeAllConnections();
}
