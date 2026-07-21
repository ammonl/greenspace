"""Upload a PR screenshot to S3 and print a presigned-URL Markdown embed.

Invoked through ``upload-pr-screenshot.sh``, which runs this under
``uv run --with boto3`` so neither the AWS CLI nor boto3 needs to be
preinstalled. All configuration is read from the environment; see the
github-image-upload skill for the variables and the one-time operator setup.

Only the Markdown image embed is written to stdout; every status line and
error goes to stderr, so the stdout can be captured directly into a PR body.
"""

import os
import secrets
import sys
from datetime import datetime, timezone
from typing import NoReturn

CONTENT_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
}

# SigV4 presigned URLs cannot outlive 7 days.
MAX_TTL_SECONDS = 604800

# S3/STS error codes that mean the credentials are missing, wrong, expired, or
# unauthorized — the upload principal needs attention, not a retry.
AUTH_ERROR_CODES = {
    "InvalidAccessKeyId",
    "SignatureDoesNotMatch",
    "AccessDenied",
    "AccessDeniedException",
    "ExpiredToken",
    "TokenRefreshRequired",
    "InvalidToken",
    "InvalidSecurity",
    "UnrecognizedClientException",
    "AuthFailure",
}

# Distinct exit code so the caller (and the github-image-upload skill) can tell a
# credential problem apart from an ordinary failure and prompt the user to fix it.
CREDENTIAL_EXIT_CODE = 3


def fail(message, code=1) -> NoReturn:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(code)


def fail_credentials(problem, *, regenerate) -> NoReturn:
    """Stop with actionable rotation/config instructions and exit code 3.

    Used whenever the credentials are missing or S3 rejects them, so the caller
    knows to halt and prompt the user rather than retry or fall back.
    """
    lines = [
        f"error: {problem}",
        "",
        "Screenshots cannot be uploaded until this is fixed. Stop here and ask the",
        "user to refresh the credentials — do not retry blindly, fall back to a",
        "committed image URL, or leave a broken embed.",
        "",
        "Fix (full steps in the github-image-upload skill):",
    ]
    step = 1
    if regenerate:
        lines += [
            f"  {step}. Regenerate the upload principal's access key:",
            "       aws iam create-access-key --user-name pr-screenshot-uploader",
            "     then delete the old key once the new one works:",
            "       aws iam delete-access-key --user-name pr-screenshot-uploader \\",
            "         --access-key-id <OLD_KEY_ID>",
        ]
        step += 1
    lines += [
        f"  {step}. Set the screenshot-upload environment variables:",
        "       AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, PR_SCREENSHOT_S3_BUCKET",
        "       (and AWS_SESSION_TOKEN only when using temporary credentials)",
        "     In a Claude remote session, set these in the environment's",
        "     configuration (its variables/secrets), not in the repo.",
    ]
    print("\n".join(lines), file=sys.stderr)
    raise SystemExit(CREDENTIAL_EXIT_CODE)


def main(argv):
    if not argv:
        print(
            "usage: upload-pr-screenshot.sh <screenshot-path> [alt-text]",
            file=sys.stderr,
        )
        raise SystemExit(2)

    image_path = argv[0]
    alt_text = argv[1] if len(argv) > 1 else ""

    if not os.path.isfile(image_path):
        fail(f"screenshot not found: {image_path}", 2)

    # AWS_SESSION_TOKEN is intentionally not required: it is only set when
    # temporary STS/session credentials are used. All AWS_* values are consumed
    # implicitly by boto3's default credential and region resolution.
    region = os.environ.get("AWS_REGION", "")
    bucket = os.environ.get("PR_SCREENSHOT_S3_BUCKET", "")
    required = {
        "AWS_ACCESS_KEY_ID": os.environ.get("AWS_ACCESS_KEY_ID", ""),
        "AWS_SECRET_ACCESS_KEY": os.environ.get("AWS_SECRET_ACCESS_KEY", ""),
        "AWS_REGION": region,
        "PR_SCREENSHOT_S3_BUCKET": bucket,
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        fail_credentials(
            "missing screenshot-upload configuration: " + ", ".join(missing),
            regenerate=False,
        )

    extension = os.path.splitext(image_path)[1].lower()
    content_type = CONTENT_TYPES.get(extension)
    if content_type is None:
        fail(
            f"unsupported image extension '{extension}'; use png, jpg, jpeg, gif, webp, or svg",
            2,
        )

    ttl_raw = os.environ.get("PR_SCREENSHOT_URL_TTL_SECONDS", str(MAX_TTL_SECONDS))
    if not ttl_raw.isdigit() or not 0 < int(ttl_raw) <= MAX_TTL_SECONDS:
        fail(
            "PR_SCREENSHOT_URL_TTL_SECONDS must be a positive integer no greater "
            f"than {MAX_TTL_SECONDS} (the 7-day SigV4 maximum); got: {ttl_raw}"
        )
    ttl = int(ttl_raw)

    # Default prefix keeps screenshots namespaced within the bucket. An empty
    # value also falls back to the default, so uploads always land under the
    # prefix the bucket lifecycle rule expires.
    prefix = os.environ.get("PR_SCREENSHOT_S3_PREFIX", "") or "pr-screenshots/"
    if not prefix.endswith("/"):
        prefix += "/"

    # Unique object key: a timestamp plus random bytes avoids collisions when the
    # same screenshot name is uploaded from different PRs or runs.
    filename = os.path.basename(image_path)
    safe_name = "".join(c if c.isalnum() or c in "._-" else "_" for c in filename)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    key = f"{prefix}{stamp}-{secrets.token_hex(4)}-{safe_name}"

    import boto3
    from botocore.config import Config
    from botocore.exceptions import (
        BotoCoreError,
        ClientError,
        NoCredentialsError,
        PartialCredentialsError,
    )

    # Force SigV4 with virtual-hosted addressing so the presigned URL is valid
    # in every region and can carry the full 7-day expiry; boto3 would otherwise
    # fall back to the legacy SigV2 query format in some cases.
    s3 = boto3.client(
        "s3",
        region_name=region,
        config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
    )

    try:
        with open(image_path, "rb") as image:
            s3.put_object(Bucket=bucket, Key=key, Body=image, ContentType=content_type)
    except (NoCredentialsError, PartialCredentialsError) as error:
        fail_credentials(f"AWS credentials could not be resolved: {error}", regenerate=True)
    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "")
        if code in AUTH_ERROR_CODES:
            fail_credentials(f"S3 rejected the upload credentials ({code}).", regenerate=True)
        fail(f"failed to upload {image_path} to s3://{bucket}/{key}: {error}")
    except BotoCoreError as error:
        fail(f"failed to upload {image_path} to s3://{bucket}/{key}: {error}")

    try:
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=ttl,
        )
    except (BotoCoreError, ClientError) as error:
        fail(f"failed to presign s3://{bucket}/{key}: {error}")

    if not url:
        fail("presign produced no URL")

    print(f"![{alt_text or filename}]({url})")


if __name__ == "__main__":
    main(sys.argv[1:])
