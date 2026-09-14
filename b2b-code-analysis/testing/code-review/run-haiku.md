# Blind review run — Claude Haiku 4.5 (2026-09-14)

Same methodology as every run (see the speaker notes of the "Reviewing with AI"
slide, presentation/pages/8-code-review.md): the exact text of `prompt.md`
(the three frozen `../0-initial/` files pasted inline) sent through Claude
Code in print mode from an empty directory, all tools disabled, no repo
access, no execution, single run. Captured verbatim below.

- Model: claude-haiku-4-5 · list price $1/M input, $5/M output
- Usage: 16,365 total tokens (9,482 input incl. prompt-cache write, 6,883 output of which 4,903 reasoning), 44 s wall-clock
- Cost: ≈ $0.05 (harness-reported at list price; the prompt was written to a 1 h cache, which bills input at 2×)
- Findings: 10

---

# Code Review Findings

## Critical Issues (ordered by severity)

**1. DIVISION BY ZERO — stats.cpp:20**
- **Severity:** Bug (Undefined Behavior)
- **Problem:** When `readings` is empty, `count = readings.size()` equals 0, then `sum / count` performs division by zero.
- **Trigger:** Running with an empty input file, or a file that fails to open (see robustness issue below).
- **Fix:**
```cpp
int count = readings.size();
if (count == 0) return {0, 0, 0};  // or handle appropriately
int mean = sum / count;
```

**2. BUFFER OVERFLOW — main.cpp:24**
- **Severity:** Bug (Undefined Behavior)
- **Problem:** Array `buckets` has size 10 (indices 0–9), but `buckets[r / 10]` accesses index 10 or higher when `r >= 100`, and negative indices when `r <= -10`.
- **Trigger:** Any sensor reading outside range [0, 99].
- **Fix:**
```cpp
if (r >= 0 && r < 100) ++buckets[r / 10];  // or clamp
```

**3. MEMORY LEAK — main.cpp:45**
- **Severity:** Leak
- **Problem:** `loadReadings()` returns a heap-allocated pointer, which is immediately dereferenced into a reference. The pointer is lost; the allocation is never deleted.
- **Trigger:** Every program run (minor for process termination, but bad practice).
- **Fix:** Return by value instead:
```cpp
std::vector<int> loadReadings(const std::string& path)
{
    std::vector<int> readings;
    std::ifstream in(path);
    int value = 0;
    while (in >> value) readings.push_back(value);
    return readings;
}
// Then: std::vector<int> readings = loadReadings(argv[1]);
```

**4. FILE OPEN NOT CHECKED — main.cpp:10**
- **Severity:** Robustness
- **Problem:** `std::ifstream in(path)` may fail to open (file missing, no permissions), but failure is not checked. The `while (in >> value)` loop silently produces an empty vector; user has no way to distinguish "file had no data" from "file didn't open."
- **Trigger:** Nonexistent or unreadable input file.
- **Fix:**
```cpp
std::ifstream in(path);
if (!in) {
    std::cerr << "Error: cannot open file " << path << '\n';
    return readings;  // return empty
}
```

**5. EMPTY VECTOR NOT FULLY GUARDED — main.cpp:52**
- **Severity:** Bug (chains to issue #1)
- **Problem:** Line 47 checks `if (readings.empty())` and prints a warning, but **continues execution** anyway. Line 52 then calls `computeStats(readings)`, which crashes on division by zero if empty.
- **Trigger:** Empty input file (or failed file open with issue #4).
- **Fix:** Return early after warning:
```cpp
if (readings.empty()) {
    std::cout << "warning: no readings loaded\n";
    return 1;
}
```

**6. O(n²) ALGORITHM — stats.cpp:24–43**
- **Severity:** Performance
- **Problem:** `countDistinct()` uses nested loops to find duplicates, making it O(n²). For 10,000 readings, this is ~100M comparisons.
- **Trigger:** Any moderately large input.
- **Fix:** Use a set:
```cpp
int countDistinct(const std::vector<int>& readings) {
    return std::unordered_set<int>(readings.begin(), readings.end()).size();
}
```

**7. UNUSED PARAMETER — main.cpp:29**
- **Severity:** Style
- **Problem:** `printReport()` accepts `bool verbose` but never uses it.
- **Trigger:** Every call.
- **Fix:** Either remove the parameter or implement its logic:
```cpp
void printReport(const Stats& stats, bool verbose)
{
    // if (verbose) { /* more detailed output */ }
    std::cout << "min " << stats.minimum ...;
}
```

**8. UNUSED VARIABLE — main.cpp:44**
- **Severity:** Style
- **Problem:** `int checksum = 0;` is declared but never assigned or used.
- **Trigger:** Code review / compilation with `-Wunused-variable`.
- **Fix:** Remove the line entirely.

**9. TYPE MISMATCH / SIGNEDNESS — stats.cpp:19**
- **Severity:** Style / Minor correctness
- **Problem:** `readings.size()` returns `size_t` (unsigned), assigned to `int count`. For very large vectors (>2B elements, unrealistic here), this truncates. Also, inconsistency with later loop using `std::size_t i`.
- **Trigger:** Unlikely in practice, but bad style.
- **Fix:**
```cpp
std::size_t count = readings.size();
int mean = (count > 0) ? sum / static_cast<int>(count) : 0;
```

**10. MISLEADING VARIABLE NAME — main.cpp:44**
- **Severity:** Style
- **Problem:** Variable `checksum` suggests a computed value, but it is initialized but never updated, making the intent confusing.
- **Trigger:** Code review.
- **Fix:** Delete the variable (no other fixes needed since it's unused).

---

## Rewritten Highlights

**stats.cpp:6–21 (safe version):**
```cpp
Stats computeStats(const std::vector<int>& readings)
{
    if (readings.empty()) return {0, 0, 0};

    int minimum = std::numeric_limits<int>::max();
    int maximum = std::numeric_limits<int>::min();
    long long sum = 0;  // use long long to avoid overflow
    
    for (int r : readings) {
        minimum = std::min(minimum, r);
        maximum = std::max(maximum, r);
        sum += r;
    }
    
    int mean = sum / static_cast<int>(readings.size());
    return {minimum, maximum, mean};
}
```

**stats.cpp:24–26 (efficient version):**
```cpp
int countDistinct(const std::vector<int>& readings)
{
    return std::unordered_set<int>(readings.begin(), readings.end()).size();
}
```

**main.cpp:7–16 (return by value, check open):**
```cpp
std::vector<int> loadReadings(const std::string& path)
{
    std::vector<int> readings;
    std::ifstream in(path);
    if (!in) {
        std::cerr << "Error: cannot open " << path << '\n';
        return readings;
    }
    int value;
    while (in >> value) readings.push_back(value);
    return readings;
}
```

**main.cpp:45–52 (early exit, bounds check):**
```cpp
const std::vector<int> readings = loadReadings(argv[1]);

if (readings.empty()) {
    std::cout << "warning: no readings loaded\n";
    return 0;  // early exit
}

printReport(computeStats(readings), false);
std::cout << "distinct " << countDistinct(readings) << '\n';
```

**main.cpp:19–26 (safe histogram):**
```cpp
std::array<int, 10> histogram(const std::vector<int>& readings)
{
    std::array<int, 10> buckets{};
    for (int r : readings) {
        int bucket = r / 10;
        if (bucket >= 0 && bucket < 10) ++buckets[bucket];
    }
    return buckets;
}
```
