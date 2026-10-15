#!/usr/bin/env bash
set -euo pipefail

repo="${VARS_REPO:-${INPUT_SOURCE_REPO:-}}"
if [[ -z "$repo" ]]; then
  echo "::error::source repo not configured" >&2
  exit 1
fi

if [[ -z "${SECRET_PAT:-}" ]]; then
  echo "::error::token secret missing" >&2
  exit 1
fi

echo "::add-mask::$repo"

level="${INPUT_OBFUSCATION:-on}"
case "$level" in
  on|off) ;;
  *) echo "::error::invalid obfuscation: $level" >&2; exit 1 ;;
esac

ver="${INPUT_TOOLCHAIN_VERSION:-1.11.0}"
if [[ ! "$ver" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "::error::invalid toolchain version" >&2
  exit 1
fi

code="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${SECRET_PAT}" \
  "https://api.github.com/repos/${repo}/git/refs?per_page=1" || true)"
if [[ "$code" != "200" ]]; then
  echo "::error::token cannot read source repo (HTTP $code); Contents read+write required" >&2
  exit 1
fi

{
  echo "SOURCE_REPO=$repo"
  echo "SOURCE_REF=${INPUT_SOURCE_REF:-}"
  echo "OBFUSCATION=$level"
  echo "TOOLCHAIN_VERSION=$ver"
  echo "INPUT_RELEASE_TAG=${INPUT_RELEASE_TAG:-}"
} >> "$GITHUB_ENV"

echo "setup ok"
