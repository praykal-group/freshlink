# API Documentation

Base path `/api/v1`. JSON, camelCase, ISO-8601 UTC timestamps, UUID ids. Swagger UI: `/api/docs` (non-production only).

## Headers sent by the apps
| Header | Values | Notes |
|--------|--------|-------|
| `Authorization` | `Bearer <Supabase access token>` | All non-public routes |
| `X-App-Flavor` | `driver` \| `operator` \| `manager` \| `web` | Required on authenticated routes |
| `X-App-Version-Code` | integer | Below the flavor's `minSupportedVersionCode` → **426** |
| `X-Device-Id` | string | Required for DRIVER requests and `/me/logout` |
| `Accept-Language` | `en` \| `hi` \| `mr` | |

## Authentication and authorisation
Login, OTP, token refresh and sign-out happen in **Supabase** from the app (D-21). The backend:
1. **Version gate** (`VersionGateGuard`): `X-App-Version-Code < minSupportedVersionCode` of the newest active stable release → 426 `UPGRADE_REQUIRED`. Exempt: `/auth/*`, `/app/updates*`, `/health*`; requests without the header.
2. **JWT** (`SupabaseAuthGuard`): signature via JWKS (`SUPABASE_JWKS_URL`, default `${SUPABASE_URL}/auth/v1/.well-known/jwks.json`), `iss = ${SUPABASE_URL}/auth/v1`, `aud = authenticated`, `exp`. Then `users` row by `supabase_uid = sub` (cached 60 s); missing or not `ACTIVE` → 403 `NOT_REGISTERED`. Email users with an unverified address get 403 `EMAIL_NOT_VERIFIED` except on `GET /me` and `POST /me/logout`.
3. **Flavor ↔ role** (`FlavorRoleGuard`): `driver→DRIVER`, `operator→OPERATOR`, `manager|web→MANAGER|ADMIN`; mismatch → 403 `WRONG_APP_FOR_ROLE` (the app signs out).
4. **Device** (`DeviceGuard`, drivers only): `X-Device-Id` must equal the active registration from `POST /me/session`; otherwise 409 `SESSION_ON_OTHER_DEVICE` (or 409 `NO_ACTIVE_SESSION` if none).
5. **Roles** (`@Roles`) → 403 `FORBIDDEN_ROLE`; then ownership checks in services (`common/auth/ownership.ts`).
6. **Rate limit**: 120 req/min per user (IP for public routes) → 429.

Manager/admin writes are recorded in `audit_logs` (route, target id, redacted body, IP, requestId).

## Error envelope
```json
{"error":{"code":"WRONG_APP_FOR_ROLE","message":"Role DRIVER cannot use the manager app","details":{"role":"DRIVER","flavor":"manager"},"requestId":"9b2e…"}}
```
| Code | HTTP | When |
|------|------|------|
| `VALIDATION_FAILED` | 400 | DTO validation (`details.errors`) |
| `MISSING_APP_FLAVOR` / `MISSING_DEVICE_ID` | 400 | Required header missing/invalid |
| `UNAUTHORIZED` / `INVALID_TOKEN` / `TOKEN_EXPIRED` | 401 | No / bad / expired Supabase token |
| `NOT_REGISTERED` | 403 | Token valid but no linked active user |
| `EMAIL_NOT_VERIFIED` | 403 | Email user must verify first |
| `WRONG_APP_FOR_ROLE` | 403 | Role not allowed in this app |
| `FORBIDDEN_ROLE` / `FORBIDDEN_SITE` / `FORBIDDEN_TRIP` | 403 | Role / ownership |
| `NOT_FOUND` / `UNKNOWN_CONFIG_KEY` | 404 | |
| `SESSION_ON_OTHER_DEVICE` / `NO_ACTIVE_SESSION` | 409 | Driver single-device rule |
| `DUPLICATE` | 409 | Unique constraint (Prisma P2002) |
| `UPGRADE_REQUIRED` | 426 | App too old (`details.minSupportedVersionCode`) |
| `RATE_LIMITED` | 429 | |
| `SUPABASE_ERROR` | 502 | Supabase admin API failed |
| `SUPABASE_NOT_CONFIGURED` | 503 | `SUPABASE_SERVICE_ROLE_KEY` missing |

## Endpoints implemented

### Health (public)
`GET /health` → `{"status":"ok","uptimeS":12}` · `GET /health/ready` → 200 `{"status":"ok","checks":[{"name":"db","ok":true,"latencyMs":3},{"name":"ml","ok":true,…}]}` or 503 with the same body.

### Me
| Method | Path | Body | Notes |
|--------|------|------|-------|
| GET | `/me` | – | `{id,name,role,phone,email,emailVerified,language,site,flags}`. Syncs `email_verified_at` and picks up an email changed in Supabase (resets verification, AUTH-04) |
| POST | `/me/session` | `{deviceId, fcmToken?, appVersionCode}` | Call after every login. This device becomes the only active one for user + flavor |
| PUT | `/me/language` | `{language: "en"\|"hi"\|"mr"}` | |
| POST | `/me/logout` | – | Marks this `X-Device-Id` inactive; the app also calls `supabase.auth.signOut()` |

### Admin users (ADMIN)
| Method | Path | Body / notes |
|--------|------|------|
| GET | `/admin/users?role&status&q&cursor&limit` | M13. Newest first, cursor paged; `q` matches name / phone / email (case-insensitive). Profile fields only (`id, name, role, status, phone, email, siteId, language, emergencyContactPhone, createdAt`) |
| POST | `/admin/users` | `{name, role, phone?, email?, siteId?, language?, emergencyContactPhone?}`. DRIVER/OPERATOR need `phone` + `siteId`. Creates the RDS row (`INVITED`), then the Supabase user: phone → pre-confirmed (OTP login); email (manager/admin) → invite mail. Linked → `ACTIVE` |
| PATCH | `/admin/users/:id` | `{name?, role?, siteId?, language?, emergencyContactPhone?}`. Phone/email are identity fields and change through Supabase |
| POST | `/admin/users/:id/disable` | `DISABLED` + Supabase ban + all devices inactive |
| POST | `/admin/users/:id/enable` | Unban → `ACTIVE` |
| POST | `/admin/users/:id/resend-invite` | Re-sends the invite, or finishes provisioning that failed earlier |

Response (all): `{id,name,role,phone,email,emailVerified,siteId,language,status,linked,createdAt}`.

### Masters (read: all roles · write: ADMIN)
`GET|POST /masters/{products|sites|storage-units|vehicles|devices}` · `PATCH /masters/<entity>/:id`. `GET /masters/storage-units?siteId=`. Devices: read MANAGER/ADMIN; `secret` (16–128 chars) is stored as bcrypt and never returned. Codes are immutable after create. Range fields (min ≤ max) are validated.

`GET /masters/bundle?since=<ISO>` → `{generatedAt, since, products, sites, storageUnits, config:{key:value}}`. Without `since`: active rows only; with `since`: all rows changed after it (incl. deactivated). Sends `ETag`; `If-None-Match` with the same tag → **304** with no body.

### Remote config
`GET /config/:key` (MANAGER, ADMIN) · `PUT /config/:key {value}` (ADMIN). Keys and value shapes (`modules/remote-config/config-keys.ts`): `persistMinutes, ackMinutes, offerMinutes, editWindowMin` (int minutes), `safetyMarginH`, `driftSlopeMax`, `rescueRadiusKm`, `gpsIntervalSec`, `emissionFactorKgPerKm {value, source}`, `featureFlags {name: bool}`. Unknown key → 404 `UNKNOWN_CONFIG_KEY`; bad value → 400 `INVALID_CONFIG_VALUE`.

### Hooks (no JWT, signature-checked; not in Swagger)
**`POST /hooks/supabase/send-sms`** — Supabase Send SMS Hook (D-22). Standard Webhooks headers `webhook-id`, `webhook-timestamp`, `webhook-signature`; secret `SUPABASE_SEND_SMS_HOOK_SECRET` (`v1,whsec_…`), 5-min tolerance. Body `{user:{phone}, sms:{otp}}` → SMS `I-CCMS: your login code is {otp}. Valid for 5 minutes. Do not share it.` Responses (Supabase contract): `200 {}`; errors `{"error":{"http_code":<n>,"message":"…"}}` with 401 bad signature, 429 (5/hour/phone, 30/hour/IP), 500 provider failure, 503 not configured. The OTP is never logged.

**`POST /hooks/httpsms`** — httpSMS delivery events. `Authorization: Bearer <HS256 JWT signed with HTTPSMS_WEBHOOK_SECRET>`. `message.phone.sent|delivered` → notification `SENT`; `message.send.failed|expired` → `FAILED`. Matches `notifications.provider_ref = data.message_id`.

### Files
| Method | Path | Notes |
|--------|------|-------|
| POST | `/files/presign` | `{purpose: BATCH_IMAGE\|POD_SIGNATURE\|POD_PHOTO\|INCIDENT_PHOTO\|VOICE_NOTE, contentType, sizeBytes}` → `{uploadUrl, key, expiresIn: 300, headers}`. Images jpeg/png/webp ≤ 2 MB, audio m4a/aac ≤ 5 MB (400 `UNSUPPORTED_TYPE`, 413 `FILE_TOO_LARGE`). Key `<purpose>/<yyyy>/<mm>/<uuid>.<ext>`. The PUT **must send the returned `headers`** (Content-Type, Content-Length, `x-amz-meta-uploader`): they are part of the signature |
| GET | `/files/url?key=<key>` | Presigned GET, 5 min. Managers/admins: any file; others: only their own uploads (403 `FILE_NOT_OWNED`). Query parameter because keys contain `/` (D-42) |

Attaching a key anywhere checks: right purpose prefix, object exists (409 `FILE_NOT_UPLOADED`), uploaded by the caller (403 `FILE_NOT_OWNED`).

### Batches (OPERATOR / MANAGER / ADMIN; drivers have no batch access)
Operators only see and change batches whose source or current site is their own site (403 `FORBIDDEN_SITE`).

| Method | Path | Body / notes |
|--------|------|------|
| POST | `/batches` (OPERATOR, ADMIN) | `{id (client UUID v4), productId, caughtOrHarvestedAt, weightKg, capturedAt, capturedLat?, capturedLng?, siteId? (ADMIN only)}` + fish: `vesselId, iceToFishRatio, initialCoreTemp (−2..+10 °C)` or produce: `farmRef, maturityIndex, brix?, fieldTemp?, fieldHumidity?`. Needs `X-Device-Id`. **Idempotent:** the same `id` from the same user returns the stored batch; from another user → 409 `DUPLICATE`. Code `{FSH\|PRD}-{yyyymmdd IST}-{site}-{0001}`; `recordHash` = SHA-256 of the canonical creation payload. Trace `REGISTERED` |
| GET | `/batches?status&q&siteId&cursor&limit` | `q` = code fragment or exact tag UID. `{items, nextCursor}` |
| GET | `/batches/:id` | Batch + product, tags, images, storage unit |
| PATCH | `/batches/:id` (OPERATOR, ADMIN) | Editable fields only. Within `editWindowMin` (30) of creation, same site; else 409 `EDIT_WINDOW_CLOSED` (`details.windowMin`). Writes `audit_logs` (before/after) + trace `BATCH_CORRECTED {changes:{field:{from,to}}}` |
| POST | `/batches/:id/edit-requests` (OPERATOR, ADMIN) | `{changes, reason}`; one pending request per batch (409 `EDIT_REQUEST_PENDING`) |
| GET | `/edit-requests?status` (MANAGER, ADMIN) | Paged |
| POST | `/edit-requests/:id/approve\|reject` (MANAGER, ADMIN) | `{note?}`. Approve applies the changes like a direct edit (`via: EDIT_REQUEST`). Second review → 409 `ALREADY_REVIEWED` |
| POST | `/batches/:id/tags` (OPERATOR, ADMIN) | `{tagType: NFC\|UHF_RFID\|QR, tagUid}`. Same tag on the same batch → returns it; on another batch → 409 `TAG_IN_USE`. Trace `TAGGED` |
| POST | `/batches/:id/images` (OPERATOR, ADMIN) | `{view: TOP\|SIDE\|CLOSEUP, key, width, height, capturedAt}`. Same key again → returns it. Trace `IMAGED`; publishes `quality-scans` (stub, D-47) |
| GET | `/batches/:id/storage-path` | `{path, sellFirst, reason, recommendedUnit, alternatives[], note?}` (SYN-10/20). Fish or non-climacteric → `BLAST_CHILLER`; climacteric → `RIPENING_CHAMBER`; grade C → `COLD_ROOM` + `sellFirst`. Units: same site, right type, enough free kg, temperature range overlapping the product's safe range; best fit first |
| POST | `/batches/:id/storage` (OPERATOR, ADMIN) | `{storageUnitId}`. Batch must be REGISTERED/GRADED/STORED. Capacity reserved atomically (409 `UNIT_FULL`, `UNIT_AT_OTHER_SITE`, `UNIT_TEMP_MISMATCH`); moving releases the old unit. Trace `STORED` |
| GET | `/batches/:id/label` | `{code, product{name,nameHi,nameMr}, weightKg, grade, caughtOrHarvestedAt, sourceSite, traceUrl, qrData}` |
| POST | `/batches/:id/receive` (OPERATOR, ADMIN) | `{outcome: ACCEPTED\|PARTIAL\|REJECTED, acceptedKg, condition: GOOD\|FAIR\|POOR, notes?, imageKeys?[]}`. Moves the batch to the operator's site, releases storage; PARTIAL sets weight to `acceptedKg` (must be between 0 and the weight); REJECTED → status REJECTED. Images stored as RECEIVING/DAMAGE. Trace `RECEIVED`/`REJECTED` |
| GET | `/batches/:id/timeline` | `{verified, verification, events[{seq,type,payload,actorUserId,occurredAt,hash}]}` |
| GET | `/batches/:id/shelf-life` | Current estimate + history (filled from M5) |

### Sync (offline outbox)
`POST /sync {ops:[{clientOpId, type, payload, capturedAt}]}` (1–50 ops) → `200 {results:[{clientOpId, type, status, data?, error?, replayed?}]}`. Ops run oldest `capturedAt` first.
- `APPLIED` / `REJECTED` (4xx) results are stored in `sync_ops`; resending the same `clientOpId` replays them (`replayed: true`) with no second write.
- `ERROR` (5xx/408/429) is **not** stored: keep the op and retry.
- `UNSUPPORTED`: type handled in a later milestone (`LOAD, TRIP_EVENT, GPS_POINTS, POD, ALERT_ACK, ROUTE_ACCEPT`); keep it queued.
- Payloads: `BATCH_CREATE` = POST /batches body; `BATCH_UPDATE` = `{batchId, ...fields}` (edit window uses the device times, D-45); `TAG_ATTACH` / `IMAGE_ATTACH` / `RECEIVE` = `{batchId, ...body}`. Same role rules as REST.

### Public trace (no auth, outside `/api/v1`)
- `GET /t/:code?s=<sig>` → HTML page: product (EN/HI/MR), origin, time, weight, grade, status, journey timeline, temperature placeholder, **Verified** badge from a fresh chain check. No user ids, tag UIDs or file keys. `s` = base64url(HMAC-SHA256(code, TRACE_SIGNING_KEY))[:22].
- `GET /t/:code/verify?s=<sig>` → `{code, valid, count, brokenAtSeq?, reason?, checkedAt}`.
- Bad signature or unknown code → 404 (same response).

### Grading (M5)
| Method | Path | Notes |
|--------|------|-------|
| POST | `/batches/:id/grade` (OPERATOR, ADMIN) | Uses the latest TOP, SIDE, CLOSEUP photo (409 `IMAGES_REQUIRED` with `details.missing`). Sends presigned GET URLs to the ML service. Stores an AUTO grade, sets `currentGrade` (REGISTERED → GRADED), traces `GRADED`, recomputes shelf life. Returns the grade row + `mlLatencyMs`, `totalLatencyMs`, `storagePath`. **503 `GRADING_UNAVAILABLE`** when no model is loaded or ML is down (the app keeps the request queued); 422 `GRADING_FAILED` for unreadable photos |
| POST | `/batches/:id/grade/dispute` (OPERATOR, ADMIN) | `{reason}`. Flags the latest grade; 409 `NO_GRADE` / `ALREADY_DISPUTED`. Trace `GRADE_DISPUTED` |
| POST | `/grades/:id/resolve` (MANAGER, ADMIN) | `{grade: A\|B\|C}`. Writes a new MANUAL grade row (the AUTO row is kept), updates the batch, traces `GRADE_RESOLVED`, recomputes shelf life. 409 `NOT_DISPUTED` / `ALREADY_RESOLVED` |
| GET | `/grades/disputes` (MANAGER, ADMIN) | Open disputes, paged |

### Shelf life (M5)
Recomputed on grading, dispute resolution and (from M8) on threshold breaches and every 15 min. Each run stores a `shelf_life_estimates` row and updates `batches.remaining_shelf_life_h`. `SHELF_LIFE_UPDATED` is traced only for the first estimate or a change of ≥ 2 h. If the ML service is unreachable the backend computes the Q10 fallback itself (`modelVersion: backend-q10-1`), so a value always exists (ML-02). Read with `GET /batches/:id/shelf-life`.

## ML service (internal, `X-Internal-Token`)
| Method | Path | Contract |
|--------|------|----------|
| GET | `/health` | `{status, models:{vision_fish, vision_produce, shelf_life_cox: {active, loaded, reason, metrics}}}` |
| GET | `/v1/models` | Same model table |
| POST | `/v1/vision/grade` | `{batchId, category: FISH\|PRODUCE, imageUrls[3]}` → `{batchId, grade, confidence, defects[{class, conf, box, areaPct}], perImage[{index, grade, confidence, itemDetected, defects}], modelVersion, latencyMs}`. 503 `MODEL_NOT_AVAILABLE` (with `details.reason`) when no hash-verified model is loaded; 422 for image fetch/decode errors |
| POST | `/v1/shelf-life/predict` | `{items[1..200]: {batchId, productCode, category, grade?, hoursSinceHarvest, meanTempC, degreeMinutesAbove, humidityPct?, ethylenePpm?, shockEvents, baseShelfLifeH, q10, refTempC}}` → `{results[{batchId, remainingH, survivalCurve[{h,p}], method: COX\|Q10_FALLBACK, modelVersion, censored}], latencyMs}`. `baseShelfLifeH`, `q10`, `refTempC` are product reference values sent by the backend (D-53) |
Errors: `{"error":{"code","message","details"}}`; 401 without/with a wrong token; 422 `VALIDATION_FAILED`.

### Forecast (MANAGER, ADMIN; M6)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/forecasts?siteId&productId&from&to` | `from`/`to` = `YYYY-MM-DD`, at most 92 days. Newest run's value per (site, product, day): `[{siteId, productId, date, predictedKg, lowerKg, upperKg, modelVersion, runId}]` |
| POST | `/forecasts/run` | `{startDate?, siteIds?, productIds?}` → **202** `{id, status: RUNNING, startedAt}`. Forecasts active DISTRIBUTION_CENTRE sites × active products for 7 days (default start = tomorrow IST). One run at a time (409 `FORECAST_RUNNING`) |
| GET | `/forecasts/jobs/:id` | `RUNNING` / `DONE {result:{runId, rows, modelVersion, method, …}}` / `FAILED {error}` |
The worker process also runs the forecast every night at 02:00 IST.

### ML service additions (internal)
| Method | Path | Contract |
|--------|------|----------|
| POST | `/v1/forecast/run` | `{siteIds, productIds, startDate, horizonDays 1..7, history?[{siteId, productId, date, kg, priceInr?}], siteCoords?{id:{lat,lng}}}` → `{runId, rows[{siteId, productId, date, predictedKg, lowerKg, upperKg, historySource: PROVIDED\|SIMULATED}], modelVersion, method: ENSEMBLE\|LIGHTGBM\|SEASONAL_NAIVE\|MIXED, latencyMs}`. A series uses provided history only with 30 complete days ending the day before `startDate`; otherwise the simulated world (Section 2). No registered model → seasonal naive. Max 500 series |
| POST | `/v1/routes/optimize` | `{mode: INITIAL\|REPLAN, depot, vehicles[{id, capacityKg, start?, shiftEnd?}], stops[{id, lat, lng, demandKg, windowStart?, windowEnd?, serviceMin, shelfLifeH?, mustKeepVehicle?}], fixedPrefix?{vehicleId:[stopId…]} (REPLAN only), departAt?, timeLimitS ≤ 8, seed?}` → `{routes[{vehicleId, stops[{id, eta, lateMin}], distanceKm, loadKg}], fitness, distanceKm, feasible, violations{lateMin, overloadKg, spoilMin, wrongVehicle}, solver: GA, generations, stoppedBy, travelProvider, travelFallbackReason, latencyMs}`. 422: `UNKNOWN_VEHICLE`, `INVALID_MODE`, `INVALID_PREFIX`, `INVALID_WINDOW`, `DUPLICATE_ID` |
| POST | `/v1/routes/baseline` | Same body (INITIAL only) → same response with `solver: OR_TOOLS`. 503 `BASELINE_UNAVAILABLE` where OR-Tools is not installed (production image) |
Travel times: `ROUTING_PROVIDER` = `haversine` (default; road factor 1.3, IST time-of-day speeds), `osrm` (`OSRM_URL`) or `google` (`GOOGLE_MAPS_API_KEY`); any provider failure falls back to haversine and is reported in `travelFallbackReason`.

### Planning (MANAGER, ADMIN; M7, W-3)
| Method | Path | Notes |
|--------|------|-------|
| POST | `/planning/run` | `{date}` (IST day). Per distribution centre × product: `need = forecast − on-hand − in-transit`; FEFO allocation of free batches at docks/farm gates/cold storages/warehouses; one DRAFT order per (source, centre, product), window 06:00–18:00 IST. Re-running a date replaces that date's planner drafts. → `{date, replacedDrafts, orders[], needs[{siteCode, productCode, forecastKg, onHandKg, inTransitKg, needKg, shortfallKg}]}` |
| POST | `/planning/routes` | `{date, depotSiteId}`. APPROVED orders whose source is the depot → ML `/v1/routes/optimize` → one PLANNED trip per used vehicle (`TRP-yyyymmdd-0001`), a PICKUP stop at the depot + a DROP stop per order, `route_plans` v1 (INITIAL, ACCEPTED). Orders → PLANNED. 422 `NO_APPROVED_ORDERS`, 409 `NO_VEHICLES`, 503 `ROUTING_UNAVAILABLE` |

### Orders (MANAGER, ADMIN)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/orders?status&date&cursor` | Paged, with allocated batches |
| PATCH | `/orders/:id` | DRAFT only: `{quantityKg?, destinationSiteId?, windowStart?, windowEnd?}` (409 `ORDER_NOT_EDITABLE`) |
| POST | `/orders/:id/approve` | DRAFT → APPROVED. Orders without batches (ERP/CSV) get a FEFO allocation from their source site now. Batches → ALLOCATED + trace `ALLOCATED`. Returns `allocatedKg`, `shortfallKg` |
| POST | `/orders/import` | multipart `file` (≤ 1 MB, ≤ 2000 rows). Columns: `external_ref, source_site_code, destination_site_code, product_code, quantity_kg, window_start, window_end`. Per row `CREATED` / `DUPLICATE` (same external_ref) / `REJECTED` with reason |
Order code: `ORD-<yyyymmdd of window start, IST>-0001`.

### ERP integration (no JWT)
`POST /integrations/orders` with `X-Api-Key: <key>` and `X-Signature: <hex HMAC-SHA256(raw body, key)>` (optional `sha256=` prefix). Body `{orders:[ExternalOrder…]}` (1–500, same fields as the CSV in camelCase). Authentication happens **before** validation: 401 `INVALID_API_KEY` / `INVALID_SIGNATURE`, 403 `FORBIDDEN_SCOPE`, then 400. Idempotent per `externalRef` (origin ERP). Rate limit 60/min per IP.
ADMIN: `GET /admin/integration-clients`, `POST /admin/integration-clients {name, scopes:["orders:write"]}` → returns `apiKey` once (only its SHA-256 is stored), `POST /admin/integration-clients/:id/disable`.

### Trips (M7)
| Method | Path | Who | Notes |
|--------|------|-----|-------|
| GET | `/driver/trips/current` | DRIVER | ASSIGNED / PRE_CHECK_DONE / IN_PROGRESS trip (IN_PROGRESS first) with stops, batches, vehicle; `null` if none |
| GET | `/driver/trips?cursor` | DRIVER | History |
| GET | `/trips?status&date` | MANAGER | |
| GET | `/trips/:id` | driver (own), operator, manager | Current-version stops (`site{code,name}`, `buyer{name}`, M12: `batchIds` = batches this drop expects, `null` = any batch on board for DIVERSION_DROP / COLD_STORAGE_DROP / RESCUE_DROP or stops without an order), batches on the trip (M12: `product{code,name,nameHi,nameMr}`, `tagUids[]`) |
| GET | `/trips/:id/route` | driver (own), manager | `{currentVersion, accepted, pending}`. M12: each plan has `distanceKm` and `stopRows` (its non-cancelled stops with site / buyer names, position, ETA); `pending` also `extraKm` (pending − accepted distance) and `canDecline` (false for INCIDENT / DIVERSION / RESCUE) |
| GET | `/trips/:id/cargo-status` | driver (own), manager | Batches on board with grade + remaining shelf life (`telemetry: null` until M8) |
| POST | `/trips/:id/assign` | MANAGER | `{driverId, vehicleId}` → ASSIGNED. 409 `DRIVER_BUSY` / `VEHICLE_BUSY` |
| POST | `/trips/:id/load` | OPERATOR (at the depot) | `{batchIds}`. Each batch must be allocated to an order dropped by this trip (409 `BATCH_NOT_ON_TRIP`, `details.batchIds`) and be at the depot. Batch → LOADED (storage released) + trace `LOADED`. Re-scans are ignored. Loading after a passed pre-check sets the trip back to ASSIGNED |
| POST | `/trips/:id/pre-check` | DRIVER | `{id?, reeferOn, setpointC, doorsClosed, occurredAt?}`. Setpoint must lie in the intersection of the loaded products' safe ranges (clipped to the reefer). Always saved as a `PRE_TRIP_CHECK` event; fail → 422 `PRE_CHECK_FAILED` (`details.problems`: `REEFER_OFF`, `DOORS_OPEN`, `SETPOINT_OUT_OF_RANGE`, `INCOMPATIBLE_CARGO`) |
| POST | `/trips/:id/start` | DRIVER | Needs PRE_CHECK_DONE (409 `PRE_CHECK_REQUIRED`) and ≥ 1 loaded batch. Binds `X-Device-Id` (409 `TRIP_ON_OTHER_DEVICE`); one IN_PROGRESS trip per driver (409 `DRIVER_ON_OTHER_TRIP`) and per vehicle (409 `VEHICLE_IN_USE`). Batches → IN_TRANSIT + `DEPARTED`; orders → IN_TRANSIT; pickup stop completed |
| POST | `/trips/:id/events` | DRIVER | `{id, type: INCIDENT_DELAY\|INCIDENT_BREAKDOWN\|INCIDENT_ACCIDENT\|INCIDENT_ROADBLOCK\|INCIDENT_REEFER_FAULT\|SOS, payload?, photoKey?, voiceKey?, lat?, lng?, occurredAt}`. Idempotent on `id`. **SOS** → CRITICAL `SOS` alert, `alert.raised` to managers, SMS with a maps link to the driver's emergency contact. Incidents → `incident.updated` to managers (handled by the incident engine in M9) |
| POST | `/trips/:id/routes/:version/accept\|decline` | DRIVER | PROPOSED only. Accept supersedes the old plan and cancels its open stops. Decline is refused for `INCIDENT`/`DIVERSION`/`RESCUE` replans (409 `DECLINE_NOT_ALLOWED`) |
| POST | `/trips/:id/stops/:stopId/arrive` | DRIVER | `{arrivedAt?, lat?, lng?}` → ARRIVED |
| POST | `/trips/:id/stops/:stopId/pod` | DRIVER | `{receiverName, signatureKey (POD_SIGNATURE upload), photoKey (POD_PHOTO upload), capturedAt, lat, lng, items[{id, batchId, outcome: ACCEPTED\|PARTIAL\|REJECTED, acceptedKg, reason?, scannedTagUid}]}`. The scan must be one of the batch's tag UIDs or its code (409 `TAG_MISMATCH`). ACCEPTED = full weight; PARTIAL 0 < kg < weight (+ reason); REJECTED 0 kg (+ reason). Batch → DELIVERED / PARTIALLY_DELIVERED / REJECTED with a `DELIVERED`/`REJECTED` trace event. Stop COMPLETED when every expected batch has a PoD; its order → DELIVERED. When all stops are done the trip completes: vehicle AVAILABLE, `co2Kg = distanceKm × emissionFactorKgPerKm` (SYN-16). Rows are idempotent on `items[].id` |

### Operator (OPERATOR, ADMIN; M11)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/operator/summary?date=YYYY-MM-DD` | Today's counts at the operator's site (IST day, default today): `{date, site{id, code, name, type}, registered, graded, stored, dispatched}`. A user without a site → 422 `NO_SITE` |
| GET | `/operator/trips?date=YYYY-MM-DD` | Loadable trips (PLANNED / ASSIGNED / PRE_CHECK_DONE) leaving the operator's site that day: `{date, items[{id, code, status, plannedStart, vehicle{regNo, capacityKg}, driverName, allocated[{id, code, weightKg}], loadedBatchIds[]}]}`. `allocated` = the batches on the current route version's stops. Loading itself is the `LOAD` sync op (or `POST /trips/:id/load`) |

### Control tower (MANAGER, ADMIN; M13)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/control/summary` | `{date, kpis{activeTrips, openCriticalAlerts, atRiskBatches, deliveriesToday, spoilageAvoidedKg}, vehicles[{vehicleId, regNo, tripId, tripCode, driverName, lat, lng, tempC, at}]}`. Definitions in D-151 (IST day; at risk < 12 h; spoilage avoided = kg accepted at diversion / cold-storage / rescue drops, last 30 days). Positions are the last pod reading (null without Redis or before the first packet); live moves come as `vehicle.position` |
| GET | `/control/drivers` | `{items[{id, name, phone, siteId, busyTripCode}]}`: ACTIVE drivers, with the code of the trip they already have (assignment picker) |
| GET | `/control/releases?flavor` | `{items[{id, flavor, channel, versionName, versionCode, minSupportedCode, mandatory, publishedAt, sizeBytes, features, improvements, fixes}]}`: active releases, newest first (filled by the release sync, M15) |

### Sync additions
`LOAD {tripId, batchIds}` (OPERATOR), `TRIP_EVENT {tripId, ...event}`, `POD {tripId, stopId, ...pod}`, `ROUTE_ACCEPT {tripId, version}` (DRIVER). M12: `STOP_ARRIVE {tripId, stopId, arrivedAt?, lat?, lng?}` (DRIVER; same rules as `POST /trips/:id/stops/:stopId/arrive`, a replay is a no-op). Every op type has a role list and anything else is refused (`FORBIDDEN_ROLE`, D-148). M8: `GPS_POINTS {tripId, points[1..500]{at, lat, lng, speedKmh?, accuracyM?}}` (DRIVER, trip IN_PROGRESS, written to InfluxDB `driver_gps`; M12: for a COMPLETED trip the points inside startedAt..completedAt are written and the rest dropped, `{written, dropped}`, D-149), `ALERT_ACK {alertId}` (same rules as `POST /alerts/:id/ack`; replay is idempotent).

### Alerts (M8)
| Method | Path | Roles | Notes |
|--------|------|-------|-------|
| GET | `/alerts` | DRIVER, MANAGER, ADMIN | Filters `status`, `tripId`, cursor pagination. A driver sees only alerts on their own trips |
| POST | `/alerts/:id/ack` | DRIVER, MANAGER, ADMIN | → ACKNOWLEDGED (idempotent); a driver only for their own trip (403); cancels the pending escalation |
| POST | `/alerts/:id/resolve` | MANAGER, ADMIN | → RESOLVED (also records the ack if none); cancels the pending escalation |

Raising an alert: realtime `alert.raised`, Kafka `alerts` event `ALERT_RAISED`, driver in-app + push (SMS if push fails), managers in-app + push + email (verified addresses only) + SMS for CRITICAL. Not acknowledged within remote-config `ackMinutes` (default 5) → ESCALATED, managers texted, `alert.updated`.

### Telemetry (M8)
`GET /trips/:id/telemetry?from=<ISO>&to=<ISO>&every=1m` (MANAGER, ADMIN) → reefer series from InfluxDB (per window: mean values, max shock) plus `band` = the strictest safe limits of the cargo on board. `every` ∈ `1m|5m|15m|1h` (default `1m`); range at most 31 days (`RANGE_TOO_LONG`). Device ingestion is MQTT only: topic `iccms/telemetry/<username>`, 40-byte binary or JSON (`simulator/binary_format.md`).

### Buyers (MANAGER, ADMIN; M9, W-1)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/buyers?type&active&productId&cursor` | Backup buyer registry |
| GET | `/buyers/:id` | |
| POST | `/buyers` | `{name, type: CANNING\|PROCESSING\|LOCAL_MARKET\|DISCOUNT_RETAIL\|COLD_STORAGE, phone (E.164), email?, lat, lng, acceptedProductIds[], minGrade, discountPct 0–100, openingHours, capacityKg?, active?}`. `openingHours` = `{"mon":[["06:00","20:00"]], ...}` with keys `sun..sat`, IST; a range ending before it starts runs past midnight; `"23:59"` as an end means end of day. Unknown products → 422 `UNKNOWN_PRODUCT` |
| PATCH | `/buyers/:id` | Partial update, same rules |
| DELETE | `/buyers/:id` | Soft delete (`active=false`); offers and stops keep the buyer |

### Incidents (MANAGER, ADMIN; M9, W-2)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/incidents?status&tripId&cursor` | `steps` = number of decision-log entries |
| GET | `/incidents/:id` | Incident + full `decisionLog` + offers (with buyer) + rescue trip code |
| GET | `/incidents/:id/offers` | Offers in the order they were sent (`status`: SENT, ACCEPTED, REJECTED, EXPIRED, CANCELLED; no token) |
| POST | `/incidents/:id/action` | Manager override `{action, buyerId?, rescueTripId?, note?}`: `DRIVER_FIX`; `DIVERT_BUYER`/`DIVERT_COLD_STORAGE` + `buyerId` (agreed outside the system: recorded as an accepted offer, route proposed at once; cold storage must be type COLD_STORAGE); `RESCUE_PICKUP` + `rescueTripId` (must be an eligible truck, else 422 `RESCUE_NOT_POSSIBLE` with the reason); `REPLAN` (same stops from the current position); `MANUAL`. Open offers are cancelled first. Closed incident → 409 `INCIDENT_CLOSED` |
| POST | `/incidents/:id/resolve` | `{note?, failed?}` → RESOLVED, or FAILED when the cargo was lost |

**Engine (worker).** Triggers: critical `TEMP_EXCURSION` alerts and driver incident reports (Kafka `alerts`, consumer group `incident-engine`), the spoilage gate (after every shelf-life estimate: remaining shelf life < remaining stop ETA + `safetyMarginH`) and the DRIVER_FIX re-check. One active incident per trip; later triggers are added to its log.
- `TEMP_DRIFT` (reefer ON, slope ≤ `driftSlopeMax` °C/10 min over the last 30 min) → `DRIVER_FIX` alert to the driver → re-check after 15 min: back in range → RESOLVED, else `SPOILAGE_RISK`.
- `REEFER_FAILURE` (reefer OFF, faster warming, or driver report) → nearest reachable cold storage (offer) → rescue truck within `rescueRadiusKm` with a compatible reefer and free capacity (two route proposals: `RESCUE_DROP` on the failing trip, `RESCUE_PICKUP` first on the rescue trip) → buyer offers → `MANUAL`.
- `SPOILAGE_RISK` → buyer offers → `MANUAL`. `DELAY`/road block: still feasible → REPLAN of the same stops; else buyer offers. `BREAKDOWN`/accident → rescue → `MANUAL`.
- `MANUAL` raises a CRITICAL `SPOILAGE_RISK` alert to managers (push, verified email, SMS).
- Every step is appended to `decisionLog`: `{at, step, reason, inputs?, candidates?, chosen?, by?}`. Steps: `CLASSIFIED, TRIGGER_NOTED, ESCALATED, DRIVER_FIX, DRIVER_FIX_RECOVERED, DRIVER_FIX_FAILED, DELAY_CHECK, COLD_STORAGE_SEARCH, RESCUE_SEARCH, RESCUE_PLANNED, BUYER_SEARCH, OFFER_SENT, OFFER_ACCEPTED, OFFER_REJECTED, OFFER_EXPIRED, ROUTE_PROPOSED, ROUTE_ACCEPTED, MANUAL, MANUAL_OVERRIDE, NO_CARGO, RESOLVED, FAILED`. Searches list eligible candidates and the excluded ones with a reason (`INACTIVE, ALREADY_OFFERED, WRONG_TYPE, PRODUCT_NOT_ACCEPTED, GRADE_TOO_LOW, CLOSED_AT_ETA, NO_CAPACITY, NOT_REACHABLE_BEFORE_SPOILAGE`; rescue: `SAME_TRIP, NO_POSITION, TOO_FAR, NO_CAPACITY, INCOMPATIBLE_TEMPERATURE, NOT_REACHABLE_BEFORE_SPOILAGE`).
- Reroutes are `route_plans` with status PROPOSED + their stops, sent as `route.proposed` (trip room, managers) and a push to the driver; the trip switches when the driver accepts (`POST /trips/:id/routes/:version/accept`). No answer within `ackMinutes` → managers are told (push, email, SMS). Accepting a route cancels orders whose drop is on no live route any more.
- PoD at a `RESCUE_DROP` hands the batches over to the rescue trip (outcome ACCEPTED only; trace `RESCUED`; batches stay IN_TRANSIT) and completes the rescue truck's `RESCUE_PICKUP`. PoD at a diversion / cold-storage / rescue drop resolves the incident.

### Diversion offer page (public, no JWT, outside `/api/v1`; W-1)
The buyer gets an SMS: `APP_BASE_URL/offer/<token>` (32 random bytes, base64url; only its SHA-256 is stored), valid `offerMinutes` (default 10).
- `GET /offer/:token` → HTML offer (product, quantity, grade, discount, shelf life left, deadline) with Accept / Reject buttons. Unknown → 404; expired or already answered → 410.
- `POST /offer/:token/accept` / `POST /offer/:token/reject` → HTML confirmation. A token answers once (conditional update): a second answer, or an answer after expiry → 410.
- Accept → batches `DIVERTED` (trace `DIVERTED`), new route with the buyer (`DIVERSION_DROP`) or cold storage (`COLD_STORAGE_DROP`) stop first, proposed to the driver. Reject or expiry → next candidate.

### Reports (MANAGER, ADMIN; M9, SYN-15/16/17)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/reports/batches/:id/compliance?format=html\|csv\|json` | HACCP-style record: per trip leg the 1-min temperature log from InfluxDB (mean per minute, same query as the trip chart), min/mean/max, excursions outside the product's safe range, cargo alerts; all trace events with hashes and the chain verdict; PoD. CSV = the 1-min log (`batch_code, product, trip_code, time_utc, time_ist, temp_c, humidity_pct, safe_min_c, safe_max_c, in_range`). If InfluxDB cannot be read the report still opens with a note |
| GET | `/reports/traceability?from&to&format=csv` | FSMA 204-style KDE export (≤ 92 days, ≤ 50,000 events): `event_time_utc, cte, event_type, traceability_lot_code, product_code, product_description, quantity, unit, location, reference_trip, outcome, trace_seq, record_hash`. CTE mapping: REGISTERED → FIRST_LAND_BASED_RECEIVING (fish) / HARVESTING (produce); STORED → COOLING; DEPARTED, DIVERTED, RESCUED → SHIPPING; RECEIVED, DELIVERED → RECEIVING; other events are not CTEs |
| GET | `/reports/emissions?from&to&format=json\|csv` | Completed trips (≤ 366 days): distance, `co2Kg` stored at completion, totals, and the current factor + source |
| GET | `/reports/reefer-health` | Per vehicle: baseline pull-down rate and the last 8 weekly rows (rate, degradation %, flagged) |

### Realtime (Socket.IO, path `/rt`)
Connect with `auth: {token: <Supabase access token>, flavor}`. Same checks as HTTP (valid JWT, linked ACTIVE user, role allowed for the flavor), else `error {code: UNAUTHORIZED}` + disconnect. Rooms: `user:<id>` always, `role:manager` for MANAGER/ADMIN. `trip.join {tripId}` → ack `{ok:true}` for managers or the trip's driver, `{ok:false, code:FORBIDDEN}` otherwise; `trip.leave {tripId}`. Server events used so far: `trip.updated`, `route.updated`, `cargo.status`, `alert.raised`, `alert.updated`, `incident.updated` (managers + trip room), `route.proposed` (trip room + managers; the driver also gets a push), `offer.updated` (managers), `vehicle.position` (managers; latest truck position + temperature). Since M8 the worker emits through Redis, so events reach clients on any API instance.
