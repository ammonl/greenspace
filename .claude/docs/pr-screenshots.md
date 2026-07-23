# Attaching screenshots to PRs

The canonical instructions for uploading any image to GitHub live in the
**`github-image-upload` skill** (synced to
`.claude/skills/github-image-upload/SKILL.md`); this doc is the PR-screenshot
quick reference and stays consistent with it.

These repositories are **private**, so a committed image URL
(`raw.githubusercontent.com`, a `/blob/` link, a repository/branch path, or a
dedicated `screenshots` branch) will **not** render inline — GitHub's anonymous
image proxy can't fetch them for a private repo. Instead, upload the screenshot
to S3 and embed the **presigned GET URL** it returns. GitHub's image proxy
(Camo) fetches that URL server-side and caches the bytes, so the image renders
inline and keeps rendering even after the presigned URL expires.

## Upload

Use the fail-fast wrapper. It reads the AWS configuration from the environment,
uploads the image to S3, generates a presigned URL, and prints only the
ready-to-paste Markdown on stdout (status/errors go to stderr). No AWS CLI is
needed — the wrapper runs its uploader under `uv run --with boto3`, so it needs
only `uv` plus network access to PyPI (first run only) and S3:

```bash
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png                 # alt text defaults to the file name
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png "After: 1440px"
```

It prints Markdown such as:

```markdown
![After: 1440px](https://<bucket>.s3.<region>.amazonaws.com/pr-screenshots/…?X-Amz-Signature=…)
```

Paste that into the PR body, or capture it into a variable when creating the
PR — check the exit status first so a failed upload aborts instead of writing a
broken embed:

```bash
embed="$(.claude/scripts/upload-pr-screenshot.sh before.png "Before")" || exit 1
gh pr create --title "..." --body "$embed"
```

## Before/after tables

For a before/after pair, let the wrapper build the whole table with `--table`
instead of hand-assembling the cells — hand-assembly is where the embeds
regress into code-wrapped text or plain links:

```bash
table="$(.claude/scripts/upload-pr-screenshot.sh --table before.png after.png "Before" "After")" || exit 1
gh pr create --title "..." --body "$table"
```

It prints a ready-to-paste table whose cells are already bare `![alt](url)`
embeds — paste it verbatim, add no backticks, keep each leading `!`:

```markdown
| Before                                                                    | After                                                                    |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| ![Before](https://<bucket>.s3.<region>.amazonaws.com/…?X-Amz-Signature=…) | ![After](https://<bucket>.s3.<region>.amazonaws.com/…?X-Amz-Signature=…) |
```

Do **not** wrap the cells in backticks or drop the `!` (`` `[Before]()` `` /
`[After]()`) — that renders as clickable text, not inline images.

## Rules

- **Never** embed a PR screenshot via `raw.githubusercontent.com`, a `/blob/`
  URL, a repository/branch path, or a `screenshots` branch.
- Do not commit screenshots to the feature branch. Keep them in ignored agent
  scratch storage and delete them once the PR embed is verified.
- Include clearly labeled **before/after** screenshots for user-facing changes
  (after-only for a brand-new surface, noted as such); capture the same viewport
  and state in both images so the diff is obvious.

## Required configuration

The upload flow reads all configuration from the environment:

| Variable                        | Required                       | Meaning                                                                                |
| ------------------------------- | ------------------------------ | -------------------------------------------------------------------------------------- |
| `AWS_ACCESS_KEY_ID`             | yes                            | Access key id for the principal that uploads screenshots and signs the presigned URLs. |
| `AWS_SECRET_ACCESS_KEY`         | yes                            | Secret access key for that principal.                                                  |
| `AWS_SESSION_TOKEN`             | only for temporary creds       | Session token; include **only** when using temporary STS/session credentials.          |
| `AWS_REGION`                    | yes                            | Region of the screenshot bucket.                                                       |
| `PR_SCREENSHOT_S3_BUCKET`       | yes                            | Bucket name screenshots are uploaded to.                                               |
| `PR_SCREENSHOT_S3_PREFIX`       | no (default `pr-screenshots/`) | Object-key prefix.                                                                     |
| `PR_SCREENSHOT_URL_TTL_SECONDS` | no (default `604800` = 7 days) | Presigned URL lifetime in seconds (capped at the 7-day SigV4 maximum).                 |

The one-time operator setup — creating the bucket, its 30-day lifecycle rule,
and the AWS credentials — is documented in the `github-image-upload` skill.
