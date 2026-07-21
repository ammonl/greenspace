---
name: github-image-upload
description: Upload images (PR screenshots, diagrams, any visual asset) to S3 and embed them in PR, issue, or comment bodies via a presigned URL. Use whenever embedding an image anywhere on GitHub. Covers the upload wrapper, the required AWS environment, and the one-time operator setup (bucket, 30-day lifecycle rule, credentials).
---

# GitHub image upload (S3 presigned URLs)

This skill is the single source of truth for getting an image to render inline
in a GitHub PR, issue, or comment. Use it whenever you need to embed a
screenshot or any other image asset on GitHub — capture guidance for UI
screenshots lives in the `visual-verification` skill; everything from "I have
an image file" onward lives here.

## How it works

These repositories are private, and committed image files (`raw.githubusercontent.com`,
`/blob/` links, a repository/branch path, or a dedicated `screenshots` branch)
do **not** render inline — GitHub's anonymous image proxy cannot fetch them.
Instead, upload the image to an S3 bucket and embed a **presigned GET URL**.
GitHub's image proxy (Camo) fetches that URL server-side and caches the bytes,
so the image renders inline and keeps rendering even after the presigned URL
expires. The presigned URL therefore only needs to be valid at the moment the
proxy first fetches it; a lifetime of hours-to-days is plenty. The bucket's
lifecycle rule deletes the object after 30 days regardless.

Never commit image files to any branch to serve them, and never leave a broken
`![](…)` embed in a body.

## Upload

Use the fail-fast wrapper. It validates the required configuration, uploads the
image to S3, generates a presigned URL, and prints only the ready-to-paste
Markdown on stdout (all status/errors go to stderr). No AWS CLI is needed: the
wrapper runs its uploader under `uv run --with boto3`, so the only runtime
requirements are `uv` (present in every Claude session) plus network access to
PyPI (first run only, then cached) and to S3.

```bash
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png                 # alt text defaults to the file name
.claude/scripts/upload-pr-screenshot.sh path/to/shot.png "After: 1440px"
```

Capture the stdout into a variable and check the exit status before using it,
so a failed upload aborts instead of creating a PR with a broken embed:

```bash
embed="$(.claude/scripts/upload-pr-screenshot.sh after.png "After: 1440px")" || exit 1
gh pr create --title "..." --body "$embed"
```

The wrapper prints Markdown such as:

```markdown
![After: 1440px](https://<bucket>.s3.<region>.amazonaws.com/pr-screenshots/…?X-Amz-Signature=…)
```

Paste that into the PR description (or issue/comment). Include clearly labeled
**before/after** screenshots for user-facing changes (after-only for a
brand-new surface, noted as such); capture the same viewport and state in both
images so the diff is obvious.

## When authentication fails — stop and prompt the user

If the credentials are missing, expired, invalid, or unauthorized, the wrapper
**exits with code 3** and prints the exact fix on stderr. Treat exit 3 as a hard
stop that only the user can clear:

- **Stop** — do not retry blindly, do not fall back to a committed
  `raw.githubusercontent.com` / `/blob/` URL, and do not leave a broken
  `![](…)` embed in the body.
- **Prompt the user** with the instructions the wrapper printed: regenerate the
  upload principal's access key
  (`aws iam create-access-key --user-name pr-screenshot-uploader`, then delete
  the old key once the new one works), and set the new `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY` (and `AWS_SESSION_TOKEN` only for temporary
  credentials). In a **Claude remote session these belong in the environment's
  configuration** (its variables/secrets), not in the repo — the running session
  cannot set them itself, so the user must.
- As a stopgap **for the current PR only**, you may deliver the image files and
  ask the user to drag them into the PR/issue composer — but the real fix is
  refreshing the credentials so the upload path works again.

The credential env vars themselves are listed under
[Required configuration](#required-configuration); the one-time key generation
is under [Operator setup](#operator-setup-one-time).

## Required configuration

The upload flow reads all configuration from the environment. Provision these
as protected environment secrets/values for the screenshot-upload job.

| Variable                        | Required                       | Meaning                                                                                                 |
| ------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `AWS_ACCESS_KEY_ID`             | yes                            | Access key id for the principal that uploads screenshots and signs the presigned GET URLs.              |
| `AWS_SECRET_ACCESS_KEY`         | yes                            | Secret access key for that principal.                                                                   |
| `AWS_SESSION_TOKEN`             | only for temporary creds       | Session token; include **only** when using temporary STS/session credentials. Omit for long-lived keys. |
| `AWS_REGION`                    | yes                            | Region of the screenshot bucket (e.g. `us-east-1`).                                                     |
| `PR_SCREENSHOT_S3_BUCKET`       | yes                            | Bucket name screenshots are uploaded to.                                                                |
| `PR_SCREENSHOT_S3_PREFIX`       | no (default `pr-screenshots/`) | Object-key prefix; a trailing slash is added if absent.                                                 |
| `PR_SCREENSHOT_URL_TTL_SECONDS` | no (default `604800` = 7 days) | Presigned URL lifetime in seconds. Capped at `604800` (the 7-day SigV4 maximum).                        |

Treat the credentials like any other secret: scope them to the upload job/
workflow, and prefer a dedicated principal whose IAM policy is limited to the
screenshot bucket (see below) over broad account credentials.

## Operator setup (one-time)

The bucket is provisioned **out of band** — the upload path never creates it.
Do this once with an AWS account that can manage S3 and IAM.

### 1. Create the bucket and its 30-day lifecycle rule

```bash
export BUCKET=my-pr-screenshots        # must be globally unique
export REGION=us-east-1

# Create the bucket. us-east-1 omits LocationConstraint; every other region requires it.
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  $( [ "$REGION" = "us-east-1" ] || echo --create-bucket-configuration LocationConstraint="$REGION" )

# Expire uploaded screenshots after 30 days.
cat > /tmp/lifecycle.json <<'JSON'
{
  "Rules": [
    {
      "ID": "expire-pr-screenshots-30d",
      "Filter": { "Prefix": "pr-screenshots/" },
      "Status": "Enabled",
      "Expiration": { "Days": 30 }
    }
  ]
}
JSON
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" --lifecycle-configuration file:///tmp/lifecycle.json
```

Match the rule's `Prefix` to `PR_SCREENSHOT_S3_PREFIX` (default `pr-screenshots/`).
Keep the bucket private — presigned URLs work without public access, and the
image proxy caches the fetched bytes.

### 2. Generate the upload credentials

Create an IAM user with a policy limited to putting and getting objects under
the screenshot prefix, then mint an access key for it:

```bash
export BUCKET=my-pr-screenshots

cat > /tmp/policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::${BUCKET}/pr-screenshots/*"
    }
  ]
}
JSON

aws iam create-user --user-name pr-screenshot-uploader
aws iam put-user-policy --user-name pr-screenshot-uploader \
  --policy-name pr-screenshot-upload --policy-document file:///tmp/policy.json
aws iam create-access-key --user-name pr-screenshot-uploader
```

The `create-access-key` output's `AccessKeyId` and `SecretAccessKey` become
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. The `s3:GetObject` permission
is what lets this principal sign the presigned GET URLs. For temporary
credentials instead, issue them via `aws sts assume-role` against a role with
the same policy and also set `AWS_SESSION_TOKEN`.

Expose the values only to the screenshot-upload job, e.g.:

```yaml
environment: pr-screenshots
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.PR_SCREENSHOT_AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.PR_SCREENSHOT_AWS_SECRET_ACCESS_KEY }}
  AWS_REGION: us-east-1
  PR_SCREENSHOT_S3_BUCKET: my-pr-screenshots
```

## Rules

- **Never** embed an image via `raw.githubusercontent.com`, a `/blob/` URL, a
  repository/branch path, or a `screenshots` branch — and never leave a broken
  `![](…)` embed in a body.
- Do not commit screenshots or other one-off image assets to any branch. Keep
  them in ignored agent scratch storage and delete them once the embed renders.
- Include clearly labeled **before/after** screenshots for user-facing changes
  (after-only for a brand-new surface, noted as such); capture the same
  viewport and state in both images so the diff is obvious.
