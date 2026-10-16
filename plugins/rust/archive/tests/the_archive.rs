use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

use archive::{Acts, Archive, declaration};
use yoke_sdk::base::Error;
use yoke_sdk::plugin::{Command, Event, Object, Outcome, Question};

/// What the archive did on a Session that records it.
#[derive(Debug, PartialEq)]
enum Act {
    Acked {
        id: String,
        done: bool,
        line: String,
    },
    Answered {
        id: String,
        payload: String,
    },
    Health {
        grade: u8,
        line: String,
    },
}

#[derive(Default)]
struct Session(Mutex<Vec<Act>>);

impl Acts for Session {
    async fn ack(&self, c: &Command, outcome: Outcome, line: &str) -> Result<(), Error> {
        let done = matches!(outcome, Outcome::Done);
        self.0.lock().unwrap().push(Act::Acked {
            id: c.id.clone(),
            done,
            line: line.into(),
        });
        Ok(())
    }
    async fn answer(&self, q: &Question, payload: Vec<u8>) -> Result<(), Error> {
        let payload = String::from_utf8(payload).unwrap();
        self.0.lock().unwrap().push(Act::Answered {
            id: q.id.clone(),
            payload,
        });
        Ok(())
    }
    async fn health(&self, grade: u8, line: &str) -> Result<(), Error> {
        self.0.lock().unwrap().push(Act::Health {
            grade,
            line: line.into(),
        });
        Ok(())
    }
}

/// A store of the case's own, in the layout given, or in none.
fn store(name: &str, layout: Option<&str>) -> PathBuf {
    let root = std::env::temp_dir().join(format!("archive-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(&root).unwrap();
    if let Some(l) = layout {
        fs::write(root.join("layout"), l).unwrap();
    }
    root
}

/// 2026-10-16 at noon, UTC.
const DAY: u64 = 1_792_152_000;

fn archive(root: &Path, keep_days: u64) -> Archive<impl Fn() -> u64> {
    Archive {
        root: root.to_path_buf(),
        keep_days,
        now: || DAY,
    }
}

fn command(id: &str, payload: &str) -> Event {
    Event::Command(Command {
        id: id.into(),
        r#type: "archive.store".into(),
        payload: payload.as_bytes().to_vec(),
    })
}

// std: yoke-reference:archive.01
#[test]
fn the_manifest_is_the_one_its_declaration_generates() {
    let committed =
        fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("manifest.yaml")).unwrap();
    assert_eq!(
        committed,
        declaration().manifest(),
        "run `cargo run -q -- manifest > manifest.yaml`"
    );
    let d = declaration();
    assert_eq!(d.id, "com.yoke.station.archive");
    assert_eq!(d.needs, vec!["storage:datasets".to_string()]);
    assert_eq!(d.commands, vec!["archive.store".to_string()]);
    assert_eq!(d.queries, vec!["archive.describe".to_string()]);
    let governed: Vec<String> = d
        .capabilities
        .iter()
        .map(|c| match &c.governs {
            Object::Command(s) | Object::Query(s) => s.clone(),
            other => format!("{other:?}"),
        })
        .collect();
    assert_eq!(governed, vec!["archive.store", "archive.describe"]);
}

// std: yoke-reference:archive.02
#[tokio::test]
async fn a_dataset_is_stored_in_the_layout_the_store_has() {
    let (one, two) = (store("v1", Some("v1\n")), store("v2", Some("v2\n")));
    let s = Session::default();
    archive(&one, 90)
        .handle(&s, &command("c-1", "{\"scan\":1}"))
        .await
        .unwrap();
    archive(&one, 90)
        .handle(&s, &command("c-2", "{\"scan\":2}"))
        .await
        .unwrap();
    archive(&two, 90)
        .handle(&s, &command("c-3", "{\"scan\":3}"))
        .await
        .unwrap();
    assert_eq!(
        *s.0.lock().unwrap(),
        vec![
            Act::Acked {
                id: "c-1".into(),
                done: true,
                line: "stored as datasets/1.json".into()
            },
            Act::Acked {
                id: "c-2".into(),
                done: true,
                line: "stored as datasets/2.json".into()
            },
            Act::Acked {
                id: "c-3".into(),
                done: true,
                line: "stored as datasets/2026-10-16/1.json".into()
            },
        ]
    );
    assert_eq!(
        fs::read_to_string(one.join("datasets/1.json")).unwrap(),
        "{\"scan\":1}"
    );
    assert_eq!(
        fs::read_to_string(one.join("datasets/2.json")).unwrap(),
        "{\"scan\":2}"
    );
    assert_eq!(
        fs::read_to_string(two.join("datasets/2026-10-16/1.json")).unwrap(),
        "{\"scan\":3}"
    );
}

// std: yoke-reference:archive.03
#[tokio::test]
async fn a_store_nobody_prepared_is_refused_and_said() {
    for (name, layout, says) in [
        ("none", None, "holds no layout"),
        ("v9", Some("v9"), "does not know: v9"),
    ] {
        let root = store(name, layout);
        let s = Session::default();
        let a = archive(&root, 90);
        a.begin(&s).await.unwrap();
        a.handle(&s, &command("c-1", "{}")).await.unwrap();
        let acts = s.0.lock().unwrap();
        match (&acts[0], &acts[1]) {
            (
                Act::Health {
                    grade: 60,
                    line: health,
                },
                Act::Acked {
                    done: false, line, ..
                },
            ) => {
                assert!(health.contains(says), "{name}: the health said {health}");
                assert_eq!(health, line, "{name}: the failure said something else");
            }
            other => panic!("{name}: the archive did {other:?}"),
        }
        assert!(
            !root.join("datasets").exists(),
            "{name}: something was written"
        );
    }
}

// std: yoke-reference:archive.04
#[tokio::test]
async fn datasets_older_than_it_keeps_are_removed_and_the_store_described() {
    let root = store("expire", Some("v1"));
    fs::create_dir_all(root.join("datasets")).unwrap();
    let (old, new) = (root.join("datasets/1.json"), root.join("datasets/2.json"));
    fs::write(&old, "{}").unwrap();
    fs::write(&new, "{}").unwrap();
    let at = |seconds: u64| SystemTime::UNIX_EPOCH + Duration::from_secs(seconds);
    fs::File::options()
        .write(true)
        .open(&old)
        .unwrap()
        .set_modified(at(DAY - 10 * 86_400))
        .unwrap();
    fs::File::options()
        .write(true)
        .open(&new)
        .unwrap()
        .set_modified(at(DAY - 3_600))
        .unwrap();
    let s = Session::default();
    let a = archive(&root, 7);
    a.begin(&s).await.unwrap();
    a.handle(
        &s,
        &Event::Question(Question {
            id: "q-1".into(),
            r#type: "archive.describe".into(),
            payload: vec![],
        }),
    )
    .await
    .unwrap();
    assert!(
        !old.exists() && new.exists(),
        "the old dataset stayed, or today's went"
    );
    assert_eq!(
        s.0.lock().unwrap().last(),
        Some(&Act::Answered {
            id: "q-1".into(),
            payload: "{\"layout\":\"v1\",\"datasets\":1,\"keep_days\":7}".into()
        })
    );
}
