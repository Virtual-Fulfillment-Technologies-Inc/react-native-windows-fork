# Branch Mapping — React Native Windows PRs

Each branch contains committed fixes ready to be pushed and submitted as a PR to `microsoft/react-native-windows`.

> **Note:** PRs 1, 2, and 4 all modify `CompositionEventHandler.cpp/.h` — rebase sequentially after each upstream merge. All other PRs are fully independent.

---

| PR | Branch | Commits | Priority | Description |
|----|--------|---------|----------|-------------|
| 1 | `fix/touch-event-handling` | 3 | **P0** | Fix touch type detection (all events were hardcoded as mouse), fix screenPoint using local coords instead of scaled coords, fix touch cancel to include all active touches per W3C spec. |
| 2 | `fix/root-component-view-null-safety` | 1 | **P0** | RootComponentView() dereferenced a weak_ref without null checking. Changed return type to pointer and added null guards at all 18 call sites to prevent crashes during island teardown. |
| 3 | `fix/js-component-bugs` | 2 | **P0** | Fix Pressability hover-out timeout stored in wrong variable and dead nullish coalescing. Fix tabIndex-to-focusable using boolean negation which broke positive tabIndex values. |
| 4 | `perf/pointer-event-handling` | 2 | **P0-PERF** | Replace O(n) linear search on m_capturedPointers with unordered_set. Cache event path to root to avoid 600+ tree walks/sec on pointer events. |
| 5 | `perf/hit-testing-and-scroll` | 2 | **P0-PERF** | Add parallel vector cache for O(1) child access, eliminating O(n²) hit testing. Skip snap scroll reconfiguration when snap points haven't changed. |
| 6 | `fix/textinput-reliability` | 2 | **P1** | Thread-safe RichEdit loading via std::call_once, early return if text services fail. Fix CompTextHost use-after-free by adding Detach() and null checks in all 16 callbacks. |
| 7 | `fix/threading-and-error-handling` | 2 | **P1** | Change m_usingRendering from bool to std::atomic to fix data race. Remove duplicate errorInfo allocation in image loading error handler. |
| 8 | `perf/data-structure-optimizations` | 2 | **P2-PERF** | Change AnimatedNode::m_children and WindowsComponentDescriptorRegistry::m_componentNames from vector to unordered_set for O(1) lookups. |
| 9 | `chore/dead-code-cleanup` | 1 | **P3** | Remove unused PointerDeviceType variables in ScrollViewComponentView. Simplify redundant nested platform check in Modal event emitter initialization. |

---

## File Conflict Groups

```
Group A — CompositionEventHandler.cpp/.h (submit sequentially):
  PR 1 → PR 2 → PR 4

Group B — All others (submit in parallel):
  PR 3, PR 5, PR 6, PR 7, PR 8, PR 9
```
