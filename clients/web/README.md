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
```

| File | What it is |
| --- | --- |
| `server.mjs` | the front: the pages, and `/v1/` forwarded |
| `public/attachment.js` | the contract: one attachment, its picture, one method per operation |
| `public/app.js` | the pages, drawn from the attachment |
| `test/` | the tests, run by `node --test 'test/*.test.mjs'` against a channel written in the test |
