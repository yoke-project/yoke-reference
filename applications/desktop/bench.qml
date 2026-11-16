// The desktop bench's document: what a desktop shell does, with nothing of any shell. It attaches to the
// channel `desktop` of an application instance with the C++ family's QML binding, asks hw-monitor for its
// snapshot, starts its CPU and memory streams and follows them, and draws the latest of each.
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

    function arg(name, otherwise) {
        const i = args.indexOf(name);
        return i >= 0 && i + 1 < args.length ? args[i + 1] : otherwise;
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
                ask(bench.unit, "hw.snapshot", "", answer => {
                    bench.snapshot = bench.json(answer);
                    console.log("bench: snapshot " + yoke.text(answer));
                }, refusal => console.log("bench: hw.snapshot refused " + refusal.code));
                for (const stream of bench.streams)
                    startStream(bench.unit, stream, ack => console.log("bench: " + stream + " started " + ack.outcome),
                                refusal => console.log("bench: " + stream + " not started " + refusal.code));
            } else if (status === Attachment.Ended) {
                console.log("bench: ended " + failure.code + " " + failure.message);
            }
        }
    }

    Delivery {
        attachment: yoke
        unit: bench.unit
        stream: "hw.cpu"
        onFrame: frame => {
            bench.cpu = bench.json(frame.payload);
            console.log("bench: hw.cpu " + frame.sequence);
        }
    }

    Delivery {
        attachment: yoke
        unit: bench.unit
        stream: "hw.memory"
        onFrame: frame => {
            bench.memory = bench.json(frame.payload);
            console.log("bench: hw.memory " + frame.sequence);
        }
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
