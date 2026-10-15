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

ver_req="${INPUT_TOOLCHAIN_VERSION:-1.11.0}"
if [[ ! "$ver_req" =~ ^[0-9A-Za-z._-]+$ ]]; then
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

tags="$(curl -s -H "Authorization: Bearer ${SECRET_PAT}" \
  "https://api.github.com/repos/${repo}/git/refs/tags?per_page=100" \
  | grep -oE 'refs/tags/v?[0-9]+\.[0-9]+\.[0-9]+' | sed 's#refs/tags/v\?##' | sort -V -u || true)"

latest="$(printf '%s\n' "$tags" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)"

if [[ -z "$latest" ]]; then
  nex_major=1
  nex_minor=0
  nex_patch=0
else
  IFS=. read -r nex_major nex_minor nex_patch <<< "$latest"
  nex_patch=$((nex_patch + 1))
fi

for _ in $(seq 1 40); do
  if (( nex_patch > 10 )); then
    nex_minor=$((nex_minor + 1))
    nex_patch=0
  fi
  cand="${nex_major}.${nex_minor}.${nex_patch}"
  if printf '%s\n' "$tags" | grep -qx "$cand"; then
    nex_patch=$((nex_patch + 1))
    continue
  fi
  break
done

if [[ -z "${cand:-}" ]]; then
  echo "::error::cannot resolve next version" >&2
  exit 1
fi

{
  echo "SOURCE_REPO=$repo"
  echo "SOURCE_REF=${INPUT_SOURCE_REF:-}"
  echo "OBFUSCATION=$level"
  echo "TOOLCHAIN_VERSION=$ver_req"
  echo "VERSION=$cand"
  echo "INPUT_RELEASE_TAG=${INPUT_RELEASE_TAG:-}"
} >> "$GITHUB_ENV"

echo "setup ok (version $cand)"
