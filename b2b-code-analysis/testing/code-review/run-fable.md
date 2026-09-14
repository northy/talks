# Blind review run — Claude Fable 5 (2026-09-14)

The chapter's main captured run (the one quoted on the "Reviewing with AI" slide). Same methodology as every run (see the speaker notes of the "Reviewing with AI"
slide, presentation/pages/8-code-review.md): the exact text of `prompt.md`
(the three frozen `../0-initial/` files pasted inline) sent through Claude
Code in print mode from an empty directory, all tools disabled, no repo
access, no execution, single run. Captured verbatim below.

- Model: claude-fable-5 · list price $10/M input, $50/M output
- Usage: 11,622 total tokens (5,004 input incl. prompt-cache write, 6,618 output of which 3,089 reasoning), 74 s wall-clock
- Cost: ≈ $0.43 (harness-reported at list price; the prompt was written to a 1 h cache, which bills input at 2×)
  The harness additionally made one small Claude Haiku 4.5 side call (~2 k tokens, < $0.01); it is excluded from the numbers above.
- Findings: 11

---

# Code Review: humidity-stats

## Findings, most severe first

### 1. Out-of-bounds write in `histogram` — **UB (memory corruption)**
**main.cpp:24** — `++buckets[r / 10];` indexes a `std::array<int, 10>` with no range check. Any reading ≥ 100 yields index ≥ 10, and any reading ≤ −10 yields a negative index; both are out-of-bounds writes into a stack array (classic stack smash). Readings −1 … −9 don't crash but are silently misfiled into bucket 0 (truncation toward zero). Nothing validates that inputs are 0–99.

Fix — validate or clamp, and name the assumption:
```cpp
constexpr int kBuckets = 10;
constexpr int kBucketWidth = 10;
for (int r : readings) {
    if (r < 0 || r >= kBuckets * kBucketWidth) {
        // count into an overflow bucket, or report the bad reading
        continue;
    }
    ++buckets[r / kBucketWidth];
}
```
(Using `buckets.at(...)` would at least turn corruption into an exception.)

### 2. Division by zero on empty input — **UB**
**stats.cpp:20** (`sum / count`), triggered from **main.cpp:52**. If the file is empty, missing, or starts with a non-integer token, `readings` is empty, `count` is 0, and integer division by zero is undefined behavior. Note that main.cpp:47–50 *detects* the empty case, prints a warning, and then calls `computeStats` anyway — the check exists but doesn't guard anything.

Fix: make emptiness part of the contract, e.g. return `std::optional<Stats>` (or throw), and in `main` skip the report when empty:
```cpp
std::optional<Stats> computeStats(const std::vector<int>& readings)
{
    if (readings.empty()) return std::nullopt;
    ...
}
```
Even without UB, the empty case would also return the sentinel values `INT_MAX`/`INT_MIN` as "min"/"max" (stats.cpp:8–9), which is misleading output — another reason the empty case must be an explicit non-result.

### 3. Signed overflow when summing — **UB**
**stats.cpp:16** — `sum += r;` with `int sum`. For example ~2200 readings of 1,000,000 overflow `int`; signed overflow is undefined behavior, and even where it "wraps" the mean is garbage. Fix: accumulate in `long long` (or `std::int64_t`):
```cpp
long long sum = 0;
```

### 4. Memory leak / raw owning pointer — **leak + API design**
**main.cpp:9, 16, 45** — `loadReadings` `new`s a `std::vector<int>` and returns a raw pointer; `main` immediately dereferences it into a `const&` (line 45) and never deletes it. The allocation is never freed, and the ownership is invisible at the call site. There is no reason for heap allocation at all — a `std::vector` is cheap to return by value (moved / NRVO'd):
```cpp
std::vector<int> loadReadings(const std::string& path)
{
    std::vector<int> readings;
    std::ifstream in(path);
    int value = 0;
    while (in >> value) readings.push_back(value);
    return readings;
}
```
The `const std::vector<int>& readings = *loadReadings(...)` pattern at line 45 is exactly the kind of code that turns into a dangling reference the moment someone "fixes" the function to return by value while a stale caller still dereferences — kill it now.

### 5. File-open failure is silently treated as "no readings" — **robustness / bug**
**main.cpp:10–15** — `std::ifstream in(path)` is never checked with `in.is_open()` / `if (!in)`. A missing or unreadable file behaves identically to an empty file: the program prints the "warning: no readings loaded" line and exits with status **0**, so scripts can't tell success from failure. Fix:
```cpp
std::ifstream in(path);
if (!in) {
    throw std::runtime_error("cannot open " + path); // or return an error to main
}
```
and return a nonzero exit code from `main` on failure.

### 6. Malformed input silently truncates the data — **robustness**
**main.cpp:12** — `while (in >> value)` stops at the first token that isn't an integer (e.g. `12 34 oops 56` loads only two readings) and at values that overflow `int` (failbit set, extraction stops). No diagnostic is produced; statistics are quietly computed over a partial dataset. Fix: after the loop, check `if (!in.eof())` and report a parse error with position/token.

### 7. Truncating narrowing conversions in `computeStats` — **bug (portability/correctness)**
- **stats.cpp:19** — `int count = readings.size();` narrows `size_t` → `int` (compiler warning at minimum; wrong for > 2³¹ elements). Use `auto count = readings.size();` or `std::ssize`.
- **stats.cpp:20 / stats.hpp:10** — `mean` is an `int`, so the mean is truncated integer division (and truncates toward zero for negative sums, e.g. mean of −1 and −2 reports −1). If integer mean is intended, document it; otherwise make `mean` a `double`:
```cpp
double mean = static_cast<double>(sum) / count;
```

### 8. `countDistinct` is O(n²) — **performance**
**stats.cpp:24–44** — nested-loop "seen before" scan is quadratic; for 10⁶ readings that's ~5·10¹¹ comparisons. Replace with a set:
```cpp
int countDistinct(const std::vector<int>& readings)
{
    std::unordered_set<int> seen(readings.begin(), readings.end());
    return static_cast<int>(seen.size());
}
```
(Or sort a copy + `std::unique` if memory matters.) Note the return type also has a latent narrowing: `size()` → `int`.

### 9. Dead/unused code — **style (and a smell)**
- **main.cpp:44** — `int checksum = 0;` is never used. Delete it (a leftover like this suggests an intended checksum feature was dropped half-way).
- **main.cpp:29, 52** — `printReport`'s `verbose` parameter is never read, and the call site passes a bare `false` whose meaning is invisible to the reader. Either implement it or remove it; if kept, avoid boolean parameters — use an enum (`enum class Verbosity { Terse, Verbose };`) or two functions.

### 10. Include hygiene — **style**
- **stats.hpp:3** — `<string>` is included but nothing in the header uses `std::string`. Remove it.
- **main.cpp** — uses `std::string` (the `argv[1]` → `const std::string&` conversion at line 45 and the parameter at line 7) but never includes `<string>`; it compiles only via the transitive include from stats.hpp — which finding above says to delete. Add `#include <string>` to main.cpp. Include-what-you-use, both directions.

### 11. Minor style / idiom
- **stats.cpp:8–17** — hand-rolled min/max/sum; `std::minmax_element` (or C++20 `std::ranges::minmax`) plus `std::accumulate<long long>` is shorter and harder to get wrong, and reads as intent.
- **main.cpp:21, 24** — the magic numbers 10 (bucket count) and 10 (bucket width) coincidentally match; name them so changing one doesn't silently break the other (see fix in finding 1).
- **stats.hpp** — `computeStats`/`countDistinct` could take `std::span<const int>` (C++20) instead of binding to `std::vector` specifically; minor API-generality point.
- **main.cpp:60** — implicit `return 0` from `main` is legal; but given finding 5, `main` should return nonzero on load failure, so an explicit exit-status story is needed anyway.

## Rewritten highlights

```cpp
// stats.hpp
struct Stats {
    int minimum;
    int maximum;
    double mean;
};
std::optional<Stats> computeStats(const std::vector<int>& readings);

// stats.cpp
std::optional<Stats> computeStats(const std::vector<int>& readings)
{
    if (readings.empty()) return std::nullopt;
    auto [lo, hi] = std::minmax_element(readings.begin(), readings.end());
    long long sum = std::accumulate(readings.begin(), readings.end(), 0LL);
    return Stats{*lo, *hi, static_cast<double>(sum) / readings.size()};
}

int countDistinct(const std::vector<int>& readings)
{
    return static_cast<int>(
        std::unordered_set<int>(readings.begin(), readings.end()).size());
}

// main.cpp
std::vector<int> loadReadings(const std::string& path)   // by value, no new
{
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot open " + path);
    std::vector<int> readings;
    int value = 0;
    while (in >> value) readings.push_back(value);
    if (!in.eof()) throw std::runtime_error("malformed reading in " + path);
    return readings;
}

std::array<int, 10> histogram(const std::vector<int>& readings)
{
    constexpr int kBuckets = 10, kWidth = 10;
    std::array<int, kBuckets> buckets{};
    for (int r : readings)
        if (r >= 0 && r < kBuckets * kWidth)
            ++buckets[r / kWidth];
    return buckets;
}

int main(int argc, char* argv[])
{
    if (argc != 2) { std::cerr << "usage: humidity-stats <file>\n"; return 1; }
    const std::vector<int> readings = loadReadings(argv[1]);   // wrap in try/catch → return 1
    const auto stats = computeStats(readings);
    if (!stats) { std::cout << "no readings loaded\n"; return 0; }
    printReport(*stats);
    ...
}
```

The two findings that can actually crash or corrupt memory today are the histogram out-of-bounds write (any reading outside 0–99) and the divide-by-zero on empty/unreadable input; I'd fix those and the leak before anything else.
