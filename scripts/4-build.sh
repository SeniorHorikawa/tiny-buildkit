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

log="${RUNNER_TEMP:-/tmp}/build.log"
set +e
(
  cd "$src"
  chmod +x ./gradlew 2>/dev/null || true
  bash ./gradlew nativeBuild :app:assembleRelease -x nativeVerify -Pbash=/bin/bash --console=plain
) >"$log" 2>&1
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "::error::build failed (exit $rc)" >&2
  grep -E '^> Task |^FAILURE|^Execution failed|^BUILD FAILED|^\* Try|^\* Where|^\* What went wrong' "$log" 2>/dev/null \
    | tail -n 25 \
    | sed -E 's/[A-Za-z0-9_.:\/+=-]{48,}/[redacted]/g' >&2 || true
  exit "$rc"
fi

echo "build ok"
