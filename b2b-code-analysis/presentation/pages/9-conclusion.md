---
layout: section
---

# Conclusion

---
layout: default
title: What a clean result proves
---

## What code analysis proves

<br>

<v-switch>

<template #0>

| Output              | What that detects                 |
|---------------------|-----------------------------------|
| No warnings         | none of the enabled checks fired  |
| Sanitizers silent   | no bug on the paths you ran       |
| 100 % coverage      | every line ran                    |
| Flat profile        | no hotspot in this workload       |
| PR approved         | no issues found by the reviewer   |

</template>

<template #1-3>

| Output              | What that detects                 | What it says nothing about                    |
|---------------------|-----------------------------------|-----------------------------------------------|
| No warnings         | none of the enabled checks fired  | checks you did not enable |
| Sanitizers silent   | no bug on the paths you ran       | paths you did not run |
| 100 % coverage      | every line ran                    | whether any result was checked |
| Flat profile        | no hotspot in this workload       | what you did not measure |
| PR approved         | no issues found by the reviewer   | what the reviewer did not see |

</template>

</v-switch>

<v-click at="2">

<span v-mark.red="2">No single step</span> replaces the others

</v-click>

---
layout: fact
title: 'The question map: complete'
---

<Transform :scale="0.8">

```mermaid
flowchart LR
  q{"What am I trying to learn<br/>about this code?"}
  q --> qs["Can I find issues<br/>before I even run it?"]
  q --> qr["Why does it misbehave<br/>while it runs?"]
  q --> qc["Has this code<br/>even run?"]
  q --> qp["Where do time<br/>and memory go?"]
  q --> qm["Is it doing what it<br/>was meant to do?"]
  qs --> s["<b>Static analysis</b>"]:::rounded
  qr --> r["<b>Runtime analysis</b>"]:::rounded
  qc --> c["<b>Coverage</b>"]:::rounded
  qp --> p["<b>Profiling</b>"]:::rounded
  qm --> m["<b>Code review</b>"]:::rounded

  classDef rounded rx:15, ry:15
```

</Transform>

---
layout: default
title: It's all code analysis
---

![It's all code analysis](/its_all_code_analysis.png)
