use std::time::Duration;

use ask::{Asks, WAIT_MS, declaration, expire, handle, now_ms};
use yoke_sdk::plugin::{Event, start};

#[tokio::main]
async fn main() {
    // `ask manifest` prints the Manifest the declaration generates, which is installed beside the binary.
    let args: Vec<String> = std::env::args().collect();
    if args.len() == 2 && args[1] == "manifest" {
        print!("{}", declaration().manifest());
        return;
    }
    let unit = match start(&declaration()).await {
        Ok(unit) => unit,
        Err(err) => {
            eprintln!("ask: {err}");
            std::process::exit(1);
        }
    };
    if let Err(err) = unit.health(0, "nothing asked").await {
        eprintln!("ask: {err}");
    }
    let mut asks = Asks::new(WAIT_MS);
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("ask listens for SIGTERM");
    loop {
        // The Plugin sleeps until an event comes, or until the first open ask runs out; with no ask open
        // it has no deadline at all.
        let deadline = asks.deadline();
        let runs_out = async {
            match deadline {
                Some(at) => {
                    tokio::time::sleep(Duration::from_millis(at.saturating_sub(now_ms()))).await
                }
                None => std::future::pending().await,
            }
        };
        tokio::select! {
            event = unit.next() => match event {
                None | Some(Event::Ended(_)) => return,
                Some(event) => {
                    if let Err(err) = handle(&unit, &mut asks, &event, now_ms()).await {
                        eprintln!("ask: {err}");
                    }
                }
            },
            () = runs_out => {
                if let Err(err) = expire(&unit, &mut asks, now_ms()).await {
                    eprintln!("ask: {err}");
                }
            },
            _ = term.recv() => {
                // Asked to stop: close the Session in order, and leave once it has ended.
                let _ = unit.close().await;
                while let Some(event) = unit.next().await {
                    if matches!(event, Event::Ended(_)) {
                        break;
                    }
                }
                return;
            }
        }
    }
}
