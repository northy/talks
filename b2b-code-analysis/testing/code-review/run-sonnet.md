# Blind review run — Claude Sonnet 5 (2026-09-14)

Same methodology as every run (see the speaker notes of the "Reviewing with AI"
slide, presentation/pages/8-code-review.md): the exact text of `prompt.md`
(the three frozen `../0-initial/` files pasted inline) sent through Claude
Code in print mode from an empty directory, all tools disabled, no repo
access, no execution, single run. Captured verbatim below.

- Model: claude-sonnet-5 · list price $2/M input, $10/M output
- Usage: 14,652 total tokens (10,152 input incl. prompt-cache write, 4,500 output of which 0 reasoning), 40 s wall-clock
- Cost: ≈ $0.07 (harness-reported at list price; the prompt was written to a 1 h cache, which bills input at 2×)
  The harness additionally made one small Claude Haiku 4.5 side call (~2 k tokens, < $0.01); it is excluded from the numbers above.
- Findings: 15

---

I'll perform the blind static review now, working purely from the pasted source.

## Findings (most to least severe)

### 1. `main.cpp:29` — **Bug/UB**: `histogram` out-of-bounds write for negative or large readings
`buckets[r / 10]` is computed with no bounds check. If `r` is negative (e.g., `-5`), `r / 10 == 0` in C++ (truncation toward zero), so small negatives land in bucket 0 silently (logic bug), but more importantly if `r` is, say, `-15`, `r/10 == -1`, giving `buckets[-1]` — out-of-bounds write, undefined behavior. Similarly any `r >= 100` gives an index ≥ 10, also out-of-bounds. Since readings come from an arbitrary file, this is trivially triggerable and is a memory-corruption bug, not just a logic error.

**Fix:**
```cpp
std::array<int, 10> histogram(const std::vector<int>& readings)
{
    std::array<int, 10> buckets{};
    for (int r : readings)
    {
        std::size_t bucket = static_cast<std::size_t>(r / 10);
        if (r >= 0 && bucket < buckets.size())
        {
            ++buckets[bucket];
        }
    }
    return buckets;
}
```
(Or clamp/report out-of-range values explicitly, depending on desired semantics.)

---

### 2. `main.cpp:9-16` and `main.cpp:37` — **Leak**: `loadReadings` returns an owning raw pointer, bound to a `const&`, never deleted
`loadReadings` does `new std::vector<int>` and returns a raw pointer. `main` does:
```cpp
const std::vector<int>& readings = *loadReadings(argv[1]);
```
This binds a reference to a dereferenced heap pointer and then **discards the pointer** — there is no way to ever `delete` it. This is a guaranteed memory leak on every run. It also obscures ownership: nothing in the type signature indicates the caller must free anything, so even a careful caller couldn't get this right without extra info.

**Fix:** Return by value (RVO/move makes this free), no raw `new`/pointer needed at all:
```cpp
std::vector<int> loadReadings(const std::string& path)
{
    std::vector<int> readings;
    std::ifstream in(path);
    int value = 0;
    while (in >> value)
    {
        readings.push_back(value);
    }
    return readings;
}
...
std::vector<int> readings = loadReadings(argv[1]);
```

---

### 3. `stats.cpp:19-20` — **Bug/UB**: division by zero when `readings` is empty
```cpp
int count = readings.size();
int mean = sum / count;
```
If `readings` is empty, `count == 0`, and `sum / count` is integer division by zero — UB (typically SIGFPE / crash). `main.cpp` explicitly anticipates the empty-readings case (prints a warning) but then calls `computeStats(readings)` anyway right after, so this is directly reachable, e.g. with an empty or nonexistent input file.

**Fix:**
```cpp
int mean = count > 0 ? sum / count : 0;
```
and/or have `main` skip calling `computeStats` (and `histogram`/`countDistinct`) entirely when `readings.empty()`.

---

### 4. `main.cpp:9-16` — **Robustness**: no error handling for failed file open
`std::ifstream in(path)` is never checked with `in.is_open()` / `in.good()`. If the path doesn't exist or can't be opened, the stream silently fails, the `while (in >> value)` loop never executes, and `loadReadings` returns an empty vector indistinguishable from "file existed but was empty." The user gets a vague "no readings loaded" warning instead of a clear "file not found" error.

**Fix:**
```cpp
std::ifstream in(path);
if (!in)
{
    std::cerr << "error: could not open " << path << '\n';
    // signal failure, e.g. via std::optional<std::vector<int>> or exception
}
```

---

### 5. `main.cpp:9-16` — **Robustness**: malformed input is silently swallowed rather than reported
If the file contains non-integer tokens (e.g., `"abc"`), `in >> value` fails, the loop simply stops, and everything read up to that point is silently kept with no indication that parsing stopped early due to bad data rather than reaching EOF cleanly. A user with a typo'd or partially corrupt data file gets no diagnostic.

**Fix:** Check `in.eof()` vs. failure after the loop, and warn on parse failure:
```cpp
while (in >> value) { readings.push_back(value); }
if (!in.eof())
{
    std::cerr << "warning: stopped reading at malformed input\n";
}
```

---

### 6. `stats.cpp:17` — **Bug**: `int count = readings.size()` — narrowing conversion, silent truncation/sign issues
`readings.size()` returns `std::vector<int>::size_type` (typically `size_t`, unsigned, 64-bit). Assigning to `int` narrows silently (no compiler warning without `-Wconversion`/`{}`-init) and can overflow/wrap for very large inputs (> ~2 billion elements — unlikely here but still a latent correctness issue and definitely a style smell), and mixes signedness in a way that's easy to get wrong.

**Fix:**
```cpp
std::size_t count = readings.size();
...
int mean = count > 0 ? static_cast<int>(sum / static_cast<long long>(count)) : 0;
```

---

### 7. `stats.cpp:11-18` — **Bug/robustness**: `sum` (and `mean`) can silently overflow `int`
`sum += r` accumulates into a plain `int`. For a file with many large-magnitude readings (e.g. thousands of values near `INT_MAX`), this overflows, which is signed-integer UB. Even for realistic sensor data this is a correctness risk if bad/outlier data sneaks in (e.g. a corrupted reading of `2000000000`).

**Fix:** Accumulate in a wider type:
```cpp
long long sum = 0;
...
int mean = count > 0 ? static_cast<int>(sum / static_cast<long long>(count)) : 0;
```

---

### 8. `stats.cpp:29-45` — **Performance**: `countDistinct` is O(n²)
For each element it does a linear scan of all previous elements. For large input files this is quadratic and will be noticeably slow, whereas a sorted-copy or hash-set approach is O(n log n) or O(n) average.

**Fix:**
```cpp
int countDistinct(const std::vector<int>& readings)
{
    std::unordered_set<int> seen(readings.begin(), readings.end());
    return static_cast<int>(seen.size());
}
```

---

### 9. `main.cpp:32-38` — **Style/API design**: `printReport` takes an unused `verbose` parameter that does nothing
```cpp
void printReport(const Stats& stats, bool verbose)
```
`verbose` is never read inside the function, yet the caller passes `false` as if it mattered. This is dead/misleading API surface — either implement verbose behavior (e.g., also print distinct count or histogram when true) or remove the parameter entirely.

**Fix:** Remove the parameter, or actually branch on it:
```cpp
void printReport(const Stats& stats)
{
    std::cout << "min " << stats.minimum << " max " << stats.maximum
              << " mean " << stats.mean << '\n';
}
```

---

### 10. `main.cpp:19` — **Bug/style**: unused variable `checksum`
`int checksum = 0;` is declared and never used anywhere afterward. This is dead code — likely a leftover from removed functionality — and will trigger `-Wunused-variable`. It hints at an intended feature (validating readings?) that was never completed.

**Fix:** Remove it, or implement the intended checksum logic if it was meant to validate file integrity.

---

### 11. `stats.hpp:9` / `stats.cpp` — **API design**: `Stats::mean` as `int` loses information and is misleading
A mean is generally not an integer quantity; truncating it to `int` (via integer division) silently discards the fractional part, which can be surprising for callers expecting an actual average (e.g., readings `{1, 2}` yields `mean == 1`, not `1.5`). This isn't "wrong" if integer-only stats are intentional, but it's worth calling out as a design choice that should at least be documented.

**Fix:** Consider `double mean;` and `double(sum) / count`, or explicitly document that `mean` is a truncated integer average.

---

### 12. `stats.hpp` / `stats.cpp` — **Style**: no header guard consistency issue (minor) — actually fine (`#pragma once` present), but no namespace
Both `computeStats`/`countDistinct`/`Stats` live in the global namespace. For a small program this is acceptable, but for anything meant to grow into a library, an explicit namespace (e.g. `sensors::`) would avoid future name collisions. Minor style note.

---

### 13. `main.cpp:1-38` — **Style**: inconsistent output stream usage for warnings
`"warning: no readings loaded\n"` is printed to `std::cout` (main.cpp:26) while usage errors are printed to `std::cerr` (main.cpp:34). Warnings/diagnostics should consistently go to `std::cerr` so they can be separated from actual program output (e.g., when piping stdout to a file).

**Fix:**
```cpp
std::cerr << "warning: no readings loaded\n";
```

---

### 14. `main.cpp:33` — **Style/robustness**: no validation of `argv[1]` content
Not a bug per se, but there's no check that the argument is a plausible path (e.g., not empty). Minor — mostly subsumed by finding #4 (open-failure check), which would catch this too.

---

### 15. `stats.cpp` / `main.cpp` — **Style**: missing `<cstddef>` / relying on transitively included headers
`std::size_t` is used in `stats.cpp` (`for (std::size_t i ...)`) without including `<cstddef>` directly; it currently compiles only because `<vector>` or `<algorithm>` happens to pull it in transitively. This is fragile — an unrelated header change elsewhere could break the build.

**Fix:** `#include <cstddef>` explicitly wherever `std::size_t` is used directly.

---

## Rewritten highlights

```cpp
// stats.hpp
struct Stats
{
    int minimum;
    int maximum;
    double mean;   // no longer silently truncated
};

// stats.cpp
Stats computeStats(const std::vector<int>& readings)
{
    int minimum = std::numeric_limits<int>::max();
    int maximum = std::numeric_limits<int>::min();
    long long sum = 0;               // avoid overflow

    for (int r : readings)
    {
        minimum = std::min(minimum, r);
        maximum = std::max(maximum, r);
        sum += r;
    }

    std::size_t count = readings.size();
    double mean = count > 0 ? static_cast<double>(sum) / count : 0.0;  // no div-by-zero
    return {minimum, maximum, mean};
}

int countDistinct(const std::vector<int>& readings)
{
    std::unordered_set<int> seen(readings.begin(), readings.end()); // O(n) not O(n^2)
    return static_cast<int>(seen.size());
}

// main.cpp
std::vector<int> loadReadings(const std::string& path)   // return by value, no leak
{
    std::vector<int> readings;
    std::ifstream in(path);
    if (!in)
    {
        std::cerr << "error: could not open " << path << '\n';
        return readings;
    }
    int value = 0;
    while (in >> value)
    {
        readings.push_back(value);
    }
    if (!in.eof())
    {
        std::cerr << "warning: stopped reading at malformed input\n";
    }
    return readings;
}

std::array<int, 10> histogram(const std::vector<int>& readings)
{
    std::array<int, 10> buckets{};
    for (int r : readings)
    {
        if (r >= 0 && static_cast<std::size_t>(r) / 10 < buckets.size())  // bounds check
        {
            ++buckets[r / 10];
        }
    }
    return buckets;
}

int main(int argc, char* argv[])
{
    if (argc != 2)
    {
        std::cerr << "usage: humidity-stats <file>\n";
        return 1;
    }

    std::vector<int> readings = loadReadings(argv[1]);

    if (readings.empty())
    {
        std::cerr << "warning: no readings loaded\n";
        return 1;
    }

    printReport(computeStats(readings));
    std::cout << "distinct " << countDistinct(readings) << '\n';
    for (int count : histogram(readings)) std::cout << count << ' ';
    std::cout << '\n';
}
```
