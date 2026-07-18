#!/usr/bin/env bash
#
# Idempotently install the gh-image gh CLI extension, which uploads images to
# GitHub and returns github.com/user-attachments/assets/... URLs (the only
# image URLs that render inline in a private-repository PR body). See the
# github-image-upload skill for the full workflow.
#
# The install prefers the vendored extension source synced alongside this
# script at .claude/scripts/gh-image/, using a local, network-free
# 'gh extension install .'. That path works in every session — including
# remote sessions whose GitHub access is scoped away from the upstream
# drogers0/gh-image repository. Installing from the upstream repo is only
# attempted when the vendored copy is absent.
#
# Safe to run repeatedly: it installs the extension only when it is absent,
# verifies the extension is usable, and reports the installed version. It never
# inspects, echoes, or otherwise touches GH_SESSION_TOKEN.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="${SCRIPT_DIR}/gh-image"
UPSTREAM_EXTENSION="drogers0/gh-image"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: the GitHub CLI ('gh') is required but was not found." >&2
  echo "       Install it from https://cli.github.com/ and re-run this script." >&2
  exit 1
fi

# Install only when the extension is not already present. Capture the list once
# so the presence check is a plain grep with no pipe — avoiding any pipefail /
# SIGPIPE interaction — where a "not found" result (grep exit 1) simply selects
# an install branch rather than aborting under set -e. The command itself is
# also guarded, since some gh versions exit non-zero when no extensions are
# installed.
# A remotely installed extension lists as "gh image  drogers0/gh-image  v…",
# but a locally installed (symlinked) one lists as just "gh image" with no
# repo column, so match either form.
installed_extensions="$(gh extension list 2>/dev/null || true)"
if grep -Eq "gh[- ]image" <<< "${installed_extensions}"; then
  echo "gh-image already installed; skipping install."
elif [ -f "${VENDOR_DIR}/gh-image" ]; then
  # Local installs symlink the directory into gh's extension store, need no
  # network or gh authentication, and require the executable bit (which a
  # plain file copy may have dropped).
  echo "Installing gh-image from the vendored copy at ${VENDOR_DIR}..."
  chmod +x "${VENDOR_DIR}/gh-image"
  (cd "${VENDOR_DIR}" && gh extension install .)
else
  echo "No vendored copy at ${VENDOR_DIR}; installing ${UPSTREAM_EXTENSION} (requires GitHub access to that repo)..."
  gh extension install "${UPSTREAM_EXTENSION}"
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
