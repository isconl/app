slate_ui is vendored from xkeel/slate ui/flutter at commit 846992c (0.2.0).
The source of truth is that repo. xkeel/slate is private, so CI here cannot fetch it as a git dependency.
Resync by copying lib/ and pubspec.yaml from there; never edit this copy. Replace with a git dependency once the repo is readable from CI.
