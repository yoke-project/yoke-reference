//! A reference Plugin: a clock that tells the time when asked and marks it when told.
//!
//! It is written against the published Rust plugin library like anyone's, and depends on nothing that
//! somebody outside the project could not obtain. Copy it as the start of a Plugin of your own.

use std::time::{SystemTime, UNIX_EPOCH};

use yoke_sdk::base::Error;
use yoke_sdk::plugin::{
    Capability, Command, Declaration, Event, Object, Outcome, Question, Severity, Unit,
};

/// What the clock says about itself: one question, one command, one occurrence, and the capability
/// that governs each.
pub fn declaration() -> Declaration {
    Declaration {
        id: "com.yoke.reference.clock".into(),
        commands: vec!["clock.mark".into()],
        queries: vec!["clock.now".into()],
        occurrences: vec!["clock.marked".into()],
        capabilities: vec![
            Capability {
                name: "command.mark.accept".into(),
                governs: Object::Command("clock.mark".into()),
            },
            Capability {
                name: "query.now.answer".into(),
                governs: Object::Query("clock.now".into()),
            },
            Capability {
                name: "event.marked.report".into(),
                governs: Object::Occurrence("clock.marked".into()),
            },
        ],
        ..Default::default()
    }
}

/// A mark is routine: the clock states its severity itself, since the library chooses none for it.
const MARK_SEVERITY: u8 = 10;

/// What the clock does on its Session. A started unit of the library does all three.
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
    ) -> impl Future<Output = Result<(), Error>>;
}

impl Acts for Unit {
    async fn ack(&self, c: &Command, outcome: Outcome, line: &str) -> Result<(), Error> {
        Unit::ack(self, c, outcome, line).await
    }
    async fn answer(&self, q: &Question, payload: Vec<u8>) -> Result<(), Error> {
        Unit::answer(self, q, payload).await
    }
    async fn report(&self, occurrence: &str, severity: Severity, line: &str) -> Result<(), Error> {
        Unit::report(self, occurrence, Some(severity), line, Vec::new()).await
    }
}

/// Does what one event of the Session asks, reading the time from `now`, in seconds since the epoch.
pub async fn handle(u: &impl Acts, event: &Event, now: impl Fn() -> u64) -> Result<(), Error> {
    let instant = rfc3339(now());
    match event {
        Event::Question(q) if q.r#type == "clock.now" => u.answer(q, instant.into_bytes()).await,
        Event::Command(c) if c.r#type == "clock.mark" => {
            let line = format!("marked at {instant}");
            u.ack(c, Outcome::Done, &line).await?;
            u.report("clock.marked", Severity::of(MARK_SEVERITY), &line)
                .await
        }
        // Nothing else is declared, so nothing else is granted, and the Core sends nothing else.
        _ => Ok(()),
    }
}

/// The time now, in seconds since the epoch.
pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

/// An instant in UTC as RFC 3339 writes it, to the second.
pub fn rfc3339(seconds: u64) -> String {
    let (days, rest) = ((seconds / 86_400) as i64, seconds % 86_400);
    // Civil from days, after Howard Hinnant's algorithm.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        rest / 3_600,
        rest % 3_600 / 60,
        rest % 60
    )
}
