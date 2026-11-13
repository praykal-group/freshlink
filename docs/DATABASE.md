# Database

PostgreSQL 16 (RDS in prod), Prisma 6. Schema: `server/prisma/schema.prisma`. Spec: `PROJECT_IMPLEMENTATION.md` Section 7.

## Conventions
`snake_case` tables/columns (`@@map`/`@map`), `uuid` PKs (client-generated for `batches`, `trip_events`, `proof_of_delivery`, `sync_ops`), `timestamptz`, `numeric(12,3)` for kg and money, Prisma enums, soft delete via `active`.

## Tables (36)
| Area | Tables |
|------|--------|
| Identity | `users`, `device_registrations` |
| Masters | `sites`, `storage_units`, `vehicles`, `iot_devices`, `products`, `app_config` |
| Batches | `batches`, `batch_tags`, `batch_images`, `quality_grades`, `batch_edit_requests`, `shelf_life_estimates`, `batch_exposure` |
| Planning | `demand_forecasts`, `dispatch_orders`, `order_batches` |
| Trips | `trips`, `trip_stops`, `trip_batches`, `route_plans`, `trip_events`, `proof_of_delivery` |
| Alerts | `alerts`, `notifications`, `incidents`, `backup_buyers`, `diversion_offers` |
| Trace | `trace_events` (bigserial, insert-only for the app) |
| Ops | `reefer_health`, `app_releases`, `app_installs`, `sync_ops`, `integration_clients`, `audit_logs` |

Key relations: `batches → products, sites (source/current), storage_units, users (creator)`; `trips → vehicles, users (driver), sites (depot)`; `trip_stops → trips, sites | backup_buyers, dispatch_orders`; `incidents → trips, alerts`; `diversion_offers → incidents, backup_buyers`; `trace_events → batches`.

## Constraints beyond Prisma (`migrations/20261113000100_constraints`)
- `users`: `phone OR email` required; DRIVER/OPERATOR must have a phone; email stored lower-case.
- `device_registrations`: partial unique `(user_id, flavor) WHERE active` (one active device, DA-FR-01).
- Range checks: storage unit and product temperature/humidity ranges, `batches.weight_kg > 0`, `trace_events.seq >= 1`.
- Re-applies `REVOKE UPDATE, DELETE, TRUNCATE ON trace_events FROM iccms_app` (W-4).

Notable indexes: `batches(created_at DESC)`, `quality_grades/shelf_life_estimates(batch_id, created_at DESC)`, `alerts(status, created_at DESC)`, GIN `backup_buyers(accepted_product_ids)`, `dispatch_orders UNIQUE(origin, external_ref)`, `trace_events UNIQUE(batch_id, seq)`.

## Migrations
| Name | Content |
|------|---------|
| `20261113000000_init` | All tables, enums, indexes, FKs (generated with `prisma migrate diff --from-empty`) |
| `20261113000100_constraints` | CHECKs, partial unique index, trace_events revoke |

Commands (from `server/`): `npm run db:migrate` (dev), `npm run db:deploy` (prod, with `DATABASE_URL=$MIGRATION_DATABASE_URL`), `npm run db:reset`, `npm run db:seed`.

## Roles (`prisma/sql/roles.sql`, D-15)
| Role | Rights |
|------|--------|
| `iccms_migrator` | Owns schema objects; runs migrations |
| `iccms_app` | SELECT/INSERT/UPDATE/DELETE on all tables via default privileges; **INSERT/SELECT only on `trace_events`**; no TRUNCATE |

Order on a fresh DB: run `roles.sql` as master → `prisma migrate deploy` as `iccms_migrator` → run `roles.sql` again (grants on existing tables) → app connects as `iccms_app`.

## Seed (`prisma/seed.ts`, idempotent)
6 sites (2 docks, 1 farm gate, 1 cold storage, 2 distribution centres), 11 storage units, 10 products, 6 users (admin, manager, 2 drivers, 2 operators; phones overridable with `SEED_<KEY>_PHONE`), 3 vehicles + 3 IoT devices (`DEV-001..003`), 6 backup buyers incl. 2 cold storages, default `app_config`. Existing `app_config` values are never overwritten.
Product limits are **indicative prototype values**, not sourced figures; replace them with values from cited storage guides before reporting results. `emissionFactorKgPerKm` is a marked placeholder (SYN-16).

## InfluxDB
Bucket `telemetry`, 30-day retention (`deploy/influx/setup.sh`). Measurements: `reefer` (tags device_id, vehicle_id, trip_id), `driver_gps` (trip_id, driver_id), `beacon` (site_id, beacon_id). Fields per Section 7.
