#!/usr/bin/env bash
# Fetch active ML models and verify sha256 (see scripts/fetch_models.py).
set -euo pipefail
exec python3 "$(dirname "$0")/fetch_models.py" "$@"
