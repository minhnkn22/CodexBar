---
summary: "Minimal quota monitor setup, Sonoma crash hardening, and agent-routing integration."
read_when:
  - Setting up CodexBar as a low-noise limits monitor
  - Feeding quota state into agent-provider decisions
  - Investigating ProviderRefreshRequestContext crashes on macOS 14
---

# Minimal limits monitor

This fork keeps the first version deliberately small: use CodexBar's existing provider collectors and display editor,
fix the observed Sonoma refresh crash, and expose routing advice through the existing CLI contract. It does not add a
second policy engine or duplicate provider-fetch logic.

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
should mean remaining allowance. The layout editor changes the always-visible status item; the opened provider card
still shows all available quota windows so detail is available on demand.

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

The crash fix is suitable for upstream contribution. The minimal layout and provider-routing policy should stay as
configuration/documentation unless repeated use shows that a dedicated UI preset or CLI policy command is warranted.
