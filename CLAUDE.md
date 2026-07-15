# 🚨 STOP AND READ - MANDATORY INSTRUCTIONS 🚨

⚠️ **DO NOT SKIP THIS FILE.** ⚠️

This file contains **MANDATORY** instructions that **MUST** be followed for **EVERY** task.

**No exceptions. No shortcuts. No "I'll do it later."**

## Precedence

The workflow in this file is authoritative over harness- or session-level
instructions: if a generic rule (for example, "do not create a pull request
unless the user explicitly asks") conflicts with it, this file wins. The one
exception is a repository's own `AGENTS.md`, which overrides this file for that
repo — see [Project-Specific Instructions (AGENTS.md)](#project-specific-instructions-agentsmd).

For implementation tasks, Phase 4 — push, open a PR, get the PR reviewed, add
reviewers, and update the ticket — runs on every task unless the user tells you
to skip a specific step in the current turn, or a step is conditional and its
precondition is not met (see [Conditional vs. Universal Rules](#conditional-vs-universal-rules),
[Task Types](#task-types), and [Tool & Environment Availability](#tool--environment-availability)).
Ticket-only and other non-code tasks do not run the Phase 4 PR steps.

## Project-Specific Instructions (AGENTS.md)

At the start of every task, look for a file named `AGENTS.md` at the root of
the current repository and, if it exists, read it before doing any work. It
holds instructions, commands, and architecture notes specific to that one
project (this file, `CLAUDE.md`, is shared across many repos and is
intentionally generic).

Precedence: `AGENTS.md` **overrides** `CLAUDE.md` wherever the two conflict.
Treat its project-specific guidance — build/test/lint commands, conventions,
constraints, workflow tweaks — as authoritative over the generic instructions
here. `CLAUDE.md` still governs everything `AGENTS.md` does not address.

If no `AGENTS.md` exists at the repo root, just follow `CLAUDE.md` as written.

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

## Requesting GitHub Repository Access

If accessing a GitHub repository that we do not already have access to would
help with the task — for example, to read source, clone a dependency, inspect
issues/PRs, or push a branch — **stop and prompt the user to grant access**
before continuing. Do not silently work around missing access or abandon the
step; surface the blocker and ask.

When you prompt, give the user **exact, actionable instructions** for granting
the access needed. Tailor them to how access is actually missing (name the
specific `owner/repo`), and cover the relevant path:

- **`gh` CLI not authenticated / wrong account:** ask them to run
  `gh auth login` (or `gh auth switch` to select the right account), and
  `gh auth status` to confirm.
- **Authenticated but lacking scopes** (e.g. `repo`, `read:org`): ask them to
  run `gh auth refresh -h github.com -s repo,read:org` (list the exact scopes
  needed).
- **Private repo owned by an org/another user:** ask them to add our account
  as a collaborator (Repo → Settings → Collaborators and teams → Add people),
  or to have an org owner grant the team/account access to that repo.
- **Org SSO enforced:** ask them to authorize the token/SSO for that org
  (GitHub → Settings → Applications, or the "Configure SSO" button next to the
  personal access token).
- **A specific token is required:** tell them exactly which environment
  variable or credential to set and where.

Prefer suggesting they run the command themselves via the `!` prefix in the
prompt (e.g. `! gh auth login`) so the output lands in this session. After they
confirm access is granted, verify with a quick read (e.g. `gh repo view
<owner>/<repo>`) before resuming the task.

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

## Remote Session Provisioning for Screenshots (Playwright hook)

For Claude Code on the web to run the app and capture screenshots (the
[3.5 Visual Verification](#35-visual-verification) step), the container needs a
remote `SessionStart` hook that installs the repo's dependencies and the browser
the Playwright MCP drives. The synced `settings.json` already registers this hook
at `.claude/hooks/session-start.sh` with `matcher: "remote"`, but the script
itself is **not** part of the sync set — each repo must carry its own, because
the dependency-install step is stack-specific (for example `npm install` vs.
`uv pip install -e '.[dev]'` vs. a build). Only the browser-install step is
identical across repos.

On any task, do a quick check and bootstrap the hook if it is missing — this is
a one-time-per-repo action that no-ops once the hook exists:

- Look for `.claude/hooks/session-start.sh` that installs the repo's
  dependencies **and** the Playwright MCP browser. If it exists and does both,
  do nothing further.
- The base Chromium at `/opt/pw-browsers` is **not** the browser the MCP drives —
  it needs the `chrome-for-testing` build, which is not pre-installed — so the
  hook must install it explicitly.
- If the hook is missing (or present but does not install the MCP browser),
  create or update `.claude/hooks/session-start.sh` so it is:
  - remote-only (guard on `CLAUDE_CODE_REMOTE`), **asynchronous** (its first
    stdout line is `{"async": true, "asyncTimeout": 600000}`), idempotent, and
    prep-only — it must never start a long-running dev server.
  - installs the repo's dependencies with the stack's real command (confirm it
    from the repo's manifests / `AGENTS.md`, e.g. `npm install`,
    `uv pip install -e '.[dev]'`), then the MCP browser:
    `npx --yes @playwright/mcp@latest install-browser chrome-for-testing`
    (add `npx --yes playwright install-deps chromium` where the OS libraries are
    not already present).
  - `chmod +x` and registered under `hooks.SessionStart` with `matcher: "remote"`
    by merging into `.claude/settings.json`, preserving existing hooks.
- Prove it end-to-end before committing: run the hook against a simulated cold
  start, serve the app, capture one Playwright-MCP screenshot, then delete the
  screenshot and any test artifacts so they are not committed.
- Open a **dedicated PR** for just this hook/config change, separate from the
  task at hand. A repo may set stack-specific details (install command, port,
  health check) in its `AGENTS.md`.

## Remote Session Provisioning for Screenshots (Playwright hook)

For Claude Code on the web to run the app and capture screenshots (the
[3.5 Visual Verification](#35-visual-verification) step), the container needs a
remote `SessionStart` hook that installs the repo's dependencies and the browser
the Playwright MCP drives. The synced `settings.json` already registers this hook
at `.claude/hooks/session-start.sh` with `matcher: "remote"`, but the script
itself is **not** part of the sync set — each repo must carry its own, because
the dependency-install step is stack-specific (for example `npm install` vs.
`uv pip install -e '.[dev]'` vs. a build). Only the browser-install step is
identical across repos.

On any task, do a quick check and bootstrap the hook if it is missing — this is
a one-time-per-repo action that no-ops once the hook exists:

- Look for `.claude/hooks/session-start.sh` that installs the repo's
  dependencies **and** the Playwright MCP browser. If it exists and does both,
  do nothing further.
- The base Chromium at `/opt/pw-browsers` is **not** the browser the MCP drives —
  it needs the `chrome-for-testing` build, which is not pre-installed — so the
  hook must install it explicitly.
- If the hook is missing (or present but does not install the MCP browser),
  create or update `.claude/hooks/session-start.sh` so it is:
  - remote-only (guard on `CLAUDE_CODE_REMOTE`), **asynchronous** (its first
    stdout line is `{"async": true, "asyncTimeout": 600000}`), idempotent, and
    prep-only — it must never start a long-running dev server.
  - installs the repo's dependencies with the stack's real command (confirm it
    from the repo's manifests / `AGENTS.md`, e.g. `npm install`,
    `uv pip install -e '.[dev]'`), then the MCP browser:
    `npx --yes @playwright/mcp@latest install-browser chrome-for-testing`
    (add `npx --yes playwright install-deps chromium` where the OS libraries are
    not already present).
  - `chmod +x` and registered under `hooks.SessionStart` with `matcher: "remote"`
    by merging into `.claude/settings.json`, preserving existing hooks.
- Prove it end-to-end before committing: run the hook against a simulated cold
  start, serve the app, capture one Playwright-MCP screenshot, then delete the
  screenshot and any test artifacts so they are not committed.
- Open a **dedicated PR** for just this hook/config change, separate from the
  task at hand. A repo may set stack-specific details (install command, port,
  health check) in its `AGENTS.md`.

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

### Debugging discipline

When diagnosing a failure — especially an environment- or deployment-specific one — follow these before reaching for deep infrastructure theories:

- **Config-parity first.** When the _same build/image_ is healthy in one environment and broken in another, diff the per-environment **configuration** (env vars, secrets, config maps) **before** investigating code, mounts, or timing. A green staging + red prod on an identical build is a config delta until proven otherwise.
- **Diagnose the real process, not a convenience shell.** Env-dependent behavior (`$HOME`, `expanduser`, `PATH`) can differ between an interactive shell (`kubectl exec`, SSH) and the actual service process, because the runtime may inject env from the user's passwd entry for exec sessions only. Read the real process's environment (e.g. `/proc/1/environ`), not an exec shell's `echo $HOME`.
- **Reproduce with the app's real inputs.** When something fails in-app but "works" in a manual test, make the manual test use the **same resolved config/arguments** the app uses — not hardcoded stand-ins. A hardcoded value that passes proves nothing about the config-derived path.
- **Pick the single decisive check.** When each diagnostic round-trips through a human or slow tooling, choose the one test that discriminates between the leading hypotheses in a single step instead of iterating one theory at a time.
- **Drop disproven theories and their artifacts immediately.** When a hypothesis is refuted, discard any half-built fix or branch for it — do not push a dead branch or apply a known no-op "just in case".

### Permissions hygiene

- **Never allowlist an interpreter or shell.** Entries like `Bash(python3:*)`, `Bash(node:*)`, `Bash(bash -c:*)`, `Bash(sh -c:*)`, or `Bash(xargs:*)` are effectively arbitrary code execution — the permission matcher only sees the command prefix, not what the interpreter runs, so they are no narrower than allowing everything. Allowlist the **specific read-only tools** the task needs instead (e.g. `Bash(jq:*)` for JSON processing, `Bash(kubectl logs:*)` / `Bash(gcloud logging read:*)` for reads). Keep state-mutating or code-executing commands behind manual approval.

---

## 🔵 PHASE 3: VALIDATION (Before Creating/Updating PR)

Complete every **applicable** check before creating a PR. The commands below are
examples — use the project's actual equivalents, and skip any check the project
does not configure.

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

When a change affects user-facing UI, **always** capture screenshots and include
them in the PR. This is not optional for UI changes.

- [ ] Start the dev server (or relevant preview).
- [ ] Navigate to the affected route.
- [ ] Capture screenshots at the relevant viewports (e.g., 375px, 768px, 1440px).
- [ ] For modified surfaces, also check out main, capture the "before" at the same viewports, then return to the feature branch.
- [ ] Embed screenshots directly in the PR description as Markdown images (backed by the `screenshots` branch — see below), with clear before/after labels.
- [ ] Embed screenshots directly in the PR description as Markdown images (backed by the `screenshots` branch — see below), with clear before/after labels.

**Preferred tool: Playwright MCP server.** The project `.mcp.json` configures a
Playwright MCP server with `--browser chromium --headless`. Use it to navigate,
interact (click toggles, fill forms, select states), and screenshot.

**Fallback: Playwright CLI.** If the MCP server is unavailable or errors out,
use the Playwright CLI directly via Bash. The environment pre-installs Chromium
at `/opt/pw-browsers` with `PLAYWRIGHT_BROWSERS_PATH` already set:

```bash
# Simple full-page screenshot
npx -y playwright@latest screenshot --browser chromium --viewport-size "1440,900" --full-page http://localhost:5173 screenshot.png

# For interactive scenarios (clicking, toggling state), write a short script:
node -e "
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto('http://localhost:5173');
  await page.screenshot({ path: 'before.png', fullPage: true });
  await page.click('input[type=checkbox]');
  await page.screenshot({ path: 'after.png', fullPage: true });
  await browser.close();
})();
"
```

**Commit screenshot files to the `screenshots` branch, not the feature branch,
and embed them in the PR description as Markdown images.** Do **not** commit
screenshot assets into the code-change branch being reviewed — that would put
binary image files in the diff under review. Instead:

- Commit the screenshot files to a dedicated `screenshots` branch in this repo,
  under a `screenshots/ticket-<number>/` path. **If the `screenshots` branch
  does not exist yet, create it first** (e.g. from an existing branch:
  `git fetch origin`, then `git push origin origin/main:refs/heads/screenshots`
  to create it on the remote), then add the image files there and push.
- In the PR description, embed each screenshot inline as a Markdown image that
  points at the file on the `screenshots` branch via its raw URL, using the
  form:

  ```markdown
  ![alt text](https://raw.githubusercontent.com/OWNER/REPO/BRANCH/path/to/image.png)
  ```

  For example:

  ```markdown
  ![settings panel — after](https://raw.githubusercontent.com/ammonl/ammonl-claude/screenshots/screenshots/ticket-61/after-1440.png)
  ```

  Use `screenshots` as the `BRANCH` segment and the committed path (e.g.
  `screenshots/ticket-<number>/after-1440.png`) as `path/to/image.png` so the
  images render inline in the PR description without depending on `gh` or an
  external upload. Provide clear before/after labels in the alt text.

If the change has no user-facing UI, skip this step.
**Commit screenshot files to the `screenshots` branch, not the feature branch,
and embed them in the PR description as Markdown images.** Do **not** commit
screenshot assets into the code-change branch being reviewed — that would put
binary image files in the diff under review. Instead:

- Commit the screenshot files to a dedicated `screenshots` branch in this repo,
  under a `screenshots/ticket-<number>/` path. **If the `screenshots` branch
  does not exist yet, create it first** (e.g. from an existing branch:
  `git fetch origin`, then `git push origin origin/main:refs/heads/screenshots`
  to create it on the remote), then add the image files there and push.
- In the PR description, embed each screenshot inline as a Markdown image that
  points at the file on the `screenshots` branch via its raw URL, using the
  form:

  ```markdown
  ![alt text](https://raw.githubusercontent.com/OWNER/REPO/BRANCH/path/to/image.png)
  ```

  For example:

  ```markdown
  ![settings panel — after](https://raw.githubusercontent.com/ammonl/ammonl-claude/screenshots/screenshots/ticket-61/after-1440.png)
  ```

  Use `screenshots` as the `BRANCH` segment and the committed path (e.g.
  `screenshots/ticket-<number>/after-1440.png`) as `path/to/image.png` so the
  images render inline in the PR description without depending on `gh` or an
  external upload. Provide clear before/after labels in the alt text.

> **Private repositories: raw URLs do NOT render inline.** The
> `raw.githubusercontent.com` embed above only works for **public** repos.
> GitHub renders images in PR/issue bodies through its camo image proxy, which
> fetches the URL server-side **without authentication**; for a private repo the
> raw (and `github.com/<owner>/<repo>/raw/...`) URL requires a token, so camo
> gets a 404 and the image shows broken — even though the `blob` view opens fine
> for a logged-in human. Check the repo's visibility first (e.g.
> `gh repo view <owner>/<repo> --json visibility`, or note a 404 on the repo
> homepage when unauthenticated) and branch on it:
>
> - **Public repo:** use the `raw.githubusercontent.com` embed above.
> - **Private repo:** the only thing that renders inline for all authorized
>   viewers is a GitHub **attachment asset** (a `https://github.com/<owner>/<repo>/assets/...`
>   or `https://github.com/user-attachments/assets/...` URL), which is minted by
>   dragging/pasting the image into the PR description composer — it is **not**
>   tied to repo auth. The API/MCP tools cannot mint these URLs, so an agent
>   cannot embed them unaided. When the repo is private and no attachment-upload
>   tool is available:
>   1. Still commit the images to the `screenshots` branch (durable provenance)
>      and link to their `blob` view in the PR body — `blob` links work for
>      anyone who can access the repo, unlike raw embeds.
>   2. Deliver the image files to the user (e.g. via the file-send tool) with a
>      one-line instruction to drag them into the PR description box for true
>      inline rendering.
>   3. Do **not** leave broken `![](raw...)` embeds in the body — a broken-image
>      icon is worse than a working link. State explicitly in the PR that inline
>      previews require the attachment upload because the repo is private.

If the change has no user-facing UI, skip this step.

If the affected surface requires authentication or a live backend that is not
available in the current environment, Playwright cannot render it — treat this
as an allowed skip, note it in the PR, and rely on the build and tests for
confidence. Do not treat an un-verifiable surface as a blocker.

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
- **Screenshots (visual changes)**: If the change affects any user-facing UI, embed screenshots in the PR description as Markdown images backed by files committed to the `screenshots` branch (see 3.5), not the feature branch. Include before and after when modifying an existing surface. For new UI where no "before" exists, include after screenshots only and note it's a new surface. Capture the same viewport and state in both images so the diff is obvious.
- **Screenshots (visual changes)**: If the change affects any user-facing UI, embed screenshots in the PR description as Markdown images backed by files committed to the `screenshots` branch (see 3.5), not the feature branch. Include before and after when modifying an existing surface. For new UI where no "before" exists, include after screenshots only and note it's a new surface. Capture the same viewport and state in both images so the diff is obvious.

```bash
gh pr create --title "feat: <description>" --body "..."
```

**Keep PR metadata current as the branch evolves.** The PR title and description
must always describe the code currently in the branch, not just the original PR
contents. Whenever a later commit materially changes the PR — its scope,
implementation approach, user-facing impact, or test plan — update the PR title
and/or description in the same turn so they stay accurate. Use `gh pr edit` to
apply the update:

```bash
gh pr edit <number> --title "feat: <updated description>"
gh pr edit <number> --body-file /tmp/pr-body.txt
```

This applies throughout the life of the PR, including while watching it (4.6),
not only at initial creation.

### 4.2 PR Review (MANDATORY)

Every PR must be reviewed before requesting human review. The reviewing is
mandatory; the specific tool is not. If a `pr-reviewer` agent is available, use it:

```
Review PR #<number> comprehensively and post findings as PR review comment
```

If no review agent is available, perform a self-review of the diff instead and
note that in the PR.

Match the review effort to the change. For a **trivial diff** — copy/label text,
comments, config or permission entries, or a mechanical rename with no logic
change — a self-review posted as the review comment is sufficient; you do not
need to spawn the `pr-reviewer` agent. Reserve the agent for diffs that change
logic, control flow, data handling, or public contracts. Either way, the
distinct reviewer comment in this step is still required.

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

Add the designated assignee(s) as a reviewer, if the platform and tooling support adding reviewers.

```bash
# Add reviewer
gh pr edit <number> --add-reviewer alice
```

Leave a comment on the ticket referencing the PR, with a summary of the implementation.

- [ ] Reviewer added (designated assignee(s)), if supported
- [ ] Ticket commented with PR link + implementation summary
- [ ] Move the ticket to "in review" status (skip if the current provider has no such status — see [Provider-Specific Workflow Steps](#provider-specific-workflow-steps)).
- [ ] Ready for final review

### 4.6 Watch the PR (MANDATORY, if supported)

After the PR is opened and reviewed, **always** subscribe to its activity and
watch it until it merges or the user tells you to stop. This is universal — do
it on every PR, without being asked — whenever the PR-activity subscription
tooling is available (e.g. a `subscribe_pr_activity` tool). If that tooling is
not available in the current environment, skip this step and note the skip.

On subscribing, immediately check the current CI status and any unresolved
review comments, and handle them before going idle. Thereafter, for each
incoming CI / review / comment event:

- **CI failure:** diagnose, and if the fix is small and you're confident, push
  it and update the PR. Re-kick the loop on each failure until the checks are
  green; green CI is the terminal state.
- **Review comment:** if the fix is unambiguous and small, make it; if it's
  ambiguous or architecturally significant, ask the user first
  (via AskUserQuestion); if no action is needed, skip silently.
- **Scope change:** whenever a commit you push while watching materially changes
  what the PR contains, update the PR title and/or description with `gh pr edit`
  so they still match the branch (see 4.1).
- **`main` advanced:** when another change lands on `main` while you are watching
  the PR, attempt to rebase the PR branch onto the latest `main`. If the rebase
  cannot be completed cleanly because of conflicts, merge `main` into the PR
  branch where needed instead of abandoning the update. Resolve conflicts so that
  both sides' intent is preserved — keep the intentions behind the changes
  already in the PR branch and the intentions behind the newer changes that
  landed on `main`. Only when there is a true either/or conflict where one side
  must win, prefer the PR branch being watched. After resolving, report a
  concrete list of the files or conflicts that required manual resolution.
- Never poll with `sleep` or repeated status checks — events wake the session.

**Monitoring `main` with `CronCreate`.** PR-activity webhooks do **not** deliver
the events that matter most for keeping a PR current: `main` advancing, CI
turning green, and merge-conflict transitions are never pushed. So relying on the
subscription alone leaves the "`main` advanced" case (above) undetected. To cover
it, schedule a recurring self check-in with the **`CronCreate`** tool when it is
available (it supersedes the older `send_later` approach, which is not provisioned
in this environment). Arm it right after subscribing — roughly hourly on an
off-minute (e.g. cron `37 * * * *`, not `0`/`30`) — with a prompt that re-checks
the watched PR: fetch and compare the PR branch against `origin/main` and
rebase/merge per the `main` advanced rule if it moved, re-check CI status and
mergeability and act on anything actionable, and stop the job (via `CronDelete`)
once the PR is merged or closed. The job must stay silent when nothing changed —
no user message, no PR comment. `CronCreate` jobs are session-only and auto-expire
after 7 days, so re-arm if the PR is still open past that. If `CronCreate` is also
unavailable, note the skip and fall back to event-driven watching only.

- Stop watching the moment the user asks; unsubscribe, cancel the `CronCreate`
  job with `CronDelete`, and push no further changes to that PR.

- [ ] Subscribed to PR activity (if supported)
- [ ] Initial CI status + unresolved review comments checked and addressed
- [ ] Recurring `CronCreate` self check-in armed to catch `main` advancing / CI green / merge transitions (if supported)
- [ ] When `main` advances: rebased onto `main` (merged on conflict, preserving both sides' intent, preferring the PR branch on a true either/or conflict) and reported any files needing manual resolution

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

If you need to create a ticket, use the MCP tool or local client. Always add the target repo name to each ticket you file (for example: `interhumanai/interhuman-api`), if the provider supports labels. Never add the label "claude" to a ticket you file. Put the ticket in `Triage` status, if the provider supports statuses. If a designated assignee(s) exists for the project exists, assign it to them. Skip any unsupported behaviors per [Provider-Specific Workflow Steps](#provider-specific-workflow-steps).

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
- Do not add tests for non-production repo surfaces. The no-tests rule applies at least to docs, infrastructure, scripts, dev tools, and repo-maintenance-only helpers that exist solely to support these. Check AGENTS.md for any additional repo-specific instructions about files and directories to exclude.
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
├─ Keep PR title/description current with `gh pr edit` when later commits change scope
├─ Remove "agent active" label (if supported)
├─ Add reviewer (designated assignee(s), if supported)
├─ Comment on ticket
├─ Update ticket status (if supported)
├─ Subscribe to PR activity + watch CI/reviews until merged (if supported)
└─ When main advances while watching: rebase onto main (merge on conflict),
   preserve both sides' intent, prefer the PR branch on a true either/or
   conflict, and report files that needed manual resolution

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
- ✅ Watch every PR for CI failures and review comments until it merges
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
