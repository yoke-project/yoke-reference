//! link: a link of the chain. It answers `chain.ask` by asking the unit its need `next` is bound to the same
//! question, naming the question it answers as the cause, and puts what the Core said of its own question in
//! front of the answer. It follows that unit's `chain.ticks` from the start — which holds the stream against
//! any other channel's stop — and republishes each frame as its own `chain.ticks` while that flows.
//!
//!   link --name <name> --next ${bind.next}
//!   link --manifest
//!
//! The unit is handed the channel's path and nothing else: the unit behind it is the one the channel's opening
//! shows. The follow outlives a restart of that unit; a question asked while it is down fails, and the next
//! one is asked again.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::UNIX_EPOCH;

use serde_json::{Value, json};
use yoke_proto::interface::v1::record::Subject;
use yoke_sdk::interface::{Attachment, Options};
use yoke_sdk::plugin::{
    Capability, Declaration, Event, Object, Question, Stream, Unit, Use, start,
};

const ASK: &str = "chain.ask";
const TICKS: &str = "chain.ticks";
const NEXT: &str = "next";

fn declaration() -> Declaration {
    Declaration {
        id: "com.yoke.reference.chain.link".into(),
        needs: vec![format!("unit:{NEXT}")],
        queries: vec![ASK.into()],
        streams: vec![Stream {
            id: TICKS.into(),
            tolerates_loss: true,
            ..Default::default()
        }],
        uses: BTreeMap::from([(
            NEXT.to_string(),
            Use {
                questions: vec![ASK.into()],
                streams: vec![TICKS.into()],
            },
        )]),
        capabilities: vec![
            Capability {
                name: format!("query.{ASK}.answer"),
                governs: Object::Query(ASK.into()),
            },
            Capability {
                name: format!("stream.{TICKS}.publish"),
                governs: Object::Stream(TICKS.into()),
            },
            Capability {
                name: format!("query.{ASK}.ask"),
                governs: Object::UseQuery(NEXT.into(), ASK.into()),
            },
            Capability {
                name: format!("stream.{TICKS}.follow"),
                governs: Object::UseStream(NEXT.into(), TICKS.into()),
            },
        ],
        ..Default::default()
    }
}

/// The need's channel, attached once: the attachment and the unit its opening shows.
async fn attach(path: &str) -> Result<(Attachment, String), String> {
    let a = Attachment::attach(path, Options::new())
        .await
        .map_err(|e| format!("the channel of the need next cannot be attached: {e}"))?;
    let unit = a
        .picture
        .records
        .iter()
        .find_map(|r| match &r.subject {
            Some(Subject::Unit(u)) => u.declared.as_ref().map(|d| d.identity.clone()),
            _ => None,
        })
        .ok_or("the channel of the need next shows no unit")?;
    Ok((a, unit))
}

struct Link {
    name: String,
    next: Attachment,
    bound: String,
    /// Frames followed from the unit bound, across its restarts.
    followed: AtomicU64,
    emitted: AtomicU64,
    flows: AtomicBool,
}

impl Link {
    /// Answers a question by asking the unit bound, the question as the cause.
    async fn answer(&self, unit: &Unit, q: &Question) {
        let hop = json!({
            "unit": self.name,
            "asker": q.asker,
            "chain": q.chain,
            "deadline": q.deadline.duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as u64,
            "ticks": self.followed.load(Ordering::Relaxed),
        });
        match self
            .next
            .ask_caused(&q.id, &self.bound, ASK, &q.payload)
            .await
        {
            Ok(inner) => {
                let mut hops = vec![hop];
                if let Ok(v) = serde_json::from_slice::<Value>(&inner) {
                    hops.extend(v["hops"].as_array().cloned().unwrap_or_default());
                }
                let _ = unit
                    .answer(q, json!({ "hops": hops }).to_string().into_bytes())
                    .await;
            }
            // The inner failure is this unit's to translate: it says which link it met and what.
            Err(yoke_sdk::base::Error::Refusal(r)) => {
                let code = r.item.clone().unwrap_or_else(|| r.code.clone());
                let _ = unit
                    .fail(
                        &q.id,
                        "next.failed",
                        &format!(
                            "{} could not ask {}: {code}: {}",
                            self.name, self.bound, r.message
                        ),
                    )
                    .await;
            }
            Err(e) => {
                let _ = unit
                    .fail(
                        &q.id,
                        "next.failed",
                        &format!("{} could not ask {}: {e}", self.name, self.bound),
                    )
                    .await;
            }
        }
    }
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--manifest") {
        print!("{}", declaration().manifest());
        return;
    }
    let (name, next) = match args.as_slice() {
        [a, name, b, next] if a == "--name" && b == "--next" => (name.clone(), next.clone()),
        _ => {
            eprintln!("link: usage: link --name <name> --next ${{bind.next}}");
            std::process::exit(2);
        }
    };
    let unit = match start(&declaration()).await {
        Ok(u) => Arc::new(u),
        Err(e) => {
            eprintln!("link: {e}");
            std::process::exit(1);
        }
    };
    let (attachment, bound) = match attach(&next).await {
        Ok(x) => x,
        Err(why) => {
            let _ = unit.health(50, &why).await;
            eprintln!("link: {why}");
            std::process::exit(1);
        }
    };
    let _ = unit.health(0, &format!("{name}: asks {bound}")).await;
    let link = Arc::new(Link {
        name,
        next: attachment,
        bound,
        followed: AtomicU64::new(0),
        emitted: AtomicU64::new(0),
        flows: AtomicBool::new(false),
    });
    // The unit bound's stream, followed from the start and across its restarts.
    {
        let (link, unit) = (link.clone(), unit.clone());
        tokio::spawn(async move {
            let mut follow = match link.next.follow(&link.bound, TICKS).await {
                Ok(f) => f,
                Err(e) => {
                    let _ = unit
                        .health(
                            30,
                            &format!("{} cannot follow {}'s {TICKS}: {e}", link.name, link.bound),
                        )
                        .await;
                    return;
                }
            };
            while let Ok(frame) = follow.next().await {
                link.followed.fetch_add(1, Ordering::Relaxed);
                if link.flows.load(Ordering::Relaxed) {
                    let n = link.emitted.fetch_add(1, Ordering::Relaxed) + 1;
                    let from: Value = serde_json::from_slice(&frame.payload).unwrap_or(Value::Null);
                    let _ = unit
                        .emit(
                            TICKS,
                            json!({ "n": n, "by": link.name, "from": from })
                                .to_string()
                                .into_bytes(),
                        )
                        .await;
                }
            }
        });
    }
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("link listens for SIGTERM");
    loop {
        tokio::select! {
            event = unit.next() => match event {
                None | Some(Event::Ended(_)) => return,
                Some(Event::Activated(a)) if a.stream == TICKS => link.flows.store(true, Ordering::Relaxed),
                Some(Event::Stopped { stream }) if stream == TICKS => link.flows.store(false, Ordering::Relaxed),
                Some(Event::Question(q)) if q.r#type == ASK => {
                    let (link, unit) = (link.clone(), unit.clone());
                    tokio::spawn(async move { link.answer(&unit, &q).await });
                }
                Some(_) => {}
            },
            _ = term.recv() => {
                let _ = unit.close().await;
                while let Some(e) = unit.next().await {
                    if matches!(e, Event::Ended(_)) { break; }
                }
                return;
            }
        }
    }
}
