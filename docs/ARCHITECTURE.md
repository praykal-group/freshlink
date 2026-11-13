# Architecture

## Runtime
See `PROJECT_IMPLEMENTATION.md` Section 5.1 for the full target diagram. Current state (M1):

```
client (Flutter: driver | operator | manager APK, web console)
        │ HTTPS  X-App-Flavor
        ▼
server  api (NestJS, /api/v1)  ──HTTP X-Internal-Token──>  ml/service (FastAPI)
server  worker (NestJS app context; consumers/jobs from M8)
postgres 16 (schema from M2)
```

## Folder map
| Folder | Content |
|--------|---------|
| `server/` | NestJS backend (spec name `backend/`, D-25). `src/{config,common,infra,modules,workers}` |
| `client/` | Flutter apps (spec name `mobile/`, D-25). `lib/{core,shared,apps/<flavor>}` |
| `ml/service/` | FastAPI inference service; `ml/training/` offline training |
| `simulator/` | IoT simulator (M8) |
| `deploy/` | docker compose, nginx, mosquitto, aws |
| `scripts/` | build, isolation, secret scan, deploy helpers |
| `release/` | per-flavor versions + release notes |

## Module rules
- Backend: each module = module/controller/service/dto/spec. Modules talk via exported services only.
- Mobile: `apps/<flavor>/` imports only `core/` and `shared/`; never another `apps/` folder. `core/` and `shared/` never import `apps/`. Checked by `scripts/check_flavor_isolation.sh`.
