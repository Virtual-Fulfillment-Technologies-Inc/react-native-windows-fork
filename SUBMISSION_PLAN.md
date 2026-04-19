# PR Submission Plan — React Native Windows

## Priority Legend

| Priority | Meaning |
|----------|---------|
| P0 | Critical — crashes, broken core functionality |
| P0-PERF | Critical performance — O(n²) hot paths at 60Hz |
| P1 | High — data races, use-after-free, incorrect behavior |
| P2-PERF | Medium performance — suboptimal lookups |
| P3 | Low — code quality, cleanup |

---

## Step 1: Add Upstream Remote

```bash
git remote add upstream https://github.com/microsoft/react-native-windows.git
```

Skip if already configured.

---

## Step 2: Rebase All Branches onto Upstream Main

```bash
git fetch upstream

git checkout fix/touch-event-handling && git rebase upstream/main
git checkout fix/root-component-view-null-safety && git rebase upstream/main
git checkout fix/js-component-bugs && git rebase upstream/main
git checkout perf/pointer-event-handling && git rebase upstream/main
git checkout perf/hit-testing-and-scroll && git rebase upstream/main
git checkout fix/textinput-reliability && git rebase upstream/main
git checkout fix/threading-and-error-handling && git rebase upstream/main
git checkout perf/data-structure-optimizations && git rebase upstream/main
git checkout chore/dead-code-cleanup && git rebase upstream/main
```

Resolve any conflicts as they come up.

---

## Step 3: Push All Branches to Your Fork

```bash
git push origin \
  fix/touch-event-handling \
  fix/root-component-view-null-safety \
  fix/js-component-bugs \
  perf/pointer-event-handling \
  perf/hit-testing-and-scroll \
  fix/textinput-reliability \
  fix/threading-and-error-handling \
  perf/data-structure-optimizations \
  chore/dead-code-cleanup
```

---

## Step 4: Create Upstream PRs for All Independent + Chain Starter

Open 7 PRs against `microsoft/react-native-windows` on Day 1:

| PR | Branch | Title | Priority |
|----|--------|-------|----------|
| **1** | `fix/touch-event-handling` | Fix touch event handling: device type detection, screenPoint coordinates, and cancel W3C compliance | **P0** |
| **3** | `fix/js-component-bugs` | Fix Pressability hover timeout and tabIndex focusable mapping on Windows | **P0** |
| **5** | `perf/hit-testing-and-scroll` | Eliminate O(n²) hit testing and optimize snap scroll configuration | **P0-PERF** |
| **6** | `fix/textinput-reliability` | Improve TextInput reliability: thread-safe loading, null safety, and use-after-free fix | **P1** |
| **7** | `fix/threading-and-error-handling` | Fix Timing data race and remove duplicate image error allocation | **P1** |
| **8** | `perf/data-structure-optimizations` | Use unordered_set for animated node and component registry lookups | **P2-PERF** |
| **9** | `chore/dead-code-cleanup` | Clean up dead code in ScrollView and simplify Modal event emitter init | **P3** |

---

## Step 5: After PR 1 Merges — Submit PR 2

```bash
git fetch upstream
git checkout fix/root-component-view-null-safety
git rebase upstream/main
git push origin fix/root-component-view-null-safety --force-with-lease
```

| PR | Branch | Title | Priority |
|----|--------|-------|----------|
| **2** | `fix/root-component-view-null-safety` | Add null safety to RootComponentView() to prevent crash during island teardown | **P0** |

---

## Step 6: After PR 2 Merges — Submit PR 4

```bash
git fetch upstream
git checkout perf/pointer-event-handling
git rebase upstream/main
git push origin perf/pointer-event-handling --force-with-lease
```

| PR | Branch | Title | Priority |
|----|--------|-------|----------|
| **4** | `perf/pointer-event-handling` | Optimize pointer event handling: unordered_set for capture tracking and event path caching | **P0-PERF** |

---

## Step 7: Done

All 9 PRs merged.

---

## Full Priority Summary

| Priority | PRs | Count |
|----------|-----|-------|
| **P0** | 1, 2, 3 | 3 |
| **P0-PERF** | 4, 5 | 2 |
| **P1** | 6, 7 | 2 |
| **P2-PERF** | 8 | 1 |
| **P3** | 9 | 1 |
| **Total** | | **9** |
