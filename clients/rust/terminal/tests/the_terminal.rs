//! The cases of the-rust-terminal.std.md, one test each.

use yoke_sdk::base::yoke_proto::interface::v1 as pb;

use terminal::{Args, event_line, parse, picture, run};

fn none(_: &str) -> Option<String> {
    None
}

fn said(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| s.to_string()).collect()
}

// std: yoke-reference:the-rust-terminal.01
#[test]
fn the_channel_is_named_one_way_and_the_operations_are_read() {
    let env = |k: &str| match k {
        "XDG_RUNTIME_DIR" => Some("/run/user/1000".to_string()),
        "YOKE_SOCKET" => Some("/run/yoke/interfaces/panel.sock".to_string()),
        _ => None,
    };
    let by_instance = parse(
        &said(&[
            "--instance",
            "bench-a",
            "--channel",
            "terminal",
            "--command",
            "clock:clock.mark=now",
            "--ask",
            "clock:clock.now",
            "--events",
            "2",
        ]),
        env,
    )
    .unwrap();
    assert_eq!(
        by_instance,
        Args {
            address: "/run/user/1000/yoke/bench-a/interfaces/terminal.sock".into(),
            command: Some(("clock".into(), "clock.mark".into(), "now".into())),
            ask: Some(("clock".into(), "clock.now".into(), String::new())),
            events: 2,
        }
    );
    assert_eq!(
        parse(
            &said(&["--runtime", "/run/yoke", "--channel", "panel"]),
            none
        )
        .unwrap()
        .address,
        "/run/yoke/interfaces/panel.sock"
    );
    assert_eq!(
        parse(&said(&["--socket", "/tmp/a.sock"]), none)
            .unwrap()
            .address,
        "/tmp/a.sock"
    );
    assert_eq!(
        parse(&[], env).unwrap().address,
        "/run/yoke/interfaces/panel.sock"
    );
    assert!(
        parse(&[], none).is_err(),
        "a managed interface handed no channel was taken"
    );
    assert!(
        parse(
            &said(&["--socket", "/a", "--instance", "x", "--channel", "y"]),
            none
        )
        .is_err()
    );
    assert!(parse(&said(&["--command", "clock"]), none).is_err());
    assert!(parse(&said(&["--events", "many", "--socket", "/a"]), none).is_err());
}

// std: yoke-reference:the-rust-terminal.02
#[test]
fn a_picture_is_drawn_a_line_for_each_thing_the_channel_sees() {
    let unit = pb::Record {
        subject: Some(pb::record::Subject::Unit(pb::UnitRecord {
            declared: Some(pb::unit_record::Declared {
                identity: "clock".into(),
                kind: "plugin".into(),
            }),
            observed: Some(pb::unit_record::Observed {
                state: "Running".into(),
                ..Default::default()
            }),
            addressed: Some(pb::unit_record::Addressed {
                streams: vec![],
                commands: vec!["clock.mark".into()],
                queries: vec!["clock.now".into()],
            }),
        })),
    };
    let channel = pb::Record {
        subject: Some(pb::record::Subject::Channel(pb::ChannelRecord {
            declared: Some(pb::channel_record::Declared {
                name: "terminal".into(),
                projection: "local".into(),
                ..Default::default()
            }),
            observed: Some(pb::channel_record::Observed {
                attached: true,
                ..Default::default()
            }),
        })),
    };
    let instance = pb::Record {
        subject: Some(pb::record::Subject::Instance(pb::InstanceRecord {
            ready: true,
            ..Default::default()
        })),
    };
    let lines = picture(&pb::Snapshot {
        at: 4,
        records: vec![instance, unit, channel],
    });
    assert_eq!(
        lines,
        [
            "instance ready",
            "unit clock Running commands=[clock.mark] queries=[clock.now] streams=[]",
            "channel terminal local attached"
        ]
    );
    let event = pb::Event {
        seq: 7,
        r#type: "unit.state.changed".into(),
        subject: Some(pb::Subject {
            kind: "unit".into(),
            identity: "clock".into(),
            incarnation: 1,
        }),
        ..Default::default()
    };
    assert_eq!(event_line(&event), "event #7 unit.state.changed unit clock");
}

// std: yoke-reference:the-rust-terminal.03
#[tokio::test]
async fn a_channel_nobody_serves_is_said_and_the_status_is_one() {
    let args = Args {
        address: "/tmp/yoke-terminal-no-such-channel.sock".into(),
        command: None,
        ask: None,
        events: 0,
    };
    let mut out = Vec::new();
    let status = run(&args, &mut out).await;
    let said = String::from_utf8(out).unwrap();
    assert_eq!(status, 1);
    assert!(said.starts_with("terminal: "), "{said}");
    assert!(
        said.contains("failed") || said.contains("refused"),
        "{said}"
    );
}
