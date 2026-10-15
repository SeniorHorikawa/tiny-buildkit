#!/usr/bin/env bash
set -euo pipefail

out="${RUNNER_TEMP:-/tmp}/artifacts"
ver="${VERSION:?}"
tag="${INPUT_RELEASE_TAG:-v${ver}}"

shopt -s nullglob
apks=("$out"/*.apk)
if (( ${#apks[@]} == 0 )); then
  echo "::error::no apk produced" >&2
  exit 1
fi

cd "$out"
sha256sum ./*.apk > SHA256SUMS.txt

extra=()
if [[ -f "$out/omvll-logs.tar.gz" ]]; then
  cp "$out/omvll-logs.tar.gz" "$out/obfuscator-logs-${ver}.tar.gz"
  extra=("obfuscator-logs-${ver}.tar.gz")
fi

{
  echo "- artifacts: ${#apks[@]}"
  echo "- total size: $(du -ch ./*.apk | tail -1 | cut -f1)"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

if gh release view "$tag" --repo "$SOURCE_REPO" >/dev/null 2>&1; then
  if gh release upload "$tag" --repo "$SOURCE_REPO" --clobber ./*.apk SHA256SUMS.txt ${extra[@]+"${extra[@]}"} >/dev/null 2>&1; then
    echo "uploaded: $tag"
    [[ ${#extra[@]} -gt 0 ]] && echo "logs: ${extra[0]}"
    exit 0
  fi
else
  if gh release create "$tag" --repo "$SOURCE_REPO" --title "$tag" --notes "automated build" \
       ./*.apk SHA256SUMS.txt ${extra[@]+"${extra[@]}"} >/dev/null 2>&1; then
    echo "uploaded: $tag"
    [[ ${#extra[@]} -gt 0 ]] && echo "logs: ${extra[0]}"
    exit 0
  fi
fi

if gh release upload "$tag" --repo "$SOURCE_REPO" --clobber ./*.apk SHA256SUMS.txt ${extra[@]+"${extra[@]}"} >/dev/null 2>&1; then
  echo "uploaded: $tag"
  [[ ${#extra[@]} -gt 0 ]] && echo "logs: ${extra[0]}"
  exit 0
fi

echo "::error::upload failed (token needs Contents read+write on the target repo)" >&2
exit 1
