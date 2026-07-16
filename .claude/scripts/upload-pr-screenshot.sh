#!/usr/bin/env bash
#
# Fail-fast wrapper for uploading a PR screenshot via gh-image in headless /
# agent environments. It requires the idempotent setup step, a GH_SESSION_TOKEN
# session, and a passing token preflight, then validates the returned URL before
# it can reach a PR body.
#
# Prints ONLY the ready-to-paste Markdown on stdout; all status and errors go to
# stderr, so the stdout can be captured directly in a PR command such as:
#   gh pr create --body "After: $(.claude/scripts/upload-pr-screenshot.sh after.png)"
#
# Usage:
#   .claude/scripts/upload-pr-screenshot.sh <screenshot-path> [owner/repo]
#
# The target repository defaults to the current repository (resolved via
# 'gh repo view') when not supplied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "$@" >&2; }

image_path="${1:-}"
repo="${2:-}"

if [ -z "${image_path}" ]; then
  log "usage: $(basename "$0") <screenshot-path> [owner/repo]"
  exit 2
fi

if [ ! -f "${image_path}" ]; then
  log "error: screenshot not found: ${image_path}"
  exit 2
fi

# Ensure the gh-image extension is installed and usable (idempotent). Running
# setup first also guarantees 'gh' exists before the repo is resolved below.
"${SCRIPT_DIR}/setup-gh-image.sh" >&2

# Default the target repo to the current repository when not supplied. Resolve
# it from the gh/git context rather than hardcoding, so this works in any repo.
if [ -z "${repo}" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  if [ -z "${repo}" ]; then
    log "error: could not resolve the target repo from the current directory; pass it explicitly as owner/repo"
    exit 2
  fi
fi

# Require an exact owner/repo (no protocol, host, .git, or trailing slash) so a
# malformed target cannot be forwarded to gh image.
if ! printf '%s' "${repo}" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
  log "error: repo must be in owner/repo form (got: ${repo})"
  exit 2
fi

# A GitHub user_session cookie is required for headless uploads. Never print,
# log, or inspect its value.
if [ -z "${GH_SESSION_TOKEN:-}" ]; then
  log "error: GH_SESSION_TOKEN is required for headless gh-image uploads; configure the protected gh-image environment secret"
  exit 1
fi

# Fail before any PR body is created if the session is expired or invalid.
if ! gh image check-token >&2; then
  log "error: gh image check-token failed; the GH_SESSION_TOKEN session is expired or invalid"
  exit 1
fi

# Upload. gh-image reads the token from the environment; it is never passed on
# the command line. Guard the assignment so a non-zero gh exit reports a clear
# error here rather than aborting silently under set -e.
if ! markdown="$(gh image "${image_path}" --repo "${repo}")"; then
  log "error: gh image upload failed for ${image_path}"
  exit 1
fi

# Reject empty output and any raw / blob / branch URL before it can be inserted
# into a PR description; require a github.com/user-attachments/assets/ URL.
if [ -z "${markdown}" ]; then
  log "error: gh image produced no output"
  exit 1
fi

if printf '%s' "${markdown}" | grep -Eq 'raw\.githubusercontent\.com|/blob/|/raw/'; then
  log "error: gh image returned a forbidden raw/blob/branch URL; refusing to emit it: ${markdown}"
  exit 1
fi

if ! printf '%s' "${markdown}" | grep -Eq 'https://github\.com/user-attachments/assets/'; then
  log "error: gh image output did not contain a github.com/user-attachments/assets/ URL: ${markdown}"
  exit 1
fi

# Success: emit only the ready-to-paste Markdown on stdout.
printf '%s\n' "${markdown}"
