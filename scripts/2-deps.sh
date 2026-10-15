#!/usr/bin/env bash
set -euo pipefail

src="${1:?usage: 2-deps.sh <dir>}"
cache="${GRADLE_USER_HOME:-$HOME/.gradle}/caches/modules-2/files-2.1"
mkdir -p "$cache"

for f in "$src"/tools/*/fetch-lib.sh; do
  if [[ -f "$f" ]]; then
    # 别静默吞掉失败：这一步失败 ⇒ 后面的构建必然缺依赖。历史上这里把下载失败吃掉了，
    # 结果错误拖到很靠后的步骤才炸（看起来像那一层自己坏了），定位成本很高。
    # 这里只报脚本自身的名字（不回显任何路径/模块名），真正的兜底在源仓库那侧。
    bash "$f" >/dev/null 2>&1 || echo "::warning::$(basename "$f") returned non-zero (network?)" >&2
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
