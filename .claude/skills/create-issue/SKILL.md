---
name: create-issue
description: Create a well-structured issue ticket with the target repo's declared ticket provider (Jira, Linear, or GitHub Issues). Use when the user wants to file a bug, feature request, task, or chore.
---

Filing an "issue" and filing a "ticket" are the same job, so this skill is an alias:
follow the `create-ticket` skill and do exactly what it says.

`create-ticket` is the single source of truth for provider selection, the issue body
template, ticket state, labels, and assignee — including that the target repo's
`AGENTS.md` `Ticket Provider:` wins over any auto-detection, that a connected tracker
MCP tool is not evidence the project uses that tracker, and that steps a provider can't
represent are silently skipped rather than treated as failures.

Nothing here overrides `create-ticket`; if the two ever appear to disagree,
`create-ticket` is correct.
