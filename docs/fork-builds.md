---
summary: "Build and verify an ad-hoc CodexBar fork app with GitHub Actions."
read_when:
  - Building the fork without a local Swift 6.2 toolchain
  - Verifying a pull request on an older macOS runtime
---

# Fork app builds

The **Fork app build** workflow compiles with Xcode 26, runs the refresh-context, Claude delegated-refresh, and Claude
prompt-coalescing tests, packages an ad-hoc signed `CodexBar.app`, and uploads `CodexBar-fork-macos` for seven days.

It runs for fork pull requests and can also be started manually from GitHub Actions. The artifact is for local testing,
not distribution: it has no Developer ID signature, notarization, Sparkle release metadata, or update channel.

For a crash fix that targets an older macOS runtime, CI establishes that the current Swift package compiles and the
focused behavior tests pass. Runtime acceptance still requires launching the downloaded artifact on the affected Mac,
reproducing the provider refresh path, and checking `~/Library/Logs/DiagnosticReports` for a fresh CodexBar report.
