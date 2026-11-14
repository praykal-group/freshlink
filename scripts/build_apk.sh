#!/usr/bin/env bash
# Build one release APK (Section 11): reads release/versions.json, builds with the flavor's entry
# point, obfuscates, then copies it to dist/iccms-<flavor>-<versionName>-<versionCode>.apk and
# prints its SHA-256 and size.
#
#   scripts/build_apk.sh <driver|operator|manager> [dev|prod]
#
# Signing comes from client/android/key.properties (see docs/BUILD_GUIDE.md); without it Gradle
# signs with the debug key and warns. Env values come from client/env/<env>.json (no secrets).
set -euo pipefail

flavor="${1:-}"; env_name="${2:-prod}"
case "$flavor" in driver|operator|manager) ;; *) echo "usage: $0 <driver|operator|manager> [dev|prod]" >&2; exit 2;; esac

root="$(git rev-parse --show-toplevel)"
cd "$root/client"
env_file="env/${env_name}.json"
[[ -f "$env_file" ]] || { echo "missing $env_file (copy env/example.json)" >&2; exit 2; }

read -r version_name version_code < <(python - "$root/release/versions.json" "$flavor" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))[sys.argv[2]]
print(v["versionName"], v["versionCode"])
PY
)
[[ -f android/key.properties ]] || echo "WARNING: android/key.properties missing - this APK is signed with the DEBUG key (local testing only)." >&2

flutter pub get >/dev/null
flutter build apk --release --flavor "$flavor" -t "lib/main_${flavor}.dart" \
  --target-platform android-arm,android-arm64 \
  --build-name="$version_name" --build-number="$version_code" \
  --dart-define-from-file="$env_file" \
  --obfuscate --split-debug-info="build/symbols/$flavor"

src="build/app/outputs/flutter-apk/app-${flavor}-release.apk"
mkdir -p "$root/dist"
out="$root/dist/iccms-${flavor}-${version_name}-${version_code}.apk"
cp "$src" "$out"
sha=$(sha256sum "$out" | cut -d' ' -f1)
size=$(wc -c < "$out" | tr -d ' ')
echo "apk:    $out"
echo "sha256: $sha"
echo "bytes:  $size ($(( size / 1024 / 1024 )) MB)"
