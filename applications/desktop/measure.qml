// The desktop bench's measuring document: bench.qml's attachment, driven through fixed phases, each figure
// said on standard error as a line beginning `measure:`, which measure.sh reads and writes into a table.
//
//   qml -I <import path> measure.qml -- --instance <instance> [--channel desktop] [--rest 30] [--flowing 30]
//
// The phases, in order: attach, and stop both streams, which another client may have left flowing; ask hw.snapshot twenty times, one after the other; start and stop
// hw.cpu ten times, one after the other; rest, with every stream stopped and nothing asked; flow, with
// hw.cpu and hw.memory started and followed; then quit. Each phase's beginning and end is said with the
// time, so the script can read the processes' counters across exactly that phase. Times are this host's
// clock in milliseconds; a frame's clock is the producer's, in nanoseconds, on the same host.
import QtQuick
import QtQuick.Window
import Yoke.Interface

// A window, since Qt's qml runtime keeps running only what shows one; it says which phase is under way.
Window {
    id: measure

    width: 320
    height: 80
    visible: true
    title: "Yoke desktop bench — measuring"
    property string current: "attaching"

    readonly property var args: Qt.application.arguments
    readonly property string unit: "hw-monitor"
    readonly property int asks: 20
    readonly property int toggles: 10
    property var latencies: []
    property int done: 0
    property double began: 0

    function arg(name, otherwise) {
        const i = args.indexOf(name);
        return i >= 0 && i + 1 < args.length ? args[i + 1] : otherwise;
    }
    function say(line) {
        console.log("measure: " + line);
    }
    function phase(name, what) {
        current = name + " " + what;
        say("phase " + name + " " + what + " " + Date.now());
    }
    // Says the count, the mean and the worst of a set of figures in milliseconds.
    function summary(name, figures) {
        const n = figures.length;
        const mean = n ? figures.reduce((a, b) => a + b, 0) / n : 0;
        const worst = n ? Math.max(...figures) : 0;
        say(name + " n=" + n + " mean=" + mean.toFixed(2) + " worst=" + worst.toFixed(2));
    }
    function failed(what, refusal) {
        say("failed " + what + " " + refusal.code + " " + refusal.message);
        Qt.exit(1);
    }

    // One question after the other: each answered before the next is asked.
    function askNext() {
        if (done === asks) {
            summary("ask", latencies);
            latencies = [];
            done = 0;
            phase("toggle", "begins");
            toggleNext(true);
            return;
        }
        began = Date.now();
        yoke.ask(unit, "hw.snapshot", "", () => {
            latencies = latencies.concat([Date.now() - began]);
            done++;
            askNext();
        }, refusal => failed("hw.snapshot", refusal));
    }
    // Starts and stops hw.cpu, one acknowledgement after the other.
    function toggleNext(start) {
        if (done === 2 * toggles) {
            summary("acknowledge", latencies);
            phase("toggle", "ends");
            phase("rest", "begins");
            rest.start();
            return;
        }
        began = Date.now();
        const then = () => {
            latencies = latencies.concat([Date.now() - began]);
            done++;
            toggleNext(!start);
        };
        if (start)
            yoke.startStream(unit, "hw.cpu", then, refusal => failed("hw.cpu start", refusal));
        else
            yoke.stopStream(unit, "hw.cpu", then, refusal => failed("hw.cpu stop", refusal));
    }

    property Attachment yoke: Attachment {
        instance: measure.arg("--instance", "")
        channel: measure.arg("--channel", "desktop")
        onStatusChanged: {
            if (attached) {
                measure.say("attached " + Date.now());
                // A stream another client started flows for everyone until it is stopped: both are stopped
                // first, so that rest is rest.
                stopStream(measure.unit, "hw.cpu", null, refusal => measure.failed("hw.cpu stop", refusal));
                stopStream(measure.unit, "hw.memory", () => {
                    measure.phase("ask", "begins");
                    measure.askNext();
                }, refusal => measure.failed("hw.memory stop", refusal));
            } else if (status === Attachment.Ended) {
                measure.failed("the attachment", failure);
            }
        }
    }

    // The frames of the flowing phase: from the producer's clock to this handler, where a property is set.
    property var frameLatencies: []
    property int frames: 0
    property real cpu: 0
    property Delivery cpuFrames: Delivery {
        attachment: measure.yoke
        unit: measure.unit
        stream: "hw.cpu"
        onFrame: frame => {
            if (!measure.flowing.running)
                return;
            measure.cpu = JSON.parse(measure.yoke.text(frame.payload)).aggregate_usage_percent;
            measure.frameLatencies = measure.frameLatencies.concat([Date.now() - frame.sentAt / 1e6]);
            measure.frames++;
        }
    }
    property Delivery memoryFrames: Delivery {
        attachment: measure.yoke
        unit: measure.unit
        stream: "hw.memory"
        onFrame: frame => {
            if (!measure.flowing.running)
                return;
            measure.frameLatencies = measure.frameLatencies.concat([Date.now() - frame.sentAt / 1e6]);
            measure.frames++;
        }
    }

    property Timer rest: Timer {
        interval: Number(measure.arg("--rest", "30")) * 1000
        onTriggered: {
            measure.phase("rest", "ends");
            measure.phase("flowing", "begins");
            measure.yoke.startStream(measure.unit, "hw.cpu", null, refusal => measure.failed("hw.cpu start", refusal));
            measure.yoke.startStream(measure.unit, "hw.memory", null, refusal => measure.failed("hw.memory start", refusal));
            flowing.start();
        }
    }
    property Timer flowing: Timer {
        interval: Number(measure.arg("--flowing", "30")) * 1000
        onTriggered: {
            measure.phase("flowing", "ends");
            measure.summary("frame", measure.frameLatencies);
            leave.start();
        }
    }
    // A moment before leaving, so the counters at the phase's end are read from processes still there.
    property Timer leave: Timer {
        interval: 2000
        onTriggered: {
            measure.yoke.stopStream(measure.unit, "hw.cpu");
            measure.yoke.stopStream(measure.unit, "hw.memory", () => Qt.quit(), () => Qt.quit());
        }
    }

    Text {
        anchors.centerIn: parent
        text: measure.current + (measure.cpu ? " — CPU " + measure.cpu.toFixed(1) + " %" : "")
    }
}
