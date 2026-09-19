# iSconl · the client application

Offline-first Flutter client for the iSconl sovereign personal agent.
Lives on the **`app` branch** - a parallel, orphan branch of
`Sconl/isconl-agent`. The web dashboard (dev/staging/main) is untouched.

One codebase, several platforms: **Android**, **Windows**, **Linux**.
macOS is deferred and iOS is dropped until there is an Apple account. The
branch was called `apk` until 3 August 2026; the release tag prefix is
still `apk-v` on purpose, because every already-installed phone looks for
that prefix to find its own update.

## What it is

- A native mirror of the dashboard: Hub · Tasks · Ask · Alerts, plus
  Planning, Calendar, Inbox, Kanban, GitHub, Finance, Journal, Learning,
  Circle, Projects, Spaces, Decisions & Risks, Audit Chain, Outbox, Settings.
- **Offline-first**: every domain is cached in SQLite on the device. Reads
  work with no connection. Writes queue in an outbox and deliver on
  reconnect; the server then pushes the vault to OneDrive (the app also
  triggers `/api/vault/sync` after each drain so files land promptly).
- **Same security model**: TOTP or static-token login (404-as-denial
  semantics preserved), token in encrypted storage, optional biometric
  lock, no anonymous surface. GATE-sensitive actions (deletes, Jira writes)
  are online-only and always confirmed - never queued, never optimistic.
- **Platform-aware, not platform-forked**: the client asks the agent what
  the host can do (`/api/capabilities`) and renders accordingly. Capability
  belongs to the agent host, not the client device - which is why system
  audio capture is a server feature and the UI stays identical everywhere.
- **Native capabilities**: share any text into the inbox from the Android
  share sheet, photograph receipts into `/api/finance/receipt`, native
  dial/WhatsApp/mail actions from Circle, haptics, system notifications
  for high-severity alerts after sync.

## Design

Ported 1:1 from `dashboard/style.css` - the GitHub-dark green system:
`#0d1117` ground, `#161b22` panels with 1px `#30363d` borders, green
`#3fb950` as the only brand accent, Inter for UI, JetBrains Mono for
IDs/hashes/timestamps. Empty states teach. No em-dashes anywhere.

Reading surfaces are the exception to the panel system: lesson and article
bodies render borderless on the page ground, full measure, because a
reading pane is not a card. See `lib/ui/widgets/reader.dart`.

## Build & release flow (automated)

- CI (`.github/workflows/app-build.yml`) runs on every push to `app` and on
  manual dispatch: bumps the patch version once, regenerates icons,
  analyzes, tests, then builds Android, Windows and Linux in parallel and
  attaches all three artefacts to GitHub Release `apk-vX.Y.Z`:
  - `YYYYMMDD_isconl_vX.Y.Z.apk`
  - `YYYYMMDD_isconl_vX.Y.Z_windows_x64.zip`
  - `YYYYMMDD_isconl_vX.Y.Z_linux_x64.tar.gz`
- **Update on cue**: in the app, Settings -> Check for update pulls the
  latest `apk-v*` release (needs a fine-grained PAT with contents:read,
  stored in Settings) and hands the APK to the Android installer.
- **Main-branch trigger (staged)**: when ARCHITECT cues the main push, copy
  `docs/main-trigger/trigger-app-build.yml` into `.github/workflows/` on
  main - from then on every main push also cuts a client build.
- One-time setup: `powershell -File tool/setup_ci_secrets.ps1` uploads the
  signing keystore to GitHub secrets (same key as local builds, so
  in-place upgrades keep working). Keystore lives at
  `C:\Users\PC\dev\keys\` - never in git.

## Custom branding

- Launcher icon: drop a square PNG at `branding/icon.png` and the next
  build adopts it (`tool/icon_gen.js` falls back to the favicon design).
- In-app logo: Settings -> Appearance -> Choose logo (runtime, no rebuild).

## Local development

```
flutter pub get
flutter analyze && flutter test
flutter build apk --release      # signing via android/key.properties
flutter run -d chrome            # fastest UI iteration loop
node tool/icon_gen.js            # regenerate launcher icons
```

Toolchain on this workstation: Flutter at `C:\Users\PC\dev\flutter`,
JDK 17 at `C:\Users\PC\dev\jdk17`, Android SDK at
`C:\Users\PC\dev\android-sdk`.

**Windows desktop cannot be built on this workstation.** `flutter doctor`
reports Visual Studio missing, and the "Desktop development with C++"
workload is a ~7GB install. Windows and Linux binaries are produced by CI
instead; iterate on desktop layout with `flutter run -d chrome`, which
uses the same adaptive breakpoints.
