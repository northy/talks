---
layout: section
---

# Appendix

---
layout: default
title: clang-analyzer
info: |
    https://clang.llvm.org/docs/analyzer/
---

## The path-sensitive big gun

`clang-analyzer-*`: symbolic execution exploring **paths**, each possible sequence of branches, with symbolic values tracked along the way

<!-- Verified: clang-tidy 22.1.8 on @/testing/0-initial (and again on 1-post-static-analysis): zero findings from both TUs. Proof the analyzer runs: @/testing/static-analysis/micro/analyzer_sanity.cpp (same-function new leak + null deref) fires NewDeleteLeaks and NullDereference; @/testing/static-analysis/micro/leak_replica.cpp reproduces the humidity-stats pattern and stays silent. -->
```sh {lines: false}
clang-tidy stats.cpp --checks='-*,clang-analyzer-*' -- -std=c++20
clang-tidy main.cpp  --checks='-*,clang-analyzer-*' -- -std=c++20
```

<div v-click>

```txt {lines: false}
ㅤ
```

</div>

<v-clicks at="2">

* Silence
* It *is* running: a same-function leak or null dereference fires instantly
  (`clang-analyzer-cplusplus.NewDeleteLeaks`, `clang-analyzer-core.NullDereference`)
* Path exploration is budgeted (paths explode exponentially) and mostly per translation unit

</v-clicks>

---
layout: default
title: 'Appendix: ASan and optimization levels'
---

## ASan reports shift with optimization

<!-- Verified: @/testing/runtime-analysis/build/ (ASan captures at -O0 and -O1) -->

<v-clicks>

* At `-O0`, the boundary.txt report points at `histogram(...) main.cpp:30`, the bug line
* At `-O1`, `histogram` is inlined; depending on the symbolizer the report either collapses into the call site (`main.cpp:60`) or keeps the bug line as an inline frame
* Practical default: build sanitizer configurations with `-O1 -g -fno-omit-frame-pointer` for speed, but expect inlining in stacks, or drop to `-O0` when a report confuses you

</v-clicks>

<!-- ### Notes:
* Backs up the runtime-analysis ASan demo, for "why does my ASan stack point at the wrong line?"
* Key point: at -O1 inlining can move the report from the bug line (main.cpp:30) to the call site (main.cpp:60). macOS atos shows the call site, llvm-symbolizer keeps the inline frame. Drop to -O0 when confused.
-->

---
layout: default
title: 'Appendix: the TSan fix'
---

## The TSan fix: make the sharing explicit

<!-- Snippets from @/testing/runtime-analysis/parallel/stats.cpp -> stats_fixed.cpp -->
````md magic-move[stats.cpp ~i-vscode-icons:file-type-cpp~]{at: 1}

```cpp
int sum = 0;
const std::size_t mid = readings.size() / 2;
auto worker = [&](std::size_t lo, std::size_t hi)
{
    for (std::size_t i = lo; i < hi; ++i)
    {
        sum += readings[i];
    }
};
```

```cpp
std::atomic<int> sum = 0;
const std::size_t mid = readings.size() / 2;
auto worker = [&](std::size_t lo, std::size_t hi)
{
    for (std::size_t i = lo; i < hi; ++i)
    {
        sum += readings[i];   // atomic read-modify-write: no race
    }
};
```

````

<v-clicks at="2">

* The conflicting writes are now synchronized, and the sharing is *declared*, in the type
* TSan on the fixed build: **no reports**, output correct

</v-clicks>

<!-- ### Notes:
* Backs up the TSan detour in the runtime chapter, for "and how do you fix a race like that?"
* Verified: @/testing/runtime-analysis/build/tsan_fixed.txt - the atomic variant (parallel/stats_fixed.cpp) runs clean under TSan, correct output.
* An atomic is the smallest honest fix; per-thread partial sums joined at the end would avoid the contention entirely. The point that matters: shared mutable state is now visible to tools *and* humans.
-->

---
layout: default
title: 'Appendix: contracts, the static side'
info: |
    P2900R14 (wg21.link/P2900); draft: [dcl.contract.func] (9.4.1), [basic.contract] (6.11)
---

## C++26 contracts: intent as program structure

<!-- Snippet from @/testing/static-analysis/micro/contract_pre.cpp; compiles: GCC 16.1, -std=c++26 -->
```cpp [contract_pre.cpp ~i-vscode-icons:file-type-cpp~]{*|6-7}{at: 1}
#include <vector>

struct Stats { int minimum, maximum, mean; };

// Precondition is now program structure, not a comment:
Stats computeStats(const std::vector<int>& readings)
    pre (!readings.empty());
```

<v-clicks at="2">

* `pre`, `post`, and `contract_assert` adopted into C++26 ([P2900](https://wg21.link/P2900))
* The predicate is real C++: type-checked at compile time

</v-clicks>

<!-- ### Notes:
* Backs up the production chapter's "where do assumptions live" and contract semantics slides, for "can contracts help *static* analysis too?"
* Key point: the predicate is type-checked at compile time, the static-side complement to the runtime evaluation semantics shown in the production chapter.
-->

---
layout: default
title: 'Appendix: contract compiler support'
---

## Support today (verified July 2026)

| Compiler | `-std=c++26` + `pre()` |
|---|---|
| GCC 16.1 | <emojione-white-heavy-check-mark/> **compiles** |
| GCC 16.1 (`-std=c++23`) | <emojione-cross-mark-button/> `error: expected initializer before 'pre'` |
| Clang 22.1 | <emojione-cross-mark-button/> `error: expected function body after function declarator` |
| MSVC 19 (latest) | <emojione-cross-mark-button/> `error C3646: 'pre': unknown override specifier` |

<v-click>

Bleeding edge, but the *direction* is set: assumptions are becoming code

</v-click>

<footer class="absolute bottom-2 left-0 right-0 text-center">
<emojione-white-heavy-check-mark/>: Success | <emojione-cross-mark-button/>: Failure
</footer>

<!-- ### Notes:
* Backs up the production chapter's contracts slides (and the appendix slide above), for "can I use contracts today?"
* Key point: only GCC 16.1 at -std=c++26 compiles the `pre()` syntax so far.
* Also verified on GCC 16.1: `post(r : r >= 0)` and `contract_assert(cond)` compile; `-fcontracts` is not required for the P2900 syntax; the predicate is type-checked (a bogus member gives "has no member named"). Clang 22.1 rejects `-fcontracts` as an unknown argument. Only the `pre` probe is kept in the repo (@/testing/static-analysis/micro/contract_pre.cpp); the post/contract_assert/C++23 probes were one-off runs.
* C++26 was finalized March 2026 (London/Croydon) with contracts merged into the working draft: [basic.contract] (6.11), [dcl.contract.func] (9.4.1).
-->

