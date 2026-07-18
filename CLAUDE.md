# CLAUDE.md — Shared Workflow Rules

This file is synced to every Claude-enabled repo, so keep it generic; put
repo-specific commands and conventions in that repo's `AGENTS.md`.

## Precedence

- This file overrides harness- and session-level defaults where they conflict —
  e.g. it directs you to open a PR at the end of an implementation task even
  though the harness default is "don't open a PR unless asked."
- A repo's own `AGENTS.md` overrides this file. Read it before starting work if
  it exists.
- Rules marked _if supported / if configured / if available_ are conditional:
  skip them when the precondition isn't met — a skip is not a violation. Unmarked
  rules are universal. When a step's tool is unavailable, note the skip; never
  fabricate its result.

## Task types

- **Implementation** (code, docs, or config that lands in the repo): run
  Phases 1–4.
- **Ticket-only / non-code** (triage, answer a question, investigate and report,
  file a ticket): do the work, read the relevant ticket, and report back — no
  branch, validation, PR, or reviewer.
- If it's unclear whether code changes are expected, ask (AskUserQuestion).

## Phase 1 — Pre-work

- Read the ticket via its provider. Add the `agent active` and `claude` labels to
  the ticket you're working and set it In Progress. Skip provider-unsupported
  steps (GitHub Issues has no In Progress status, and its labels must already
  exist).
- Write a plan to `.agent/ticket-<n>-plan.md`. Don't commit plan files.
- Work on a feature branch. On Claude Code remote the branch is created before
  this file is read — continue on it rather than remaking it.

## Phase 2 — Execution

- Make the minimal change the task needs; don't refactor unrelated code or fix
  symptoms instead of root causes.
- Reflect user-facing changes in `README.md`; add any new env var to the matching
  `.example` file in the same change.
- Never skip pre-commit hooks or force-push to `main`/`master`. Use `trash`, not
  `rm -rf`, for deletions.
- Never allowlist an interpreter or shell in permissions — `Bash(python3:*)`,
  `Bash(node:*)`, `Bash(bash -c:*)`, `Bash(sh -c:*)`, `Bash(xargs:*)` are
  effectively arbitrary code execution. Allowlist the specific read-only tools a
  task needs instead, and keep state-mutating commands behind manual approval.
- Comments: no numbering; no ticket/issue/bug numbers; don't add a comment that
  only explains a reaction to a past bug (write the code as if it had always been
  that way).
- Debugging an environment- or deployment-specific failure: see the
  `debugging-discipline` skill.

## Phase 3 — Validation (run what the project configures; skip what it doesn't)

- Run the project's tests, lint/format, and build before opening a PR. Note "N/A"
  for a step the project doesn't have.
- For user-facing UI changes, capture before/after screenshots (see the
  `visual-verification` skill) and attach them to the PR via the
  `github-image-upload` skill.

## Phase 4 — Submission

- Push and open a PR: conventional-commit title, body with a summary + test plan,
  referencing the ticket (#<n>). Keep the title/description current with
  `gh pr edit` as later commits change the branch's scope.
- **Review (mandatory).** Review the diff — use the `pr-reviewer` agent for diffs
  that change logic, control flow, data handling, or public contracts; self-review
  is enough for trivial diffs — and post it as a distinct PR review comment, even
  when nothing is actionable.
- **Address feedback.** Fix or justify each item; file a ticket for valuable
  out-of-scope items. Then post a _separate_ responder follow-up comment (e.g.
  "Thanks for the review."). The reviewer comment and the responder comment are
  two distinct comments — never merge them.
- Remove the `agent active` label. Add the designated assignee(s) as reviewer.
  Comment the PR link + implementation summary on the ticket, and set it In Review
  (skip steps the provider can't do).
- **Watch the PR** until it merges, if the subscription tool is available: handle
  CI failures and review comments, and rebase when `main` advances. Full mechanics
  (event handling, `CronCreate` self check-in, conflict resolution) are in
  `.claude/docs/pr-watching.md`.

## Conventions

- **Language:** American English everywhere (initialize, color, center, canceled,
  gray), including when editing files that currently use British spellings.
- **Shell:** one command per line — never chain with `&&`. Never use heredocs in
  Bash (they break permission matching); write `gh` bodies to a temp file and use
  `--body-file`.
- **Filing tickets** (distinct from the ticket you're working): label with the
  target `owner/repo`, set Triage status, assign the project's assignee, and never
  add the `claude` label. Skip unsupported steps.
- **Requesting repo access** you don't have: stop and ask the user for it with
  exact instructions — see `.claude/docs/github-access.md`.
- **Python projects:** see the `python-guidelines` skill (uv-managed envs, `src/`
  layout, Ruff, pytest). **Remote screenshot hook bootstrap:** see the
  `session-start-hook` skill.
