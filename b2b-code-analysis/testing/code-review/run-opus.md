# Blind review run — Claude Opus 5 (2026-09-14)

Same methodology as every run (see the speaker notes of the "Reviewing with AI"
slide, presentation/pages/8-code-review.md): the exact text of `prompt.md`
(the three frozen `../0-initial/` files pasted inline) sent through Claude
Code in print mode from an empty directory, all tools disabled, no repo
access, no execution, single run. Captured verbatim below.

- Model: claude-opus-5 · list price $5/M input, $25/M output
- Usage: 15,066 total tokens (4,730 input incl. prompt-cache write, 10,336 output of which 3,967 reasoning), 120 s wall-clock
- Cost: ≈ $0.31 (harness-reported at list price; the prompt was written to a 1 h cache, which bills input at 2×)
  The harness additionally made one small Claude Haiku 4.5 side call (~2 k tokens, < $0.01); it is excluded from the numbers above.
- Findings: 17

---

# Blind static review

Line numbers are counted from 1 at the top of each file as given.

---

## 1. `main.cpp:24` — **UB (stack buffer overflow, write)**

```cpp
++buckets[r / 10];
```

`buckets` has exactly 10 elements, so only `r / 10 ∈ [0, 9]`, i.e. `r ∈ [0, 99]`, is in range. There is no validation anywhere that readings fall in that window — `loadReadings` accepts any `int` the file contains.

* `r = 100` → index 10 → one-past-the-end write.
* `r = 12345` → index 1234 → wild write far past the array.
* `r = -15` → `-15 / 10 == -1` (truncation toward zero) → index −1 → write *before* the array.

Note the asymmetry that makes this easy to miss in testing: `r ∈ [-9, -1]` yields index 0, so small negatives look "fine" while `-10` and below corrupt the stack. This is a corrupting out-of-bounds *write* on an automatic-storage object, so it is a genuine memory-safety hole, not just a wrong answer.

**Fix** — make the bucketing total, and stop hardcoding the divisor separately from the size:

```cpp
constexpr std::size_t bucketCount = 10;
constexpr int bucketWidth = 10;

std::array<int, bucketCount> histogram(const std::vector<int>& readings)
{
    std::array<int, bucketCount> buckets{};
    for (const int r : readings)
    {
        const long long index = std::clamp<long long>(r / bucketWidth, 0, bucketCount - 1);
        ++buckets[static_cast<std::size_t>(index)];
    }
    return buckets;
}
```

If out-of-range readings are supposed to be an error rather than clamped, reject them at load time instead — but silently mis-indexing is not an option either way.

---

## 2. `stats.cpp:20` — **UB (division by zero)**

```cpp
int count = readings.size();
int mean = sum / count;
```

With an empty `readings`, `count == 0` and `sum / count` is undefined behaviour (on x86 typically `SIGFPE`, killing the process). This is *reachable*: `main.cpp:47–50` detects the empty case, prints a warning, and then falls straight through to `printReport(computeStats(readings), false)` at line 52. So the trivially common inputs — missing file, empty file, file of non-numeric junk — crash the program after politely warning you.

**Fix** — make emptiness a precondition the type system enforces, rather than a runtime landmine:

```cpp
std::optional<Stats> computeStats(const std::vector<int>& readings);
```

```cpp
if (readings.empty())
{
    return std::nullopt;
}
```

and have `main` bail out before calling it (see #9).

---

## 3. `stats.cpp:16` — **UB (signed integer overflow)**

```cpp
sum += r;
```

`sum` is `int`. Overflow of a signed integer is UB, not wraparound, and the compiler is entitled to optimise on the assumption it never happens. Manifests with as few as two readings near `INT_MAX`, or ~2.1 million readings of value 1000 — entirely plausible for a sensor log. The resulting `mean` is garbage even in the benign case.

**Fix**: accumulate in a wide type and divide there.

```cpp
long long sum = 0;   // or std::int64_t
...
const double mean = static_cast<double>(sum) / static_cast<double>(readings.size());
```

(For a truly overflow-proof mean over `int64` inputs you would need a running/Kahan average, but `long long` over `int` inputs cannot overflow for any vector that fits in memory.)

---

## 4. `main.cpp:9`, `main.cpp:45` — **leak (unrecoverable)**

```cpp
auto* readings = new std::vector<int>;
...
const std::vector<int>& readings = *loadReadings(argv[1]);
```

The vector and its heap buffer are never freed. Worse, line 45 binds a reference to the pointee and **discards the pointer immediately**, so the allocation is not merely leaked — it is *unreclaimable*; there is no expression left in the program that could be passed to `delete`. Every run leaks the whole dataset.

There is no reason for the allocation at all: returning a `std::vector` by value is a move (in practice NRVO, so zero copies).

**Fix**:

```cpp
std::vector<int> loadReadings(const std::string& path)
{
    std::vector<int> readings;
    std::ifstream in(path);
    ...
    return readings;
}
```

```cpp
const std::vector<int> readings = loadReadings(argv[1]);
```

---

## 5. `stats.cpp:19` — **bug (narrowing `size_t` → `int`)**

```cpp
int count = readings.size();
```

Silent narrowing from `std::vector<int>::size_type`. For more than `INT_MAX` elements the value is wrong (since C++20 well-defined modulo 2³², before that implementation-defined) — it can become negative or zero, which turns the division at line 20 into either a wrong result or the division-by-zero UB of #2 with a *non-empty* vector. It also trips `-Wconversion` / `-Wshorten-64-to-32` on every build. Admittedly `>2^31` readings is a stretch, but the fix costs nothing.

**Fix**: don't introduce the intermediate at all — divide using the wide types as shown in #3, or use `const auto count = readings.size();`.

---

## 6. `stats.cpp:8–9` — **bug (sentinel values escape on empty input)**

```cpp
int minimum = std::numeric_limits<int>::max();
int maximum = std::numeric_limits<int>::min();
```

Even after fixing the division-by-zero, the empty-input path would return `{2147483647, -2147483648, ...}` — a `Stats` that looks like valid data and will be printed as such by `printReport`. The sentinel-initialisation idiom quietly conflates "no data" with "extreme data".

**Fix**: the `std::optional<Stats>` return from #2 removes the ambiguity. Once emptiness is excluded, prefer the standard algorithm over the manual sentinel loop:

```cpp
const auto [minIt, maxIt] = std::minmax_element(readings.begin(), readings.end());
```

---

## 7. `stats.cpp:20` and `stats.hpp:12` — **bug / API design (integer mean)**

```cpp
int mean;
...
int mean = sum / count;
```

The mean of integers is not an integer. `{1, 2}` reports mean `1`; `{0, 0, 0, 10}` reports `2` instead of `2.5`. Worse, integer division truncates *toward zero*, so the sign of the error flips with the sign of the data: `{-1, -2}` gives `-1` (rounded up) while `{1, 2}` gives `1` (rounded down). For a humidity sensor straddling zero this produces a systematic bias toward zero, not a consistent rounding rule.

**Fix**: make the field `double`. If an integer really is required by the output contract, round explicitly (`std::llround`) and name it `roundedMean` so the lossiness is visible at the call site.

---

## 8. `main.cpp:10–15` — **robustness (no I/O error detection)**

```cpp
std::ifstream in(path);
int value = 0;
while (in >> value)
```

Three distinct failures are silently indistinguishable from "the file legitimately contained no numbers":

* **File does not exist / is unreadable** — `in` is in a failed state, the loop body never executes, an empty vector is returned. The user gets `warning: no readings loaded` and (currently) a crash, with no hint that the *path* was the problem.
* **Malformed token mid-file** — `12 34 abc 56` stops at `abc` and silently returns only `{12, 34}`. Statistics are computed over a truncated dataset and reported as authoritative. This is the dangerous one: wrong numbers, no diagnostic.
* **Values outside the sensor's valid range** — no validation, feeding #1.

**Fix**: check `is_open()`, and after the loop distinguish EOF from a conversion failure via `in.eof()`.

```cpp
std::ifstream in(path);
if (!in)
{
    throw std::runtime_error("cannot open " + path);
}
...
if (!in.eof())
{
    throw std::runtime_error("malformed integer in " + path);
}
```

Also consider `readings.reserve(...)` if a rough size is known — minor, but the current loop reallocates *O*(log n) times.

---

## 9. `main.cpp:47–50` — **bug (warning is not handling)**

```cpp
if (readings.empty())
{
    std::cout << "warning: no readings loaded\n";
}
```

Detecting the bad state and then proceeding into it anyway. Three problems: it falls through to the UB at #2; the warning goes to `stdout`, polluting the machine-readable report rather than going to `stderr`; and the process still exits 0 (implicit `return 0` at line 60), so a scripted caller sees success for a run that produced nothing.

**Fix**:

```cpp
if (readings.empty())
{
    std::cerr << "error: no readings loaded from " << argv[1] << '\n';
    return 1;
}
```

---

## 10. `stats.cpp:27–42` — **performance (*O*(n²))**

The nested loop compares every element against every prior element: ~n²/2 comparisons. At 100 000 readings that is ~5·10⁹ comparisons — minutes of wall time for work that should be milliseconds. There is no compensating benefit; the function does not preserve order or avoid allocation in any way that matters here.

**Fix** — *O*(n) average with a hash set:

```cpp
std::size_t countDistinct(const std::vector<int>& readings)
{
    return std::unordered_set<int>(readings.begin(), readings.end()).size();
}
```

If allocation is a concern, sort a copy and `std::unique` for *O*(n log n) with one allocation.

---

## 11. `main.cpp:7` — **API design (owning raw pointer)**

`std::vector<int>* loadReadings(...)` returns ownership through a naked pointer, with nothing in the signature or a comment saying so. This is precisely what caused #4. Even had the caller been disciplined, it is exception-unsafe: anything that throws between the `new` and the eventual `delete` leaks.

**Fix**: return by value (#4). Never `new` a container to return it.

Minor, same line: taking `const std::string&` forces a `std::string` temporary to be constructed from `argv[1]`. `const std::filesystem::path&` is the idiomatic parameter for a path and avoids the transcoding question on Windows.

---

## 12. `main.cpp:29` — **bug (parameter silently ignored)**

```cpp
void printReport(const Stats& stats, bool verbose)
```

`verbose` is never read. Either the verbose branch was lost or never written; the parameter is now a lie in the API — a caller passing `true` gets identical output with no indication that the request was dropped. Emits `-Wunused-parameter`.

**Fix**: implement it, or delete the parameter and the `false` argument at line 52.

```cpp
if (verbose)
{
    std::cout << "  (" << /* n */ " readings)\n";
}
```

---

## 13. `main.cpp:44` — **style (unused variable)**

```cpp
int checksum = 0;
```

Never read or written again. Dead code — remove it. Suggests a checksum feature was started and abandoned; if it is still intended, it belongs in a tracked TODO, not as a stray local.

---

## 14. `stats.hpp` — **API design / style, several**

* **Line 3, `#include <string>`** — nothing in the header uses `std::string`. Remove it. (Conversely `main.cpp` uses `std::string` at line 7 and `std::vector` at line 19 while including neither directly — it leans on `stats.hpp`'s includes. Include what you use, so a change to the header cannot break unrelated translation units.)
* **Lines 8–13, `Stats` has no default member initialisers** — `Stats s;` leaves all three members indeterminate; reading them is UB. Add `int minimum{};` etc., or `= 0`.
* **Line 14, `int countDistinct(...)`** — a count cannot be negative and is bounded by `readings.size()`; return `std::size_t`. Same narrowing objection as #5.
* **Lines 13–14** — neither function is marked `[[nodiscard]]`. Both are pure and calling them for effect is always a bug; let the compiler say so.
* **`std::size_t` in `stats.cpp:27,30`** without `#include <cstddef>` — it compiles today only because `<vector>` happens to drag it in. Add the include.

---

## 15. `main.cpp:19,24` — **style (magic numbers, decoupled constants)**

The bucket count `10` (line 21, in the type) and the bucket width `10` (line 24, in the divisor) are independent literals that *must* agree for the code to be correct, but nothing ties them together. Changing one silently reintroduces #1. Hoist both to named `constexpr` constants as shown in #1.

---

## 16. `main.cpp:55–59` — **style (output formatting)**

Emits a trailing space before the newline (`0 0 3 1 ... 0 \n`). Harmless but untidy and awkward to diff or parse. Print the separator *before* all but the first element, or use an index test.

Also, `main` has no explicit `return 0;` at line 60. That is legal and well-defined for `main` specifically, but given that every other exit path returns explicitly, the asymmetry reads as an oversight.

---

## 17. `stats.cpp:12–17` — **style (hand-rolled loop)**

Combining min, max, and sum in one manual loop is fine for performance but obscures intent. With emptiness already excluded, `std::minmax_element` plus `std::accumulate` (into `0LL`) says the same thing in two lines and cannot get the sentinel initialisation wrong. The single-pass version is only worth keeping if profiling shows the traversal matters.

---

# Rewritten highlights

**`stats.hpp`**

```cpp
#pragma once

#include <cstddef>
#include <optional>
#include <vector>

struct Stats
{
    int minimum{};
    int maximum{};
    double mean{};
};

// Returns nullopt for an empty input: min/max/mean are undefined there.
[[nodiscard]] std::optional<Stats> computeStats(const std::vector<int>& readings);
[[nodiscard]] std::size_t countDistinct(const std::vector<int>& readings);
```

**`stats.cpp`**

```cpp
#include "stats.hpp"

#include <algorithm>
#include <numeric>
#include <unordered_set>

std::optional<Stats> computeStats(const std::vector<int>& readings)
{
    if (readings.empty())
    {
        return std::nullopt;
    }

    const auto [minIt, maxIt] = std::minmax_element(readings.begin(), readings.end());
    const long long sum = std::accumulate(readings.begin(), readings.end(), 0LL);

    return Stats{*minIt, *maxIt, static_cast<double>(sum) / static_cast<double>(readings.size())};
}

std::size_t countDistinct(const std::vector<int>& readings)
{
    return std::unordered_set<int>(readings.begin(), readings.end()).size();
}
```

**`main.cpp`**

```cpp
#include "stats.hpp"

#include <algorithm>
#include <array>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
constexpr std::size_t bucketCount = 10;
constexpr int bucketWidth = 10;

std::vector<int> loadReadings(const std::string& path)
{
    std::ifstream in(path);
    if (!in)
    {
        throw std::runtime_error("cannot open " + path);
    }

    std::vector<int> readings;
    int value = 0;
    while (in >> value)
    {
        readings.push_back(value);
    }
    if (!in.eof())
    {
        throw std::runtime_error("malformed integer in " + path);
    }
    return readings;
}

std::array<int, bucketCount> histogram(const std::vector<int>& readings)
{
    std::array<int, bucketCount> buckets{};
    for (const int r : readings)
    {
        const auto index = std::clamp<long long>(r / bucketWidth, 0, bucketCount - 1);
        ++buckets[static_cast<std::size_t>(index)];
    }
    return buckets;
}

void printReport(const Stats& stats)
{
    std::cout << "min " << stats.minimum
              << " max " << stats.maximum
              << " mean " << stats.mean << '\n';
}
} // namespace

int main(int argc, char* argv[])
{
    if (argc != 2)
    {
        std::cerr << "usage: humidity-stats <file>\n";
        return 1;
    }

    try
    {
        const std::vector<int> readings = loadReadings(argv[1]);

        const auto stats = computeStats(readings);
        if (!stats)
        {
            std::cerr << "error: no readings loaded from " << argv[1] << '\n';
            return 1;
        }

        printReport(*stats);
        std::cout << "distinct " << countDistinct(readings) << '\n';

        const auto buckets = histogram(readings);
        for (std::size_t i = 0; i < buckets.size(); ++i)
        {
            std::cout << (i == 0 ? "" : " ") << buckets[i];
        }
        std::cout << '\n';
    }
    catch (const std::exception& e)
    {
        std::cerr << "error: " << e.what() << '\n';
        return 1;
    }

    return 0;
}
```

**Summary of severities:** 3 UB (OOB write, division by zero, signed overflow), 1 unrecoverable leak, 5 correctness bugs (narrowing, sentinel leakage, truncating mean, ignored `verbose`, warn-and-continue), 1 major performance defect (*O*(n²)), plus robustness gaps in I/O handling and assorted API/style issues.

The two I would fix first are the histogram OOB write and the empty-input division — both are reachable from a plain `./humidity-stats somefile.txt` with unremarkable data.
