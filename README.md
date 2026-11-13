# I-CCMS — AI-Based Logistics Management System for Fishery, Fruits & Vegetables

Tracks every perishable batch from dock or farm to buyer, predicts its remaining shelf life, and diverts cargo before it spoils.

> Skeleton README (M1). The full README (Section 22 of `docs/PROJECT_IMPLEMENTATION.md`) is written in M15.

## Repository
| Folder | What |
|--------|------|
| `server/` | NestJS backend (`api` + `worker`) |
| `client/` | Flutter: Driver, Operator and Control Tower APKs + web console |
| `ml/` | FastAPI ML service + training |
| `deploy/`, `scripts/` | Dev/prod stacks and tooling |
| `docs/` | Spec, status, decisions, testing, logs |

## Quick start (dev)
```bash
cd server && cp .env.example .env && npm install && npm run dev:api
cd client && flutter run --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/dev.json
```

Status: see [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md).
