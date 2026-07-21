# Watching a PR

Referenced by `CLAUDE.md` (Phase 4). After a PR is opened and reviewed, **always**
subscribe to its activity and watch it until it merges or the user tells you to
stop, whenever the subscription tooling (e.g. a `subscribe_pr_activity` tool) is
available. If it isn't, skip and note it.

Subscribing is a **one-time** action taken right after the PR is created. The
`subscribe_pr_activity` call triggers a single permission prompt that cannot be
suppressed — like the other claude-code-remote tools it is gated independently of
the `settings.json` allowlist, so an exact-name allow entry does not silence it — but
accept it: it is a one-time cost, and once subscribed the PR events arrive as messages
with no further prompts. Do not skip subscribing to dodge that prompt. This is the one
claude-code-remote prompt worth taking, precisely because it is not recurring — unlike
the scheduling tools below, which would prompt on every call for no durable benefit.

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

## Covering what webhooks don't deliver

PR-activity webhooks do **not** deliver the events that often matter most: `main`
advancing, CI turning green, and merge-conflict transitions are never pushed. It is
tempting to cover them by arming a recurring autonomous self check-in — but under
current platform constraints no scheduling primitive is both prompt-free and durable,
so do **not** arm one:

- The built-in `Cron*` tools (`CronCreate`/`CronDelete`) run without a permission
  prompt, but their jobs are session-only and in-memory — the `durable` option is a
  no-op, and every job vanishes when the session ends, which is usually before the
  follow-up check is due.
- The claude-code-remote scheduling tools (`send_later`, `create_trigger`,
  `delete_trigger`) create durable Routines that survive session end, but they prompt
  for approval on **every** call even though `settings.json` allowlists them by exact
  name — the durable, account-scoped side effect is gated independently of the
  in-session permission allowlist, so no allowlist entry can suppress the prompt.

Because neither is both prompt-free and persistent, cover the un-delivered
transitions **opportunistically** rather than on a fixed cadence: whenever the session
is already awake for any reason — an incoming PR webhook or a normal user turn —
re-check the watched PR. Compare the branch to `origin/main` and rebase/merge per the
`main` advanced rule if it moved, re-check CI status and mergeability, and act on
anything actionable. This is best-effort: if the session has ended, monitoring pauses
until it is resumed, and that is an accepted limitation — do not try to fake durability
by reaching for the prompting scheduling tools.

Stop watching the moment the user asks: unsubscribe and push no further changes to
that PR.
