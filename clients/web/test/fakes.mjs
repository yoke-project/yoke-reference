// What the attachment's tests drive it with: a channel written in the test, standing behind a fake
// fetch and a fake WebSocket, which records every request and answers as the test tells it to.

export class Channel {
  constructor() {
    this.requests = [];
    this.answers = new Map();
    this.sockets = [];
    const channel = this;

    this.fetch = async (url, init) => {
      const { pathname } = new URL(url);
      const body = JSON.parse(init.body);
      channel.requests.push({ url, method: init.method, path: pathname, body });
      const operation = pathname.slice("/v1/".length);
      const queue = channel.answers.get(operation) ?? [];
      const reply = queue.length > 1 ? queue.shift() : queue[0];
      const { status = 200, json = {}, call } = typeof reply === "function" ? reply(body) : reply ?? {};
      return new Response(JSON.stringify(json), {
        status,
        headers: call ? { "Content-Type": "application/json", "Yoke-Call": call } : { "Content-Type": "application/json" },
      });
    };

    this.WebSocket = class {
      constructor(url) {
        this.url = url;
        this.sent = [];
        this.closedWith = undefined;
        channel.sockets.push(this);
      }
      send(data) {
        this.sent.push(data);
      }
      close(code) {
        this.closedWith = code;
        this.onclose?.({ code });
      }
      // What the channel sends on this socket.
      deliver(data) {
        this.onmessage?.({ data: typeof data === "object" && !(data instanceof ArrayBuffer) ? JSON.stringify(data) : data });
      }
    };
  }

  // The answer, or answers in order, the channel gives an operation.
  answer(operation, ...replies) {
    this.answers.set(operation, replies);
  }

  socket(path) {
    return this.sockets.find((s) => new URL(s.url).pathname === path);
  }

  requestsFor(operation) {
    return this.requests.filter((r) => r.path === `/v1/${operation}`);
  }
}

// An interval the test drives by hand.
export class Clock {
  constructor() {
    this.timers = new Map();
    this.next = 1;
    this.setInterval = (fn, every) => {
      const id = this.next++;
      this.timers.set(id, { fn, every });
      return id;
    };
    this.clearInterval = (id) => this.timers.delete(id);
  }
  tick() {
    for (const { fn } of [...this.timers.values()]) fn();
  }
}

export const opening = {
  opening: {
    version: 1,
    subscription: "standing",
    picture: {
      at: "3",
      records: [
        { instance: { ready: true, since: "2026-10-05T10:00:00Z" } },
        {
          unit: {
            declared: { identity: "station", kind: "plugin" },
            observed: { state: "running", incarnation: "1" },
            addressed: { streams: ["station.spectra"], commands: ["calibrate"], queries: ["status"] },
          },
        },
        { unit: { declared: { identity: "panel", kind: "interface" }, observed: { state: "running", incarnation: "1" }, addressed: {} } },
        {
          channel: {
            declared: { name: "remote", projection: "http+ws", addressClass: "loopback", clients: "multiple" },
            observed: { attached: true, client: "unestablished" },
          },
        },
      ],
    },
  },
};

// Lets every promise already settled run its continuations.
export const settled = () => new Promise((resolve) => setImmediate(resolve));
