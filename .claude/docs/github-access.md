# Requesting GitHub repository access

Referenced by `CLAUDE.md` (Conventions). If accessing a GitHub repository we don't
already have access to would help with the task — to read source, clone a
dependency, inspect issues/PRs, or push a branch — **stop and prompt the user to
grant access** before continuing. Do not silently work around missing access or
abandon the step; surface the blocker and ask.

Give **exact, actionable instructions** tailored to how access is actually missing,
naming the specific `owner/repo`:

- **`gh` not authenticated / wrong account:** run `gh auth login` (or
  `gh auth switch`), then `gh auth status` to confirm.
- **Authenticated but lacking scopes** (e.g. `repo`, `read:org`): run
  `gh auth refresh -h github.com -s repo,read:org` with the exact scopes needed.
- **Private repo owned by an org/another user:** add our account as a collaborator
  (Repo → Settings → Collaborators and teams → Add people), or have an org owner
  grant the team/account access.
- **Org SSO enforced:** authorize the token/SSO for that org (GitHub → Settings →
  Applications, or the "Configure SSO" button next to the token).
- **A specific token is required:** name the exact environment variable or
  credential to set and where.

Prefer having the user run the command via the `!` prefix in the prompt (e.g.
`! gh auth login`) so output lands in-session. After they confirm, verify with a
quick read (e.g. `gh repo view <owner>/<repo>`) before resuming.
