# Scan Demo (Rust + SQLite + Qt5 QML)

Simple demo: input a barcode in the UI; backend mocks an external call, stores to SQLite, and returns shift info and result.

## Features
- Rust backend using Axum + rusqlite (with r2d2 pool)
- SQLite persistence
- Mocked external processing
- Qt5 QML UI (uses XMLHttpRequest to call local backend)
- GitHub Actions cross-compile for ARMv7 (Cortex-A7)

## Run locally (Windows)
1. Install Rust and Qt5 tools (for UI, you only need qmlscene to preview):
   - Backend: `cargo run`
   - UI: open `ui/main.qml` with `qmlscene` (or use Qt Creator)
2. Backend will listen on `127.0.0.1:8080`.

## API
- GET `/api/settings` → `{ group, shift, plan_target, realtime_count }`
- POST `/api/process_barcode` with `{ barcode }` → `{ success, message, group, shift, plan_target, realtime_count, barcode, timestamp }`

## Cross-compile in GitHub
Push to `main`/`master`. Workflow builds ARMv7 and uploads artifacts.
- Artifact contains `scan_demo`, `ui/`, `scripts/`.

## Deploy on device (Cortex-A7, Linux 5.15)
1. Copy artifact to device, e.g. `/opt/scan-demo/`.
2. Ensure Qt5 runtime is present (qmlscene) and `libsqlite3` is available.
3. Run:
```sh
chmod +x scripts/run_device.sh
./scripts/run_device.sh
```

## Notes
- Database file defaults to `scan_demo.sqlite` in working dir. Override with `SCAN_DEMO_DB` env.
- Mock success rule: even-length barcode not ending with `9`.
