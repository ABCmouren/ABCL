#!/usr/bin/env bash
# 从源码编译设备兼容层 -> entry/src/main/resources/rawfile/amcl-launcher.jar
# 用法: JAVA_HOME=/path/to/jdk ./third_party/amcl-compat/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$HERE/lib"
OUT="$ROOT/entry/src/main/resources/rawfile/amcl-launcher.jar"

# JDK 的 javac/jar 是原生程序，路径交给 cygpath 转成 Windows 形式，
# 否则 MSYS 路径（/c/...）会被误解释。
if [ -n "${JAVA_HOME:-}" ]; then
  JAVAC="$JAVA_HOME/bin/javac"
  JAR="$JAVA_HOME/bin/jar"
else
  JAVAC="javac"
  JAR="jar"
fi
echo "javac: $JAVAC"
"$JAVAC" -version

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CLASSES="$TMP/classes"
mkdir -p "$CLASSES"

# -encoding UTF-8 必带: 源码是 UTF-8, Windows 上 javac 默认按 GBK 读会报错
find "$SRC" -name '*.java' -print0 | xargs -0 "$JAVAC" -encoding UTF-8 -nowarn -d "$CLASSES"

CNT="$(find "$CLASSES" -name '*.class' | wc -l)"
echo "compiled classes: $CNT"
if [ "$CNT" -lt 40 ]; then
  echo "ERROR: 编译产出过少(预期 49), 源码可能不完整" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# 用 -C 形式；cd + '.' 在 MSYS 下会因路径转换失败产出空 jar
"$JAR" cf "$OUT" -C "$CLASSES" .

echo "wrote: $OUT ($(stat -c %s "$OUT") bytes)"