# Watching a PR

Referenced by `CLAUDE.md` (Phase 4). After a PR is opened and reviewed, **always**
subscribe to its activity and watch it until it merges or the user tells you to
stop, whenever the subscription tooling (e.g. a `subscribe_pr_activity` tool) is
available. If it isn't, skip and note it.

On subscribing, immediately check the current CI status and any unresolved review
comments and handle them before going idle. Then, for each incoming event:

- **CI failure:** diagnose; if the fix is small and you're confident, push it and
  update the PR. Re-kick until the checks are green — green CI is the terminal
  state.
- **Review comment:** if the fix is unambiguous and small, make it; if it's
  ambiguous or architecturally significant, ask the user first (AskUserQuestion); if
  no action is needed, skip silently.
- **Scope change from your push:** whenever a commit you push materially changes
  what the PR contains, update the title and/or description with `gh pr edit` so
  they still match the branch.
- **`main` advanced:** rebase the PR branch onto the latest `main`. If a clean
  rebase is blocked by conflicts, merge `main` in instead of abandoning the update.
  Resolve so both sides' intent is preserved; only on a true either/or conflict
  prefer the PR branch. Report a concrete list of the files/conflicts that needed
  manual resolution.
- Never poll with `sleep` — events wake the session.

## Monitoring `main` with `CronCreate`

PR-activity webhooks do **not** deliver the events that matter most: `main`
advancing, CI turning green, and merge-conflict transitions are never pushed. Cover
them by arming a recurring self check-in with the built-in `CronCreate` tool right
after subscribing — roughly hourly on an off-minute (e.g. cron `37 * * * *`, not
`0`/`30`).

Use the built-in `Cron*` tools (`CronCreate`/`CronDelete`) for this — **not** the
claude-code-remote MCP scheduling tools (`send_later`, `create_trigger`,
`delete_trigger`). The built-in `Cron*` tools run without a permission prompt, while
every call to an MCP scheduling tool prompts for approval — which defeats the point of
autonomous watching, interrupting the loop precisely when it is meant to act on its
own. If the harness suggests `send_later` for the self check-in, override it and use
`CronCreate` here.

The scheduled prompt should re-check the watched PR: compare the branch to
`origin/main` and rebase/merge per the `main` advanced rule if it moved, re-check CI
status and mergeability, act on anything actionable, and stop the job with `CronDelete`
once the PR is merged or closed. Keep the job silent when nothing changed — no user
message, no PR comment. `CronCreate` jobs are session-only and auto-expire after 7
days, so re-arm if the PR is still open.

If the built-in `Cron*` tools are unavailable, note the skip and fall back to
event-driven watching only — check `main` opportunistically on the wake events you do
get (incoming PR webhooks and user turns), accepting that detection is no longer on a
fixed cadence. Do **not** substitute the prompting MCP scheduling tools as the
fallback.

Stop watching the moment the user asks: unsubscribe, cancel the `CronCreate` job with
`CronDelete`, and push no further changes to that PR.
