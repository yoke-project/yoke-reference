"""The cases of the-python-terminal.std.md, one test each."""

import asyncio
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import terminal  # noqa: E402
from yoke.interface.v1 import codes_pb2, events_pb2, records_pb2  # noqa: E402


class TheTerminal(unittest.IsolatedAsyncioTestCase):
    # std: yoke-reference:the-python-terminal.01
    def test_the_channel_is_named_one_way_and_the_operations_are_read(self):
        env = {
            "XDG_RUNTIME_DIR": "/run/user/1000",
            "YOKE_SOCKET": "/run/yoke/interfaces/panel.sock",
        }
        self.assertEqual(
            terminal.parse(
                [
                    "--instance", "bench-a", "--channel", "terminal",
                    "--command", "clock:clock.mark=now", "--ask", "clock:clock.now",
                    "--events", "2",
                ],
                env.get,
            ),
            (
                "/run/user/1000/yoke/bench-a/interfaces/terminal.sock",
                ("clock", "clock.mark", "now"),
                ("clock", "clock.now", ""),
                2,
            ),
        )  # fmt: skip
        self.assertEqual(
            terminal.parse(["--runtime", "/run/yoke", "--channel", "panel"], {}.get)[0],
            "/run/yoke/interfaces/panel.sock",
        )
        self.assertEqual(
            terminal.parse(["--socket", "/tmp/a.sock"], {}.get)[0], "/tmp/a.sock"
        )
        self.assertEqual(
            terminal.parse([], env.get)[0], "/run/yoke/interfaces/panel.sock"
        )
        for bad in (
            [],
            ["--socket", "/a", "--instance", "x", "--channel", "y"],
            ["--command", "clock"],
            ["--events", "many", "--socket", "/a"],
            ["--wat"],
        ):
            with self.assertRaises(terminal.Usage, msg=str(bad)):
                terminal.parse(bad, {}.get)

    # std: yoke-reference:the-python-terminal.02
    def test_a_picture_is_drawn_a_line_for_each_thing_the_channel_sees(self):
        unit = records_pb2.Record(
            unit=records_pb2.UnitRecord(
                declared=records_pb2.UnitRecord.Declared(
                    identity="clock", kind="plugin"
                ),
                observed=records_pb2.UnitRecord.Observed(state="Running"),
                addressed=records_pb2.UnitRecord.Addressed(
                    commands=["clock.mark"], queries=["clock.now"]
                ),
            )
        )
        channel = records_pb2.Record(
            channel=records_pb2.ChannelRecord(
                declared=records_pb2.ChannelRecord.Declared(
                    name="terminal", projection="local"
                ),
                observed=records_pb2.ChannelRecord.Observed(attached=True),
            )
        )
        instance = records_pb2.Record(instance=records_pb2.InstanceRecord(ready=True))
        self.assertEqual(
            terminal.picture(
                records_pb2.Snapshot(at=4, records=[instance, unit, channel])
            ),
            [
                "instance ready",
                "unit clock Running commands=[clock.mark] queries=[clock.now] streams=[]",
                "channel terminal local attached",
            ],
        )
        event = events_pb2.Event(
            seq=7,
            type="unit.state.changed",
            subject=codes_pb2.Subject(kind="unit", identity="clock", incarnation=1),
        )
        self.assertEqual(
            terminal.event_line(event), "event #7 unit.state.changed unit clock"
        )

    # std: yoke-reference:the-python-terminal.03
    async def test_a_channel_nobody_serves_is_said_and_the_status_is_one(self):
        said = []
        status = await terminal.run(
            "/tmp/yoke-terminal-no-such-channel.sock", None, None, 0, say=said.append
        )
        self.assertEqual(status, 1)
        self.assertTrue(said and said[0].startswith("terminal: "), said)
        self.assertTrue("failed" in said[0] or "refused" in said[0], said)


if __name__ == "__main__":
    unittest.main()
