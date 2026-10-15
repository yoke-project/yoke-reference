# The reference web client

A client of the interface contract on its browser projection, and of nothing else. A small application
in Node.js serves the pages and forwards everything under `/v1/` — requests and WebSocket upgrades —
unchanged to a channel the Core bound with `transport: http+ws`, so the pages and the contract share one
origin and the attachment's cookie works as the browser projection expects.

The pages compose themselves from what the channel presents: the units it may address, with the
commands, questions and streams each may be asked for, the channel's own state, and the events of the
standing subscription. Nothing in them names a unit or a Plugin.

It depends on no package: Node.js 24 or newer on the server, `fetch` and `WebSocket` in the browser.

```sh
node server.mjs --channel http://127.0.0.1:47911 --listen 127.0.0.1:8080
node server.mjs --channel unix:/run/yoke/interfaces/remote.sock
node server.mjs --channel https://192.0.2.10:8443 --roots channel-roots.pem --cert front.crt --key front.key
```

In front of a routable channel the front speaks TLS both ways. It reaches the channel over TLS 1.3 and
trusts the roots `--roots` names and no others. It serves the browser over HTTPS with the certificate
it is given, because a browser keeps the session cookie, which is `Secure`, only from a page served
over HTTPS. Without either it refuses to start. On such a channel nothing attaches before the caller
signs in, so the page asks for an account and a secret, sends them once to `/v1/authenticate`, and then
attaches with the cookie that comes back. The page never reads that cookie.

| File | What it is |
| --- | --- |
| `server.mjs` | the front: the pages, and `/v1/` forwarded |
| `public/attachment.js` | the contract: one attachment, its picture, one method per operation |
| `public/app.js` | the pages, drawn from the attachment |
| `test/` | the tests, run by `node --test 'test/*.test.mjs'` against a channel written in the test; `test/l3/` is driven by `ci/signed-in.sh` against a real Core |
