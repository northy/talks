#!/usr/bin/env bash
# ============================================================================
# Runtime-analysis chapter (3) - regenerate every on-slide capture.
#
# The chapter tells a FORWARD story: each diagnostic runs on the program state
# the previous fix produced, never on an earlier one.
#
#   ../1-post-static-analysis   lldb crash on corrupt.txt        -> range filter
#   steps/1-after-debugger      ASan on boundary.txt             -> min(r/10, 9)
#   steps/2-after-asan          UBSan on corrupt.txt             -> std::int64_t sum
#   steps/3-after-ubsan         LSan on readings.txt             -> return by value
#   ../2-post-runtime-analysis  re-verification: everything clean, empty.txt still UB
#
# parallel/ (TSan) is a side branch of the chapter-start state; the hardening
# demo is the "had this shipped" counterfactual on the chapter-start state. Both the
# hardening demo and contracts/ are SHOWN in chapter 5 (Checks in Production), after
# coverage; their captures stay here because this script produces them.
# Sources are never touched: cwd sits inside a state only so tools record
# bare filenames; all outputs land in ./build/.
# ============================================================================
set -uo pipefail   # not -e: sanitizer runs return nonzero on purpose

LLVM_BIN="${LLVM_BIN:-}"
[ -z "$LLVM_BIN" ] && [ -d /opt/homebrew/opt/llvm/bin ] && LLVM_BIN=/opt/homebrew/opt/llvm/bin
CXX="${LLVM_BIN:+$LLVM_BIN/}clang++"
STD=-std=c++20
# GCC>=16 libstdc++ enables assertions at -O0 by default; they would catch the
# OOB before ASan does. No-op with libc++ (macOS).
NOASSERT=-D_GLIBCXX_NO_ASSERTIONS

ROOT="$(cd "$(dirname "$0")" && pwd)"
B="$ROOT/build"
IN="$(cd "$ROOT/../inputs" && pwd)"
rm -rf "$B" && mkdir -p "$B"

run() { name=$1; shift; "$@" > "$B/$name.out" 2> "$B/$name.txt"; echo "[$name] exit $?"; }
# plain -O2 run of a state on an input: stdout+exit in one capture
plain() { name=$1; dir=$2; input=$3; (cd "$dir" && $CXX $STD -O2 $NOASSERT stats.cpp main.cpp -o "$B/$name-bin") \
    && { "$B/$name-bin" "$IN/$input" > "$B/$name.out" 2>&1; echo "exit $?" >> "$B/$name.out"; echo "[$name] $(tr '\n' ' ' < "$B/$name.out")"; }; }

echo "### State A (1-post-static-analysis): lldb, plain debug build crash on corrupt.txt"
cd "$ROOT/../1-post-static-analysis"
$CXX $STD -g -O0 $NOASSERT stats.cpp main.cpp -o "$B/ss-debug"
if command -v lldb > /dev/null; then
    (cd "$IN" && lldb -b -o run -k 'bt 2' -k 'frame variable r' -k 'frame variable buckets' -k quit -- "$B/ss-debug" corrupt.txt) \
        > "$B/lldb_corrupt.txt" 2>&1; echo "[lldb_corrupt] done"
else
    echo "[lldb_corrupt] SKIPPED: lldb not on PATH (capture unchanged: state A is untouched)"
fi
plain stateA_corrupt "$ROOT/../1-post-static-analysis" corrupt.txt
plain stateA_boundary "$ROOT/../1-post-static-analysis" boundary.txt
echo "### State A: UBSan cascade on corrupt.txt (appendix 'one input, two bugs': overflow, then the wild histogram access)"
$CXX $STD -g $NOASSERT -fsanitize=undefined stats.cpp main.cpp -o "$B/ss-ubsan-stateA"
run ubsan_corrupt_stateA "$B/ss-ubsan-stateA" "$IN/corrupt.txt"

echo "### Fix the range filter -> State B (steps/1-after-debugger): corrupt.txt no longer crashes; ASan on boundary.txt"
plain stateB_corrupt "$ROOT/steps/1-after-debugger" corrupt.txt
plain stateB_boundary "$ROOT/steps/1-after-debugger" boundary.txt
cd "$ROOT/steps/1-after-debugger"
$CXX $STD -g -O0 $NOASSERT -fsanitize=address stats.cpp main.cpp -o "$B/ss-asan"
run asan_boundary env ASAN_OPTIONS=detect_leaks=0 "$B/ss-asan" "$IN/boundary.txt"
echo "### ASan at -O1 (appendix: inlining in reports)"
$CXX $STD -g -O1 $NOASSERT -fsanitize=address stats.cpp main.cpp -o "$B/ss-asan-O1"
run asan_boundary_O1 env ASAN_OPTIONS=detect_leaks=0 "$B/ss-asan-O1" "$IN/boundary.txt"

echo "### Fix the top bucket -> State C (steps/2-after-asan): ASan clean; UBSan on corrupt.txt (overflow) and empty.txt (division by zero)"
cd "$ROOT/steps/2-after-asan"
$CXX $STD -g -O0 $NOASSERT -fsanitize=address stats.cpp main.cpp -o "$B/ssC-asan"
ASAN_OPTIONS=detect_leaks=0 "$B/ssC-asan" "$IN/boundary.txt" > "$B/stateC_asan_boundary.out" 2>&1 && echo "[stateC asan boundary] clean: $(tr '\n' ' ' < "$B/stateC_asan_boundary.out")" || echo "[stateC asan boundary] FIRED (unexpected)"
plain stateC_corrupt "$ROOT/steps/2-after-asan" corrupt.txt
$CXX $STD -g $NOASSERT -fsanitize=undefined stats.cpp main.cpp -o "$B/ss-ubsan"
run ubsan_corrupt "$B/ss-ubsan" "$IN/corrupt.txt"
run ubsan_empty   "$B/ss-ubsan" "$IN/empty.txt"

echo "### Fix the overflow -> State D (steps/3-after-ubsan): UBSan clean on corrupt; LSan on readings.txt (the leak)"
cd "$ROOT/steps/3-after-ubsan"
$CXX $STD -g $NOASSERT -fsanitize=undefined stats.cpp main.cpp -o "$B/ssD-ubsan"
"$B/ssD-ubsan" "$IN/corrupt.txt" > "$B/stateD_ubsan_corrupt.out" 2> "$B/stateD_ubsan_corrupt.txt"
[ -s "$B/stateD_ubsan_corrupt.txt" ] && echo "[stateD ubsan corrupt] FIRED (unexpected)" || echo "[stateD ubsan corrupt] clean: $(tr '\n' ' ' < "$B/stateD_ubsan_corrupt.out")"
if [ "$(uname)" = Darwin ]; then
    echo "[lsan_run] SKIPPED: LSan is rejected on Apple Silicon; capture on Linux (or Docker)"
else
    $CXX $STD -g -O0 -fsanitize=leak stats.cpp main.cpp -o "$B/ss-lsan"
    run lsan_run "$B/ss-lsan" "$IN/readings.txt"
fi

echo "### Hardened stdlib on boundary.txt, chapter-start state (libc++ only): 'had this shipped'"
cd "$ROOT/../1-post-static-analysis"
if $CXX $STD -O2 -stdlib=libc++ -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG \
        stats.cpp main.cpp -o "$B/ss-hard" 2> "$B/hardened_build.txt"; then
    run hard_DEBUG_boundary "$B/ss-hard" "$IN/boundary.txt"
    $CXX $STD -O2 -stdlib=libc++ -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST stats.cpp main.cpp -o "$B/ss-hard-fast"
    run hard_FAST_boundary "$B/ss-hard-fast" "$IN/boundary.txt"
else
    echo "[hard_DEBUG_boundary] SKIPPED: libc++ not available"
fi

echo "### TSan: the parallel variant's data race"
cd "$ROOT/parallel"
$CXX $STD -g -O0 -fsanitize=thread stats.cpp main.cpp -o "$B/ss-tsan"
for i in 1 2 3 4 5 6 7 8; do
    "$B/ss-tsan" "$IN/readings.txt" > /dev/null 2> "$B/tsan_race_O0.txt"
    grep -q 'data race' "$B/tsan_race_O0.txt" && break
done
grep -q 'data race' "$B/tsan_race_O0.txt" && echo "[tsan_race_O0] race caught" || echo "[tsan_race_O0] NO RACE in 8 runs"
$CXX $STD -g -O0 -fsanitize=thread stats_fixed.cpp main.cpp -o "$B/ss-tsan-fixed"
ok=1; for i in 1 2 3 4 5; do "$B/ss-tsan-fixed" "$IN/readings.txt" > /dev/null 2>> "$B/tsan_fixed.txt" || ok=0; done
[ $ok = 1 ] && echo "[tsan_fixed] clean" || echo "[tsan_fixed] FIRED (unexpected)"

echo "### Fix the leak -> State E (2-post-runtime-analysis): everything clean, the division by zero deliberately alive"
cd "$ROOT/../2-post-runtime-analysis"
$CXX $STD -g -O0 $NOASSERT -fsanitize=address stats.cpp main.cpp -o "$B/ss2-asan"
ASAN_OPTIONS=detect_leaks=0 "$B/ss2-asan" "$IN/boundary.txt" > /dev/null 2>&1 && echo "[iter2 asan boundary] clean" || echo "[iter2 asan boundary] FIRED (unexpected)"
$CXX $STD -g $NOASSERT -fsanitize=undefined stats.cpp main.cpp -o "$B/ss2-ubsan"
"$B/ss2-ubsan" "$IN/corrupt.txt" > /dev/null 2> "$B/iter2_ubsan_corrupt.txt"
[ -s "$B/iter2_ubsan_corrupt.txt" ] && echo "[iter2 ubsan corrupt] FIRED (unexpected)" || echo "[iter2 ubsan corrupt] clean"
"$B/ss2-ubsan" "$IN/empty.txt" > /dev/null 2> "$B/iter2_ubsan_empty.txt"
grep -q 'division by zero' "$B/iter2_ubsan_empty.txt" && echo "[iter2 ubsan empty] still fires (expected: chapter 4's setup)" || echo "[iter2 ubsan empty] SILENT (unexpected)"
if [ "$(uname)" != Darwin ]; then
    $CXX $STD -g -O0 -fsanitize=leak stats.cpp main.cpp -o "$B/ss2-lsan"
    "$B/ss2-lsan" "$IN/readings.txt" > "$B/iter2_lsan.out" 2>&1 && echo "[iter2 lsan] clean" || echo "[iter2 lsan] FIRED (unexpected)"
fi
for f in readings boundary corrupt; do plain stateE_$f "$ROOT/../2-post-runtime-analysis" $f.txt; done
# "The hardening fix" slide: the fixed program under the production dial
if $CXX $STD -O2 -stdlib=libc++ -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST \
        stats.cpp main.cpp -o "$B/ss2-hard" 2>> "$B/hardened_build.txt"; then
    "$B/ss2-hard" "$IN/boundary.txt" > "$B/iter2_hard_boundary.out" 2>&1 && echo "[iter2 hardened boundary] clean: $(tr '\n' ' ' < "$B/iter2_hard_boundary.out")" || echo "[iter2 hardened boundary] TRAPPED (unexpected)"
else
    echo "[iter2 hardened boundary] SKIPPED: libc++ not available"
fi

echo "DONE - captures in $B"
