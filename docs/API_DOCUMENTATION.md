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
