use clock::{declaration, handle, now};
use yoke_sdk::plugin::{Event, start};

#[tokio::main]
async fn main() {
    // `clock manifest` prints the Manifest the declaration generates, which is installed beside the binary.
    let args: Vec<String> = std::env::args().collect();
    if args.len() == 2 && args[1] == "manifest" {
        print!("{}", declaration().manifest());
        return;
    }
    let unit = match start(&declaration()).await {
        Ok(unit) => unit,
        Err(err) => {
            eprintln!("clock: {err}");
            std::process::exit(1);
        }
    };
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("the clock listens for SIGTERM");
    loop {
        tokio::select! {
            event = unit.next() => match event {
                None | Some(Event::Ended(_)) => return,
                Some(event) => {
                    if let Err(err) = handle(&unit, &event, now).await {
                        eprintln!("clock: {err}");
                    }
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
