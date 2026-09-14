---
layout: section
---

# Real Projects

<!-- ### Notes:
* All of this was ~120 lines. Your codebase isn't.
-->

---
layout: default
title: The wall of warnings
---

## Your codebase already exists

* Every tool you enable can find hundreds of problems on day one

<!-- Run on @/testing/4-post-profiling (the program's final, fully fixed state); clang-tidy 22.1.8, Linux; regenerate: @/testing/real-projects/run-all.sh -->
```sh {lines: false}
clang-tidy main.cpp --checks='*' -- -std=c++20
```

<div v-click>

```txt {lines: false}
main.cpp:3:1: warning: system include algorithm not allowed [llvmlibc-restrict-system-libc-headers]
main.cpp:10:18: warning: use a trailing return type for this function [modernize-use-trailing-return-type]
main.cpp:10:18: warning: function 'loadReadings' can be made static or moved into an anonymous namespace to enforce internal linkage [misc-use-internal-linkage]
...
11324 warnings generated.
```

</div>

<v-clicks at="2">

* **65 warnings from 17 checks** on our 65-line `main.cpp`
* The goal is <span v-mark.red=3>no new findings</span>

</v-clicks>

<!-- ### Notes:
* This was after all the previous fixes
-->

---
layout: default
title: The adoption staircase
clicks: 6
---

## The adoption staircase

<br>

<v-clicks>

1. Compile clean at `-Wall -Wextra`
2. `-Werror`
3. Useful clang-tidy check sets
4. Sanitizers on the test suite
5. <span v-mark.red=6>Observed</span> coverage and profiling

</v-clicks>

---
layout: default
title: Suppressing with a reason
---

## Suppressing: narrow, named, explained

<!-- Snippets from @/testing/real-projects/legacy/: widget_before.cpp (pre-policy, both flagged) -> widget.cpp (NOLINT added) -->
````md magic-move[widget.cpp ~i-vscode-icons:file-type-cpp~]{at: 1}

```cpp {*|*}
int n = readings.size();
```

```cpp
// NOLINTNEXTLINE(bugprone-narrowing-conversions): legacy code, not touched by the new policy
int n = readings.size();
```

````

<div v-click="[1, 2]">

<!-- Verified (clang-tidy 22.1.8): widget_before.cpp flags BOTH functions (lines 6 and 13); widget.cpp with the NOLINTNEXTLINE flags only the new function (`widget.cpp:14:13`) and reports `Suppressed 1 warnings (1 NOLINT)`. -->

```txt {lines: false}
warning: narrowing conversion from 'size_type' (aka
'unsigned long') to signed type 'int' [bugprone-narrowing-conversions]
```

</div>
