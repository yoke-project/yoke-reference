"""A reference Plugin: a clock that tells the time when asked and marks it when told.

It is written against the published Python plugin library like anyone's, and depends on nothing that
somebody outside the project could not obtain. Copy it as the start of a Plugin of your own.
"""

import asyncio
import datetime
import signal
import sys

from yoke_sdk import base, plugin


def declaration():
    """What the clock says about itself: one question, one command, one occurrence, and the capability
    that governs each."""
    return plugin.Declaration(
        id="com.yoke.reference.clock",
        commands=["clock.mark"],
        queries=["clock.now"],
        occurrences=["clock.marked"],
        capabilities=[
            plugin.Capability("command.mark.accept", plugin.Object(command="clock.mark")),
            plugin.Capability("query.now.answer", plugin.Object(query="clock.now")),
            plugin.Capability("event.marked.report", plugin.Object(occurrence="clock.marked")),
        ],
    )


# A mark is routine: the clock states its severity itself, since the library chooses none for it.
MARK_SEVERITY = plugin.Severity.of(10)


def now():
    """The time now, in UTC."""
    return datetime.datetime.now(datetime.timezone.utc)


async def handle(unit, event, now=now):
    """Does what one event of the Session asks, reading the time from now. The unit is anything that
    acknowledges, answers and reports, as a started unit of the library does."""
    instant = now().astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if isinstance(event, plugin.Question) and event.type == "clock.now":
        await unit.answer(event, instant.encode())
    elif isinstance(event, plugin.Command) and event.type == "clock.mark":
        line = "marked at " + instant
        await unit.ack(event, plugin.Outcome.DONE, line)
        await unit.report("clock.marked", MARK_SEVERITY, line)
    # Nothing else is declared, so nothing else is granted, and the Core sends nothing else.


async def run():
    unit = await plugin.start(declaration())
    stopping = asyncio.Event()
    asyncio.get_running_loop().add_signal_handler(signal.SIGTERM, stopping.set)
    asked = asyncio.create_task(stopping.wait())
    while True:
        following = asyncio.create_task(unit.next())
        done, _ = await asyncio.wait({following, asked}, return_when=asyncio.FIRST_COMPLETED)
        if following in done:
            event = following.result()
            if event is None or isinstance(event, plugin.Ended):
                asked.cancel()
                return
            try:
                await handle(unit, event)
            except Exception as err:  # a failed act is said, and the Session goes on
                print("clock:", err, file=sys.stderr)
            continue
        # Asked to stop: close the Session in order, and leave once it has ended.
        following.cancel()
        await unit.close()
        while (event := await unit.next()) is not None and not isinstance(event, plugin.Ended):
            pass
        return


def main():
    # `clock.py manifest` prints the Manifest the declaration generates, installed beside the program.
    if sys.argv[1:] == ["manifest"]:
        sys.stdout.write(declaration().manifest())
        return
    try:
        asyncio.run(run())
    except base.Error as err:
        print("clock:", err, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
