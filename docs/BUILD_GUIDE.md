# Build Guide

The three Android apps and the web console are one Flutter project in `client/` (the spec's
`mobile/`, D-01). Each app is an Android product flavor with its own entry point (Section 11).

| Flavor | App name | applicationId | Entry point | Roles | Accent |
|--------|----------|---------------|-------------|-------|--------|
| `driver` | I-CCMS Driver | `in.iccms.driver` | `lib/main_driver.dart` | DRIVER | Glacier Cyan |
| `operator` | I-CCMS Operator | `in.iccms.operator` | `lib/main_operator.dart` | OPERATOR | Fresh Leaf |
| `manager` | I-CCMS Control Tower | `in.iccms.manager` | `lib/main_manager.dart` | MANAGER, ADMIN | Indigo |

## 1. Toolchain

- **Flutter 3.44.0** (stable, Dart 3.12.0) — pinned in `client/.fvmrc` and `pubspec.yaml` (`environment.flutter`).
  Package versions are exact in `pubspec.yaml`; `pubspec.lock` is committed.
- Android SDK 36, build-tools 36, JDK 17+ (the dev PC uses JDK 21). Accept the SDK licences once:
  `flutter doctor --android-licenses`.
- Chrome for the web console.

## 2. Environment files (`client/env/*.json`)

Only **non-secret** values (Section 11): API/WS URLs, update channel, Supabase URL + **publishable**
key, Google web client id, Firebase app options. Never the Supabase service-role key.

```bash
cp client/env/example.json client/env/prod.json   # then fill in the values
```

`env/dev.json` points at the local stack from the Android emulator (`10.0.2.2`). With the Supabase
values empty the apps start and the login screens say "Sign-in is not set up in this build".
Firebase values empty → push and Crashlytics are off (the backend falls back to SMS for drivers).
Firebase options are read from the env file, so **no `google-services.json` is needed** (D-120).

## 3. Code generation

```bash
cd client
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift database code
flutter gen-l10n                                           # EN / HI / MR strings
```

The local database is **SQLCipher** (`hooks: user_defines: sqlite3: source: sqlcipher` in
`pubspec.yaml`, D-118): the native library is fetched by `package:sqlite3`'s build hook from its
GitHub release and checked against the SHA-256 published in the package.

## 4. Run (debug)

```bash
cd client
flutter run --flavor driver   -t lib/main_driver.dart   --dart-define-from-file=env/dev.json
flutter run --flavor operator -t lib/main_operator.dart --dart-define-from-file=env/dev.json
flutter run --flavor manager  -t lib/main_manager.dart  --dart-define-from-file=env/dev.json
flutter run -d chrome         -t lib/main_manager.dart  --dart-define-from-file=env/dev.json   # web console
```

## 5. Release APKs

```bash
scripts/build_apk.sh driver   prod   # → dist/iccms-driver-<ver>-<code>-arm64-v8a.apk + ...-armeabi-v7a.apk (D-146)
scripts/build_apk.sh operator prod
scripts/build_apk.sh manager  prod
```

The script reads `release/versions.json` (independent `versionName` / `versionCode` per flavor),
builds `--release --obfuscate --split-debug-info=build/symbols/<flavor>` for `android-arm,android-arm64`,
copies the APK to `dist/iccms-<flavor>-<versionName>-<versionCode>.apk` and prints its SHA-256 and size.
Keep `build/symbols/<flavor>` for each release: Crashlytics stack traces need it.

Web console:

```bash
cd client && flutter build web --release -t lib/main_manager.dart --dart-define-from-file=env/prod.json --base-href /console/
```

## 6. Signing

One upload keystore for all three flavors (the package ids differ, so there is no conflict).

```bash
keytool -genkeypair -v -keystore ~/keys/iccms-upload.jks -alias iccms -keyalg RSA -keysize 4096 -validity 10000
```

`client/android/key.properties` (gitignored, Section 19.5) points to it — the keystore stays
**outside** the repo:

```properties
storeFile=C:/Users/<you>/keys/iccms-upload.jks
storePassword=...
keyAlias=iccms
keyPassword=...
```

Without `key.properties`, Gradle signs release builds with the **debug** key and prints a warning.
Those APKs are for local testing only: an app signed with the debug key can never be updated by a
production APK (different certificate).

**Keep two offline backups of the keystore and its passwords. If it is lost, installed apps can
never be updated.** CI gets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (M15).

### Certificate fingerprints (fill in when the upload key is created)

| Key | SHA-1 (Google OAuth Android client) | SHA-256 (updater check, Section 12.4) |
|-----|-------------------------------------|----------------------------------------|
| debug (`~/.android/debug.keystore`) | see `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` | same command |
| release (upload key) | _not created yet_ | _not created yet_ |

Read them with `keytool -list -v -keystore <file> -alias <alias>` or, from a built APK,
`apksigner verify --print-certs dist/iccms-manager-*.apk`.

## 7. Google sign-in (manager)

Google Cloud console → APIs & Services → Credentials:
1. **Web client** (used by Supabase and as `GOOGLE_WEB_CLIENT_ID` / `serverClientId` in the app).
2. **Android client** for `in.iccms.manager` with the **debug** SHA-1, and a second one with the
   **release** SHA-1. Google sign-in fails with `DEVELOPER_ERROR` if the APK's signing SHA-1 is not
   registered.
3. In Supabase → Auth → Providers → Google: the web client id + secret; add both Android client ids
   as authorized client ids; "Skip nonce check" stays OFF.
4. Supabase redirect URLs: `in.iccms.manager://login-callback` (password reset / OAuth on Android) and
   the console URL (web OAuth redirect).

## 8. Checks

```bash
cd client && flutter analyze && flutter test        # unit + widget tests (incl. text scale 2.0, EN/HI/MR)
scripts/check_flavor_isolation.sh                   # no cross-flavor imports
scripts/verify_apk_isolation.sh driver              # after a release build: each ABI's libapp.so holds only its own module tag
scripts/verify_apk_isolation.sh operator
scripts/verify_apk_isolation.sh manager
```

Each flavor module defines `kModuleTag = 'iccms-module-<flavor>'` and uses it in its router; Dart AOT
tree-shaking drops the other flavors' code because their `main_*.dart` never imports it.

## 9. Per-flavor Android resources

`android/app/src/<flavor>/`: `AndroidManifest.xml` with only that app's permissions (driver:
location, foreground service, notifications, microphone, camera; operator: camera, NFC, Bluetooth,
microphone; manager: notifications + the `in.iccms.manager://login-callback` deep link) and its own
launcher icon (`res/mipmap-*/ic_launcher.png`, Deep Ocean with the flavor accent band and letter).
`src/main/AndroidManifest.xml`: `allowBackup=false`, no cloud backup / device transfer,
`usesCleartextTraffic=false`; only the **debug** manifest allows plain http (dev API).
