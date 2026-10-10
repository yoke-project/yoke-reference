import datetime
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import clock  # noqa: E402
from yoke_sdk import plugin  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Session:
    """Records what the clock does on it."""

    def __init__(self):
        self.acts = []

    async def ack(self, command, outcome, line=""):
        self.acts.append(("ack", command.id, outcome, line))

    async def answer(self, question, payload):
        self.acts.append(("answer", question.id, payload))

    async def report(self, occurrence, severity, line="", detail=b""):
        self.acts.append(("report", occurrence, severity.value, line))


def noon():
    """2026-09-26 12:00:00 UTC, told in another zone."""
    return datetime.datetime(2026, 9, 26, 14, 0, 0, tzinfo=datetime.timezone(datetime.timedelta(hours=2)))


class TheClock(unittest.IsolatedAsyncioTestCase):
    # std: yoke-reference:the-python-clock.01
    def test_the_manifest_is_the_one_the_declaration_generates(self):
        with open(os.path.join(HERE, "manifest.yaml")) as f:
            committed = f.read()
        d = clock.declaration()
        self.assertEqual(committed, d.manifest(), "run `python clock.py manifest > manifest.yaml`")
        self.assertEqual(d.id, "com.yoke.reference.clock")
        self.assertEqual((d.queries, d.commands, d.occurrences), (["clock.now"], ["clock.mark"], ["clock.marked"]))
        governed = sorted(c.governs.query or c.governs.command or c.governs.occurrence for c in d.capabilities)
        self.assertEqual(governed, ["clock.mark", "clock.marked", "clock.now"])

    # std: yoke-reference:the-python-clock.02
    async def test_a_question_for_the_time_is_answered(self):
        s = Session()
        await clock.handle(s, plugin.Question("q-1", "clock.now", b""), noon)
        self.assertEqual(s.acts, [("answer", "q-1", b"2026-09-26T12:00:00Z")])

    # std: yoke-reference:the-python-clock.03
    async def test_a_mark_is_acknowledged_and_reported_with_the_clocks_own_severity(self):
        s = Session()
        await clock.handle(s, plugin.Command("c-1", "clock.mark", b""), noon)
        line = "marked at 2026-09-26T12:00:00Z"
        self.assertEqual(s.acts, [("ack", "c-1", plugin.Outcome.DONE, line), ("report", "clock.marked", 10, line)])


if __name__ == "__main__":
    unittest.main()
