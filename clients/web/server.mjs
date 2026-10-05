// The front of the reference web client: it serves the pages and forwards the browser projection to the
// channel, unchanged. It is what stands in front of the channel so the pages and the contract share one
// origin; it answers no operation of its own, and anything that is neither a page nor under /v1/ is 404.
//
// Usage: node server.mjs --channel <http://127.0.0.1:port | unix:/path/to/socket> [--listen 127.0.0.1:8080]

import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";

const pages = path.join(path.dirname(fileURLToPath(import.meta.url)), "public");

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
};

// A channel's address as the front reaches it: a local socket, or a host and port.
export function channelOf(address) {
  if (address.startsWith("unix:")) return { socketPath: address.slice("unix:".length) };
  const url = new URL(address);
  if (url.protocol !== "http:") throw new Error(`the channel ${address} is neither unix:<path> nor http://<host>:<port>`);
  return { host: url.hostname, port: Number(url.port || 80) };
}

function connectTo(channel) {
  return channel.socketPath ? net.connect(channel.socketPath) : net.connect(channel.port, channel.host);
}

async function servePage(request, response) {
  const wanted = request.url === "/" ? "/index.html" : decodeURIComponent(new URL(request.url, "http://front").pathname);
  const file = path.join(pages, path.normalize(wanted));
  if (!file.startsWith(pages + path.sep) || (request.method !== "GET" && request.method !== "HEAD")) return false;
  try {
    if (!(await stat(file)).isFile()) return false;
  } catch {
    return false;
  }
  response.writeHead(200, { "Content-Type": types[path.extname(file)] ?? "application/octet-stream" });
  if (request.method === "HEAD") response.end();
  else createReadStream(file).pipe(response);
  return true;
}

// The control shape: the request as it came, and the answer as it went.
function forward(channel, request, response) {
  const upstream = http.request(
    { ...channel, method: request.method, path: request.url, headers: request.headers },
    (answer) => {
      response.writeHead(answer.statusCode, answer.rawHeaders);
      answer.pipe(response);
    },
  );
  upstream.on("error", () => {
    if (response.headersSent) return response.destroy();
    response.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("the channel cannot be reached\n");
  });
  request.pipe(upstream);
}

// The live shape: the upgrade's request is written to the channel as it arrived, and from then on the
// two sockets are joined byte for byte.
function forwardUpgrade(channel, request, client, head, tunnels) {
  const upstream = connectTo(channel);
  tunnels.add(client);
  client.on("close", () => tunnels.delete(client));
  upstream.on("connect", () => {
    const lines = [`${request.method} ${request.url} HTTP/${request.httpVersion}`];
    for (let i = 0; i < request.rawHeaders.length; i += 2) lines.push(`${request.rawHeaders[i]}: ${request.rawHeaders[i + 1]}`);
    upstream.write(lines.join("\r\n") + "\r\n\r\n");
    if (head?.length) upstream.write(head);
    upstream.pipe(client);
    client.pipe(upstream);
  });
  upstream.on("error", () => {
    if (!client.destroyed) client.end("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
  });
  client.on("error", () => upstream.destroy());
  upstream.on("close", () => client.destroy());
  client.on("close", () => upstream.destroy());
}

const underContract = (url) => url === "/v1" || url.startsWith("/v1/");

export function createFront({ channel }) {
  const reached = typeof channel === "string" ? channelOf(channel) : channel;
  // An upgraded connection is no longer the server's to close, so the front keeps them and ends them
  // when it closes.
  const tunnels = new Set();
  const server = http.createServer(async (request, response) => {
    if (underContract(request.url)) return forward(reached, request, response);
    if (await servePage(request, response)) return;
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("not found\n");
  });
  server.on("upgrade", (request, client, head) => {
    if (underContract(request.url)) return forwardUpgrade(reached, request, client, head, tunnels);
    client.end("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
  });
  server.on("close", () => {
    for (const client of tunnels) client.destroy();
  });
  return server;
}

function argument(name, fallback) {
  const at = process.argv.indexOf(`--${name}`);
  return at > 0 ? process.argv[at + 1] : fallback;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const channel = argument("channel", process.env.YOKE_CHANNEL);
  if (!channel) {
    console.error("usage: node server.mjs --channel <http://127.0.0.1:port | unix:/path> [--listen host:port]");
    process.exit(2);
  }
  const [host, port] = argument("listen", "127.0.0.1:8080").split(/:(?=\d+$)/);
  createFront({ channel }).listen(Number(port), host, () => {
    console.log(`the reference web client is at http://${host}:${port}/, in front of ${channel}`);
  });
}
