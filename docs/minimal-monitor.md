---
summary: "Minimal quota monitor setup, Sonoma crash hardening, and agent-routing integration."
read_when:
  - Setting up CodexBar as a low-noise limits monitor
  - Feeding quota state into agent-provider decisions
  - Investigating ProviderRefreshRequestContext crashes on macOS 14
---

# Minimal limits monitor

This fork keeps CodexBar's existing visual theme and provider collectors while making the opened **Overview** tab a
true quick glance: each selected source shows its name and up to three primary quota meters with their reset times.
Cost charts, token histories, projects, conversations, storage, and verbose diagnostics stay out of
Overview and remain available in the individual provider tabs. Clicking an Overview row opens that provider's detail
tab.

The fork also fixes the observed Sonoma refresh crash and exposes routing advice through the existing CLI contract. It
does not add a second policy engine or duplicate provider-fetch logic.

App startup acquires a process-scoped advisory lock before SwiftUI initializes. LaunchServices normally reuses the
installed app, but a direct executable invocation can bypass that behavior; later instances now exit before creating
another status item. The OS releases the lock on normal exit or a crash, and startup also checks for an active older
build that predates the lock. A lock-file setup failure is logged and does not prevent the app from launching.
Developers can explicitly bypass the guard with `CODEXBAR_ALLOW_MULTIPLE_INSTANCES=1`.

The fork build verifies lock contention, lock release for relaunch, legacy-instance detection, and fail-open behavior
when the lock file cannot be created before packaging the app.

## Compact Overview

The Overview tab intentionally reuses CodexBar's standard typography, provider tint, progress bar, spacing primitives,
and native menu selection. It changes content hierarchy rather than introducing a new theme:

- one compact row per selected provider;
- up to three primary quota windows shown as meter bars;
- percentage and window label on the left, reset countdown on the right;
- a one-line unavailable or refreshing state when no quota meter can be shown, even if the provider has cost-only
  detail in its full tab;
- no embedded dashboard or hover submenu in the quick-glance view.

Use the existing provider tabs for account identity, diagnostics, spend, token history, projects, conversations,
storage, and other secondary data.

## Low-noise menu bar setup

1. In **Providers**, enable only the subscriptions that should be monitored.
2. In **Display**, turn on **Merge Icons** so the providers share one status item.
3. Keep the menu-bar icon style on **Icon + Percent**; custom token layouts are ignored by the other renderer styles.
4. Open **Display → Menu Bar → Layout** and set the scope to **All providers**.
5. Start from **Percent + reset**. Add **Provider name**, drag it to the front, and remove **Icon** if the provider name
   is sufficient. The resulting tokens are:

   ```text
   Provider name · Auto % · Separator dot · Resets in
   ```

6. Select **Small** and **Tight** for the least menu-bar space. Leave cost and pace tokens out of the layout.

`Auto %` selects the provider's most useful active quota window. Turn off **Show usage as used** when the percentage
should mean remaining allowance. The layout editor changes the always-visible status item; the opened Overview tab
shows all available quota windows in compact rows, while provider tabs retain the full detail.

## Machine-readable quota gate

The CLI already provides a stable agent-facing decision surface:

```bash
codexbar guard --provider claude --window weekly --min-remaining 20 --json --pretty
```

Exit codes are `0` when the provider is safe, `1` below the threshold, `64` for invalid invocation, and `69` when the
quota cannot be checked. Do not silently treat `69` as healthy; stale credentials or an outage should produce an
explicit unknown recommendation.

A Claude-first, Kimi-fallback policy can remain outside the app:

```bash
claude_state="$(codexbar guard --provider claude --window weekly --min-remaining 20 --json)"
claude_exit=$?

case "$claude_exit" in
  0) jq -n --arg recommended claude --arg reason claude_has_headroom \
       --argjson claude "$claude_state" '{recommended:$recommended,reason:$reason,claude:$claude}' ;;
  1) kimi_state="$(codexbar guard --provider kimi --window weekly --min-remaining 10 --json)"
     kimi_exit=$?
     if [ "$kimi_exit" -eq 0 ]; then
       jq -n --arg recommended kimi --arg reason claude_near_limit \
         --argjson claude "$claude_state" --argjson kimi "$kimi_state" \
         '{recommended:$recommended,reason:$reason,claude:$claude,kimi:$kimi}'
     else
       jq -n --arg recommended none --arg reason no_verified_headroom \
         --argjson claude "$claude_state" --argjson kimi "$kimi_state" \
         '{recommended:$recommended,reason:$reason,claude:$claude,kimi:$kimi}'
     fi ;;
  *) jq -n --arg recommended unknown --arg reason claude_quota_unavailable \
       --argjson claude "$claude_state" '{recommended:$recommended,reason:$reason,claude:$claude}' ;;
esac
```

An agent launcher can run this once before provider selection and record the returned JSON in its decision log. For
long-running monitoring, `codexbar hooks watch` can publish the same state only when a configured threshold is crossed.

## Sonoma crash hardening

Two CodexBar 0.48.1 crash reports from macOS 14.4.1 arm64 symbolicate to
`ClaudeUsageFetcher.OAuthExecutor.loadAfterDelegatedRefresh`, specifically the nested
`ProviderRefreshRequestContext.withNewRequest` around the post-delegation credential reload. Both terminate in
`swift_task_dealloc`.

The initial provider refresh still establishes one request scope. The post-delegation retry no longer nests a second
TaskLocal binding inside the provider fetch child task; it passes a fresh prompt-attempt UUID directly into the
credential repository instead. The ID is process-local, is never persisted or sent to providers, and cannot match the
pre-delegation prompt result. Because this retry never permits a Keychain prompt, the fresh ID specifically prevents a
stale failure from the pre-delegation attempt from being replayed. Removing the nested scope avoids the allocator-order
abort on the macOS 14 Swift concurrency backdeployment runtime while preserving the fresh retry epoch.

The repository initializer defaults this explicit scope to `nil`, so every existing credential-load caller continues
to inherit the outer refresh request ID. Only the post-delegation retry supplies a fresh ID.

Acceptance requires:

- focused request-context and Claude delegated-refresh tests;
- the full lint/test gate on a Swift 6.2+ toolchain;
- exactly one production `ProviderRefreshRequestContext.withNewRequest` call site;
- an ad-hoc signed release build launched repeatedly on macOS 14.4.1 with Claude enabled and an expired/delegated OAuth
  refresh path;
- no fresh `CodexBar-*.ips` report and no `swift_task_dealloc` abort after repeated refreshes.

## Durable Claude Auto fallback

Claude Code can remain logged in after the OAuth credential copy visible to CodexBar expires. Previously, Auto mode
could not recover in the background: it classified all Claude child processes as potentially interactive, skipped the
healthy CLI unless broad background Keychain prompting was enabled, and eventually published an unavailable state.
The process-local foreground-availability marker also disappeared on every app restart.

Background Auto now uses a separate usage-only execution path. It launches `claude /usage` directly with no PTY, no
`claude auth status` preflight, null stdin, sanitized passive-probe environment, and a 12-second process timeout. It
does not run browser or optional web enrichment on this path. Auth-status, version detection, explicit OAuth recovery,
and foreground interactive CLI flows keep their existing prompt policy.

The retry guard remains account-scoped. A successful direct read establishes the existing in-process marker; a failed
read revokes subsequent scheduled attempts for that binary/account pair until the app restarts or a foreground fetch
succeeds. Switching Claude accounts creates a new scope and permits one fresh bounded attempt, while removing account
identity leaves background CLI unavailable.

Regression coverage verifies cold-start recovery with Keychain enabled and **Only on user action**, direct `/usage`
execution without auth preflight or PTY, timer retry suppression, rate-limit cooldown preservation, and account-scope
isolation. Cancellation, a cooldown that prevents process launch, and a live rate-limit response do not revoke
background availability. SwiftFormat and SwiftLint run locally; compile/test verification uses the repository's
Swift 6.2+ workflows because the
maintenance Mac currently has Xcode 15.4. The fork's macOS build workflow runs the dedicated Claude background Auto
durability suite before packaging the installable app.

The crash fix is suitable for upstream contribution. The compact Overview is a fork-specific product choice; the
provider-routing policy should stay outside the app unless repeated use shows that a dedicated policy command is
warranted.
