# Changelog

All notable changes, per milestone (Keep a Changelog style).

## [m10] - 2026-11-15
### Added
- Flutter core: design tokens (colours light/dark, typography with bundled Poppins + Noto Sans/Devanagari, spacing, motion), app theme per flavor, contrast test.
- Shared widgets: buttons, cards with status strip, inputs with unit + voice slot, status/grade chips, AsyncView with skeleton/empty/error, offline banner, stale label.
- ApiClient (headers, single-flight token refresh, GET retry, 426 / revoked-session events, error envelope), secure storage, Supabase auth (phone OTP, Google native/web, email + password, reset, verify email), session with `/me/session` → `/me` and wrong-role sign-out.
- Drift database on SQLCipher; outbox + sync engine (files first, capture order, chunks of 50, backoff, needs-attention) + scheduler; realtime Socket.IO client; FCM + local notifications + Crashlytics from env options.
- Localisation EN / HI / MR; splash, login per flavor, OTP, verify email, settings, sync queue, update-required screens; go_router with session guard; flavor routers.
- Android: per-flavor manifests and icons, release signing from key.properties, backup off, cleartext only in debug; `scripts/build_apk.sh`, `scripts/verify_apk_isolation.sh`, `scripts/gen_launcher_icons.py`; BUILD_GUIDE.md.

## [m09] - 2026-11-14
### Added
- Incident engine (worker, Kafka `alerts` consumer `incident-engine`): classifier, spoilage gate on every shelf-life estimate, DRIVER_FIX with a 15-min re-check, cold storage → rescue → buyer chain, DELAY replans, MANUAL escalation, append-only decision log, one active incident per trip.
- Backup buyers CRUD (`/buyers`), candidate filtering/ranking, diversion offers with one-time SMS links, 10-min timeout chain, public offer page `/offer/:token`.
- Rerouting via ML REPLAN with fixed prefix: diversion / cold-storage stops, two-trip rescue (handover drop + rescue pickup), `route.proposed` + push, driver-response escalation; PoD handover moves batches to the rescue trip (`RESCUED`).
- `/incidents` list/detail/offers, manager override `POST /incidents/:id/action`, `POST /incidents/:id/resolve`.
- Reports: batch compliance (HTML/CSV/JSON from InfluxDB 1-min), FSMA 204-style traceability CSV, emissions (JSON/CSV), reefer health; weekly reefer-health job (SYN-17).
- Migration `20261114010000_incident_rescue_trip`; live test `server/test/incidents/run.ts`.
### Changed
- Accepting a route cancels orders that are on no live route any more; alerts can SMS managers and be resolved by the system.
- Unit tests pin `TELEMETRY_TIME_SCALE=1` (Jest setup).

## [m08] - 2026-11-14
### Added
- Dev stack: Kafka 3.8.1 (KRaft), Redis 7.4, Mosquitto 2.0.20 (password file + per-device ACL), InfluxDB 2.7 (30-day `telemetry` bucket).
- Simulator `simulator/sim.py` with 7 scenarios and the 40-byte binary format (`simulator/binary_format.md`, CRC-32, `seq`).
- Worker: MQTT → Kafka bridge; consumer groups `telemetry-writer` (InfluxDB), `threshold-processor` (persistence window, breach → shelf-life recompute, alerts) and `exposure-aggregator`; BullMQ escalation, device offline, exposure flush, shelf-life refresh, telemetry tiering (S3 / local) and nightly forecast schedules.
- Alerts module: `GET /alerts`, `POST /alerts/:id/ack`, `POST /alerts/:id/resolve`; Kafka `alerts` events; escalation to managers after the ack timeout; `SMS_GATEWAY_DOWN` alert.
- Notifications: in-app, FCM push, SMS fallback, email to verified addresses only.
- `GET /trips/:id/telemetry`; last reading in `cargo.status`; `/sync` `GPS_POINTS` and `ALERT_ACK`.
- Socket.IO Redis adapter (API) and Redis emitter (worker); `vehicle.position`, `alert.updated` events.
- Live pipeline test `server/test/pipeline/run.ts`; `TELEMETRY_TIME_SCALE` for time-scaled runs.
### Changed
- Rate limiting stored in Redis; EventBus publishes to Kafka when configured.
- Nightly forecast runs as a BullMQ cron instead of a timer; SOS goes through the alerts module.
- Dev Postgres on host port 5433; backend URLs use `127.0.0.1`.

## [m07] - 2026-11-13
### Added
- FEFO planner (`POST /planning/run`) and route building (`POST /planning/routes`) creating trips, stops and route plan v1.
- Orders: list, draft edit, manager approval with FEFO allocation, CSV import; ERP `POST /integrations/orders` (API key + body HMAC, idempotent) and ADMIN key management.
- Trips: assign, operator load with wrong-batch check, pre-trip check, start with device/vehicle binding, incidents and SOS (alert + SMS), route accept/decline, arrive, PoD per batch, automatic completion with CO₂.
- Socket.IO gateway `/rt` with user/trip/manager rooms; `cargo.status` now emitted to trip rooms.
- `/sync` op types LOAD, TRIP_EVENT, POD, ROUTE_ACCEPT.

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
