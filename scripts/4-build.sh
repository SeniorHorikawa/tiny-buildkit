#!/usr/bin/env bash
set -euo pipefail

src="${1:?usage: 4-build.sh <dir>}"
ver="${VERSION:?}"
IFS=. read -r v_ma v_mi v_pa <<< "$ver"
vcode=$(( v_ma * 10000 + v_mi * 100 + v_pa ))

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

app_dir="$src/app"
app_id="$(sed -n 's/^ *applicationId *= *"\([^"]*\)".*/\1/p' "$app_dir/build.gradle.kts" 2>/dev/null | head -1)"
app_id="${app_id:-app}"
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

bump_version() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  sed -i "s/^\( *\)versionName *= *\"[^\"]*\"/\1versionName = \"$ver\"/" "$f" 2>/dev/null || true
  sed -i "s/^\( *\)versionCode *= *[0-9]*/\1versionCode = $vcode/" "$f" 2>/dev/null || true
}
bump_version "$app_dir/build.gradle.kts"
if [[ -n "$mod_dir" ]]; then
  bump_version "$mod_dir/build.gradle.kts"
fi

out="${RUNNER_TEMP:-/tmp}/artifacts"
rm -rf "$out"
mkdir -p "$out"

run_gradle() {
  local tag="$1"
  shift
  local log="${RUNNER_TEMP:-/tmp}/$tag.log"
  set +e
  (
    cd "$src"
    chmod +x ./gradlew 2>/dev/null || true
    bash ./gradlew "$@" --console=plain
  ) >"$log" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    report_fail "$rc" "$log"
  fi
}

newest_apk() { ls -t "$1"/*.apk 2>/dev/null | head -1; }

jni="$app_dir/src/main/jniLibs/arm64-v8a"
nat_off="$out/.native-off"
nat_on="$out/.native-on"
mkdir -p "$nat_off" "$nat_on"

native_build() {
  local lvl="$1"
  local log="${RUNNER_TEMP:-/tmp}/native-$lvl.log"
  set +e
  (
    cd "$src"
    OBFUSCATION="$lvl" ZIG="$wbin/cc" bash native/build.sh
  ) >"$log" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "----- native ($lvl) failed -----" >&2
    filter_log "$log" >&2 || true
    exit "$rc"
  fi
}

native_build off
cp -a "$jni/." "$nat_off/"
native_build on
cp -a "$jni/." "$nat_on/"

rel="$app_dir/build/outputs/apk/release"

HOOK_SKIP_ARGS=""
HOOK_FINAL_TASK=""
HOOK_FINAL_ARGS=""
HOOK_SUFFIX=""
hooks="$src/native/tools/build-hooks.sh"
if [[ -f "$hooks" ]]; then
  . "$hooks"
fi

cp -a "$nat_off/." "$jni/"
run_gradle v1 :app:assembleRelease ${HOOK_SKIP_ARGS} -x nativeBuild
cp "$(newest_apk "$rel")" "$out/${app_id}-${ver}.apk"

cp -a "$nat_on/." "$jni/"
run_gradle v2 :app:assembleRelease ${HOOK_SKIP_ARGS} -x nativeBuild
cp "$(newest_apk "$rel")" "$out/${app_id}-${ver}-ollvm.apk"

run_gradle v3 :app:assembleRelease ${HOOK_SKIP_ARGS} -x nativeBuild
apk3="$(newest_apk "$rel")"
props="$src/keystore.properties"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
signer="$(ls -1d "$sdk"/build-tools/* 2>/dev/null | sort -V | tail -1)/apksigner"
store="$(sed -n 's/^storeFile=//p' "$props" 2>/dev/null | tr -d '\r')"
spass="$(sed -n 's/^storePassword=//p' "$props" 2>/dev/null | tr -d '\r')"
kalias="$(sed -n 's/^keyAlias=//p' "$props" 2>/dev/null | tr -d '\r')"
kpass="$(sed -n 's/^keyPassword=//p' "$props" 2>/dev/null | tr -d '\r')"
if [[ -x "$signer" && -n "$store" && -n "$spass" ]]; then
  if ! "$signer" sign --ks "$src/$store" --ks-key-alias "$kalias" \
        --ks-pass "pass:$spass" --key-pass "pass:$kpass" \
        --v2-signing-enabled true --v3-signing-enabled true \
        --out "$apk3.resigned" "$apk3" >/dev/null 2>&1; then
    echo "::error::resign failed" >&2
    exit 1
  fi
  mv "$apk3.resigned" "$apk3"
else
  echo "::error::apksigner or keystore unavailable" >&2
  exit 1
fi
if [[ -n "$HOOK_FINAL_TASK" ]]; then
  run_gradle v3f "$HOOK_FINAL_TASK" ${HOOK_FINAL_ARGS}
  cp "$(newest_apk "$rel")" "$out/${app_id}-${ver}-ollvm${HOOK_SUFFIX}.apk"
else
  echo "final build step: not provided by the source repo"
fi

if [[ -n "$mod_dir" ]]; then
  run_gradle v4 ":$(basename "$mod_dir"):assembleRelease"
  mapk="$(newest_apk "$mod_dir/build/outputs/apk/release")"
  if [[ -n "$mapk" ]]; then
    cp "$mapk" "$out/${mod_id}-${ver}.apk"
  fi
fi

# Obligatory obfuscator logs.
# o-mvll 只有在**作为编译器 pass 真正跑过**之后才会写 omvll-logs/ —— 也就是这里
# （编译 App 的 native 源码时），而不是编译插件的时候。所以捕获点必须在 4-build.sh。
# 公开日志只回显一行中性状态：日志里含函数名与源文件名，细节只进私库归档（见 5-upload.sh）。
logdir="$(find "$src" -maxdepth 5 -type d -name 'omvll-logs' 2>/dev/null | head -1)"
if [[ -n "$logdir" ]] && [[ -n "$(ls -A "$logdir" 2>/dev/null)" ]]; then
  tar -czf "$out/omvll-logs.tar.gz" -C "$(dirname "$logdir")" "$(basename "$logdir")"
  echo "obfuscator logs: captured ($(wc -c <"$out/omvll-logs.tar.gz") bytes)"
else
  echo "obfuscator logs: none"
fi

rm -rf "$nat_off" "$nat_on"
ls -l "$out"
echo "build ok"
