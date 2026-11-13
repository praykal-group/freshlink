#!/usr/bin/env bash
# Simple pre-commit secret scan (Section 19.5). Scans tracked + staged files.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PATTERN='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|password=[A-Za-z0-9_-]{4,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
hits=$(git ls-files -co --exclude-standard \
  | grep -vE '(^|/)(package-lock\.json|pubspec\.lock)$|\.(png|jpg|jpeg|webp|ico|onnx)$|^scripts/secret_scan\.sh$' \
  | xargs -r grep -nIE "$PATTERN" 2>/dev/null || true)
if [[ -n "$hits" ]]; then
  echo "Possible secrets found:"; echo "$hits"; exit 1
fi
echo "secret_scan: OK"
