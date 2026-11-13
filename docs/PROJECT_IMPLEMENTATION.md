# PROJECT_IMPLEMENTATION.md
## I-CCMS — AI-Based Logistics Management System for Fishery, Fruits & Vegetables

> **Primary instruction file for Claude Code.** Read this file fully once. In later sessions, read only
> `docs/PROJECT_STATUS.md`, the last entry of `docs/DEVELOPMENT_LOG.md`, and the section of this file for the
> current milestone. This file is the source of truth. If something here conflicts with a doc in `docs/`,
> this file wins, unless `docs/DECISIONS.md` records a later decision that changes it.

---

## 0. Working Rules for Claude Code

1. Build **one milestone at a time, in order** (Section 20). Do not start milestone N+1 until milestone N meets its completion criteria.
2. A milestone is complete only when: code is done, its tests pass, the docs are updated, and the Git commit is made.
3. **Commit after every completed milestone without asking.** Follow the Git rules in Section 19 (no AI author or co-author lines).
4. Never claim something works unless you ran it and saw it work. Record failures in `docs/TESTING.md` and `docs/PROJECT_STATUS.md`.
5. If you have to deviate from this file, write the reason in `docs/DECISIONS.md` (one short entry) and continue. Ask the user only when a requirement truly cannot be decided.
6. Token discipline (Section 21): read before editing, make focused edits, don't re-read unchanged files, and don't regenerate whole files.
7. Never hardcode secrets. Use the env files and SSM described in Sections 14 and 17.

---

## 1. Project Summary

Perishable goods (fish, fruits, vegetables) spoil fast when the temperature, timing or handling goes wrong. I-CCMS tracks every
**batch** from the dock or farm to the buyer. It keeps predicting the batch's remaining shelf life, and it diverts the cargo before it spoils.

### 1.1 End-to-end workflow (the core flow every module serves)

| # | Step | What happens | Main modules |
|---|------|--------------|--------------|
| 1 | Register | Field operator registers the batch (catch/harvest data) and tags the crate (NFC/QR/UHF RFID) | Operator App, Batches, Trace |
| 2 | Grade | 3 guided photos → YOLOv8 gives Grade A/B/C + defects | Operator App, ML Vision |
| 3 | Store | System decides: blast chiller (fish, non-climacteric) or ripening/ethylene-control chamber (climacteric) | Batches, Storage |
| 4 | Plan | 7-day demand forecast → FEFO draft dispatch orders → manager approves → GA route optimiser builds trips | ML Forecast, Planning, ML Routing, Manager App |
| 5 | Transit | IoT pod sends telemetry every 60 s → MQTT → Kafka → InfluxDB; threshold checks; Cox model updates shelf life | Simulator, Telemetry, Worker, ML Shelf-life |
| 6 | Decide | If remaining shelf life < remaining ETA + margin → incident engine picks: driver fix / divert (buyer or cold storage) / rescue pickup | Incidents, Diversions, Routing, Driver App |
| 7 | Deliver | Receiver scan + signature + photo = Proof-of-Delivery | Driver App, PoD |
| 8 | Trace | Hash-chained, tamper-evident journey log; public QR trace page | Trace, Public pages |

### 1.2 Users and dashboards

| Role | Client | Purpose |
|------|--------|---------|
| `DRIVER` | **Driver APK** | Trips, navigation, cargo status, alerts, reroutes, incidents, SOS, PoD |
| `OPERATOR` | **Operator APK** | Batch registration, tagging, grading photos, storage, labels, receiving, dispatch loading |
| `MANAGER` | **Control Tower APK** + same code as **web console** | Live monitoring, alerts/incidents, forecasts, planning/approvals, buyers, reports |
| `ADMIN` | Control Tower APK / web | Everything a manager can do + master data, users, remote config |
| Backup buyer / cold storage | No app. SMS link → server-rendered offer page | Accept/reject diversion offers |
| Consumer / retailer | No app. QR → server-rendered trace page | View the verified batch journey |

---

## 2. Scope: Build vs Simulate vs Design-only

| Category | Items |
|----------|-------|
| **Build (working, demo-able)** | 3 Flutter APK flavors + web console, NestJS backend (API + worker), PostgreSQL schema, Kafka/MQTT/InfluxDB pipeline, 4 AI models (served), alerts (push/SMS/email/in-app), incident engine with 3 actions, backup buyer registry + offers, FEFO planning, hash-chained trace log + public trace page, compliance/emission/reefer-health reports, ERP order import, in-app update system with GitHub Releases, AWS deployment |
| **Simulate** | IoT reefer pods and warehouse BLE beacons (Python simulator over MQTT). RFID gate portals (NFC/QR on phone + keyboard-wedge handheld). Sales history for forecasting. Live traffic (haversine + speed profile by default, OSRM/Google as optional providers) |
| **Design-only (documented, not built)** | Real IoT hardware (sensor specs in Section 9.4), NVIDIA Jetson edge inference, 10,000-device scale, multi-region 99.99% uptime, Kubernetes, FSMA 204 / EU 178/2002 full certification (we generate the supporting logs and reports only) |

---

## 3. Requirements Catalogue

Every ID below must be traceable to code and tests. Use the IDs in commit bodies, test names and `docs/TESTING.md`.

### 3.1 Synopsis functional requirements (SYN)

| ID | Requirement |
|----|-------------|
| SYN-01 | Ingest IoT telemetry in JSON and binary packet format: temperature, humidity, 3-axis vibration/shock, ethylene (C₂H₄) |
| SYN-02 | ERP connectivity: secure API to import delivery orders/invoices/depots (+ CSV import) |
| SYN-03 | Batch onboarding of harvest/catch profile (time, species, weight, ice ratio, maturity index) |
| SYN-04 | Recalculate residual shelf life (Cox PH) **within 5 s** of a threshold-crossing packet |
| SYN-05 | Automated visual grading A/B/C **within 3 s** of batch scan (server-side inference target) |
| SYN-06 | Recalculate routes (Genetic DVRPTW) on temperature excursion or reported delay |
| SYN-07 | Multi-channel alerts (SMS, push, email) to driver + control tower when an excursion persists **> 15 min** |
| SYN-08 | Push altered routes, stop order and liquidation targets to the driver app with no manual dispatcher step |
| SYN-09 | Signed public URL/QR per batch showing its audited journey |
| SYN-10 | Storage path decision gate (climacteric → ripening chamber; fish/non-climacteric → blast chiller) |
| SYN-11 | 7-day demand forecast (LSTM + LightGBM) |
| SYN-12 | Telemetry data tiering: ≤ 30 days in InfluxDB, older archived to compressed object storage for training |
| SYN-13 | RBAC: driver read-only routes; manager read-write routing/inventory; consumer read-only trace |
| SYN-14 | TLS for all external traffic; SHA-256 hashing for tamper-evident history |
| SYN-15 | Compliance documentation: HACCP-style temperature logs (EN 12830-style recorder data), FSMA 204 KDE-style traceability export |
| SYN-16 | ESG: Scope 3 transport emission per trip (distance × configurable factor) |
| SYN-17 | Predictive reefer maintenance: flag degrading cooling performance |
| SYN-18 | Ethylene build-up alerts for climacteric cargo |
| SYN-19 | Warehouse pallet movement / cross-docking: batch receive + dispatch loading at sites |
| SYN-20 | Inventory allocation: recommend storage unit by maturity/product |

### 3.2 Workflow fixes agreed in discussion (W)

| ID | Fix |
|----|-----|
| W-1 | **Backup Buyer Registry.** Diversion only to buyers that are open, accept the product + grade, and are reachable before spoilage. Offer sent by SMS link. Route changes only after the buyer accepts. 10-min timeout → next buyer |
| W-2 | **Incident actions.** `DRIVER_FIX` for drift with the reefer ON (re-check after 15 min) → else divert. `REEFER_FAILURE` → nearest cold storage first, or `RESCUE_PICKUP` by a nearby compatible truck with free capacity, else divert to a buyer |
| W-3 | **Order Planning step.** Forecast → FEFO draft dispatch orders → manager approval → route optimiser → trips |
| W-4 | **Tamper-evident hash-chained log** (not "blockchain"). Each record stores its own hash + the previous hash. Table is insert-only for the app DB role. The trace page shows a "Verified" badge |

### 3.3 Driver App (DA)

| ID | Requirement |
|----|-------------|
| DA-FR-01 | Mobile + OTP login; one active session per device and one vehicle at a time |
| DA-FR-02 | Show the day's trip: vehicle, batches, pickup/drop points, time windows |
| DA-FR-03 | Start Trip only after pre-trip check (reefer ON, set temp correct, doors closed), saved with timestamp |
| DA-FR-04 | Navigation on the optimised route: stop order + ETA per stop (turn-by-turn via Google Maps hand-off, see D-12) |
| DA-FR-05 | Live cargo status: temp, humidity, remaining shelf life per batch, refreshed every 60 s |
| DA-FR-06 | Critical alert: push + loud in-app alarm + TTS voice prompt; SMS if push fails |
| DA-FR-07 | Alert acknowledgement required; no ack in 5 min → escalate to manager |
| DA-FR-08 | Reroute proposal: old vs new stop + reason → Accept → navigation switches; no driver response in 5 min → escalate |
| DA-FR-09 | 2-tap incident report (delay, breakdown, accident, roadblock, reefer fault) + optional photo + voice note; triggers replanning |
| DA-FR-10 | Phone GPS every 30 s while trip active (backup to the IoT pod) |
| DA-FR-11 | PoD: scan crate tag, receiver name + signature, photo → upload |
| DA-FR-12 | Accept / partial / reject per batch with reason and accepted quantity |
| DA-FR-13 | Trip history, PoD status, pending uploads |
| DA-FR-14 | One-tap SOS with live location to manager + emergency contact |
| DA-NFR-01..12 | Offline route/stop cache + pre-downloaded corridor map tiles; SQLite queue + auto sync, no data loss; alert reaches phone ≤ 10 s; 2 GB RAM / Android 8+ / 720p; APK < 40 MB; GPS battery < 5%/h with foreground service; 48 dp+ touch targets, high contrast, icon+text, voice prompts; typing blocked above 10 km/h (only Acknowledge, Accept Reroute, SOS work); EN/HI/MR switchable on the login screen; TLS 1.3, JWT 15 min + refresh, SQLCipher, driver role read-only; crash-free > 99% (Crashlytics); cold start < 3 s |

### 3.4 Field Operator App (FO)

| ID | Requirement |
|----|-------------|
| FO-FR-01 | Mobile + OTP login, linked to one site |
| FO-FR-02 | Fishery batch form: catch time, vessel ID, dock, species, weight kg, ice-to-fish ratio, initial core temp |
| FO-FR-03 | Produce batch form: harvest time, farm ID, crop + variety, weight kg, maturity index, Brix, field temp/humidity |
| FO-FR-04 | Master lists from server; last-used values pre-filled |
| FO-FR-05 | NFC tag tap (13.56 MHz); QR fallback; UHF RFID via Bluetooth handheld (keyboard-wedge) |
| FO-FR-06 | Guided 3-photo capture (top, side, close-up) with an on-screen frame |
| FO-FR-07 | Show grade, defects and confidence within 5 s of upload; dispute option |
| FO-FR-08 | Show storage path (blast chiller vs ripening chamber) and the recommended unit |
| FO-FR-09 | Print label with QR over a Bluetooth thermal printer; share-as-image fallback |
| FO-FR-10 | Receiving: scan, condition check, damage photos, accept/reject |
| FO-FR-11 | Dispatch loading: link scanned batches to a truck/trip |
| FO-FR-12 | Batch list with status filters + search by ID |
| FO-FR-13 | Edit only within 30 min of creation; later edits need manager approval; all changes logged |
| FO-NFR-01..10 | Fully offline registration/tagging/photos with original capture time; client UUIDs + server dedupe; batch done in < 60 s; photos 1280 px long side, < 500 KB, full-res kept until graded; gloves/wet-hand friendly, sunlight high-contrast; Android 8+, 3 GB RAM, 12 MP camera, NFC recommended; on-device range validation (e.g. fish core temp −2 to +10 °C); TLS 1.3, JWT, encrypted local storage, operator/device/GPS/time on each record, SHA-256 record hash; EN/HI/MR with field icons; text scale to 200%, voice input for numeric fields |

### 3.5 Server and model targets (SRV / ML)

| ID | Target |
|----|--------|
| SRV-01 | p95 mobile API latency < 300 ms (measured on the prototype EC2) |
| SRV-02 | Sensor → InfluxDB ≤ 500 ms |
| SRV-03 | Threshold breach → alert sent < 5 s (after the persistence window) |
| SRV-04 | Uptime target 99.5% (prototype); daily DB backups kept 30 days |
| ML-01 | Vision: YOLOv8s, mAP@0.5 ≥ 0.80, grade accuracy ≥ 85%, ≤ 3 s end-to-end |
| ML-02 | Shelf-life: Cox PH, C-index ≥ 0.75, error ≤ ±12 h; Q10 fallback always returns a value |
| ML-03 | Forecast: 7-day, MAPE < 15% on a time-based test split |
| ML-04 | Routing: replan < 10 s for 10 vehicles / 50 stops; ≥ 10% distance saving vs the manual order |

### 3.6 Authentication (AUTH)

| ID | Requirement |
|----|-------------|
| AUTH-01 | Supabase Auth is the only identity provider. Providers enabled: Google, Email (with "Confirm email" ON), Phone. Public sign-ups disabled |
| AUTH-02 | Driver and Operator APKs: phone OTP only (6 digits, 5-min expiry, Supabase defaults), SMS delivered through the Send SMS Hook → httpSMS |
| AUTH-03 | Control Tower APK + web: "Continue with Google" and email + password. Email login is blocked until the email is verified. Password reset by email link |
| AUTH-04 | Manager/admin alert emails are sent only to verified addresses (`users.email_verified_at` set). Changing an email requires re-verification |
| AUTH-05 | The backend accepts a request only when the Supabase JWT is valid (signature through JWKS, `exp`, `iss`, `aud=authenticated`) **and** the Supabase user is linked to an active row in `users` whose role is allowed for the calling app (`X-App-Flavor`) |
| AUTH-06 | Admin creates a user (name, role, site, phone and/or email) → backend creates the Supabase user via the admin API (phone pre-confirmed; email → invite/verification mail) and stores `supabase_uid` |
| AUTH-07 | Driver single-device rule (DA-FR-01) enforced by the backend (`device_registrations.active`), not by Supabase |
| AUTH-08 | The Send SMS Hook endpoint verifies the Standard Webhooks signature, rate-limits per phone (5/hour), and logs no OTP value |

> ML targets are **goals**. Record the measured values honestly in `docs/TESTING.md`. Never copy targets in as results.

---

## 4. Key Technical Decisions (summary)

Copy these into `docs/DECISIONS.md` in M1, with one-line reasons, and add new ones there.

| ID | Decision | Reason |
|----|----------|--------|
| D-01 | **Flutter** (one codebase) for all 3 APKs **and** the web Control Tower (Flutter web build of the manager flavor) | The synopsis allows Flutter. One codebase means less work. The synopsis's React.js console is replaced by a Flutter web build (deviation recorded) |
| D-02 | **NestJS (Node.js 24 LTS, TypeScript)** modular monolith with two processes: `api` and `worker` | Synopsis allows Node.js. Modules stay separated without microservice overhead. gRPC between services is dropped; API ↔ ML uses internal HTTP (deviation recorded) |
| D-03 | **Python 3.12 FastAPI** ML service. Inference uses **ONNX Runtime** for YOLOv8 and LSTM; LightGBM, lifelines, DEAP and OR-Tools are native | No PyTorch in the server image, so less RAM on EC2. Training runs separately (local GPU / Colab) |
| D-04 | **AWS RDS PostgreSQL 16** primary DB with **Prisma** ORM + migrations; lat/lng stored as doubles, haversine in code (no PostGIS) | Mandated RDS. Prisma migrations are simple. PostGIS is not needed |
| D-05 | **Apache Kafka (KRaft, single broker, 512 MB heap)**, **Mosquitto MQTT**, **InfluxDB 2.7**, **Redis 7**, all in Docker on one EC2 | Keeps the synopsis architecture at prototype cost. Kafka Streams (Java) is replaced by a Node Kafka consumer doing the same threshold checks (deviation recorded) |
| D-06 | **Redis + BullMQ** for delayed jobs (5-min ack escalation, 10-min offer timeout, 15-min shelf-life refresh) and the rate-limit store | Reliable timers that survive process restarts |
| D-07 | **S3** (one private bucket) for photos, signatures, voice notes and the telemetry archive. Uploads use presigned PUT URLs | Cheap, keeps the EC2 disk small. No keys on the server (IAM instance role) |
| D-08 | **SSM Parameter Store (SecureString)** for production secrets, rendered into `.env` at deploy | Free tier, no secrets in Git |
| D-09 | **CloudWatch Logs** via the Docker `awslogs` driver + a few CloudWatch alarms → SNS email | Basic monitoring without running Prometheus/ELK on a small server |
| D-10 | **Firebase**: FCM push + Crashlytics; 3 Android apps in one Firebase project | Already required by DA-NFR-11 and push alerts |
| D-11 | All SMS (OTP, alert fallback, SOS, buyer offers) via a provider adapter: `console` in dev, **`httpsms` (self-hosted httpSMS on the same EC2)** in prod. Email via custom SMTP (`nodemailer`; same SMTP configured in Supabase) | No DLT/bulk-SMS provider needed for the prototype; testable without cost |
| D-12 | Driver navigation = in-app map (flutter_map + OSM tiles, cached) + **"Navigate" hand-off to the Google Maps app** for turn-by-turn on the current leg | Real turn-by-turn is not practical to build; the hand-off meets DA-FR-04 |
| D-13 | Travel-time provider adapter: `haversine` (default: road factor 1.3, speed profile) / `osrm` / `google` | Works without paid APIs. Live traffic is optional by config |
| D-14 | Trace portal and buyer offer pages are **server-rendered HTML** (NestJS + Handlebars), not apps | Fast, no extra frontend |
| D-15 | Separate **DB roles**: `iccms_migrator` (owner) and `iccms_app` (DML only; INSERT/SELECT only on `trace_events`) | Enforces W-4 at the database level |
| D-16 | **Single universal APK per flavor** built for `android-arm,android-arm64` (no per-ABI splits) | The updater picks one asset; versionCode stays simple |
| D-17 | Updates: GitHub Releases (separate **public** releases repo allowed via `GITHUB_RELEASES_REPO`). The backend syncs releases into the `app_releases` table; phones call only the backend + asset download URLs | Avoids GitHub API rate limits on phones |
| D-18 | YOLOv8 (Ultralytics, AGPL-3.0) is acceptable for this academic project; this is noted in the README license section | Licence transparency |
| D-19 | ResNet (mentioned in the synopsis) is not used; YOLOv8 does both detection and grading | Less work, same requirement coverage |
| D-20 | Model registry = `ml/service/models/registry.json` + versioned files (no MLflow server) | Avoids an extra service |
| D-21 | **Supabase Auth (identity only)**: Google (Gmail) sign-in, email + password with **email verification**, and phone OTP. Supabase issues and refreshes sessions; the NestJS backend verifies Supabase JWTs through JWKS. **All app data stays in RDS**; Supabase's own database is not used for app data | User decision. Removes custom OTP/JWT/refresh code; Google + email verification come built in |
| D-22 | Supabase **Send SMS Hook (HTTPS)** → `POST /api/v1/hooks/supabase/send-sms` on our backend (Standard Webhooks signature check) → httpSMS API → Android gateway phone → SMS | Lets Supabase generate/verify OTPs while delivery goes through our own httpSMS |
| D-23 | Roles stay in our `users` table (RDS), never in Supabase metadata. Public sign-up is **disabled** in Supabase; admins create users from the Control Tower, and the backend creates the matching Supabase user with the admin API | Only pre-registered staff can log in; RBAC stays server-side |
| D-24 | Login methods per app: **Driver/Operator → phone OTP** (field staff may not use email). **Control Tower/web → Google sign-in or email + password (verified email required)**; phone OTP allowed as a fallback | Fits each user group |

---

## 5. Architecture and Repository Layout

### 5.1 Runtime architecture

```
 IoT Simulator (Python) --MQTT/TLS:8883--> Mosquitto --bridge--> Kafka [truck-telemetry]
                                                               |      [quality-scans][order-transactions][alerts]
 Flutter APKs (driver/operator/manager) --HTTPS/WSS--> Nginx --> NestJS api (REST + Socket.IO)
 Flutter web console (manager) ----------HTTPS------> Nginx (/console static)       |
 Public trace / offer pages <------------HTTPS------- NestJS api (Handlebars)       |
                                                                                    v
 NestJS worker: kafka consumers (telemetry-writer, threshold-processor, exposure-aggregator, scan-consumer),
                BullMQ jobs (escalations, offer timeouts, shelf-life refresh, forecast nightly, reefer health,
                data tiering, GitHub release sync)
        |                 |                    |                     |
   RDS PostgreSQL     InfluxDB 2.7          Redis 7          ML service (FastAPI, internal only)
   (primary)          (telemetry ≤30d)      (queues/cache)    vision | shelf-life | forecast | routing
        S3 bucket (photos, PoD, voice, telemetry archive)     FCM / SMS / SMTP (notifications)
```

### 5.2 Repository layout (monorepo)

```
iccms/
├─ PROJECT_IMPLEMENTATION.md   README.md   .gitignore   .editorconfig
├─ docs/  (Section 18)
├─ release/
│  ├─ versions.json            # per-flavor versionName, versionCode, minSupportedVersionCode
│  └─ notes/<flavor>-<version>.md
├─ backend/
│  ├─ prisma/ schema.prisma  migrations/  seed.ts  sql/roles.sql
│  ├─ src/
│  │  ├─ main.ts  worker.ts  app.module.ts  worker.module.ts
│  │  ├─ config/ (env schema via zod, typed config service)
│  │  ├─ common/ (filters, guards, interceptors, decorators, pagination, errors, hashing, geo)
│  │  ├─ infra/ (prisma, redis, kafka, influx, s3, ml-client, queue)
│  │  ├─ modules/
│  │  │  auth/ users/ masters/ (sites, storage-units, vehicles, devices, products) batches/ files/ trace/
│  │  │  grading/ shelf-life/ storage/ forecast/ planning/ orders/ trips/ pod/ telemetry/ alerts/
│  │  │  notifications/ incidents/ buyers/ diversions/ reports/ maintenance/ app-updates/
│  │  │  integrations/ remote-config/ sync/ realtime/ public-pages/ health/
│  │  └─ workers/ (consumers/, jobs/)
│  ├─ views/ (handlebars: trace.hbs, offer.hbs, compliance.hbs)
│  └─ test/ (unit next to sources as *.spec.ts; e2e in test/e2e/*.e2e-spec.ts)
├─ ml/
│  ├─ service/ app/{main.py, routers/, core/, schemas/}  models/registry.json  tests/  Dockerfile
│  └─ training/ vision/ shelf_life/ forecast/ routing/  data/ (gitignored)  requirements-train.txt
├─ simulator/ sim.py  scenarios/*.yaml  binary_format.md  requirements.txt
├─ mobile/
│  ├─ lib/
│  │  ├─ main_driver.dart  main_operator.dart  main_manager.dart  bootstrap.dart
│  │  ├─ core/ config/ theme/ network/ storage/ sync/ auth/ l10n/ updates/ permissions/ realtime/ utils/
│  │  ├─ shared/ widgets/  screens/ (splash, login, otp, updates, settings, sync_queue)
│  │  ├─ apps/driver/   (router.dart, module_tag.dart, screens/, widgets/, data/, providers/)
│  │  ├─ apps/operator/ (same shape)
│  │  ├─ apps/manager/  (same shape)
│  │  └─ l10n/ app_en.arb app_hi.arb app_mr.arb
│  ├─ android/app/src/{driver,operator,manager}/ (AndroidManifest.xml, res/, google-services.json [gitignored])
│  ├─ android/app/src/main/kotlin/in/iccms/app/ApkInstallerPlugin.kt
│  ├─ assets/fonts/  assets/images/
│  └─ test/  integration_test/
├─ deploy/ docker-compose.dev.yml  docker-compose.prod.yml  nginx/iccms.conf  mosquitto/  kafka/  aws/ (policy json)
├─ scripts/ build_apk.sh  check_flavor_isolation.sh  verify_apk_isolation.sh  release.sh  deploy.sh
│           render_env.sh  backup_db.sh  backup_influx.sh  disk_check.sh
└─ .github/workflows/ ci.yml  release-android.yml  release-console.yml
```

**Module rule (backend):** each module = `*.module.ts`, `*.controller.ts`, `*.service.ts`, `dto/`, `*.spec.ts`. Controllers stay thin. Business rules live in services. Modules talk to each other through exported services, never through other modules' Prisma calls.

**Module rule (mobile):** `apps/<flavor>/` may import `core/` and `shared/` only. **It must never import another `apps/` folder.** `core/` and `shared/` never import `apps/`.

---

## 6. Backend Specification (NestJS)

### 6.1 Conventions
- Base path `/api/v1`. JSON, camelCase. Timestamps ISO-8601 UTC. IDs are UUID v4 (client-generated for offline-created records).
- Validation: `class-validator` DTOs with whitelist + forbidNonWhitelisted. Reject unknown fields.
- Error envelope (global exception filter): `{"error":{"code":"EDIT_WINDOW_CLOSED","message":"...","details":{},"requestId":"..."}}`. Codes are `SCREAMING_SNAKE`. Map Prisma `P2002` → 409 `DUPLICATE`, not found → 404 `NOT_FOUND`.
- Pagination: cursor based `?cursor=&limit=` (default 20, max 100) → `{items, nextCursor}`.
- Headers sent by apps: `X-App-Flavor` (driver|operator|manager|web), `X-App-Version-Code`, `X-Device-Id`, `Accept-Language`.
- If `X-App-Version-Code` < `minSupportedVersionCode` for that flavor → **426** `UPGRADE_REQUIRED` (except `/auth/*`, `/app/updates*`, `/health*`).
- Rate limits (`@nestjs/throttler`, Redis store): global 120 req/min/user; Send SMS Hook 5/hour/phone (Supabase also applies its own OTP limits).
- Logging: `nestjs-pino` JSON with `requestId`, `userId`, `route`, `latencyMs`. Redact `authorization`, `otp`, `code`, `password`, `token`, `secret`.

### 6.2 Authentication (Supabase Auth + httpSMS)

**Flow**
```
App ── supabase_flutter ──> Supabase Auth ──(phone OTP)── Send SMS Hook ──> NestJS /hooks/supabase/send-sms ──> httpSMS API (EC2) ──FCM──> Android gateway phone ──SMS──> user
 │        (Google / email+password / phone OTP; Supabase stores and refreshes the session)
 └── HTTPS + "Authorization: Bearer <supabase access token>" + X-App-Flavor ──> NestJS (verifies JWT via JWKS, loads users row, applies RBAC)
```

**Supabase project setup (dashboard or Supabase CLI; record the settings in DEPLOYMENT.md)**
- Region: `ap-south-1` (Mumbai). Use **asymmetric JWT signing keys** so the backend can verify tokens with the JWKS URL `https://<ref>.supabase.co/auth/v1/.well-known/jwks.json` (no shared secret on the server).
- Auth → Providers: **Google** ON (Web client ID + secret from Google Cloud console; Android OAuth client IDs for `in.iccms.manager` with debug and release SHA-1 listed as "authorized client IDs"; Google provider "Skip nonce check" stays OFF). **Email** ON with "Confirm email" ON and "Secure email change" ON. **Phone** ON.
- Auth → Settings: **"Allow new users to sign up" OFF** (D-23). JWT expiry 3600 s (default). Refresh-token rotation ON (default).
- Auth → SMTP: custom SMTP (same as the backend `SMTP_*`; Supabase's built-in mailer is only for testing and has strict limits). Email templates (confirm, invite, reset, change email) branded "I-CCMS", in English + short Hindi/Marathi line.
- Auth → URL configuration: Site URL `https://api.<domain>/console/`. Redirect URLs: `https://api.<domain>/console/**`, `in.iccms.manager://login-callback`.
- Auth → Hooks → **Send SMS Hook**: type HTTPS, URL `https://api.<domain>/api/v1/hooks/supabase/send-sms`. Generate the secret and store it in SSM as `SUPABASE_SEND_SMS_HOOK_SECRET` (keep the `v1,whsec_` prefix in SSM; the code strips it).
- SMS OTP template: `I-CCMS: your login code is {{ .Code }}. Valid for 5 minutes. Do not share it.`
- Rate limits: keep the Supabase defaults; our hook adds 5 per hour per phone.
- Free-tier note: free Supabase projects pause after a period of inactivity. Before any demo or review, open the dashboard and make sure the project is active, or upgrade.

**Backend pieces (`modules/auth/`)**
- `SupabaseJwtStrategy`: verifies the token with `jose` `createRemoteJWKSet(SUPABASE_JWKS_URL)` (cached), checks `iss = ${SUPABASE_URL}/auth/v1`, `aud = authenticated`, `exp`. Then it loads `users` by `supabase_uid = sub` (cached in Redis 60 s). No row / `status != ACTIVE` → 403 `NOT_REGISTERED`.
- `FlavorRoleGuard`: role ↔ flavor map `driver→DRIVER`, `operator→OPERATOR`, `manager|web→MANAGER|ADMIN`. Mismatch → 403 `WRONG_APP_FOR_ROLE` (the app then signs out of Supabase). The header can be faked, but RolesGuard + ownership still decide access (6.3).
- `POST /api/v1/hooks/supabase/send-sms` (no JWT; Standard Webhooks HMAC check with `standardwebhooks`, 5-min timestamp tolerance): body `{user:{phone}, sms:{otp}}` → message from the template → `SmsService.send(phone, text, {priority:'otp'})` → returns `{}` with 200. On provider failure return 500 with `{error:{http_code:500, message}}` so Supabase reports the failure to the app. Rate limit 5/hour/phone, 30/hour/IP of the hook source. Never log the OTP.
- `SmsService` with the `HttpSmsProvider`: `POST ${HTTPSMS_API_URL}/v1/messages/send`, header `x-api-key: ${HTTPSMS_API_KEY}`, JSON `{from: HTTPSMS_FROM_NUMBER, to: "+91…", content}`. Expects 202. Retries twice on network errors only (an OTP must not go out twice). Stores the httpSMS message ID in `notifications.provider_ref`. Optional delivery webhook from httpSMS → `POST /api/v1/hooks/httpsms` (shared-secret header) → updates `notifications.status`.
- `UsersService.create` (ADMIN): creates the RDS row first, then `supabase.auth.admin.createUser({phone, phone_confirm:true})` for phone users, or `supabase.auth.admin.inviteUserByEmail(email)` for email users (the invite mail verifies the address), and saves `supabase_uid`. Uses `SUPABASE_SERVICE_ROLE_KEY` (server only, never in apps). Disable user → `status=DISABLED` + `auth.admin.updateUserById(uid, {ban_duration:'876000h'})`. Delete → soft delete in RDS + ban in Supabase.
- Email verified status: on every `/me` call, copy `email_confirmed_at` from the JWT claims/admin API into `users.email_verified_at`. The notification service sends alert emails only when it is set (AUTH-04).
- **Device rule (DA-FR-01, AUTH-07):** `POST /me/session {deviceId, fcmToken, appVersionCode}` after every login marks this device active for the user + flavor and all others inactive. For DRIVER, requests carrying a different `X-Device-Id` than the active one → 409 `SESSION_ON_OTHER_DEVICE` (the app shows "You logged in on another phone" and signs out). A trip binds `deviceId + vehicleId` on start.
- Dev/test: `SMS_PROVIDER=console` prints SMS text to the worker log (dev only). For automated tests, use Supabase **test phone numbers** (Auth → Phone → test OTPs) or the Supabase CLI local stack (`supabase start`) with its Inbucket mailbox. Production refuses to start if `SMS_PROVIDER=console`.

### 6.3 Authorisation (server is the only authority)
- `SupabaseAuthGuard` (JWT + linked active user) → `FlavorRoleGuard` (role allowed for `X-App-Flavor`) → `DeviceGuard` (drivers only) → `RolesGuard` (`@Roles(...)`) → **ownership checks in services** (driver sees only their trips; operator only their site's batches).
- Even if someone edits an APK or calls the API directly, the role + ownership checks block access. Client-side screen separation is for size and UX only, not security.

| Area | DRIVER | OPERATOR | MANAGER | ADMIN | Public |
|------|:-:|:-:|:-:|:-:|:-:|
| Own trips, route (read), events, PoD, ack alerts | ✔ | | read | read | |
| Batches create/edit (own site, 30-min window), tags, images, receive, load | | ✔ | read + approve edits | ✔ | |
| Alerts/incidents manage, manual actions | | | ✔ | ✔ | |
| Forecast, planning, orders approve, trips assign | | | ✔ | ✔ | |
| Buyers registry | | | ✔ | ✔ | |
| Masters, users, remote config | | read masters | read | ✔ | |
| Reports | | | ✔ | ✔ | |
| Trace page `/t/:code?s=`, offer page `/offer/:token` | | | | | ✔ (signed) |

### 6.4 API endpoints (implement all; document request/response in `docs/API_DOCUMENTATION.md`)

**Auth and self** (login, OTP, refresh and logout happen in Supabase from the app): `GET /me` (role, site, flags, emailVerified) · `POST /me/session {deviceId, fcmToken, appVersionCode}` · `PUT /me/language` · `POST /me/logout` (marks the device inactive; the app also calls `supabase.auth.signOut()`) · `POST /admin/users` · `PATCH /admin/users/:id` · `POST /admin/users/:id/disable|enable` · `POST /admin/users/:id/resend-invite` (ADMIN)

**Hooks (no JWT, signature-checked):** `POST /hooks/supabase/send-sms` · `POST /hooks/httpsms` (delivery status)

**Masters (read: all roles; write: ADMIN):** `GET|POST|PATCH /masters/{products|sites|storage-units|vehicles|devices}`. `GET /masters/bundle?since=` returns everything an app needs offline (products, sites, storage units, remote config) with an ETag.

**Batches (OPERATOR / MANAGER):**
`POST /batches` (client UUID, idempotent) · `GET /batches?status&q&siteId&cursor` · `GET /batches/:id` ·
`PATCH /batches/:id` (≤ 30 min, else 409 `EDIT_WINDOW_CLOSED`) · `POST /batches/:id/edit-requests` · `GET /edit-requests?status` (MANAGER) ·
`POST /edit-requests/:id/approve|reject` (MANAGER) · `POST /batches/:id/tags {tagType, tagUid}` ·
`POST /batches/:id/images {view, key}` · `POST /batches/:id/grade` (sync ML call, returns grade) · `POST /batches/:id/grade/dispute {reason}` ·
`POST /grades/:id/resolve {grade}` (MANAGER) · `GET /batches/:id/storage-path` · `POST /batches/:id/storage {storageUnitId}` ·
`GET /batches/:id/label` (label data + signed trace URL) · `POST /batches/:id/receive {outcome, acceptedKg, condition, notes, imageKeys}` ·
`GET /batches/:id/timeline` · `GET /batches/:id/shelf-life`

**Files:** `POST /files/presign {purpose: BATCH_IMAGE|POD_SIGNATURE|POD_PHOTO|INCIDENT_PHOTO|VOICE_NOTE, contentType, sizeBytes}` → `{uploadUrl, key, expiresIn: 300}`. Allowed types: jpeg/png/webp/m4a/aac. Max 2 MB for images, 5 MB for audio. Key pattern `<purpose>/<yyyy>/<mm>/<uuid>.<ext>`. `GET /files/:key/url` → presigned GET (5 min), with an ownership check.

**Trips (DRIVER / OPERATOR load / MANAGER):**
`GET /driver/trips/current` · `GET /driver/trips?cursor` · `GET /trips/:id` · `GET /trips/:id/route` (latest accepted + pending proposal) ·
`POST /trips/:id/pre-check {reeferOn, setpointC, doorsClosed}` · `POST /trips/:id/start` · `POST /trips/:id/events` (incident/SOS, client UUID) ·
`POST /trips/:id/routes/:version/accept|decline` · `POST /trips/:id/stops/:stopId/arrive` · `POST /trips/:id/stops/:stopId/pod` (per batch outcome) ·
`GET /trips/:id/cargo-status` · `POST /trips/:id/load {batchIds}` (OPERATOR) · `GET /trips?status&date` (MANAGER) ·
`POST /trips/:id/assign {driverId, vehicleId}` (MANAGER) · `GET /trips/:id/telemetry?from&to&every=1m` (MANAGER; InfluxDB query)

**Alerts / incidents / diversions:** `GET /alerts?status&tripId` · `POST /alerts/:id/ack` (DRIVER own / MANAGER) · `POST /alerts/:id/resolve` (MANAGER) ·
`GET /incidents?status` · `GET /incidents/:id` (with decision log) · `POST /incidents/:id/action {action, buyerId?, rescueTripId?}` (MANAGER manual override) ·
`GET /incidents/:id/offers`

**Buyers (MANAGER):** `GET|POST|PATCH|DELETE /buyers` (soft delete via `active=false`)

**Forecast / planning / orders (MANAGER):** `GET /forecasts?siteId&productId&from&to` · `POST /forecasts/run` (async job) ·
`POST /planning/run {date}` → FEFO draft orders · `GET /orders?status` · `PATCH /orders/:id` · `POST /orders/:id/approve` ·
`POST /planning/routes {date, depotSiteId}` → trips + initial route plans · `POST /orders/import` (CSV multipart)

**Integrations (ERP):** `POST /integrations/orders` with `X-Api-Key` (stored hashed in `integration_clients`) + `X-Signature` = HMAC-SHA256(body). Idempotent on `externalRef`.

**Reports (MANAGER):** `GET /reports/batches/:id/compliance?format=html|csv` (temperature log at 1-min resolution, min/max/mean, excursions, all trace events, PoD) ·
`GET /reports/traceability?from&to&format=csv` (FSMA-204-style KDE export: what, where, when, quantities, lot codes) ·
`GET /reports/emissions?from&to&format=csv|json` · `GET /reports/reefer-health`

**Remote config (ADMIN write, all read via bundle):** `GET|PUT /config/:key`

**Sync:** `POST /sync {ops:[{clientOpId, type, payload, capturedAt}]}` → per-op result. Types: `BATCH_CREATE, BATCH_UPDATE, TAG_ATTACH, IMAGE_ATTACH, RECEIVE, LOAD, TRIP_EVENT, GPS_POINTS, POD, ALERT_ACK, ROUTE_ACCEPT`. Results are idempotent through `sync_ops`. Ops are applied in `capturedAt` order per entity.

**App updates:** `GET /app/updates?flavor&channel&versionCode` (public; returns latest compatible + mandatory flag + history) · `POST /app/updates/installed {flavor, fromCode, toCode, deviceId}` ·
`POST /admin/app-releases/sync` (ADMIN) · `POST /webhooks/github` (HMAC `X-Hub-Signature-256`, `release` events)

**Public (no auth):** `GET /t/:code?s=<sig>` (trace page HTML) · `GET /t/:code/verify?s=` (JSON chain verification) · `GET /offer/:token` · `POST /offer/:token/accept|reject`

**Health:** `GET /health` (liveness) · `GET /health/ready` (DB, Redis, Kafka, Influx, ML)

**Realtime (Socket.IO, path `/rt`, JWT in auth payload):** rooms `user:<id>`, `trip:<id>`, `role:manager`. Server events:
`alert.raised`, `alert.updated`, `cargo.status`, `route.proposed`, `route.updated`, `incident.updated`, `offer.updated`, `trip.updated`, `vehicle.position`.
When the app is in the background, critical events also go through FCM (data message + high priority).

### 6.5 Core business logic

**Batch code:** `{FSH|PRD}-{yyyymmdd}-{site code}-{4-digit seq}`. **Record hash** = SHA-256 of the canonical JSON of the creation payload (sorted keys).

**Storage path (SYN-10, SYN-20):** `FISH` or `!isClimacteric` → `BLAST_CHILLER`; climacteric → `RIPENING_CHAMBER`. Recommend a unit at the batch's current site with the matching type, free capacity, and a temp range that fits the product. Grade C → `COLD_ROOM` with a "sell first" flag.

**Edit window (FO-FR-13):** `now - createdAt ≤ 30 min` and same site → direct PATCH (logged in `audit_logs` + trace event `BATCH_CORRECTED`). Otherwise an edit request → manager approval → a new trace event. Original values are never overwritten silently.

**Trace hash chain (W-4, SYN-14):** in one transaction: `SELECT ... FROM batches WHERE id=$1 FOR UPDATE` → next `seq` → `hash = sha256(prevHash || eventType || canonicalJson(payload) || occurredAt.toISOString())`, where `prevHash` = 64 zeros for seq 1. Verify = recompute the chain. The trace URL signature `s` = base64url(HMAC-SHA256(code, `TRACE_SIGNING_KEY`))[:22].
Events: `REGISTERED, TAGGED, IMAGED, GRADED, GRADE_DISPUTED, GRADE_RESOLVED, STORED, BATCH_CORRECTED, ALLOCATED, LOADED, DEPARTED, EXCURSION, SHELF_LIFE_UPDATED (only on change ≥ 2 h), DIVERTED, RESCUED, RECEIVED, DELIVERED, REJECTED`.

**Threshold processing (SYN-07, SYN-18):** per device, Redis keeps `breachStart` per metric. A reading outside product limits (the strictest limits among the batches on the truck) starts or continues a breach.
- At breach start → immediately request a shelf-life recompute (SYN-04, ≤ 5 s) → push `cargo.status`.
- Breach lasting ≥ `persistMinutes` (config, default 15) → alert `CRITICAL` + notify driver (push, in-app, SMS fallback) + managers (push, email) → BullMQ job `alert-escalation` in `ackMinutes` (default 5).
- Shock > `shockMaxG` → `WARNING` alert, recorded in exposure. Ethylene > product `ethyleneMaxPpm` → `WARNING`; if leafy/non-climacteric produce shares the truck → `CRITICAL`.
- No packet for 5 min → `DEVICE_OFFLINE` `WARNING`. Phone GPS continues the position.

**Spoilage decision gate (Section 1.1 step 6):** every shelf-life update → `remainingShelfLifeH` vs `remainingEtaH + safetyMarginH` (config, default 2). If below → incident `SPOILAGE_RISK` → incident engine.

**Incident engine (W-2):**
1. Classify: `reeferOn=true` and temp slope ≤ `driftSlopeMax` (default 0.5 °C / 10 min) → `TEMP_DRIFT`. `reeferOn=false` or slope > max or a driver reported `REEFER_FAULT` → `REEFER_FAILURE`. Shelf life < ETA + margin → `SPOILAGE_RISK`. Driver-reported delay/breakdown → `DELAY` / `BREAKDOWN`.
2. `TEMP_DRIFT` → `DRIVER_FIX` instruction (check door seal, setpoint, airflow) through an alert. Re-evaluate in 15 min (BullMQ). Not recovered → treat as `SPOILAGE_RISK`.
3. `REEFER_FAILURE` → candidates in this order: (a) nearest `COLD_STORAGE` buyer reachable before spoilage; (b) `RESCUE_PICKUP`: an active trip with a compatible temp range, free capacity ≥ cargo, within `rescueRadiusKm` (default 30); (c) divert to a buyer.
4. `SPOILAGE_RISK` / `DELAY` that makes delivery impossible → divert to a buyer (W-1). `DELAY` where delivery is still feasible → replan the same stops (SYN-06).
5. Every step is appended to `incidents.decision_log` (inputs, candidates, chosen, reason). Managers can override with `POST /incidents/:id/action`.

**Diversion offers (W-1):** candidates = active buyers whose `acceptedProductIds` include the product, `minGrade ≤ batch grade`, open at the ETA (`openingHours` JSON per weekday), and with ETA < shelf life − margin. Rank by `(discountPct asc, etaH asc)`. Send an offer to the top one: create the token (32 bytes random; store its SHA-256), SMS the link `APP_BASE_URL/offer/<token>`, expiry 10 min (BullMQ). Accept → call the routing replan with the diversion stop → `route.proposed` to the driver. Reject/expire → next candidate. No candidates left → `MANUAL` + escalate to managers.

**Planning (W-3):** `POST /planning/run` → for each distribution centre and product: `need = forecast(date) − in-transit − on-hand at the centre`. Allocate available batches FEFO (lowest remaining shelf life first). Batches with shelf life < 24 h go to the nearest centres. Result: `dispatch_orders` with status `DRAFT` + `order_batches`. The manager edits/approves. `POST /planning/routes` groups approved orders by depot → ML `/routes/optimize` → trips + stops + `route_plans v1`.

**Emissions (SYN-16):** `co2Kg = distanceKm × config.emissionFactorKgPerKm` (admin sets the value and its source; no hardcoded default in code; seed puts a placeholder value marked "replace with sourced factor").

**Reefer health (SYN-17):** weekly job: for each vehicle, the pull-down rate (°C/min) in the first 20 min after door-close events or trip start. `degradationPct = (baseline − current)/baseline`. Above 30% → `REEFER_MAINTENANCE` alert + report row. Baseline = median of the first 4 weeks.

**Data tiering (SYN-12):** InfluxDB bucket retention 30 days. A nightly job exports day D−29 to `s3://<bucket>/telemetry-archive/yyyy/mm/dd.csv.gz` before expiry.

**GitHub release sync (D-17):** see Section 12.

---

## 7. Database Design (PostgreSQL 16 on RDS, Prisma)

Conventions: `snake_case` tables/columns via `@@map/@map`. `id uuid` PK (except where noted). `created_at`, `updated_at` timestamptz. Soft delete by `active` where needed. Money/weights as `numeric(12,3)`. Enums as Prisma enums.

| Table | Key columns (beyond id/timestamps) | Indexes / constraints |
|-------|-------------------------------------|-----------------------|
| users | supabase_uid UNIQUE (nullable until linked), phone UNIQUE? (E.164), email UNIQUE? (lower-case), email_verified_at?, auth_method (PHONE/GOOGLE/EMAIL), name, role (ADMIN/MANAGER/OPERATOR/DRIVER), site_id FK?, language (en/hi/mr), emergency_contact_phone?, status (INVITED/ACTIVE/DISABLED) | idx(role), idx(site_id); CHECK (phone IS NOT NULL OR email IS NOT NULL); CHECK role IN (DRIVER, OPERATOR) → phone NOT NULL |
| device_registrations | user_id, device_id, flavor, fcm_token, app_version_code, active, last_seen_at | UNIQUE(device_id, flavor); partial UNIQUE(user_id, flavor) WHERE active |
| sites | code UNIQUE, name, type (DOCK/FARM_GATE/COLD_STORAGE/WAREHOUSE/DISTRIBUTION_CENTRE), lat, lng, address | idx(type) |
| storage_units | site_id FK, code, type (BLAST_CHILLER/RIPENING_CHAMBER/COLD_ROOM), temp_min, temp_max, capacity_kg, used_kg | UNIQUE(site_id, code) |
| vehicles | reg_no UNIQUE, capacity_kg, reefer_min_temp, reefer_max_temp, home_site_id, status, baseline_pulldown_rate? | |
| iot_devices | device_code UNIQUE, vehicle_id?, storage_unit_id?, mqtt_username UNIQUE, secret_hash, status, last_seen_at | |
| products | code UNIQUE, name, name_hi, name_mr, category (FISH/PRODUCE), is_climacteric, is_ethylene_sensitive, safe_temp_min/max, humidity_min/max, ethylene_max_ppm?, shock_max_g, base_shelf_life_h, q10, unit_price | |
| app_config | key PK, value jsonb, updated_by | (persistMinutes, ackMinutes, offerMinutes, safetyMarginH, driftSlopeMax, rescueRadiusKm, emissionFactorKgPerKm, gpsIntervalSec, editWindowMin, featureFlags) |
| batches | id (client UUID), code UNIQUE, product_id, source_type (FISHERY/FARM), source_site_id, current_site_id, storage_unit_id?, vessel_id?, farm_ref?, caught_or_harvested_at, weight_kg, ice_to_fish_ratio?, initial_core_temp?, maturity_index?, brix?, field_temp?, field_humidity?, status, current_grade?, remaining_shelf_life_h?, shelf_life_updated_at?, created_by, device_id, captured_at, captured_lat, captured_lng, record_hash | idx(current_site_id, status), idx(product_id, status), idx(created_at desc), idx(remaining_shelf_life_h) |
| batch_tags | batch_id, tag_type (NFC/UHF_RFID/QR), tag_uid UNIQUE, attached_by | idx(batch_id) |
| batch_images | batch_id, view (TOP/SIDE/CLOSEUP/RECEIVING/DAMAGE), s3_key, size_bytes, width, height, captured_at | idx(batch_id) |
| quality_grades | batch_id, grade (A/B/C), defects jsonb, confidence, model_version, source (AUTO/MANUAL), disputed, dispute_reason?, resolved_by? | idx(batch_id, created_at desc) |
| batch_edit_requests | batch_id, requested_by, changes jsonb, reason, status, reviewed_by?, reviewed_at? | idx(status) |
| shelf_life_estimates | batch_id, remaining_h, survival_curve jsonb, method (COX/Q10_FALLBACK), model_version, trigger (BREACH/SCHEDULED/GRADE/MANUAL) | idx(batch_id, created_at desc) |
| batch_exposure | batch_id PK, degree_minutes_above, minutes_above_limit, mean_temp, max_temp, shock_events, max_ethylene_ppm | |
| demand_forecasts | site_id, product_id, forecast_date, predicted_kg, lower_kg, upper_kg, model_version, run_id | UNIQUE(site_id, product_id, forecast_date, run_id) |
| dispatch_orders | code UNIQUE, source_site_id, destination_site_id, product_id, quantity_kg, window_start, window_end, status (DRAFT/APPROVED/PLANNED/IN_TRANSIT/DELIVERED/CANCELLED), origin (PLANNER/ERP/CSV/MANUAL), external_ref?, approved_by? | idx(status, window_start), UNIQUE(origin, external_ref) |
| order_batches | order_id, batch_id, allocated_kg | PK(order_id, batch_id) |
| trips | code UNIQUE, vehicle_id, driver_id?, depot_site_id, status (PLANNED/ASSIGNED/PRE_CHECK_DONE/IN_PROGRESS/COMPLETED/CANCELLED), planned_start, started_at, completed_at, bound_device_id?, current_route_version, distance_km?, co2_kg? | idx(driver_id, status), idx(status, planned_start) |
| trip_stops | trip_id, seq, route_version, type (PICKUP/DROP/DIVERSION_DROP/RESCUE_PICKUP/RESCUE_DROP/COLD_STORAGE_DROP), site_id?, buyer_id?, order_id?, lat, lng, window_start?, window_end?, eta?, arrived_at?, completed_at?, status | idx(trip_id, route_version, seq) |
| trip_batches | trip_id, batch_id, loaded_by, loaded_at, unloaded_at? | PK(trip_id, batch_id) |
| route_plans | trip_id, version, reason (INITIAL/DELAY/INCIDENT/DIVERSION/RESCUE/MANUAL), stops jsonb, polyline?, fitness, status (PROPOSED/ACCEPTED/DECLINED/SUPERSEDED), responded_at? | UNIQUE(trip_id, version) |
| trip_events | id (client UUID), trip_id, type (PRE_TRIP_CHECK/START/INCIDENT_DELAY/INCIDENT_BREAKDOWN/INCIDENT_ACCIDENT/INCIDENT_ROADBLOCK/INCIDENT_REEFER_FAULT/SOS/ARRIVE/COMPLETE), payload jsonb, photo_key?, voice_key?, lat?, lng?, occurred_at | idx(trip_id, occurred_at) |
| proof_of_delivery | id (client UUID), trip_stop_id, batch_id, outcome (ACCEPTED/PARTIAL/REJECTED), accepted_kg, reason?, receiver_name, signature_key, photo_key, scanned_tag_uid, captured_at, lat, lng | UNIQUE(trip_stop_id, batch_id) |
| alerts | type (TEMP_EXCURSION/HUMIDITY/ETHYLENE/SHOCK/SPOILAGE_RISK/DEVICE_OFFLINE/SOS/REEFER_MAINTENANCE/DRIVER_FIX), severity, trip_id?, vehicle_id?, batch_id?, message, data jsonb, status (OPEN/ACKNOWLEDGED/ESCALATED/RESOLVED), acknowledged_by?, acknowledged_at?, escalated_at?, resolved_at? | idx(status, created_at desc), idx(trip_id) |
| notifications | alert_id?, user_id, channel (PUSH/SMS/EMAIL/IN_APP), status (QUEUED/SENT/FAILED), provider_ref?, error? | idx(alert_id) |
| incidents | trip_id, alert_id?, kind, decided_action (DRIVER_FIX/DIVERT_BUYER/DIVERT_COLD_STORAGE/RESCUE_PICKUP/REPLAN/MANUAL), status (OPEN/ACTION_IN_PROGRESS/RESOLVED/FAILED), decision_log jsonb, resolved_at? | idx(status), idx(trip_id) |
| backup_buyers | name, type (CANNING/PROCESSING/LOCAL_MARKET/DISCOUNT_RETAIL/COLD_STORAGE), phone, email?, lat, lng, accepted_product_ids uuid[], min_grade, discount_pct, opening_hours jsonb, capacity_kg?, active | idx(type, active), GIN(accepted_product_ids) |
| diversion_offers | incident_id, buyer_id, batch_ids uuid[], quantity_kg, token_hash UNIQUE, status (SENT/ACCEPTED/REJECTED/EXPIRED/CANCELLED), expires_at, responded_at? | idx(incident_id) |
| trace_events | id bigserial PK, batch_id, seq, event_type, payload jsonb, actor_user_id?, occurred_at, prev_hash char(64), hash char(64) | UNIQUE(batch_id, seq); **app role: INSERT/SELECT only** |
| reefer_health | vehicle_id, period_start, period_end, pulldown_rate, baseline_rate, degradation_pct, flagged | idx(vehicle_id, period_start desc) |
| app_releases | flavor, channel (stable/beta), version_name, version_code, min_supported_code, mandatory, notes_md, features jsonb, improvements jsonb, fixes jsonb, apk_url, apk_name, sha256, size_bytes, signing_cert_sha256, github_release_id UNIQUE, published_at, is_active | UNIQUE(flavor, channel, version_code) |
| app_installs | device_id, flavor, from_code, to_code, status | idx(flavor, created_at) |
| sync_ops | client_op_id PK, user_id, type, result jsonb, received_at | |
| integration_clients | name, key_hash UNIQUE, scopes text[], active | |
| audit_logs | actor_id?, action, entity, entity_id, before jsonb?, after jsonb?, ip?, request_id | idx(entity, entity_id) |

**InfluxDB** (bucket `telemetry`, 30-day retention):
- measurement `reefer`: tags `device_id, vehicle_id, trip_id`; fields `temp_c, humidity_pct, ax, ay, az, shock_g, ethylene_ppm, reefer_on, setpoint_c, door_open, battery_pct, lat, lng`
- measurement `driver_gps`: tags `trip_id, driver_id`; fields `lat, lng, speed_kmh, accuracy_m`
- measurement `beacon`: tags `site_id, beacon_id`; fields `batch_tag, rssi` (simulated pallet movement)

**Migrations:** `prisma migrate dev` locally; `prisma migrate deploy` in production with `MIGRATION_DATABASE_URL`. `prisma/sql/roles.sql` creates the roles and grants, plus `ALTER DEFAULT PRIVILEGES` and `REVOKE UPDATE, DELETE, TRUNCATE ON trace_events FROM iccms_app`. A raw SQL migration step re-applies the trace_events revoke after table creation.
**Seed (`prisma/seed.ts`, idempotent):** 1 admin, 1 manager, 2 drivers, 2 operators (dev phones from env), 6 sites (2 docks, 1 farm gate, 1 cold storage, 2 distribution centres in Chh. Sambhajinagar region), storage units, 3 vehicles, 3 IoT devices, 10 products (rohu, pomfret, prawns, surmai, banana, tomato, mango, spinach, onion, grapes) with limits, 6 backup buyers incl. 2 cold storages, default app_config.

---

## 8. ML Service Specification (FastAPI, internal only)

- Runs at `ml:8000` inside the Docker network only (never exposed through nginx). Every request needs `X-Internal-Token`.
- `GET /health`, `GET /v1/models` (versions from `registry.json`).
- Model files live in `ml/service/models/<model>/<version>/` (gitignored). Download with `scripts/fetch_models.sh` from S3 `models/` or GitHub release assets. `registry.json` (committed) records the active version, sha256 and metrics.

| Endpoint | Input | Output | Notes |
|----------|-------|--------|-------|
| `POST /v1/vision/grade` | `{batchId, category, imageUrls[3]}` (presigned GET URLs) | `{grade, confidence, defects:[{class, conf, box, areaPct}], perImage[], modelVersion, latencyMs}` | YOLOv8s ONNX, 640×640 letterbox, conf 0.35, NMS 0.5. Grade rule: no defect → A; minor defects < 10% item area → B; rot/mould or ≥ 10% → C. Fish classes: fresh, discoloured_skin, damaged_torn, sunken_eye. Produce: fresh, bruise, rot_mould, cut_crack, overripe |
| `POST /v1/shelf-life/predict` | `{items:[{batchId, productCode, category, grade, hoursSinceHarvest, meanTempC, degreeMinutesAbove, humidityPct, ethylenePpm, shockEvents}]}` | `{results:[{batchId, remainingH, survivalCurve:[{h,p}], method, modelVersion}]}` | lifelines `CoxTimeVaryingFitter` or `CoxPHFitter` on exposure features; remaining = t where S(t)=0.5 minus elapsed. Fallback Q10: `remaining = baseShelfLife × Q10^((refTemp − meanTemp)/10) − elapsed`, clamped ≥ 0. Must answer < 1 s |
| `POST /v1/forecast/run` | `{siteIds, productIds, startDate, horizonDays:7}` | `{runId, rows:[{siteId, productId, date, predictedKg, lowerKg, upperKg}], modelVersion}` | LSTM (2 layers 64/32, dropout 0.2, 30-day window) in ONNX + LightGBM (day of week, holiday/festival flag, mandi price, rainfall, temp, 7/14/30-day means). Ensemble weights from validation. Weather from Open-Meteo (`OPEN_METEO_URL`, no key) |
| `POST /v1/routes/optimize` | `{mode: INITIAL\|REPLAN, depot, vehicles:[{id, capacityKg, start:{lat,lng}, shiftEnd}], stops:[{id, lat, lng, demandKg, windowStart, windowEnd, serviceMin, shelfLifeH, mustKeepVehicle?}], fixedPrefix?}` | `{routes:[{vehicleId, stops:[{id, eta}], distanceKm}], fitness, latencyMs}` | DEAP GA: chromosome = stop permutation + vehicle split; fitness = distance + 1000×late-min + 5000×overload + spoilage-risk penalty (late beyond shelf life); pop 100, gens 200, OX crossover 0.8, swap mutation 0.1, tournament 3; early stop after 30 gens with no gain; hard limit 8 s. Travel matrix from `ROUTING_PROVIDER` |
| `POST /v1/routes/baseline` | same | same | OR-Tools VRPTW for comparison tests only |

**Training (`ml/training/`, not deployed):**
- Vision: Ultralytics YOLOv8s, 100 epochs, batch 16, SGD lr 0.01, augmentations (flip, HSV, blur). Datasets: Kaggle "Fruits fresh and rotten for classification", FruitNet (Indian fruits), Kaggle "A Large-Scale Fish Dataset", plus own photos (target ~1,500) labelled in Roboflow/CVAT, split 70/20/10. Export `yolo export format=onnx imgsz=640 opset=12`.
- Shelf-life: build a dataset from published storage studies + own controlled storage test (3 temperatures, checks every 12 h). Document the source of every row in `ml/training/shelf_life/DATA_SOURCES.md`. If own data is not ready, ship the Q10 fallback as the active method and record this in TESTING.md.
- Forecast: Agmarknet (data.gov.in API key `DATA_GOV_IN_KEY` or manual CSV), Open-Meteo history, simulated sales generator (`simulate_sales.py`, seeded). Time split: last 3 months = test.
- Routing: Solomon VRPTW instances (C101, R101, RC101) + a Chh. Sambhajinagar test case (10 vehicles, 50 stops).
- Each training script writes `metrics.json`. `scripts/register_model.py` updates `registry.json`.

---

## 9. IoT Simulator and Telemetry Pipeline

### 9.1 Simulator (`simulator/sim.py`)
- `python sim.py --devices 20 --scenario scenarios/reefer_failure.yaml --broker mqtts://host:8883 --interval 60 --speedup 10`
- Publishes to `iccms/telemetry/<deviceCode>` (QoS 1), each device with its own MQTT username/password (from seed).
- Scenarios: `normal`, `temp_drift_recoverable`, `reefer_failure`, `shock_event`, `ethylene_buildup`, `network_dropout` (buffer, then burst-send with original timestamps), `beacons` (pallet movement at sites). Moves the truck along the trip's route (fetched from the API with a sim service account) so positions match.
- `--format binary` sends the binary packet (below).

### 9.2 Packet formats (SYN-01)
JSON: `{"d":"DEV-001","ts":"2026-11-13T10:00:00Z","t":3.4,"h":88,"ax":0.01,"ay":0.02,"az":0.98,"g":1.1,"e":2.5,"lat":19.87,"lng":75.34,"r":1,"sp":2.0,"do":0,"b":81}`
Binary (little-endian, 40 bytes; documented in `simulator/binary_format.md`): `u8 version=1 | u8 flags(bit0 reefer_on, bit1 door_open) | u16 battery×10 | u32 epoch_s | i16 temp×100 | u16 hum×100 | i16 ax×1000 | i16 ay×1000 | i16 az×1000 | u16 shock×100 | u16 ethylene×100 | i16 setpoint×100 | i32 lat×1e6 | i32 lng×1e6 | u32 crc32(first 36 bytes)`. Bad CRC → drop + count the metric.

### 9.3 Pipeline
Mosquitto (password file + ACL: device can publish only to its own topic, TLS 8883) → **mqtt-bridge consumer** (inside `worker`) subscribes `iccms/telemetry/+`, decodes, validates, attaches `vehicleId/tripId` (Redis cache), produces to Kafka `truck-telemetry` (key = deviceCode). Consumers (separate consumer groups): `telemetry-writer` → InfluxDB batch writes (flush 1 s or 500 points), `threshold-processor` (Section 6.5), `exposure-aggregator` (updates `batch_exposure` every 5 min). Kafka topics: 3 partitions, retention 72 h: `truck-telemetry`, `quality-scans`, `order-transactions`, `alerts`.

### 9.4 Real hardware spec (design-only, for the report)
Reefer pod: 4G/5G with NB-IoT fallback, temp probe ±0.1 °C (−30 to +40 °C), capacitive RH, 3-axis accelerometer, electrochemical C₂H₄ 0–100 ppm with a hydrophobic membrane, Li-SOCl₂ battery ≥ 3 years, IP67. RFID: HF 13.56 MHz / UHF passive chemical-resistant tags + gate readers. Dock camera 4K60 + Jetson-class edge accelerator.

---

## 10. Mobile Application Specification (Flutter)

### 10.1 Stack (pin versions in `pubspec.yaml`; add nothing else without a DECISIONS entry)
Flutter latest stable 3.x (pin it via `.fvmrc` + README) · `supabase_flutter` (auth only) · `google_sign_in` (manager flavor only, native Google sign-in → `signInWithIdToken`) · `flutter_riverpod` · `go_router` · `dio` · `drift` + `sqlcipher_flutter_libs` · `flutter_secure_storage` · `socket_io_client` · `firebase_core`, `firebase_messaging`, `firebase_crashlytics` · `flutter_local_notifications` · `flutter_map` + `latlong2` · `geolocator` · `flutter_foreground_task` · `nfc_manager` · `mobile_scanner` · `camera` · `flutter_image_compress` · `signature` · `record` · `speech_to_text` · `flutter_tts` · `print_bluetooth_thermal` + `esc_pos_utils_plus` · `connectivity_plus` · `package_info_plus` · `device_info_plus` · `crypto` · `permission_handler` · `url_launcher` · `fl_chart` (manager only) · `animations` · `intl` + `flutter_localizations` · `path_provider` · `share_plus` · `uuid`.

### 10.2 Architecture
- **Layers per feature:** `data/` (API client + DAO + repository) → `providers/` (Riverpod notifiers, state = `AsyncValue`) → `screens/` + `widgets/`. No business logic in widgets.
- **core/auth:** `AuthRepository` wraps `supabase_flutter` (session stored securely by the SDK with a `flutter_secure_storage`-backed `LocalStorage`; auto refresh ON). It exposes `signInWithPhoneOtp(phone)`, `verifyOtp(phone, code)`, `signInWithGoogle()` (manager: native on Android, `signInWithOAuth` redirect on web), `signInWithEmail(email, password)`, `resetPassword(email)`, `signOut()`. After every sign-in → `POST /me/session` → `GET /me`. A 403 `WRONG_APP_FOR_ROLE` / `NOT_REGISTERED` → sign out + clear message. Unverified email → "Check your inbox" screen with a Resend button.
- **core/network:** one `ApiClient` (dio) with interceptors: the current Supabase access token as the bearer (on 401, call `refreshSession()` once with a single-flight lock, then retry once), headers from 6.1, retry with backoff (GET only, 3 tries), `426 → UpgradeRequired` stream → forced update screen, error mapping to `AppException(code, message)`.
- **core/storage:** drift DB encrypted with a key generated on first run and stored in secure storage. Tables: `cached_masters`, `cached_trips`, `cached_routes`, `cached_batches`, `outbox_ops`, `pending_files`, `kv`.
- **core/sync (outbox):** every write = a local transaction (entity + `outbox_op` with `clientOpId`, `capturedAt`). The sync engine runs on connectivity regain, on app resume, and every 60 s while online (and in the driver foreground service). Files upload first (presign → PUT); then `/sync` in chunks of 50. Retry with exponential backoff (max 30 min). Permanent failures (4xx except 408/429) → "Needs attention" in the Sync Queue screen. Nothing is deleted locally until the server confirms it.
- **core/realtime:** Socket.IO with auto-reconnect; events update Riverpod state. FCM data messages are handled the same way when the app is in the background.
- **Loading/error/empty states:** every list/detail uses a shared `AsyncView` widget: skeleton loader → content, plus an empty-state illustration + action, and an error card with Retry. Offline banner when there is no connectivity. Stale-data label "Updated 3 min ago".
- **Validation:** shared validators in `core/utils/validators.dart` with ranges from the products master (FO-NFR-07). Inline error text under the field.
- **Localisation:** ARB files en/hi/mr. Every user-facing string through `AppLocalizations`. Language picker on the login screen + settings.
- **Accessibility:** `textScaler` up to 2.0 without overflow (test it), semantics labels, min 48 dp targets (56 dp in driver/operator), colour never the only signal (icons + text).

### 10.3 Shared screens (`shared/screens/`)
Splash (init, session restore, update check, mandatory gate) · Login, shown per flavor: driver/operator = phone (+91 prefix) + language picker → OTP screen (6 boxes, auto-read where Android allows it, resend after 30 s); manager = "Continue with Google" + email/password + "Forgot password" + "Use phone OTP instead" link · Verify-email screen (manager) · Updates (Section 12) · Settings (language, theme, sync status, about, logout) · Sync Queue · Permission rationale sheets.

### 10.4 Operator APK screens (`apps/operator/`)
1. **Home:** site name, today's counts (registered/graded/stored/dispatched), pending sync badge, big quick actions: New Fish Batch, New Produce Batch, Receive, Load Truck.
2. **New Batch wizard** (stepper, state saved at every step, resumable): Form (FO-FR-02/03/04, voice input on numeric fields) → Tag (NFC tap / QR scan / RFID wedge text field) → Photos (guided camera overlay: top, side, close-up; compress per FO-NFR-04) → Grade (spinner up to 5 s; result card A/B/C with defects + confidence + Dispute; offline → "Grading queued", the grade arrives by push later) → Storage path (unit recommendation + confirm) → Label (print / share image) → Done (< 60 s target, FO-NFR-03).
3. **Batch list:** status chips filter, search, infinite scroll.
4. **Batch detail:** timeline (trace events), grade, shelf life, images, Edit (within 30 min) / Request edit.
5. **Receive:** scan → batch summary → condition checklist → damage photos → Accept / Partial (kg) / Reject (reason).
6. **Load truck:** pick today's trip → scan batches (counter, wrong-batch warning if not allocated to the trip) → confirm.
7. **Printer setup:** Bluetooth scan/pair/test print.
- RFID abstraction: `TagReader` interface → `NfcTagReader`, `QrTagReader`, `WedgeTagReader` (captures keyboard input ending with Enter).

### 10.5 Driver APK screens (`apps/driver/`)
1. **Today:** trip card (code, vehicle, batch count, stops with windows) → Pre-trip check → Start Trip.
2. **Pre-trip check:** 3 toggles + setpoint input, saved with timestamp (DA-FR-03).
3. **Active trip (main):** map (route polyline, truck, stops), next stop card (name, ETA, window), **Navigate** button (Google Maps intent `google.navigation:q=lat,lng`, fallback to a geo: URL), cargo strip (temp, humidity, lowest shelf life with colour + icon), SOS button, Report Incident button.
4. **Cargo status:** per-batch rows (product, grade, temp, shelf-life countdown).
5. **Critical alert screen:** full-screen; alarm sound (looped until ack, max 2 min, then every 30 s); TTS in the chosen language; instructions (driver fix); big Acknowledge button.
6. **Reroute proposal:** old stop vs new stop, reason, extra km/ETA, Accept (Decline only for non-critical replans).
7. **Report incident:** 2-tap grid (Delay, Breakdown, Accident, Road block, Reefer fault) → optional photo / voice note (max 60 s) → send (queued offline).
8. **Stop / PoD:** Arrive → scan each crate → outcome per batch (Accepted / Partial kg / Rejected + reason) → receiver name → signature pad → photo → Submit (queued offline).
9. **History + pending uploads.**
- **Foreground service** while a trip is active: GPS every `gpsIntervalSec` (30) batched to the outbox, sync, socket keep-alive. Persistent notification "Trip in progress".
- **Speed lock (DA-NFR-08):** if GPS speed > 10 km/h → overlay blocks text input and non-essential actions. Only Acknowledge, Accept Reroute, SOS and Navigate stay active.
- **Offline (DA-NFR-01):** on trip start, cache the trip, route, stops and batch data, and pre-download map tiles for the corridor (zoom 10–15, bounding box of the route + 2 km buffer, max 60 MB) through a disk-caching `TileProvider` in `core/` (custom, no GPL packages).

### 10.6 Control Tower (manager) APK + web (`apps/manager/`)
Responsive: phone = bottom navigation; tablet/web ≥ 840 px = navigation rail + multi-pane layout.
1. **Dashboard:** KPI cards (active trips, open critical alerts, at-risk batches < 12 h, deliveries today, spoilage avoided kg), live map of vehicles (socket `vehicle.position`).
2. **Trips:** list + detail (route versions, stops, telemetry line chart with safe band, events, PoD, emissions).
3. **Alerts & incidents:** live list, ack/resolve, incident detail with decision log, offers status, manual action buttons.
4. **Forecast:** site + product selectors, 7-day bar chart with range whiskers.
5. **Planning:** Run planner → draft orders table (edit qty/destination) → Approve → Build routes → assign driver/vehicle.
6. **Approvals:** edit requests, grade disputes.
7. **Buyers & cold storages:** CRUD with an opening-hours editor and product multi-select.
8. **Masters & users** (ADMIN only; hidden for MANAGER, and enforced server-side).
9. **Remote config** (ADMIN).
10. **Reports:** compliance per batch (opens the HTML report), traceability CSV, emissions, reefer health.
11. **App releases:** read-only list per flavor (from `/app/updates` history).
- Manager module must not depend on mobile-only plugins (NFC, camera, foreground service). Use only web-safe packages, so `flutter build web` works. It has no offline outbox (online-only, cached reads).

---

## 11. Dashboard-Specific APKs (one codebase, Android product flavors)

| Flavor | App name | applicationId | Entry point | Roles allowed | Signature accent |
|--------|----------|---------------|-------------|---------------|------------------|
| `driver` | I-CCMS Driver | `in.iccms.driver` | `lib/main_driver.dart` | DRIVER | Glacier Cyan |
| `operator` | I-CCMS Operator | `in.iccms.operator` | `lib/main_operator.dart` | OPERATOR | Fresh Leaf |
| `manager` | I-CCMS Control Tower | `in.iccms.manager` | `lib/main_manager.dart` | MANAGER, ADMIN | Indigo |

**How isolation works**
- Each `main_<flavor>.dart` calls `bootstrap(AppFlavorConfig(flavor: ..., router: <flavor>Router, theme: ...))` and imports **only** its `apps/<flavor>/router.dart`. Dart AOT tree-shaking removes the code of other dashboards from the binary because it is never imported.
- `android/app/build.gradle(.kts)`: `flavorDimensions "app"` with the three `productFlavors`, each with its `applicationId`, `resValue "string", "app_name", ...`, and its own launcher icon in `src/<flavor>/res/mipmap-*`.
- Per-flavor `src/<flavor>/AndroidManifest.xml` merges only the needed permissions: driver → `ACCESS_FINE_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `RECORD_AUDIO`, `CAMERA`; operator → `CAMERA`, `NFC`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, `RECORD_AUDIO`; manager → `POST_NOTIFICATIONS`. All → `INTERNET`, `REQUEST_INSTALL_PACKAGES`.
- Per-flavor `google-services.json` in `src/<flavor>/` (gitignored; CI writes it from secrets).
- **Static check** `scripts/check_flavor_isolation.sh`: fails if any file in `lib/apps/X/` imports `apps/Y/`, or if `core/`/`shared/` import `apps/`.
- **Binary check** `scripts/verify_apk_isolation.sh <flavor>`: each module defines `const kModuleTag = 'iccms-module-<flavor>'`, used in its router. The script unzips the built APK and runs `strings lib/arm64-v8a/libapp.so | grep iccms-module-`. It must show only its own tag.
- Server side, the role ↔ flavor map at login + `aud` claim + RolesGuard (Section 6.3) mean a modified APK still gets nothing extra.

**Versioning:** `release/versions.json` holds an independent `versionName`, `versionCode` and `minSupportedVersionCode` per flavor. versionCode only increases. `pubspec.yaml` version is not used for releases; the build script passes `--build-name/--build-number`.

**Build commands**
```bash
cd mobile
flutter pub get && dart run build_runner build --delete-conflicting-outputs
# debug run on device
flutter run --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/dev.json
# release APK (script reads release/versions.json, applies signing, prints sha256)
../scripts/build_apk.sh driver   prod
../scripts/build_apk.sh operator prod
../scripts/build_apk.sh manager  prod
# what the script runs:
flutter build apk --release --flavor driver -t lib/main_driver.dart \
  --target-platform android-arm,android-arm64 \
  --build-name=$VERSION_NAME --build-number=$VERSION_CODE \
  --dart-define-from-file=env/prod.json --obfuscate --split-debug-info=build/symbols/driver
# output: build/app/outputs/flutter-apk/app-driver-release.apk → renamed dist/iccms-driver-<ver>-<code>.apk
# web console
flutter build web --release -t lib/main_manager.dart --dart-define-from-file=env/prod.json --base-href /console/
```
`env/dev.json` / `env/prod.json` hold only non-secret values: `API_BASE_URL`, `WS_URL`, `UPDATE_CHANNEL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (the anon/publishable key is safe in clients; **never** the service role key), `GOOGLE_WEB_CLIENT_ID` (manager).
Google sign-in on Android needs an OAuth "Android" client in Google Cloud for `in.iccms.manager` with **both the debug and the release signing SHA-1**. Record the SHA-1 values in BUILD_GUIDE.md.

**Signing:** one upload keystore for all flavors (package IDs differ, so no conflict). `android/key.properties` (gitignored) points to a keystore outside the repo. CI gets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. **Keep two offline backups of the keystore. If it is lost, installed apps can never be updated.** Record the signing certificate SHA-256 in `docs/BUILD_GUIDE.md`.

---

## 12. In-App Update System + GitHub Releases

### 12.1 What needs what

| Change type | Delivery | Needs a new APK? |
|-------------|----------|------------------|
| Backend logic, APIs, bug fixes on the server | `scripts/deploy.sh` | No |
| AI model versions | Upload model + update `registry.json` + restart ml | No |
| Thresholds, timers, emission factor, feature flags, master lists, buyers | Remote config / masters (manager app or API) | No |
| Screens, navigation, Flutter/Dart code, native plugins, permissions, icons | New APK through GitHub Release + in-app updater | **Yes** |

### 12.2 Release pipeline
1. `scripts/release.sh <flavor> <major|minor|patch> [--beta] [--mandatory] [--min-supported <code>]` bumps `release/versions.json`, creates `release/notes/<flavor>-<ver>.md` from a template (sections `### New features`, `### Improvements`, `### Bug fixes`), and commits `release(<flavor>): v<ver> (<code>)` + tag `<flavor>-v<ver>`. The developer edits the notes before pushing the tag.
2. `.github/workflows/release-android.yml` (on tag `driver-v*|operator-v*|manager-v*`): set up Flutter → write keystore + google-services from secrets → `scripts/build_apk.sh <flavor> prod` → `scripts/verify_apk_isolation.sh` → compute `sha256` and size → read the cert SHA-256 with `apksigner verify --print-certs` → create a GitHub Release in `GITHUB_RELEASES_REPO` (prerelease if beta) with the asset `iccms-<flavor>-<ver>-<code>.apk`, and a body = notes + a metadata comment:
   `<!-- iccms-release {"flavor":"driver","versionName":"1.3.0","versionCode":13,"minSupportedVersionCode":10,"mandatory":false,"channel":"stable","sha256":"…","sizeBytes":23456789,"signingCertSha256":"…","applicationId":"in.iccms.driver"} -->`
3. The GitHub `release` webhook → `POST /webhooks/github` (HMAC verified) → sync job. Backup: a BullMQ repeatable job polls `GET /repos/{repo}/releases?per_page=30` every 15 min with `If-None-Match` (ETag), using a fine-grained read-only `GITHUB_TOKEN` (5,000 req/h; 304 responses don't count against the limit). It parses the metadata, upserts `app_releases`, and marks missing/deleted releases `is_active=false`.
4. Phones never call the GitHub API. They call `GET /api/v1/app/updates` and download the `apk_url` (browser_download_url; public releases repo). If the releases repo is private, set `UPDATE_DOWNLOAD_PROXY=true` → backend endpoint `GET /app/updates/:id/download` streams the asset with the token (supports `Range`).

### 12.3 Update API contract
`GET /api/v1/app/updates?flavor=driver&channel=stable&versionCode=12` →
```json
{"current":{"versionCode":12,"supported":true},
 "latest":{"versionName":"1.3.0","versionCode":13,"publishedAt":"…","sizeBytes":23456789,"sha256":"…",
           "signingCertSha256":"…","mandatory":false,"apkUrl":"…","features":[],"improvements":[],"fixes":[],"notesMd":"…"},
 "mustUpdate":false,
 "history":[{"versionName":"1.2.0","versionCode":12,"publishedAt":"…","features":[],"improvements":[],"fixes":[]}]}
```
`mustUpdate = versionCode < minSupportedVersionCode(latest stable) OR any newer release between current and latest is mandatory`. Only releases with the same `flavor` are ever returned (and the beta channel includes stable).

### 12.4 App behaviour (`core/updates/`)
- Check on splash, on resume (at most once every 6 h), and from **Updates** in settings (manual "Check now").
- **Updates screen:** current version + build, channel toggle ("Receive beta updates", off by default), latest card (version, date, size, mandatory badge, features/improvements/fixes lists), Download button, progress ring with MB/s and percent, states: `idle → checking → available → downloading → verifying → readyToInstall → installing → installed/failed`, and a history list of past releases with notes.
- **Mandatory:** a blocking screen after splash with only Update (and Exit). The 426 response from any API also opens it.
- **Download:** dio to `getApplicationSupportDirectory()/updates/<code>.apk.part`, resume with a `Range` header after network loss, max 3 auto-retries, then a manual Retry. Low-storage check (needs size × 2 free).
- **Verify before install:** (1) SHA-256 equals the manifest; (2) the native `ApkInstallerPlugin.inspect(path)` uses `PackageManager.getPackageArchiveInfo(..., GET_SIGNING_CERTIFICATES)` to check that `packageName == context.packageName`, `versionCode > installed`, and the signing cert SHA-256 == the installed app's cert. Any mismatch → delete the file, show "Incompatible update", and report it through `/app/updates/installed` with status `REJECTED_INCOMPATIBLE`.
- **Install (Kotlin, `ApkInstallerPlugin`):** if `!packageManager.canRequestPackageInstalls()` → open `ACTION_MANAGE_UNKNOWN_APP_SOURCES` for this package and resume after return. Then use the `PackageInstaller` session API (`MODE_FULL_INSTALL`, write the APK, commit with a `PendingIntent` to a broadcast receiver). Statuses (`PENDING_USER_ACTION` → launch the confirm intent, `SUCCESS`, `FAILURE_*`) go to Flutter through an `EventChannel`. Android always shows its own confirmation. **No silent install is possible and none is attempted.** Same package + same signing key = the app updates in place, data kept, no uninstall.
- After the update, the app starts fresh. On the next launch, it detects the higher versionCode → shows a one-time "Updated to vX" sheet, posts `installed`, and deletes old update files.

---

## 13. Design System and Motion

**Direction:** "Cold-chain fresh". Deep ocean blues for trust and cold, fresh leaf green for produce and safety, one bright glacier cyan accent. Clean surfaces, strong status colours, big readable numbers. All tokens live in **`lib/core/theme/app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_theme.dart`**. No hex values anywhere else (lint check in CI: grep `Color(0x` outside `core/theme`).

### 13.1 Colours

| Token | Light | Dark |
|-------|-------|------|
| primary (Deep Ocean) | `#0B4F6C` | `#4FC3E8` |
| onPrimary | `#FFFFFF` | `#00222F` |
| primaryContainer | `#D4ECF5` | `#0F3A4C` |
| secondary (Fresh Leaf) | `#2E9D5B` | `#5CCB8A` |
| accent (Glacier Cyan) | `#12C2E9` | `#12C2E9` |
| background | `#F4F8FA` | `#0A141A` |
| surface | `#FFFFFF` | `#111E26` |
| surfaceVariant | `#E8F0F4` | `#18303B` |
| outline | `#D0DCE3` | `#24404D` |
| textPrimary | `#0F1C24` | `#E6F1F5` |
| textSecondary | `#55666F` | `#93A8B3` |
| status.safe / grade A | `#15803D` | `#4ADE80` |
| status.watch / grade B | `#B45309` | `#FBBF24` |
| status.critical / grade C | `#B91C1C` | `#F87171` |
| status.info | `#1D4ED8` | `#60A5FA` |
| flavor accent driver / operator / manager | `#12C2E9` / `#2E9D5B` / `#5B5BD6` | `#12C2E9` / `#5CCB8A` / `#8B8BF0` |

Text-on-background pairs must meet WCAG AA 4.5:1. Add a unit test that computes contrast for every pair used. Default theme: driver = follows system (dark at night is useful in the cab), operator = light high-contrast (sunlight), manager = system.

### 13.2 Typography
Bundle the fonts (offline, OFL licence) in `assets/fonts/`: **Poppins** (headings; supports Devanagari) and **Noto Sans + Noto Sans Devanagari** (body, fallback). Numbers on telemetry use `FontFeature.tabularFigures()`.

| Style | Size/Line | Weight |
|-------|-----------|--------|
| display | 32/40 | Poppins 600 |
| headline | 24/32 | Poppins 600 |
| title | 20/28 | Poppins 600 |
| subtitle | 16/24 | Noto 600 |
| body | 15/22 | Noto 400 |
| bodySmall | 13/18 | Noto 400 |
| label | 13/16 | Noto 500 |
| metric (temp, shelf life) | 28/32 | Poppins 600, tabular |

### 13.3 Components and layout
- Spacing scale 4/8/12/16/24/32/48. Screen padding 16 (phone) / 24 (tablet). Radius: inputs/chips 10, buttons 12, cards 16, sheets 20.
- Buttons: height 52 (56 in driver/operator), filled primary for the main action, tonal for secondary, outlined for tertiary, red filled only for SOS/Reject. One primary button per screen.
- Cards: surface, 1 px outline, elevation 0–1, optional 4 px left status strip (safe/watch/critical).
- Inputs: filled, label above, helper/error text below, unit suffix (kg, °C, %), mic icon for voice input on numeric fields.
- Navigation: Material 3 `NavigationBar` (max 4 tabs) on phones; `NavigationRail` ≥ 840 px (manager).
- Icons: Material Icons rounded variants (`Icons.*_rounded`), no extra icon package. Grade chips show the letter + icon + colour.
- Status: never colour alone; always icon + label.

### 13.4 Motion (package `animations` + implicit animations)
- Durations: micro 120 ms, standard 220 ms, emphasised 320 ms; curves `easeOutCubic` (enter), `easeInCubic` (exit).
- Screen transitions: `SharedAxisTransition` (horizontal) for wizard steps, `FadeThroughTransition` for tab switches, container transform for batch card → detail.
- Buttons: press scale 0.97 + ripple. Toggles: animated colour. List items: staggered fade/slide in (max 8 items, 30 ms stagger, first load only).
- Loading: custom shimmer skeletons (no package), max 1.5 s loop. Empty states: simple illustration with a subtle float.
- Data: shelf-life and temperature numbers animate with `TweenAnimationBuilder` (300 ms). Chart lines draw in once.
- Alerts: critical banner slides down + a 3-cycle pulse, then stays still (battery). Update download: animated progress ring; success check animation.
- Respect `MediaQuery.disableAnimations` (reduce motion = no transitions beyond fade). Driver app while moving: no decorative animation. Target 60 fps on a 2 GB device; check with the performance overlay in M12.

---

## 14. Security

- TLS 1.3/1.2 only at nginx (Mozilla intermediate config), HSTS, MQTT over TLS 8883. RDS connections with `sslmode=require`.
- Secrets only in `.env` (local, gitignored) and SSM `/iccms/prod/*` (production). `.env.example` is committed with placeholder values only.
- Passwords and OTPs are handled only by Supabase (never stored or logged by us). Random tokens are stored as SHA-256; device secrets as bcrypt. `SUPABASE_SERVICE_ROLE_KEY` and `HTTPSMS_API_KEY` live only in SSM/.env on the server.
- The httpSMS web dashboard and API are reachable only through nginx on `sms.<domain>` (TLS). The dashboard is limited to the developer's IP in nginx (`allow <ip>; deny all;` on `/`), except the API routes the phone and backend use (`/v1/`).
- Least privilege: DB roles (D-15), IAM role scoped to one bucket, its SSM path and log groups; security groups (Section 17.3).
- Uploads: presigned with content-type + size limits; server checks that the key prefix matches the purpose and owner before attaching.
- Input validation everywhere (DTOs, zod for env). Parameterised queries only (Prisma; no string-built SQL).
- Mobile: tokens in `flutter_secure_storage`, SQLCipher DB, `android:allowBackup="false"`, `usesCleartextTraffic=false` in release, obfuscated builds, no secrets in `--dart-define`.
- Signed public links (trace HMAC, offer tokens with expiry, single-use).
- Audit log for all manager/admin writes and batch corrections.
- `npm audit --omit=dev`, `pip-audit`, `flutter pub outdated` in CI (report only; fix high severity).

---

## 15. Logging, Monitoring, Error Reporting

- Backend: pino JSON → stdout → Docker `awslogs` driver → CloudWatch log groups `/iccms/api`, `/iccms/worker`, `/iccms/ml`, `/iccms/nginx` (retention 14 days). Every log line has `requestId`.
- Metrics/health: `/health/ready`. Worker logs a heartbeat every minute (`consumerLag`, `queueDepth`). `scripts/disk_check.sh` (cron, 15 min) puts the custom metric `DiskUsedPct`.
- CloudWatch alarms → SNS topic `iccms-alerts` (email): EC2 `StatusCheckFailed` ≥ 1, EC2 CPU > 85% for 15 min, `DiskUsedPct` > 80%, RDS `FreeStorageSpace` < 2 GB, RDS CPU > 80% for 15 min.
- Mobile: Firebase Crashlytics (fatal + non-fatal with `AppException` codes), no PII in logs.
- Auth/SMS: count Send SMS Hook calls, httpSMS 202 vs failures, and delivery statuses. 3 failed OTP sends in a row → manager alert "SMS gateway down" + email. Supabase Auth logs are checked from the Supabase dashboard.
- ML: per-request latency logged; model version on every response.

---

## 16. Testing Strategy

| Layer | Tool | What |
|-------|------|------|
| Auth | Jest + Supabase dev project (test phone numbers, test Google/email accounts) or `supabase start` locally | JWKS verification, hook signature, role/flavor/device guards, admin create/invite/ban, verified-email gating |
| Backend unit | Jest | services: auth, RBAC guards, edit window, hash chain, threshold logic, incident classifier, diversion ranking, FEFO, update manifest logic |
| Backend API/e2e | Jest + supertest + docker compose test stack (Postgres, Redis, Kafka, Influx, mocked ML) | every endpoint group, auth/permission matrix (each role × each route group → expected 2xx/403), 426 behaviour, idempotent sync |
| DB | Prisma migrate reset + SQL checks | constraints, indexes exist, `iccms_app` cannot UPDATE/DELETE `trace_events` |
| ML | pytest | API contracts, grade rule, Q10 fallback, GA feasibility (capacity/time windows), latency budgets, model metrics recorded |
| Pipeline | simulator scenarios + assertions script `backend/test/pipeline/*.ts` | sensor → Influx ≤ 500 ms, breach → shelf-life ≤ 5 s, persist 15 min → alert, escalation 5 min, offer timeout 10 min (time-scaled via config) |
| Mobile unit/widget | flutter_test | validators, outbox ordering, sync retry, update state machine, theme contrast, text scale 2.0 golden checks |
| Mobile integration | integration_test on a real Android device/emulator | operator wizard offline → sync; driver trip → alert ack → reroute → PoD; manager planning flow |
| Builds | scripts | each flavor builds, isolation static + binary checks pass, APK size < 40 MB (driver), signing cert matches |
| Update system | real device | install v1 → publish v2 → in-app update without uninstall; tampered APK (wrong sha) rejected; other flavor's APK rejected; mandatory gate; interrupted download resumes |
| Deployment | curl/scripts on AWS | HTTPS, health ready, migrations, MQTT TLS from simulator, push/SMS delivery, backup + restore drill |
| Performance | autocannon (dev dependency) | p95 < 300 ms on key GETs at 50 concurrent; simulator 500 devices at 60 s intervals with no loss (production 10k = design target) |

Record each run in `docs/TESTING.md`: date, milestone, command, result (pass/fail counts), measured numbers, known issues.

---

## 17. AWS Infrastructure and Deployment

### 17.1 Resources (region `ap-south-1` Mumbai)

| Resource | Config | Approx. cost* |
|----------|--------|---------------|
| EC2 | `t3.large` (2 vCPU, 8 GB), Ubuntu 24.04 LTS, 40 GB gp3, 4 GB swap, Elastic IP | ~USD 60–70/month on-demand (stop it when not demoing) |
| RDS PostgreSQL 16 | `db.t4g.micro`, 20 GB gp3, single-AZ, encrypted, backups 7 days, not public | ~USD 15/month or free tier |
| S3 | 1 private bucket, SSE-S3, lifecycle (`tmp/` expire 7 d) | < USD 2 |
| SSM Parameter Store | standard SecureString | free |
| CloudWatch Logs + alarms + SNS | 14-day retention, 5 alarms | a few USD |
| Domain | any registrar or a free DNS subdomain; A records `api.`, `mqtt.`, `sms.` → Elastic IP | — |
| Supabase (outside AWS) | Auth only, region Mumbai, free tier to start | free tier (pauses when inactive) |
| httpSMS (on the same EC2) | self-hosted Docker stack + 1 dedicated Android phone with a SIM and an SMS pack | SIM plan cost |

*Check current prices in the AWS Pricing Calculator; record the actual numbers in DEPLOYMENT.md. **Not used (on purpose):** NAT Gateway, ALB, EKS, MSK, ElastiCache, Secrets Manager.

### 17.2 Network (default VPC — simple and enough)
RDS in the default VPC subnets with `--no-publicly-accessible`, reachable only from the EC2 security group. No NAT is needed (EC2 is in a public subnet).

### 17.3 Provisioning commands (AWS CLI v2; run from the developer machine, store outputs in `deploy/aws/outputs.env`, gitignored)

```bash
export AWS_REGION=ap-south-1 APP=iccms
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"

# Security groups
EC2_SG=$(aws ec2 create-security-group --group-name $APP-ec2-sg --description "I-CCMS app" --vpc-id $VPC_ID --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 22   --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 80   --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 443  --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 8883 --cidr 0.0.0.0/0
RDS_SG=$(aws ec2 create-security-group --group-name $APP-rds-sg --description "I-CCMS db" --vpc-id $VPC_ID --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 5432 --source-group $EC2_SG

# Secrets in SSM (generate, never type into files)
DB_MASTER_PW=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
aws ssm put-parameter --name /$APP/prod/DB_MASTER_PASSWORD --type SecureString --value "$DB_MASTER_PW"
for k in TRACE_SIGNING_KEY OFFER_TOKEN_SECRET ML_INTERNAL_TOKEN INFLUX_TOKEN MQTT_BRIDGE_PASSWORD DB_APP_PASSWORD DB_MIGRATOR_PASSWORD GITHUB_WEBHOOK_SECRET HTTPSMS_WEBHOOK_SECRET HTTPSMS_DB_PASSWORD; do
  aws ssm put-parameter --name /$APP/prod/$k --type SecureString --value "$(openssl rand -hex 32)"
done
# Add provider keys manually (all SecureString): GITHUB_TOKEN, SMTP_PASS, FIREBASE_CREDENTIALS_JSON,
#   SUPABASE_SERVICE_ROLE_KEY, SUPABASE_SEND_SMS_HOOK_SECRET, HTTPSMS_API_KEY (after 17.11 step 6),
#   HTTPSMS_FIREBASE_CREDENTIALS_JSON, HTTPSMS_TURNSTILE_SECRET
# Plain String params: SUPABASE_URL, SUPABASE_JWKS_URL, HTTPSMS_FROM_NUMBER

# RDS
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[].SubnetId' --output text)
aws rds create-db-subnet-group --db-subnet-group-name $APP-db-subnets --db-subnet-group-description "I-CCMS" --subnet-ids $SUBNETS
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[?starts_with(EngineVersion,'16')].EngineVersion" --output text  # pick latest 16.x
aws rds create-db-instance --db-instance-identifier $APP-db --engine postgres --engine-version <16.x> \
  --db-instance-class db.t4g.micro --allocated-storage 20 --storage-type gp3 --storage-encrypted \
  --master-username iccms_master --master-user-password "$DB_MASTER_PW" \
  --db-subnet-group-name $APP-db-subnets --vpc-security-group-ids $RDS_SG --no-publicly-accessible \
  --backup-retention-period 7 --deletion-protection --auto-minor-version-upgrade --db-name iccms
aws rds wait db-instance-available --db-instance-identifier $APP-db
RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier $APP-db --query 'DBInstances[0].Endpoint.Address' --output text)
aws ssm put-parameter --name /$APP/prod/DB_HOST --type String --value "$RDS_HOST"

# S3
BUCKET=$APP-files-$ACCOUNT_ID
aws s3api create-bucket --bucket $BUCKET --create-bucket-configuration LocationConstraint=$AWS_REGION
aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-lifecycle-configuration --bucket $BUCKET --lifecycle-configuration file://deploy/aws/s3-lifecycle.json
# CORS not needed for mobile PUT; add only if the web console uploads.

# IAM role for EC2 (policy file deploy/aws/ec2-policy.json: s3 Get/Put/List/Delete on $BUCKET/*,
#   ssm:GetParametersByPath on /iccms/prod/*, logs:CreateLogGroup/CreateLogStream/PutLogEvents/PutRetentionPolicy,
#   cloudwatch:PutMetricData, rds:CreateDBSnapshot on $APP-db)
aws iam create-role --role-name $APP-ec2-role --assume-role-policy-document file://deploy/aws/ec2-trust.json
aws iam put-role-policy --role-name $APP-ec2-role --policy-name $APP-ec2 --policy-document file://deploy/aws/ec2-policy.json
aws iam create-instance-profile --instance-profile-name $APP-ec2-profile
aws iam add-role-to-instance-profile --instance-profile-name $APP-ec2-profile --role-name $APP-ec2-role

# EC2
AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)
aws ec2 create-key-pair --key-name $APP-key --query KeyMaterial --output text > ~/.ssh/$APP-key.pem && chmod 400 ~/.ssh/$APP-key.pem
INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI --instance-type t3.large --key-name $APP-key \
  --security-group-ids $EC2_SG --iam-instance-profile Name=$APP-ec2-profile \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=40,VolumeType=gp3,Encrypted=true}' \
  --metadata-options HttpTokens=required --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$APP-app}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
EIP=$(aws ec2 allocate-address --query AllocationId --output text)
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP
# → point DNS A records api.<domain> and mqtt.<domain> to the Elastic IP

# Monitoring
TOPIC=$(aws sns create-topic --name $APP-alerts --query TopicArn --output text)
aws sns subscribe --topic-arn $TOPIC --protocol email --notification-endpoint <your-email>
aws cloudwatch put-metric-alarm --alarm-name $APP-ec2-status --namespace AWS/EC2 --metric-name StatusCheckFailed \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID --statistic Maximum --period 300 --evaluation-periods 1 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --alarm-actions $TOPIC
# repeat the pattern for CPU, DiskUsedPct (namespace ICCMS), RDS FreeStorageSpace, RDS CPU (scripts in deploy/aws/alarms.sh)
```

### 17.4 Server setup (on EC2, once)
```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install ca-certificates curl git nginx certbot python3-certbot-nginx postgresql-client unattended-upgrades fail2ban awscli jq
curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker ubuntu
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo mkdir -p /opt/iccms && sudo chown ubuntu:ubuntu /opt/iccms
git clone https://github.com/<OWNER>/<REPO>.git /opt/iccms/app
curl -o /opt/iccms/rds-global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
# DB roles (master password read from SSM, never echoed)
export PGPASSWORD=$(aws ssm get-parameter --name /iccms/prod/DB_MASTER_PASSWORD --with-decryption --query Parameter.Value --output text)
psql "host=$(aws ssm get-parameter --name /iccms/prod/DB_HOST --query Parameter.Value --output text) dbname=iccms user=iccms_master sslmode=require" \
  -v app_pw="$(aws ssm get-parameter --name /iccms/prod/DB_APP_PASSWORD --with-decryption --query Parameter.Value --output text)" \
  -v mig_pw="$(aws ssm get-parameter --name /iccms/prod/DB_MIGRATOR_PASSWORD --with-decryption --query Parameter.Value --output text)" \
  -f /opt/iccms/app/backend/prisma/sql/roles.sql
unset PGPASSWORD
# TLS
sudo cp /opt/iccms/app/deploy/nginx/iccms.conf /etc/nginx/sites-available/iccms && sudo ln -s /etc/nginx/sites-available/iccms /etc/nginx/sites-enabled/
sudo certbot --nginx -d api.<domain> -d mqtt.<domain> -d sms.<domain> --redirect -m <email> --agree-tos -n
echo 'deploy-hook: docker restart iccms-mosquitto' | sudo tee -a /etc/letsencrypt/cli.ini
```
`deploy/nginx/iccms.conf`: TLS, HSTS, gzip, `client_max_body_size 10m`. `/api/` and `/rt/` (WebSocket upgrade) → `127.0.0.1:3000`; `/t/` and `/offer/` → api; `/console/` → `/var/www/iccms-console` (SPA fallback); everything else 404.

### 17.5 Containers (`deploy/docker-compose.prod.yml`)
Services: `api` (port 127.0.0.1:3000), `worker`, `ml` (internal), `kafka` (apache/kafka 4.x KRaft, `KAFKA_HEAP_OPTS=-Xmx512m -Xms512m`, internal), `mosquitto` (0.0.0.0:8883 with Let's Encrypt certs mounted read-only), `influxdb` (2.7, internal, volume), `redis` (7, internal, AOF on, volume). All use `logging: driver: awslogs` with group `/iccms/<service>`, `restart: unless-stopped`, memory limits (api 768m, worker 768m, ml 1.5g, kafka 1g, influx 1g, redis 256m, mosquitto 64m). Env from `/opt/iccms/.env` (chmod 600). Containers run as non-root.

### 17.6 Deploy and update procedure
- `scripts/render_env.sh` → reads `aws ssm get-parameters-by-path --path /iccms/prod --with-decryption`, builds `DATABASE_URL=postgresql://iccms_app:<pw>@<host>:5432/iccms?sslmode=require` and `MIGRATION_DATABASE_URL` (migrator), writes `/opt/iccms/.env` (600).
- `scripts/deploy.sh <git-tag>`:
  1. `git fetch --tags && git checkout <tag>`; 2. `render_env.sh`; 3. `aws rds create-db-snapshot --db-snapshot-identifier iccms-pre-<tag>-<ts>` (only if new migrations exist); 4. `docker compose build api worker ml`; 5. `docker compose run --rm -e DATABASE_URL=$MIGRATION_DATABASE_URL api npx prisma migrate deploy`; 6. `docker compose up -d`; 7. download the console build from the `console-v*` release matching the tag and unzip it to `/var/www/iccms-console`; 8. poll `https://api.<domain>/api/v1/health/ready` for 90 s; 9. failure → `git checkout <previous tag>`, `docker compose up -d`, exit 1 (DB restore is manual from the snapshot if a migration broke data).
- Zero secrets in the repo; the deploy logs never print the env.
- Updates: tag `vX.Y.Z` for the backend → `ssh` → `scripts/deploy.sh vX.Y.Z`. Optional GitHub Action `deploy.yml` (manual trigger) that SSHes with a deploy key in secrets.

### 17.7 Backups and recovery
- RDS automated backups 7 days (point-in-time) + pre-deploy snapshots + `scripts/backup_db.sh` (cron daily 02:30 IST): `pg_dump -Fc` → `s3://<bucket>/backups/db/` (lifecycle keeps 30 days).
- `scripts/backup_influx.sh` weekly: `influx backup` → tar.gz → S3.
- **Restore drill (must be done once in M14):** `aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier iccms-db --target-db-instance-identifier iccms-db-restore --use-latest-restorable-time ...` → check row counts → switch the `DB_HOST` parameter → deploy → delete the old instance after verification. Also test `pg_restore` of a dump into a scratch DB.

### 17.8 Maintenance
Weekly: check alarms, disk, `docker system prune -f --filter until=168h`, `apt` updates (unattended for security). Monthly: rotate `HTTPSMS_API_KEY` and the Send SMS Hook secret (update SSM, then redeploy), check the gateway phone and SIM balance, review IAM and the Supabase user list, test a restore. `git pull` the pinned httpSMS tag only after reading its release notes. Certbot auto-renews (systemd timer); check with `sudo certbot renew --dry-run`.

### 17.9 Local development
`deploy/docker-compose.dev.yml` runs postgres:16, redis, kafka, influxdb, mosquitto (no TLS, 1883), ml. `backend/.env.example` → `.env`. Commands: `npm run start:dev` (api), `npm run worker:dev`, `npx prisma migrate dev`, `npx prisma db seed`, `python simulator/sim.py --broker mqtt://localhost:1883`. Phones on the same Wi-Fi use `env/dev.json` with the LAN IP.

### 17.10 Environment variables (backend; same names in SSM)
`NODE_ENV, PORT, APP_BASE_URL, CORS_ORIGINS, LOG_LEVEL, DATABASE_URL, MIGRATION_DATABASE_URL, REDIS_URL, KAFKA_BROKERS, INFLUX_URL, INFLUX_TOKEN, INFLUX_ORG, INFLUX_BUCKET, MQTT_URL, MQTT_BRIDGE_USERNAME, MQTT_BRIDGE_PASSWORD, ML_SERVICE_URL, ML_INTERNAL_TOKEN, SUPABASE_URL, SUPABASE_JWKS_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_SEND_SMS_HOOK_SECRET, TRACE_SIGNING_KEY, OFFER_TOKEN_SECRET, AWS_REGION, S3_BUCKET, FIREBASE_CREDENTIALS_JSON, SMS_PROVIDER (console|httpsms; console is refused when NODE_ENV=production), HTTPSMS_API_URL (internal: http://httpsms-api:8000, or https://sms.<domain>), HTTPSMS_API_KEY, HTTPSMS_FROM_NUMBER (E.164 of the gateway SIM), HTTPSMS_WEBHOOK_SECRET, SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM, ROUTING_PROVIDER, OSRM_URL, GOOGLE_MAPS_API_KEY, GITHUB_TOKEN, GITHUB_RELEASES_REPO, GITHUB_WEBHOOK_SECRET, UPDATE_DOWNLOAD_PROXY`. The env schema (zod) fails fast on missing values.

### 17.11 httpSMS (self-hosted SMS gateway on the same EC2)

httpSMS (github.com/NdoleStudio/httpsms, AGPL-3.0, used unmodified) turns an Android phone into an SMS gateway. The backend calls its HTTP API, httpSMS pushes the job to the phone through FCM, and the phone sends the SMS from its SIM.

**Before you start (one time)**
- A **dedicated Android phone + SIM** (not a personal number), with an SMS pack. Check the plan's daily SMS limit (many Indian prepaid plans cap SMS per day) and put that number in `docs/DEPLOYMENT.md`. Keep the phone on charge and on Wi-Fi + mobile data. Turn off battery optimisation for the httpSMS app.
- A **separate Firebase project** `iccms-httpsms`. httpSMS needs Email/Password sign-in with email enumeration protection turned off (per its docs), so don't do this on the main I-CCMS Firebase project. Download its service account JSON and the Android `google-services.json`.
- A Cloudflare Turnstile widget for `sms.<domain>` (site key + secret).
- SMTP: reuse the I-CCMS SMTP (httpSMS uses it to email when the phone goes offline).

**Install on EC2**
```bash
git clone https://github.com/NdoleStudio/httpsms.git /opt/iccms/httpsms
cd /opt/iccms/httpsms && git checkout <latest release tag>   # pin it; record the tag in DECISIONS.md
cp api/.env.docker api/.env && cp web/.env.docker web/.env && chmod 600 api/.env web/.env
# Fill api/.env: SMTP_*, FIREBASE_CREDENTIALS (contents of the httpsms service account JSON), GCP_PROJECT_ID=iccms-httpsms,
#   Turnstile secret, database/redis passwords from SSM (HTTPSMS_DB_PASSWORD). Fill web/.env: Firebase web config, Turnstile site key,
#   API base URL https://sms.<domain>. Use scripts/render_httpsms_env.sh (reads SSM) instead of typing secrets by hand.
```
- Read the repo's `docker-compose.yml` before running it. **Remap its ports so they don't clash with I-CCMS** (its web UI defaults to 3000, the same as our api): web → `127.0.0.1:3100`, api → `127.0.0.1:8100`; its database and cache stay internal (no host ports). Add memory limits (api 256m, web 256m, db 512m, cache 128m), `restart: unless-stopped`, and the `awslogs` driver with group `/iccms/httpsms`. Put these changes in an override file `deploy/httpsms/docker-compose.override.yml` kept in **our** repo, so the httpSMS clone stays untouched.
- Join httpSMS's API container to the I-CCMS Docker network (external network `iccms_net`) so the backend can call `http://httpsms-api:8000` without leaving the server.
- `docker compose -f docker-compose.yml -f /opt/iccms/app/deploy/httpsms/docker-compose.override.yml up -d --build`
- Do the **system user step** from the httpSMS README (insert the `users` row with the ID + API key the events queue expects, then restart the API container).

**nginx (`deploy/nginx/httpsms.conf`)**: `sms.<domain>` → `/` to `127.0.0.1:3100` (dashboard; `allow <developer-ip>; deny all;`), `/v1/` to `127.0.0.1:8100` (open, because the phone calls it). TLS from the certbot cert above.

**Gateway phone**
1. Build the httpSMS Android app from `android/` in Android Studio with the `iccms-httpsms` `google-services.json`, pointing it at `https://sms.<domain>`. Check the app/README for where the server URL is set; if it is a build constant, change only that constant and record it in DEPLOYMENT.md.
2. Install it on the gateway phone, sign in with the httpSMS dashboard account, and grant the SMS permissions.
3. In the dashboard, copy the API key → SSM `HTTPSMS_API_KEY`. Put the SIM's number in `HTTPSMS_FROM_NUMBER`.
4. Optional: in the dashboard, add a webhook for delivery events → `https://api.<domain>/api/v1/hooks/httpsms` with the `HTTPSMS_WEBHOOK_SECRET` header.
5. Smoke test from EC2:
   `curl -s -X POST http://127.0.0.1:8100/v1/messages/send -H "x-api-key: $HTTPSMS_API_KEY" -H "Content-Type: application/json" -d '{"from":"'$HTTPSMS_FROM_NUMBER'","to":"+91XXXXXXXXXX","content":"I-CCMS test"}'` → 202, then the SMS arrives.

**Known limits (put them in TESTING.md as constraints, not bugs)**
- If the gateway phone is offline, no OTPs go out. Alert: httpSMS's own offline email + our worker checks the last delivered SMS time and raises a manager alert if OTP sends fail 3 times in a row.
- Sending speed is limited by httpSMS back-pressure settings and by the SIM/operator. Fine for a prototype, not for production scale.
- Sending a lot of automated SMS from a personal-type SIM can get the SIM blocked by the operator. Keep volume low (OTP + critical fallback only); push notifications stay the main alert channel. For a real launch, swap the `SmsService` provider for a DLT-registered SMS gateway; nothing else changes.

---

## 18. Documentation Tracking

| File | Content (keep it concise, no duplication) | Update when |
|------|--------------------------------------------|-------------|
| `README.md` | Section 22 | M1 skeleton, M15 final |
| `docs/PROJECT_STATUS.md` | milestone table (status, date, commit hash), current milestone, blockers, next steps | end of every milestone |
| `docs/CHANGELOG.md` | Keep-a-Changelog style per milestone/release | every milestone and release |
| `docs/ARCHITECTURE.md` | diagram, modules, folder map, data flow | M1, then on structural change |
| `docs/DATABASE.md` | tables, relations, migrations list, roles | M2, then per migration |
| `docs/API_DOCUMENTATION.md` | endpoints, auth, request/response examples, error codes; also Swagger at `/api/docs` (non-prod only) | each backend milestone |
| `docs/DEPLOYMENT.md` | Section 17, actual resource IDs (no secrets), costs | M14 |
| `docs/BUILD_GUIDE.md` | flavor builds, signing, isolation checks, cert fingerprint | M10, M15 |
| `docs/UPDATE_SYSTEM.md` | Section 12, release how-to, troubleshooting | M15 |
| `docs/TESTING.md` | test commands, results per run, measured metrics, known issues | every milestone |
| `docs/DECISIONS.md` | D-01…D-20 + new ones (date, decision, reason, alternatives) | when decided |
| `docs/DEVELOPMENT_LOG.md` | per milestone: implemented, files created/modified/removed, tests + results, bugs fixed, limitations, pending, repro commands | end of every milestone |

---

## 19. Git and Version Control Rules

1. `git init` in M1. Branch `main`. One commit per completed milestone (more small commits inside a milestone are allowed; the milestone-closing commit is mandatory).
2. **Commit after every completed milestone without asking the user.**
3. Commit message format: `feat(mNN): <summary>` + body listing requirement IDs covered, the test summary, and docs updated. Release commits: `release(<flavor>): vX.Y.Z (code)`.
4. **Do not add any AI author, co-author, `Co-Authored-By`, "Generated with" or similar trailer lines. Do not change `user.name`/`user.email`; commit as the repository's configured user.**
5. Never commit: `.env*` (except `.env.example`), keystores, `key.properties`, `google-services.json`, model weights, datasets, `deploy/aws/outputs.env`, `*.pem`. The `.gitignore` in M1 covers these. Before each commit run `git status` and `scripts/secret_scan.sh` (simple grep for key patterns: `AKIA`, `-----BEGIN`, `password=`, `ghp_`, `github_pat_`).
6. Update `PROJECT_STATUS.md`, `CHANGELOG.md`, `DEVELOPMENT_LOG.md`, `TESTING.md` before the milestone commit.
7. Tag milestones: `m01` … `m15`. Tag backend releases `vX.Y.Z`, app releases `<flavor>-vX.Y.Z`, console `console-vX.Y.Z`.

---

## 20. Milestones (exactly 15)

> Format per milestone: Objective · Tasks · FE/BE/DB · Files · Tests · Done when · Commit.

### M1 — Repository, Architecture and Tooling
- **Objective:** a working monorepo skeleton everyone can run.
- **Tasks:** create the layout in 5.2; `.gitignore`, `.editorconfig`; backend NestJS app with `api` and `worker` entry points, env schema (zod), pino logging, error filter, `/health`; ml FastAPI skeleton with `/health` + internal-token middleware; Flutter project with 3 flavors (empty routers + `kModuleTag`), entry points, `bootstrap.dart`; `deploy/docker-compose.dev.yml`; `scripts/check_flavor_isolation.sh`, `scripts/secret_scan.sh`; CI `ci.yml` (backend lint+test, ml pytest, flutter analyze+test, isolation check); all docs files from Section 18 created with headings; DECISIONS D-01…D-20.
- **BE:** skeleton. **FE:** flavors build in debug. **DB:** none.
- **Files:** `backend/src/{main,worker,app.module,worker.module}.ts`, `backend/src/config/*`, `ml/service/app/main.py`, `mobile/lib/main_*.dart`, `mobile/android/app/build.gradle(.kts)`, `deploy/docker-compose.dev.yml`, `.github/workflows/ci.yml`, `docs/*`.
- **Tests:** `docker compose -f deploy/docker-compose.dev.yml up -d` all healthy; `curl :3000/api/v1/health` 200; `curl ml:8000/health` 200 with token, 401 without; `flutter build apk --debug --flavor <each>` succeeds; isolation script passes, and fails on a deliberate bad import (then revert).
- **Done when:** all of the above pass and are recorded in TESTING.md.
- **Commit:** `feat(m01): monorepo skeleton, flavors, dev stack, CI and docs structure`

### M2 — Database Schema, Migrations and Seed
- **Objective:** the full PostgreSQL schema from Section 7.
- **Tasks:** `schema.prisma` with all tables/enums/indexes; initial migration; `sql/roles.sql` (roles, grants, trace_events revoke) + a migration that re-applies the revoke; `seed.ts` (idempotent); InfluxDB bucket + retention setup script; DATABASE.md.
- **DB:** all tables. **BE:** PrismaService in `infra/`.
- **Files:** `backend/prisma/*`, `backend/src/infra/prisma/*`, `deploy/influx/setup.sh`, `docs/DATABASE.md`.
- **Tests:** `prisma migrate reset` clean; seed twice → no duplicates; SQL test: connect as `iccms_app`, `UPDATE trace_events` → permission denied, `INSERT` → ok; unique constraints (batch code, tag uid) enforced; required indexes exist (query `pg_indexes`).
- **Done when:** schema + roles verified and documented.
- **Commit:** `feat(m02): postgres schema, roles, migrations and seed data`

### M3 — Backend Foundation, Authentication and RBAC
- **Objective:** secure login and an enforced permission model.
- **Tasks:** Supabase project setup as in 6.2 (dev project; record settings), `SupabaseAuthGuard` with JWKS verification, `FlavorRoleGuard`, `DeviceGuard` + `/me/session` (DA-FR-01), `RolesGuard`, ownership helper; admin user management that creates/invites/bans Supabase users (AUTH-06); email-verified sync (AUTH-04); **Send SMS Hook endpoint** with signature check + rate limit (AUTH-08); `SmsService` with `console` and `httpsms` providers (httpSMS itself is installed in M14; until then test the provider against a mock server); httpSMS delivery webhook; throttler (Redis), 426 version gate, masters CRUD + `/masters/bundle` (ETag), remote config, audit log interceptor, Swagger (non-prod), API docs.
- **Files:** `modules/{auth,users,masters,remote-config,sms,hooks}/*`, `common/guards/*`, `common/interceptors/audit.interceptor.ts`, `infra/{redis,supabase}/*`.
- **Tests:** unit: JWKS verification (valid / expired / wrong issuer / wrong audience / tampered), hook signature (valid / bad / stale timestamp), httpSMS provider request shape + no double send on 5xx; e2e with real Supabase dev tokens (test phone numbers + a test Google/email account): unregistered user → 403 `NOT_REGISTERED`, disabled user → 403, wrong app for role → 403, unverified email user → limited to the verify flow, driver on a second device → 409; permission matrix (4 roles × route groups); 426 behaviour; masters bundle 304 with ETag; admin-created phone user can log in by OTP, invited email user receives the verification mail.
- **Done when:** all three login methods produce a working backend session for the right roles, the permission matrix is green, and everything is documented in API_DOCUMENTATION.md.
- **Commit:** `feat(m03): supabase auth integration, sms hook, rbac with flavor and device guards, masters and remote config`

### M4 — Batches, Files, Storage Path and Traceability
- **Objective:** steps 1, 3 and 8 of the workflow on the backend.
- **Tasks:** batch create (client UUID, idempotent), list/search/detail, 30-min edit window + edit requests + approval, tags (NFC/QR/UHF), S3 presign + attach images, storage path + unit recommendation (SYN-10/20), receive, label data, hash-chained trace events (W-4), signed trace URL, public trace page (Handlebars: timeline, temperature summary placeholder, Verified badge), `/t/:code/verify`, `/sync` endpoint with `sync_ops` for batch-related op types, Kafka producer `quality-scans` stub.
- **Files:** `modules/{batches,files,trace,storage,sync,public-pages}/*`, `views/trace.hbs`, `common/hashing/*`.
- **Tests:** edit at 29 min ok / 31 min → 409; duplicate sync op → same result, no duplicate row; chain verify ok, then manually tamper a row as the master user → verify fails; invalid signature → 404; presign rejects a wrong type/size; operator from another site → 403; storage path rules for fish / banana / spinach.
- **Done when:** full batch lifecycle works through the API and the trace page renders on a phone browser.
- **Commit:** `feat(m04): batches, s3 uploads, storage path, hash-chained trace log and public trace page`

### M5 — ML Service I: Vision Grading and Shelf-Life
- **Objective:** steps 2 and 5 (shelf-life) on real models.
- **Tasks:** training scripts for YOLOv8s (datasets in 8), export ONNX, register; ONNX Runtime inference + grade rule; Cox PH training script + DATA_SOURCES.md; Q10 fallback; `/v1/vision/grade`, `/v1/shelf-life/predict`; backend `grading` module (`POST /batches/:id/grade`, dispute/resolve, trace events) and `shelf-life` module (store estimates, update the batch, `cargo.status` hook stub); `scripts/fetch_models.sh`, `register_model.py`.
- **Files:** `ml/training/{vision,shelf_life}/*`, `ml/service/app/routers/{vision,shelf_life}.py`, `backend/src/modules/{grading,shelf-life}/*`, `ml/service/models/registry.json`.
- **Tests:** pytest contracts; grade rule unit tests; measured mAP@0.5 + grade accuracy on the test split recorded; latency on EC2-like CPU (`t3.large` equivalent local Docker with `--cpus 2`) < 3 s end-to-end; Cox C-index recorded or fallback flagged; fallback returns ≥ 0 for every product; backend e2e with the real ml container.
- **Done when:** a batch with 3 photos gets a stored grade + shelf-life estimate via the API; metrics recorded honestly.
- **Commit:** `feat(m05): yolov8 onnx grading and cox/q10 shelf-life service with backend integration`

### M6 — ML Service II: Demand Forecast and Route Optimiser
- **Objective:** the AI behind planning and rerouting.
- **Tasks:** sales simulator, Agmarknet/Open-Meteo loaders, LSTM training + ONNX export, LightGBM training, ensemble weights, `/v1/forecast/run`; travel-matrix providers (haversine default, osrm, google); DEAP GA DVRPTW with time limit and the spoilage penalty; OR-Tools baseline; `/v1/routes/optimize` (INITIAL, REPLAN with a fixed prefix + current positions), `/v1/routes/baseline`; backend `forecast` module + nightly job.
- **Files:** `ml/training/{forecast,routing}/*`, `ml/service/app/routers/{forecast,routing}.py`, `ml/service/app/core/travel_matrix.py`, `backend/src/modules/forecast/*`, `backend/src/workers/jobs/forecast.job.ts`.
- **Tests:** forecast MAPE on the test split recorded; GA solutions respect capacity + time windows (property test on 50 random instances); replan 10 vehicles/50 stops < 10 s; GA vs manual order distance saving recorded; GA vs OR-Tools gap recorded on Solomon C101/R101/RC101.
- **Done when:** forecasts stored for all seeded centres/products; the optimiser returns feasible routes within the time limit.
- **Commit:** `feat(m06): lstm+lightgbm demand forecast and genetic dvrptw route optimiser`

### M7 — Orders, FEFO Planning, Trips and Dispatch
- **Objective:** step 4 end to end (W-3) + trip lifecycle APIs for the driver.
- **Tasks:** planner (FEFO draft orders), order edit/approve, CSV import, ERP API with HMAC + idempotency (SYN-02), build routes → trips/stops/route_plans v1, assign driver/vehicle, operator load (FO-FR-11), driver trip APIs (current, pre-check, start with device+vehicle binding, arrive, PoD with per-batch outcome DA-FR-11/12, route accept/decline), trip events (incl. SOS → alert to manager + SMS to the emergency contact), emissions on completion (SYN-16), `order-transactions` Kafka events, Socket.IO gateway (`realtime` module) with rooms.
- **Files:** `modules/{planning,orders,trips,pod,integrations,realtime}/*`.
- **Tests:** FEFO picks the lowest shelf life first; manager-only approval; ERP duplicate `externalRef` idempotent; bad HMAC → 401; cannot start a trip without pre-check; a second device start → 409; PoD partial updates the batch status + trace events; socket events received by the right rooms only.
- **Done when:** a seeded day can go forecast → orders → approved → trips → loaded → started → delivered through the API.
- **Commit:** `feat(m07): fefo planning, orders, erp import, trips, pod and realtime gateway`

### M8 — Telemetry Pipeline, Alerts and Notifications
- **Objective:** step 5 in real time (SYN-01/04/07/12/18).
- **Tasks:** Mosquitto config (passwords, ACL, TLS-ready), simulator with all scenarios + binary format, mqtt-bridge, Kafka topics setup, telemetry-writer (Influx), threshold-processor (Redis state, persistence window, shelf-life recompute on breach), exposure-aggregator, device-offline detection, alerts module (raise/ack/escalate/resolve), notifications (FCM, SMS, email, in-app) with a fallback chain, BullMQ escalation (5 min), 15-min shelf-life refresh job, data tiering export job, manager telemetry query endpoint, driver `cargo-status`.
- **Files:** `simulator/*`, `deploy/mosquitto/*`, `backend/src/workers/consumers/*`, `modules/{telemetry,alerts,notifications}/*`, `workers/jobs/{escalation,shelf-life-refresh,tiering}.job.ts`.
- **Tests:** pipeline test with time-scaled config (persist 15 min → e.g. 15 s in test): sensor→Influx ≤ 500 ms (p95 over 1,000 packets), breach→shelf-life stored ≤ 5 s, alert after persistence, escalation after ack timeout, no duplicate alerts for one breach, binary CRC failure dropped, 500 simulated devices at 60 s with zero loss; push delivered to a real test device; SMS via console adapter; tiering export file created.
- **Done when:** the `temp_drift` and `ethylene_buildup` scenarios produce correct alerts and shelf-life updates visible through the API and sockets.
- **Commit:** `feat(m08): mqtt-kafka-influx telemetry pipeline, threshold alerts, escalation and notifications`

### M9 — Incident Engine, Backup Buyers, Diversion and Rescue
- **Objective:** step 6 (W-1, W-2, SYN-06/08) + maintenance + compliance reports.
- **Tasks:** spoilage decision gate, incident classifier, DRIVER_FIX re-check job, buyers CRUD, candidate filtering/ranking, offers (token, SMS link, 10-min timeout chain), public offer page, replan via ML with the diversion/cold-storage stop, rescue matching + two-trip replan, `route.proposed` to the driver + driver-response escalation (5 min), manager manual override, decision log; reefer health job (SYN-17); compliance HTML/CSV, traceability CSV, emissions + reefer reports (SYN-15/16/17).
- **Files:** `modules/{incidents,buyers,diversions,reports,maintenance}/*`, `views/{offer,compliance}.hbs`, `workers/jobs/{offer-timeout,driver-fix-recheck,reefer-health}.job.ts`.
- **Tests:** scenario `reefer_failure` → cold storage chosen when reachable, else rescue, else buyer; `temp_drift_recoverable` → DRIVER_FIX then resolved without diversion; buyer closed / wrong product / grade too low → excluded; offer expiry → next buyer; all rejected → MANUAL + manager alert; expired or reused token → 410; decision log complete; reports open and match the Influx data.
- **Done when:** all three incident paths work end to end with the simulator and are visible in the decision logs.
- **Commit:** `feat(m09): incident engine, backup buyer offers, diversion/rescue rerouting and compliance reports`

### M10 — Mobile Foundation: Core, Design System, Auth, Offline Sync
- **Objective:** the shared mobile base all three APKs use.
- **Tasks:** theme tokens (Section 13) + bundled fonts + contrast test; shared widgets (buttons, cards, inputs, chips, AsyncView, skeleton, empty/error, offline banner, status strip); ApiClient + interceptors; secure storage; `core/auth` on `supabase_flutter` (phone OTP for driver/operator; Google native + email/password + reset + verify-email for manager; web OAuth redirect for the console); drift + SQLCipher; outbox + sync engine + file upload queue; realtime client; FCM + local notifications; localisation EN/HI/MR; splash, login per flavor, OTP, verify-email, settings, sync queue screens; Google OAuth Android client with debug + release SHA-1; routers per flavor with shared routes; per-flavor manifests, names, icons, Firebase config; release signing config; `scripts/build_apk.sh`, `verify_apk_isolation.sh`; BUILD_GUIDE.md.
- **Files:** `mobile/lib/core/**`, `mobile/lib/shared/**`, `mobile/lib/l10n/*`, `mobile/android/app/src/{driver,operator,manager}/**`, `scripts/build_apk.sh`, `scripts/verify_apk_isolation.sh`.
- **Tests:** unit (outbox ordering, retry/backoff, token refresh single-flight, validators); widget tests at text scale 2.0; wrong-role login shows a clear error and signs out; Google sign-in works on the **release** build of the manager APK (release SHA-1); session survives app restart and refreshes after 1 h; all 3 release APKs build and install side by side on one device; binary isolation check passes for all 3; airplane-mode write → reconnect → synced exactly once.
- **Done when:** each APK logs in with the right role, works offline for queued writes, and shows the correct name/icon/accent.
- **Commit:** `feat(m10): flutter core, design system, auth, offline outbox sync and flavor builds`

### M11 — Operator APK
- **Objective:** FO-FR-01…13 and FO-NFR-01…10 on device.
- **Tasks:** home; batch wizard (fish/produce forms with smart defaults + voice input + range validation, tag readers NFC/QR/wedge, guided camera + compression, grade result + dispute + queued grading, storage path, label print/share); batch list/detail/edit/request-edit; receive; load truck; printer setup.
- **Files:** `mobile/lib/apps/operator/**`, `mobile/lib/core/tags/*` (TagReader implementations).
- **Tests:** integration test of the full wizard online and offline; timing of one batch with a trained flow < 60 s (record it); photo size < 500 KB; NFC on a real tag (or a recorded limitation if no NFC phone); edit-window behaviour; Bluetooth print or share fallback; Hindi + Marathi screens checked for overflow; gloves test (large targets) noted.
- **Done when:** a batch registered offline at the "dock" syncs, gets graded, gets a storage unit, prints a label, and appears on the public trace page.
- **Commit:** `feat(m11): operator app - batch wizard, tagging, grading, storage, labels, receiving and loading`

### M12 — Driver APK
- **Objective:** DA-FR-01…14 and DA-NFR-01…12 on device.
- **Tasks:** today/trip screens, pre-trip check, active trip map + Google Maps hand-off + corridor tile caching, cargo status, critical alert screen (alarm + TTS + ack), reroute proposal flow, incident report (photo/voice), SOS, stop/PoD flow (scan, outcomes, signature, photo), history + pending uploads, foreground service GPS, speed lock overlay, performance pass (cold start, 60 fps, battery).
- **Files:** `mobile/lib/apps/driver/**`, `mobile/lib/core/location/*`, `mobile/lib/core/map/caching_tile_provider.dart`.
- **Tests:** with the simulator `reefer_failure`: alert ≤ 10 s on the phone, ack stops escalation, the reroute appears and navigation switches; offline trip (airplane mode for 20 min) → GPS + PoD synced later with no loss; speed lock with mocked speed; cold start < 3 s on a 2–3 GB device (record the device used); battery drain measured over 1 h (record it); APK size < 40 MB.
- **Done when:** a full simulated trip with one incident and diversion is completed from the driver phone.
- **Commit:** `feat(m12): driver app - trips, navigation hand-off, live cargo, alerts, reroutes, incidents and pod`

### M13 — Control Tower (Manager) APK + Web Console
- **Objective:** all manager/admin functions on mobile and web.
- **Tasks:** responsive shell (bar/rail), dashboard KPIs + live vehicle map, trips list/detail with telemetry chart, alerts & incidents (decision log, offers, manual actions), forecast charts, planning flow (run → edit → approve → build routes → assign), approvals (edits, disputes), buyers CRUD, masters/users (ADMIN), remote config, reports, app releases list; Flutter web build + `release-console.yml`.
- **Files:** `mobile/lib/apps/manager/**`, `.github/workflows/release-console.yml`.
- **Tests:** integration test of the planning flow; MANAGER cannot see/open admin screens and the API returns 403 if forced; web build runs in Chrome at 1280 px and on a phone; live alert appears on the dashboard within 5 s of being raised; charts match API data.
- **Done when:** a manager can run a whole day (plan → monitor → handle an incident → see reports) from the APK and from the web console.
- **Commit:** `feat(m13): control tower app and web console - monitoring, planning, incidents, buyers, reports`

### M14 — AWS Infrastructure and Production Deployment
- **Objective:** the backend live on EC2 + RDS with HTTPS, MQTT TLS, backups and monitoring.
- **Tasks:** everything in Section 17: resources, SSM params, roles.sql on RDS, server setup, nginx + certbot, prod compose with awslogs, render_env/deploy/backup/disk scripts + cron, alarms, console deploy, **httpSMS install + gateway phone + nginx for `sms.<domain>` (17.11)**, production Supabase settings (Send SMS Hook URL → the live API, Site/Redirect URLs, custom SMTP), simulator pointed at `mqtts://mqtt.<domain>:8883`, APK `env/prod.json` pointing at the live API; DEPLOYMENT.md with real resource IDs (no secrets).
- **Files:** `deploy/docker-compose.prod.yml`, `deploy/nginx/iccms.conf`, `deploy/aws/*`, `scripts/{deploy,render_env,backup_db,backup_influx,disk_check}.sh`, `docs/DEPLOYMENT.md`.
- **Tests:** `curl -I https://api.<domain>/api/v1/health/ready` 200 with valid TLS (also check with `openssl s_client`); RDS not reachable from the internet (connection from a laptop fails); `iccms_app` permissions verified on RDS; simulator → Influx on the server; push from production; httpSMS curl smoke test → 202 + SMS received; **real phone OTP login on the driver APK through Supabase → hook → httpSMS → SIM** (record the time from tap to SMS); Google sign-in + email verification on the manager APK and web console against production; `sms.<domain>` dashboard blocked from a non-allowed IP; gateway phone switched off → OTP failure is reported cleanly in the app and the "SMS gateway down" alert fires; deploy of a new tag works and a forced health failure rolls back; backup file in S3; **restore drill done**; alarm test email received (`aws cloudwatch set-alarm-state`); autocannon p95 < 300 ms recorded.
- **Done when:** all three APKs (prod env) work against the live server end to end.
- **Commit:** `feat(m14): aws ec2 + rds deployment with tls, mqtt, backups, monitoring and deploy scripts`

### M15 — In-App Updates, GitHub Releases, Final QA and README
- **Objective:** a maintainable release channel + a verified, documented system.
- **Tasks:** `app-updates` backend module (sync job + webhook + manifest API + install reports + download proxy option), `release.sh`, `release-android.yml` with metadata + checksums + cert fingerprint, mobile `core/updates` (Updates screen, state machine, resumable download, sha256 + package/cert inspection, `ApkInstallerPlugin.kt` with PackageInstaller + EventChannel, mandatory gate, post-update sheet), beta channel toggle; full regression on all three flavors against production; fix bugs; final README (Section 22), UPDATE_SYSTEM.md, BUILD_GUIDE.md, TESTING.md summary, PROJECT_STATUS.md all green or honestly marked.
- **Files:** `backend/src/modules/app-updates/*`, `mobile/lib/core/updates/**`, `mobile/lib/shared/screens/updates_screen.dart`, `mobile/android/app/src/main/kotlin/in/iccms/app/ApkInstallerPlugin.kt`, `.github/workflows/release-android.yml`, `scripts/release.sh`, `README.md`, `docs/UPDATE_SYSTEM.md`.
- **Tests (on a real device):** install driver v1.0.0 → publish v1.0.1 → in-app update installs over it without uninstall, data kept; interrupted download resumes; wrong sha256 rejected; operator APK offered to the driver app → rejected (package mismatch); APK signed with a different key → rejected; mandatory release blocks use + 426 path works; beta toggle shows prereleases only when on; GitHub API calls stay within limits (log check: 304s); end-to-end regression checklist across all workflows passes, or failures are logged as known issues.
- **Done when:** one real update per flavor has been delivered through the app, and the documentation lets a new developer set up, build, release and deploy without help.
- **Commit:** `feat(m15): in-app update system with github releases, final qa and documentation`

---

## 21. Token-Efficiency and Implementation Discipline

- At session start: read `docs/PROJECT_STATUS.md` + the last `DEVELOPMENT_LOG.md` entry + the current milestone section only.
- Use search (`rg`) to find code. Open only the files you will change. Don't re-read a file you just wrote.
- Make focused edits. Never regenerate a whole file to change a few lines.
- Reuse shared code (`common/`, `core/`, `shared/`) before writing new helpers. One implementation per concern.
- No new dependency without a one-line DECISIONS entry (why, and the alternative considered).
- Keep explanations in chat short. Write details once, in the right doc file.
- Fix root causes. If you add a temporary workaround, log it as a known issue with a follow-up.
- Generate code from schemas where possible (Prisma client, drift codegen, l10n codegen) instead of writing it by hand.
- When a test fails, read the failing output carefully before changing code. Do not change a test just to make it pass unless the test itself is wrong (note it in TESTING.md).

---

## 22. README.md Specification (finalised in M15)

Sections, in order: project title + one-line purpose · problem and solution (short) · key features (bullets, matching Section 3) · dashboards and roles table · tech stack table · architecture diagram (from 5.1) · screenshots section with **placeholders only** (`docs/screenshots/<flavor>-<screen>.png` – "to be added") · folder structure · prerequisites (pinned versions) · local setup (dev compose, env, DB migrate + seed, backend, worker, ml, simulator, mobile run per flavor) · environment configuration (link to the variable list, no values) · APK build commands per flavor · APK downloads (link to the GitHub Releases page) and how the in-app update works · AWS deployment overview (link DEPLOYMENT.md) · testing (commands, link TESTING.md) · milestones table (from PROJECT_STATUS.md) · SDG mapping (2, 3, 9, 12, 13, 14, 15; one line each) · licence notes (incl. the Ultralytics AGPL note) · contribution and maintenance guidelines (branching, commit format, release steps, keystore warning) · team/credits placeholder.
**No fabricated screenshots, badges, metrics, test results or deployment claims.** Badges only for things that exist (e.g. the CI workflow status after CI runs).
