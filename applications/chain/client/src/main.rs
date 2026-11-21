//! client: the chain's client, on a channel of an application instance.
//!
//!   client --instance <name> --channel <channel> ask <unit>
//!   client --instance <name> --channel <channel> stop <unit> <stream>
//!
//! `ask` prints the answer, or `refused <code> <item>: <message>`; `stop` prints `stopped`, or the refusal the
//! same way. Either exits 0 once the channel answered, and 1 where it could not be reached.

use yoke_sdk::interface::{self, Attachment, Options};

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (instance, channel, rest) = match args.as_slice() {
        [a, instance, b, channel, rest @ ..] if a == "--instance" && b == "--channel" => {
            (instance, channel, rest)
        }
        _ => usage(),
    };
    let address = match interface::application(instance, channel, |k| std::env::var(k).ok()) {
        Ok(a) => a,
        Err(e) => fail(&e.to_string()),
    };
    let a = match Attachment::attach(&address.to_string_lossy(), Options::new()).await {
        Ok(a) => a,
        Err(e) => fail(&e.to_string()),
    };
    let said = match rest {
        [op, unit] if op == "ask" => a
            .ask(unit, "chain.ask", b"{}")
            .await
            .map(|b| String::from_utf8_lossy(&b).into_owned()),
        [op, unit, stream] if op == "stop" => a
            .stop_stream(unit, stream)
            .await
            .map(|_| "stopped".to_string()),
        _ => usage(),
    };
    match said {
        Ok(line) => println!("{line}"),
        Err(yoke_sdk::base::Error::Refusal(r)) => {
            let names = r
                .item
                .clone()
                .or(r.subject.as_ref().map(|s| s.identity.clone()))
                .unwrap_or_default();
            println!("refused {} {names}: {}", r.code, r.message);
        }
        Err(e) => fail(&e.to_string()),
    }
    let mut a = a;
    a.close().await;
}

fn usage() -> ! {
    eprintln!(
        "client: usage: client --instance <name> --channel <channel> ask <unit> | stop <unit> <stream>"
    );
    std::process::exit(2);
}

fn fail(why: &str) -> ! {
    eprintln!("client: {why}");
    std::process::exit(1);
}
