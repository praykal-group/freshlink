# I-CCMS client (Flutter)

One codebase, three Android apps (driver, operator, control tower) and the web console.
See [docs/BUILD_GUIDE.md](../docs/BUILD_GUIDE.md) for setup, flavors, signing and checks.

```
lib/
  main_<flavor>.dart     entry points (each imports only its own apps/<flavor>/)
  bootstrap.dart         shared start-up
  core/                  config, theme tokens, network, auth, storage (SQLCipher), sync, realtime, push, router
  shared/                widgets + shared screens (splash, login, OTP, settings, sync queue, ...)
  apps/<flavor>/         flavor screens (M11–M13)
  l10n/                  ARB files (en, hi, mr)
```
