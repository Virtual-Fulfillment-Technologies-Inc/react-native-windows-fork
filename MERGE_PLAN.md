# Merge Plan — React Native Windows Upstream PRs

This document details the exact order to create PRs, when to submit them, when to rebase, and how to manage merge conflicts across the 9 PRs.

---

## Why Order Matters

Three PRs modify `CompositionEventHandler.cpp/.h`. If two of those are open simultaneously and one merges, the other will have merge conflicts. The remaining 6 PRs touch unique files and can be submitted in parallel without conflict.

---

## Conflict Groups

```
Group A — CompositionEventHandler.cpp/.h (3 PRs, must be sequential):
  PR 1 (touch fixes) → PR 2 (null safety) → PR 4 (pointer perf)

Group B — Independent (6 PRs, submit in parallel):
  PR 3, PR 5, PR 6, PR 7, PR 8, PR 9
```

---

## Mermaid Diagram

```mermaid
graph TD
    subgraph "Phase 1 — Submit in Parallel (Day 1)"
        PR3["PR 3: JS component bugs<br/><i>Pressability.windows.js, View.windows.js</i><br/><b>P0</b>"]
        PR5["PR 5: Hit testing + scroll perf<br/><i>CompositionContextHelper.cpp<br/>CompositionViewComponentView.cpp</i><br/><b>P0-PERF</b>"]
        PR6["PR 6: TextInput reliability<br/><i>WindowsTextInputComponentView.cpp/.h</i><br/><b>P1</b>"]
        PR7["PR 7: Threading + error fixes<br/><i>Timing.h, WindowsImageManager.cpp</i><br/><b>P1</b>"]
        PR8["PR 8: Data structure perf<br/><i>AnimatedNode.cpp/.h<br/>WindowsComponentDescriptorRegistry.cpp/.h</i><br/><b>P2-PERF</b>"]
        PR9["PR 9: Dead code cleanup<br/><i>ScrollViewComponentView.cpp<br/>Modal.windows.js</i><br/><b>P3</b>"]
    end

    subgraph "Phase 2 — CompositionEventHandler Chain (Start Day 1)"
        PR1["PR 1: Touch event handling<br/><i>CompositionEventHandler.cpp/.h</i><br/><b>P0</b> — 3 commits"]
        PR2["PR 2: RootComponentView null safety<br/><i>CompositionEventHandler.cpp/.h</i><br/><b>P0</b> — 18 crash sites"]
        PR4["PR 4: Pointer event perf<br/><i>CompositionEventHandler.cpp/.h</i><br/><b>P0-PERF</b> — cache + set"]

        PR1 -->|"merge, then rebase"| PR2
        PR2 -->|"merge, then rebase"| PR4
    end

    style PR1 fill:#ff6b6b,color:#fff
    style PR2 fill:#ff6b6b,color:#fff
    style PR3 fill:#ff6b6b,color:#fff
    style PR4 fill:#339af0,color:#fff
    style PR5 fill:#339af0,color:#fff
    style PR6 fill:#fcc419,color:#333
    style PR7 fill:#fcc419,color:#333
    style PR8 fill:#339af0,color:#fff
    style PR9 fill:#51cf66,color:#fff
```

**Legend:**
- Red = Critical bug fix (P0)
- Blue = Performance improvement (P0-PERF / P2-PERF)
- Yellow = Reliability / safety fix (P1)
- Green = Cleanup (P3)

---

## Detailed Step-by-Step Execution

### Day 1 — Submit Everything You Can

**Step 1: Submit all 6 independent PRs simultaneously**

These touch unique files — no conflict risk:

| PR | Branch | Title |
|----|--------|-------|
| 3 | `fix/js-component-bugs` | Fix Pressability hover timeout and tabIndex focusable mapping on Windows |
| 5 | `perf/hit-testing-and-scroll` | Eliminate O(n²) hit testing and optimize snap scroll configuration |
| 6 | `fix/textinput-reliability` | Improve TextInput reliability: thread-safe loading, null safety, and use-after-free fix |
| 7 | `fix/threading-and-error-handling` | Fix Timing data race and remove duplicate image error allocation |
| 8 | `perf/data-structure-optimizations` | Use unordered_set for animated node and component registry lookups |
| 9 | `chore/dead-code-cleanup` | Clean up dead code in ScrollView and simplify Modal event emitter init |

**Step 2: Submit first PR in the CompositionEventHandler chain**

| PR | Branch | Title |
|----|--------|-------|
| 1 | `fix/touch-event-handling` | Fix touch event handling: device type detection, screenPoint coordinates, and cancel W3C compliance |

---

### Ongoing — As Chain PRs Merge

```
┌─────────────────────────────────────────────────────────────┐
│ CHAIN: PR 1 → PR 2 → PR 4                                  │
│                                                             │
│ After PR 1 merges:                                          │
│   git fetch upstream                                        │
│   git checkout fix/root-component-view-null-safety           │
│   git rebase upstream/main                                  │
│   git push origin fix/root-component-view-null-safety --force-with-lease │
│   → Create upstream PR for PR 2                             │
│                                                             │
│ After PR 2 merges:                                          │
│   git fetch upstream                                        │
│   git checkout perf/pointer-event-handling                  │
│   git rebase upstream/main                                  │
│   git push origin perf/pointer-event-handling --force-with-lease │
│   → Create upstream PR for PR 4                             │
│                                                             │
│ After PR 4 merges:                                          │
│   → All 9 PRs complete!                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Timeline Estimate

Assuming upstream reviews take 2-5 business days per PR:

| Week | What Happens |
|------|-------------|
| **Week 1** | Submit all 6 independent PRs + PR 1 (chain starter). 7 PRs open for review. |
| **Week 2** | Independent PRs merge. PR 1 merges → submit PR 2. |
| **Week 3** | PR 2 merges → submit PR 4. |
| **Week 4** | PR 4 merges. All 9 PRs complete. |

**Optimistic (fast reviews):** 2-3 weeks  
**Realistic:** 3-4 weeks

---

## Alternative: Submit Chain PRs Early With Dependencies

Submit all 3 CompositionEventHandler PRs at once, noting dependencies:

```markdown
## Dependencies
This PR depends on #XX. Please merge that first.
```

This lets reviewers see the full scope and potentially batch-approve. You'll still need to rebase as each merges, but it parallelizes review time.
