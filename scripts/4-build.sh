#!/usr/bin/env bash
set -euo pipefail

src="${1:?usage: 4-build.sh <dir>}"
clang_bin="$(find "$OLLVM_DIR/bin" -maxdepth 1 \( -name clang -o -name 'clang-[0-9]*' \) | head -1)"
if [[ -z "$clang_bin" ]]; then
  echo "::error::toolchain not ready" >&2
  exit 1
fi

chmod +x "$GITHUB_WORKSPACE/scripts/bin/cc" 2>/dev/null || true
wbin="${RUNNER_TEMP:-/tmp}/wbin"
mkdir -p "$wbin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$GITHUB_WORKSPACE/scripts/bin/cc" > "$wbin/cc"
chmod 755 "$wbin/cc"
export PATH="$wbin:$OLLVM_DIR/bin:$PATH"
export ZIG="$wbin/cc"

host_cc="$(command -v gcc || command -v cc || true)"
if [[ -n "$host_cc" ]]; then
  export CC="$host_cc"
fi

filter_log() {
  tail -n 45 "$1" 2>/dev/null \
    | sed -E 's#[A-Za-z0-9_./-]+\.(c|h|cc|cpp|hpp|java|kt|kts|py|sh)(:[0-9]+)+#<file:line>#g; s#[A-Za-z0-9_./-]+\.(c|h|cc|cpp|hpp|java|kt|kts|py|sh)#<file>#g; s#^[[:space:]]*[0-9]+ \|.*$#<src>#; s#^[[:space:]]*\|.*$#<src>#; s#lib[A-Za-z0-9_]+\.so#<lib>#g; s#[A-Za-z0-9_.:+/=-]{24,}#[redacted]#g'
}

report_fail() {
  local rc="$1" file="$2"
  echo "::error::build failed (exit $rc)" >&2
  grep -E '^> Task |^FAILURE|^Execution failed|^BUILD FAILED|^\* Try|^\* Where|^\* What went wrong' "$file" 2>/dev/null \
    | tail -n 20 >&2 || true
  echo "----- details (filtered) -----" >&2
  filter_log "$file" >&2 || true
  exit "$rc"
}

build_log="${RUNNER_TEMP:-/tmp}/build.log"
set +e
(
  cd "$src"
  chmod +x ./gradlew 2>/dev/null || true
  bash ./gradlew nativeBuild :app:assembleRelease -PskipFog --console=plain
) >"$build_log" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  report_fail "$rc" "$build_log"
fi

apk="$src/app/build/outputs/apk/release/app-release.apk"
props="$src/keystore.properties"
if [[ ! -f "$apk" || ! -f "$props" ]]; then
  echo "::error::apk or keystore properties missing" >&2
  exit 1
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
tools="$(ls -1d "$sdk"/build-tools/* 2>/dev/null | sort -V | tail -1)"
signer="$tools/apksigner"
store="$(sed -n 's/^storeFile=//p' "$props" | tr -d '\r')"
spass="$(sed -n 's/^storePassword=//p' "$props" | tr -d '\r')"
kalias="$(sed -n 's/^keyAlias=//p' "$props" | tr -d '\r')"
kpass="$(sed -n 's/^keyPassword=//p' "$props" | tr -d '\r')"

if [[ -x "$signer" && -n "$store" && -n "$spass" ]]; then
  if ! "$signer" sign --ks "$src/$store" --ks-key-alias "$kalias" \
        --ks-pass "pass:$spass" --key-pass "pass:$kpass" \
        --v2-signing-enabled true --v3-signing-enabled true \
        --out "$apk.resigned" "$apk" >/dev/null 2>&1; then
    echo "::error::resign failed" >&2
    exit 1
  fi
  mv "$apk.resigned" "$apk"
else
  echo "::error::apksigner or keystore unavailable" >&2
  exit 1
fi

fog_log="${RUNNER_TEMP:-/tmp}/fog.log"
set +e
(
  cd "$src"
  bash ./gradlew :app:fogRelease -Pbash=/bin/bash --console=plain
) >"$fog_log" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  report_fail "$rc" "$fog_log"
fi

echo "build ok"
