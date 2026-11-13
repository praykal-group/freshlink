# Decisions

Format: ID · date · decision · reason · alternatives. D-01…D-24 come from `PROJECT_IMPLEMENTATION.md` Section 4 (recorded 2026-11-13).

| ID | Decision | Reason |
|----|----------|--------|
| D-01 | Flutter for all 3 APKs + the web Control Tower (Flutter web build of the manager flavor) | One codebase; React console replaced (deviation from synopsis) |
| D-02 | NestJS (Node 24 LTS, TypeScript) modular monolith, two processes: `api` + `worker` | Module separation without microservice overhead; gRPC dropped for internal HTTP |
| D-03 | Python 3.12 FastAPI ML service; ONNX Runtime for YOLOv8/LSTM; LightGBM, lifelines, DEAP, OR-Tools native | No PyTorch in the server image; training runs separately |
| D-04 | AWS RDS PostgreSQL 16 + Prisma; lat/lng doubles, haversine in code (no PostGIS) | Mandated RDS; simple migrations |
| D-05 | Kafka (KRaft, single broker), Mosquitto, InfluxDB 2.7, Redis 7 in Docker on one EC2 | Synopsis architecture at prototype cost; Node consumer replaces Kafka Streams |
| D-06 | Redis + BullMQ for delayed jobs and the rate-limit store | Timers that survive restarts |
| D-07 | One private S3 bucket; presigned PUT uploads | Cheap; no keys on server |
| D-08 | SSM Parameter Store (SecureString) for prod secrets | Free tier; no secrets in Git |
| D-09 | CloudWatch Logs via `awslogs` + alarms → SNS email | Basic monitoring without Prometheus/ELK |
| D-10 | Firebase: FCM push + Crashlytics, 3 Android apps in one project | Required by push alerts and DA-NFR-11 |
| D-11 | SMS adapter: `console` (dev) / self-hosted `httpsms` (prod); email via SMTP (nodemailer) | No DLT provider needed; testable at no cost |
| D-12 | In-app map (flutter_map + cached OSM) + "Navigate" hand-off to Google Maps | Meets DA-FR-04 without building turn-by-turn |
| D-13 | Travel-time adapter: `haversine` (default) / `osrm` / `google` | Works without paid APIs |
| D-14 | Trace + offer pages are server-rendered Handlebars | Fast; no extra frontend |
| D-15 | DB roles `iccms_migrator` (owner) and `iccms_app` (DML; INSERT/SELECT only on `trace_events`) | Enforces W-4 in the database |
| D-16 | One universal APK per flavor (`android-arm,android-arm64`) | Updater picks one asset |
| D-17 | Updates via GitHub Releases synced into `app_releases`; phones call only the backend | Avoids GitHub rate limits on phones |
| D-18 | YOLOv8 (AGPL-3.0) accepted for this academic project; noted in README | Licence transparency |
| D-19 | No ResNet; YOLOv8 does detection + grading | Less work, same coverage |
| D-20 | Model registry = `ml/service/models/registry.json` + versioned files | No MLflow server |
| D-21 | Supabase Auth for identity only; backend verifies JWT via JWKS; app data stays in RDS | User decision; built-in Google + email verification |
| D-22 | Supabase Send SMS Hook → backend → httpSMS → gateway phone | Supabase handles OTPs; delivery via our gateway |
| D-23 | Roles live in our `users` table; public sign-up disabled; admins create users | RBAC stays server-side |
| D-24 | Driver/Operator → phone OTP; Control Tower/web → Google or verified email (+ OTP fallback) | Fits each user group |

## Decisions made during implementation

| ID | Date | Decision | Reason | Alternatives |
|----|------|----------|--------|--------------|
| D-25 | 2026-11-13 | Repo folders keep the names `client/` (= spec `mobile/`) and `server/` (= spec `backend/`). The Vite/React template in `server/` was replaced by NestJS | User decision (keep existing names) | Rename to `mobile/` + `backend/` |
| D-26 | 2026-11-13 | M1 dev compose has only `postgres` + `ml`; Kafka, Redis, Mosquitto, InfluxDB join in the milestones that use them (M3/M8). M1 verification tests were not run | User instruction: develop M1 without testing, ignore those services; Docker is not installed on the dev PC | Full stack in M1 |
| D-27 | 2026-11-13 | Removed the iOS, macOS, Linux and Windows runners from `client/` | Scope is Android APKs + web (Section 2); stale `com.example` ids would break with flavors | Keep and configure them |
| D-28 | 2026-11-13 | `PROJECT_IMPLEMENTATION.md` lives in `docs/`, not the repo root | It was already committed there | Move to root |
| D-29 | 2026-11-13 | M1 flavor routers use `MaterialApp` named routes behind a `FlavorRouter` interface; no router package yet | No new dependency in a skeleton; revisit in M10 | go_router now |
| D-30 | 2026-11-13 | Backend dev deps: TypeScript 5.8, ts-node-dev (watch), jest + ts-jest, eslint + typescript-eslint, pino-pretty (dev logs only) | Standard minimal NestJS toolchain without the Nest CLI | @nestjs/cli + swc |
| D-31 | 2026-11-13 | Prisma **6** (`prisma-client-js`), not Prisma 7 | Prisma 7 requires driver adapters + `prisma.config.ts`; v6 is simpler for this project | Prisma 7, Drizzle |
| D-32 | 2026-11-13 | Initial migration generated offline with `prisma migrate diff --from-empty`; CHECKs/partial index/revoke in a hand-written second migration | No dev DB credentials available during M2; Prisma cannot express those constraints | `prisma migrate dev` against a live DB |
| D-33 | 2026-11-13 | Seed users are `ACTIVE` with `supabase_uid` NULL; M3 links them to Supabase users | Lets M3 create/link Supabase accounts for existing rows | Seed as `INVITED` |
| D-34 | 2026-11-13 | Added deps: `@prisma/client`, `prisma`, `ts-node` (seed runner) | Mandated ORM (D-04); ts-node was only transitively present | tsx |
| D-35 | 2026-11-13 | In-process TTL cache (user lookup, version gate) and in-memory throttler/rate-limit stores instead of Redis | Redis is not in the dev stack yet (D-26); correct for one api process. Must move to Redis before running more than one api instance (M8) | Add Redis now |
| D-36 | 2026-11-13 | `jose` pinned to v5 (dual CJS/ESM) | v6 is ESM-only and cannot be loaded by Jest's CommonJS runtime | jose 6 + ESM Jest config |
| D-37 | 2026-11-13 | `@nestjs/swagger@11`, `@nestjs/throttler@6` | Latest swagger (v12) requires NestJS 12; we are on 11 | Upgrade to NestJS 12 |
| D-38 | 2026-11-13 | httpSMS delivery webhook verified as a HS256 JWT in `Authorization` using `HTTPSMS_WEBHOOK_SECRET` | That is how httpSMS signs webhooks; it is still a shared secret | Custom shared-secret header |
| D-39 | 2026-11-13 | Admin PATCH cannot change a user's phone/email. Email changes go through Supabase secure email change; `/me` detects the new address and resets `email_verified_at` | Keeps identity changes verified by Supabase (AUTH-04) | Admin edits email via admin API |
| D-40 | 2026-11-13 | A driver with no active device registration gets 409 `NO_ACTIVE_SESSION` (distinct from `SESSION_ON_OTHER_DEVICE`) | The app can tell "register this device" from "logged in elsewhere" | Reuse one code |
| D-41 | 2026-11-13 | Added deps: `@supabase/supabase-js` (admin API), `jose` (JWKS), `standardwebhooks` (hook signature), `@nestjs/throttler`, `@nestjs/swagger`, `bcryptjs` (device secrets; pure JS, no native build) | Named in the spec (6.2, 14) | native `bcrypt` |
| D-42 | 2026-11-13 | `GET /files/url?key=` instead of `GET /files/:key/url` | File keys contain `/`, which a path segment cannot carry cleanly | URL-encode the key in the path |
| D-43 | 2026-11-13 | Upload ownership = uploader id in signed S3 object metadata (`x-amz-meta-uploader`), checked with HeadObject on attach/download | Durable, no extra table; the client cannot forge it because it is part of the presigned signature | `uploads` table |
| D-44 | 2026-11-13 | A received batch goes back to `GRADED` (or `REGISTERED` if ungraded) at the receiving site; `REJECTED` on reject | The enum has no "at site, unstored" state; storage then follows the normal path | New status value |
| D-45 | 2026-11-13 | Offline edits (via /sync) check the edit window on device times: batch `captured_at` vs op `capturedAt`; future device times (> 2 min) are refused | FO-NFR-01 keeps original capture times; a forged device clock is possible but every edit is in the audit log with both times | Server time only (would reject legitimate offline edits) |
| D-46 | 2026-11-13 | Receiving photos are stored with width/height 0 | The receive call (Section 6.4) sends only keys | Extend the receive body |
| D-47 | 2026-11-13 | `quality-scans` Kafka producer is a logging stub (`infra/events/EventBus`) with the final publish signature | Kafka joins in M8 (D-26) | Add kafkajs now |
| D-48 | 2026-11-13 | Trace page rendered with `handlebars` directly (template compiled once) and served at `/t/...` outside `/api/v1` | Simple; the label URL stays short | Nest view engine (`hbs`) |
| D-49 | 2026-11-13 | Batch code day = Asia/Kolkata calendar day of `capturedAt`; sequence allocated under `pg_advisory_xact_lock(hashtext(prefix))` | Operators' local day; no sequence collisions under concurrency | DB sequence per site/day |
| D-50 | 2026-11-13 | `/batches/:id/receive` has no current-site ownership check | Receiving operators are at the destination, not the batch's current site; trip/order binding tightens this in M7 | Require the same site |
| D-51 | 2026-11-13 | Empty env values (`KEY=`) are treated as unset | A copied `.env.example` must boot | Require deleting empty lines |
| D-52 | 2026-11-13 | Added deps: `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner` (D-07), `handlebars` (D-14) | Named in the spec | aws-sdk v2 (deprecated) |
| D-53 | 2026-11-13 | Shelf-life requests carry the product reference values (`baseShelfLifeH`, `q10`, `refTempC` = middle of the safe range) | The ML service keeps no product table; the backend owns master data | Copy products into the ML service |
| D-54 | 2026-11-13 | Cox PH is served from exported parameters (beta, means, baseline survival) evaluated with numpy; lifelines is training-only | Same maths as lifelines' prediction, no pandas/scipy in the service image (D-03) | lifelines in the service |
| D-55 | 2026-11-13 | Grade rule details: item area = largest `fresh` box, else the whole image; batch grade = worst of the 3 images; confidence = mean confidence of the images with that grade; nothing detected → A with confidence 0 and `itemDetected:false` | Section 8 defines "% of item area" but not how the item is found | Separate item detector |
| D-56 | 2026-11-13 | Two vision models, `vision_fish` and `vision_produce`, each with its own class list | The spec lists different classes per category | One model with all classes |
| D-57 | 2026-11-13 | No trained models are shipped: vision answers 503 `MODEL_NOT_AVAILABLE` (backend 503 `GRADING_UNAVAILABLE`, app queues); shelf life runs on the Q10 fallback | No datasets prepared yet; never fake grades or metrics | Placeholder model |
| D-58 | 2026-11-13 | The backend has its own Q10 copy used only when the ML service is unreachable (`backend-q10-1`) | The spoilage gate (M9) must always have a value (ML-02) | Fail the recompute |
| D-59 | 2026-11-13 | Until telemetry exists (M8), shelf life assumes the batch was held at the product reference temperature | `batch_exposure` is empty before M8 | Refuse to estimate |
| D-60 | 2026-11-13 | Local ML tests run on Python 3.10 (no 3.12 interpreter on the dev PC); code stays 3.10-compatible; Docker and CI use 3.12. pytest pinned < 9 (9.2.0 crashes at session start) | Keeps the spec's runtime while testing locally | Install 3.12 locally |
| D-61 | 2026-11-13 | Resolving a dispute writes a new MANUAL grade row; `GET /grades/disputes` added for the manager approvals screen | Keeps the model's original output for audit; M13 needs a dispute queue | Overwrite the AUTO row |
| D-62 | 2026-11-13 | Added ML deps: `onnxruntime`, `numpy`, `pillow`, `httpx`, `pydantic` (service); `onnx` (tests only); `ultralytics`, `lifelines`, `pandas` (training only) | Named in Section 8 / D-03 | PyTorch in the service |
| D-63 | 2026-11-13 | Route plan time is minutes from `departAt`; routes end at the depot; `shelfLifeH` on a stop = remaining hours at departure | One internal unit for real (lat/lng) and benchmark (Euclidean) problems | Absolute timestamps inside the solver |
| D-64 | 2026-11-13 | Chromosome = permutation of free stops + (V−1) separator genes; DEAP `cxOrdered`, custom swap mutation, tournament 3, 2 elites; fixed prefixes (REPLAN) are prepended at decode and never move; `mustKeepVehicle` is a 5000-per-violation penalty | Stop order and vehicle split in one genome (Section 8) with standard operators | Two-part genome |
| D-65 | 2026-11-13 | OR-Tools is a dev/training dependency only; `/v1/routes/baseline` answers 503 in the production image | Spec: baseline "for comparison tests only"; keeps the image smaller | Ship OR-Tools |
| D-66 | 2026-11-13 | Indicative haversine speed profile (IST): 28 km/h 08–11 & 17–20, 50 km/h 22–06, 40 km/h otherwise, road factor 1.3 | Works without paid APIs (D-13); replace with measured speeds once trips exist | Constant speed |
| D-67 | 2026-11-13 | Forecast weather: Open-Meteo daily forecast when `OPEN_METEO_URL` and site coordinates are set, else the simulator's weather | Sales are simulated (Section 2), so the simulated weather keeps features consistent | Require Open-Meteo |
| D-68 | 2026-11-13 | Festival flag from a per-year table (Holi, Gudi Padwa, Eid al-Fitr, Ganesh Chaturthi, Diwali; 3-day lead) | Lunar dates need a table; verify against the official holiday list before reporting | Fixed Gregorian holidays |
| D-69 | 2026-11-13 | **Memetic polish:** relocate + 2-opt local search on the GA seed (≤ 25 % of the time limit) and on the final best, inside the same 8 s limit | Measured: the plain GA was 82–93 % behind OR-Tools on 100-customer instances; with the polish 13–15 % | Raise mutation / more generations |
| D-70 | 2026-11-13 | No sales table yet: the backend sends no history and the ML service uses its simulated history; the API already accepts real history | Section 2 simulates sales; real history can be passed later without a contract change | Add a sales table now |
| D-71 | 2026-11-13 | Nightly forecast = a timer in the worker (02:00 IST) until BullMQ repeatable jobs arrive with Redis (M8); `/forecasts/run` jobs kept in memory | Redis is not in the stack yet (D-26, D-35) | Add Redis now |
| D-72 | 2026-11-13 | Forecast model trained in M6 on simulated data is **not registered/activated** in `registry.json`; its metrics are committed (`ml/training/forecast/metrics-m06.json`) | Weights are gitignored and not uploaded; an active entry would only produce "file not found" elsewhere. Register + upload when deploying (M14) | Commit weights |
| D-73 | 2026-11-13 | Forecast features: series scaled by the 30-day mean; LightGBM direct multi-horizon (one row per target day); LSTM 2×(64/32) on a 30-day window, 7 outputs, ONNX opset 13; ensemble weight + 80 % interval from validation | One global model across sites/products; serving shares the exact feature code | Per-series models |
| D-74 | 2026-11-13 | Added deps: service `lightgbm`, `deap`; dev `ortools`; training `torch` (CPU), `lightgbm`, `deap`, `ortools`. ML Docker image installs `libgomp1` (LightGBM runtime) | Named in Section 8 / D-03 | — |
