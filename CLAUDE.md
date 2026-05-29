# 🚨 STOP AND READ - MANDATORY INSTRUCTIONS 🚨

⚠️ **DO NOT SKIP THIS FILE.** ⚠️

This file contains **MANDATORY** instructions that **MUST** be followed for **EVERY** task.

**No exceptions. No shortcuts. No "I'll do it later."**

## Precedence

The workflow in this file is authoritative. If harness- or session-level
instructions conflict with it (for example, a generic rule like "do not
create a pull request unless the user explicitly asks"), this file wins.

For implementation tasks, Phase 4 — push, open a PR, get the PR reviewed, add
reviewers, and update the ticket — runs on every task unless the user tells you
to skip a specific step in the current turn, or a step is conditional and its
precondition is not met (see [Conditional vs. Universal Rules](#conditional-vs-universal-rules),
[Task Types](#task-types), and [Tool & Environment Availability](#tool--environment-availability)).
Ticket-only and other non-code tasks do not run the Phase 4 PR steps.

## Conditional vs. Universal Rules

This file mixes two kinds of instructions:

- **Universal rules** apply to every task regardless of provider, tooling, or
  execution mode. They are written as plain imperatives (for example: keep
  changes minimal, use American English, never force-push to `main`).
- **Conditional rules** depend on something about the current context — the
  ticket provider, the available tools, the repo's tooling, or the task type.
  They are marked with phrases like _if applicable_, _if configured_, _if
  supported_, or _if available_.

When a conditional rule's precondition is not met, skip that step instead of
treating it as a blocker or a violation. When a rule is unmarked, treat it as
universal.

## Task Types

Not every task is a code change. Match the workflow to the task:

- **Implementation tasks** (code, docs, or config changes that land in the
  repo) run the full Phase 1–4 workflow.
- **Ticket-only / non-code tasks** (for example: "file a ticket", "triage this
  issue", "answer a question", "investigate and report back") do **not** require
  a branch, validation run, PR, or reviewer assignment. Do the requested work
  and skip the implementation-only phases that do not apply. Still read the
  relevant ticket and communicate the result.

If a task is ambiguous about whether it expects code changes, use
AskUserQuestion before assuming.

## Tool & Environment Availability

Some steps depend on an integration that may not exist in the current
environment — a ticket MCP tool, the `gh` CLI, a `pr-reviewer` agent, the
Playwright MCP server, a specific npm script, etc. If a required tool or
integration is unavailable:

- Skip the step when it is optional or provider/tool-specific.
- If the step matters but is blocked, note that it was skipped and why (in the
  PR description or your response) and continue with the rest of the workflow
  rather than stopping.
- Never fabricate the result of a step you could not actually run.

## Provider-Specific Workflow Steps

Some ticket/issue workflow steps in this file assume capabilities that not
every ticket provider supports. If a workflow step that deals with a ticket
or issue is not applicable to the current ticket provider, ignore that
specific instruction rather than treating it as a required step.

For example, GitHub Issues do not support an `In Progress` status the way
other providers (such as Linear) do, so instructions to move a ticket to
`In Progress` or `in review` simply do not apply when GitHub Issues is the
provider — skip them. The same goes for any other provider-specific
capability (custom statuses, certain label conventions, assignment
semantics, etc.) that the active provider lacks.

This exception applies **only** to ticket/issue workflow steps that the
current provider genuinely cannot support. It does not exempt you from the
rest of the workflow: every other phase and step still runs as written, and
steps that the provider _does_ support (for example, reading the ticket,
adding labels that exist, and commenting) must still be completed.

# 📋 MANDATORY WORKFLOW FOR EVERY TASK

Every task follows this exact pattern. **No skipping phases.**

## 🟡 PHASE 1: PRE-WORK (Before Writing Code)

### 1.1 Load Context

Always start by reading the issue via the project's ticket provider using the MCP tool or local client. Add the labels "agent active" and "claude" to the ticket you are working on, and move it to "In Progress" status. (If the current provider does not support one of these steps — for example, GitHub Issues has no `In Progress` status, and labels must already exist — skip the unsupported step per [Provider-Specific Workflow Steps](#provider-specific-workflow-steps).) These labels apply to the ticket you are actively working; tickets you _file_ follow the separate rules in [Filing Tickets](#filing-tickets).

**Confirm:**

- [ ] Ticket read and understood
- [ ] Labels added (if supported)
- [ ] Status updated (if supported)
- [ ] Requirements clear (if not, use AskUserQuestion)

### 1.2 Create Planning Document

Create `.agent/ticket-<number>-plan.md` with:

- **Analysis**: Current state, target state, approach
- **Task Checklist**: All steps needed
- **Implementation Summary**: Files to modify, estimated impact

**Confirm:**

- [ ] Plan document created (do not commit plan files)
- [ ] Approach is sound (if uncertain, get user approval)

### 1.3 Setup Branch

```bash
# Ensure on latest main
git checkout main
git pull
```

Create a feature branch using the project format. Follow the branch naming
rules whenever possible — this is the preferred path.

**Note on Claude Code remote:** Claude Code remote generally creates a branch
_before_ it reads `CLAUDE.md`, so the steps above cannot always be followed
literally. If work is already happening in a branch that was created outside
this workflow before `CLAUDE.md` was read, that is acceptable — continue on
that branch rather than treating it as a violation. Only create a new branch
when you are not already on a suitable working branch.

**CHECKPOINT: Phase 1 complete?**

- ✅ Ticket read; labels added and status updated (if supported)
- ✅ Plan created
- ✅ On a working branch (created from latest main when possible, or the
  pre-existing branch provided by the remote workflow)

**If NO to any item, STOP and complete it NOW.**

---

## 🟢 PHASE 2: EXECUTION (Write Code)

### Code Guidelines

**Critical Rules:**

1. **Minimal changes** - Address task requirements ONLY
2. **DRY/KISS/YAGNI** - Keep it simple, avoid over-engineering
3. **Root causes** - Fix underlying issues, not symptoms
4. **No scope creep** - Don't refactor unrelated code
5. **Concise communication** - Remove filler, use bullets

**Safety:**

- DO NOT modify logic/variables unrelated to the task
- Use `trash` for deletions, never `rm -rf`
- Never skip pre-commit hooks without explicit permission
- Never force push to main/master

**Best Practices:**

- Follow existing code patterns in the codebase
- Maintain consistent formatting and style
- Add validation for user input
- Provide user-facing error messages (not just console.error)
- Consider edge cases and error states
- Ensure that any relevant changes are reflected in README.md
- If any new environment variables are added, add them into the appropriate environment `.example` file in the same change (not as a separate cleanup step)

**Workflow Customizations**
Follow all Task Execution Workflow Customizations steps or instructions included in this file.

---

## 🔵 PHASE 3: VALIDATION (Before Creating/Updating PR)

Complete every **applicable** check before creating a PR. The commands below are
examples — use the project's actual equivalents, and skip any check the project
does not configure. (For example, this repo has no test/lint/build step; its
validation is `npm run format:check` via Prettier.)

### 3.1 Run Tests

```bash
npm test  # or the project's test command
```

Run the project's test suite if it has one.

- [ ] All tests pass (if a test suite exists)
- [ ] Coverage meets the project's threshold, if the project tracks coverage (add tests if needed)

**If no test script exists:** note "N/A" in the plan or PR.

### 3.2 Run Linter

```bash
npm run lint  # or the project's lint/format command
```

- [ ] No new linting/formatting errors introduced (if the project configures a linter or formatter)

### 3.3 Build Verification

```bash
npm run build  # or the project's build command
```

- [ ] Build completes successfully (if the project has a build step)
- [ ] No errors or critical warnings

### 3.4 Pre-commit Checks

- [ ] Pre-commit hooks pass (if configured)
- [ ] No debugging code left (console.log, debugger, etc.)

### 3.5 Visual Verification

When a change affects user-facing UI **and** the Playwright MCP server is available, use it to:

- [ ] Start the dev server (or relevant preview).
- [ ] Navigate to the affected route.
- [ ] Capture screenshots at the relevant viewports (e.g., 375px, 768px, 1440px).
- [ ] For modified surfaces, also check out main, capture the "before" at the same viewports, then return to the feature branch.
- [ ] Attach screenshots to the PR description with clear before/after labels.

Save screenshots under .agent/screenshots/ticket-<number>/ so they're traceable. Do not commit them — upload to the PR directly via gh pr comment --body-file referencing the image, or use gh to attach via a GitHub-hosted upload. If the change has no user-facing UI, or the Playwright MCP server is unavailable, skip this step (note the skip in the PR when relevant).

**CHECKPOINT: All validation items complete?**

**If NO, fix issues before proceeding.**

---

## ⚪ PHASE 4: SUBMISSION

### 4.1 Push and Create PR

```bash
git push -u origin <branch-name>
```

Create PR with:

- **Title**: Conventional commit format (feat:, fix:, etc.)
- **Body**: Include ticket number, summary, test plan
- **Link**: Reference ticket (#<number>)
- **Screenshots (visual changes)**: If the change affects any user-facing UI, include screenshots in the PR description. Include before and after when modifying an existing surface. For new UI where no "before" exists, include after screenshots only and note it's a new surface. Capture the same viewport and state in both images so the diff is obvious.

```bash
gh pr create --title "feat: <description>" --body "..."
```

### 4.2 PR Review (MANDATORY)

Every PR must be reviewed before requesting human review. The reviewing is
mandatory; the specific tool is not. If a `pr-reviewer` agent is available, use it:

```
Review PR #<number> comprehensively and post findings as PR review comment
```

If no review agent is available, perform a self-review of the diff instead and
note that in the PR.

The reviewer must **always** leave a distinct PR review comment, even when the
review finds nothing actionable (in that case the comment should say so
explicitly). This review comment is one of two required comments on every PR —
it must never be merged with the responder follow-up comment from 4.3.

- [ ] PR reviewed (by the review agent if available, otherwise a self-review)
- [ ] Review findings posted as a PR comment (e.g. via `gh pr review`, or the available tooling)
- [ ] This reviewer comment is separate from the responder follow-up comment (4.3)

### 4.3 Address Feedback

**For EVERY piece of feedback:**

- Either fix the issue and update PR
- Or explain why it shouldn't be addressed
- For any issues that are judged to be valuable but out of scope, create a new ticket via the project's ticket provider using the MCP tool.

After responding to the review, the responder must **always** leave a separate
follow-up PR comment — every PR, every time. This is the second of the two
required comments and must be **distinct** from the reviewer comment in 4.2; the
two must never be combined into a single comment. If the review had no actionable
feedback, the responder must still leave a follow-up comment such as
`Thanks for the review.`

Post response using:

```bash
gh pr comment <number> --body "Addressed: ... / Not addressed: ..."
```

- [ ] All feedback addressed or justified, or a ticket has been created for the out of scope feedback.
- [ ] Separate responder follow-up comment posted to the PR (even when there is no actionable feedback, e.g. `Thanks for the review.`)
- [ ] Responder follow-up is a distinct comment, not merged with the reviewer comment (4.2)

### 4.4 Remove label

Remove the "agent active" label from the ticket.

### 4.5 Final Steps

Add ammonl as a reviewer, if the platform and tooling support adding reviewers.

```bash
# Add reviewer
gh pr edit <number> --add-reviewer ammonl
```

Leave a comment on the ticket referencing the PR, with a summary of the implementation.

- [ ] Reviewer added (ammonl), if supported
- [ ] Ticket commented with PR link + implementation summary
- [ ] Move the ticket to "in review" status (skip if the current provider has no such status — see [Provider-Specific Workflow Steps](#provider-specific-workflow-steps)).
- [ ] Ready for final review

---

## Language & Spelling

Always use **American English** spelling and terminology in all written output — code comments, docstrings, log messages, commit messages, PR descriptions, documentation, and user-facing strings.

- Use `-ize` / `-ization`, not `-ise` / `-isation` (e.g., `initialize`, `organization`).
- Use `-or`, not `-our` (e.g., `color`, `behavior`, `favor`).
- Use `-er`, not `-re` (e.g., `center`, `meter`).
- Use single `l` in past tense where American English does (e.g., `canceled`, `traveled`, `modeled`).
- Prefer American vocabulary (e.g., `gray` not `grey`, `catalog` not `catalogue`).

This applies even when editing files that already contain British spellings — normalize to American English unless the surrounding identifier is a fixed external API name (e.g., a third-party library's `Colour` class) that cannot be changed.

## Command Style

Never chain commands with `&&`. Use separate commands instead.

Bad:

```bash
cd foo && npm install && npm test
```

Good:

```bash
cd foo
npm install
npm test
```

**Never use heredocs in Bash commands.** Heredocs embed newlines into the command string, which breaks permission pattern matching.

For multi-line `gh` command bodies, write to a temp file instead:

```bash
printf '%s' "body content here" > /tmp/pr-body.txt
gh pr create --title "..." --body-file /tmp/pr-body.txt
```

Or use a single-quoted string with explicit \n escaping if the body is short enough to fit on one line.

The key flags that accept files:

```
- `gh pr create --body-file <file>`
- `gh pr comment --body-file <file>`
- `gh pr review --body-file <file>`
- `gh issue comment --body-file <file>`
```

# Filing Tickets

These rules apply to tickets you **file** (e.g. to fix a bug you discovered or as a followup), which is distinct from the ticket you are actively working (see [1.1 Load Context](#11-load-context)).

If you need to create a ticket, use the MCP tool or local client. Do not add the label "claude" to a ticket you file. Put the ticket in TODO status and assign it to Ammon Larson, if the provider supports statuses and assignment (skip the unsupported part per [Provider-Specific Workflow Steps](#provider-specific-workflow-steps)).

# Python Guidelines

Always use uv to manage python environments and run python commands. Check at the root folder for existing environments before creating a new one.
When working in the Python coding language, follow “The Hitchhiker’s Guide to Python” conventions for project structure, packaging, tooling, and general best practices:
Core principles

- Prefer readability and explicitness over cleverness.
- Keep modules small and cohesive; avoid deep inheritance and over-abstraction.
- Prefer the standard library where practical; add dependencies only when justified.
  Project layout and structure
- Default to a `src/` layout for packages (e.g., `src/<package_name>/...`) and keep import paths clean.
- Keep configuration, documentation, and tooling files at the repo root.
- Put tests in `tests/` and write tests that are fast, deterministic, and isolated.
- Organize code by feature/domain rather than by “layers” unless the project clearly benefits.
  Environment and dependencies
- Always assume an isolated virtual environment.
- Prefer pinned, reproducible dependencies (lockfile or pinned requirements).
- Do not instruct to modify global Python installations.
  Code style
- Follow PEP 8 naming and formatting conventions.
- Prefer f-strings, pathlib, context managers, and type hints where they improve clarity.
- Write docstrings for public modules/classes/functions; keep them concise and useful.
- Use exceptions intentionally; never blanket-catch without re-raising or logging.
  Tooling (assume these unless the user specifies otherwise)
- Formatting/linting: use Ruff (and Black only if requested or already present).
- Type checking: use mypy or pyright if the project uses typing seriously.
- Testing: use pytest; use fixtures; avoid network in unit tests.
- Logging: use the standard `logging` module; no print statements in library code.
  Async and concurrency
- Use asyncio only for I/O concurrency; avoid making everything async.
- Do not block the event loop; if forced to call blocking code from async code, use `asyncio.to_thread()`.
- Do not add numbering to comments.
- Do not mention specific tickets, issues, or bug numbers in comments.
- If a change is a reaction to a bug in existing code and would not have been commented if the code had been written that way initially, do not add that comment.

---

# 🎯 QUICK REFERENCE

Implementation tasks run all four phases below. Ticket-only / non-code tasks
skip the branch, validation, and PR steps — see [Task Types](#task-types).

```
Phase 1: Pre-Work
├─ Read ticket/issue, add labels + update status (if supported)
├─ Create .agent/ticket-X-plan.md
└─ Use the project branch format (or the pre-existing remote branch)

Phase 2: Execution
├─ Write minimal code
├─ Follow project patterns
├─ Add new env vars to the matching .example file
└─ Add validation + error handling

Phase 3: Validation (run each check the project configures)
├─ Tests (if a suite exists)
├─ Lint / format (if configured)
├─ Build (if a build step exists)
└─ Pre-commit checks

Phase 4: Submission
├─ git push + create PR
├─ PR review (agent if available, else self-review) + post a distinct reviewer comment
├─ Address all feedback + post a separate responder follow-up comment (e.g. "Thanks for the review.")
├─ Remove "agent active" label (if supported)
├─ Add reviewer (ammonl, if supported)
├─ Comment on ticket
└─ Update ticket status (if supported)

Note: skip any ticket/issue step above that the current provider does not
support, and any tool-specific step whose tool is unavailable — see
[Provider-Specific Workflow Steps](#provider-specific-workflow-steps),
[Conditional vs. Universal Rules](#conditional-vs-universal-rules), and
[Tool & Environment Availability](#tool--environment-availability).
```

## Critical Reminders

**DON'T:**

- ❌ Forget ticket labels (when the provider supports them)
- ❌ Skip planning document
- ❌ Modify unrelated code
- ❌ Skip PR review (use a self-review if no review agent is available)
- ❌ Skip the reviewer comment or the responder follow-up comment — both are required on every PR
- ❌ Merge the reviewer comment and the responder follow-up into a single comment
- ❌ Ignore review feedback
- ❌ Force push to main
- ❌ Treat a conditional step as a blocker when its precondition is not met

**DO:**

- ✅ Follow the phase workflow
- ✅ Validate required fields
- ✅ Provide user-facing errors
- ✅ Test before pushing
- ✅ Address all PR feedback
- ✅ Leave two distinct PR comments every time: a reviewer comment and a separate responder follow-up
- ✅ Keep changes minimal

---

# ⚠️ WHY THIS MATTERS

**Skipping workflow phases leads to:**

- Missing labels → Lost tracking
- No planning → Wasted rework
- No validation → Broken builds
- No review → Critical bugs shipped

**Following this file ensures:**

- ✅ Consistent, high-quality code
- ✅ Proper tracking and documentation
- ✅ Caught bugs before merge
- ✅ Efficient workflow
- ✅ User trust maintained

---

**Remember: This file is not a suggestion. It is a requirement.**

**When in doubt, re-read this file. When finishing a task, verify all phases complete.**

# PROJECT-SPECIFIC INFORMATION

---

## IMPORTANT! Keep the '# PROJECT-SPECIFIC INFORMATION' header here -- everything above is automatically copied from the Claude configuration repo, and updated whenever the global instructions change. Everything below is project-specific, and should be edited as needed.

## Project Settings

- **Ticket Provider**: GitHub Issues
- **Branch Format**: `<type>/<ticket-number>` (e.g., `feature/123`)
- **Main Branch**: `main`

## Project Overview

UN17 Village Rooftop Gardens — bilingual (Danish/English) registration platform for two rooftop greenhouses (Kronen, Søen) with a 29-box catalog. Public users register without auth; admins use email/password.

Primary references:
- `docs/specs/greenspace-2026-spec.md` — product spec (single source of truth for requirements)
- `docs/architecture.md` — system architecture with diagrams
- `docs/api/openapi.yaml` — API contract
- `docs/data/schema.md` — data contract and invariants

Working agreement: contract-first changes. Update spec/ADR/API/data contract first, then implementation, then tests.

## Repository Layout

npm workspaces monorepo:

- `apps/api` (`@greenspace/api`) — Node 20 / TypeScript backend. Runs as both an AWS Lambda (`src/lambda.ts`) and a local HTTP dev server (`src/dev-server.ts`) wrapping the same `handler` from `src/index.ts`.
- `apps/web` (`@greenspace/web`) — Next.js 15 / React 19 frontend (App Router, inline styles, no CSS framework).
- `packages/shared` (`@greenspace/shared`) — Domain constants, types, validators, DAWA helpers, i18n key contracts. Imported as source (no build step required for consumers; `transpilePackages` is set in `next.config.js`).
- `infra/terraform` — AWS infrastructure (VPC, Lambda, RDS, SES, Amplify, monitoring) split into `bootstrap/`, `environments/{staging,prod}/`, and `modules/greenspace_stack/`.

## Commands

Root (runs against all workspaces via `--if-present`):

```
npm test          # vitest run in each workspace
npm run lint      # eslint
npm run build     # tsc / next build
npm run typecheck # tsc --noEmit
```

Per-workspace (use `--workspace=@greenspace/<name>` from root, or `cd` into the dir):

```
# apps/api
npm run dev --workspace=@greenspace/api       # tsx watch on port 3001
npm run db:setup --workspace=@greenspace/api  # migrate + seed (needs DB_PASSWORD)
npm run bundle --workspace=@greenspace/api    # esbuild → dist/lambda/index.mjs (Lambda artifact)
npm run test --workspace=@greenspace/api -- <pattern>   # single vitest file/pattern

# apps/web
npm run dev --workspace=@greenspace/web       # next dev on port 3000
```

The web dev server proxies `/public/*`, `/admin/*`, and `/health` to `API_URL` (default `http://localhost:3001`) via `next.config.js` rewrites — start the API before exercising any network paths from the UI.

Local DB bootstrap (Postgres 16 required):

```
docker run -d --name greenspace-db -e POSTGRES_DB=greenspace -e POSTGRES_USER=greenspace -e POSTGRES_PASSWORD=localdev -p 5432:5432 postgres:16
DB_PASSWORD=localdev npm run db:setup --workspace=@greenspace/api
DB_PASSWORD=localdev npm run dev --workspace=@greenspace/api
```

Seed admin password defaults to `changeme123` (override with `SEED_ADMIN_PASSWORD`).

## Architecture Notes

### Backend HTTP layer
Custom router (`apps/api/src/router.ts`) — not Express/Fastify. `Router` exposes `get/post/patch/delete(path, handler)` and matches `:param` segments. Add new endpoints by:
1. Writing a handler `(ctx: RequestContext) => Promise<RouteResponse>` in `src/routes/...`.
2. Registering it in `createRouter()` in `src/index.ts`.
3. Wrapping with `requireAdmin(...)` from `src/middleware/auth.ts` for admin endpoints.

`apps/api/src/index.ts#handler` is the single entry point. It dispatches three event shapes: HTTP requests, EventBridge `Scheduled Event` (hourly session cleanup), and `{action: "migrate"}` (one-shot migrate+seed). The `dev-server.ts` and `lambda.ts` files just adapt their respective transports onto this handler.

DB connection is lazily initialized once per Lambda container (`db` singleton in `index.ts`). In deployed environments it loads `host`, `port`, `dbname`, `username`, and `password` from the shared-db Secrets Manager secret pointed at by `DB_SECRET_ID` (e.g. `rds/shared/greenspace_staging`). For local dev, when `DB_SECRET_ID` is unset, it falls back to the individual `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` env vars.

Staging-only routes (`/admin/staging/*`) are gated by `process.env.ENVIRONMENT === "staging"` — keep destructive helpers behind this guard.

### Database
Kysely query builder over Postgres 16. Migrations live in `apps/api/src/db/migrations/` and are also registered in `migration-registry.ts` (the inline registry is what runs in Lambda — adding a migration file is not enough, you must also add it to the registry). Schema types in `src/db/types.ts` must match the migration shape.

Critical invariants enforced at the DB level (don't replicate in app code, don't bypass):
- One active registration per apartment_key (partial unique index where `status = 'active'`).
- One active occupant per box (partial unique index where `status = 'active'`).
- `audit_events` is append-only — a trigger blocks UPDATE/DELETE.
- Box `state` is `available | occupied | reserved`.

### Time / registration gate (server-authoritative)
The server clock (`Date.now()`) is the only source of truth for whether registration is open. `GET /public/status` returns `isOpen` + `serverTime`; `POST /public/register` re-checks the gate independently. The frontend never trusts the client clock — when API is unreachable it defaults to pre-open (deny). Opening time is stored as `timestamptz` UTC; display uses `Europe/Copenhagen` via `OPENING_TIMEZONE` from `@greenspace/shared`.

### Frontend
State-driven view routing (no URL routes for public flow): `apps/web/src/app/page.tsx` switches between `PreOpenPage` / `LandingPage` / `GreenhouseMapPage` based on local state and `/public/status`. Admin views live under components with `/admin` paths.

i18n via React context (`src/i18n/LanguageProvider.tsx`); language detected from `navigator.language`, manually overridable. Translation keys are contracted in `@greenspace/shared/i18n.ts`; strings live in `apps/web/src/i18n/translations.ts`.

Inline styles only — no Tailwind, no CSS modules. Shared visual constants (e.g. `boxStateColors.ts`) are colocated in `components/`.

### Shared package
`packages/shared` is consumed as source (`main` and `types` point at `src/index.ts`). No need to rebuild after editing — just save and the consumer picks it up. When adding exports, add them to `src/index.ts` and consider whether `index.test.ts`'s export-completeness check needs updating.

### Infra & deploy
- `deploy.yml` triggers on `apps/api/**` or `packages/shared/**` changes to main: bundles via esbuild, deploys to staging Lambda, smoke-tests `/health`, then promotes to prod (gated by GitHub `production` environment protection).
- `terraform.yml` triggers on `infra/terraform/**`; staging applies first, prod after.
- `deploy-web.yml` handles the Amplify-hosted Next.js app.
- `drift-detection.yml` runs daily and opens a GitHub issue if `terraform plan` shows drift.
- All AWS auth uses GitHub OIDC role assumption — no long-lived keys.

## Testing
Vitest in all workspaces. `apps/web` uses `@testing-library/react` + jsdom; `apps/api` runs node-side tests against in-memory or test fixtures (no shared test DB harness — most route tests stub Kysely or use unit-level helpers). Place tests next to the file they cover (`foo.ts` ↔ `foo.test.ts`).
