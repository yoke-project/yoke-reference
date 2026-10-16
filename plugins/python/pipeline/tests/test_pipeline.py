import asyncio
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pipeline  # noqa: E402
from yoke_sdk import plugin  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Session:
    """Records what the pipeline does on it."""

    def __init__(self, watching=None):
        self.acts = []
        self.watching = watching

    async def answer(self, question, payload):
        self.acts.append(("answer", question.id, payload))

    async def emit(self, stream, payload):
        self.acts.append(("emit", stream, payload))

    async def health(self, grade, line=""):
        # What the pipeline held when it said how it is.
        self.acts.append(("health", grade, line, self.watching.index is not None if self.watching else None))


def spectrum(scan, peak=8):
    """A spectrum as acquire publishes it: sixteen counts, peaking in one bin."""
    counts = [1000 - 10 * (b - peak) * (b - peak) for b in range(16)]
    return json.dumps({"label": "bench a", "scan": scan, "counts": counts}).encode()


def ask(n, payload):
    return plugin.Question(id="q-%d" % n, type=pipeline.QUESTION, payload=payload)


def started(site="bench a"):
    p = pipeline.Pipeline(site)
    asyncio.run(p.begin(Session()))
    return p


class ThePipeline(unittest.TestCase):
    # std: yoke-reference:pipeline.01
    def test_the_manifest_is_the_one_its_declaration_generates(self):
        with open(os.path.join(HERE, "manifest.yaml")) as f:
            committed = f.read()
        d = pipeline.declaration()
        self.assertEqual(committed, d.manifest(), "run `python3 pipeline.py manifest > manifest.yaml`")
        self.assertEqual(d.id, "com.yoke.station.pipeline")
        self.assertEqual(d.queries, ["spectrum.identify"])
        self.assertEqual([(s.id, s.tolerates_loss, s.tolerates_reorder) for s in d.streams], [("station.identified", False, False)])
        governed = sorted((c.governs.query or c.governs.stream) for c in d.capabilities)
        self.assertEqual(governed, ["spectrum.identify", "station.identified"])
        self.assertFalse(d.needs)

    # std: yoke-reference:pipeline.02
    def test_a_spectrum_is_identified_against_the_index_with_the_site(self):
        p, s = started(), Session()
        asyncio.run(p.handle(s, ask(1, spectrum(3))))
        asyncio.run(p.handle(s, ask(2, b"not a spectrum")))
        self.assertEqual([a[:2] for a in s.acts], [("answer", "q-1"), ("answer", "q-2")])
        first = json.loads(s.acts[0][2])
        self.assertEqual((first["site"], first["scan"], first["peak_bin"], first["line"]), ("bench a", 3, 8, "lamp"))
        self.assertAlmostEqual(first["centroid"], 8.0, places=3)
        second = json.loads(s.acts[1][2])
        self.assertEqual(second["site"], "bench a")
        self.assertIn("unreadable spectrum", second["error"])

    # std: yoke-reference:pipeline.03
    def test_an_identification_is_published_only_while_its_stream_is_activated(self):
        p, s = started(), Session()
        asyncio.run(p.handle(s, ask(1, spectrum(1))))
        asyncio.run(p.handle(s, plugin.Activated(stream="station.identified", transport="ordered", address="/run/x.sock")))
        asyncio.run(p.handle(s, ask(2, spectrum(2))))
        asyncio.run(p.handle(s, plugin.Stopped(stream="station.identified")))
        asyncio.run(p.handle(s, ask(3, spectrum(3))))
        answers = [a for a in s.acts if a[0] == "answer"]
        emitted = [a for a in s.acts if a[0] == "emit"]
        self.assertEqual(len(answers), 3)
        self.assertEqual(emitted, [("emit", "station.identified", answers[1][2])])

    # std: yoke-reference:pipeline.04
    def test_it_says_it_is_well_only_once_its_index_is_built(self):
        p = pipeline.Pipeline("bench a")
        s = Session(watching=p)
        asyncio.run(p.begin(s))
        self.assertEqual(s.acts, [("health", 0, "identifying against 3 reference lines", True)])


if __name__ == "__main__":
    unittest.main()
