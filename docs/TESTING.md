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

## Measured metrics
None yet.

## Known issues
None recorded.
