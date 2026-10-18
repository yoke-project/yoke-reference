use std::io::Write;

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let parsed = match terminal::parse(&args, |name| std::env::var(name).ok()) {
        Ok(parsed) => parsed,
        Err(why) => {
            eprintln!("terminal: {why}\n{}", terminal::USAGE);
            std::process::exit(2);
        }
    };
    let mut out = std::io::stdout();
    let status = terminal::run(&parsed, &mut out).await;
    let _ = out.flush();
    std::process::exit(status);
}
