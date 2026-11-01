#!/usr/bin/env bash
set -euo pipefail

src="${1:?usage: 4-build.sh <dir>}"
ver="${VERSION:?}"
IFS=. read -r v_ma v_mi v_pa <<< "$ver"
vcode=$(( v_ma * 10000 + v_mi * 100 + v_pa ))

filter_log() {
  tail -n 45 "$1" 2>/dev/null \
    | sed -E 's#[A-Za-z0-9_./-]+\.(c|h|cc|cpp|hpp|java|kt|kts|py|sh|rs|json)(:[0-9]+)+#<file:line>#g; s#[A-Za-z0-9_./-]+\.(c|h|cc|cpp|hpp|java|kt|kts|py|sh|rs|json)#<file>#g; s#^[[:space:]]*[0-9]+ \|.*$#<src>#; s#^[[:space:]]*\|.*$#<src>#; s#lib[A-Za-z0-9_]+\.so#<lib>#g; s#[A-Za-z0-9_.:+/=-]{24,}#[redacted]#g'
}

report_fail() {
  local rc="$1" file="$2" label="$3"
  echo "::error::$label stage failed (exit $rc)" >&2
  grep -E '^> Task |^FAILURE|^Execution failed|^BUILD FAILED|^\* Try|^\* Where|^\* What went wrong|^[A-Za-z_]*Error:|^error\[' "$file" 2>/dev/null \
    | tail -n 15 >&2 || true
  echo "----- details (filtered) -----" >&2
  filter_log "$file" >&2 || true
  exit "$rc"
}

app_dir="$src/app"
app_id="$(sed -n 's/^ *applicationId *= *"\([^"]*\)".*/\1/p' "$app_dir/build.gradle.kts" 2>/dev/null | head -1)"
if [[ -z "$app_id" ]]; then
  echo "::error::application id not found" >&2
  exit 1
fi
echo "::add-mask::$app_id"

mod_dir=""
mod_id=""
for d in "$src"/*/; do
  d="${d%/}"
  n="$(basename "$d")"
  [[ "$n" == "app" ]] && continue
  [[ -f "$d/build.gradle.kts" ]] || continue
  m="$(sed -n 's/^ *applicationId *= *"\([^"]*\)".*/\1/p' "$d/build.gradle.kts" 2>/dev/null | head -1)"
  if [[ -n "$m" ]]; then
    mod_dir="$d"
    mod_id="$m"
    echo "::add-mask::$m"
    break
  fi
done
if [[ -z "$mod_dir" ]]; then
  echo "::error::standalone module not found" >&2
  exit 1
fi

bump_version() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  sed -i "s/^\( *\)versionName *= *\"[^\"]*\"/\1versionName = \"$ver\"/" "$f" 2>/dev/null || true
  sed -i "s/^\( *\)versionCode *= *[0-9]*/\1versionCode = $vcode/" "$f" 2>/dev/null || true
}
bump_version "$app_dir/build.gradle.kts"
bump_version "$mod_dir/build.gradle.kts"

out="${RUNNER_TEMP:-/tmp}/artifacts"
rm -rf "$out"
mkdir -p "$out"

runner="$src/.ci/buildkit.sh"
if [[ ! -f "$runner" ]]; then
  echo "::error::private stage runner missing in the source repo" >&2
  exit 1
fi

export ARTIFACTS_DIR="$out"
export GH_TOKEN="${GH_TOKEN:-${SECRET_PAT:-}}"
export BUILDKIT_REPOSITORY="${SOURCE_REPO:?}"

stage() {
  local name="$1"
  local log="${RUNNER_TEMP:-/tmp}/stage-$name.log"
  set +e
  (
    cd "$src"
    bash "$runner" "$name"
  ) >"$log" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    report_fail "$rc" "$log" "$name"
  fi
  echo "stage $name ok"
}

for s in prepare vm ollvm fog module; do
  stage "$s"
done

take() {
  local from="$1" to="$2"
  if [[ ! -s "$out/$from" ]]; then
    echo "::error::stage output missing" >&2
    exit 1
  fi
  mv -f "$out/$from" "$out/$to"
}

take 01-vm.apk "$app_id-$ver.apk"
take 02-vm-ollvm.apk "$app_id-$ver-ollvm.apk"
take 03-vm-ollvm-fog.apk "$app_id-$ver-fog.apk"
take 04-module.apk "$mod_id-$ver.apk"

shopt -s nullglob
apks=("$out"/*.apk)
if (( ${#apks[@]} != 4 )); then
  echo "::error::expected four apk outputs, got ${#apks[@]}" >&2
  exit 1
fi
if [[ "$(sha256sum "${apks[@]}" | cut -d' ' -f1 | sort -u | wc -l)" != "4" ]]; then
  echo "::error::apk outputs are not distinct" >&2
  exit 1
fi

logdir="$(find "$src" -maxdepth 4 -type d -name 'omvll-logs' 2>/dev/null | head -1)"
if [[ -n "$logdir" ]] && [[ -n "$(ls -A "$logdir" 2>/dev/null)" ]]; then
  tar -czf "$out/omvll-logs.tar.gz" -C "$(dirname "$logdir")" "$(basename "$logdir")"
  echo "obfuscator logs: captured"
else
  echo "obfuscator logs: none"
fi

echo "build ok: 4 artifacts"
