#!/usr/bin/env bash
# ============================================================================
# Profiling chapter (6) - reproducible measurements.
# slow = ../3-post-coverage (correct on every input, the quadratic countDistinct still planted)
# fast = ../4-post-profiling (countDistinct fixed)
# Sources are never touched; everything lands in ./build/.
# perf/heaptrack captures are host-specific, see the slide comments in
# presentation/pages/6-profiling.md and 10-appendix.md; this script
# verifies the substance: identical output, countDistinct dominance, speedup.
# ============================================================================
set -euo pipefail

LLVM_BIN="${LLVM_BIN:-}"
[ -z "$LLVM_BIN" ] && [ -d /opt/homebrew/opt/llvm/bin ] && LLVM_BIN=/opt/homebrew/opt/llvm/bin
CXX="${CXX:-${LLVM_BIN:+$LLVM_BIN/}clang++}"   # CXX=g++ inside the perf container
STD=-std=c++20

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Linux captures (perf/heaptrack) land in build/linux100 -- the paths the slides cite.
# macOS-only cross-checks keep a _macos suffix in build/ so the two hosts never overwrite
# each other. Only our own output dir is cleaned; sibling captures survive.
B="$ROOT/build/${CAPTURE_DIR:-linux100}"
rm -rf "$B" && mkdir -p "$B"

# The slides show `./ss-slow-linux big.txt` for the container capture; match that name there.
SUF=""; [ "$(uname)" = "Linux" ] && SUF="-linux"

echo "### 1. Generate the big input (deterministic, 20M readings, 0..100)"
$CXX $STD -O2 "$ROOT/gen.cpp" -o "$B/gen"
"$B/gen" 20000000 "$B/big.txt"

echo "### 2. Build slow (3-post-coverage) and fast (4-post-profiling), -O2 -g"
(cd "$ROOT/../3-post-coverage"  && $CXX $STD -O2 -g stats.cpp main.cpp -o "$B/ss-slow$SUF")
(cd "$ROOT/../4-post-profiling" && $CXX $STD -O2 -g stats.cpp main.cpp -o "$B/ss-fast$SUF")

echo "### 3. Outputs must be identical"
"$B/ss-slow$SUF" "$B/big.txt" > "$B/out-slow.txt"
"$B/ss-fast$SUF" "$B/big.txt" > "$B/out-fast.txt"
cmp "$B/out-slow.txt" "$B/out-fast.txt" && echo "outputs identical"
head -2 "$B/out-slow.txt"

echo "### 4. Wall time, 3 runs each"
for v in slow fast; do
    for i in 1 2 3; do
        { /usr/bin/time -p "$B/ss-$v$SUF" "$B/big.txt" > /dev/null; } 2>> "$B/time_$v.txt"
    done
    echo "-- $v:"; grep real "$B/time_$v.txt"
done

echo "### 5. Phase breakdown (steady_clock harness, diag.cpp)"
(cd "$ROOT/../3-post-coverage"  && $CXX $STD -O2 -I. "$ROOT/diag.cpp" stats.cpp -o "$B/diag-slow")
(cd "$ROOT/../4-post-profiling" && $CXX $STD -O2 -I. "$ROOT/diag.cpp" stats.cpp -o "$B/diag-fast")
echo "-- slow:"; "$B/diag-slow" "$B/big.txt" | tee "$B/diag_slow.txt"
echo "-- fast:"; "$B/diag-fast" "$B/big.txt" | tee "$B/diag_fast.txt"

echo "### 5b. countDistinct alternatives (sort+unique vs ranges vs unordered_set)"
$CXX $STD -O2 "$ROOT/alts.cpp" -o "$B/alts"
for i in 1 2; do "$B/alts" "$B/big.txt"; done | tee "$B/alts.txt"

echo "### 6. perf (only where available)"
PERF="$(ls /usr/lib/linux-tools/*/perf 2>/dev/null | head -1 || true)"
[ -z "$PERF" ] && PERF="$(command -v perf || true)"
if [ -n "$PERF" ]; then
    echo "using $PERF"
    # Sampling in a container needs the paranoid level dropped (run with --privileged).
    sysctl -w kernel.perf_event_paranoid=-1 > /dev/null 2>&1 || true
    "$PERF" record -F 999 -e cpu-clock --call-graph dwarf -o "$B/perf.data" "$B/ss-slow$SUF" "$B/big.txt" > /dev/null 2> "$B/perf_record.log" || true
    "$PERF" report --no-children -i "$B/perf.data" --stdio 2>/dev/null \
        | grep -E '^[[:space:]]+[0-9]+\.[0-9]+%' | head -14 > "$B/perf_report_selftime.txt" || true
    if [ ! -s "$B/perf_report_selftime.txt" ]; then
        echo "!! perf report empty -- check $B/perf_record.log (needs --privileged)"
    else
        cat "$B/perf_report_selftime.txt"
    fi
else
    echo "perf not available, skipped."
    echo "    Linux capture on an Apple host, from this directory:"
    echo "      docker build -f Dockerfile.perf -t ss-perf ."
    echo "      docker run --rm --privileged -v \"$PWD/..\":/work ss-perf \\"
    echo "        bash -c 'cd /work/profiling && CAPTURE_DIR=linux100 ./run-all.sh'"
    echo "    perf needs --privileged (the script sets perf_event_paranoid=-1)."
fi

echo "### 6b. heaptrack + peak RSS (memory slides)"
if command -v heaptrack > /dev/null; then
    for v in slow fast; do
        heaptrack -o "$B/ht_$v" "$B/ss-$v$SUF" "$B/big.txt" > "$B/ht_${v}_run.log" 2>&1 || true
        HT="$(ls "$B/ht_$v".gz "$B/ht_$v".zst 2>/dev/null | head -1 || true)"
        [ -n "$HT" ] && heaptrack_print "$HT" 2>/dev/null | tail -30 > "$B/ht_${v}_summary.txt" || true
        /usr/bin/time -v "$B/ss-$v$SUF" "$B/big.txt" > /dev/null 2> "$B/rss_$v.txt" || true
        echo "-- $v: $(grep -i 'peak heap memory' "$B/ht_${v}_summary.txt" 2>/dev/null || true)  $(grep 'Maximum resident' "$B/rss_$v.txt" 2>/dev/null || true)"
    done
else
    echo "heaptrack not available, skipped (Linux container only)"
fi

echo "### 7. macOS sampling (appendix slide), only on macOS"
if command -v sample > /dev/null && [ "$(uname)" = "Darwin" ]; then
    # dsymutil is NOT optional: without it the debug map points at deleted .o files
    # and `sample` segfaults while symbolicating.
    dsymutil "$B/ss-slow$SUF" 2>/dev/null || true
    "$B/ss-slow$SUF" "$B/big.txt" > /dev/null &
    SPID=$!
    sleep 0.2
    sample $SPID 2 -f "$B/macos_sample.txt" > /dev/null 2>&1 || echo "sample failed"
    wait $SPID 2>/dev/null || true
    grep -E "countDistinct.*stats\.cpp" "$B/macos_sample.txt" 2>/dev/null | head -3 || true
fi

echo "DONE"
