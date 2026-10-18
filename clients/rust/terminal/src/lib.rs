//! A reference interface client: it attaches to a channel, draws the picture the channel opens with,
//! invokes one operation if it is told to, and follows the events of its standing subscription.
//!
//! It is written against the published Rust interface library like anyone's, and depends on nothing that
//! somebody outside the project could not obtain. Copy it as the start of a client of your own.

use std::io::Write;
use std::path::Path;
use std::time::Duration;

use yoke_sdk::base::{Error, yoke_proto::interface::v1 as pb};
use yoke_sdk::interface::{self, Attachment, Options};

pub const USAGE: &str = "usage: terminal [--socket PATH | --instance NAME --channel NAME | --runtime DIR --channel NAME]
                [--command UNIT:TYPE[=PAYLOAD]] [--ask UNIT:TYPE[=PAYLOAD]] [--events COUNT]
With none of the first three, the channel is the one a managed interface is handed (YOKE_SOCKET).";

/// How long the client waits for the Core, for one answer or one event.
const WAIT: Duration = Duration::from_secs(30);

/// What the client was asked to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Args {
    /// The channel's address.
    pub address: String,
    /// A command to send, as unit, type and payload.
    pub command: Option<(String, String, String)>,
    /// A question to ask, as unit, type and payload.
    pub ask: Option<(String, String, String)>,
    /// How many events of the standing subscription to follow before leaving.
    pub events: usize,
}

/// `UNIT:TYPE` or `UNIT:TYPE=PAYLOAD`.
fn operation(said: &str) -> Result<(String, String, String), String> {
    let (target, payload) = said.split_once('=').unwrap_or((said, ""));
    match target.split_once(':') {
        Some((unit, kind)) if !unit.is_empty() && !kind.is_empty() => {
            Ok((unit.into(), kind.into(), payload.into()))
        }
        _ => Err(format!("{said} is not UNIT:TYPE")),
    }
}

/// Reads the command line, and the environment a managed interface is handed.
pub fn parse(
    args: &[String],
    getenv: impl Fn(&str) -> Option<String> + Copy,
) -> Result<Args, String> {
    let (mut socket, mut instance, mut runtime, mut channel) = (None, None, None, None);
    let mut parsed = Args {
        address: String::new(),
        command: None,
        ask: None,
        events: 0,
    };
    let mut it = args.iter();
    while let Some(flag) = it.next() {
        let mut value = || it.next().cloned().ok_or(format!("{flag} takes a value"));
        match flag.as_str() {
            "--socket" => socket = Some(value()?),
            "--instance" => instance = Some(value()?),
            "--runtime" => runtime = Some(value()?),
            "--channel" => channel = Some(value()?),
            "--command" => parsed.command = Some(operation(&value()?)?),
            "--ask" => parsed.ask = Some(operation(&value()?)?),
            "--events" => {
                parsed.events = value()?
                    .parse()
                    .map_err(|_| "--events takes a count".to_string())?
            }
            other => return Err(format!("{other} is not an option")),
        }
    }
    let path = match (socket, instance, runtime, channel) {
        (Some(socket), None, None, None) => socket.into(),
        (None, Some(instance), None, Some(channel)) => {
            interface::application(&instance, &channel, getenv).map_err(|e| e.to_string())?
        }
        (None, None, Some(runtime), Some(channel)) => {
            interface::service(Path::new(&runtime), &channel).map_err(|e| e.to_string())?
        }
        (None, None, None, None) => interface::managed(getenv).map_err(|e| e.to_string())?,
        _ => return Err("the channel is named one way only".into()),
    };
    parsed.address = path.to_string_lossy().into_owned();
    Ok(parsed)
}

/// The lines of a picture, one for each thing the channel sees.
pub fn picture(snapshot: &pb::Snapshot) -> Vec<String> {
    snapshot
        .records
        .iter()
        .filter_map(|r| match r.subject.as_ref()? {
            pb::record::Subject::Instance(i) => Some(format!(
                "instance {}",
                if i.stopping {
                    "stopping"
                } else if i.ready {
                    "ready"
                } else {
                    "starting"
                }
            )),
            pb::record::Subject::Unit(u) => {
                let declared = u.declared.clone().unwrap_or_default();
                let state = u.observed.as_ref().map_or("", |o| o.state.as_str());
                let addressed = u.addressed.clone().unwrap_or_default();
                Some(format!(
                    "unit {} {} commands=[{}] queries=[{}] streams=[{}]",
                    declared.identity,
                    state,
                    addressed.commands.join(","),
                    addressed.queries.join(","),
                    addressed.streams.join(",")
                ))
            }
            pb::record::Subject::Channel(c) => {
                let declared = c.declared.clone().unwrap_or_default();
                let attached = c.observed.as_ref().is_some_and(|o| o.attached);
                Some(format!(
                    "channel {} {} {}",
                    declared.name,
                    declared.projection,
                    if attached { "attached" } else { "detached" }
                ))
            }
        })
        .collect()
}

/// An event on one line: its sequence, what happened and to whom.
pub fn event_line(e: &pb::Event) -> String {
    let subject = e.subject.clone().unwrap_or_default();
    format!(
        "event #{} {} {} {}",
        e.seq, e.r#type, subject.kind, subject.identity
    )
}

/// What a refusal says: its code, and what it names.
fn refusal_line(e: &Error) -> String {
    match e {
        Error::Refusal(r) => format!("refused {}: {}", r.code, r.message),
        other => format!("failed: {other}"),
    }
}

/// Does what it was asked, writing what it sees to `out`; its exit status: 0 done, 1 refused or failed.
pub async fn run(args: &Args, out: &mut impl Write) -> i32 {
    let mut say = |line: String| {
        let _ = writeln!(out, "{line}");
    };
    let attached =
        tokio::time::timeout(WAIT, Attachment::attach(&args.address, Options::new())).await;
    let mut a = match attached {
        Ok(Ok(a)) => a,
        Ok(Err(e)) => {
            say(format!("terminal: {}", refusal_line(&e)));
            return 1;
        }
        Err(_) => {
            say(format!("terminal: failed: {} did not open", args.address));
            return 1;
        }
    };
    say(format!(
        "terminal: attached to {} (contract {})",
        args.address, a.version
    ));
    for line in picture(&a.picture) {
        say(line);
    }
    let mut status = 0;
    // The events are followed from a subscription of the client's own, opened before it asks for anything.
    let mut following = if args.events > 0 {
        match tokio::time::timeout(WAIT, a.subscribe(pb::Filter::default())).await {
            Ok(Ok(sub)) => Some(sub),
            _ => {
                say("terminal: the events could not be followed".into());
                status = 1;
                None
            }
        }
    } else {
        None
    };
    if let Some((unit, kind, payload)) = &args.command {
        match tokio::time::timeout(WAIT, a.command(unit, kind, payload.as_bytes())).await {
            Ok(Ok(ack)) => say(format!(
                "terminal: command {unit}:{kind} {} {}",
                pb::acknowledged::Outcome::try_from(ack.outcome)
                    .map_or("unknown", |o| o.as_str_name()),
                ack.line
            )),
            Ok(Err(e)) => {
                say(format!(
                    "terminal: command {unit}:{kind} {}",
                    refusal_line(&e)
                ));
                status = 1;
            }
            Err(_) => status = 1,
        }
    }
    if let Some((unit, kind, payload)) = &args.ask {
        match tokio::time::timeout(WAIT, a.ask(unit, kind, payload.as_bytes())).await {
            Ok(Ok(answer)) => say(format!(
                "terminal: answer {unit}:{kind} {}",
                String::from_utf8_lossy(&answer)
            )),
            Ok(Err(e)) => {
                say(format!(
                    "terminal: answer {unit}:{kind} {}",
                    refusal_line(&e)
                ));
                status = 1;
            }
            Err(_) => status = 1,
        }
    }
    if let Some(sub) = following.as_mut() {
        let mut seen = 0;
        while seen < args.events {
            match tokio::time::timeout(WAIT, sub.next()).await {
                Ok(Ok(Some(d))) => {
                    if let Some(pb::subscribed::Carries::Event(e)) = d.carries {
                        say(event_line(&e));
                        seen += 1;
                    }
                }
                _ => {
                    say("terminal: the events ended before they were all seen".into());
                    status = 1;
                    break;
                }
            }
        }
    }
    a.close().await;
    status
}
