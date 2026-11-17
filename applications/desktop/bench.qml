// The desktop bench's document: what a desktop shell does, with nothing of any shell. It attaches to the
// channel `desktop` of an application instance with the C++ family's QML binding, and joins hw-monitor's
// present to what follows it without a gap: it subscribes to the CPU and memory streams, starts them, and
// only then asks the snapshot; the frames that arrive meanwhile are held, and those at or below the
// sequence the snapshot states for their stream are dropped, as already in it. It draws the latest of each.
//
// It is started beside the application, not by it, with the instance on the command line:
//   qml -I <import path> bench.qml -- --instance <instance> [--channel desktop]
// Each thing it sees it also says on standard error, a line beginning `bench:`, which is what a case
// reads.
import QtQuick
import QtQuick.Window
import Yoke.Interface

Window {
    id: bench

    readonly property var args: Qt.application.arguments
    readonly property string unit: "hw-monitor"
    readonly property var streams: ["hw.cpu", "hw.memory"]
    property var snapshot: null
    property var cpu: null
    property var memory: null
    // Per stream: the frames held until the snapshot is answered, and the sequence of the last value applied.
    property var held: ({ "hw.cpu": [], "hw.memory": [] })
    property var applied: ({})
    property bool asked: false

    function arg(name, otherwise) {
        const i = args.indexOf(name);
        return i >= 0 && i + 1 < args.length ? args[i + 1] : otherwise;
    }
    // A value of a stream, applied in the order the unit counted it; one that skips a count says so.
    function apply(stream, value) {
        if (!value)
            return;
        const last = applied[stream];
        if (last !== undefined && value.sequence <= last)
            return;
        if (last !== undefined && value.sequence !== last + 1)
            console.log("bench: gap " + stream + " after " + last + " to " + value.sequence);
        applied[stream] = value.sequence;
        console.log("bench: value " + stream + " " + value.sequence);
        if (stream === "hw.cpu")
            cpu = value;
        else
            memory = value;
    }
    // The present, asked once both deliveries are open: what the snapshot reflects is dropped from what
    // was held, and the rest applied after it.
    function join() {
        if (asked || !cpuDelivery.open || !memoryDelivery.open)
            return;
        asked = true;
        for (const stream of streams)
            yoke.startStream(unit, stream, ack => console.log("bench: " + stream + " started " + ack.outcome),
                             refusal => console.log("bench: " + stream + " not started " + refusal.code));
        yoke.ask(unit, "hw.snapshot", "", answer => {
            snapshot = json(answer);
            console.log("bench: snapshot " + yoke.text(answer));
            for (const stream of streams) {
                const present = snapshot ? snapshot[stream === "hw.cpu" ? "cpu" : "memory"] : null;
                const at = present && present.sequence !== undefined ? present.sequence : 0;
                applied[stream] = at;
                if (stream === "hw.cpu")
                    cpu = present;
                else
                    memory = present;
                const kept = held[stream].filter(v => v.sequence > at);
                console.log("bench: joined " + stream + " at " + at + ", " + (held[stream].length - kept.length) + " held dropped");
                for (const v of kept)
                    apply(stream, v);
                held[stream] = null;
            }
        }, refusal => console.log("bench: hw.snapshot refused " + refusal.code));
    }
    function arrived(stream, frame) {
        console.log("bench: " + stream + " " + frame.sequence);
        const value = json(frame.payload);
        if (held[stream] !== null)
            held[stream].push(value);
        else
            apply(stream, value);
    }
    function json(bytes) {
        try {
            return JSON.parse(yoke.text(bytes));
        } catch (e) {
            console.log("bench: a payload is not JSON: " + e);
            return null;
        }
    }

    width: 380
    height: 200
    visible: true
    title: "Yoke desktop bench"
    color: "#1e1e2e"

    Attachment {
        id: yoke

        instance: bench.arg("--instance", "")
        channel: bench.arg("--channel", "desktop")
        onStatusChanged: {
            if (attached) {
                console.log("bench: attached to " + channel + " of " + instance + " (contract " + version + ")");
                bench.join();
            } else if (status === Attachment.Ended) {
                console.log("bench: ended " + failure.code + " " + failure.message);
            }
        }
    }

    Delivery {
        id: cpuDelivery

        attachment: yoke
        unit: bench.unit
        stream: "hw.cpu"
        onOpenChanged: bench.join()
        onFrame: frame => bench.arrived("hw.cpu", frame)
    }

    Delivery {
        id: memoryDelivery

        attachment: yoke
        unit: bench.unit
        stream: "hw.memory"
        onOpenChanged: bench.join()
        onFrame: frame => bench.arrived("hw.memory", frame)
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Text {
            color: yoke.attached ? "#a6e3a1" : "#f38ba8"
            font.pixelSize: 14
            text: yoke.attached ? "attached to " + yoke.channel : "not attached"
        }
        Text {
            color: "#cdd6f4"
            font.pixelSize: 22
            text: "CPU " + (bench.cpu ? bench.cpu.aggregate_usage_percent.toFixed(1) + " %" : "—")
        }
        Text {
            color: "#cdd6f4"
            font.pixelSize: 22
            text: "Memory " + (bench.memory ? bench.memory.usage_percent.toFixed(1) + " %" : "—")
        }
        Text {
            color: "#9399b2"
            font.pixelSize: 12
            text: bench.snapshot ? "snapshot at " + new Date(bench.snapshot.at_ms).toLocaleTimeString() : "no snapshot yet"
        }
    }
}
