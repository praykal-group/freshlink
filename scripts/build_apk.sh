#!/usr/bin/env bash
# Build a flavor's release APKs (Section 11): reads release/versions.json, builds with the flavor's
# entry point, obfuscates, one APK per ABI (D-146: arm64-v8a and armeabi-v7a, each < 40 MB), copies
# them to dist/iccms-<flavor>-<versionName>-<versionCode>-<abi>.apk and prints SHA-256 and size.
# Each ABI is its own build (not --split-per-abi): that flag adds 1000/2000 to the versionCode,
# which the update API and the 426 minimum-version check compare as-is.
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

read -r version_name version_code < <(python - "$root/release/versions.json" "$flavor" <<'PY' | tr -d '\r'
import json, sys
v = json.load(open(sys.argv[1]))[sys.argv[2]]
print(v["versionName"], v["versionCode"])
PY
)
[[ -f android/key.properties ]] || echo "WARNING: android/key.properties missing - this APK is signed with the DEBUG key (local testing only)." >&2

flutter pub get >/dev/null
mkdir -p "$root/dist"
for abi in arm64-v8a armeabi-v7a; do
  case "$abi" in arm64-v8a) platform=android-arm64;; armeabi-v7a) platform=android-arm;; esac
  flutter build apk --release --flavor "$flavor" -t "lib/main_${flavor}.dart"     --target-platform "$platform"     --build-name="$version_name" --build-number="$version_code"     --dart-define-from-file="$env_file"     --obfuscate --split-debug-info="build/symbols/$flavor/$abi"

  src="build/app/outputs/flutter-apk/app-${flavor}-release.apk"
  out="$root/dist/iccms-${flavor}-${version_name}-${version_code}-${abi}.apk"
  # Windows Python ends lines with CRLF: without `tr -d '\r'` the versionCode carried a \r into the
  # file name, which Windows tools could not open (TESTING.md M12).
  read -r sha size < <(python - "$src" "$out" <<'PY' | tr -d '\r'
import hashlib, shutil, sys
shutil.copyfile(sys.argv[1], sys.argv[2])
d = open(sys.argv[2], 'rb').read()
print(hashlib.sha256(d).hexdigest(), len(d))
PY
)
  echo "apk:    $out"
  echo "abi:    $abi"
  echo "sha256: $sha"
  echo "bytes:  $size ($(( size / 1024 / 1024 )) MB)"
done
