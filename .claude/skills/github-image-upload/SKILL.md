---
name: github-image-upload
description: Upload images (PR screenshots, diagrams, any visual asset) to GitHub as attachment assets and embed them in PR, issue, or comment bodies. Use whenever embedding an image anywhere on GitHub. Covers the gh-image extension, the headless upload wrapper, the vendored session-safe install, and GH_SESSION_TOKEN authentication.
---

# GitHub image upload (gh-image)

This skill is the single source of truth for getting an image to render inline
in a GitHub PR, issue, or comment. Use it whenever you need to embed a
screenshot or any other image asset on GitHub — capture guidance for UI
screenshots lives in the `visual-verification` skill; everything from "I have
an image file" onward lives here.

## The one rule

The only image URL guaranteed to render inline in these repositories is a
GitHub **attachment asset**: `https://github.com/user-attachments/assets/…`.
These repositories are private, so GitHub's anonymous image proxy cannot fetch
a `raw.githubusercontent.com` URL, a `/blob/` link, a repository/branch path,
or anything on a dedicated `screenshots` branch — those all show a broken
image. Never use them, and never commit image files to any branch to serve
them. Attachment assets are minted by the
[`gh-image`](https://github.com/drogers0/gh-image) `gh` CLI extension (or by
manually dragging an image into the GitHub composer).

## Upload — headless/agent sessions (the default)

Do **not** call `gh image` directly in agent sessions. Use the fail-fast
wrapper, which installs the extension, resolves the repo, requires
`GH_SESSION_TOKEN`, runs the `gh image check-token` preflight, validates that
the returned URL is a `user-attachments/assets/…` URL (rejecting
raw/blob/branch/empty output), and prints only the ready-to-paste Markdown on
stdout:

```bash
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png            # repo auto-resolved from the checkout
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png owner/repo
```

Capture the stdout directly into a PR body:

```bash
gh pr create --title "..." --body "After: $(.claude/scripts/upload-pr-screenshot.sh after.png)"
```

If the wrapper fails because `GH_SESSION_TOKEN` is missing or expired, do not
fall back to raw/blob URLs. Instead deliver the image files to the user and
ask them to drag the images into the PR/issue composer (which mints the same
attachment assets), and say why: headless uploads need the session token.

## Upload — interactive local sessions

From a machine where you are signed into `gh` in a browser-adjacent session:

```bash
.claude/scripts/setup-gh-image.sh                # one-time, idempotent
gh image path/to/shot.png --repo <owner>/<repo>
```

It prints ready-to-paste Markdown such as:

```markdown
![shot.png](https://github.com/user-attachments/assets/…)
```

## Install / bootstrap (session-safe)

`.claude/scripts/setup-gh-image.sh` installs the extension idempotently, and
the upload wrapper runs it for you, so there is normally nothing to do. The
install order:

1. **Vendored copy (preferred, works in every session).** The extension
   source is vendored at `.claude/scripts/gh-image/` and synced to every
   Claude-enabled repo, so the setup script installs it with a local,
   network-free `gh extension install .`. This requires no GitHub access to
   the upstream repo at all — it works in remote sessions whose GitHub access
   is scoped to a single repository.
2. **Upstream fallback.** Only when the vendored copy is absent (it has not
   been synced into the repo yet) does the script try
   `gh extension install drogers0/gh-image`, which needs network access to
   that repo and will fail in scoped remote sessions.

Never try to widen a session's GitHub repo access just to install gh-image;
if the vendored copy is missing, refresh it (below) or ask the user to.

### Refreshing the vendored copy (maintainers)

The vendored source is produced by the `vendor-gh-image` workflow in the
central `ammonl-claude` repo (manual `workflow_dispatch`). It clones
`drogers0/gh-image` on an Actions runner, copies the source into
`.claude/scripts/gh-image/` with provenance recorded in `VENDORED.md`, and
delivers the refresh as a PR (or a direct commit to a given branch). Never
hand-edit files under `.claude/scripts/gh-image/`.

## Authentication (`GH_SESSION_TOKEN`)

Remote/headless uploads need a GitHub `user_session` cookie exposed as
`GH_SESSION_TOKEN`. It is **not** a PAT, **not** `GH_TOKEN`, and **not** the
value from `gh auth token`. It grants full account access, so store it as a
protected environment secret (e.g. a `gh-image` environment) restricted to
trusted branches/workflows, and treat it like a password. Prefer a dedicated
bot account with only the required repository access over a personal session.

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
inactivity, or password change, and there is no API to mint or renew it.
Because `gh image check-token` runs before every upload, an expired session
fails loudly and early instead of producing a broken image — treat that
failure as the signal to re-extract (`gh image extract-token`) and update the
secret. Rotate or revoke through GitHub **Settings → Sessions / sign out**.

## Rules

- **Never** embed an image via `raw.githubusercontent.com`, a `/blob/` URL, a
  repository/branch path, or a `screenshots` branch — and never leave a broken
  `![](…)` embed in a body.
- Do not commit screenshots or other one-off image assets to any branch. Keep
  them in ignored agent scratch storage and delete them once the attachment
  is verified.
- Include clearly labeled **before/after** screenshots for user-facing changes
  (after-only for a brand-new surface, noted as such); capture the same
  viewport and state in both images so the diff is obvious.
