"""A reference interface client: it attaches to a channel, draws the picture the channel opens with,
invokes one operation if it is told to, and follows the events of its standing subscription.

It is written against the published Python interface library like anyone's, and depends on nothing that
somebody outside the project could not obtain. Copy it as the start of a client of your own.
"""

import asyncio
import sys

from yoke_sdk import base, interface

USAGE = """usage: terminal [--socket PATH | --instance NAME --channel NAME | --runtime DIR --channel NAME]
                [--command UNIT:TYPE[=PAYLOAD]] [--ask UNIT:TYPE[=PAYLOAD]] [--events COUNT]
With none of the first three, the channel is the one a managed interface is handed (YOKE_SOCKET)."""

# How long the client waits for the Core, for one answer or one event.
WAIT = 30


class Usage(Exception):
    """The command line asked for something that is not there to be done."""


def _operation(said):
    """`UNIT:TYPE` or `UNIT:TYPE=PAYLOAD`, as unit, type and payload."""
    target, _, payload = said.partition("=")
    unit, colon, kind = target.partition(":")
    if not colon or not unit or not kind:
        raise Usage(f"{said} is not UNIT:TYPE")
    return unit, kind, payload


def parse(args, getenv):
    """Reads the command line, and the environment a managed interface is handed: the channel's address,
    the command to send, the question to ask, and how many events to follow."""
    named = {"--socket": None, "--instance": None, "--runtime": None, "--channel": None}
    command = ask = None
    events = 0
    it = iter(args)
    for flag in it:
        if flag not in (*named, "--command", "--ask", "--events"):
            raise Usage(f"{flag} is not an option")
        value = next(it, None)
        if value is None:
            raise Usage(f"{flag} takes a value")
        if flag in named:
            named[flag] = value
        elif flag == "--command":
            command = _operation(value)
        elif flag == "--ask":
            ask = _operation(value)
        else:
            try:
                events = int(value)
            except ValueError:
                raise Usage("--events takes a count") from None
    socket, instance, runtime, channel = (
        named["--socket"],
        named["--instance"],
        named["--runtime"],
        named["--channel"],
    )
    try:
        if socket and not (instance or runtime or channel):
            address = socket
        elif instance and channel and not (socket or runtime):
            address = interface.application(instance, channel, getenv)
        elif runtime and channel and not (socket or instance):
            address = interface.service(runtime, channel)
        elif not (socket or instance or runtime or channel):
            address = interface.managed(getenv)
        else:
            raise Usage("the channel is named one way only")
    except base.Error as failure:
        raise Usage(str(failure)) from failure
    return address, command, ask, events


def picture(snapshot):
    """The lines of a picture, one for each thing the channel sees."""
    lines = []
    for record in snapshot.records:
        kind = record.WhichOneof("subject")
        if kind == "instance":
            i = record.instance
            lines.append(
                "instance "
                + ("stopping" if i.stopping else "ready" if i.ready else "starting")
            )
        elif kind == "unit":
            u = record.unit
            lines.append(
                f"unit {u.declared.identity} {u.observed.state} "
                f"commands=[{','.join(u.addressed.commands)}] "
                f"queries=[{','.join(u.addressed.queries)}] "
                f"streams=[{','.join(u.addressed.streams)}]"
            )
        elif kind == "channel":
            c = record.channel
            attached = "attached" if c.observed.attached else "detached"
            lines.append(
                f"channel {c.declared.name} {c.declared.projection} {attached}"
            )
    return lines


def event_line(e):
    """An event on one line: its sequence, what happened and to whom."""
    return f"event #{e.seq} {e.type} {e.subject.kind} {e.subject.identity}"


def _refusal_line(failure):
    if isinstance(failure, base.Refusal):
        return f"refused {failure.code}: {failure.message}"
    return f"failed: {failure}"


async def run(address, command, ask, events, say=print):
    """Does what it was asked, saying what it sees; its exit status: 0 done, 1 refused or failed."""
    try:
        a = await asyncio.wait_for(interface.Attachment.attach(address), WAIT)
    except base.Error as failure:
        say(f"terminal: {_refusal_line(failure)}")
        return 1
    except asyncio.TimeoutError:
        say(f"terminal: failed: {address} did not open")
        return 1
    status = 0
    try:
        say(f"terminal: attached to {address} (contract {a.version})")
        for line in picture(a.picture):
            say(line)
        # The events are followed from a subscription of the client's own, opened before it asks for anything.
        following = None
        if events:
            try:
                following = await asyncio.wait_for(a.subscribe(), WAIT)
            except (base.Error, asyncio.TimeoutError):
                say("terminal: the events could not be followed")
                status = 1
        if command:
            unit, kind, payload = command
            try:
                ack = await asyncio.wait_for(
                    a.command(unit, kind, payload.encode()), WAIT
                )
                outcome = ack.Outcome.Name(ack.outcome)
                say(f"terminal: command {unit}:{kind} {outcome} {ack.line}")
            except (base.Error, asyncio.TimeoutError) as failure:
                say(f"terminal: command {unit}:{kind} {_refusal_line(failure)}")
                status = 1
        if ask:
            unit, kind, payload = ask
            try:
                answer = await asyncio.wait_for(
                    a.ask(unit, kind, payload.encode()), WAIT
                )
                say(f"terminal: answer {unit}:{kind} {answer.decode(errors='replace')}")
            except (base.Error, asyncio.TimeoutError) as failure:
                say(f"terminal: answer {unit}:{kind} {_refusal_line(failure)}")
                status = 1
        if following is not None:
            seen = 0
            while seen < events:
                try:
                    delivery = await asyncio.wait_for(following.next(), WAIT)
                except (base.Error, asyncio.TimeoutError):
                    delivery = None
                if delivery is None:
                    say("terminal: the events ended before they were all seen")
                    status = 1
                    break
                if delivery.WhichOneof("carries") == "event":
                    say(event_line(delivery.event))
                    seen += 1
    finally:
        await a.close()
    return status


def main():
    import os

    try:
        address, command, ask, events = parse(sys.argv[1:], os.environ.get)
    except Usage as why:
        print(f"terminal: {why}\n{USAGE}", file=sys.stderr)
        raise SystemExit(2) from None
    raise SystemExit(asyncio.run(run(address, command, ask, events)))


if __name__ == "__main__":
    main()
