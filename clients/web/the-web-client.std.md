# The reference web client

| | |
| --- | --- |
| **Feature** | an application in Node.js that serves its own pages and forwards the browser projection of the interface contract, unchanged, to a channel the Core bound; the pages compose themselves from what the channel presents — the units it may address, with their commands, questions and streams, the channel's own state and what arrives on the standing subscription — and reach the Core by nothing but that projection |
| **Planning item** | yoke-project/yoke-reference#18 |

## yoke-reference:the-web-client.01 — attaching is opening the live socket, and the picture is the opening

| Field | Value |
| --- | --- |
| **Cites** | specs/90.40 · arch/90-sdks/07 §What each one is · arch/70-interface-surface/03 · arch/70-interface-surface/08 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a channel written in the test that answers the live socket with an opening carrying the instance, two units — one a Plugin unit with a command, a question and a stream it may address, one not — and the channel's own record |
| **Action** | attach |
| **Expected** | the live socket is `/v1/events`; the attachment is open once the opening arrived and not before; its picture holds the instance, both units with what each may address, and the channel, and it names the standing subscription and the contract version |

## yoke-reference:the-web-client.02 — an operation is its name as a path, answered once, and a refusal keeps what it names

| Field | Value |
| --- | --- |
| **Cites** | arch/70-interface-surface/04 · arch/70-interface-surface/08 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an attachment on a channel written in the test, which records every control request and answers a command as done and a question with a payload, and refuses a second command `channel.suspended`, read-only, prevailed over by `panel` |
| **Action** | issue a command with a text payload, ask a question, then issue the command again |
| **Expected** | each request is a `POST` to `/v1/<operation>` carrying the contract version and the operation in the canonical JSON mapping, the payload as its bytes; the command is answered done with the unit's line, the question with its payload; the refusal surfaces as an error carrying the code, the message and the suspension's grade and channel |

## yoke-reference:the-web-client.03 — the picture follows the standing subscription, and an overflow replaces it

| Field | Value |
| --- | --- |
| **Cites** | specs/90.40 · arch/70-interface-surface/05 · arch/45-events/04 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an attachment on a channel written in the test |
| **Action** | the channel sends, on the standing subscription, an event about a unit, then an event about the channel, then an overflow carrying a fresh snapshot |
| **Expected** | each event reaches the client's listeners; the subject each names is read again and its record replaces the one held, so the channel shows suspended once its record says so; the overflow replaces the whole picture with its records |

## yoke-reference:the-web-client.04 — the standing subscription is confirmed at the sequence last applied

| Field | Value |
| --- | --- |
| **Cites** | arch/70-interface-surface/03 §So liveness is the confirmed subscription and not a second mechanism · specs/90.41 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an attachment on a channel written in the test, opened at sequence 3, confirming on an interval the test drives |
| **Action** | let one interval pass; apply an event at sequence 7; let another pass; receive an event at sequence 9 whose subject cannot be read, and let another pass; receive an overflow at sequence 12, and let another pass; close the attachment and let a last one pass |
| **Expected** | the standing subscription is confirmed at 3, then at 7, at 7 again while the subject of 9 is unread, then at 12; nothing is confirmed once the attachment is closed |

## yoke-reference:the-web-client.05 — a stream's data arrives on the path it was answered with, header and payload unchanged

| Field | Value |
| --- | --- |
| **Cites** | arch/70-interface-surface/07 · arch/70-interface-surface/08 · specs/70.6 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an attachment on a channel written in the test, which answers `stream.subscribe` with a delivery and its path, and sends two binary frames on that path |
| **Action** | subscribe to the stream, take its frames, then release the delivery |
| **Expected** | the client opens the path it was answered with and derives none; each frame is read as its sequence and the sender's clock, little-endian, and its payload; releasing it sends `stream.unsubscribe` naming the delivery and closes the socket |

## yoke-reference:the-web-client.06 — the front forwards the control shape unchanged and serves the pages

| Field | Value |
| --- | --- |
| **Cites** | arch/90-sdks/07 §They hold no privileged route, and that is what they are for · arch/00-system/03 · specs/90.41 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the front, started on a free port in front of a channel written in the test, which records what reaches it; once on loopback and once on a local socket |
| **Action** | fetch the page; post a request to `/v1/read` with a cookie; fetch a path that is neither a page nor under `/v1/` |
| **Expected** | the page is served; the request reaches the channel with its method, path, body and cookie, and its answer reaches the caller with its status, body, `Set-Cookie` and `Yoke-Call`; the third is `404` and reaches nothing |

## yoke-reference:the-web-client.07 — the front forwards an upgrade byte for byte, and answers for no channel it cannot reach

| Field | Value |
| --- | --- |
| **Cites** | arch/90-sdks/07 §They hold no privileged route, and that is what they are for · arch/70-interface-surface/08 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the front in front of a channel written in the test that upgrades `/v1/events`, sends a text message and echoes what it receives; and a front in front of an address nothing listens on |
| **Action** | open `/v1/events` through the first front and send a message; post a request through the second |
| **Expected** | the upgrade is answered by the channel, its message arrives and the echo comes back; the second answers `502` and invents no answer of the contract |

## yoke-reference:the-web-client.08 — signing in is a request of its own, and the token never reaches the page

| Field | Value |
| --- | --- |
| **Cites** | arch/80-security/08 §2 — A browser reaches a routable channel · arch/80-security/04 §The session token · arch/70-interface-surface/08 §`http+ws` — the browser projection |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a channel written in the test that answers `authenticate` with an account and an expiry, then refuses it `auth.invalid` |
| **Action** | sign in with an account and a secret; sign in again |
| **Expected** | the request is a `POST` to `/v1/authenticate`, same-origin, carrying the contract version and the password in the canonical JSON mapping, and nothing is opened before it; its answer names the account and the expiry and holds no token; the second surfaces as an error carrying `auth.invalid` |

## yoke-reference:the-web-client.09 — in front of a routable channel the front speaks TLS both ways, and trusts only the roots it was given

| Field | Value |
| --- | --- |
| **Cites** | arch/80-security/08 §2 — A browser reaches a routable channel · arch/90-sdks/07 §They hold no privileged route, and that is what they are for · arch/70-interface-surface/08 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a channel written in the test that speaks TLS with a certificate of its own, sets a `Secure`, `HttpOnly` cookie on `/v1/authenticate` and upgrades `/v1/events`; a second certificate the front serves with; a third certificate that signed nothing |
| **Action** | start the front with `--channel https://…`, that channel's certificate as its roots, and its own certificate and key; fetch the page and post `/v1/authenticate` over HTTPS; open `/v1/events` over WSS; then start a front whose roots are the third certificate and post again; then start a front in front of an `https://` channel with no roots, and one with no certificate of its own |
| **Expected** | the page is served over HTTPS; the request reaches the channel over TLS 1.3, and its `Set-Cookie` comes back unchanged; the upgrade is answered by the channel; the front that trusts the wrong root answers `502` and invents no answer of the contract; the last two refuse to start, naming what is missing |

## yoke-reference:the-web-client.10 — under a real Core, the client signs in across a routable channel and attaches with the cookie

| Field | Value |
| --- | --- |
| **Cites** | arch/80-security/08 §2 — A browser reaches a routable channel · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a Core and `yoke-auth` built from the `yoke` module at the commit `ci/signed-in.sh` names, asking a stack of the test's own that accepts `alice` with `hunter2x`; its composition declares a routable `http+ws` channel on `127.0.0.1`, its certificate and key in the store; the front in front of it, trusting that certificate and serving with one of its own; a client trusting the front's certificate and keeping cookies as a browser does |
| **Action** | open the attachment with no cookie; sign in through the front; open the attachment again |
| **Expected** | the first is refused before any opening; the sign-in names `alice` and holds no token, and sets `yoke-session`; the second attachment opens, and its picture holds the channel `routable`, its client `alice` |
