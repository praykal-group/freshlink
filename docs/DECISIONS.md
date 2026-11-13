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
