#!/usr/bin/env bash
#
# Idempotently install the drogers0/gh-image gh CLI extension, which uploads PR
# screenshots to GitHub and returns github.com/user-attachments/assets/... URLs
# (the only image URLs that render inline in a private-repository PR body).
#
# Safe to run repeatedly: it installs the extension only when it is absent,
# verifies the extension is usable, and reports the installed version. It never
# inspects, echoes, or otherwise touches GH_SESSION_TOKEN.
set -euo pipefail

EXTENSION="drogers0/gh-image"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: the GitHub CLI ('gh') is required but was not found." >&2
  echo "       Install it from https://cli.github.com/ and re-run this script." >&2
  exit 1
fi

# Install only when the extension is not already present. Capture the list once
# so the presence check is a plain grep with no pipe — avoiding any pipefail /
# SIGPIPE interaction — where a "not found" result (grep exit 1) simply selects
# the install branch rather than aborting under set -e.
installed_extensions="$(gh extension list)"
if grep -q "gh-image" <<< "${installed_extensions}"; then
  echo "gh-image already installed; skipping install."
else
  echo "Installing ${EXTENSION} (requires network access on first run)..."
  gh extension install "${EXTENSION}"
fi

# Verify the extension actually runs before declaring success.
if ! gh image --help >/dev/null 2>&1; then
  echo "error: 'gh image --help' failed; the gh-image extension is not usable." >&2
  exit 1
fi

# Report the installed version. Prefer 'gh image --version' when the extension
# supports it; otherwise fall back to the version token from 'gh extension list'
# rather than treating unsupported version syntax as success.
version="$(gh image --version 2>/dev/null || true)"
if [ -z "${version}" ]; then
  # Fall back to the version column (last field) of the gh-image row.
  version="$(gh extension list | awk '/gh-image/ {print $NF; exit}' || true)"
fi
if [ -z "${version}" ]; then
  version="(version unavailable)"
fi

echo "gh-image ready: ${version}"
