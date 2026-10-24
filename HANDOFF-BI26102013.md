# HANDOFF BI26102013 (web speed)
Branch row/BI26102013 (worktree _wt-app-BI26102013), rebased on dev 0.3.161.
Done: flutter_secure_storage 10.3.4 so `flutter build web --wasm` compiles (205 s); DOM splash in web/index.html (the LCP element, removed on flutter-first-frame).
Measured (Lighthouse 12 mobile, simulated 4G, gzip server, wasm build, 5.7 MB transfer): score 62 (was no valid score), FCP 0.7 s, LCP 1.2 s, TBT 6,550 ms, TTI 22.5 s, speed index 8.8 s.
Open: TBT is the drag; need score >= 80. Find the startup work on the main thread (main.dart init, sqlite3 wasm, store loads) and defer it past first frame.
Not landed: Android's stored values migrate out of EncryptedSharedPreferences on first read after secure storage 10 (verify login survives an upgrade before landing).
Land: fetch, rebase on dev, `node tool/bump_version.js dev`, one push to dev when no Build app run is active, close on green run + apk release.
