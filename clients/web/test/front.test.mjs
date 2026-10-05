import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import http from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { createFront } from "../server.mjs";

const listening = (server, ...where) => new Promise((resolve) => server.listen(...where, () => resolve(server.address())));
const closing = (server) =>
  new Promise((resolve) => {
    server.close(() => resolve());
    server.closeAllConnections();
  });

// A channel written in the test: it records what reaches it and answers a read as the browser
// projection does, with a cookie and the call a stream's later answers would travel under.
function recordingChannel() {
  const reached = [];
  const server = http.createServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => (body += chunk));
    request.on("end", () => {
      reached.push({ method: request.method, url: request.url, body, cookie: request.headers.cookie });
      response.writeHead(200, {
        "Content-Type": "application/json",
        "Set-Cookie": "yoke-attachment=abc; Path=/v1; HttpOnly; SameSite=Strict",
        "Yoke-Call": "http-0123456789abcdef",
      });
      response.end('{"read":{"records":[]}}');
    });
  });
  return { server, reached };
}

// A front started on a free port in front of `channel`, closed when the test ends.
async function front(t, channel) {
  const server = createFront({ channel });
  const { port } = await listening(server, 0, "127.0.0.1");
  t.after(() => closing(server));
  return `http://127.0.0.1:${port}`;
}

async function exercise(t, address, reached) {
  const base = await front(t, address);

  const page = await fetch(base + "/");
  assert.equal(page.status, 200);
  assert.match(page.headers.get("content-type"), /text\/html/);
  assert.match(await page.text(), /<script type="module" src="app.js">/);
  assert.equal((await fetch(base + "/attachment.js")).status, 200);

  const answer = await fetch(base + "/v1/read", {
    method: "POST",
    headers: { "Content-Type": "application/json", Cookie: "yoke-attachment=abc" },
    body: '{"version":1,"read":{"kind":"unit"}}',
  });
  assert.equal(answer.status, 200);
  assert.equal(await answer.text(), '{"read":{"records":[]}}');
  assert.equal(answer.headers.get("set-cookie"), "yoke-attachment=abc; Path=/v1; HttpOnly; SameSite=Strict");
  assert.equal(answer.headers.get("yoke-call"), "http-0123456789abcdef");
  assert.deepEqual(reached, [{ method: "POST", url: "/v1/read", body: '{"version":1,"read":{"kind":"unit"}}', cookie: "yoke-attachment=abc" }]);

  const elsewhere = await fetch(base + "/admin");
  assert.equal(elsewhere.status, 404);
  const outside = await fetch(base + "/../server.mjs");
  assert.equal(outside.status, 404);
  assert.equal(reached.length, 1, "nothing outside /v1/ reaches the channel");
}

// std: yoke-reference:the-web-client.06
async function the_front_forwards_the_control_shape_unchanged_and_serves_the_pages(t) {
  await t.test("on loopback", async (t) => {
    const { server, reached } = recordingChannel();
    const { port } = await listening(server, 0, "127.0.0.1");
    t.after(() => closing(server));
    await exercise(t, `http://127.0.0.1:${port}`, reached);
  });
  await t.test("on a local socket", async (t) => {
    const dir = await mkdtemp(path.join(tmpdir(), "yoke-front-"));
    t.after(() => rm(dir, { recursive: true, force: true }));
    const { server, reached } = recordingChannel();
    const socket = path.join(dir, "channel.sock");
    await listening(server, socket);
    t.after(() => closing(server));
    await exercise(t, `unix:${socket}`, reached);
  });
}
test(the_front_forwards_the_control_shape_unchanged_and_serves_the_pages);

// A text frame from the channel, which a server sends unmasked; and the payload of a client's masked one.
function textFrame(text) {
  const payload = Buffer.from(text);
  return Buffer.concat([Buffer.from([0x81, payload.length]), payload]);
}
function unmasked(data) {
  const length = data[1] & 0x7f;
  const mask = data.subarray(2, 6);
  return Buffer.from(data.subarray(6, 6 + length).map((byte, i) => byte ^ mask[i % 4])).toString();
}

// std: yoke-reference:the-web-client.07
async function the_front_forwards_an_upgrade_byte_for_byte_and_answers_for_no_channel_it_cannot_reach(t) {
  const channel = http.createServer();
  const upgraded = new Set();
  channel.on("upgrade", (request, socket) => {
    upgraded.add(socket);
    assert.equal(request.url, "/v1/events");
    const accept = createHash("sha1").update(request.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    socket.write(textFrame('{"opening":{"version":1}}'));
    socket.on("data", (data) => {
      if ((data[0] & 0x0f) === 0x1) socket.write(textFrame("echo " + unmasked(data)));
    });
  });
  const { port } = await listening(channel, 0, "127.0.0.1");
  t.after(() => {
    for (const socket of upgraded) socket.destroy();
    return closing(channel);
  });
  const base = await front(t, `http://127.0.0.1:${port}`);

  const received = [];
  const socket = new WebSocket(base.replace("http", "ws") + "/v1/events");
  const echoed = new Promise((resolve, reject) => {
    socket.onmessage = (message) => {
      received.push(message.data);
      if (received.length === 1) socket.send("hello");
      else resolve();
    };
    socket.onerror = () => reject(new Error("the upgrade was not forwarded"));
  });
  await echoed;
  socket.close();
  assert.deepEqual(received, ['{"opening":{"version":1}}', "echo hello"]);

  const nobody = http.createServer();
  const { port: freed } = await listening(nobody, 0, "127.0.0.1");
  await closing(nobody);
  const unreachable = await front(t, `http://127.0.0.1:${freed}`);
  const answer = await fetch(unreachable + "/v1/read", { method: "POST", body: "{}" });
  assert.equal(answer.status, 502);
  assert.doesNotMatch(await answer.text(), /"code"/, "the front invents no answer of the contract");
}
test(the_front_forwards_an_upgrade_byte_for_byte_and_answers_for_no_channel_it_cannot_reach);
