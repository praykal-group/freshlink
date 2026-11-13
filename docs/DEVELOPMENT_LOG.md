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
