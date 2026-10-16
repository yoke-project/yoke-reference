//! A reference Plugin: the example's archive, which keeps the datasets it is given in the storage its
//! Manifest needs.
//!
//! It runs in a container, from an image of its own, and is written against the published Rust plugin
//! library like anyone's. The store's layout is not the archive's to choose: the unit that prepares the
//! store writes it, the unit that migrates it rewrites it, and the archive reads it. Copy it as the start
//! of a Plugin that keeps data.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use yoke_sdk::base::Error;
use yoke_sdk::plugin::{Capability, Command, Declaration, Event, Object, Outcome, Question, Unit};

pub const STORE: &str = "archive.store";
pub const DESCRIBE: &str = "archive.describe";

/// What the archive says about itself: the storage it needs, one command, one question, and the
/// capability that governs each.
pub fn declaration() -> Declaration {
    Declaration {
        id: "com.yoke.station.archive".into(),
        needs: vec!["storage:datasets".into()],
        commands: vec![STORE.into()],
        queries: vec![DESCRIBE.into()],
        capabilities: vec![
            Capability {
                name: "command.store.accept".into(),
                governs: Object::Command(STORE.into()),
            },
            Capability {
                name: "query.describe.answer".into(),
                governs: Object::Query(DESCRIBE.into()),
            },
        ],
        ..Default::default()
    }
}

/// The health grades the archive reports: none of them is a state, only how it is.
pub const GRADE_ARCHIVING: u8 = 0;
pub const GRADE_UNPREPARED: u8 = 60;

/// How a store lays its datasets out, as its `layout` file says.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Layout {
    /// One directory: `datasets/<n>.json`.
    V1,
    /// One directory per day: `datasets/<YYYY-MM-DD>/<n>.json`.
    V2,
}

impl Layout {
    fn name(self) -> &'static str {
        match self {
            Layout::V1 => "v1",
            Layout::V2 => "v2",
        }
    }
}

/// The layout the store at `root` says it has, or what it lacks.
pub fn layout(root: &Path) -> Result<Layout, String> {
    match fs::read_to_string(root.join("layout")) {
        Ok(s) if s.trim() == "v1" => Ok(Layout::V1),
        Ok(s) if s.trim() == "v2" => Ok(Layout::V2),
        Ok(s) => Err(format!(
            "the store at {} is in a layout this archive does not know: {}",
            root.display(),
            s.trim()
        )),
        Err(_) => Err(format!(
            "the store at {} was never prepared: it holds no layout",
            root.display()
        )),
    }
}

/// What the archive does on its Session. A started unit of the library does all three.
pub trait Acts {
    fn ack(
        &self,
        c: &Command,
        outcome: Outcome,
        line: &str,
    ) -> impl Future<Output = Result<(), Error>>;
    fn answer(&self, q: &Question, payload: Vec<u8>) -> impl Future<Output = Result<(), Error>>;
    fn health(&self, grade: u8, line: &str) -> impl Future<Output = Result<(), Error>>;
}

impl Acts for Unit {
    async fn ack(&self, c: &Command, outcome: Outcome, line: &str) -> Result<(), Error> {
        Unit::ack(self, c, outcome, line).await
    }
    async fn answer(&self, q: &Question, payload: Vec<u8>) -> Result<(), Error> {
        Unit::answer(self, q, payload).await
    }
    async fn health(&self, grade: u8, line: &str) -> Result<(), Error> {
        Unit::health(self, grade, line).await
    }
}

/// The archive: its store, how long it keeps datasets, and the clock it reads, in seconds since the
/// epoch.
pub struct Archive<C: Fn() -> u64> {
    pub root: PathBuf,
    pub keep_days: u64,
    pub now: C,
}

impl<C: Fn() -> u64> Archive<C> {
    /// Removes what it no longer keeps, and says how the store is.
    pub async fn begin(&self, u: &impl Acts) -> Result<(), Error> {
        match layout(&self.root) {
            Ok(l) => {
                self.expire();
                u.health(
                    GRADE_ARCHIVING,
                    &format!("archiving in layout {}", l.name()),
                )
                .await
            }
            Err(why) => u.health(GRADE_UNPREPARED, &why).await,
        }
    }

    /// Does what one event of the Session asks.
    pub async fn handle(&self, u: &impl Acts, event: &Event) -> Result<(), Error> {
        match event {
            Event::Command(c) if c.r#type == STORE => match self.store(&c.payload) {
                Ok(at) => u.ack(c, Outcome::Done, &format!("stored as {at}")).await,
                Err(why) => u.ack(c, Outcome::Failed, &why).await,
            },
            Event::Question(q) if q.r#type == DESCRIBE => {
                u.answer(q, self.describe().into_bytes()).await
            }
            // Nothing else is declared, so nothing else is granted, and the Core sends nothing else.
            _ => Ok(()),
        }
    }

    /// Writes one dataset where the layout puts it, whole or not at all, and says where, relative to the
    /// store.
    pub fn store(&self, payload: &[u8]) -> Result<String, String> {
        let layout = layout(&self.root)?;
        let dir = match layout {
            Layout::V1 => PathBuf::from("datasets"),
            Layout::V2 => Path::new("datasets").join(day(self.now() as i64)),
        };
        let full = self.root.join(&dir);
        fs::create_dir_all(&full).map_err(|e| format!("{} cannot be made: {e}", full.display()))?;
        let n = self.datasets().len() + 1;
        let name = dir.join(format!("{n}.json"));
        let target = self.root.join(&name);
        let tmp = self.root.join(&dir).join(format!(".{n}.json.writing"));
        let written = fs::File::create(&tmp)
            .and_then(|mut f| f.write_all(payload).and_then(|_| f.sync_all()))
            .and_then(|_| fs::rename(&tmp, &target));
        if let Err(e) = written {
            let _ = fs::remove_file(&tmp);
            return Err(format!("{} cannot be written: {e}", target.display()));
        }
        self.expire();
        Ok(name.display().to_string())
    }

    /// The store as JSON: its layout, how many datasets it holds, and how long they are kept.
    pub fn describe(&self) -> String {
        let layout = layout(&self.root).map(Layout::name).unwrap_or("none");
        format!(
            "{{\"layout\":\"{layout}\",\"datasets\":{},\"keep_days\":{}}}",
            self.datasets().len(),
            self.keep_days
        )
    }

    fn now(&self) -> u64 {
        (self.now)()
    }

    /// Every dataset the store holds, in either layout.
    fn datasets(&self) -> Vec<PathBuf> {
        fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
            let Ok(entries) = fs::read_dir(dir) else {
                return;
            };
            for e in entries.flatten() {
                let p = e.path();
                if p.is_dir() {
                    walk(&p, out);
                } else if p.extension().is_some_and(|x| x == "json")
                    && !p
                        .file_name()
                        .is_some_and(|n| n.to_string_lossy().starts_with('.'))
                {
                    out.push(p);
                }
            }
        }
        let mut out = Vec::new();
        walk(&self.root.join("datasets"), &mut out);
        out
    }

    /// Removes every dataset written longer ago than the archive keeps them.
    fn expire(&self) {
        let horizon =
            UNIX_EPOCH + Duration::from_secs(self.now().saturating_sub(self.keep_days * 86_400));
        for p in self.datasets() {
            if fs::metadata(&p)
                .and_then(|m| m.modified())
                .is_ok_and(|t| t < horizon)
            {
                let _ = fs::remove_file(&p);
            }
        }
    }
}

/// The time now, in seconds since the epoch.
pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

/// The day an instant falls on, in UTC, as `YYYY-MM-DD`.
pub fn day(seconds: i64) -> String {
    // Civil from days, after Howard Hinnant's algorithm.
    let z = seconds.div_euclid(86_400) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}
