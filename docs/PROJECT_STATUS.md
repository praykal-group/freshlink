# Project Status

**Current milestone:** M2 — Database Schema, Migrations and Seed (next)

| # | Milestone | Status | Date | Commit |
|---|-----------|--------|------|--------|
| M1 | Repository, Architecture and Tooling | Code done, verification not run (D-26) | 2026-11-13 | see `git log --grep m01` |
| M2 | Database Schema, Migrations and Seed | Not started | | |
| M3 | Backend Foundation, Authentication and RBAC | Not started | | |
| M4 | Batches, Files, Storage Path and Traceability | Not started | | |
| M5 | ML Service I: Vision Grading and Shelf-Life | Not started | | |
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
- Docker is not installed on the dev PC, so `deploy/docker-compose.dev.yml` has not been run.

## Next steps
- M2: Prisma schema (Section 7), roles.sql, seed, DATABASE.md.
- Run the deferred M1 checks when Docker is available (listed in TESTING.md).
