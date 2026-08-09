# BUILDLOG - apk branch

Continuity organ for the native client, mirroring the root BUILDLOG
convention. Newest entries on top. Status words: DONE / PARTIAL / BLOCKED.

---

## 2026-08-08 · Teams on the phone, and paste-to-ledger

Carried the two in-flight features through to the client, on ARCHITECT's cue to
"carry through all implementations" and to "provision, in the mobile app, the
option to paste messages that would be distilled into financial records".

**DONE - Teams view (`lib/ui/views/teams.dart`), a Channels entry.** Reads the
model the agent computes (`/api/teams`, lib/teams.js): each team's health as
green/amber/red people, each person's ready-work DEPTH as a number, span-over
flagged where a leader carries more than five directs, past-due surfaced. It is
read-focused by design - the doctrine keeps team MANAGEMENT on the console; the
phone is where he SEES, offline-tolerant, whether anyone is about to run dry.
Pull to refresh; offline and error states are the shared `ErrorRetry`.

**DONE - paste a message, get a ledger row.** A paste FAB on Finance opens a
sheet prefilled from the clipboard; the text posts to `/api/finance/messages/
commit`, which RE-PARSES it server-side with the one moneytalk parser (the
ledger never trusts the client's numbers), writes an idempotent transaction
keyed on the M-Pesa code, breaks out the transaction fee, and pushes
finance/transactions.tsv online - so the record lands on Render and syncs back
to every device. Offline, the raw text queues in the outbox and distils on
reconnect, so it still ends up online. `Mutations.distillMessage` carries it.

`flutter analyze lib` clean; the whole feature set is additive UI over routes
that already shipped on dev. Version bump + build + `apk-v*` release are the
CI's job on push (bump commits carry [skip ci]).

---

## 2026-08-01 · Session 2 - catching up with three days of agent work

Built unattended, on ARCHITECT's cue: "build the complete updated apk
autonomously... the new apk has to have all improvements made to the
agent", with a dedicated place in Settings to download it.

**DONE - the agent is now the app store.** Three server routes on the
agent side (`server.js`): `GET /api/apk/latest` reports the current
build, `POST /api/apk/ticket` mints a 15-minute one-time download
ticket, `GET /api/apk/download` streams the actual signed binary.

Two decisions worth keeping:
- The binary is **proxied, not linked**. Releases live on a private
  repo, whose asset URLs 404 without a token. Linking would mean a
  GitHub PAT on the phone - which is exactly what the old in-app updater
  did and the weakest thing about it. The server holds `GITHUB_TOKEN`
  already, so it fetches and streams; the phone uses the session it has.
  Verified against the real private asset: 302 to
  `release-assets.githubusercontent.com`, Authorization deliberately
  dropped on that hop (the signed URL rejects it), `PK\x03\x04` on the
  wire, content-length exact.
- The **ticket** exists because a browser download cannot set an
  Authorization header. Tapping a link has to work: on Android that
  means the system download manager, a progress notification, and
  install straight from the notification. Header auth would force an
  in-page blob and lose all three. `/api/apk/download` therefore sits
  above the auth gate but is not ungated - valid session OR live ticket,
  and a miss 404s like everywhere else.

`apkLocalFile()` falls back to a build on the host's disk, so "CI could
not run" never means "no APK".

**DONE - Settings card on the web.** Top of Settings: version, size,
date, release notes, Download, Refresh, plus the absolute URL so the
desktop can hand it to the phone. Rendered async - `renderSettings()` is
synchronous and a network call there would stall the page.

**DONE - the client caught up.** 53 agent commits landed between v0.0.0
and now; the app knew 42 endpoints of ~165. Added:
- **Ideas** (Spark) - capture is the point of having it on a phone;
  stage/type/domain/tags, offline-optimistic like the journal.
- **Rhythm** - today's habits plus the 365-day heatmap. The four derived
  habits (commits, lessons, journal, tasks) render as evidence, not
  checkboxes: a tick the next sync overwrites is a lie about control.
- **Files** - the OneDrive mirror, per-folder cached so a visited folder
  opens offline. Content is never cached: a stale document shown as
  current is worse than an honest "offline".
- **Buffer** - read-only desk. Publishing outward is exactly the class
  of action the constitution keeps behind a deliberate, online,
  confirmed gate, not a thumb on a phone.
- **Articles** - what is written and how far along.
- **Decisions** rewritten onto `/api/decisions` for the STALE and AGING
  flags the server computes; playbooks still ride from `/api/refs`.
- **Learning** margin notes (`/api/learning/notes`) - the tutor and the
  course-revision pass both read them, and most reading happens here.
- **Finance wishlist** with necessity/satisfaction scoring, captured in
  the shop rather than after.
- **Chat threads** - server-side conversation switching, online-only
  because the model's context window follows whichever thread is open.

**DONE - PIN sign-in**, feature-detected from `/api/auth/methods`, hidden
behind three taps on the wordmark exactly as on the web. Silent no-op
when the server offers no PIN: revealing a box that cannot work is worse
than not having the gesture.

**DONE - updates come from the agent.** `UpdateService` no longer talks
to GitHub. The stored `ghPat` is now **deleted on load** - a live
credential should not sit on the phone after the upgrade that stopped
using it. Downloads assemble under `.part` and only rename on the last
byte, so a truncated APK can never reach the installer.

**Quality gates.** `flutter analyze`: No issues found. `flutter test`:
11/11. Release build signed with the same key as v0.0.0 (SHA-256
`9fca8bf4…`) - verified with apksigner, which is what lets it install
over the existing app and keep its data.

**LESSON (cost real time).** Two verification runs passed against the
wrong directory: the shell's cwd had drifted to the agent repo, where
`flutter analyze` finds no Dart and cheerfully reports "No issues", and
`dart analyze lib` analysed the agent's JavaScript `lib/`. A green check
from the wrong working directory is worse than no check. Every command
in this session's build steps now carries an explicit `cd`.

**NOT DONE, deliberately.** Buffer composing, OneDrive upload/mkdir/move,
Jira push/compose, M365 mail, Articles co-writer, task deliverables and
coverage. Each is either a write to the outside world that belongs on
the desk, or a large surface with a contract worth reading properly
first. Say the word and they ship in a patch.

---

## 2026-07-29 · Session 1 - the whole client, from zero

**DONE - toolchain.** Workstation had no Flutter/Dart/Java/Android SDK.
Installed: Flutter 3.44.8 stable (`C:\Users\PC\dev\flutter`), Temurin JDK
17.0.20 (`C:\Users\PC\dev\jdk17`), Android SDK platforms 35+36 +
build-tools 35/36 + platform-tools (`C:\Users\PC\dev\android-sdk`),
licenses accepted. `flutter doctor` green for Android.

**DONE - branch topology.** Orphan branch `apk` in a separate worktree at
`iSconl/_worktrees/isconl-agent-apk` (underscore folder = trifractal-exempt).
dev/staging/main untouched; ARCHITECT's dirty dev tree untouched.

**DONE - the app.** ~7k lines of Dart, zero third-party UI kits.
Architecture: `ApiClient` (Bearer auth, 404-as-denial heuristic, SSE
parser, 75s cold-start budget for Render wake) -> `Store` of `Snapshot`s
(SQLite-cached endpoint mirrors, hydrate-then-refresh) -> `OutboxService`
(FIFO queue of offline writes) -> `SyncEngine` (connectivity watcher, 90s
poll parity with the dashboard, drain -> `/api/vault/sync` nudge -> pull
all domains) -> `Mutations` (single policy point: online-direct /
offline-queue+optimistic / GATE-actions-online-only).

Views: Command, Tasks (+detail), Ask (SSE chat sheet), Alerts, Calendar
(+key dates), Inbox, Kanban, GitHub, Finance (+receipt camera), Journal,
Learning (+lesson reader), Circle (+DIA profiles, native contact actions),
Projects, Planning, Spaces, Decisions & Risks, Audit Chain (chain-of-dots
with linkage verification), Outbox, Settings, Login (TOTP countdown +
static token), biometric lock screen.

Design tokens ported 1:1 from `dashboard/style.css` into `lib/theme.dart`.
Fonts bundled (Inter 4.1, JetBrains Mono 2.304) for offline. Launcher icon
rasterized from the favicon design by `tool/icon_gen.js` (pure Node PNG
encoder; adopts `branding/icon.png` when present, incl. adaptive +
monochrome layers).

**DONE - native capabilities.** Share-sheet -> inbox capture (cold start +
warm via MethodChannel `isconl/platform`), camera/gallery receipts ->
`/api/finance/receipt`, tel/wa.me/mailto actions from Circle, biometric
lock (local_auth, FlutterFragmentActivity), system notifications for
fresh high-severity alerts after sync, haptics on primary actions.

**DONE - quality gates.** `flutter analyze`: No issues found.
`flutter test`: 11/11 green (TSV sentinel parsing, money/date formatting,
version compare, markdown renderer widget tests).

**DONE - automation.** `.github/workflows/apk-build.yml` on this branch:
push/dispatch -> bump patch (`tool/bump_version.js`) -> regen icons ->
analyze -> test -> signed release build -> commit bump `[skip ci]` ->
GitHub Release `apk-vX.Y.Z` with `YYYYMMDD_isconl_vX.Y.Z.apk`. In-app
updater (Settings) reads those releases with a fine-grained PAT and hands
the APK to the system installer (REQUEST_INSTALL_PACKAGES + FileProvider).

**PARTIAL - CI signing secrets.** The permission classifier in this
session declined uploading the keystore to GitHub secrets. One-time
manual step: `powershell -File tool/setup_ci_secrets.ps1` (keystore at
`C:\Users\PC\dev\keys\isconl-apk.keystore`, RSA-2048, 30y validity,
alias `isconl`). Until then the workflow fails loudly at the keystore
step - by design, releases must be signed with the same key.

**STAGED - main trigger.** `docs/main-trigger/trigger-apk-build.yml` is
ready to copy onto main when ARCHITECT cues the main push - uses
`gh workflow run` (workflow_dispatch is exempt from the GITHUB_TOKEN
no-retrigger rule, so no PAT needed).

**DECISION-NEEDED (non-blocking).**
1. Buffer/Social composer and the OneDrive file manager were left out of
   v0 - lower daily value on the phone vs. the risk budget. Say the word
   and they ship in a patch release.
2. "Native capabilities into the main agent": candidate server additions
   (device pings, push channel via Telegram relay, receipt OCR feedback
   loop) are listed in IDEAS-APK below rather than pushed to dev tonight -
   dev auto-deploys to Render and the tree carries uncommitted dashboard
   work.

## IDEAS-APK
- Server: `POST /api/device/state` (battery, connectivity, last-sync) so
  the agent can reason about the phone.
- Server: WhatsApp-style push via Telegram bot when RANK > threshold.
- App: workmanager background sync (15-min WorkManager job) once the
  foreground loop has proven itself for a week.
- App: voice capture -> inbox via speech-to-text intent.

## LESSONS
- `flutter build` mid-edit compiles broken intermediate states - always
  gate builds on `flutter analyze` first (CI does).
- PowerShell `"y" | sdkmanager.bat` does not reach stdin; pre-writing
  `licenses/*` hash files is the deterministic path.
- The theme class `T` collided with a generic `<T>` - generics in this
  codebase use `<R>`.

**ADDENDUM (29 Jul, night):** v0.0.0 built locally, signed (CN=ARCHITECT,
SHA-256 9fca8bf4…), released as `apk-v0.0.0` with
`20260729_isconl_v0.0.0.apk` attached. Two build snags, both fixed and
encoded: flutter_local_notifications requires core-library desugaring
(added desugar_jdk_libs 2.1.5); the keystore password file carried a
PowerShell UTF-8 BOM into key.properties (stripped - keystore itself was
always clean). CI note: the push-triggered run start-failed like every
other run on the repo today - the known private-repo Actions minutes
exhaustion, not a workflow defect; the pipeline arms itself when the
billing month resets, after `tool/setup_ci_secrets.ps1` is run.

## v0.1.2 - 4 August 2026, built and delivered

Ten commits since `apk-v0.1.0`. Built locally on the workstation toolchain
(Flutter 3.44.8, Temurin 17, Android SDK 36), released as `apk-v0.1.2` with
`20260804_isconl_v0.1.2.apk` attached - 59,137,803 bytes, 56.4 MB as Flutter
reports it.

**Gate order, and why each step was run**

1. `flutter analyze` from the worktree - `No issues found`, 222.8s. From the agent
   repo it would have said the same thing in two seconds and meant nothing, which
   is the trap this project already recorded once.
2. `flutter build apk --release` - 662.6s. The Kotlin Gradle Plugin warning from
   `flutter_tts` and `package_info_plus` is upstream and non-fatal; MaterialIcons
   tree-shook 1,645,184 to 17,516 bytes.
3. `apksigner verify --print-certs` - `CN=ARCHITECT, OU=iSconl, O=iSconl, L=Nairobi,
   C=KE`, SHA-256 `9fca8bf442de7ec33f19ef29f83a123fb71b072e871c03cf735b03c6d2cedf2d`.
   Byte-identical to the fingerprint on v0.1.0, so this upgrades the installed app
   in place rather than asking to be uninstalled first.
4. `gh release create apk-v0.1.2 --target app` with the notes and the binary.

**Delivery proven, not assumed.** A release existing is not the same as the phone
being able to get it. Booted the agent and walked the exact path the download card
walks: `/api/apk/latest` reported `0.1.2` / `apk-v0.1.2` from the private repo,
`/api/apk/ticket` issued a 15-minute URL, and `/api/apk/download` streamed
59,137,803 bytes with `Content-Type: application/vnd.android.package-archive`. The
SHA-256 of the delivered bytes matches the signed file exactly
(`8657cef0aa6d55aff70a3b0eee385e6f5ce50900d90b5e7c38c9083cca17e4f4`).

**One correction to the record.** The ticket was described as "one-time". It is
not - the second use returns 200, and that is deliberate: Android's download
manager retries and range-requests, so burning the ticket on the first byte would
break exactly the weak-signal download it exists to serve. It is short-lived (15
minutes), not single-use, and the comment in `server.js` now says so.

**Server side, shipped alongside on `dev`.** The wishlist route was rebuilt around
TSV columns for the console and would have blanked the wishlist on this client -
which posts `name`/`cost`/`necessity`/`satisfaction` and reads the same. It now
speaks both vocabularies, and `finance/wishlist.tsv` carries NECESSITY and
SATISFACTION as columns so the scores this app has always taken are kept. Caught
while preparing this release, before it reached the handset.

**Not in this build.** Today's agent work is web-console only so far: the rebuilt
finance space (Plan, Ledger, Wants, Prices, Income), the price crawl and
comparison, the message scan that turns M-Pesa alerts into ledger rows, the four
day blocks, and the 26,378-row day-in-history corpus. This client still shows the
finance summary, the wishlist and receipt capture. Blocks and prices on the phone
are the next client increment.
