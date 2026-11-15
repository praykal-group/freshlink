# Project Status

**Current milestone:** M13 — Control Tower (Manager) APK + Web Console (next)

| # | Milestone | Status | Date | Commit |
|---|-----------|--------|------|--------|
| M1 | Repository, Architecture and Tooling | Code done, verification not run (D-26) | 2026-11-13 | see `git log --grep m01` |
| M2 | Database Schema, Migrations and Seed | Code done, DB tests not run (no DB credentials) | 2026-11-13 | see `git log --grep m02` |
| M3 | Backend Foundation, Authentication and RBAC | Code + unit tests done (78 pass); e2e with Supabase not run | 2026-11-13 | see `git log --grep m03` |
| M4 | Batches, Files, Storage Path and Traceability | Code + unit tests done (140 pass); DB/S3/phone checks not run | 2026-11-13 | see `git log --grep m04` |
| M5 | ML Service I: Vision Grading and Shelf-Life | Code + tests done (ML 45, backend 162 pass); **no trained models**: vision 503, shelf life on Q10 | 2026-11-13 | see `git log --grep m05` |
| M6 | ML Service II: Demand Forecast and Route Optimiser | Done: forecast MAPE 8.79 % (simulated data), routing feasible & < 10 s, GA 13–15 % behind OR-Tools (synthetic Solomon-style); ML 74 + backend 168 tests pass | 2026-11-13 | see `git log --grep m06` |
| M7 | Orders, FEFO Planning, Trips and Dispatch | Code + tests done (backend 210 pass, incl. a real Socket.IO room test); the seeded-day run through the API is not run (no database) | 2026-11-13 | see `git log --grep m07` |
| M8 | Telemetry Pipeline, Alerts and Notifications | Code + unit tests done (245 pass); live Docker stack: 6 of 7 pipeline steps pass (breach → shelf life 152 ms, single alert, escalation, CRC drop, 500 devices zero loss, tiering). **SRV-02 latency not verified**: measured runs failed (3.5 s / 6.4 s, cold worker, 1 s timestamp resolution); fix written, rerun skipped (no live sensors) | 2026-11-14 | see `git log --grep m08` |
| M9 | Incident Engine, Backup Buyers, Diversion and Rescue | Done on the dev stack: all three incident paths (cold storage / rescue / buyer → MANUAL) and drift recovery end to end with simulated MQTT packets, 26/26 live checks; 282 unit tests. Driver route acceptance + PoD via API not run (no Supabase login) | 2026-11-14 | see `git log --grep m09` |
| M10 | Mobile Foundation: Core, Design System, Auth, Offline Sync | Code + 92 tests pass (sync engine, token refresh, SQLCipher, contrast, text scale 2.0 in EN/HI/MR, wrong-role login); 3 release APKs built and isolation-verified; web console builds and renders. Not run: install on a device, real Supabase/Google/FCM logins (no projects/keys yet) | 2026-11-15 | see `git log --grep m10` |
| M11 | Operator APK | Code + tests done: 142 Flutter tests (wizard online / offline-then-reconnect exactly once / grade 503 queued / resume; every operator screen at text scale 2.0 in EN/HI/MR), backend 285; 3 release APKs built (53–54 MB), isolation and per-flavor permissions verified. Not run: on a phone (NFC, camera, printer, voice, < 60 s per batch), real grading (no model) | 2026-11-15 | see `git log --grep m11` |
| M12 | Driver APK | Code + tests done: 197 Flutter tests (full trip with an offline delivery synced exactly once, alert → ack, diversion accepted offline, speed lock; every driver screen at text scale 2.0 in EN/HI/MR), backend 290; per-ABI release APKs, **driver 32.1 / 27.0 MB (< 40 MB met)**, isolation verified. Not run: on a phone (alert ≤ 10 s, 20-min airplane trip, cold start, 60 fps, battery), real logins | 2026-11-15 | see `git log --grep m12` |
| M13 | Control Tower (Manager) APK + Web Console | Not started | | |
| M14 | AWS Infrastructure and Production Deployment | Not started | | |
| M15 | In-App Updates, GitHub Releases, Final QA and README | Not started | | |

## Blockers
- No vision datasets or shelf-life observations yet, so no YOLOv8 or Cox model exists (D-57). Grading returns 503 until a model is registered.
- No S3 bucket (or MinIO) configured, so uploads cannot be exercised end to end.
- No Supabase dev project yet, so the M3 e2e login checks cannot run.
- No Firebase service account or SMTP server configured, so push and email are skipped in dev (SMS goes to the console provider).

## Next steps
- Apply migrations + seed to a dev Postgres and run the M2 DB checks (TESTING.md).
- Create the Supabase dev project (DEPLOYMENT.md checklist) and run the M3 e2e checks (TESTING.md).
- Run the M4 DB checks (real tamper test as master user, trace page on a phone) once a database and S3 bucket exist.
- Collect/label the vision datasets and shelf-life observations, train, register models, and record measured metrics (ml/training/README.md).
- Place real Solomon C101/R101/RC101 files in `ml/training/data/routing/` and re-run the benchmark (results so far are on synthetic Solomon-style instances).
- Run the seeded day forecast → orders → approved → trips → loaded → started → delivered through the API once a database exists (TESTING.md).
- Re-run `server/test/pipeline/run.ts` to verify SRV-02 (sensor → Influx p95 ≤ 500 ms) with the new ms-accurate measurement (TESTING.md, M8).
- The dev stack now runs in Docker: the deferred M1–M4/M7 database checks can be run against it.
- Create the Supabase dev project, the Google OAuth clients (debug + release SHA-1), the Firebase project and the upload keystore; then run the deferred M10 device checks (TESTING.md).
- Run the deferred M11 phone checks (TESTING.md): NFC / QR / UHF reads, photo size, Bluetooth label, voice in HI/MR, < 60 s per batch.
- Run the deferred M12 phone checks (TESTING.md): alert ≤ 10 s, 20-min airplane-mode trip, cold start, 60 fps, 1-h battery, the full simulated trip with an incident and diversion.
- M15: add `abi` to the release metadata and `GET /app/updates` (two APKs per release, D-146).
- M13: manager APK + web console.
- Run the M9 driver-side steps (accept reroute, PoD at the diversion / handover stop) once a Supabase dev project exists.
