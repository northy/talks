#!/usr/bin/env bash
# ============================================================================
# Real-projects chapter (7) - regenerate every on-slide capture.
# The wall-of-warnings runs on ../4-post-profiling (the program's final
# state). Sources are never touched; outputs land in ./build/.
# ============================================================================
set -uo pipefail

LLVM_BIN="${LLVM_BIN:-}"
[ -z "$LLVM_BIN" ] && [ -d /opt/homebrew/opt/llvm/bin ] && LLVM_BIN=/opt/homebrew/opt/llvm/bin
TIDY="${LLVM_BIN:+$LLVM_BIN/}clang-tidy"

ROOT="$(cd "$(dirname "$0")" && pwd)"
B="$ROOT/build"
rm -rf "$B" && mkdir -p "$B"

echo "### 1. The wall of warnings: --checks='*' on the final main.cpp"
cd "$ROOT/../4-post-profiling"
$TIDY main.cpp --checks='*' -- -std=c++20 > "$B/wall-full.txt" 2> "$B/wall-stderr.txt"
grep 'warnings generated' "$B/wall-stderr.txt" | head -1
echo "user-code warnings: $(grep -c 'warning:' "$B/wall-full.txt")"
grep -oE '\[[a-z0-9.-]+\]$' "$B/wall-full.txt" | sort | uniq -c | sort -rn | tee "$B/wall-itemized.txt"
echo "distinct checks: $(wc -l < "$B/wall-itemized.txt")"

echo "### 2. Suppressing with a reason (NOLINT demo)"
cd "$ROOT/legacy"
$TIDY widget_before.cpp -- -std=c++20 2>&1 | tee "$B/legacy_before.txt" | grep -E 'warning:|Suppressed'
$TIDY widget.cpp -- -std=c++20 2>&1 | tee "$B/legacy.txt" | grep -E 'warning:|Suppressed'

echo "DONE"
