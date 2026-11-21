//! end: the chain's last link. It answers `chain.ask` with what the Core said of the question — who asked, the
//! chain it belongs to and the instant the asker stops waiting — and publishes `chain.ticks`, a count every
//! 200 ms while the stream flows.
//!
//!   end --name <name>
//!   end --manifest

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, UNIX_EPOCH};

use serde_json::json;
use yoke_sdk::plugin::{Capability, Declaration, Event, Object, Stream, start};

const ASK: &str = "chain.ask";
const TICKS: &str = "chain.ticks";
const EVERY: Duration = Duration::from_millis(200);

fn declaration() -> Declaration {
    Declaration {
        id: "com.yoke.reference.chain.end".into(),
        queries: vec![ASK.into()],
        streams: vec![Stream {
            id: TICKS.into(),
            tolerates_loss: true,
            ..Default::default()
        }],
        capabilities: vec![
            Capability {
                name: format!("query.{ASK}.answer"),
                governs: Object::Query(ASK.into()),
            },
            Capability {
                name: format!("stream.{TICKS}.publish"),
                governs: Object::Stream(TICKS.into()),
            },
        ],
        ..Default::default()
    }
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--manifest") {
        print!("{}", declaration().manifest());
        return;
    }
    let name = match args.as_slice() {
        [flag, name] if flag == "--name" => name.clone(),
        _ => {
            eprintln!("end: usage: end --name <name>");
            std::process::exit(2);
        }
    };
    let unit = match start(&declaration()).await {
        Ok(u) => Arc::new(u),
        Err(e) => {
            eprintln!("end: {e}");
            std::process::exit(1);
        }
    };
    let _ = unit
        .health(0, &format!("{name}: the chain ends here"))
        .await;
    let (flows, emitted) = (
        Arc::new(AtomicBool::new(false)),
        Arc::new(AtomicU64::new(0)),
    );
    {
        let (unit, flows, emitted, name) =
            (unit.clone(), flows.clone(), emitted.clone(), name.clone());
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(EVERY).await;
                if flows.load(Ordering::Relaxed) {
                    let n = emitted.fetch_add(1, Ordering::Relaxed) + 1;
                    let _ = unit
                        .emit(
                            TICKS,
                            json!({ "n": n, "by": name }).to_string().into_bytes(),
                        )
                        .await;
                }
            }
        });
    }
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("end listens for SIGTERM");
    loop {
        tokio::select! {
            event = unit.next() => match event {
                None | Some(Event::Ended(_)) => return,
                Some(Event::Activated(a)) if a.stream == TICKS => flows.store(true, Ordering::Relaxed),
                Some(Event::Stopped { stream }) if stream == TICKS => flows.store(false, Ordering::Relaxed),
                Some(Event::Question(q)) if q.r#type == ASK => {
                    let hop = json!({
                        "unit": name,
                        "asker": q.asker,
                        "chain": q.chain,
                        "deadline": q.deadline.duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as u64,
                        "ticks": emitted.load(Ordering::Relaxed),
                    });
                    let _ = unit.answer(&q, json!({ "hops": [hop] }).to_string().into_bytes()).await;
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
