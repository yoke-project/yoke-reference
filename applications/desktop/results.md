# Desktop bench measurements

2026-11-16T23:37Z on sa-nb089, 6.18.57-1-lts, yoke 0.15.0, Qt 6.4.2.
The documents drew on the offscreen platform of Qt, in a container.
Rest 30 s, flowing 30 s; hw-monitor reads the machine every second. Times are milliseconds on this host's clock, read with a resolution of 1 ms.

| Figure | Value |
| --- | --- |
| Question `hw.snapshot`, asked to answered (mean / worst) | 0.80 / 4.00 ms (n=20) |
| Stream start or stop, asked to acknowledged (mean / worst) | 1.00 / 2.00 ms (n=20) |
| Frame, produced to the QML handler that sets a property (mean / worst) | 0.77 / 2.12 ms (n=60) |
| Application started to hw-monitor granted and running | 137 ms |
| Document started to attached | 66 ms |
| Document started to the snapshot drawn | 68 ms |
| Document started to the first frame drawn | 1012 ms |

| Process | Wakeups at rest | Wakeups flowing | Resident memory |
| --- | ---: | ---: | ---: |
| yoke-core | 13.0/s | 99.6/s | 32.2 MB |
| hw-monitor | 4.8/s | 4.5/s | 5.1 MB |
| the document (`qml`) | 26.0/s | 962.0/s | 55.6 MB |
