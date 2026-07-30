---
name: create-ticket
description: Create a well-structured ticket or issue with the target repo's declared ticket provider (Jira, Linear, or GitHub Issues). Use whenever the user wants to file a bug, feature request, task, or chore. Falls back to auto-detection when no provider is declared.
---

Create a ticket/issue based on the user's description. Follow these steps:

## 1. Gather Information

If the user hasn't provided enough detail, ask for:

- **Title**: Short, action-oriented summary (e.g., "Fix login timeout on mobile")
- **Type**: Bug, Feature, Task, or Chore
- **Description**: What is the problem or goal?
- **Acceptance criteria**: How do we know it's done? (optional but recommended)
- **Priority**: Urgent, High, Medium, Low (default: Medium)

## 2. Choose Platform

1. **Declared provider first**: If the target repo's `AGENTS.md` declares a **Ticket Provider**, use exactly that platform. Skip auto-detection and do not probe any other provider. If the target repo is not the working repo, read its `AGENTS.md` from the host (e.g. `gh api repos/<owner>/<repo>/contents/AGENTS.md`) or ask.
2. **Otherwise auto-detect from project-level markers only.** An MCP connector being available in context is NOT evidence the project uses that platform — connectors follow the account, not the project.
   - **Linear**: The project itself references Linear (a `.linear` config, or Linear issue IDs in the repo) and a Linear issue-creation tool (e.g. `save_issue`) is available.
   - **Jira**: The project itself references Jira (a `.jira` config or a configured project key) and a Jira MCP tool (e.g. `mcp__*jira*__create_issue` / `mcp__atlassian__*`) or the `jira` CLI is available.
   - **GitHub**: The project has a `.git` remote pointing to GitHub — use `gh issue create`.
3. **If still ambiguous**: Ask the user which to use.

## 3. Format the Issue

Structure the body using this template:

```
## Summary
[1-2 sentence description of the problem or goal]

## Details
[More context, repro steps for bugs, or requirements for features]

## Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Notes
[Any additional context, links, or related issues]
```

For bugs, include:

- Steps to reproduce
- Expected vs actual behavior
- Environment/version info if relevant

Jira uses its own markup in some fields. When creating via a Jira MCP tool that
accepts markdown or ADF, pass the template above as-is. If the target field only
accepts wiki markup, convert headings to `h2.` and checkboxes to `*` list items.

### Operational tickets

For any cutover, configuration, or deployment ticket:

- Exhaustively enumerate every configuration value and environment variable to add or change. Put each on its own line with its exact target value and a format note covering applicable details such as file extension, trailing slash, unit, or casing. Never replace the individual entries with collective phrasing such as "set all the path env vars."
- Include an acceptance checklist for each environment in the form `variable -> expected value -> verification command or log signal`.
- Identify values that must match across environments. State any legitimate environment-specific difference explicitly, such as a differing bucket name.
- Include the exact success and failure log lines or health signals operators should grep for so verification is unambiguous.
- For multi-step operational work, state that the ticket remains open until the final cleanup and verification step is confirmed. Deployment alone is not completion.
- When a configuration value feeds a third-party library's path or name resolution, document the library's convention, such as whether it appends the file extension, so operators do not apply the convention twice.

## 4. Create the Issue

**For Linear**:
Use the available Linear issue-creation tool (e.g. `save_issue`) with:

- `title`: The issue title
- `description`: Formatted markdown body
- `priority`: Map user priority to Linear values (urgent=1, high=2, medium=3, low=4)
- `teamId`: Detect from the Linear team-listing tool (e.g. `list_teams`) if not obvious

**For Jira**:
Use the available Jira MCP tool (e.g. `create_issue`) with:

- `summary`: The issue title
- `description`: Formatted body (see markup note above)
- `issuetype`: Map user type to the project's type name (Bug, Story/Feature, Task, or the nearest configured equivalent)
- `priority`: Map user priority to the project's scheme (Urgent/Highest, High, Medium, Low)
- `project`: The project key. Detect from `.jira` config or ask if not obvious.

If no Jira MCP tool is available but the `jira` CLI is installed:

```bash
printf '%s' "<body>" > /tmp/issue-body.txt
jira issue create --type "<type>" --summary "<title>" --template /tmp/issue-body.txt
```

**For GitHub**:

```bash
printf '%s' "<body>" > /tmp/issue-body.txt
gh issue create --title "<title>" --body-file /tmp/issue-body.txt --label "<type>"
```

## 5. State, Labels, and Assignee

Apply each of these to the filed ticket, and **silently skip any step the provider
can't represent** — an unsupported step is not a failure, and never fake one (no
invented status label, no comment standing in for a state you can't set).

- **State**: put the ticket in its provider's triage/backlog state — Linear `Triage`,
  the Jira project's equivalent, or a configured GitHub Project triage column. GitHub
  Issues has no native state, so an open issue already _is_ its triage state; read a
  request to put a GitHub issue in `Todo` or `Triage` the same way. Only set a status
  on a GitHub Project item when the repo actually has a project configured.
- **Repo label**: make the target repository identifiable, reusing the label form that
  tracker already uses — the repository name minus its owner prefix in a shared
  Linear/Jira workspace (`interhuman-api` for `InterhumanAI/interhuman-api`), or an
  existing `owner/repo` label where a GitHub repo has one. Check the existing labels
  first: create a new one only when the tracker spans repositories and has none, never
  introduce a second variant of a label that already exists in another form, and skip
  the label entirely on a per-repo tracker that doesn't use one.
- **Type label**: apply one if the provider supports it (`--label "<type>"` on GitHub,
  where the label must already exist; the type field on Jira/Linear).
- **Assignee**: assign the designated project assignee if one exists.
- **Never** add a `claude` or `Codex` label. Those are reserved for when an agent picks
  up a ticket to work on it.

## 6. Confirm and Share

After creating, output:

- The issue title and number/ID
- A direct link to the issue
- One-line summary of what was created
