#!/usr/bin/env bash
#
# Upload a PR screenshot to S3 and print a presigned GET URL as ready-to-paste
# Markdown. This is a thin wrapper that runs the Python implementation under
# `uv run --with boto3`, so neither the AWS CLI nor boto3 needs to be
# preinstalled — only `uv` (present in every Claude session) plus network
# access to PyPI (first run only, then cached) and to S3. See the
# github-image-upload skill for the full workflow, the required environment
# variables, and the one-time operator setup (bucket, lifecycle rule, credentials).
#
# Prints ONLY the Markdown image embed on stdout; all status and errors go to
# stderr. Capture stdout and check the exit status before using it, so a failed
# upload aborts instead of writing a broken embed into a PR body:
#   embed="$(.claude/scripts/upload-pr-screenshot.sh after.png)" || exit 1
#   gh pr create --body "After: ${embed}"
#
# Usage:
#   .claude/scripts/upload-pr-screenshot.sh <screenshot-path> [alt-text]
#   .claude/scripts/upload-pr-screenshot.sh --table <before-path> <after-path> [before-alt] [after-alt]
#
# --table uploads both images and prints a complete before/after Markdown table
# with bare `![alt](url)` cells, so the table is never hand-assembled (the most
# common way the embeds regressed into code-wrapped text or plain links).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: 'uv' is required but was not found. Install it from https://docs.astral.sh/uv/ and re-run." >&2
  exit 1
fi

# --quiet keeps uv's dependency-resolution/progress output off stdout so only
# the Python program's Markdown reaches the caller. boto3 is fetched into uv's
# cache on the first run and reused afterward.
exec uv run --with boto3 --python 3.11 --quiet \
  python "${SCRIPT_DIR}/pr_screenshot_upload.py" "$@"
