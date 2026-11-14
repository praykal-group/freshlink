#!/usr/bin/env bash
# Binary isolation check (Section 11): the compiled Dart code (lib/<abi>/libapp.so) of a flavor's
# APK must contain only its own module tag 'iccms-module-<flavor>', never another dashboard's.
#
#   scripts/verify_apk_isolation.sh <flavor> [path/to.apk]
set -euo pipefail

flavor="${1:-}"
case "$flavor" in driver|operator|manager) ;; *) echo "usage: $0 <driver|operator|manager> [apk]" >&2; exit 2;; esac
root="$(git rev-parse --show-toplevel)"
apk="${2:-$root/client/build/app/outputs/flutter-apk/app-${flavor}-release.apk}"
[[ -f "$apk" ]] || { echo "APK not found: $apk" >&2; exit 2; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python - "$apk" "$tmp" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
libs = [n for n in z.namelist() if n.endswith('/libapp.so')]
if not libs:
    sys.exit('no libapp.so in the APK (not a release build?)')
for n in libs:
    z.extract(n, sys.argv[2])
print('\n'.join(libs))
PY

# Exact tags: strings in libapp.so are packed without separators, so a loose pattern can run on
# into the next string. Own tag present + every other flavor's tag absent.
fail=0
while IFS= read -r so; do
  abi=$(basename "$(dirname "$so")")
  found=()
  for f in driver operator manager; do
    if grep -aqF "iccms-module-$f" "$so"; then found+=("$f"); fi
  done
  echo "$abi: ${found[*]:-<none>}"
  if [[ "${found[*]:-}" != "$flavor" ]]; then fail=1; fi
done < <(find "$tmp" -name libapp.so)

if [[ $fail -ne 0 ]]; then echo "verify_apk_isolation: FAIL ($flavor APK must contain only iccms-module-$flavor)"; exit 1; fi
echo "verify_apk_isolation: OK ($flavor)"
