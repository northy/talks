---
layout: section
---

##  Checks in Production

### Assumptions the program can enforce itself

---
layout: default
title: Assumptions as comments
---

## Where do assumptions live today?

<br>

* "readings are between 0 and 100": a comment at best

<v-clicks>

* "the vector must not be empty": someone's head
* "returns an owning pointer": tribal knowledge

</v-clicks>

<v-click>

These can't be type-checked, linted, or enforced: **tools can't see intent**

</v-click>

<!-- ### Notes:
* Each bullet is a bug from this talk: the histogram range guard, the empty-input division, the leak.
* Chapter arc: first contracts, where *we* put the second assumption into the declaration; then hardening, where the *standard library* does the same for the assumptions it has always had (the first bullet is really `operator[]`'s `n < size()`).
-->

---
layout: default
title: Contract runtime semantics
---

## C++26 contracts

<!-- A stripped-down `computeStats`, standalone (GCC 16.1, `-std=c++26`): -->

````md magic-move[stats.cpp ~i-vscode-icons:file-type-cpp~]{at: 1}

```cpp
int meanOf(const std::vector<int>& readings)
{
    assert(!readings.empty());
    int sum = 0;
    for (int r : readings) sum += r;
    return sum / readings.size();
}
```

<!-- Snippet from @/testing/runtime-analysis/contracts/stats_contract.cpp -->
```cpp {*|2|2}
int meanOf(const std::vector<int>& readings)
    pre (!readings.empty())
{
    int sum = 0;
    for (int r : readings) sum += r;
    return sum / readings.size();
}
```

````

<v-clicks depth="2" at="2">

* The requirement is part of the declaration
    * Callers see it, tools see it, and the check has selectable semantics

</v-clicks>

---
layout: default
title: The four evaluation semantics
---

## Evaluation semantics

<!-- Verified on GCC 16.1, empty input violating the precondition; @/testing/runtime-analysis/contracts/stats_contract.cpp with -std=c++26 -fcontracts -fcontract-evaluation-semantic=<...> -->

```sh {lines: false}
g++ -std=c++26 -fcontract-evaluation-semantic=<...> stats.cpp
```

<v-switch>

<template #1>

| Semantic | On violation | `meanOf` on empty input |
|---|---|---|
| `ignore` | no check emitted | UB |

</template>

<template #2>

| Semantic | On violation | `meanOf` on empty input |
|---|---|---|
| `ignore` | no check emitted | UB |
| `observe` | log, continue | logs, then UB |

</template>

<template #3>

| Semantic | On violation | `meanOf` on empty input |
|---|---|---|
| `ignore` | no check emitted | UB |
| `observe` | log, continue | logs, then UB |
| `enforce` | log, terminate | stopped |

</template>

<template #4>

| Semantic | On violation | `meanOf` on empty input |
|---|---|---|
| `ignore` | no check emitted | UB |
| `observe` | log, continue | logs, then UB |
| `enforce` | log, terminate | stopped |
| `quick_enforce` | terminate | stopped |

</template>

</v-switch>

<!-- ### Notes:
* `enforce`: default
* Remember these four names: the hardened standard library, a few slides on, reuses exactly these semantics for its own checks (`_LIBCPP_ASSERTION_SEMANTIC`).
-->

---
layout: default
title: The contracts fix
---

## Caller checks the precondition

<!-- Snippet @/testing/runtime-analysis/contracts/stats_contract.cpp -> stats_contract_fixed.cpp -->
````md magic-move[stats.cpp ~i-vscode-icons:file-type-cpp~]{at: 1}

```cpp {*|*}
int main()
{
    std::vector<int> readings;
    std::cout << "mean " << meanOf(readings) << '\n';
}
```

```cpp
int main()
{
    std::vector<int> readings;
    if (readings.empty())
    {
        std::cout << "no readings\n";
        return 0;
    }
    std::cout << "mean " << meanOf(readings) << '\n';
}
```

````

<div v-click="[1, 2]">

<!-- Verbatim: GCC 16.1, -fcontract-evaluation-semantic=enforce -->
```txt {lines: false}
contract violation in function int meanOf(...) at example.cpp:5: !readings.empty()
[assertion_kind: pre, semantic: enforce, mode: predicate_false, terminating: yes]
```

</div>

<!-- ### Notes:
* That was one precondition, on a function we own. The standard library has them in prose: 
-->

---
layout: quote
info: |
    P3471R4, "Standard Library Hardening" (Varlamov & Dionne), approved for C++26:
    https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p3471r4.html
---

## "Hardening allows turning some instances of undefined behavior in the standard library into a contract violation."

- P3471R4, *Standard Library Hardening*

---
layout: default
title: Hardened standard library
info: |
    https://libcxx.llvm.org/Hardening.html
    C++26 working draft: [structure.specifications], [sequence.reqmts]
---

## The hardened standard library

C++26 (P3471, Standard Library Hardening)

<!-- verified against the working draft (eel.is, fetched 2026-09-14):
     [sequence.reqmts], a[n]: "Hardened preconditions: n < a.size() is true."
     [structure.specifications]/3.5: "Hardened preconditions: conditions that the function assumes to hold whenever it is called."
     /3.5.1: "When invoking the function in a hardened implementation, prior to any other observable side effects of the function, contract assertions whose predicates are as described in the hardened precondition are evaluated with a terminating semantic ([basic.contract.eval])."
     /3.5.2: in a non-hardened implementation a violated hardened precondition is undefined behavior. -->

<v-clicks depth="2">

* `operator[]` requires `n < size()`
* Library preconditions become hardened preconditions
    * checked like a `pre`

</v-clicks>

<v-click>

Modes of hardening:

| Mode | Checks | Intended use |
|---|---|---|
| `FAST` | valid element access, valid input range | **production** |
| `EXTENSIVE` | + null pointers, deallocation, ... | production, more budget |
| `DEBUG` | + semantic requirements, verbose message | development |

</v-click>

<!-- ### Notes:
* These ARE contracts (libcxx.llvm.org/Hardening.html): `_LIBCPP_ASSERTION_SEMANTIC` = ignore / observe / quick-enforce / enforce, the four semantics from the contracts slides (experimental, LLVM 21+). Defaults: quick-enforce in fast/extensive, enforce in debug. The message above is the `enforce` flavor: log, then terminate.
-->

---
layout: default
title: Hardening
---

## Boundary checks in production

If our program had shipped with hardening:

<!-- Verbatim: @/testing/runtime-analysis/build/hard_DEBUG_boundary.txt -->
```txt {lines: false}
.../array:277: libc++ Hardening assertion __n < _Size failed:
out-of-bounds access in std::array<T, N>
```

<v-clicks>

* `__n < _Size`: the `operator[]` precondition, enforced
* Google reports overhead "as low as 0.3 %" in deployment and 1000+ bugs found (P3471R4 &#x00A7;4)

</v-clicks>
