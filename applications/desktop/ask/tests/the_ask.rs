use std::sync::Mutex;

use ask::{Acts, Asks, NEEDED_SEVERITY, SETTLED_SEVERITY, declaration, expire, handle};
use serde_json::Value;
use yoke_sdk::base::Error;
use yoke_sdk::plugin::{Command, Event, Object, Outcome, Question, Severity};

/// What the Plugin did on a Session that records it.
#[derive(Debug, Clone, PartialEq)]
enum Act {
    Acked {
        id: String,
        outcome: String,
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
        detail: String,
    },
}

#[derive(Default)]
struct Session(Mutex<Vec<Act>>);

impl Session {
    fn take(&self) -> Vec<Act> {
        std::mem::take(&mut *self.0.lock().unwrap())
    }
}

impl Acts for Session {
    async fn ack(&self, c: &Command, outcome: Outcome, line: &str) -> Result<(), Error> {
        self.0.lock().unwrap().push(Act::Acked {
            id: c.id.clone(),
            outcome: format!("{outcome:?}"),
            line: line.into(),
        });
        Ok(())
    }
    async fn answer(&self, q: &Question, payload: Vec<u8>) -> Result<(), Error> {
        self.0.lock().unwrap().push(Act::Answered {
            id: q.id.clone(),
            payload: String::from_utf8(payload).unwrap(),
        });
        Ok(())
    }
    async fn report(
        &self,
        occurrence: &str,
        severity: Severity,
        line: &str,
        detail: Vec<u8>,
    ) -> Result<(), Error> {
        self.0.lock().unwrap().push(Act::Reported {
            occurrence: occurrence.into(),
            severity: format!("{severity:?}"),
            line: line.into(),
            detail: String::from_utf8(detail).unwrap(),
        });
        Ok(())
    }
}

const NOW: u64 = 1_790_424_000_000;
const WAIT: u64 = 60_000;
const SECRET: &str = "correct horse battery";

fn command(id: &str, r#type: &str, payload: &str) -> Event {
    Event::Command(Command {
        id: id.into(),
        r#type: r#type.into(),
        payload: payload.as_bytes().to_vec(),
    })
}

fn pending(id: &str) -> Event {
    Event::Question(Question {
        id: id.into(),
        r#type: "ask.pending".into(),
        payload: Vec::new(),
    })
}

fn json(text: &str) -> Value {
    serde_json::from_str(text).unwrap()
}

/// An ask for the network `bench`, made at NOW: the Plugin and the Session it acted on.
async fn asked() -> (Session, Asks) {
    let s = Session::default();
    let mut asks = Asks::new(WAIT);
    handle(
        &s,
        &mut asks,
        &command("c-1", "ask.join", r#"{"network":"bench"}"#),
        NOW,
    )
    .await
    .unwrap();
    s.take();
    (s, asks)
}

/// Every word the Plugin gave the Session, in one string.
fn said(acts: &[Act]) -> String {
    format!("{acts:?}")
}

// std: yoke-reference:ask.01
#[test]
fn the_manifest_is_the_one_the_declaration_generates() {
    let committed = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/com.yoke.reference.ask.yaml"
    ))
    .unwrap();
    let d = declaration();
    assert_eq!(
        committed,
        d.manifest(),
        "com.yoke.reference.ask.yaml is not what the declaration generates; run `cargo run -q -- manifest > com.yoke.reference.ask.yaml`"
    );
    assert_eq!(d.id, "com.yoke.reference.ask");
    let mut governed: Vec<String> = d
        .capabilities
        .iter()
        .map(|c| match &c.governs {
            Object::Query(o) | Object::Command(o) | Object::Occurrence(o) => o.clone(),
            other => format!("{other:?}"),
        })
        .collect();
    governed.sort();
    assert_eq!(
        governed,
        [
            "ask.answer",
            "ask.join",
            "ask.needed",
            "ask.pending",
            "ask.settled",
            "ask.withdraw"
        ]
    );
}

// std: yoke-reference:ask.02
#[tokio::test]
async fn a_join_is_accepted_and_the_ask_reported_with_its_sequence() {
    let s = Session::default();
    let mut asks = Asks::new(WAIT);
    handle(
        &s,
        &mut asks,
        &command("c-1", "ask.join", r#"{"network":"bench"}"#),
        NOW,
    )
    .await
    .unwrap();
    let acts = s.take();
    assert_eq!(acts.len(), 2, "{acts:?}");
    assert_eq!(
        acts[0],
        Act::Acked {
            id: "c-1".into(),
            outcome: "Accepted".into(),
            line: "a1 asks for the passphrase of bench".into()
        }
    );
    let Act::Reported {
        occurrence,
        severity,
        line,
        detail,
    } = &acts[1]
    else {
        panic!("not reported: {acts:?}")
    };
    assert_eq!(occurrence, "ask.needed");
    assert_eq!(severity, &format!("{:?}", Severity::of(NEEDED_SEVERITY)));
    assert_eq!(line, "a1 asks for the passphrase of bench");
    let d = json(detail);
    assert_eq!(d["sequence"], 1);
    assert_eq!(d["id"], "a1");
    assert_eq!(d["network"], "bench");
    assert_eq!(d["secret"], true);
    assert_eq!(d["expires_ms"], NOW + WAIT);
    assert_eq!(d["line"], "a1 asks for the passphrase of bench");

    // The same network asked again while its ask is open is refused, and names the ask.
    handle(
        &s,
        &mut asks,
        &command("c-2", "ask.join", r#"{"network":"bench"}"#),
        NOW,
    )
    .await
    .unwrap();
    assert_eq!(
        s.take(),
        [Act::Acked {
            id: "c-2".into(),
            outcome: "Failed".into(),
            line: "the passphrase of bench is already asked, as a1".into()
        }]
    );
}

// std: yoke-reference:ask.03
#[tokio::test]
async fn an_interface_that_comes_late_is_told_the_open_asks_and_their_sequence() {
    let s = Session::default();
    let mut asks = Asks::new(WAIT);
    handle(&s, &mut asks, &pending("q-0"), NOW).await.unwrap();
    let Act::Answered { payload, .. } = &s.take()[0] else {
        panic!()
    };
    assert_eq!(json(payload), json(r#"{"sequence":0,"asks":[]}"#));

    let (s, mut asks) = asked().await;
    handle(&s, &mut asks, &pending("q-1"), NOW).await.unwrap();
    let acts = s.take();
    let [Act::Answered { id, payload }] = &acts[..] else {
        panic!("{acts:?}")
    };
    assert_eq!(id, "q-1");
    let p = json(payload);
    assert_eq!(
        p["sequence"], 1,
        "the present reflects the ask's own occurrence"
    );
    assert_eq!(p["asks"][0]["id"], "a1");
    assert_eq!(p["asks"][0]["network"], "bench");
    assert_eq!(p["asks"][0]["secret"], true);
}

// std: yoke-reference:ask.04
#[tokio::test]
async fn the_first_answer_settles_the_ask_and_one_after_it_is_told_so() {
    let (s, mut asks) = asked().await;
    let answer = format!(r#"{{"id":"a1","answer":"{SECRET}"}}"#);
    handle(&s, &mut asks, &command("c-2", "ask.answer", &answer), NOW)
        .await
        .unwrap();
    handle(&s, &mut asks, &command("c-3", "ask.answer", &answer), NOW)
        .await
        .unwrap();
    let acts = s.take();
    assert_eq!(acts.len(), 3, "{acts:?}");
    assert_eq!(
        acts[0],
        Act::Acked {
            id: "c-2".into(),
            outcome: "Done".into(),
            line: "a1 is answered".into()
        }
    );
    let Act::Reported {
        occurrence,
        severity,
        detail,
        ..
    } = &acts[1]
    else {
        panic!("{acts:?}")
    };
    assert_eq!(occurrence, "ask.settled");
    assert_eq!(severity, &format!("{:?}", Severity::of(SETTLED_SEVERITY)));
    let d = json(detail);
    assert_eq!(
        (d["sequence"].clone(), d["id"].clone(), d["outcome"].clone()),
        (2.into(), "a1".into(), "accepted".into())
    );
    assert_eq!(
        acts[2],
        Act::Acked {
            id: "c-3".into(),
            outcome: "Failed".into(),
            line: "a1 is not open: it was settled, or never asked".into()
        }
    );
    handle(&s, &mut asks, &pending("q-1"), NOW).await.unwrap();
    let Act::Answered { payload, .. } = &s.take()[0] else {
        panic!()
    };
    assert_eq!(json(payload), json(r#"{"sequence":2,"asks":[]}"#));
}

// std: yoke-reference:ask.05
#[tokio::test]
async fn the_answer_is_in_nothing_the_plugin_says() {
    let (s, mut asks) = asked().await;
    for payload in [
        format!(r#"{{"id":"a1","answer":"{}"}}"#, &SECRET[..5]),
        format!(r#"{{"answer":"{SECRET}"}}"#),
        format!(r#"{{"id":"a9","answer":"{SECRET}"}}"#),
        format!(r#"{{"id":"a1","answer":"{SECRET}""#),
        format!(r#"{{"id":"a1","answer":"{SECRET}"}}"#),
    ] {
        handle(&s, &mut asks, &command("c", "ask.answer", &payload), NOW)
            .await
            .unwrap();
    }
    handle(&s, &mut asks, &pending("q"), NOW).await.unwrap();
    let words = said(&s.take());
    assert!(
        !words.contains(&SECRET[..5]),
        "the answer is in what the Plugin said: {words}"
    );
}

// std: yoke-reference:ask.06
#[tokio::test]
async fn an_answer_that_is_not_one_leaves_the_ask_open() {
    let (s, mut asks) = asked().await;
    handle(
        &s,
        &mut asks,
        &command("c-2", "ask.answer", r#"{"id":"a1","answer":"short"}"#),
        NOW,
    )
    .await
    .unwrap();
    assert_eq!(
        s.take(),
        [Act::Acked {
            id: "c-2".into(),
            outcome: "Failed".into(),
            line: "a1 stays open: a passphrase is 8 to 63 characters".into()
        }]
    );
    handle(&s, &mut asks, &pending("q"), NOW).await.unwrap();
    let Act::Answered { payload, .. } = &s.take()[0] else {
        panic!()
    };
    assert_eq!(json(payload)["asks"][0]["id"], "a1");
}

// std: yoke-reference:ask.07
#[tokio::test]
async fn an_ask_is_withdrawn_at_the_interface_or_when_its_time_runs_out() {
    let (s, mut asks) = asked().await;
    handle(
        &s,
        &mut asks,
        &command("c-2", "ask.withdraw", r#"{"id":"a1"}"#),
        NOW,
    )
    .await
    .unwrap();
    let acts = s.take();
    let Act::Reported { detail, .. } = &acts[1] else {
        panic!("{acts:?}")
    };
    assert_eq!(json(detail)["outcome"], "withdrawn");

    handle(
        &s,
        &mut asks,
        &command("c-3", "ask.join", r#"{"network":"other"}"#),
        NOW,
    )
    .await
    .unwrap();
    s.take();
    assert_eq!(asks.deadline(), Some(NOW + WAIT));
    expire(&s, &mut asks, NOW + WAIT - 1).await.unwrap();
    assert_eq!(s.take(), [], "nothing runs out before its time");
    expire(&s, &mut asks, NOW + WAIT).await.unwrap();
    let acts = s.take();
    let [
        Act::Reported {
            occurrence, detail, ..
        },
    ] = &acts[..]
    else {
        panic!("{acts:?}")
    };
    assert_eq!(occurrence, "ask.settled");
    let d = json(detail);
    assert_eq!(
        (d["id"].clone(), d["outcome"].clone(), d["sequence"].clone()),
        ("a2".into(), "expired".into(), 4.into())
    );
    assert_eq!(
        asks.deadline(),
        None,
        "with no ask open there is no deadline"
    );
}
