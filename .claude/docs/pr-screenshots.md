# Attaching screenshots to PRs

The canonical instructions for uploading any image to GitHub live in the
**`github-image-upload` skill** (synced to
`.claude/skills/github-image-upload/SKILL.md`); this doc is the PR-screenshot
quick reference and stays consistent with it.

These repositories are **private**, so the only image URL that renders inline in
a PR body is a GitHub attachment
(`https://github.com/user-attachments/assets/…`). A `raw.githubusercontent.com`
URL, a `/blob/` link, a repository/branch path, or a dedicated `screenshots`
branch will **not** render — GitHub's anonymous image proxy can't fetch them for
a private repo. Upload screenshots with the
[`drogers0/gh-image`](https://github.com/drogers0/gh-image) `gh` CLI extension
instead, and paste the returned Markdown into the PR description.

## Upload

Interactive (from a machine where you're signed into `gh`):

```bash
gh image path/to/shot.png --repo <owner>/<repo>
```

It prints ready-to-paste Markdown such as:

```markdown
![shot.png](https://github.com/user-attachments/assets/…)
```

Paste that into the PR body, or capture it inline when creating the PR:

```bash
gh pr create --title "..." --body "Before: $(gh image before.png --repo <owner>/<repo>)"
```

In headless/agent sessions, do **not** call `gh image` directly — use the
fail-fast wrapper, which runs setup, resolves the repo, requires
`GH_SESSION_TOKEN`, runs the `gh image check-token` preflight, validates the
returned `user-attachments/assets/…` URL (rejecting raw/blob/branch/empty), and
prints only the ready-to-paste Markdown on stdout:

```bash
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png            # repo auto-resolved from the checkout
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png owner/repo
```

`.claude/scripts/setup-gh-image.sh` installs the extension idempotently and the
wrapper runs it for you. It prefers the vendored extension source at
`.claude/scripts/gh-image/` (a local, network-free install that works even when
the session's GitHub access does not include `drogers0/gh-image`) and only
falls back to installing from the upstream repo when the vendored copy is
absent — see the `github-image-upload` skill for details.

## Rules

- **Never** embed a PR screenshot via `raw.githubusercontent.com`, a `/blob/`
  URL, a repository/branch path, or a `screenshots` branch.
- Do not commit screenshots to the feature branch. Keep them in ignored agent
  scratch storage and delete them once the PR attachment is verified.
- Include clearly labeled **before/after** screenshots for user-facing changes
  (after-only for a brand-new surface, noted as such); capture the same viewport
  and state in both images so the diff is obvious.

## Authentication (`GH_SESSION_TOKEN`)

Remote/headless uploads need a GitHub `user_session` cookie exposed as
`GH_SESSION_TOKEN`. It is **not** a PAT, **not** `GH_TOKEN`, and **not** the
value from `gh auth token`. It grants full account access, so store it as a
protected environment secret (e.g. a `gh-image` environment) restricted to
trusted branches/workflows, and treat it like a password. Prefer a dedicated bot
account with only the required repository access over a personal session.

Provision it once from a trusted machine signed into github.com:

```bash
.claude/scripts/setup-gh-image.sh
gh image extract-token   # prints the user_session value; store it as GH_SESSION_TOKEN
gh image check-token     # validates it — prints the username, never the token
```

Expose the secret only to the screenshot-upload job:

```yaml
environment: gh-image
env:
  GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  GH_SESSION_TOKEN: ${{ secrets.GH_SESSION_TOKEN }}
```

**Expiry.** The cookie is not long-lived: GitHub invalidates it on sign-out,
inactivity, or password change, and there is no API to mint or renew it. Because
`gh image check-token` runs before every upload, an expired session fails loudly
and early instead of producing a broken image — treat that failure as the signal
to re-extract (`gh image extract-token`) and update the secret. Rotate or revoke
through GitHub **Settings → Sessions / sign out**.
