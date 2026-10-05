// The pages: everything shown is composed from what the channel presents through the attachment —
// which units it may address, what each may be asked, its streams, and the channel's own state. No unit,
// Plugin or domain is named here; a payload is shown as text and sent as text.

import { Attachment, Refused } from "./attachment.js";

const $ = (selector) => document.querySelector(selector);
const element = (tag, props = {}, ...children) => {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
};
const text = (bytes) => new TextDecoder().decode(bytes);

function say(output, what) {
  output.classList.toggle("refused", what instanceof Error);
  if (what instanceof Refused) {
    const grade = what.suspension ? ` (${what.suspension.grade}${what.suspension.by ? `, by ${what.suspension.by}` : ""})` : "";
    output.textContent = `refused ${what.code}${grade}: ${what.message}`;
    if (what.code === "auth.required" || what.code === "auth.invalid") $("#login").hidden = false;
  } else if (what instanceof Error) {
    output.textContent = what.message;
  } else {
    output.textContent = what;
  }
}

function showInstance(instance) {
  if (!instance) return;
  $("#instance").textContent = instance.stopping ? "stopping" : instance.ready ? "ready" : "not ready";
}

function showChannel(attachment, record) {
  const section = $("#channel");
  if (!record) return;
  const { declared = {}, observed = {} } = record;
  section.className = observed.suspended ? "suspended" : "";
  const what = observed.suspended
    ? `suspended, ${observed.grade}${observed.by ? ` — ${observed.by} prevails` : ""}${observed.reason ? ` (${observed.reason})` : ""}`
    : "active";
  section.replaceChildren(
    element("strong", { textContent: declared.name ?? "channel" }),
    ` · ${declared.projection} on ${declared.addressClass}, ${declared.clients} · ${what} · client ${observed.client ?? "?"}`,
  );
  // Taking control back is offered only where it can be asked: on a channel bound as a local socket.
  if (declared.addressClass === "local-socket" && observed.suspended) {
    const output = element("output");
    const button = element("button", { textContent: "Reclaim" });
    button.onclick = () => attachment.reclaim().then((r) => say(output, r.changed ? "reclaimed" : "nothing to reclaim"), (e) => say(output, e));
    section.append(" ", button, output);
  }
}

// One operation and its answer, in one row: a type, a payload, a button.
function asking(label, type, act) {
  const output = element("output");
  const payload = element("input", { placeholder: "payload" });
  const button = element("button", { textContent: label + " " + type });
  button.onclick = async () => {
    button.disabled = true;
    try {
      say(output, await act(payload.value));
    } catch (error) {
      say(output, error);
    } finally {
      button.disabled = false;
    }
  };
  return [element("div", { className: "row" }, button, payload), output];
}

function streamRow(attachment, unit, stream) {
  const output = element("output");
  let delivery;
  let frames = 0;
  const start = element("button", { textContent: "start" });
  const stop = element("button", { textContent: "stop" });
  const watch = element("button", { textContent: "watch" });
  start.onclick = () => attachment.streamStart(unit, stream).then((a) => say(output, a.outcome ?? "started"), (e) => say(output, e));
  stop.onclick = () => attachment.streamStop(unit, stream).then((a) => say(output, a.outcome ?? "stopped"), (e) => say(output, e));
  watch.onclick = async () => {
    if (delivery) {
      await delivery.release().catch((e) => say(output, e));
      delivery = undefined;
      watch.textContent = "watch";
      return;
    }
    try {
      delivery = await attachment.streamSubscribe(unit, stream, (frame) => {
        frames += 1;
        say(output, `#${frame.sequence} · ${frame.payload.length} bytes · ${frames} received`);
      });
      watch.textContent = "release";
      say(output, delivery.flowing ? "watching" : "watching — not flowing yet");
    } catch (error) {
      say(output, error);
    }
  };
  return [element("div", { className: "row" }, element("span", { textContent: stream }), start, stop, watch), output];
}

// A unit's card is built from what the channel may address on it, and rebuilt only when that changes;
// its state is refreshed in place.
const cards = new Map();

function showUnits(attachment, units) {
  const main = $("#units");
  const seen = new Set();
  for (const unit of units) {
    const id = unit.declared.identity;
    seen.add(id);
    const addressed = unit.addressed ?? {};
    const shape = JSON.stringify(addressed);
    let card = cards.get(id);
    if (!card || card.shape !== shape) {
      const state = element("span", { className: "state" });
      const body = [element("h2", {}, id, state)];
      for (const type of addressed.commands ?? []) {
        body.push(...asking("command", type, async (payload) => {
          const a = await attachment.command(id, type, payload);
          return `${a.outcome.replace("OUTCOME_", "").toLowerCase()}${a.line ? ": " + a.line : ""}`;
        }));
      }
      for (const type of addressed.queries ?? []) {
        body.push(...asking("ask", type, async (payload) => text(await attachment.query(id, type, payload))));
      }
      for (const stream of addressed.streams ?? []) body.push(...streamRow(attachment, id, stream));
      if (body.length === 1) body.push(element("p", { className: "muted", textContent: `${unit.declared.kind}: nothing this channel may address` }));
      const node = element("article", { className: "unit" }, ...body);
      if (card) card.node.replaceWith(node);
      else main.append(node);
      card = { node, state, shape };
      cards.set(id, card);
    }
    const observed = unit.observed ?? {};
    card.state.className = `state ${(observed.state ?? "").toLowerCase()}`;
    card.state.textContent = [observed.state ?? "unknown", observed.condition?.line].filter(Boolean).join(" · ");
  }
  for (const [id, card] of cards) {
    if (!seen.has(id)) {
      card.node.remove();
      cards.delete(id);
    }
  }
}

function logEvent(event) {
  const log = $("#log");
  const subject = event.subject ? `${event.subject.kind}/${event.subject.identity ?? ""}` : "";
  log.prepend(element("li", { textContent: `${event.seq} ${event.type} ${subject} sev ${event.severity ?? 0}` }));
  while (log.children.length > 200) log.lastChild.remove();
}

function show(attachment, picture) {
  showInstance(picture.instance);
  showChannel(attachment, picture.channel);
  showUnits(attachment, picture.units);
}

async function main() {
  let attachment;
  try {
    attachment = await Attachment.open();
  } catch (error) {
    $("#channel").className = "closed";
    $("#channel").textContent = "the channel refused the attachment or cannot be reached";
    return;
  }
  attachment.listen((news) => {
    if (news.kind === "event") logEvent(news.event);
    if (news.kind === "picture" || news.kind === "opening") show(attachment, news.picture);
    if (news.kind === "closed") {
      $("#channel").className = "closed";
      $("#channel").textContent = `detached${news.reason ? ": " + news.reason : ""} — reload to attach again`;
    }
  });
  show(attachment, attachment.picture);
  $("#login").onsubmit = async (submit) => {
    submit.preventDefault();
    const form = new FormData(submit.target);
    try {
      await attachment.authenticate({ password: { account: form.get("account"), secret: form.get("secret") } });
      $("#login").hidden = true;
    } catch (error) {
      say($("#channel").appendChild(element("output")), error);
    }
  };
}

main();
