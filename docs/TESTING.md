# Testing

## Commands
| Area | Command |
|------|---------|
| Backend | `cd server && npm run lint && npm test` |
| ML | `cd ml/service && pip install -r requirements.txt -r requirements-dev.txt && pytest -q` |
| Mobile | `cd client && flutter analyze && flutter test` |
| Isolation | `bash scripts/check_flavor_isolation.sh` |
| Secrets | `bash scripts/secret_scan.sh` |

## Results

### M1 — 2026-11-13
The M1 test suite was **not run**, by user instruction (D-26). What was actually run during development:

| Check | Result |
|-------|--------|
| `server`: `npm run build` (tsc) | Pass |
| `client`: `flutter analyze` | Pass (no issues) |
| `scripts/check_flavor_isolation.sh` | Pass |
| `scripts/secret_scan.sh` | Pass |

**Deferred M1 checks (NOT RUN):**
- `docker compose -f deploy/docker-compose.dev.yml up -d` all healthy (Docker not installed)
- `curl :3000/api/v1/health` → 200
- ML `/health` → 200 with token, 401 without (`ml/service/tests/test_health.py` written, not run)
- `flutter test` (`client/test/flavor_routers_test.dart` written, not run)
- `flutter build apk --debug --flavor driver|operator|manager`
- Isolation script fails on a deliberate bad import

### M2 — 2026-11-13
| Check | Result |
|-------|--------|
| `prisma validate` | Pass |
| `prisma migrate diff --from-empty` → init migration | Generated: 36 tables |
| `prisma generate` + `npm run build` | Pass |
| `eslint` on src + seed | Pass |
| `tsc --strict` on `prisma/seed.ts` | Pass |

**Deferred M2 checks (NOT RUN — no dev database credentials):**
- `prisma migrate reset` on a clean DB
- seed twice → no duplicates
- as `iccms_app`: `UPDATE trace_events` → permission denied, `INSERT` → ok
- unique constraints (batch code, tag uid) enforced
- required indexes present (`pg_indexes`)

### M3 — 2026-11-13
`cd server && npm test`: **5 suites, 78 tests, all pass.** `npm run build` and `eslint` also pass.

| Suite | Covers |
|-------|--------|
| `common/auth/jwt-verifier.spec.ts` | JWKS verification: valid, issuer normalisation, expired, wrong issuer, wrong audience, tampered payload, unknown key, garbage (AUTH-05) |
| `modules/hooks/hook-verifier.spec.ts` | Send SMS Hook: valid, bad signature, modified body, stale timestamp, other secret, missing fields, missing headers; E.164 + OTP template (AUTH-08) |
| `modules/sms/sms-provider.spec.ts` | httpSMS request shape; **no retry on 5xx/4xx** (1 call); 2 retries on network error (3 calls); recovery after a network error |
| `common/guards/guards.spec.ts` | Flavor x role matrix (4 x 4); RolesGuard route groups x roles; 426 gate (below/at min, exempt paths, no header, cache) |
| `modules/remote-config/config-keys.spec.ts` | Config value schemas; hook rate limiter 5/hour/phone |

**Deferred M3 checks (NOT RUN; need a Supabase dev project and a database):**
- e2e with real Supabase tokens: unregistered -> 403 `NOT_REGISTERED`, disabled -> 403, wrong app -> 403, unverified email -> only `/me`, driver second device -> 409
- full permission matrix over HTTP; 426 over HTTP; masters bundle 304 with ETag over HTTP
- admin-created phone user logs in by OTP; invited email user receives the mail
- API boot (needs a reachable Postgres)

### M4 — 2026-11-13
`cd server && npm test`: **13 suites, 140 tests, all pass.** `npm run build` and `eslint` pass.

| Suite | M4 test item covered |
|-------|----------------------|
| `common/hashing/hashing.spec.ts` | Chain verifies; still verifies after jsonb-style key reordering; **tampered payload → invalid at that seq**; re-hashed row caught by the next link; deleted event; changed timestamp; trace signature accept/reject (wrong code, key, length, type) |
| `modules/batches/batch-rules.spec.ts` | **Edit at 29 min ok, 30 ok, 31 refused**; IST day for codes; code format; fish core temp −2..+10; fish vs produce field rules |
| `modules/batches/batches.service.spec.ts` | **Operator from another site → 403**; 31 min → 409 `EDIT_WINDOW_CLOSED` with no write; 29 min → applied; offline edit by device times; idempotent create replay; same UUID from another user → 409 |
| `modules/storage/storage-rules.spec.ts` | **Fish → blast chiller, banana → ripening chamber, spinach → blast chiller**; grade C → cold room + sell first; unit ranking (type, capacity, temperature, active, best fit) |
| `modules/files/files.spec.ts` | **Presign rejects wrong type (400) / size (413)**; uploader signed into the PUT; attach refuses wrong purpose, missing object, other user's upload; download access |
| `modules/sync/sync.service.spec.ts` | **Duplicate op → same result, handler called once, one row**; 4xx stored, 5xx not stored; payload validation; role rules; UNSUPPORTED not stored; foreign clientOpId |
| `modules/public-pages/trace-view.spec.ts` | Labels for every event type; no tag UIDs, keys or user ids on the public page |
| `config/env.schema.spec.ts` | Empty `KEY=` values treated as unset; short trace key fails fast |

**Deferred M4 checks (NOT RUN; need Postgres + S3):**
- Tamper a `trace_events` row as the master DB user, then `/t/:code/verify` → `valid:false` (logic covered by unit tests above)
- Invalid signature → 404 over HTTP
- Full batch lifecycle through the API; concurrent code allocation; storage capacity under concurrency
- Trace page rendered on a phone browser

### M5 — 2026-11-13
**ML service** (`cd ml/service && .venv/Scripts/python -m pytest -q`, Python 3.10 locally, D-60): **45 passed.**

| File | Covers |
|------|--------|
| `tests/test_vision_logic.py` | Grade rule: no defect → A; small defect → B; defects summing to 10 % → C; rot/mould → C; area relative to the item; no fresh box → whole image; nothing detected → A with confidence 0; batch = worst image. Letterbox; decoder maps boxes back; confidence 0.35 cut; class-wise NMS 0.5; class-count mismatch |
| `tests/test_shelf_life.py` | **Q10 returns ≥ 0 and finite for all 10 seed products** over 7 temperatures × 4 ages; formula checks; curve half at total life; Cox at mean covariates = baseline median; elapsed subtraction + clamp; temperature coefficient shortens life; censoring flag; wrong feature list refused; fallback when no Cox |
| `tests/test_api.py` | Token on every route; shelf life Q10 contract; **200 items answer in < 1 s** (local laptop); validation; registered Cox model is used; **vision 503 without a model**; vision contract end to end with a tiny constant-output ONNX model through the real loader, decoder and grade rule; **wrong sha256 → model not loaded**; exactly 3 URLs |
| `tests/test_health.py` | 200 with token, 401 without, unset token rejects all |

**Backend** (`cd server && npm test`): **15 suites, 162 tests, all pass.** New: `grading/grading.spec.ts` (photo selection; ML call shape; AUTO grade + batch + trace + shelf-life recompute; missing photos 409; ML down/no model → 503 with nothing stored; unreadable photo 422; shelf-life failure does not undo the grade; dispute once; resolve → MANUAL row; resolve guards), `shelf-life/shelf-life.spec.ts` (backend Q10 = ML numbers; ≥ 2 h trace rule; request shape; ML down → backend Q10; finished batches skipped; ML client token + error mapping).

**Model metrics: NOT MEASURED.** No vision dataset or shelf-life observations exist yet, so there is no YOLOv8 or Cox model (D-57).
| Target | Status |
|--------|--------|
| ML-01 mAP@0.5 ≥ 0.80, grade accuracy ≥ 85 % | Not measured: no model trained |
| SYN-05 / ML-01 grading ≤ 3 s end to end (`--cpus 2` Docker) | Not measured: no model, Docker not installed |
| ML-02 Cox C-index ≥ 0.75, error ≤ ±12 h | Not measured: no data; **Q10 fallback is the active method** |
| ML-02 fallback returns ≥ 0 for every product | **Pass** (unit test above) |
| Shelf-life answer < 1 s | **Pass** locally for 200 items (not on EC2-like CPU) |

**Deferred M5 checks (NOT RUN):** backend e2e against the real ML container; latency on a `t3.large`-equivalent; a batch with 3 photos graded through the API (needs a model, S3 and a database).

### M6 — 2026-11-13
**ML service:** `pytest -q` → **74 passed** (Python 3.10 locally). **Backend:** `npm test` → **16 suites, 168 tests, all pass**; build + lint pass.

| File | Covers |
|------|--------|
| `tests/test_routing.py` | Haversine sanity (Mumbai–Pune ≈ 120 km), peak/night speed factor, OSRM + Google parsing (mocked), fallback to haversine; route evaluation (waiting, lateness, overload, spoilage, wrong vehicle, shift end); encode/decode with fixed prefix; prefix + `mustKeepVehicle` kept; **property test: 50 random instances with a planted feasible plan → GA result has 0 overload and 0 lateness on all 50**; GA ≥ 10 % shorter than the manual order; API contract; **REPLAN 10 vehicles / 50 stops < 10 s**; OR-Tools baseline contract; 4 validation errors |
| `tests/test_forecast.py` | Simulator determinism; festival uplift; feature shapes; seasonal naive; MAPE; Open-Meteo parse + fallback; API without a model (SEASONAL_NAIVE, 7 days, lower ≤ pred ≤ upper); provided vs simulated history; validation; a real LightGBM model registered as a multi-file model is used; bad hash → not loaded |
| `server/src/modules/forecast/forecast.spec.ts` | IST "tomorrow"; newest-run-per-day selection; next 02:00 IST; run → ML request shape + 14 rows stored under one run id; ML failure → 503, nothing stored; one background job at a time |

**Measured — demand forecast (ML-03, target MAPE < 15 %).** `ml/training/forecast/train_forecast.py`, data **simulated** (Section 2): 60 series (6 sites × 10 products), 2023-01-01…2025-12-31, time split by origin (test origins 2025-09-25…2025-12-24, validation the 3 months before), 38,220 test forecasts. File: `ml/training/forecast/metrics-m06.json`.
| Model | Test MAPE |
|-------|-----------|
| Ensemble (LSTM weight 0.1, chosen on validation) | **8.79 %** |
| LightGBM | 8.73 % |
| LSTM | 10.33 % |
| Seasonal naive | 11.29 % |
80 % interval (±14.0 %) covered **79.8 %** of test actuals. Note: on test the ensemble is 0.06 points worse than LightGBM alone; the weight was not re-tuned on test. **These numbers are on simulated data and say nothing yet about real sales.** The trained model served a real `ENSEMBLE` forecast through the API (28 rows, 24 ms); it is not registered in `registry.json` (D-72).

**Measured — route optimiser (ML-04).** `ml/training/routing/benchmark.py`, laptop CPU, GA time limit 8 s, OR-Tools 30 s. File: `ml/training/routing/metrics-m06.json`.
| Case | GA | OR-Tools | Gap (distance) |
|------|----|----------|----------------|
| C101-like (synthetic, 100 customers) | 1599.7 (2.4 s; 8.5 late-min, same as OR-Tools) | 1409.2 (31 s) | +13.5 % |
| R101-like (synthetic) | 2305.1, feasible (3.3 s) | 2042.1, feasible (30 s) | +12.9 % |
| RC101-like (synthetic) | 2086.3, feasible (1.9 s) | 1822.6, feasible (30 s) | +14.5 % |
Real Solomon files were **not** used (not downloaded; place them in `ml/training/data/routing/` and re-run). Before the memetic polish (D-69) the gaps were +93 %, +84 %, +82 %.
| ML-04 target | Measured |
|--------------|----------|
| Replan < 10 s, 10 vehicles / 50 stops | **0.81 s** (benchmark), < 10 s in the API test |
| ≥ 10 % distance saving vs manual order | **57.1 %** (Chh. Sambhajinagar synthetic case: GA 884.6 km feasible vs manual 2060.3 km with 4,582 late-min) |

**Deferred M6 checks (NOT RUN):** forecasts stored for all seeded centres/products through the API (needs a database); routing with OSRM/Google against live services.

### M7 — 2026-11-13
`cd server && npm test` → **21 suites, 210 tests, all pass.** Build + lint pass.

| File | M7 test item covered |
|------|----------------------|
| `planning/fefo.spec.ts` | **FEFO picks the lowest shelf life first**; < 24 h → nearest centre; otherwise largest need; whole batches; spoiled/other products skipped; shortfall |
| `trips/trips.spec.ts` | **Cannot start without pre-check (409)**; **second device → 409**; one active trip per driver/vehicle; foreign driver 403; start side effects (device bind, vehicle IN_USE, IN_TRANSIT + DEPARTED, managers notified); wrong batch on load → 409 with ids; operator only at depot; **SOS → CRITICAL alert + managers + SMS with maps link**; SOS replay idempotent; **order approval is MANAGER/ADMIN only** (route metadata); PoD rules; **PoD PARTIAL → PARTIALLY_DELIVERED + DELIVERED trace (outcome PARTIAL)**, stop/order/trip completion with CO₂ factor; REJECTED path; wrong crate → 409 TAG_MISMATCH; batch code accepted as scan; PoD replay |
| `trips/trip-rules.spec.ts` | Setpoint intersection; fish + banana incompatible; pre-check codes; status machine; CO₂; maps link |
| `integrations/integrations.spec.ts` | HMAC accept / prefix / tampered / other key / garbage / missing; **bad HMAC → 401, nothing imported**; unknown/disabled key 401 via SHA-256 lookup; auth before validation; scope 403; **duplicate externalRef → DUPLICATE, no insert**; invalid row rejected; CSV BOM/CRLF/quotes + column mapping |
| `realtime/realtime.e2e.spec.ts` | **Real Socket.IO server + 3 clients: trip events reach only the trip's driver and managers, a user event only that user, manager events only managers; another driver cannot join the trip room; bad token and wrong app rejected** |
| `sync/sync.service.spec.ts` | + LOAD / ROUTE_ACCEPT / POD routing and role rules |

**Deferred M7 checks (NOT RUN; need Postgres + the ML container):** "a seeded day goes forecast → orders → approved → trips → loaded → started → delivered through the API"; concurrent code allocation; ERP request over HTTP with a real key.

### M8 — 2026-11-14
`cd server && npm test` → **25 suites, 245 tests, all pass.** Build + lint pass.

| File | M8 test item covered |
|------|----------------------|
| `telemetry/packet.spec.ts` | Binary decode of a packet produced by `simulator/sim.py` (byte-identical fixture); TS encode = Python encode; **bad CRC / length / version → dropped with reason**; JSON packets; out-of-range and device mismatch |
| `telemetry/thresholds.spec.ts` | Strictest limits across mixed cargo; breach start → RAISE only after the persistence window; **exactly one alert per breach**; recovery; shock cooldown; exposure accumulation with the 5-min gap cap |
| `alerts/alerts.spec.ts` | raise → realtime + Kafka event + driver push (SMS only when push fails) + managers (email only to verified addresses) + escalation job; escalate only while OPEN; driver may ack only own trip's alerts; ack removes the escalation job; SMS gateway down after 3 failures raises `SMS_GATEWAY_DOWN` |
| `workers/workers.spec.ts` | Telemetry writer → Influx points + latency samples; threshold processor → shelf-life recompute on breach; exposure flush; tiering CSV + archive key; device offline check |
| `sync`, `trips` specs | `GPS_POINTS` (driver, trip IN_PROGRESS) and `ALERT_ACK`; `cargoStatus` includes the last reading |

**Live dev stack** (Docker 29.9.3: Postgres 16 on :5433, Redis 7.4, Kafka 3.8.1 KRaft, Mosquitto 2.0.20, InfluxDB 2.7, ml): migrations applied; **seed run twice → identical counts** (sites 6, storage units 11, products 10, users 6, vehicles 3, devices 3, buyers 6, config 10), so the seed is idempotent.

**Pipeline test** `server/test/pipeline/run.ts`, worker running with `TELEMETRY_TIME_SCALE=60`:

| Step | Target | Run 1 | Run 2 |
|------|--------|-------|-------|
| sensor → Influx p95, 1,000 packets (SRV-02) | ≤ 500 ms | **FAIL 3,546 ms** | **FAIL 6,362 ms** |
| breach → shelf-life estimate stored (SYN-04) | ≤ 5 s | PASS 110 ms | PASS 152 ms |
| alert after (scaled) 15-min window, no duplicates (SYN-07) | exactly 1 | PASS 1 | PASS 1 |
| escalation after (scaled) 5-min ack timeout (DA-FR-07) | ESCALATED | PASS | PASS |
| binary packet with bad CRC dropped and counted | +1 | PASS 0 → 1 | PASS 1 → 2 |
| 500 devices × 10 packets, zero loss (seq count in Influx) | 5,000 | **crashed: MQTT `connack timeout`** | **PASS 5,000 / 5,000** |
| tiering export file created | file exists | not reached | PASS |

**Run 1 → run 2 fix (connack timeout):** a probe showed that through `localhost` only 235 MQTT connections succeeded before timing out; through `127.0.0.1`, all **500 connected in 1.8 s**. On Windows `localhost` resolves to `::1` first, and Docker Desktop's IPv6 port forwarding stalls under load. Fix: all backend service URLs and the Kafka EXTERNAL advertised listener now use `127.0.0.1` (D-96).

**Latency: not met; fix written but NOT re-run.** A breakdown probe on a warm worker measured:
- publish → bridge: p95 **70 ms**
- publish → Kafka consumer: p95 **222 ms**
- writer metric (`now − packet ts`): p95 **1,268 ms**

The writer metric cannot resolve 500 ms, because packet time is whole seconds (`u32 epoch_s`), which adds 0–999 ms of rounding to every sample. The 3.5–6.4 s runs were also cold: the first traffic after a worker start paid for Kafka producer init (`InitProducerId` while the coordinator was loading).

The following changes are in the code: the producer and topics now connect at worker start (`KafkaService.warmUp`); consumers wait at most 100 ms (was 250); there is a new millisecond-accurate metric `metrics:latency:bridge_to_influx_ms`; and step 1 now times publish → bridge itself, excludes one 50-packet warm-up round, and checks p95(publish→bridge) + p95(bridge→Influx) ≤ 500 ms. **This version of step 1 has not been run** (skipped on 2026-11-14: no live sensors). SRV-02 is therefore **not verified**.

**Deferred M8 checks (NOT RUN):** SRV-02 rerun as above; FCM push and SMTP email to real devices/addresses (no Firebase credentials / SMTP configured: channels skipped, SMS on the console provider); Socket.IO events across two API instances through the Redis adapter; the simulator scenarios against the stack.

## Measured metrics
- M8 pipeline (dev stack on one Windows PC, time scale 60): breach → shelf life 110–152 ms; 500 devices × 10 packets → 5,000 / 5,000 stored; warm publish → Kafka p95 222 ms. Sensor → Influx p95 **not verified** (see M8).

## Known issues
- kafkajs prints `TimeoutNegativeWarning: -17946… is a negative number` from `RequestQueue.scheduleCheckPendingRequests` (its default `throttledUntil = -1`). Harmless, Node clamps it to 1 ms; third-party issue, not fixed here.
- kafkajs logs `The group coordinator is not available` / `coordinator is loading` for a few seconds after Kafka starts; consumers retry and join.
- On Windows use `127.0.0.1`, not `localhost`, for services published by Docker Desktop (see M8).
