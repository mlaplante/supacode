# Agent presence and worktree hygiene

Date: 2026-10-12
Branch: `agent-presence-and-worktree-hygiene`
Status: draft for review

## Purpose

Supacode is used to run many Claude Code and Codex sessions in parallel, one
per Git worktree. The loop is: open a worktree, start an agent, wait, review,
merge, clean up. Today the app tells you an agent is busy or idle, but it does
not tell you *how long* it has been waiting, which worktree to look at *next*,
whether a Codex session needs you at all, or which worktrees are dead weight.

This project adds seven improvements that all serve the "many agents, one
human" workflow. They share two foundations: a timestamp on every presence
change, and a small set of new git queries.

Success looks like:

- A Codex session asking for permission shows the same "awaiting input" badge
  Claude does, and triggers the same notification.
- Hovering an agent badge shows how long it has been in its current state.
- One keystroke jumps to the worktree that has waited longest for you.
- A worktree that is behind its base shows a count and can be rebased or
  merged from its row menu.
- Worktrees with nothing in them, or untouched for a week, are collected in
  one review list for batch archive or delete.
- Settings tell you whether hooks are installed *and* whether events have
  actually arrived.

Out of scope (deferred, not rejected): token and cost in the badge, automatic
archive of stale worktrees, a diff viewer, agent auto-launch on worktree create.

## Constraints

- TCA, Swift 6, macOS 26. Follow `AGENTS.md` and `CLAUDE.md` rules verbatim:
  no NSNotification between reducers, `@Shared` for settings, `SupaLogger`,
  no `Task.sleep` in tests, `FocusedAction` for menu closures, sidebar
  per-leaf invalidation preserved.
- Never read presence state from a view body for whole-tree data. Per-leaf
  data flows through `sidebarItems` and `computeSidebarStructure` as today.
- No new dependency clients that only wrap `@Shared`.
- Every reducer logic change gets tests.
- Build must pass `make build-app` after each workstream.

## Architecture overview

```
                 ┌───────────────────────────────┐
  Claude hooks ─▶│                               │
  Codex hooks  ─▶│  OSC 3008 → AgentSignal       │
                 │  → WorktreeTerminalManager    │
                 │  → AgentPresenceFeature       │──▶ lastEventAt[agent]   (W7 health)
                 │     PresenceRecord            │
                 │       + activitySince: Date   │──▶ RowSnapshot.since    (W2 badge)
                 └───────────────┬───────────────┘
                                 │ surfacesChanged fan-out (existing)
                                 ▼
                 ┌───────────────────────────────┐
                 │ RepositoriesFeature           │
                 │   SidebarItemFeature.State    │
                 │     agentSnapshot (+since)    │──▶ Active ordering by wait (W3)
                 │     behindCount, staleReason  │──▶ row accessories (W5, W4)
                 │   computeSidebarStructure     │──▶ worktree sort mode (W6)
                 │   MenuBarSections.needsYou    │──▶ menu bar + jump (W3)
                 └───────────────┬───────────────┘
                                 │
                 ┌───────────────▼───────────────┐
                 │ GitClient / GitClientDependency│
                 │   aheadBehind(base:)           │  (W5, W4)
                 │   rebaseOnto / mergeBase ref   │  (W5)
                 └────────────────────────────────┘
```

Workstreams are numbered W1 to W7. W1 (presence timestamps) is the
foundation for W2, W3 and W6. W5's git queries are the foundation for W4.
W0 is the Codex hook change and is independent.

## W0. Codex hook parity

**Problem.** `CodexHookSettings` installs only SessionStart, UserPromptSubmit
and Stop, so Codex never reports awaiting input, compacting, or session end.
The installed binary (codex-cli 0.162.1, verified by string search) supports
PermissionRequest, PreToolUse, PostToolUse, SessionEnd, PreCompact and
SubagentStop.

**Design.** Extend the Codex hook map to mirror Claude's, using the same
composite commands:

| Codex event        | Emits                                  |
|--------------------|----------------------------------------|
| SessionStart       | session_start                          |
| UserPromptSubmit   | busy                                   |
| PreToolUse (any)   | busy                                   |
| PostToolUse (any)  | idle                                   |
| PermissionRequest  | awaiting_input, forward stdin as notify|
| PreCompact         | compacting                             |
| Stop               | idle, forward stdin as notify (as now) |
| SessionEnd         | session_end, idle                      |

`PermissionRequest` replaces Claude's `Notification` as the awaiting trigger.
Codex has no AskUserQuestion-style tool matcher, so there is no matched
PreToolUse group. If Codex's `request_user_input` surfaces as a distinct hook
event in a later release, add it as a second awaiting trigger; do not guess
now.

Update `SkillAgent` capability flags for `.codex`: add `inputNeededBadge`
and `compactionBadge`. `errorDetection` stays off (Codex Stop has no
transcript error signal we can read).

Install state already reports `.outdated` when the managed command set on
disk differs from canonical, and `SettingsFeature` auto-reinstalls outdated
targets once per session, so existing users upgrade on their next visit to
settings. Verify this with a test rather than assume it.

**Verification.** Add `CodexHookSettingsTests` asserting the event map and
that every event decodes app-side. Update `SkillAgentTests`. Manual check:
run `codex` in a worktree, trigger a permission prompt, observe the badge.

**Risk.** Codex may fire PreToolUse/PostToolUse for non-shell tools in ways
that flicker. The socket already debounces idle; reuse that. If flicker is
observed in manual testing, drop PostToolUse→idle for Codex and keep
turn-level granularity (document the decision in the PR).

## W1. Presence timestamps (foundation)

**Problem.** `PresenceRecord` holds only `activity` and `pids`. Nothing knows
when a state began.

**Design.**

- Add `activitySince: Date` to `PresenceRecord`. Stamp it in
  `applyActivity` only when the activity actually changes (the early-return
  for unchanged activity already exists), in `applySessionStart`,
  `clearAttention`, and `applyRestore`.
- Add `@Dependency(\.date)` to `AgentPresenceFeature`. Tests drive it with
  `.constant`.
- Carry the date into `AgentInstance` and `RowSnapshot` (`since` = earliest
  `activitySince` among attention-state agents, else among working agents).
- Persist `activitySince` in `TerminalLayoutSnapshot.SurfaceAgentRecord` so
  wait time survives relaunch. Make it optional in Codable for older
  snapshots; a missing value restores as `now`.
- Add `lastEventAt: [SkillAgent: Date]` to `AgentPresenceFeature.State`,
  stamped on every `hookEventReceived` regardless of whether activity
  changes. This feeds W7. It is not persisted.

**Why not a ContinuousClock instant.** The value must be persisted and shown
as wall-clock elapsed time; `Date` is the right type. Views compute elapsed
time from the date with `TimelineView`, so the reducer never ticks for
display.

**Verification.** Extend `AgentPresenceFeatureTests` harness with a date:
state change stamps, unchanged state does not re-stamp, restore uses the
snapshot date, missing snapshot date falls back to now.

## W2. Elapsed time in the badge

**Design.**

- `AgentBadgeView` / `AgentAvatarGroupView` gain an optional `since: Date`.
  Tooltip becomes "Claude awaiting input for 4m 12s" and updates via
  `TimelineView(.periodic(from:by: 1))` only while hovered or while the
  badge is in an attention state, so idle sidebars do not tick.
- The sidebar row shows a compact elapsed label (e.g. `4m`) next to the
  badge only for `awaitingInput` and `error`, using `.monospaced()` digits
  and system secondary color. Working states show no label to keep the
  row quiet.
- No reducer ticks: the label reads `agentSnapshot.since` from the leaf
  state, and `TimelineView` drives re-render locally.

**Verification.** `AgentBadgeVisualTests` for the formatter (seconds,
minutes, hours, days). Snapshot the row with and without `since`.

## W3. Needs-you queue

**Design.**

- `MenuBarSections` gains a `needsYou: [RowID]` section, computed in
  `computeMenuBarSections` from leaves whose `agentSnapshot` has an
  attention-state agent, ordered by `since` ascending (longest wait first),
  excluding archived, missing and terminating rows. Rendered at the top of
  `MenuBarNotificationsMenu` with the elapsed label from W2.
- `SidebarHighlightOrdering.orderedRowIDs` orders the Active section by:
  attention rows by `since` ascending, then the existing rule (notified
  first when `moveNotifiedWorktreeToTop`, then branch name).
- New `AppFeature` action `jumpToNextAwaiting`: picks the first row of
  `needsYou`, selects the worktree, focuses the awaiting surface (reuse the
  `jumpToLatestUnread` path: `selectWorktree` + `focusSurface`), and the
  existing `clearAttention(surfaces:)` on focus removes it from the queue.
  If the queue is empty, no-op.
- Menu item under Worktrees: "Jump to Next Awaiting Agent", shortcut
  registered in `AppShortcuts` with an override entry so it is rebindable.
  Default: `⌃⇧J` (verify it is unused; pick another if it collides).
  Command palette entry mirrors it. Use `FocusedAction` with a `token` of
  the queue's first row id so the menu rebuilds only when the head changes.

**Verification.** `MenuBarNotificationListTests` for ordering and
exclusions. `SidebarHighlightOrderingTests` for the new precedence.
`AppFeatureJumpToNextAwaitingTests` with `TestStore`, modeled on the
Jump-to-Latest-Unread tests.

## W5. Branch sync (before W4, since W4 reuses its query)

**Design.**

- `GitClient` gains:
  - `aheadBehind(worktree:, base:) -> (ahead: Int, behind: Int)` via
    `git rev-list --left-right --count <base>...HEAD`.
  - `rebaseOnto(worktree:, base:)` via `git rebase <base>`; on non-zero
    exit, run `git rebase --abort` and throw a typed `GitSyncError.conflict`.
  - `mergeBase(worktree:, base:)` via `git merge --no-edit <base>`; on
    conflict, `git merge --abort` and throw the same error.
  - Each is a new `GitOperation` case, a method, a `GitClientDependency`
    closure, and an entry in `make`.
- Base ref per worktree: the repo's `worktreeBaseRef` if set, otherwise
  `automaticWorktreeBaseRef` (origin/HEAD → origin/main → local HEAD).
- Refresh: `WorktreeInfoWatcherManager` already emits `filesChanged` and
  `branchChanged`. On `branchChanged` and on the 300 s reconcile pass,
  `RepositoriesFeature` runs `aheadBehind` and stores
  `behindCount: Int?` and `aheadCount: Int?` on `SidebarItemFeature.State`
  next to `addedLines`. Do not run it on every `filesChanged` (5 s debounce
  would be too chatty); commits change HEAD, which the kqueue already
  catches.
- Row accessory: when `behindCount > 0`, show `↓N` with `.monospaced()`
  in secondary color, tooltip "N commits behind <base>".
- Row context menu: "Rebase onto <base>" and "Merge <base> into branch".
  Enabled only when `behindCount > 0`, no agent in `isWorking` state on
  that worktree, and `fileStatus` reports a clean tree. On success, re-run
  `aheadBehind` and `lineChanges`. On `GitSyncError.conflict`, present an
  alert "Rebase stopped on conflicts; the rebase was aborted and your branch
  is unchanged." Deliberately never leave a worktree mid-rebase: an agent
  may be about to run in it.
- Setting: none new. The repo's `pullRequestMergeStrategy` is about PRs and
  is not reused here.

**Verification.** `GitClientAheadBehindTests` with the stub shell
(argument shape, parse of `"3\t5"`). `RepositoriesFeature` tests for: store
counts on `branchChanged`, menu gating when agent busy, conflict path shows
alert and does not mutate counts.

## W4. Stale worktree review

**Design.**

- Record `lastFocusedAt: Date?` on `SidebarState.Item` (persisted, next to
  `archivedAt`). Set when the worktree is selected and when any hook event
  arrives for one of its surfaces (so an agent working counts as activity).
- `StaleReason` enum on `SidebarItemFeature.State`: `.empty` (ahead == 0
  and clean tree), `.idle(days:)` (`lastFocusedAt` older than
  `staleWorktreeAfterDays`), or nil. Computed in the same reconcile pass
  that runs `aheadBehind` (W5), plus `fileStatus` for cleanliness. Main
  worktrees, pinned worktrees, archived, missing, and worktrees with an
  open PR are never stale.
- Global setting `staleWorktreeAfterDays: Int` (default 7, 0 disables the
  idle rule; the empty rule stays on). Lives in `GlobalSettings`, shown in
  the Worktrees settings section.
- Sidebar: a subtle `clock.badge` system symbol accessory on stale rows
  with a tooltip stating the reason.
- Review view: `StaleWorktreesDetailView`, structurally a sibling of
  `ArchivedWorktreesDetailView`, grouped by repository, each row showing
  branch, reason, last focused, ahead count. Multi-select with "Archive
  Selected" (goes through `requestArchiveWorktrees`, so archive scripts
  still run) and "Delete Selected" (`requestDeleteSidebarItems`).
  Reachable from the Worktrees menu ("Review Stale Worktrees…"), the
  command palette, and a new `SidebarSelection.staleWorktrees` case
  mirroring `archivedWorktrees` in `WorktreeDetailView` and `WindowTitle`.
- No automatic action. The merged-PR sweep and archive auto-delete are
  untouched.

**Verification.** Pure tests for the stale classifier (every exclusion,
both reasons, disabled idle rule). `RepositoriesFeature` test that
selecting a worktree stamps `lastFocusedAt` with the injected date.
`AppFeature` selection test mirroring `AppFeatureArchivedSelectionTests`.

## W6. Sort worktrees within a repo

**Design.**

- New `SidebarWorktreeSort` enum: `.manual` (default, today's behavior),
  `.recentActivity` (by `lastFocusedAt` desc, from W4), `.agentState`
  (error, awaiting, working, idle-with-agent, then no agent; ties by
  `since` ascending then branch name). Stored per repo section on
  `SidebarState.Section`, next to `collapsed`/`color`, so it persists
  with the sidebar and needs no `RepositorySettings` Codable change.
- Applied in `SidebarItemGroup.computeSlots` after the pinned/pending split
  so pinned rows keep their slot and only the unpinned tail is sorted.
  When nesting by branch is on, nesting still wins and the sort applies
  within each nest level.
- Drag reordering (`.onMove`) is disabled unless the mode is `.manual`,
  because `translateFilteredMove` maps against visible order. The section
  header context menu gains a "Sort Worktrees" submenu with the three
  modes; the Section sort entry it sits beside stays as is.
- The agent-state sort reads only `agentSnapshot` already present on the
  leaf, so a presence change still invalidates one leaf plus the
  structure recompute that already happens today.

**Verification.** `SidebarStructureTests` for each mode, pinned slot
stability, nesting interaction, and that `.manual` output is byte-identical
to today's.

## W7. Hook health check

**Design.**

- Settings already knows `.installed / .outdated / .notInstalled` per agent
  target from `installState`. Add a second signal: the last time an event
  arrived from that agent (`lastEventAt` from W1).
- `SettingsFeature` lives in `SupacodeSettingsFeature` and cannot see
  presence state. Expose it through a tiny `AgentHookActivityClient`
  dependency with one closure, `lastEventDates() -> [SkillAgent: Date]`,
  whose live value reads from the app's presence store. This is a client
  wrapping *app state*, not `@Shared`, so it does not violate the
  no-wrapper-clients rule.
- `AgentIntegrationRow` gains one status line under the capability grid:
  - "Hooks installed · last event 2m ago" (green dot)
  - "Hooks installed · no events received this session" (grey dot) with a
    hint "Start an agent in a Supacode terminal to confirm."
  - "Hooks outdated" / "Not installed" (orange / grey) with the existing
    install button.
- A "Send test event" button runs the agent's own hook command in a
  subprocess with `SUPACODE_SURFACE_ID` set to the focused surface's id,
  so the full OSC path is exercised. The result flips the status line
  within the 2 s liveness window or shows "No event received; check that
  <config path> contains the managed hooks."

**Verification.** `SettingsFeatureAgentIntegrationTests` for the three
status variants with an injected `lastEventDates`. The test-event path is
verified manually; document the steps in the PR.

## Data flow summary of new state

| Where                              | New field                      | Persisted |
|------------------------------------|--------------------------------|-----------|
| `PresenceRecord`                   | `activitySince: Date`          | yes       |
| `AgentPresenceFeature.State`       | `lastEventAt: [SkillAgent: Date]` | no     |
| `RowSnapshot` / `AgentInstance`    | `since: Date?`                 | no        |
| `SidebarItemFeature.State`         | `aheadCount`, `behindCount`, `staleReason` | no |
| `SidebarState.Item`                | `lastFocusedAt: Date?`         | yes       |
| `SidebarState.Section`             | `worktreeSort: SidebarWorktreeSort` | yes  |
| `GlobalSettings`                   | `staleWorktreeAfterDays: Int`  | yes       |
| `MenuBarSections`                  | `needsYou: [RowID]`            | no        |

## Error handling

- Git failures in `aheadBehind` leave counts as nil and log via `SupaLogger`;
  the accessory simply does not render.
- Rebase/merge conflicts always abort and alert; the worktree is never left
  mid-operation.
- Missing `activitySince` in old snapshots restores as `now`.
- Hook events for unknown surfaces are dropped as today.

## Execution plan outline

Order respects dependencies; parallel groups can run as concurrent
subagents in separate worktrees. Model suggestion per task is a guideline
for the implementation plan.

1. **Parallel group A** (independent):
   - W0 Codex hooks (sonnet)
   - W1 presence timestamps (sonnet)
   - W5 git client queries only, no UI (sonnet)
2. **Parallel group B** (after A):
   - W2 badge elapsed time (haiku)
   - W3 queue + jump command (sonnet)
   - W5 UI: counts refresh, row accessory, rebase/merge menu (sonnet)
   - W7 health check (sonnet; haiku for the view)
3. **Group C** (after B):
   - W4 stale review (sonnet)
   - W6 worktree sort (sonnet; haiku for the submenu view)
4. Final: `make build-app`, full test run, manual pass with one Claude and
   one Codex session.

Each workstream is one commit series on this branch, tests included.
