#!/usr/bin/env bash
# Module rule (Section 5.2): client/lib/apps/<flavor>/ must never import another apps/ folder;
# core/ and shared/ must never import apps/.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/client/lib"
fail=0
for dir in apps/*/; do
  flavor=$(basename "$dir")
  bad=$(grep -rnE "import ['\"](package:[a-z_]+/)?(\.\./)*apps/" "$dir" \
        | grep -vE "apps/${flavor}/" || true)
  # relative imports climbing out of the flavor folder into a sibling flavor
  rel=$(grep -rnE "import ['\"]\.\./\.\./apps/|import ['\"]\.\./(driver|operator|manager)/" "$dir" \
        | grep -vE "/${flavor}/" || true)
  if [[ -n "$bad$rel" ]]; then echo "[$flavor] cross-flavor import:"; echo "$bad$rel"; fail=1; fi
done
for dir in core shared; do
  [[ -d $dir ]] || continue
  bad=$(grep -rnE "import ['\"].*apps/" "$dir" || true)
  if [[ -n "$bad" ]]; then echo "[$dir] must not import apps/:"; echo "$bad"; fail=1; fi
done
[[ $fail -eq 0 ]] && echo "check_flavor_isolation: OK"
exit $fail
