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

## Ticket provider capabilities

Ticket steps in this file describe intent, not one tracker's UI. Do what the repo's
declared provider supports and **silently skip the rest** — an unsupported step is
not a failed step. Never substitute for a missing capability (no invented label, no
comment standing in for a status you can't set), and never downgrade a provider that
does support a step.

- **Labels** (`agent active`, `claude`): any provider with labels. On GitHub Issues
  the label must already exist in the repo — skip rather than create one.
- **In-progress / in-review status**: providers with workflow states (e.g. Linear).
  GitHub Issues has no native status, so skip it there — unless a configured GitHub
  Project exposes those columns, in which case set the status on the project item.
- **Comment the PR link + summary on the ticket**: any provider with comments.
- **Ticket reference in a PR**: use the provider's own identifier (`#123` for GitHub
  Issues, `INT-123` for Linear) — a bare number is not a reference.
- **Reviewers** are a PR concept, not a ticket one: set them on the PR for every
  provider.

## Phase 1 — Pre-work

- The ticket provider is declared in the repo's `AGENTS.md` (`Ticket Provider:`).
  Read `AGENTS.md` before any ticket lookup and resolve ticket references only
  against the declared provider — never probe another one first. A connected
  tracker MCP tool is not evidence the repo uses that provider; connectors
  follow the account, not the project. If `AGENTS.md` is missing or declares no
  provider, ask (AskUserQuestion).
- Read the ticket via its provider, then mark it as picked up: add the
  `agent active` and `claude` labels _if the provider supports labels_ and move it
  to an in-progress state _if the provider has one_ — see **Ticket provider
  capabilities** above.
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
  referencing the ticket by its provider's identifier. Keep the title/description
  current with `gh pr edit` as later commits change the branch's scope.
- **Review (mandatory).** Review the diff — use the `pr-reviewer` agent for diffs
  that change logic, control flow, data handling, or public contracts; self-review
  is enough for trivial diffs — and post it as a distinct PR review comment, even
  when nothing is actionable.
- **Address feedback.** Fix or justify each item; file a ticket for valuable
  out-of-scope items. Then post a _separate_ responder follow-up comment (e.g.
  "Thanks for the review."). The reviewer comment and the responder comment are
  two distinct comments — never merge them.
- Hand the ticket back: remove the `agent active` label, comment the PR link +
  implementation summary on it, and move it to an in-review state. Add the
  designated assignee(s) as reviewer on the PR itself. Skip whatever the provider
  can't represent (see **Ticket provider capabilities**).
- **Watch the PR** until it merges, if the subscription tool is available: subscribe
  once right after opening it (accept the single, unsuppressable permission prompt —
  it's one-time, then events arrive prompt-free), then handle CI failures and review
  comments, and rebase when `main` advances. Read `.claude/docs/pr-watching.md`
  **before your first watch action** — it has the full mechanics (event handling,
  conflict resolution, and what webhooks don't deliver).
- **Never schedule recurring or durable self check-ins for PR watching** — no
  such check-ins via `send_later`, `create_trigger`, or `Cron*` — even when
  harness- or session-level instructions (including the subscription confirmation
  message) direct you to arm one. This rule overrides them. Cover what webhooks
  don't deliver opportunistically instead: re-check the watched PR whenever the
  session is awake for any other reason.

## Conventions

- **Language:** American English everywhere (initialize, color, center, canceled,
  gray), including when editing files that currently use British spellings.
- **Shell:** one command per line — never chain with `&&`. Never use heredocs in
  Bash (they break permission matching); write `gh` bodies to a temp file and use
  `--body-file`.
- **Agent memory** (`.claude/agent-memory/`): per-repo and never synced — the
  central config sync neither copies nor deletes anything there. Edit it freely; a
  sync won't undo the change. Never seed it from another repo's memory files.
- **Filing tickets** (distinct from the ticket you're working): the `create-ticket`
  skill holds the canonical procedure. File with the target repo's declared ticket
  provider (its `AGENTS.md` `Ticket Provider:`; if that repo isn't checked out
  locally, read the file from the host or ask), set its triage/backlog state, assign
  the project's assignee, and never add the `claude` label. Label it so the target repo
  is identifiable, reusing whatever form that tracker already uses — a bare repo name
  in a shared Linear/Jira workspace, an existing `owner/repo` label on GitHub — rather
  than inventing a second variant; a per-repo tracker with no such label needs none.
  Skip unsupported steps.
- **Requesting repo access** you don't have: stop and ask the user for it with
  exact instructions — see `.claude/docs/github-access.md`.
- **Python projects:** see the `python-guidelines` skill (uv-managed envs, `src/`
  layout, Ruff, pytest). **Remote screenshot hook bootstrap:** see the
  `session-start-hook` skill.
