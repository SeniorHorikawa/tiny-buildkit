#!/usr/bin/env bash
set -euo pipefail

VER="${TOOLCHAIN_VERSION:-1.11.0}"
DEST="${OLLVM_DIR:?}"
CACHE_REPO="${SOURCE_REPO:?}"
TAG="${TOOLCHAIN_TAG:-toolchain}"
PLUGIN_REPO="open-obfuscator/o-mvll"

PATCHER="$GITHUB_WORKSPACE/src/native/tools/omvll/patch_omvll.py"
POLICY="$GITHUB_WORKSPACE/src/native/tools/omvll/policy.py"

if [[ ! -f "$POLICY" ]]; then
  echo "::error::obfuscation policy missing in the source repo: native/tools/omvll/policy.py" >&2
  exit 1
fi

if [[ -f "$PATCHER" ]]; then
  PATCH_ID="$(sha256sum "$PATCHER" | cut -c1-12)"
  PLUGIN_MODE="patched"
else
  PATCH_ID="stock"
  PLUGIN_MODE="stock"
fi
ASSET="toolchain-${VER}-${PATCH_ID}-linux.tar.gz"

tmp="$(mktemp -d)"
mkdir -p "$(dirname "$DEST")"

if gh release download "$TAG" --repo "$CACHE_REPO" --pattern "$ASSET" --dir "$tmp" --clobber >/dev/null 2>&1; then
  mkdir -p "$DEST"
  tar -xzf "$tmp/$ASSET" -C "$DEST"
  cp "$POLICY" "$DEST/policy.py"
  echo "toolchain: cache hit"
  echo "policy: $(sha256sum "$DEST/policy.py" | cut -c1-12)"
  echo "plugin: $PLUGIN_MODE"
  exit 0
fi

work="$tmp/work"
mkdir -p "$work"

PLUGIN_URL="$(curl -fsSL "https://api.github.com/repos/$PLUGIN_REPO/releases/tags/$VER" \
  | grep -oE 'https://[^"]*linux[^"]*\.tar\.gz' | head -1)"
if [[ -z "$PLUGIN_URL" ]]; then
  echo "::error::plugin release not found: $VER" >&2
  exit 1
fi
curl -fsSL "$PLUGIN_URL" -o "$work/plugin.tar.gz"
mkdir -p "$work/plugin"
tar -xzf "$work/plugin.tar.gz" -C "$work/plugin"
PLUGIN_SO="$(find "$work/plugin" -type f -name '*.so' | head -1)"
if [[ -z "$PLUGIN_SO" ]]; then
  echo "::error::plugin archive unexpected" >&2
  find "$work/plugin" >&2 || true
  exit 1
fi

PY_LIB="$(find "$work/plugin" -maxdepth 3 -type d -name Lib | head -1)"
if [[ -z "$PY_LIB" || ! -d "$PY_LIB/encodings" ]]; then
  echo "::error::python stdlib missing in plugin archive" >&2
  find "$work/plugin" -maxdepth 3 >&2 || true
  exit 1
fi

NDK_URL=""
for v in r29d r29c r29b r29; do
  u="https://dl.google.com/android/repository/android-ndk-$v-linux.zip"
  if curl -fsI "$u" >/dev/null 2>&1; then
    NDK_URL="$u"
    break
  fi
done
if [[ -z "$NDK_URL" ]]; then
  echo "::error::no NDK package available" >&2
  exit 1
fi
curl -fsSL "$NDK_URL" -o "$work/ndk.zip"
for p in \
  "*/toolchains/llvm/prebuilt/linux-x86_64/bin/*" \
  "*/toolchains/llvm/prebuilt/linux-x86_64/lib/*" \
  "*/toolchains/llvm/prebuilt/linux-x86_64/lib64/*" \
  "*/toolchains/llvm/prebuilt/linux-x86_64/lib/cmake/*"; do
  unzip -q -o "$work/ndk.zip" "$p" -d "$work/ndk" 2>/dev/null || true
done
LLVM_ROOT="$(find "$work/ndk" -type d -path '*/toolchains/llvm/prebuilt/linux-x86_64' | head -1)"
if [[ -z "$LLVM_ROOT" || ! -d "$LLVM_ROOT/bin" || ! -d "$LLVM_ROOT/lib/clang" ]]; then
  echo "::error::NDK toolchain incomplete" >&2
  exit 1
fi

keep="$work/keep"
mkdir -p "$keep/bin" "$keep/lib"
cp -a "$LLVM_ROOT/bin/." "$keep/bin/" 2>/dev/null || true
cp -a "$LLVM_ROOT/lib/clang" "$keep/lib/" 2>/dev/null || true
if [[ -d "$LLVM_ROOT/lib64" ]]; then
  mkdir -p "$keep/lib64"
  cp -a "$LLVM_ROOT/lib64/." "$keep/lib64/" 2>/dev/null || true
fi
cp "$PLUGIN_SO" "$keep/omvll_linux.so"

if [[ "$PLUGIN_MODE" == "patched" ]]; then
  blog="$tmp/plugin.log"
  if ! OMVLL_VERSION="$VER" \
       OMVLL_WORK="$tmp/omvll-work" OMVLL_OUT="$tmp/omvll-out" \
       bash "$GITHUB_WORKSPACE/src/native/tools/omvll/build.sh" >"$blog" 2>&1; then
    echo "::error::patched plugin build failed" >&2
    tail -n 25 "$blog" >&2 || true
    exit 1
  fi
  pso="$tmp/omvll-out/omvll_linux.so"
  if [[ ! -f "$pso" ]]; then
    echo "::error::patched plugin missing after build" >&2
    exit 1
  fi
  cp "$pso" "$keep/omvll_linux.so"
  tagmark="$(tr -d '[:space:]' < "$tmp/omvll-out/plugin-tag.txt" 2>/dev/null || true)"
  if [[ -z "$tagmark" ]] || ! strings "$keep/omvll_linux.so" | grep -qF "$tagmark"; then
    echo "::error::patched plugin is missing its expected marker" >&2
    exit 1
  fi
  echo "plugin: patched (marker verified)"
  if [[ -f "$tmp/omvll-out/pass-summary.txt" ]]; then
    echo "----- obfuscator pass log (counts only) -----"
    sed 's/^/  /' "$tmp/omvll-out/pass-summary.txt"
  fi
fi

cp "$POLICY" "$keep/policy.py"
rm -rf "$PY_LIB/test"
cp -a "$PY_LIB" "$keep/pythonlib"

find "$keep/bin" -maxdepth 1 -type f ! -name 'clang*' ! -name 'lld*' ! -name 'ld.lld*' -delete 2>/dev/null || true
find "$keep/bin" -maxdepth 1 -type l ! -name 'clang*' ! -name 'lld*' ! -name 'ld.lld*' -delete 2>/dev/null || true

cat > "$work/t.c" <<'EOF'
int f(int a) {
    int s = 0;
    for (int i = 0; i < a; i++) {
        if (i % 3 == 0) s += i * 5;
        else if (i % 3 == 1) s ^= i + 7;
        else s -= i * 3 + 1;
    }
    return s;
}
EOF

CF="$(find "$keep/bin" -maxdepth 1 \( -name clang -o -name 'clang-[0-9]*' \) | head -1)"
if [[ -z "$CF" ]]; then
  echo "::error::clang missing in toolchain" >&2
  exit 1
fi
if [[ ! -f "$keep/omvll_linux.so" ]]; then
  echo "::error::plugin missing" >&2
  exit 1
fi

if ! "$CF" -c -O2 -target aarch64-linux-android -nostdlib -ffreestanding "$work/t.c" -o "$work/plain.o" 2>"$work/plain.err"; then
  echo "::error::clang unusable" >&2
  tail -n 5 "$work/plain.err" >&2 || true
  "$CF" --version 2>&1 | head -2 >&2 || true
  exit 1
fi
if ! OMVLL_CONFIG="$keep/policy.py" OMVLL_PYTHONPATH="$keep/pythonlib" "$CF" -c -O2 \
      -fpass-plugin="$keep/omvll_linux.so" \
      -target aarch64-linux-android -nostdlib -ffreestanding "$work/t.c" -o "$work/obf.o" 2>"$work/obf.err"; then
  echo "::error::plugin load failed" >&2
  tail -n 8 "$work/obf.err" >&2 || true
  (ldd --version 2>&1 | head -1) >&2 || true
  exit 1
fi

plain="$(stat -c%s "$work/plain.o")"
obf="$(stat -c%s "$work/obf.o")"
if (( obf <= plain )); then
  echo "::error::obfuscation inactive (plain=$plain obf=$obf)" >&2
  tail -n 8 "$work/obf.err" >&2 || true
  exit 1
fi

tar -czf "$tmp/$ASSET" -C "$keep" .

if ! gh release view "$TAG" --repo "$CACHE_REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$CACHE_REPO" --title "toolchain cache" --notes "cache" >/dev/null 2>&1 || true
fi
gh release upload "$TAG" --repo "$CACHE_REPO" --clobber "$tmp/$ASSET" >/dev/null 2>&1 || true

if [[ -f "$tmp/omvll-out/omvll-logs.tar.gz" ]]; then
  lg="omvll-logs-${GITHUB_RUN_ID:-manual}.tar.gz"
  if gh release upload "$TAG" --repo "$CACHE_REPO" "$tmp/omvll-out/omvll-logs.tar.gz#$lg" >/dev/null 2>&1; then
    echo "obfuscator logs: $lg"
  else
    echo "obfuscator logs: upload failed"
  fi
fi

mkdir -p "$DEST"
tar -xzf "$tmp/$ASSET" -C "$DEST"
echo "toolchain ok"
echo "policy: $(sha256sum "$DEST/policy.py" | cut -c1-12)"
echo "plugin: $PLUGIN_MODE"
