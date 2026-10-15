#!/usr/bin/env bash
set -euo pipefail

src="${1:?usage: 5-upload.sh <dir>}"
outdir="$src/app/build/outputs/apk/release"
apk="$(ls -t "$outdir"/*.apk 2>/dev/null | head -1 || true)"

if [[ -z "$apk" || ! -f "$apk" ]]; then
  echo "::error::apk not found" >&2
  exit 1
fi

version="$(sed -n 's/.*versionName *= *"\([^"]*\)".*/\1/p' "$src/app/build.gradle.kts" | head -1)"
version="${version:-0.0.0}"
run="${GITHUB_RUN_NUMBER:-0}"
tag="${INPUT_RELEASE_TAG:-ci-${version}-${run}}"

work="$(mktemp -d)"
asset="$work/app-${version}-${run}.apk"
cp "$apk" "$asset"
sha="$(sha256sum "$asset" | cut -d' ' -f1)"
printf '%s  %s\n' "$sha" "$(basename "$asset")" > "$asset.sha256"

{
  echo "version: $version"
  echo "size: $(stat -c%s "$asset")"
  echo "sha256: $sha"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

target=()
if [[ -n "${SOURCE_REF:-}" ]]; then
  target=(--target "$SOURCE_REF")
fi

if gh release create "$tag" --repo "$SOURCE_REPO" \
     --title "$version" --notes "automated build" \
     "${target[@]}" "$asset" "$asset.sha256" >/dev/null 2>&1; then
  echo "uploaded: $tag"
  exit 0
fi

if gh release upload "$tag" --repo "$SOURCE_REPO" --clobber "$asset" "$asset.sha256" >/dev/null 2>&1; then
  echo "uploaded: $tag"
  exit 0
fi

echo "::error::upload failed (token needs Contents read+write on the target repo)" >&2
exit 1
