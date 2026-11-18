// The desktop bench's document: what a desktop shell does, with nothing of any shell. It attaches to the
// channel `desktop` of an application instance with the C++ family's QML binding, and joins hw-monitor's
// present to what follows it without a gap: it subscribes to the CPU and memory streams, starts them, and
// only then asks the snapshot; the frames that arrive meanwhile are held, and those at or below the
// sequence the snapshot states for their stream are dropped, as already in it. It draws the latest of each.
//
// It also answers the unit `ask`, a Plugin that must ask the person something: it follows that unit's
// occurrences, asks it `ask.pending` once it does, joins the two by the sequence each occurrence carries,
// as it joins the streams, and shows each open ask with a field to answer it, which `ask.answer` carries
// back. Nothing tells the document that the Plugin asked but the occurrence; nothing tells the Plugin who
// answered but the command.
//
// It is started beside the application, not by it, with the instance on the command line:
//   qml -I <import path> bench.qml -- --instance <instance> [--channel desktop] [--answer <text>]
// --answer is what a case gives in place of a person: each ask the document learns of is answered with it.
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
    // The unit that asks, the asks it holds open by their id, and the occurrences held until its present is
    // answered; the sequence of the last of its occurrences applied.
    readonly property string asker: "ask"
    property var asks: ({})
    property var heldAsks: []
    property var asksAt: undefined

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
    // What the unit that asks said: an ask opened or settled. One the present already reflects is dropped.
    function heard(detail) {
        if (!detail || detail.sequence === undefined)
            return;
        if (asksAt === undefined) {
            heldAsks.push(detail);
            return;
        }
        if (detail.sequence <= asksAt)
            return;
        asksAt = detail.sequence;
        if (detail.outcome === undefined)
            open(detail);
        else
            settled(detail);
    }
    function open(ask) {
        console.log("bench: asked " + ask.id + " for " + ask.network + " (sequence " + asksAt + ")");
        const next = Object.assign({}, asks);
        next[ask.id] = ask;
        asks = next;
        const given = arg("--answer", "");
        if (given !== "")
            answer(ask.id, given);
    }
    function settled(detail) {
        console.log("bench: settled " + detail.id + " " + detail.outcome + " (sequence " + asksAt + ")");
        const next = Object.assign({}, asks);
        delete next[detail.id];
        asks = next;
    }
    // The answer goes back in a command's payload, and is said nowhere: not on standard error, not in a
    // property once sent.
    function answer(id, text) {
        console.log("bench: answering " + id);
        yoke.command(asker, "ask.answer", JSON.stringify({ "id": id, "answer": text }),
                     ack => console.log("bench: " + id + " answer " + ack.outcome + " " + (ack.line || "")),
                     refusal => console.log("bench: " + id + " answer refused " + refusal.code));
    }
    // The asks' present, asked once their occurrences are followed.
    function joinAsks() {
        yoke.ask(asker, "ask.pending", "", reply => {
            const present = json(reply);
            if (!present)
                return;
            asksAt = present.sequence;
            const held = heldAsks;
            heldAsks = [];
            console.log("bench: joined asks at " + asksAt + ", " + held.filter(d => d.sequence <= asksAt).length + " held dropped");
            for (const ask of present.asks)
                open(ask);
            for (const d of held)
                heard(d);
        }, refusal => console.log("bench: ask.pending refused " + refusal.code));
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
    height: 300
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

    Subscription {
        attachment: yoke
        subjectKind: "unit"
        subjectIdentity: bench.asker
        occurrence: "ask."
        occurrencePrefix: true
        onSnapshot: bench.joinAsks()
        onReceived: event => bench.heard(bench.json(event.detail))
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
        Repeater {
            model: Object.keys(bench.asks)

            Column {
                required property string modelData
                readonly property var ask: bench.asks[modelData]

                spacing: 4
                Text {
                    color: "#f9e2af"
                    font.pixelSize: 14
                    text: parent.ask ? parent.ask.prompt : ""
                }
                Rectangle {
                    width: 260
                    height: 26
                    color: "#313244"
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 4
                        color: "#cdd6f4"
                        echoMode: TextInput.Password
                        onAccepted: {
                            bench.answer(parent.parent.modelData, text);
                            text = "";
                        }
                    }
                }
            }
        }
    }
}
