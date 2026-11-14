/**
 * Unit tests run on real time. Importing @prisma/client loads server/.env into process.env, and a dev
 * .env may set TELEMETRY_TIME_SCALE=60 for the pipeline test; Prisma never overrides a variable that
 * is already set, so pinning it here keeps unit tests independent of the local .env.
 */
process.env.TELEMETRY_TIME_SCALE = '1';
