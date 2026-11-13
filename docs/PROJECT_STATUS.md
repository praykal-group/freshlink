# Project Status

**Current milestone:** M6 — ML Service II: Demand Forecast and Route Optimiser (next)

| # | Milestone | Status | Date | Commit |
|---|-----------|--------|------|--------|
| M1 | Repository, Architecture and Tooling | Code done, verification not run (D-26) | 2026-11-13 | see `git log --grep m01` |
| M2 | Database Schema, Migrations and Seed | Code done, DB tests not run (no DB credentials) | 2026-11-13 | see `git log --grep m02` |
| M3 | Backend Foundation, Authentication and RBAC | Code + unit tests done (78 pass); e2e with Supabase not run | 2026-11-13 | see `git log --grep m03` |
| M4 | Batches, Files, Storage Path and Traceability | Code + unit tests done (140 pass); DB/S3/phone checks not run | 2026-11-13 | see `git log --grep m04` |
| M5 | ML Service I: Vision Grading and Shelf-Life | Code + tests done (ML 45, backend 162 pass); **no trained models**: vision 503, shelf life on Q10 | 2026-11-13 | see `git log --grep m05` |
| M6 | ML Service II: Demand Forecast and Route Optimiser | Not started | | |
| M7 | Orders, FEFO Planning, Trips and Dispatch | Not started | | |
| M8 | Telemetry Pipeline, Alerts and Notifications | Not started | | |
| M9 | Incident Engine, Backup Buyers, Diversion and Rescue | Not started | | |
| M10 | Mobile Foundation: Core, Design System, Auth, Offline Sync | Not started | | |
| M11 | Operator APK | Not started | | |
| M12 | Driver APK | Not started | | |
| M13 | Control Tower (Manager) APK + Web Console | Not started | | |
| M14 | AWS Infrastructure and Production Deployment | Not started | | |
| M15 | In-App Updates, GitHub Releases, Final QA and README | Not started | | |

## Blockers
- No vision datasets or shelf-life observations yet, so no YOLOv8 or Cox model exists (D-57). Grading returns 503 until a model is registered.
- No S3 bucket (or MinIO) configured, so uploads cannot be exercised end to end.
- No Supabase dev project yet, so the M3 e2e login checks cannot run.
- Docker is not installed on the dev PC, so `deploy/docker-compose.dev.yml` has not been run.

## Next steps
- Apply migrations + seed to a dev Postgres and run the M2 DB checks (TESTING.md).
- Create the Supabase dev project (DEPLOYMENT.md checklist) and run the M3 e2e checks (TESTING.md).
- Run the M4 DB checks (real tamper test as master user, trace page on a phone) once a database and S3 bucket exist.
- Collect/label the vision datasets and shelf-life observations, train, register models, and record measured metrics (ml/training/README.md).
- M6: LSTM + LightGBM demand forecast and the genetic DVRPTW route optimiser.
- Run the deferred M1 checks when Docker is available (listed in TESTING.md).
