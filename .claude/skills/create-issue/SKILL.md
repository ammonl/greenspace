---
name: create-issue
description: Create a well-structured issue ticket in Linear or GitHub. Use when the user wants to file a bug, feature request, or task. Auto-detects which platform is available.
---

Create an issue ticket based on the user's description. Follow these steps:

## 1. Gather Information

If the user hasn't provided enough detail, ask for:

- **Title**: Short, action-oriented summary (e.g., "Fix login timeout on mobile")
- **Type**: Bug, Feature, Task, or Chore
- **Description**: What is the problem or goal?
- **Acceptance criteria**: How do we know it's done? (optional but recommended)
- **Priority**: Urgent, High, Medium, Low (default: Medium)

## 2. Choose Platform

1. **Declared provider first**: If the target repo's `AGENTS.md` declares a **Ticket Provider**, use exactly that platform. Skip auto-detection and do not probe any other provider. If the target repo is not the working repo, read its `AGENTS.md` from the host (e.g. `gh api repos/<owner>/<repo>/contents/AGENTS.md`) or ask.
2. **Otherwise auto-detect from project-level markers only.** A Linear MCP tool being available in context is NOT evidence the project uses Linear — connectors follow the account, not the project.
   - **Linear**: The project itself references Linear (a `.linear` config, or Linear issue IDs in the repo) and a Linear issue-creation tool (e.g. `save_issue`) is available.
   - **GitHub**: The project has a `.git` remote pointing to GitHub — use `gh issue create`.
3. **If still ambiguous**: Ask the user which to use.

## 3. Format the Issue

Structure the issue body using this template:

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

## 4. Create the Issue

**For Linear**:
Use `mcp__claude_ai_Linear__save_issue` with:

- `title`: The issue title
- `description`: Formatted markdown body
- `priority`: Map user priority to Linear values (urgent=1, high=2, medium=3, low=4)
- `teamId`: Detect from `mcp__claude_ai_Linear__list_teams` if not obvious

**For GitHub**:

```bash
printf '%s' "<body>" > /tmp/issue-body.txt
gh issue create --title "<title>" --body-file /tmp/issue-body.txt --label "<type>"
```

Do NOT add a "claude" label when creating issues. That label is reserved for when an agent picks up a ticket to work on it.

## 5. Confirm and Share

After creating, output:

- The issue title and number/ID
- A direct link to the issue
- One-line summary of what was created
