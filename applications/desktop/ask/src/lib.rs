//! The desktop bench's Plugin that must ask the person something: told to join a network, it needs the
//! network's passphrase, which only whoever is at the interface knows.
//!
//! A Plugin is passive: it never addresses an interface, and the Core never reads what it says. So it asks
//! the only way it can. It reports an occurrence, `ask.needed`, that names the ask and says what it wants,
//! and it waits for a command, `ask.answer`, that carries the answer. An interface that attaches while an
//! ask is open learns of it as it learns any present, by asking: `ask.pending` answers with the open asks
//! and the sequence they reflect, and every occurrence carries the sequence it was reported at, so the
//! interface drops those it already knows of. An ask is settled exactly once, and `ask.settled` says how:
//! the first well-formed answer settles it, and an answer that comes after is told there is nothing left
//! to answer. An ask nobody answers is withdrawn when its time runs out.
//!
//! The answer is a secret. It is read from the command's payload, compared, and dropped; it is in no line,
//! no detail and no answer the Plugin gives.

use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};
use yoke_sdk::base::Error;
use yoke_sdk::plugin::{
    Capability, Command, Declaration, Event, Object, Outcome, Question, Severity, Unit,
};

/// What the Plugin says about itself: three commands, one question, two occurrences, and the capability
/// that governs each.
pub fn declaration() -> Declaration {
    let governs = [
        ("command.join.accept", Object::Command("ask.join".into())),
        (
            "command.answer.accept",
            Object::Command("ask.answer".into()),
        ),
        (
            "command.withdraw.accept",
            Object::Command("ask.withdraw".into()),
        ),
        ("query.pending.answer", Object::Query("ask.pending".into())),
        (
            "event.needed.report",
            Object::Occurrence("ask.needed".into()),
        ),
        (
            "event.settled.report",
            Object::Occurrence("ask.settled".into()),
        ),
    ];
    Declaration {
        id: "com.yoke.reference.ask".into(),
        commands: vec![
            "ask.join".into(),
            "ask.answer".into(),
            "ask.withdraw".into(),
        ],
        queries: vec!["ask.pending".into()],
        occurrences: vec!["ask.needed".into(), "ask.settled".into()],
        capabilities: governs
            .into_iter()
            .map(|(name, governs)| Capability {
                name: name.into(),
                governs,
            })
            .collect(),
        ..Default::default()
    }
}

/// An ask waits on somebody, so it is reported above the routine; how it was settled is routine.
pub const NEEDED_SEVERITY: u8 = 40;
pub const SETTLED_SEVERITY: u8 = 10;
/// How long an ask stays open when nobody answers it.
pub const WAIT_MS: u64 = 120_000;

/// What the Plugin does on its Session. A started unit of the library does all three.
pub trait Acts {
    fn ack(
        &self,
        c: &Command,
        outcome: Outcome,
        line: &str,
    ) -> impl Future<Output = Result<(), Error>>;
    fn answer(&self, q: &Question, payload: Vec<u8>) -> impl Future<Output = Result<(), Error>>;
    fn report(
        &self,
        occurrence: &str,
        severity: Severity,
        line: &str,
        detail: Vec<u8>,
    ) -> impl Future<Output = Result<(), Error>>;
}

impl Acts for Unit {
    async fn ack(&self, c: &Command, outcome: Outcome, line: &str) -> Result<(), Error> {
        Unit::ack(self, c, outcome, line).await
    }
    async fn answer(&self, q: &Question, payload: Vec<u8>) -> Result<(), Error> {
        Unit::answer(self, q, payload).await
    }
    async fn report(
        &self,
        occurrence: &str,
        severity: Severity,
        line: &str,
        detail: Vec<u8>,
    ) -> Result<(), Error> {
        Unit::report(self, occurrence, Some(severity), line, detail).await
    }
}

/// One ask still open.
#[derive(Debug, Clone)]
struct Ask {
    network: String,
    prompt: String,
    expires_ms: u64,
}

/// The asks the Plugin holds, and the sequence of the last occurrence it reported about them.
#[derive(Debug)]
pub struct Asks {
    sequence: u64,
    made: u64,
    wait_ms: u64,
    open: BTreeMap<String, Ask>,
}

impl Asks {
    /// No ask open; one made from now on stays open `wait_ms` when nobody answers it.
    pub fn new(wait_ms: u64) -> Self {
        Asks {
            sequence: 0,
            made: 0,
            wait_ms,
            open: BTreeMap::new(),
        }
    }

    /// When the first open ask runs out, in milliseconds since the epoch.
    pub fn deadline(&self) -> Option<u64> {
        self.open.values().map(|a| a.expires_ms).min()
    }

    /// The present, as `ask.pending` answers it.
    pub fn present(&self) -> Value {
        let asks: Vec<Value> = self
            .open
            .iter()
            .map(|(id, a)| {
                json!({"id": id, "network": a.network, "prompt": a.prompt, "secret": true, "expires_ms": a.expires_ms})
            })
            .collect();
        json!({"sequence": self.sequence, "asks": asks})
    }
}

/// Does what one event of the Session asks, at `now_ms`, in milliseconds since the epoch.
pub async fn handle(
    u: &impl Acts,
    asks: &mut Asks,
    event: &Event,
    now_ms: u64,
) -> Result<(), Error> {
    match event {
        Event::Question(q) if q.r#type == "ask.pending" => {
            u.answer(q, asks.present().to_string().into_bytes()).await
        }
        Event::Command(c) if c.r#type == "ask.join" => join(u, asks, c, now_ms).await,
        Event::Command(c) if c.r#type == "ask.answer" => answer(u, asks, c).await,
        Event::Command(c) if c.r#type == "ask.withdraw" => withdraw(u, asks, c).await,
        // Nothing else is declared, so nothing else is granted, and the Core sends nothing else.
        _ => Ok(()),
    }
}

/// Withdraws every ask whose time has run out at `now_ms`.
pub async fn expire(u: &impl Acts, asks: &mut Asks, now_ms: u64) -> Result<(), Error> {
    let gone: Vec<String> = asks
        .open
        .iter()
        .filter(|(_, a)| a.expires_ms <= now_ms)
        .map(|(id, _)| id.clone())
        .collect();
    for id in gone {
        settle(u, asks, &id, "expired", "nobody answered in time").await?;
    }
    Ok(())
}

async fn join(u: &impl Acts, asks: &mut Asks, c: &Command, now_ms: u64) -> Result<(), Error> {
    let Some(network) = field(&c.payload, "network").filter(|n| !n.is_empty()) else {
        return u
            .ack(
                c,
                Outcome::Failed,
                r#"a join names the network: {"network": "<name>"}"#,
            )
            .await;
    };
    if let Some((id, _)) = asks.open.iter().find(|(_, a)| a.network == network) {
        let line = format!("the passphrase of {network} is already asked, as {id}");
        return u.ack(c, Outcome::Failed, &line).await;
    }
    asks.made += 1;
    asks.sequence += 1;
    let id = format!("a{}", asks.made);
    let prompt = format!("The passphrase of the network {network}");
    let ask = Ask {
        network: network.clone(),
        prompt: prompt.clone(),
        expires_ms: now_ms + asks.wait_ms,
    };
    let line = format!("{id} asks for the passphrase of {network}");
    let detail = json!({
        "sequence": asks.sequence, "id": id, "network": network, "prompt": prompt,
        "secret": true, "expires_ms": ask.expires_ms, "line": line,
    });
    asks.open.insert(id.clone(), ask);
    u.ack(c, Outcome::Accepted, &line).await?;
    u.report(
        "ask.needed",
        Severity::of(NEEDED_SEVERITY),
        &line,
        detail.to_string().into_bytes(),
    )
    .await
}

async fn answer(u: &impl Acts, asks: &mut Asks, c: &Command) -> Result<(), Error> {
    let (Some(id), Some(passphrase)) = (field(&c.payload, "id"), field(&c.payload, "answer"))
    else {
        return u
            .ack(c, Outcome::Failed, r#"an answer names its ask and carries the answer: {"id": "<ask>", "answer": "<text>"}"#)
            .await;
    };
    if !asks.open.contains_key(&id) {
        let line = format!("{id} is not open: it was settled, or never asked");
        return u.ack(c, Outcome::Failed, &line).await;
    }
    // A passphrase of WPA is 8 to 63 characters. One that is not is not an answer, and the ask stays open
    // for the next.
    let length = passphrase.chars().count();
    drop(passphrase);
    if !(8..=63).contains(&length) {
        let line = format!("{id} stays open: a passphrase is 8 to 63 characters");
        return u.ack(c, Outcome::Failed, &line).await;
    }
    let line = format!("{id} is answered");
    u.ack(c, Outcome::Done, &line).await?;
    settle(u, asks, &id, "accepted", "answered").await
}

async fn withdraw(u: &impl Acts, asks: &mut Asks, c: &Command) -> Result<(), Error> {
    let Some(id) = field(&c.payload, "id") else {
        return u
            .ack(
                c,
                Outcome::Failed,
                r#"a withdrawal names its ask: {"id": "<ask>"}"#,
            )
            .await;
    };
    if !asks.open.contains_key(&id) {
        let line = format!("{id} is not open: it was settled, or never asked");
        return u.ack(c, Outcome::Failed, &line).await;
    }
    let line = format!("{id} is withdrawn");
    u.ack(c, Outcome::Done, &line).await?;
    settle(u, asks, &id, "withdrawn", "withdrawn at the interface").await
}

/// Closes an open ask and says how.
async fn settle(
    u: &impl Acts,
    asks: &mut Asks,
    id: &str,
    outcome: &str,
    why: &str,
) -> Result<(), Error> {
    let Some(ask) = asks.open.remove(id) else {
        return Ok(());
    };
    asks.sequence += 1;
    let line = format!("{id}, for {}, is {outcome}: {why}", ask.network);
    let detail = json!({
        "sequence": asks.sequence, "id": id, "network": ask.network, "outcome": outcome, "line": line,
    });
    u.report(
        "ask.settled",
        Severity::of(SETTLED_SEVERITY),
        &line,
        detail.to_string().into_bytes(),
    )
    .await
}

/// A string field of a JSON object payload.
fn field(payload: &[u8], name: &str) -> Option<String> {
    let v: Value = serde_json::from_slice(payload).ok()?;
    v.get(name)?.as_str().map(str::to_owned)
}

/// The time now, in milliseconds since the epoch.
pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}
