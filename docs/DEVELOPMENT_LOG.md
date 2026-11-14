# Development Log

## M1 — Repository, Architecture and Tooling (2026-11-13)

**Implemented**
- Root: `.gitignore` (covers all Section 19.5 never-commit items), `.editorconfig`, `README.md` skeleton, `release/versions.json`.
- `server/` (NestJS, replaces the Vite/React template): `api` (`src/main.ts`) and `worker` (`src/worker.ts`) entry points, zod env schema with fail-fast (refuses `SMS_PROVIDER=console` in production), typed `AppConfig`, nestjs-pino logging with requestId + redaction, global error envelope filter (incl. Prisma P2002/P2025 mapping), `/api/v1/health` and `/api/v1/health/ready` (checks ML).
- `ml/service/`: FastAPI app with `X-Internal-Token` middleware (constant-time compare) and `/health`; Dockerfile; `models/registry.json`; pytest for 200/401.
- `client/` (Flutter): package renamed `iccms`, Android namespace `in.iccms.app`, 3 product flavors (`in.iccms.driver|operator|manager`) with app names and per-flavor permission manifests; `bootstrap.dart`, `main_{driver,operator,manager}.dart`, `apps/<flavor>/{router,module_tag}.dart`, `FlavorRouter` interface in `core/config`, folder skeleton for `core/` and `shared/`; widget test per flavor; `env/dev.json`.
- `deploy/docker-compose.dev.yml` (postgres + ml), `scripts/check_flavor_isolation.sh`, `scripts/secret_scan.sh`, `.github/workflows/ci.yml`.
- Docs from Section 18 created; DECISIONS D-01…D-30.

**Removed:** `server/` React template; `client/{ios,macos,linux,windows}`; `client/lib/main.dart`.

**Tests:** not run by user instruction. Build/analyze/scripts results are in TESTING.md.

**Limitations / pending:** Kafka, Redis, Mosquitto, InfluxDB not in the dev stack yet (D-26). Theme is a seed-colour placeholder until M10. No launcher icons per flavor yet (M10).

**Repro**
```bash
cd server && cp .env.example .env && npm install && npm run dev:api
cd ml/service && pip install -r requirements.txt && ML_INTERNAL_TOKEN=dev-internal-token uvicorn app.main:app --port 8000
cd client && flutter run --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/dev.json
```

## M2 — Database Schema, Migrations and Seed (2026-11-13)

**Implemented**
- `server/prisma/schema.prisma`: 36 tables, 40 enums, indexes (incl. DESC and GIN) per Section 7.
- Migrations: `20261113000000_init` (generated offline), `20261113000100_constraints` (CHECKs, partial unique active-device index, trace_events revoke).
- `prisma/sql/roles.sql`: idempotent role creation, default privileges, insert-only `trace_events` for `iccms_app`.
- `prisma/seed.ts`: idempotent upserts for sites, storage units, products, users, vehicles, IoT devices, buyers, app_config.
- `src/infra/prisma/{prisma.service,prisma.module}.ts`, wired into api + worker; `/health/ready` now checks the DB; `DATABASE_URL` required.
- `deploy/influx/setup.sh`; npm scripts `db:migrate|deploy|reset|seed`.

**Files created:** `server/prisma/**`, `server/src/infra/prisma/*`, `deploy/influx/setup.sh`. **Modified:** `server/package.json`, `server/src/{app.module,worker.module}.ts`, `server/src/config/env.schema.ts`, `server/src/modules/health/health.service.ts`, docs.

**Tests:** static checks only; DB checks deferred (TESTING.md).

**Limitations / pending:** product limits are indicative values; migrations not yet applied to any database.

**Repro**
```bash
psql "$MASTER_URL" -v app_password=... -v migrator_password=... -f server/prisma/sql/roles.sql
cd server && DATABASE_URL=postgresql://iccms_migrator:...@localhost:5432/iccms npm run db:deploy && npm run db:seed
```

## M3 — Backend Foundation, Authentication and RBAC (2026-11-13)

**Implemented**
- `common/auth/`: `JwtVerifier` (jose, injected key source), `AuthUser`/`AppRequest`, decorators (`@Public`, `@Roles`, `@AllowUnverifiedEmail`, `@SkipDeviceCheck`, `@CurrentUser`), `Ownership` helpers.
- `common/guards/`: `VersionGateGuard`, `SupabaseAuthGuard`, `FlavorRoleGuard`, `DeviceGuard`, `RolesGuard`, `UserThrottlerGuard`, registered in that order.
- `common/interceptors/audit.interceptor.ts`; `common/cache/ttl-cache.ts` (TTL cache + rate limiter, D-35).
- `infra/supabase/supabase-admin.service.ts` (create phone user, invite email, ban/unban, email-confirmed lookup).
- Modules: `auth` (/me*), `users` (admin), `sms` (console + httpSMS), `hooks` (Supabase Send SMS Hook, httpSMS webhook), `masters` (CRUD + bundle/ETag), `remote-config` (typed keys).
- `main.ts`: raw body for hook signatures, Swagger (non-prod), trust proxy. Env: `SUPABASE_URL` required; httpSMS settings validated together.

**Tests:** 78 unit tests pass (TESTING.md). e2e deferred.

**Limitations / pending:** caches and rate limits are in-process (D-35); no Supabase project yet; the "SMS gateway down" alert is a log line until M8; API not booted (no DB credentials).

**Repro**
```bash
cd server && npm test
```

## M4 — Batches, Files, Storage Path and Traceability (2026-11-13)

**Implemented**
- `common/hashing/hashing.ts` (canonical JSON, record hash, trace hash, chain verify, trace signature); `common/pagination.ts`.
- `modules/trace` (append inside the caller's transaction with a batch row lock; verify; signed URL).
- `infra/s3/s3.service.ts`, `modules/files` (presign with signed uploader metadata, attach checks, download URL).
- `modules/storage` (path rules, unit ranking, atomic reserve/release/resize).
- `modules/batches` (create, list, detail, edit window, edit requests, tags, images, storage, receive, label, timeline, shelf life).
- `modules/sync` (ordered, idempotent outbox, role checks per op type).
- `modules/public-pages` + `views/trace.hbs` (served at `/t`, CSP, no PII).
- `infra/events/event-bus.service.ts` (quality-scans stub).

**Files modified:** `src/app.module.ts`, `src/main.ts` (prefix exclude for `/t`), `src/config/env.schema.ts`, `.env.example`, docs.

**Tests:** 140 unit tests pass (TESTING.md). DB/S3/phone checks deferred.

**Limitations / pending:** receive has no trip binding yet (D-50); receiving photos have no dimensions (D-46); events are not sent to Kafka until M8; temperature summary on the trace page is a placeholder until M8.

**Repro**
```bash
cd server && npm test
```

## M5 — ML Service I: Vision Grading and Shelf-Life (2026-11-13)

**Implemented**
- `ml/service/app/core/`: `registry.py` (active versions, sha256 check), `vision.py` (letterbox, YOLOv8 decode, NMS, grade rule, ONNX wrapper), `shelf_life.py` (Q10, Weibull curve, Cox from parameters), `images.py` (parallel, size-capped photo download), `state.py`, `errors.py`; `schemas/api.py`; routers `vision.py`, `shelf_life.py`; `main.py` (lifespan model loading, error handlers, `/v1/models`).
- `ml/training/`: `vision/train_yolo.py` + `data_{fish,produce}.yaml`, `shelf_life/train_cox.py`, `requirements-train.txt`, README, DATA_SOURCES templates.
- `scripts/register_model.py`, `scripts/fetch_models.py` + `.sh`.
- Backend: `infra/ml/ml-client.service.ts`; `modules/shelf-life` (service, Q10 copy, cargo-status stub); `modules/grading` (service, controller, photo selection); `BatchesService.loadForUser` made public; `FilesService.internalUrl`.

**Tests:** ML 45 pass; backend 162 pass (TESTING.md). Model metrics not measured (no data).

**Limitations / pending:** no datasets → no models (D-57); exposure-based shelf life waits for telemetry (M8, D-59); `cargo.status` is a log line until the realtime gateway (M7).

**Repro**
```bash
cd ml/service && python -m venv .venv && .venv/Scripts/pip install -r requirements.txt -r requirements-dev.txt && .venv/Scripts/python -m pytest -q
cd server && npm test
```

## M6 — ML Service II: Demand Forecast and Route Optimiser (2026-11-13)

**Implemented**
- `ml/service/app/core/routing/`: `travel.py`, `problem.py`, `ga.py` (DEAP GA + cheapest insertion + local search), `baseline.py` (OR-Tools); `schemas/routing.py`, `routers/routing.py`.
- `ml/service/app/core/forecast/`: `calendar.py`, `simulate.py`, `features.py`, `model.py`, `weather.py`; `schemas/forecast.py`, `routers/forecast.py`; registry supports multi-file models.
- `ml/training/forecast/`: `train_forecast.py`, `simulate_sales.py`, `agmarknet.py`, `open_meteo.py`; `ml/training/routing/`: `solomon.py`, `benchmark.py`; committed `metrics-m06.json` for both.
- `scripts/register_model.py` and `fetch_models.py` handle the forecast directory model.
- Backend: `infra/ml/ml.module.ts`; `modules/forecast` (service, controller); `workers/jobs/forecast.job.ts`; worker module wiring.

**Bugs found and fixed:** plain GA far behind OR-Tools on 100-customer instances → memetic polish (D-69); a test parsed `...Z` timestamps with Python 3.10 `fromisoformat` (test fixed); Dockerfile needed `libgomp1` for LightGBM.

**Tests:** ML 74 pass; backend 168 pass (TESTING.md).

**Limitations / pending:** Solomon results are on synthetic instances; forecast metrics are on simulated data; the trained forecast model is not registered (D-72); nightly job is a timer until BullMQ (D-71).

**Repro**
```bash
ml/service/.venv/Scripts/python ml/training/forecast/train_forecast.py --out ml/training/forecast/out
ml/service/.venv/Scripts/python ml/training/routing/benchmark.py --out ml/training/routing/out
cd ml/service && .venv/Scripts/python -m pytest -q
```

## M7 — Orders, FEFO Planning, Trips and Dispatch (2026-11-13)

**Implemented**
- `common/{geo,ist,codes}.ts` (haversine, IST days, locked code sequences).
- `modules/planning` (`fefo.ts`, service: run + buildRoutes, controller).
- `modules/orders` (service, controller incl. CSV import, `csv.ts`), `modules/integrations` (ERP endpoint, `signature.ts`, admin keys).
- `modules/trips` (`trip-rules.ts`, service, controller, DTOs), `modules/pod/pod.service.ts`.
- `modules/realtime` (gateway, service, emitter-only module for the worker); `CargoStatusNotifier` emits to trip rooms.
- `modules/sync`: new op types.

**Bugs found and fixed during the milestone:** ERP endpoint validated the body before authenticating (would return 400 instead of 401) → manual validation after the HMAC check; lint caught an unused destructure in the admin key listing.

**Tests:** 210 pass (TESTING.md).

**Limitations / pending:** SOS/alerts move into the alerts module in M8; incident handling in M9; realtime from the worker and telemetry wait for M8; end-to-end day run needs a database.

**Repro**
```bash
cd server && npm test
```

## M8 — Telemetry Pipeline, Alerts and Notifications (2026-11-14)

**Implemented**
- `deploy/docker-compose.dev.yml`: Kafka (KRaft), Redis, Mosquitto (`deploy/mosquitto/`: config, ACL, password-file entrypoint), InfluxDB; Postgres moved to host port 5433.
- `simulator/`: `sim.py`, 7 scenarios, `binary_format.md`.
- `infra/{redis,kafka,influx,queue}`; `common/time-scale.ts`; Redis throttler storage.
- `modules/telemetry` (packet codec, pure threshold engine, device context cache, trip series), `modules/alerts`, `modules/notifications` (push, mail, fallback chain); SMS gateway-down listener.
- Worker: `consumers/{mqtt-bridge,telemetry-writer,threshold-processor,exposure-aggregator}`, `jobs/{maintenance.worker,tiering}`; nightly forecast now a BullMQ cron (`forecast.job.ts` removed).
- Realtime: Redis adapter (API) + emitter (worker). Trips: telemetry endpoint, last reading in cargo status, SOS through alerts. Sync: `GPS_POINTS`, `ALERT_ACK`.
- `server/test/pipeline/run.ts`: live-stack pipeline test.

**Bugs found and fixed during the milestone**
- `minutesToMs` loaded the full env (process exit in unit tests) → reads `TELEMETRY_TIME_SCALE` directly.
- Throttler async options rejected `extraProviders` → inject `REDIS`.
- Duplicate `type` key in the Kafka alert payload; `Notice.data` type mismatch.
- First `compose up` was interrupted during `initdb`, leaving an empty, corrupt Postgres volume → removed that fresh volume and re-initialised.
- Worker crashed on first produce ("does not host this topic-partition", auto-create off) → topics are created before the first produce/subscribe.
- Load test: MQTT `connack timeout` after ~235 connections through `localhost` (::1 on Windows, Docker Desktop IPv6 forwarding) → `127.0.0.1` everywhere (D-96).
- SRV-02 measurement used whole-second packet time and a cold worker → producer warm-up at start, ms-accurate bridge → Influx metric, warm-up round in the test (D-99). **Not re-run.**

**Tests:** 245 unit tests pass; live pipeline run 2: 6 of 7 steps pass, latency not verified (TESTING.md, M8).

**Limitations / pending:** SRV-02 rerun; push/email untested without Firebase/SMTP; two-instance realtime not tested; simulator scenarios not run against the stack.

**Repro**
```bash
cd deploy && MOSQ_DEVICE_COUNT=500 docker compose -p iccms-dev -f docker-compose.dev.yml up -d
cd server && npx prisma migrate deploy && npx prisma db seed
cd server && npm run build && node --env-file=.env dist/worker.js   # .env with TELEMETRY_TIME_SCALE=60
cd server && node --env-file=.env -r ts-node/register/transpile-only test/pipeline/run.ts
```
