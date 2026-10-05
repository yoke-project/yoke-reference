import assert from "node:assert/strict";
import test from "node:test";

import { Attachment, Refused } from "../public/attachment.js";
import { Channel, Clock, opening, settled } from "./fakes.mjs";

const base = "http://front.test";

function attaching(channel, clock = new Clock()) {
  const pending = Attachment.open({
    base,
    fetch: channel.fetch,
    WebSocket: channel.WebSocket,
    setInterval: clock.setInterval,
    clearInterval: clock.clearInterval,
  });
  return pending;
}

async function attached(channel, clock) {
  const pending = attaching(channel, clock);
  channel.socket("/v1/events").deliver(opening);
  return pending;
}

// std: yoke-reference:the-web-client.01
async function attaching_is_opening_the_live_socket_and_the_picture_is_the_opening() {
  const channel = new Channel();
  let open = false;
  const pending = attaching(channel).then((a) => ((open = true), a));
  const socket = channel.socket("/v1/events");
  assert.ok(socket, "the live socket is /v1/events");
  assert.equal(socket.url, "ws://front.test/v1/events");
  await settled();
  assert.equal(open, false, "the attachment is not open before its opening");

  socket.deliver(opening);
  const attachment = await pending;
  assert.equal(attachment.version, 1);
  assert.equal(attachment.subscription, "standing");
  assert.equal(attachment.picture.at, 3);
  assert.equal(attachment.picture.instance.ready, true);
  assert.deepEqual(
    attachment.picture.units.map((u) => [u.declared.identity, u.addressed]),
    [
      ["panel", {}],
      ["station", { streams: ["station.spectra"], commands: ["calibrate"], queries: ["status"] }],
    ],
  );
  assert.equal(attachment.picture.channel.declared.name, "remote");
  assert.equal(attachment.picture.channel.observed.suspended, undefined);
}
test(attaching_is_opening_the_live_socket_and_the_picture_is_the_opening);

// std: yoke-reference:the-web-client.02
async function an_operation_is_its_name_as_a_path_answered_once_and_a_refusal_keeps_what_it_names() {
  const channel = new Channel();
  channel.answer(
    "command",
    { json: { command: { outcome: "OUTCOME_DONE", line: "calibrated" } } },
    {
      status: 409,
      json: { code: "channel.suspended", message: "the channel is suspended", suspension: { grade: "read-only", by: "panel" } },
    },
  );
  channel.answer("query", { json: { query: { payload: btoa("all good") } } });
  const attachment = await attached(channel);

  const done = await attachment.command("station", "calibrate", "fast");
  assert.deepEqual(done, { outcome: "OUTCOME_DONE", line: "calibrated" });
  const answer = await attachment.query("station", "status");
  assert.equal(new TextDecoder().decode(answer), "all good");

  await assert.rejects(attachment.command("station", "calibrate", "again"), (error) => {
    assert.ok(error instanceof Refused);
    assert.equal(error.code, "channel.suspended");
    assert.equal(error.message, "the channel is suspended");
    assert.deepEqual(error.suspension, { grade: "read-only", by: "panel" });
    assert.equal(error.status, 409);
    return true;
  });

  const [first, , third] = channel.requests;
  assert.equal(first.method, "POST");
  assert.equal(first.path, "/v1/command");
  assert.deepEqual(first.body, { version: 1, command: { unit: "station", type: "calibrate", payload: btoa("fast") } });
  assert.deepEqual(channel.requests[1].body, { version: 1, query: { unit: "station", type: "status" } });
  assert.equal(third.path, "/v1/command");
}
test(an_operation_is_its_name_as_a_path_answered_once_and_a_refusal_keeps_what_it_names);

// std: yoke-reference:the-web-client.03
async function the_picture_follows_the_standing_subscription_and_an_overflow_replaces_it() {
  const channel = new Channel();
  channel.answer("read", (body) =>
    body.read.kind === "unit"
      ? { json: { read: { records: [{ unit: { declared: { identity: "station", kind: "plugin" }, observed: { state: "stopped" } } }] } } }
      : {
          json: {
            read: {
              records: [
                {
                  channel: {
                    declared: { name: "remote" },
                    observed: { attached: true, suspended: true, grade: "read-only", by: "panel", reason: "displaced" },
                  },
                },
              ],
            },
          },
        },
  );
  const attachment = await attached(channel);
  const told = [];
  attachment.listen((news) => told.push(news));
  const socket = channel.socket("/v1/events");

  socket.deliver({ call: "standing", event: { seq: "4", type: "unit.state.changed", subject: { kind: "unit", identity: "station" } } });
  await settled();
  assert.deepEqual(channel.requestsFor("read").at(-1).body, { version: 1, read: { kind: "unit", identity: "station" } });
  assert.equal(attachment.picture.units.find((u) => u.declared.identity === "station").observed.state, "stopped");

  socket.deliver({ call: "standing", event: { seq: "5", type: "channel.suspended", subject: { kind: "channel", identity: "remote" } } });
  await settled();
  assert.deepEqual(channel.requestsFor("read").at(-1).body, { version: 1, read: { kind: "channel" } });
  assert.equal(attachment.picture.channel.observed.suspended, true);
  assert.equal(attachment.picture.channel.observed.by, "panel");

  assert.deepEqual(
    told.filter((n) => n.kind === "event").map((n) => n.event.seq),
    ["4", "5"],
  );

  socket.deliver({
    call: "standing",
    answer: { subscribe: { overflow: { at: "40", records: [{ instance: { ready: true, stopping: true } }] } } },
  });
  assert.equal(attachment.picture.at, 40);
  assert.equal(attachment.picture.instance.stopping, true);
  assert.deepEqual(attachment.picture.units, []);
  assert.equal(attachment.picture.channel, undefined);
  assert.ok(told.some((n) => n.kind === "picture" && n.overflow));
}
test(the_picture_follows_the_standing_subscription_and_an_overflow_replaces_it);

// std: yoke-reference:the-web-client.04
async function the_standing_subscription_is_confirmed_at_the_sequence_last_applied() {
  const channel = new Channel();
  channel.answer("read", { json: { read: { records: [] } } });
  const clock = new Clock();
  const attachment = await attached(channel, clock);

  clock.tick();
  await settled();
  channel.socket("/v1/events").deliver({ call: "standing", event: { seq: "7", type: "unit.state.changed", subject: { kind: "unit", identity: "station" } } });
  await settled();
  clock.tick();
  await settled();
  attachment.close();
  clock.tick();
  await settled();

  assert.deepEqual(
    channel.requestsFor("confirm").map((r) => r.body),
    [
      { version: 1, confirm: { subscription: "standing", sequence: "3" } },
      { version: 1, confirm: { subscription: "standing", sequence: "7" } },
    ],
  );
}
test(the_standing_subscription_is_confirmed_at_the_sequence_last_applied);

function frame(sequence, sentAt, text) {
  const payload = new TextEncoder().encode(text);
  const bytes = new Uint8Array(16 + payload.length);
  const view = new DataView(bytes.buffer);
  view.setBigUint64(0, sequence, true);
  view.setBigUint64(8, sentAt, true);
  bytes.set(payload, 16);
  return bytes.buffer;
}

// std: yoke-reference:the-web-client.05
async function a_streams_data_arrives_on_the_path_it_was_answered_with_header_and_payload_unchanged() {
  const channel = new Channel();
  channel.answer("stream.subscribe", {
    json: { streamSubscribe: { delivery: "00000001", path: "/v1/streams/station/station.spectra/00000001", flowing: true } },
  });
  channel.answer("stream.unsubscribe", { json: { streamUnsubscribe: {} } });
  const attachment = await attached(channel);

  const frames = [];
  const delivery = await attachment.streamSubscribe("station", "station.spectra", (f) => frames.push(f));
  assert.deepEqual(channel.requestsFor("stream.subscribe")[0].body, {
    version: 1,
    streamSubscribe: { unit: "station", stream: "station.spectra" },
  });
  assert.equal(delivery.delivery, "00000001");
  assert.equal(delivery.flowing, true);
  const socket = channel.socket("/v1/streams/station/station.spectra/00000001");
  assert.ok(socket, "the client opens the path it was answered with");
  assert.equal(socket.binaryType, "arraybuffer");

  socket.deliver(frame(1n, 1_700_000_000_000_000_001n, "one"));
  socket.deliver(frame(2n, 1_700_000_000_000_000_002n, "two"));
  assert.deepEqual(
    frames.map((f) => [f.sequence, f.sentAt, new TextDecoder().decode(f.payload)]),
    [
      [1n, 1_700_000_000_000_000_001n, "one"],
      [2n, 1_700_000_000_000_000_002n, "two"],
    ],
  );

  await delivery.release();
  assert.deepEqual(channel.requestsFor("stream.unsubscribe")[0].body, { version: 1, streamUnsubscribe: { delivery: "00000001" } });
  assert.equal(socket.closedWith, 1000);
}
test(a_streams_data_arrives_on_the_path_it_was_answered_with_header_and_payload_unchanged);
