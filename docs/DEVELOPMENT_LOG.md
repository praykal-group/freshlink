# Development Log

## M1 — Repository, Architecture and Tooling (2026-11-13)

**Implemented**
- Root: `.gitignore` (covers all Section 19.5 never-commit items), `.editorconfig`, `README.md` skeleton, `release/versions.json`.
- `server/` (NestJS, replaces the Vite/React template): `api` (`src/main.ts`) and `worker` (`src/worker.ts`) entry points, zod env schema with fail-fast (refuses `SMS_PROVIDER=console` in production), typed `AppConfig`, nestjs-pino logging with requestId + redaction, global error envelope filter (incl. Prisma P2002/P2025 mapping), `/api/v1/health` and `/api/v1/health/ready` (checks ML).
- `ml/service/`: FastAPI app with `X-Internal-Token` middleware (constant-time compare) and `/health`; Dockerfile; `models/registry.json`; pytest for 200/401.
- `client/` (Flutter): package renamed `iccms`, Android namespace `in.iccms.app`, 3 product flavors (`in.iccms.driver|operator|manager`) with app names and per-flavor permission manifests; `bootstrap.dart`, `main_{driver,operator,manager}.dart`, `apps/<flavor>/{router,module_tag}.dart`, `FlavorRouter` interface in `core/config`, folder skeleton for `core/` and `shared/`; widget test per flavor; `env/dev.json`.
- `deploy/docker-compose.dev.yml` (postgres + ml), `scripts/check_flavor_isolation.sh`, `scripts/secret_scan.sh`, `.github/workflows/ci.yml`.
- Docs from Section 18 created; DECISIONS D-01…D-30.

**Removed:** `server/` React template; `client/{ios,macos,linux,windows}`; `client/lib/main.dart`.

**Tests:** not run by user instruction. Build/analyze/scripts results are in TESTING.md.

**Limitations / pending:** Kafka, Redis, Mosquitto, InfluxDB not in the dev stack yet (D-26). Theme is a seed-colour placeholder until M10. No launcher icons per flavor yet (M10).

**Repro**
```bash
cd server && cp .env.example .env && npm install && npm run dev:api
cd ml/service && pip install -r requirements.txt && ML_INTERNAL_TOKEN=dev-internal-token uvicorn app.main:app --port 8000
cd client && flutter run --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/dev.json
```

## M2 — Database Schema, Migrations and Seed (2026-11-13)

**Implemented**
- `server/prisma/schema.prisma`: 36 tables, 40 enums, indexes (incl. DESC and GIN) per Section 7.
- Migrations: `20261113000000_init` (generated offline), `20261113000100_constraints` (CHECKs, partial unique active-device index, trace_events revoke).
- `prisma/sql/roles.sql`: idempotent role creation, default privileges, insert-only `trace_events` for `iccms_app`.
- `prisma/seed.ts`: idempotent upserts for sites, storage units, products, users, vehicles, IoT devices, buyers, app_config.
- `src/infra/prisma/{prisma.service,prisma.module}.ts`, wired into api + worker; `/health/ready` now checks the DB; `DATABASE_URL` required.
- `deploy/influx/setup.sh`; npm scripts `db:migrate|deploy|reset|seed`.

**Files created:** `server/prisma/**`, `server/src/infra/prisma/*`, `deploy/influx/setup.sh`. **Modified:** `server/package.json`, `server/src/{app.module,worker.module}.ts`, `server/src/config/env.schema.ts`, `server/src/modules/health/health.service.ts`, docs.

**Tests:** static checks only; DB checks deferred (TESTING.md).

**Limitations / pending:** product limits are indicative values; migrations not yet applied to any database.

**Repro**
```bash
psql "$MASTER_URL" -v app_password=... -v migrator_password=... -f server/prisma/sql/roles.sql
cd server && DATABASE_URL=postgresql://iccms_migrator:...@localhost:5432/iccms npm run db:deploy && npm run db:seed
```

## M3 — Backend Foundation, Authentication and RBAC (2026-11-13)

**Implemented**
- `common/auth/`: `JwtVerifier` (jose, injected key source), `AuthUser`/`AppRequest`, decorators (`@Public`, `@Roles`, `@AllowUnverifiedEmail`, `@SkipDeviceCheck`, `@CurrentUser`), `Ownership` helpers.
- `common/guards/`: `VersionGateGuard`, `SupabaseAuthGuard`, `FlavorRoleGuard`, `DeviceGuard`, `RolesGuard`, `UserThrottlerGuard`, registered in that order.
- `common/interceptors/audit.interceptor.ts`; `common/cache/ttl-cache.ts` (TTL cache + rate limiter, D-35).
- `infra/supabase/supabase-admin.service.ts` (create phone user, invite email, ban/unban, email-confirmed lookup).
- Modules: `auth` (/me*), `users` (admin), `sms` (console + httpSMS), `hooks` (Supabase Send SMS Hook, httpSMS webhook), `masters` (CRUD + bundle/ETag), `remote-config` (typed keys).
- `main.ts`: raw body for hook signatures, Swagger (non-prod), trust proxy. Env: `SUPABASE_URL` required; httpSMS settings validated together.

**Tests:** 78 unit tests pass (TESTING.md). e2e deferred.

**Limitations / pending:** caches and rate limits are in-process (D-35); no Supabase project yet; the "SMS gateway down" alert is a log line until M8; API not booted (no DB credentials).

**Repro**
```bash
cd server && npm test
```
