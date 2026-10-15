#!/usr/bin/env bash
set -euo pipefail

src="${1:?usage: 2-deps.sh <dir>}"
cache="${GRADLE_USER_HOME:-$HOME/.gradle}/caches/modules-2/files-2.1"
mkdir -p "$cache"

for f in "$src"/tools/*/fetch-lib.sh; do
  if [[ -f "$f" ]]; then
    bash "$f" >/dev/null 2>&1 || true
  fi
done

need() {
  local g="$1" a="$2" v="$3"
  local dir="$cache/$1/$2/$3" gpath url tmp sum
  if [[ -d "$dir" ]] && find "$dir" -name '*.jar' -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  gpath="$(printf '%s' "$g" | tr '.' '/')"
  url="https://repo1.maven.org/maven2/$gpath/$a/$v/$a-$v.jar"
  tmp="$(mktemp)"
  if ! curl -fsSL "$url" -o "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  sum="$(sha1sum "$tmp" | cut -d' ' -f1)"
  mkdir -p "$dir/$sum"
  mv "$tmp" "$dir/$sum/$a-$v.jar"
}

need org.jetbrains.kotlin kotlin-stdlib 2.2.10
need org.jetbrains.kotlin kotlin-compiler-embeddable 2.2.10
need org.jetbrains.kotlin kotlin-script-runtime 2.2.10
need org.jetbrains.kotlin kotlin-daemon-embeddable 2.2.10
need org.jetbrains.kotlin kotlin-reflect 2.2.10
need org.jetbrains.kotlinx kotlinx-coroutines-core-jvm 1.8.1
need org.jetbrains annotations 13.0

echo "deps ok"
