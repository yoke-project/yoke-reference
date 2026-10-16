"""A reference Plugin: the example's pipeline, which identifies spectra against an index of reference lines.

It runs in a container, from an image of its own, and is written against the published Python plugin
library like anyone's. It reads nobody's stream: units never address each other, so whoever holds a
spectrum asks the pipeline about it, and the pipeline answers and publishes what it concluded. Copy it as
the start of a Plugin that answers questions.
"""

import argparse
import asyncio
import json
import signal
import sys

from yoke_sdk import plugin

QUESTION = "spectrum.identify"
STREAM = "station.identified"

# The reference lines the index is built from: the bin each falls in, and its name.
REFERENCE_LINES = {3: "hydrogen-alpha", 8: "lamp", 12: "sodium-d"}


def declaration():
    """What the pipeline says about itself: one question, one stream, and the capability that governs each.
    It needs nothing of the host: what it carries is its numerical code, in its image."""
    return plugin.Declaration(
        id="com.yoke.station.pipeline",
        streams=[plugin.Stream(STREAM)],
        queries=[QUESTION],
        capabilities=[
            plugin.Capability("query.identify.answer", plugin.Object(query=QUESTION)),
            plugin.Capability("stream.identified.publish", plugin.Object(stream=STREAM)),
        ],
    )


def build_index(lines=REFERENCE_LINES):
    """The index the pipeline answers from: for every bin, the reference line nearest to it."""
    bins = range(max(lines) + 8)
    return {b: min(lines, key=lambda line: (abs(line - b), line)) for b in bins}


def identify(index, site, spectrum):
    """What the pipeline concludes about one spectrum, as acquire publishes it: the peak, the centroid
    above the baseline, and the reference line the peak falls on."""
    counts = spectrum["counts"]
    if not isinstance(counts, list) or not counts or not all(isinstance(c, int) for c in counts):
        raise ValueError("the spectrum carries no counts")
    peak = max(range(len(counts)), key=lambda b: (counts[b], -b))
    baseline = min(counts)
    above = [c - baseline for c in counts]
    total = sum(above)
    centroid = sum(b * c for b, c in enumerate(above)) / total if total else float(peak)
    nearest = index.get(peak)
    line = REFERENCE_LINES[nearest] if nearest == peak else None
    return {
        "site": site,
        "scan": spectrum.get("scan"),
        "peak_bin": peak,
        "centroid": round(centroid, 3),
        "line": line,
    }


class Pipeline:
    """The pipeline between two questions: its site, its index, and whether its stream flows."""

    def __init__(self, site):
        self.site = site
        self.index = None
        self.flowing = False

    async def begin(self, unit):
        """Builds the index, and only then says the pipeline is well: a question before it would have
        nothing to be answered from."""
        self.index = build_index()
        await unit.health(0, "identifying against %d reference lines" % len(REFERENCE_LINES))

    async def handle(self, unit, event):
        """Does what one event of the Session asks."""
        if isinstance(event, plugin.Activated) and event.stream == STREAM:
            self.flowing = True
        elif isinstance(event, plugin.Stopped) and event.stream == STREAM:
            self.flowing = False
        elif isinstance(event, plugin.Question) and event.type == QUESTION:
            try:
                answer = identify(self.index, self.site, json.loads(event.payload))
            except (ValueError, KeyError, TypeError) as err:
                # The payload is the asker's and opaque to the Core: what was wrong with it is said in it.
                await unit.answer(event, json.dumps({"site": self.site, "error": "unreadable spectrum: %s" % err}).encode())
                return
            payload = json.dumps(answer, sort_keys=True).encode()
            await unit.answer(event, payload)
            if self.flowing:
                await unit.emit(STREAM, payload)
        # Nothing else is declared, so nothing else is granted, and the Core sends nothing else.


async def run(site):
    unit = await plugin.start(declaration())
    pipeline = Pipeline(site)
    await pipeline.begin(unit)
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
                await pipeline.handle(unit, event)
            except Exception as err:  # a failed act is said, and the Session goes on
                print("pipeline:", err, file=sys.stderr)
            continue
        # Asked to stop: close the Session in order, and leave once it has ended.
        following.cancel()
        await unit.close()
        while (event := await unit.next()) is not None and not isinstance(event, plugin.Ended):
            pass
        return


def main(argv):
    # `pipeline manifest` prints the Manifest the declaration generates, which is installed beside it.
    if argv == ["manifest"]:
        sys.stdout.write(declaration().manifest())
        return
    parser = argparse.ArgumentParser(prog="pipeline")
    parser.add_argument("--site", required=True, help="the site the pipeline stands in, carried with every answer")
    args = parser.parse_args(argv)
    asyncio.run(run(args.site))


if __name__ == "__main__":
    main(sys.argv[1:])
