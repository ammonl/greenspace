---
name: visual-verification
description: Capture before/after screenshots for user-facing UI changes and embed them in a PR. Use whenever a change affects any rendered UI. Covers Playwright MCP + CLI capture, the dedicated `screenshots` branch, raw-URL embeds for public repos, and the attachment-asset path for private repos.
---

# Visual verification

When a change affects user-facing UI, capture screenshots and include them in the
PR. This is not optional for UI changes. If the change has no user-facing UI, skip
it.

## Capture

- **Preferred: Playwright MCP server** (configured in the project `.mcp.json` with
  `--browser chromium --headless`). Use it to navigate, interact (click toggles,
  fill forms, select states), and screenshot.
- **Fallback: Playwright CLI** via Bash. The environment pre-installs Chromium at
  `/opt/pw-browsers` with `PLAYWRIGHT_BROWSERS_PATH` already set:

  ```bash
  npx -y playwright@latest screenshot --browser chromium --viewport-size "1440,900" --full-page http://localhost:5173 screenshot.png
  ```

  For interactive scenarios, write a short Playwright script that navigates,
  screenshots `before.png`, performs the interaction, then screenshots `after.png`.

- **Viewports:** capture at 375 / 768 / 1440. For a modified surface, also check
  out `main`, capture the "before" at the same viewports and state, then return to
  the feature branch.

## Where screenshots live

Commit image files to a dedicated `screenshots` branch under
`screenshots/ticket-<n>/`, **never** the code-change branch (binary images must not
land in the diff under review). If the `screenshots` branch doesn't exist yet,
create it first:

```bash
git fetch origin
git push origin origin/main:refs/heads/screenshots
```

Then add the image files there and push.

## Embedding in the PR

- **Public repo:** embed the raw URL as a Markdown image, with clear before/after
  alt text:

  ```markdown
  ![settings panel — after](https://raw.githubusercontent.com/OWNER/REPO/screenshots/screenshots/ticket-<n>/after-1440.png)
  ```

  Use `screenshots` as the branch segment and the committed path as the image path
  so images render inline without depending on `gh` or an external upload.

- **Private repo:** `raw.githubusercontent.com` URLs do **not** render inline —
  GitHub's camo proxy fetches them unauthenticated and gets a 404. Only a GitHub
  **attachment asset** (`https://github.com/user-attachments/assets/...`), minted by
  dragging/pasting the image into the PR composer, renders inline; the API/MCP
  tools cannot mint these. So when the repo is private and no attachment-upload tool
  is available:
  1. Still commit the images to the `screenshots` branch and link their `blob` view
     in the PR body (`blob` links work for anyone with repo access).
  2. Deliver the image files to the user and ask them to drag them into the PR
     description box for true inline rendering.
  3. Do **not** leave broken `![](raw...)` embeds — a broken-image icon is worse
     than a working link. State that inline previews require the attachment upload
     because the repo is private.
     Check visibility first (e.g. `gh repo view <owner>/<repo> --json visibility`).

## Un-verifiable surfaces

If the surface needs authentication or a live backend not available in the current
environment, Playwright can't render it — note the skip in the PR and rely on build
and tests. Don't treat an un-verifiable surface as a blocker.
