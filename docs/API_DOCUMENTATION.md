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
