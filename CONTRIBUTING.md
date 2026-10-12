# Contributing to the app

## Release notes are written as commit trailers

The app shows a "What's new" sheet once after every update, patches included. The notes are not written
separately: they come from the commits themselves.

A commit that a user would notice carries one or more trailer lines at the end of its message:

```
New: See what changed after every update.
Improved: Lists open faster.
Fixed: The sheet no longer closes by itself.
```

- `New:` is something the app could not do before.
- `Improved:` is something that works better.
- `Fixed:` is something that was wrong and is not any more.

Rules for each line:

- One plain sentence a user understands, at most 120 characters. No row ids, no file names, no personal names.
- It follows the writing standard (Slate doc `WRITING-VOICE.md`): no em dashes, no stock phrases. The build runs the
  vendored voice linter over every note line and stops if one fails.
- Product names are lower case except where the app prints them (section 37).

A commit with no trailer is internal (a refactor, a test, a build change) and is never shown. Do not add a
trailer to those.

## How it reaches the phone

At build time `tool/whats_new.dart` reads the trailers of every commit between the previous `apk-v*` release tag and the
commit being built, groups them as New, Improved and Fixed, drops exact repeats and keeps commit order. It writes
`assets/whats_new.json` (this release plus the last ten releases' notes, bundled in the APK) and `build/whats_new.md`
(the release body; "Maintenance release." when there is nothing to say). The app reads the bundled file, so the sheet
works offline, and a phone that skipped versions sees the notes of every release it missed under "Since <version>".

Run it by hand to see what the next release will say:

```
dart tool/whats_new.dart --version 0.3.99 --out build/whats_new.json --md build/whats_new.md
```

The committed `assets/whats_new.json` is a placeholder with no notes. CI overwrites it in the workspace for each build
and never commits it.

## Versions

Every push to `dev` bumps the patch version in `pubspec.yaml` (`node tool/bump_version.js dev`), and the build refuses a
push that did not. Staging moves the minor version and main the major one.
