#!/usr/bin/env bash
set -uo pipefail

dir="${RUNNER_TEMP:-/tmp}"
tag="diag-${GITHUB_RUN_ID:-manual}-${GITHUB_RUN_ATTEMPT:-1}"

shopt -s nullglob
logs=("$dir"/stage-*.log)
if (( ${#logs[@]} == 0 )); then
  echo "diagnostics: no stage log"
  exit 0
fi

names=()
for f in "${logs[@]}"; do
  names+=("$(basename "$f")")
done

if ! tar -czf "$dir/stage-logs.tar.gz" -C "$dir" "${names[@]}" 2>/dev/null; then
  echo "diagnostics: archive failed"
  exit 0
fi

if gh release create "$tag" --repo "${SOURCE_REPO:?}" --title diagnostics --notes "build diagnostics" "$dir/stage-logs.tar.gz" >/dev/null 2>&1 \
  || gh release upload "$tag" --repo "${SOURCE_REPO:?}" --clobber "$dir/stage-logs.tar.gz" >/dev/null 2>&1; then
  echo "diagnostics: $tag"
else
  echo "diagnostics: upload failed"
fi
