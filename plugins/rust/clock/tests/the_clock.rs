use std::sync::Mutex;

use clock::{Acts, declaration, handle, rfc3339};
use yoke_sdk::base::Error;
use yoke_sdk::plugin::{Command, Event, Object, Outcome, Question, Severity};

/// What the clock did on a Session that records it.
#[derive(Debug, PartialEq)]
enum Act {
    Acked {
        id: String,
        done: bool,
        line: String,
    },
    Answered {
        id: String,
        payload: String,
    },
    Reported {
        occurrence: String,
        severity: String,
        line: String,
    },
}

#[derive(Default)]
struct Session(Mutex<Vec<Act>>);

impl Acts for Session {
    async fn ack(&self, c: &Command, outcome: Outcome, line: &str) -> Result<(), Error> {
        let done = matches!(outcome, Outcome::Done);
        self.0.lock().unwrap().push(Act::Acked {
            id: c.id.clone(),
            done,
            line: line.into(),
        });
        Ok(())
    }
    async fn answer(&self, q: &Question, payload: Vec<u8>) -> Result<(), Error> {
        let payload = String::from_utf8(payload).unwrap();
        self.0.lock().unwrap().push(Act::Answered {
            id: q.id.clone(),
            payload,
        });
        Ok(())
    }
    async fn report(&self, occurrence: &str, severity: Severity, line: &str) -> Result<(), Error> {
        self.0.lock().unwrap().push(Act::Reported {
            occurrence: occurrence.into(),
            severity: format!("{severity:?}"),
            line: line.into(),
        });
        Ok(())
    }
}

/// 2026-09-26 12:00:00 UTC.
fn noon() -> u64 {
    1_790_424_000
}

// std: yoke-reference:the-rust-clock.01
#[test]
fn the_manifest_is_the_one_the_declaration_generates() {
    let committed =
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/manifest.yaml")).unwrap();
    let d = declaration();
    assert_eq!(
        committed,
        d.manifest(),
        "manifest.yaml is not what the declaration generates; run `cargo run -q -- manifest > manifest.yaml`"
    );
    assert_eq!(d.id, "com.yoke.reference.clock");
    assert_eq!(
        (d.queries, d.commands, d.occurrences),
        (
            vec!["clock.now".to_string()],
            vec!["clock.mark".to_string()],
            vec!["clock.marked".to_string()]
        )
    );
    let mut governed: Vec<String> = d
        .capabilities
        .iter()
        .map(|c| match &c.governs {
            Object::Query(o) | Object::Command(o) | Object::Occurrence(o) => o.clone(),
            other => format!("{other:?}"),
        })
        .collect();
    governed.sort();
    assert_eq!(governed, ["clock.mark", "clock.marked", "clock.now"]);
}

// std: yoke-reference:the-rust-clock.02
#[tokio::test]
async fn a_question_for_the_time_is_answered() {
    assert_eq!(rfc3339(noon()), "2026-09-26T12:00:00Z");
    let s = Session::default();
    let q = Question {
        id: "q-1".into(),
        r#type: "clock.now".into(),
        payload: Vec::new(),
    };
    handle(&s, &Event::Question(q), noon).await.unwrap();
    assert_eq!(
        *s.0.lock().unwrap(),
        [Act::Answered {
            id: "q-1".into(),
            payload: "2026-09-26T12:00:00Z".into()
        }]
    );
}

// std: yoke-reference:the-rust-clock.03
#[tokio::test]
async fn a_mark_is_acknowledged_and_reported_with_the_clocks_own_severity() {
    let s = Session::default();
    let c = Command {
        id: "c-1".into(),
        r#type: "clock.mark".into(),
        payload: Vec::new(),
    };
    handle(&s, &Event::Command(c), noon).await.unwrap();
    let line = "marked at 2026-09-26T12:00:00Z".to_string();
    assert_eq!(
        *s.0.lock().unwrap(),
        [
            Act::Acked {
                id: "c-1".into(),
                done: true,
                line: line.clone()
            },
            Act::Reported {
                occurrence: "clock.marked".into(),
                severity: format!("{:?}", Severity::of(10)),
                line
            },
        ]
    );
}
