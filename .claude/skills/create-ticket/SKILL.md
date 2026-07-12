---
name: create-ticket
description: Create a well-structured ticket or issue in Jira, Linear, or GitHub Issues. Use whenever the user wants to file a bug, feature request, task, or chore. Auto-detects which platform is available.
---

Create a ticket/issue based on the user's description. Follow these steps:

## 1. Gather Information

If the user hasn't provided enough detail, ask for:

- **Title**: Short, action-oriented summary (e.g., "Fix login timeout on mobile")
- **Type**: Bug, Feature, Task, or Chore
- **Description**: What is the problem or goal?
- **Acceptance criteria**: How do we know it's done? (optional but recommended)
- **Priority**: Urgent, High, Medium, Low (default: Medium)

## 2. Detect Platform

Check which platform is available, in this order:

1. **Linear**: If the `mcp__claude_ai_Linear__save_issue` tool is available and the project uses Linear (check for `.linear` config or Linear MCP tools in context), use Linear.
2. **Jira**: If a Jira MCP tool is available (e.g. `mcp__*jira*__create_issue` / `mcp__atlassian__*`) or the `jira` CLI is installed, and the project uses Jira (check for `.jira`, a configured project key, or Jira MCP tools in context), use Jira.
3. **GitHub fallback**: If the project has a `.git` remote pointing to GitHub, use `gh issue create`.
4. **If more than one is available**: Ask the user which to use.

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

**For Linear** (preferred when available):
Use `mcp__claude_ai_Linear__save_issue` with:

- `title`: The issue title
- `description`: Formatted markdown body
- `priority`: Map user priority to Linear values (urgent=1, high=2, medium=3, low=4)
- `teamId`: Detect from `mcp__claude_ai_Linear__list_teams` if not obvious
- `labels`: Add a label matching the repository name without the organization or owner prefix. For example, use `interhuman-api` for `InterhumanAI/interhuman-api`. Verify the label exists and create it if necessary before creating the issue.

**For Jira**:
Use the available Jira MCP tool (e.g. `create_issue`) with:

- `summary`: The issue title
- `description`: Formatted body (see markup note above)
- `issuetype`: Map user type to the project's type name (Bug, Story/Feature, Task, or the nearest configured equivalent)
- `priority`: Map user priority to the project's scheme (Urgent/Highest, High, Medium, Low)
- `project`: The project key. Detect from `.jira` config or ask if not obvious.
- `labels`: Add a label matching the repository name without the organization or owner prefix, mirroring the Linear rule above.

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

GitHub Issues has no native Todo state. Interpret a request to put a GitHub issue in Todo as leaving the issue open, unless a configured GitHub Project exposes a Todo status; when it does, add the issue to that project status.

Put a filed ticket in `Triage` (Linear) or the project's equivalent backlog/triage state (Jira). Assign the designated project assignee if one exists.

Do NOT add a "Codex" or "claude" label when creating issues. Those labels are reserved for when an agent picks up a ticket to work on it.

## 5. Confirm and Share

After creating, output:

- The issue title and number/ID
- A direct link to the issue
- One-line summary of what was created
