#!/bin/sh
# Dev entrypoint: build the password file from MOSQ_USERS ("user:password" pairs, whitespace separated).
# The password may itself contain ":"; only the first ":" splits user from password.
set -eu
PASSWD=/mosquitto/data/passwd
mkdir -p /mosquitto/data
: > "$PASSWD"
for pair in ${MOSQ_USERS:-}; do
  user="${pair%%:*}"
  pass="${pair#*:}"
  mosquitto_passwd -b "$PASSWD" "$user" "$pass"
done
# Load tests: MOSQ_DEVICE_COUNT=500 adds dev-001..dev-500 with password "DEV-NNN:$MOSQ_DEVICE_SECRET".
i=1
while [ "$i" -le "${MOSQ_DEVICE_COUNT:-0}" ]; do
  n=$(printf '%03d' "$i")
  mosquitto_passwd -b "$PASSWD" "dev-$n" "DEV-$n:${MOSQ_DEVICE_SECRET:-dev-device-secret}"
  i=$((i + 1))
done
chmod 0700 "$PASSWD"
chown mosquitto:mosquitto "$PASSWD" 2>/dev/null || true
# mosquitto.conf points at /mosquitto/config/passwd; use the generated file instead.
sed "s#/mosquitto/config/passwd#$PASSWD#" /mosquitto/config/mosquitto.conf > /mosquitto/data/mosquitto.conf
exec mosquitto -c /mosquitto/data/mosquitto.conf
