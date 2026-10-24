# HANDOFF BI26102013 (web speed)
Branch row/BI26102013 (worktree _wt-app-BI26102013), rebased on dev 0.3.161.
Done: flutter_secure_storage 10.3.4 so `flutter build web --wasm` compiles (205 s); DOM splash in web/index.html (the LCP element, removed on flutter-first-frame).
Measured (Lighthouse 12 mobile, simulated 4G, gzip server, wasm build, 5.7 MB transfer): score 62 (was no valid score), FCP 0.7 s, LCP 1.2 s, TBT 6,550 ms, TTI 22.5 s, speed index 8.8 s.
Findings: with COOP same-origin + COEP require-corp (multithreaded skwasm) the same build scores 63, LCP 0.8 s, TBT 4.6 s, speed index 7.3 s. Long tasks are skwasm.js rendering (5.2 s scripting) and main.dart.mjs start-up (1.2 s, 0.9 s, 0.8 s tasks); headless Chrome renders in software, so lab TBT overstates a real phone. Whoever hosts the web build (BI26102012) should send those two headers.
Open: TBT is the drag; need score >= 80. Find the startup work on the main thread (main.dart init, sqlite3 wasm, store loads) and defer it past first frame.
Not landed: Android's stored values migrate out of EncryptedSharedPreferences on first read after secure storage 10 (verify login survives an upgrade before landing).
Land: fetch, rebase on dev, `node tool/bump_version.js dev`, one push to dev when no Build app run is active, close on green run + apk release.
