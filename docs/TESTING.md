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

## Measured metrics
None yet.

## Known issues
None recorded.
