use std::path::PathBuf;

use archive::{Archive, declaration, now};
use yoke_sdk::plugin::{Event, start};

fn usage() -> ! {
    eprintln!("archive: archive --store <dir> [--keep-days <n>]");
    std::process::exit(2);
}

#[tokio::main]
async fn main() {
    // `archive manifest` prints the Manifest the declaration generates, which is installed beside it.
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args == ["manifest"] {
        print!("{}", declaration().manifest());
        return;
    }
    let (mut root, mut keep_days) = (None, 90);
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match (a.as_str(), it.next()) {
            ("--store", Some(v)) => root = Some(PathBuf::from(v)),
            ("--keep-days", Some(v)) => keep_days = v.parse().unwrap_or_else(|_| usage()),
            _ => usage(),
        }
    }
    let archive = Archive {
        root: root.unwrap_or_else(|| usage()),
        keep_days,
        now,
    };
    let unit = match start(&declaration()).await {
        Ok(unit) => unit,
        Err(err) => {
            eprintln!("archive: {err}");
            std::process::exit(1);
        }
    };
    // The library beats only once the archive has said how it is, and beginning says it.
    if let Err(err) = archive.begin(&unit).await {
        eprintln!("archive: {err}");
    }
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("the archive listens for SIGTERM");
    loop {
        tokio::select! {
            event = unit.next() => match event {
                None | Some(Event::Ended(_)) => return,
                Some(event) => {
                    if let Err(err) = archive.handle(&unit, &event).await {
                        eprintln!("archive: {err}");
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
