// The interface contract on the browser projection, and nothing else: one attachment, the opening
// picture it keeps current, one method per operation. It knows no unit, no Plugin and no domain; what a
// page shows is composed from what the channel presents. It runs in a browser and, for its tests, in
// Node.js — the transport it is given is the only thing that differs.

// The contract version this client speaks.
export const VERSION = 1;

// How often the standing subscription is confirmed, in milliseconds: the channel's interval.
export const CONFIRM_EVERY = 10_000;

// A refusal, as the Core stated it: the code, the message for a person, and what it names.
export class Refused extends Error {
  constructor(refusal, status) {
    super(refusal.message || refusal.code);
    this.name = "Refused";
    this.code = refusal.code;
    this.status = status;
    this.subject = refusal.subject;
    this.item = refusal.item;
    this.suspension = refusal.suspension;
  }
}

// The canonical JSON mapping carries 64-bit integers as strings and bytes as base64.
const number = (value) => Number(value ?? 0);

export function toBase64(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function fromBase64(text) {
  const binary = atob(text ?? "");
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

const encode = (payload) =>
  payload === undefined ? undefined : toBase64(typeof payload === "string" ? new TextEncoder().encode(payload) : payload);

// The operation's field in the request and the answer, from its name on the path.
const field = (operation) => operation.replace(/\.([a-z])/g, (_, c) => c.toUpperCase());

// A frame on a delivery's socket: the sequence and the sender's clock, little-endian, then the payload.
export function decodeFrame(data) {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return {
    sequence: view.getBigUint64(0, true),
    sentAt: view.getBigUint64(8, true),
    payload: bytes.subarray(16),
  };
}

// The subject a record is about, as a key the picture is held by.
function keyOf(record) {
  if (record.instance) return "instance";
  if (record.unit) return `unit/${record.unit.declared?.identity}`;
  if (record.channel) return "channel";
  return undefined;
}

// What a channel observes, held by subject and replaced record by record.
export class Picture {
  constructor(snapshot) {
    this.at = number(snapshot?.at);
    this.records = new Map();
    for (const record of snapshot?.records ?? []) this.put(record);
  }

  put(record) {
    const key = keyOf(record);
    if (key) this.records.set(key, record);
  }

  get instance() {
    return this.records.get("instance")?.instance;
  }

  get channel() {
    return this.records.get("channel")?.channel;
  }

  get units() {
    return [...this.records.entries()]
      .filter(([key]) => key.startsWith("unit/"))
      .map(([, record]) => record.unit)
      .sort((a, b) => a.declared.identity.localeCompare(b.declared.identity));
  }
}

// One attachment to a channel on the browser projection. `base` is the origin the pages came from;
// `fetch`, `WebSocket` and the clock are the platform's unless a test hands its own.
export class Attachment {
  static open(options = {}) {
    const attachment = new Attachment(options);
    return attachment.opened.then(() => attachment);
  }

  constructor({
    base = globalThis.location?.origin,
    fetch = globalThis.fetch.bind(globalThis),
    WebSocket = globalThis.WebSocket,
    setInterval = globalThis.setInterval.bind(globalThis),
    clearInterval = globalThis.clearInterval.bind(globalThis),
    confirmEvery = CONFIRM_EVERY,
  } = {}) {
    this.base = base;
    this.fetch = fetch;
    this.WebSocket = WebSocket;
    this.clearInterval = clearInterval;
    this.listeners = new Set();
    this.calls = new Map();
    this.applied = 0;
    this.closed = false;

    this.socket = new WebSocket(base.replace(/^http/, "ws") + "/v1/events");
    this.opened = new Promise((resolve, reject) => {
      this.socket.onmessage = (message) => {
        let frame;
        try {
          frame = JSON.parse(message.data);
        } catch (error) {
          this.tell({ kind: "malformed", error });
          return;
        }
        if (frame.opening) {
          this.version = frame.opening.version;
          this.subscription = frame.opening.subscription;
          this.picture = new Picture(frame.opening.picture);
          this.applied = this.picture.at;
          this.confirming = setInterval(() => this.confirmCurrent(), confirmEvery);
          resolve();
          this.tell({ kind: "opening", picture: this.picture });
          return;
        }
        this.receive(frame);
      };
      this.socket.onclose = (event) => {
        this.stop();
        reject(new Error("the channel closed before its opening"));
        this.tell({ kind: "closed", code: event?.code, reason: event?.reason });
      };
      this.socket.onerror = () => {};
    });
  }

  // A listener is told { kind: "opening" | "event" | "picture" | "answer" | "closed" | … }.
  listen(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  tell(news) {
    for (const listener of this.listeners) listener(news);
  }

  stop() {
    this.closed = true;
    if (this.confirming !== undefined) this.clearInterval(this.confirming);
    this.confirming = undefined;
  }

  close() {
    this.stop();
    this.socket.close(1000);
  }

  // A frame on the live shape, after the opening: the standing subscription's, or a later answer to a
  // call made on the control shape.
  receive(frame) {
    const call = frame.call ?? "";
    if (call === this.subscription) {
      if (frame.event) this.apply(frame.event);
      const overflow = frame.answer?.subscribe?.overflow;
      if (overflow) {
        this.picture = new Picture(overflow);
        this.applied = this.picture.at;
        this.behind = false;
        this.tell({ kind: "picture", picture: this.picture, overflow: true });
      }
      return;
    }
    const listener = this.calls.get(call);
    if (!listener) return;
    if (frame.completion || frame.refusal) this.calls.delete(call);
    listener(frame);
  }

  // An event changes what the channel observes about its subject: that subject is read again, and its
  // record replaces the one held. The detail is typed per event type and is not decoded here.
  // What is confirmed is what the picture shows: the sequence moves once the subject was read again,
  // never on arrival alone.
  async apply(event) {
    this.tell({ kind: "event", event });
    const { kind, identity } = event.subject ?? {};
    if (["instance", "unit", "channel"].includes(kind)) {
      try {
        const records = await this.read(kind, kind === "unit" ? identity : undefined);
        for (const record of records) this.picture.put(record);
        this.tell({ kind: "picture", picture: this.picture });
      } catch (error) {
        // A subject that could not be read leaves the picture behind, and it stays behind — unconfirmed
        // past this point — until an overflow replaces it whole.
        this.behind = true;
        this.tell({ kind: "unread", subject: event.subject, error });
        return;
      }
    }
    if (!this.behind) this.applied = Math.max(this.applied, number(event.seq));
  }

  confirmCurrent() {
    if (this.closed) return;
    this.confirm(this.applied).catch((error) => this.tell({ kind: "unconfirmed", error }));
  }

  // One request on the control shape: its operation is the path, its answer comes once.
  async call(operation, body = {}) {
    const response = await this.fetch(`${this.base}/v1/${operation}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "same-origin",
      body: JSON.stringify({ version: VERSION, [field(operation)]: body }),
    });
    const text = await response.text();
    let decoded = {};
    try {
      decoded = text ? JSON.parse(text) : {};
    } catch {
      throw new Refused({ code: "transport", message: `${response.status} ${text}` }, response.status);
    }
    if (!response.ok) throw new Refused(decoded.code ? decoded : { code: "transport", message: text }, response.status);
    return { answer: decoded[field(operation)] ?? {}, call: response.headers.get("Yoke-Call") };
  }

  async authenticate(credential) {
    return (await this.call("authenticate", credential)).answer;
  }

  async read(kind, identity) {
    return (await this.call("read", { kind, identity })).answer.records ?? [];
  }

  // A subscription of its own, beside the standing one: its snapshot is answered, and what follows
  // arrives on the live shape under the call the answer names.
  async subscribe(filter, listener) {
    const { answer, call } = await this.call("subscribe", { filter });
    if (call) this.calls.set(call, (frame) => listener(frame.answer?.subscribe ?? frame));
    return { snapshot: answer.snapshot, call };
  }

  async confirm(sequence, subscription = this.subscription) {
    return (await this.call("confirm", { subscription, sequence: String(sequence) })).answer;
  }

  async command(unit, type, payload) {
    const answer = (await this.call("command", { unit, type, payload: encode(payload) })).answer;
    return { outcome: answer.outcome ?? "OUTCOME_UNSPECIFIED", line: answer.line ?? "" };
  }

  async query(unit, type, payload) {
    return fromBase64((await this.call("query", { unit, type, payload: encode(payload) })).answer.payload);
  }

  async streamStart(unit, stream) {
    return (await this.call("stream.start", { unit, stream })).answer;
  }

  async streamStop(unit, stream) {
    return (await this.call("stream.stop", { unit, stream })).answer;
  }

  // A stream's delivery: the Core names the path its data arrives at, and the client opens that path.
  async streamSubscribe(unit, stream, onFrame) {
    const answer = (await this.call("stream.subscribe", { unit, stream })).answer;
    if (!answer.path) throw new Refused({ code: "transport", message: "the delivery names no path on this projection" });
    const socket = new this.WebSocket(this.base.replace(/^http/, "ws") + answer.path);
    socket.binaryType = "arraybuffer";
    socket.onmessage = (message) => onFrame(decodeFrame(message.data));
    return {
      delivery: answer.delivery,
      path: answer.path,
      flowing: Boolean(answer.flowing),
      release: async () => {
        try {
          await this.call("stream.unsubscribe", { delivery: answer.delivery });
        } finally {
          socket.close(1000);
        }
      },
    };
  }

  async reclaim() {
    return (await this.call("reclaim", {})).answer;
  }
}
