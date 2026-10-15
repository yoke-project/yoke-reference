import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import https from "node:https";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { createFront } from "../server.mjs";

// A self-signed certificate for 127.0.0.1 and its key, made by openssl for the length of a test.
function material(t, name) {
  const dir = mkdtempSync(path.join(tmpdir(), "yr-tls-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const cert = path.join(dir, `${name}.crt`);
  const key = path.join(dir, `${name}.key`);
  execFileSync("openssl", ["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-days", "1",
    "-subj", `/CN=${name}`, "-addext", "subjectAltName=IP:127.0.0.1", "-keyout", key, "-out", cert], { stdio: "ignore" });
  return { cert: readFileSync(cert), key: readFileSync(key) };
}

const listening = (server) => new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server.address().port)));
const closing = (server) =>
  new Promise((resolve) => {
    server.close(() => resolve());
    server.closeAllConnections();
  });

// A request over HTTPS, trusting ca: its status, headers and body, and the TLS version it was made over.
function request(url, { method = "GET", body, ca }) {
  return new Promise((resolve, reject) => {
    const r = https.request(url, { method, ca, headers: body ? { "Content-Type": "application/json" } : {} }, (answer) => {
      let text = "";
      answer.on("data", (chunk) => (text += chunk));
      answer.on("end", () => resolve({ status: answer.statusCode, headers: answer.headers, body: text }));
    });
    r.on("error", reject);
    r.end(body);
  });
}

// An upgrade of /v1/events over WSS, trusting ca: the status it was answered with.
function upgrade(url, ca) {
  return new Promise((resolve, reject) => {
    const r = https.request(url, {
      ca,
      headers: { Connection: "Upgrade", Upgrade: "websocket", "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==" },
    });
    r.on("upgrade", (answer, socket) => {
      socket.destroy();
      resolve(answer.statusCode);
    });
    r.on("response", (answer) => resolve(answer.statusCode));
    r.on("error", reject);
    r.end();
  });
}

// std: yoke-reference:the-web-client.09
async function in_front_of_a_routable_channel_the_front_speaks_tls_both_ways_and_trusts_only_its_roots(t) {
  const channelMaterial = material(t, "service");
  const frontMaterial = material(t, "front");
  const stranger = material(t, "stranger");

  const reached = [];
  const upgraded = new Set();
  const channel = https.createServer(channelMaterial, (req, res) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      reached.push({ url: req.url, body, tls: req.socket.getProtocol() });
      res.writeHead(200, {
        "Content-Type": "application/json",
        "Set-Cookie": "yoke-session=opaque; Path=/v1; HttpOnly; SameSite=Strict; Secure",
      });
      res.end('{"authenticate":{"account":"alice"}}');
    });
  });
  channel.on("upgrade", (req, socket) => {
    upgraded.add(socket);
    const accept = createHash("sha1").update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  });
  const port = await listening(channel);
  t.after(() => {
    for (const socket of upgraded) socket.destroy();
    return closing(channel);
  });

  const started = async (roots) => {
    const front = createFront({ channel: `https://127.0.0.1:${port}`, roots, ...frontMaterial });
    const at = await listening(front);
    t.after(() => closing(front));
    return `https://127.0.0.1:${at}`;
  };
  const base = await started(channelMaterial.cert);
  const page = await request(base + "/", { ca: frontMaterial.cert });
  assert.equal(page.status, 200);
  assert.match(page.body, /<script type="module" src="app.js">/);

  const signed = await request(base + "/v1/authenticate", { method: "POST", body: '{"version":1,"authenticate":{}}', ca: frontMaterial.cert });
  assert.equal(signed.status, 200);
  assert.deepEqual(signed.headers["set-cookie"], ["yoke-session=opaque; Path=/v1; HttpOnly; SameSite=Strict; Secure"]);
  assert.deepEqual(reached, [{ url: "/v1/authenticate", body: '{"version":1,"authenticate":{}}', tls: "TLSv1.3" }]);
  assert.equal(await upgrade(base + "/v1/events", frontMaterial.cert), 101);

  const mistrusting = await started(stranger.cert);
  const refused = await request(mistrusting + "/v1/authenticate", { method: "POST", body: "{}", ca: frontMaterial.cert });
  assert.equal(refused.status, 502);
  assert.doesNotMatch(refused.body, /"code"/, "the front invents no answer of the contract");
  assert.equal(reached.length, 1, "nothing reached the channel through the front that does not trust it");

  assert.throws(() => createFront({ channel: `https://127.0.0.1:${port}`, ...frontMaterial }), /--roots/);
  assert.throws(() => createFront({ channel: `https://127.0.0.1:${port}`, roots: channelMaterial.cert }), /--cert and --key/);
}
test(in_front_of_a_routable_channel_the_front_speaks_tls_both_ways_and_trusts_only_its_roots);
