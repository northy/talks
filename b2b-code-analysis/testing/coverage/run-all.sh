#!/usr/bin/env bash
# ============================================================================
# Coverage chapter (4) - full reproducible run.
# ONE instrumented binary, several runs. Coverage is measured on
# ../2-post-runtime-analysis (the program state when chapter 4 starts); the
# fix is verified against ../3-post-coverage.
# Sources are never touched: cwd sits inside a snapshot only so llvm-cov and
# UBSan record bare filenames; all outputs land in ./build/.
# ============================================================================
set -uo pipefail   # not -e: the UBSan run returns nonzero on purpose

LLVM_BIN="${LLVM_BIN:-}"
[ -z "$LLVM_BIN" ] && [ -d /opt/homebrew/opt/llvm/bin ] && LLVM_BIN=/opt/homebrew/opt/llvm/bin
CXX="${LLVM_BIN:+$LLVM_BIN/}clang++"
PROFDATA="${LLVM_BIN:+$LLVM_BIN/}llvm-profdata"
COV="${LLVM_BIN:+$LLVM_BIN/}llvm-cov"
STD=-std=c++20
COVFLAGS="-fprofile-instr-generate -fcoverage-mapping"

ROOT="$(cd "$(dirname "$0")" && pwd)"
B="$ROOT/build"
IN="$(cd "$ROOT/../inputs" && pwd)"
rm -rf "$B" && mkdir -p "$B"
cd "$ROOT/../2-post-runtime-analysis"    # <-- clean recorded filenames

echo "### 1. Build ONE coverage-instrumented binary"
set -x
$CXX $STD $COVFLAGS stats.cpp main.cpp -o "$B/humidity-stats"
set +x

echo "### 2. Run it every way we normally do; each run dumps its own .profraw"
LLVM_PROFILE_FILE="$B/readings.profraw" "$B/humidity-stats" "$IN/readings.txt"; echo "readings exit: $?"
LLVM_PROFILE_FILE="$B/boundary.profraw" "$B/humidity-stats" "$IN/boundary.txt"; echo "boundary exit: $?"
LLVM_PROFILE_FILE="$B/corrupt.profraw"  "$B/humidity-stats" "$IN/corrupt.txt";  echo "corrupt exit: $?"
LLVM_PROFILE_FILE="$B/usage.profraw"    "$B/humidity-stats";                    echo "usage exit: $? (usage error, expected 1)"

echo "### 3. Merge raw profiles -> one indexed profile"
$PROFDATA merge -sparse "$B/readings.profraw" "$B/boundary.profraw" "$B/corrupt.profraw" "$B/usage.profraw" -o "$B/merged.profdata"

echo "### 4. Summary report (per file)"
$COV report "$B/humidity-stats" -instr-profile "$B/merged.profdata" | tee "$B/report.txt"

echo "### 5. show main.cpp (execution counts)"
$COV show "$B/humidity-stats" -instr-profile "$B/merged.profdata" main.cpp | tee "$B/show-main.txt"

echo "### 6. show main.cpp (branch counts)"
$COV show "$B/humidity-stats" -instr-profile "$B/merged.profdata" --show-branches=count main.cpp | tee "$B/show-main-branches.txt"

echo "### 7. show stats.cpp (execution counts)"
$COV show "$B/humidity-stats" -instr-profile "$B/merged.profdata" stats.cpp | tee "$B/show-stats.txt"

echo
echo "### 8. COMPOSITION: coverage build that ALSO carries UBSan"
# -fprofile-continuous + %c: on x86-64 the empty run dies on SIGFPE right
# after the UBSan report (arm64 keeps running), so counters must be flushed
# continuously or the run records nothing.
set -x
$CXX $STD -fsanitize=undefined $COVFLAGS -fprofile-continuous stats.cpp main.cpp -o "$B/ss-ubsan-cov"
set +x

echo "### 9. Run the NEW empty-input case (UBSan live, coverage recording)"
LLVM_PROFILE_FILE="$B/empty%c.profraw" "$B/ss-ubsan-cov" "$IN/empty.txt" 2>&1 | tee "$B/ubsan-empty.txt"; echo "exit: ${PIPESTATUS[0]}"

echo "### 10. Merge all five runs and re-show main.cpp branches (silence closed)"
$PROFDATA merge -sparse "$B/readings.profraw" "$B/boundary.profraw" "$B/corrupt.profraw" "$B/usage.profraw" "$B"/empty*.profraw -o "$B/merged-after.profdata"
$COV show "$B/humidity-stats" -instr-profile "$B/merged-after.profdata" --show-branches=count main.cpp | tee "$B/show-main-after.txt"

echo "### 11. FIX verification: 3-post-coverage (adds the missing return)"
cd "$ROOT/../3-post-coverage"
$CXX $STD -fsanitize=undefined $COVFLAGS stats.cpp main.cpp -o "$B/ss-fixed"
LLVM_PROFILE_FILE="$B/fixed.profraw" "$B/ss-fixed" "$IN/empty.txt" 2>&1 | tee "$B/fixed-empty.txt"; echo "exit: ${PIPESTATUS[0]}"

echo "DONE"
