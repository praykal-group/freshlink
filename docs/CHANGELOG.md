# Changelog

All notable changes, per milestone (Keep a Changelog style).

## [m03] - 2026-11-13
### Added
- Supabase JWT verification (JWKS) and the guard chain: version gate (426), auth + linked user, flavor/role, driver device, roles, per-user rate limit.
- `/me`, `/me/session`, `/me/language`, `/me/logout`; admin user create/invite/disable/enable/resend via the Supabase admin API.
- Send SMS Hook (Standard Webhooks signature, 5/hour/phone), SmsService with console + httpSMS providers, httpSMS delivery webhook.
- Masters CRUD + `/masters/bundle` with ETag/304, typed remote config, audit log interceptor, Swagger at `/api/docs` (non-prod).
- 78 unit tests.
### Changed
- Seed stores device secrets as bcrypt.

## [m02] - 2026-11-13
### Added
- Prisma schema for all 36 tables (Section 7), init + constraints migrations, `roles.sql` (iccms_migrator / iccms_app, insert-only trace_events), idempotent seed, `PrismaService`, DB readiness check, InfluxDB bucket setup script, DATABASE.md.

## [m01] - 2026-11-13
### Added
- Monorepo skeleton: NestJS `server/` (api + worker, env schema, logging, error filter, health), FastAPI `ml/service` (internal token, health), Flutter `client/` with driver/operator/manager flavors.
- Dev compose (postgres + ml), CI workflow, flavor isolation and secret scan scripts, docs structure.
### Removed
- Vite/React template in `server/`; non-Android Flutter runners.
