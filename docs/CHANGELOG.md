# Changelog

All notable changes, per milestone (Keep a Changelog style).

## [m06] - 2026-11-13
### Added
- ML: demand forecast (`/v1/forecast/run`): simulated sales world, festival calendar, shared features, LightGBM + LSTM (ONNX) ensemble with intervals, seasonal-naive fallback, Open-Meteo hook, multi-file models in the registry.
- ML: route optimiser (`/v1/routes/optimize`, `/v1/routes/baseline`): haversine/OSRM/Google travel matrices, DVRPTW evaluator, cheapest-insertion seed, DEAP GA with memetic polish, REPLAN with fixed prefixes, OR-Tools baseline.
- Training: `train_forecast.py`, `simulate_sales.py`, `agmarknet.py`, `open_meteo.py`, routing `benchmark.py` + Solomon loader; measured metrics committed.
- Backend: forecast module (`GET /forecasts`, `POST /forecasts/run` + job status), nightly 02:00 IST job in the worker, shared `MlModule`.

## [m05] - 2026-11-13
### Added
- ML service: hash-verified model registry, YOLOv8 ONNX grading (letterbox, decoder, class-wise NMS, grade rule), Cox PH from exported parameters, Q10 fallback, `/v1/vision/grade`, `/v1/shelf-life/predict`, `/v1/models`, error envelope, 45 tests.
- Training scripts (YOLOv8s, Cox PH) writing measured metrics; DATA_SOURCES templates; `scripts/register_model.py`, `scripts/fetch_models.{py,sh}`.
- Backend: grading (grade, dispute, resolve, dispute queue), shelf-life recompute with estimate history, backend Q10 fallback, ML client, `cargo.status` stub.
### Notes
- No trained models are included; grading returns 503 until one is registered.

## [m04] - 2026-11-13
### Added
- Batches: idempotent create with client UUID, list/search/detail, 30-min edit window, edit requests + manager approval, NFC/QR/UHF tags, image attach, storage path + unit recommendation, storage assignment with atomic capacity, receiving, label data, timeline, shelf-life read.
- Hash-chained `trace_events` with verification; signed trace URL; public trace page `/t/:code` and `/t/:code/verify`.
- S3 presigned uploads with signed uploader metadata; `/files/url`.
- `/sync` offline outbox for batch op types, idempotent through `sync_ops`.
- `quality-scans` event stub; cursor pagination helper.
### Changed
- `TRACE_SIGNING_KEY` is required; empty env values count as unset.

## [m03] - 2026-11-13
### Added
- Supabase JWT verification (JWKS) and the guard chain: version gate (426), auth + linked user, flavor/role, driver device, roles, per-user rate limit.
- `/me`, `/me/session`, `/me/language`, `/me/logout`; admin user create/invite/disable/enable/resend via the Supabase admin API.
- Send SMS Hook (Standard Webhooks signature, 5/hour/phone), SmsService with console + httpSMS providers, httpSMS delivery webhook.
- Masters CRUD + `/masters/bundle` with ETag/304, typed remote config, audit log interceptor, Swagger at `/api/docs` (non-prod).
- 78 unit tests.
### Changed
- Seed stores device secrets as bcrypt.

## [m02] - 2026-11-13
### Added
- Prisma schema for all 36 tables (Section 7), init + constraints migrations, `roles.sql` (iccms_migrator / iccms_app, insert-only trace_events), idempotent seed, `PrismaService`, DB readiness check, InfluxDB bucket setup script, DATABASE.md.

## [m01] - 2026-11-13
### Added
- Monorepo skeleton: NestJS `server/` (api + worker, env schema, logging, error filter, health), FastAPI `ml/service` (internal token, health), Flutter `client/` with driver/operator/manager flavors.
- Dev compose (postgres + ml), CI workflow, flavor isolation and secret scan scripts, docs structure.
### Removed
- Vite/React template in `server/`; non-Android Flutter runners.
