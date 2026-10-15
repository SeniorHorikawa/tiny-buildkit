#!/usr/bin/env bash
set -euo pipefail

BRANCH="${OLLVM_BRANCH:-llvm-12.x}"
DEST="${OLLVM_DIR:?}"
SRC_URL="https://github.com/heroims/obfuscator"
GH_REPO="${GITHUB_REPOSITORY:?}"
TAG="${TOOLCHAIN_TAG:-ollvm-toolchain}"

sha="$(git ls-remote "$SRC_URL" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')"
if [[ -z "$sha" ]]; then
  echo "::error::cannot resolve branch $BRANCH" >&2
  exit 1
fi
ASSET="ollvm-${BRANCH}-${sha}.tar.zst"

tmp="$(mktemp -d)"
mkdir -p "$(dirname "$DEST")"

if gh release download "$TAG" --repo "$GH_REPO" --pattern "$ASSET" --dir "$tmp" --clobber >/dev/null 2>&1; then
  mkdir -p "$DEST"
  tar --zstd -xf "$tmp/$ASSET" -C "$DEST"
  echo "toolchain: cache hit"
  exit 0
fi

if ! (
  set -euo pipefail
  sudo apt-get update -qq
  sudo apt-get install -y -qq ninja-build zstd ccache
  mkdir -p "$tmp/src"
  curl -fsSL "https://codeload.github.com/heroims/obfuscator/tar.gz/refs/heads/$BRANCH" -o "$tmp/src.tar.gz"
  tar -xzf "$tmp/src.tar.gz" -C "$tmp/src" --strip-components=1
  cmake -S "$tmp/src/llvm" -B "$tmp/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$tmp/install" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="AArch64" \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_ZLIB=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
    -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_CCACHE_BUILD=ON
  ninja -C "$tmp/build" install
) >"$tmp/build.log" 2>&1; then
  echo "::error::toolchain build failed" >&2
  tail -n 20 "$tmp/build.log" | sed -E 's/[A-Za-z0-9_.:\/-]{64,}/[redacted]/g' >&2 || true
  exit 1
fi

if ! (
  set -euo pipefail
  keep="$tmp/keep"
  mkdir -p "$keep/bin" "$keep/lib"
  shopt -s nullglob
  for f in "$tmp/install/bin"/clang* "$tmp/install/bin"/lld*; do
    cp -a "$f" "$keep/bin/"
  done
  cp -a "$tmp/install/lib/clang" "$keep/lib/"

  if [[ -x "$tmp/install/bin/llvm-strip" ]]; then
    find "$keep/bin" -type f -exec "$tmp/install/bin/llvm-strip" --strip-all {} + 2>/dev/null || true
  fi

  cat > "$tmp/t.c" <<'EOF'
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

  try_flag() {
    local flag="$1" out
    if ! out="$("$keep/bin/clang" -c -O1 -target aarch64-linux-android -nostdlib -ffreestanding \
        -mllvm "$flag" "$tmp/t.c" -o "$tmp/t.o" 2>&1)"; then
      return 1
    fi
    if printf '%s' "$out" | grep -qiE "unknown (command line )?argument"; then
      return 1
    fi
    return 0
  }
  collect() {
    local f
    for f in "$@"; do
      if try_flag "$f"; then printf '%s\n' "-mllvm" "$f"; fi
    done
  }
  collect fla bcf bcf_prob=100 bcf_loop=3 sub sub_loop=3 sub_prob=100 split split_num=3 sobf \
    > "$keep/flags-max.txt"
  collect fla bcf bcf_prob=70 sub > "$keep/flags-balanced.txt"

  "$keep/bin/clang" -c -O1 -target aarch64-linux-android -nostdlib -ffreestanding \
      "$tmp/t.c" -o "$tmp/plain.o" 2>/dev/null
  mapfile -t maxflags < "$keep/flags-max.txt"
  "$keep/bin/clang" -c -O1 -target aarch64-linux-android -nostdlib -ffreestanding \
      "${maxflags[@]+"${maxflags[@]}"}" "$tmp/t.c" -o "$tmp/obf.o" 2>/dev/null
  plain="$(stat -c%s "$tmp/plain.o")"
  obf="$(stat -c%s "$tmp/obf.o")"
  if (( obf <= plain )); then
    echo "obfuscation inactive" >&2
    exit 1
  fi

  "$keep/bin/clang" -shared -nostdlib -ffreestanding -O2 -fPIC -fvisibility=hidden \
      -target aarch64-linux-android "${maxflags[@]+"${maxflags[@]}"}" \
      -fuse-ld=lld -B "$keep/bin" \
      -Wl,--no-undefined -Wl,-s -Wl,-z,max-page-size=16384 \
      "$tmp/t.c" -o "$tmp/smoke.so" 2>/dev/null
  file "$tmp/smoke.so" | grep -q AArch64 || exit 1

  tar --zstd -cf "$tmp/$ASSET" -C "$keep" .
); then
  echo "::error::toolchain assembly failed" >&2
  exit 1
fi

if ! gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$GH_REPO" \
    --title "toolchain cache" --notes "cache" >/dev/null 2>&1 || true
fi
gh release upload "$TAG" --repo "$GH_REPO" --clobber "$tmp/$ASSET" >/dev/null 2>&1 || true

mkdir -p "$DEST"
tar --zstd -xf "$tmp/$ASSET" -C "$DEST"
echo "toolchain ok"
