---
name: visual-verification
description: Capture before/after screenshots for user-facing UI changes and embed them in a PR. Use whenever a change affects any rendered UI. Covers Playwright MCP + CLI capture; embedding goes through the github-image-upload skill (S3 presigned URLs).
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

Keep image files in ignored agent scratch storage, **never** committed to any
branch — not the code-change branch (binary images must not land in the diff
under review) and not a dedicated `screenshots` branch (its URLs don't render
inline in private repos, and it duplicates what the S3 upload already does).
Delete the local files once the PR embed is verified.

## Embedding in the PR

Embedding goes through the `github-image-upload` skill: upload each image to S3
and paste the returned presigned-URL Markdown into the PR body with clear
before/after alt text. In headless/agent sessions that means the fail-fast
wrapper:

```bash
.claude/scripts/upload-pr-screenshot.sh path/to/after-1440.png "After: 1440px"
```

Do **not** embed via `raw.githubusercontent.com`, a `/blob/` URL, a
repository/branch path, or a `screenshots` branch — in these private repos
GitHub's image proxy can't fetch them, so they render as broken images.

If the upload isn't possible (for example the AWS configuration is missing —
see the `github-image-upload` skill), deliver the image files to the user and
ask them to drag them into the PR description box, which uploads them directly.
Do **not** leave broken `![](raw...)` embeds — a broken-image icon is worse
than no image, so state that inline previews are pending the upload.

## Un-verifiable surfaces

If the surface needs authentication or a live backend not available in the current
environment, Playwright can't render it — note the skip in the PR and rely on build
and tests. Don't treat an un-verifiable surface as a blocker.
