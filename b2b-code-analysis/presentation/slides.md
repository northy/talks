---
title: Back to Basics - Code Analysis
author: Alexsandro Thomas
keywords: cpp,static analysis,code analysis,tooling,sanitizers,coverage,profiling
info: |
  # Back to Basics
  ## Code Analysis

  In the C++ ecosystem, we have powerful tools for understanding our programs before, during, and after they run. But compiler warnings, clang-tidy, cppcheck, sanitizers, debuggers, profilers, and coverage tools all answer different questions, and using them well starts with knowing which question you are asking.

  This talk introduces code analysis from first principles. We will compare static techniques such as compiler diagnostics, linting, and include analysis with runtime techniques such as sanitizers, coverage instrumentation, and profiling. We will also briefly connect these tools to the direction of modern C++, including C++26 contracts and standard library hardening, where some assumptions that used to live only in comments, documentation, or debug modes become part of the program's checkable structure. Through small C++ examples, we will see what each category of tool can reveal, what it cannot prove, and how the tools complement each other.

  Attendees will leave with a practical mental model for choosing the right analysis tool for the task at hand, interpreting its output, introducing analysis into an existing C++ codebase, and writing code that is easier for both humans and tools to understand.

  Note: This presentation runs better on chromium-based browsers. If you experience any problems, please switch your browser accordingly.

  The source code for the presentation and all verified code samples can be found at the [git repository](https://github.com/northy/talks/tree/master/b2b-code-analysis).

  [Back to Basics: Code Analysis (slides)](https://northy.github.io/b2b-code-analysis) © 2026 by [Alexsandro Thomas](https://github.com/northy) is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

titleTemplate: '%s'
exportFilename: b2b-code-analysis
export:
  format: pdf
  dark: true
  withClicks: true
  withToc: false
theme: default
addons: []
transition: fade
highlighter: shiki
css: unocss
twoslash: false
monaco: false
lineNumbers: true
mdc: true

layout: cover
class: "text-center"
hide: false # `true` when exporting for CppCon
---

# Back to Basics

## Code Analysis

<footer class="absolute bottom-[20%] left-0 right-0 text-center">Alexsandro Thomas</footer>

---
layout: cover
title: 'Back to Basics: Code Analysis'
hide: true # `false` when exporting for CppCon
---

<!-- the `background:` frontmatter option dims the image, so do it here instead -->
<style>
.slidev-layout.cover {
  background-image: url("/cppcon_2026_title_card.png") !important;
}
</style>

---
src: ./pages/0-information.md
---

<!-- imported -->

---
src: ./pages/1-introduction.md
---

<!-- imported -->

---
src: ./pages/2-static-analysis.md
---

<!-- imported -->

---
src: ./pages/3-runtime-analysis.md
---

<!-- imported -->

---
src: ./pages/4-coverage.md
---

<!-- imported -->

---
src: ./pages/5-production.md
---

<!-- imported -->

---
src: ./pages/6-profiling.md
---

<!-- imported -->

---
src: ./pages/7-real-projects.md
---

<!-- imported -->

---
src: ./pages/8-code-review.md
---

<!-- imported -->

---
src: ./pages/9-conclusion.md
---

<!-- imported -->

---
src: ./pages/10-appendix.md
hide: true
---

<!-- imported -->

---
layout: end
---

## Thank you!
