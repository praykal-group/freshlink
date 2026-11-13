# Shelf-life dataset sources

Status: **no observations collected yet** (2026-11-13). No Cox model is registered; the service uses the **Q10 fallback** for every prediction (method `Q10_FALLBACK`). This is recorded in `docs/TESTING.md`.

Every row of `observations.csv` must carry a `source_id` listed here. Allowed sources: published storage studies (cite the table/figure), and our own controlled storage test (3 temperatures, checks every 12 h).

| source_id | Type (study / own test) | Citation or test protocol | Products | Temperatures (°C) | Rows | Notes |
|-----------|-------------------------|---------------------------|----------|-------------------|------|-------|
| | | | | | | |

Q10 reference values in the seed (`server/prisma/seed.ts`) are indicative and must also be replaced with cited values before results are reported.
