#!/usr/bin/env bash
# InfluxDB 2.7 bucket + retention setup (Section 7, SYN-12). Idempotent.
# Usage: INFLUX_URL=http://localhost:8086 INFLUX_TOKEN=... INFLUX_ORG=iccms ./deploy/influx/setup.sh
set -euo pipefail
: "${INFLUX_URL:?}" "${INFLUX_TOKEN:?}" "${INFLUX_ORG:=iccms}" "${INFLUX_BUCKET:=telemetry}"
RETENTION="${INFLUX_RETENTION:-30d}"
args=(--host "$INFLUX_URL" --token "$INFLUX_TOKEN" --org "$INFLUX_ORG")

if influx bucket list "${args[@]}" --name "$INFLUX_BUCKET" >/dev/null 2>&1; then
  id=$(influx bucket list "${args[@]}" --name "$INFLUX_BUCKET" --hide-headers | awk '{print $1}')
  influx bucket update "${args[@]}" --id "$id" --retention "$RETENTION"
  echo "bucket $INFLUX_BUCKET exists; retention set to $RETENTION"
else
  influx bucket create "${args[@]}" --name "$INFLUX_BUCKET" --retention "$RETENTION"
  echo "bucket $INFLUX_BUCKET created with retention $RETENTION"
fi
# Measurements (schemaless, documented in docs/DATABASE.md): reefer, driver_gps, beacon
