# React Native Windows - Comprehensive Bug & Performance Review Plan

**Date:** 2026-04-17  
**Branch:** 0.82-stable  
**Reviewer:** Staff Engineer Review (automated analysis + manual verification)

---

## Cross-Reference: PR #2 (`fix/text-input-touch-issues`, merged into 0.82-stable)

PR #2 already fixed several issues. The plan below excludes those, but notes where PR #2 *introduced* new bugs. For reference, PR #2 fixed:

- **Stale pointer ID handling** — added `DispatchSynthesizedTouchCancelForActiveTouch()` + cleanup logic
- **Touch released outside view** — added cancel dispatch when `tag == -1`
- **Null emitter guard** — added early return when no eventEmitter found for a touch
- **TextInput non-mouse pointer events** — changed from `WM_POINTER*` to `WM_LBUTTON*` messages (workaround)
- **wParam clobbering** — changed `wParam =` to `wParam |=` preserving X-button flags (lines 700, 769)
- **Alt key checking wrong VirtualKey** — `VirtualKey::Control` → `VirtualKey::Menu` for alt detection (line 937)
- **Duplicate altKey in submit check** — replaced second `!submitKeyEvent.altKey` with `!submitKeyEvent.ctrlKey` (line 947)
- **OnTxSetCursor outside null check** — moved inside `if (m_textServices)` block
- **Missing PointerExited unregistration** — added in destructor (line 361)

**However**, PR #2 introduced:
- **T3 below** — `DispatchSynthesizedTouchCancelForActiveTouch()` uses per-emitter touches filtering, inconsistent with `DispatchTouchEvent()` and the W3C spec

---

## Priority Legend

- **P0 (Critical):** Causes crashes, data corruption, or fundamentally broken behavior
- **P1 (High):** Significant incorrect behavior visible to users
- **P2 (Medium):** Performance degradation or edge-case bugs
- **P3 (Low):** Code quality, minor inconsistencies

---

## SECTION 1: TOUCH HANDLING BUGS

### T1. Hardcoded Touch Type — All touches report as Mouse [P0]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:1213`

```cpp
activeTouch.touchType = UITouchType::Mouse;
```

**Problem:** In `onPointerPressed()`, the touch type is unconditionally set to `UITouchType::Mouse` regardless of the actual pointer device type. The `pointerPoint` object exposes `PointerDeviceType()` (pen, touch, mouse) but it is never consulted. This means pen and touch-screen inputs are misclassified as mouse events, breaking any JS-side logic that branches on touch type.

**Fix:** Read `pointerPoint.PointerDeviceType()` and map:
- `PointerDeviceType::Touch` → `UITouchType::Touch`
- `PointerDeviceType::Pen` → `UITouchType::Pen`
- `PointerDeviceType::Mouse` → `UITouchType::Mouse`

**Reference:** `WindowsTextInputComponentView.cpp:676,749,822` already reads `PointerDeviceType()` correctly — use the same pattern.

---

### T2. screenPoint set to local coordinates instead of screen coordinates [P0]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:974-977`

```cpp
activeTouch.touch.screenPoint.x = ptLocal.x;  // BUG: should be screen coords
activeTouch.touch.screenPoint.y = ptLocal.y;  // BUG: should be screen coords
activeTouch.touch.offsetPoint.x = ptLocal.x;  // correct
activeTouch.touch.offsetPoint.y = ptLocal.y;  // correct
```

**Problem:** `screenPoint` and `offsetPoint` are both set to `ptLocal` (element-local coordinates). Per W3C spec:
- `pagePoint` = document-relative (set to `ptScaled` — correct)
- `screenPoint` = monitor screen-relative (set to `ptLocal` — **wrong**)
- `offsetPoint` = element-local (set to `ptLocal` — correct)

Any JS code using `event.screenX`/`event.screenY` (e.g., drag-and-drop, tooltip positioning, multi-monitor layouts) receives incorrect values.

**Fix:** Compute actual screen coordinates from the window position + pointer position. Use `pointerPoint.Position()` mapped to screen space or query window screen offset.

---

### T3. Touch cancel event has incomplete touches array (violates W3C spec) [P0]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:1490-1500`

```cpp
for (const auto &pair : m_activeTouches) {
    if (!pair.second.eventEmitter || pair.second.eventEmitter != cancelledTouch.eventEmitter) {
        continue;  // BUG: skips touches from other emitters
    }
    touchEvent.touches.insert(pair.second.touch);
}
```

**Problem:** `DispatchSynthesizedTouchCancelForActiveTouch()` only includes touches from the *same* event emitter in the `touches` array. But `DispatchTouchEvent()` at lines 1578-1588 includes **all** active touches regardless of emitter. Per W3C spec, `touches` should contain all active touches on the surface, not just those for the current element.

**Impact:** Multi-touch gestures spanning multiple components (e.g., two-finger pinch across overlapping views) receive incomplete touch lists, causing gesture recognizers to malfunction.

**Fix:** Change the filter at line 1491 to include all active touches (matching the pattern at line 1578-1588).

---

### T4. Stale pointer ID reuse dispatches buggy cancel [P1] *(depends on T3)*

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:1184-1193`

**Problem:** PR #2 added stale pointer cleanup (previously it just returned early). The cancel is dispatched via `DispatchSynthesizedTouchCancelForActiveTouch()` which has the per-emitter bug from T3.

**Fix:** Fix T3 first; this resolves automatically.

---

### T5. Touch released outside view dispatches buggy cancel [P1] *(depends on T3)*

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:1292-1298`

**Problem:** PR #2 added cancel dispatch when `tag == -1` (previously it just returned). The cancel goes through the buggy `DispatchSynthesizedTouchCancelForActiveTouch()`.

**Fix:** Fix T3 first; this resolves automatically.

---

### T6. DPI scaling may be incorrect for captured pointer coordinates [P2]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:1040-1041`

```cpp
ptLocal.x = ptScaled.x - (clientRect.left / strongRootView.ScaleFactor());
ptLocal.y = ptScaled.y - (clientRect.top / strongRootView.ScaleFactor());
```

**Problem:** `clientRect` coordinates are divided by `ScaleFactor()`, but it's unclear whether `clientRect` is in physical or logical pixels. If `clientRect` is already in logical pixels, the division produces incorrect coordinates on high-DPI displays (125%, 150%, 200%).

**Fix:** Verify whether `getClientRect()` returns physical or logical pixels and adjust the math accordingly. Add a unit test with non-100% DPI.

---

### T7. Dead code: unused pointer device type in ScrollView [P2]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/ScrollViewComponentView.cpp:984-985`

```cpp
auto f = args.Pointer();
auto g = f.PointerDeviceType();  // retrieved but never used
```

**Problem:** Pointer device type is fetched but discarded. Likely an incomplete implementation — scroll behavior should differ for touch (inertia/panning) vs. mouse (discrete scroll) vs. pen.

**Fix:** Either implement device-type-specific scroll behavior or remove the dead code.

---

## SECTION 2: PERFORMANCE BOTTLENECKS

### P1. O(n) linear child insertion and access in composition visual tree [P0-PERF]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionContextHelper.cpp:431-458`

```cpp
void InsertAt(..., uint32_t index) {
    auto insertAfter = containerChildren.First();
    for (uint32_t i = 1; i < index; i++)
        insertAfter.MoveNext();  // O(n) walk per insertion
}

IVisual GetAt(uint32_t index) {
    auto it = containerChildren.First();
    for (uint32_t i = 0; i < index; i++)
        it.MoveNext();  // O(n) walk per access
}
```

**Problem:** Every child insertion or access requires iterating from the head of the children collection. With N children, inserting at position K costs O(K). Building a tree of N children costs O(N²). This is called from hit testing (every touch event), scroll view initialization, and layout updates.

**Additional occurrences:** Lines 858, 872, 1786, 1800 (same pattern in other template specializations).

**Fix:** Maintain a parallel `std::vector` or indexed cache of visual children to enable O(1) access. Alternatively, use `InsertAbove`/`InsertBelow` relative to a cached reference rather than by index.

---

### P2. O(n) pointer capture lookup on every pointer event at 60Hz [P0-PERF]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:1032`

```cpp
if (std::find(m_capturedPointers.begin(), m_capturedPointers.end(), pointerId) != m_capturedPointers.end())
```

**Problem:** `m_capturedPointers` is a `std::vector` searched linearly on every pointer move, press, and release event. At 60Hz with active touch, this runs 60+ times per second.

**Fix:** Replace `std::vector<PointerId>` with `std::unordered_set<PointerId>` for O(1) lookup. The collection is small, but the frequency is extreme.

---

### P3. O(n) hover view tracking with linear search on every pointer move [P1-PERF]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:728-729, 774`

```cpp
if (std::find(currentlyHoveredViews.begin(), currentlyHoveredViews.end(), componentView) ==
    currentlyHoveredViews.end()) { ... }
```

**Problem:** Two linear searches per pointer move event: one to check enter (728-729), one to check leave (774). For a 10-level view hierarchy with 5 pointer events per second, that's 100+ linear searches per second.

**Fix:** Use `std::unordered_set` for `currentlyHoveredViews` and `eventPathViews`.

---

### P4. Full event path reconstruction (root walk) on every pointer event [P1-PERF]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:664-680`

```cpp
auto view = componentView;
while (view) {
    if (winrt::get_self<ComponentView>(view)->eventEmitter()) {
        results.push_back(view);
    }
    view = view.Parent();  // tree walk to root
}
```

**Problem:** Called at lines 708, 1102, 1164 — every mouse enter/leave and touch start/end triggers a full walk from target to root. For a 10-level deep tree at 60Hz, this is 600+ tree traversals/second.

**Fix:** Cache the event path and invalidate only when the tree structure changes. Most pointer moves hit the same or nearby nodes.

---

### P5. O(n²) hit testing due to GetAt() inside recursive traversal [P0-PERF]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionViewComponentView.cpp:1083-1099`

```cpp
do {
    index--;
    targetTag = winrt::get_self<ComponentView>(m_children.GetAt(index))  // GetAt is O(n)!
                    ->hitTest(ptContent, localPt);
} while (index != 0);
```

**Problem:** `anyHitTestHelper` iterates children in reverse, calling `GetAt(index)` which itself is O(n) (see P1). For a view with 20 children, each hit test does 20 × O(20) = O(400) iterations. Recursively through a 10-level tree, this compounds to O(n²) or worse. Hit testing runs on every pointer event.

**Fix:** Use a pre-built `std::vector` of children for O(1) indexed access, or iterate using the children collection's iterator directly rather than by index.

---

### P6. O(n) animated node child lookups on every animation frame [P2-PERF]

**File:** `vnext/Microsoft.ReactNative/Modules/Animated/AnimatedNode.cpp:32, 37`

```cpp
m_children.erase(std::find(m_children.begin(), m_children.end(), tag));  // O(n) find + erase

if (std::find(m_children.begin(), m_children.end(), tag) != m_children.end()) {  // O(n) find
```

**Problem:** Animation node graph uses linear search for child lookup and removal. With 30+ animated nodes updating at 60fps, that's 1800+ linear searches per second.

**Fix:** Use `std::unordered_set<int64_t>` for `m_children`.

---

### P7. O(n) component descriptor registry lookup [P2-PERF]

**File:** `vnext/Microsoft.ReactNative/Fabric/WindowsComponentDescriptorRegistry.cpp:54`

```cpp
return std::find(m_componentNames.begin(), m_componentNames.end(), name) != m_componentNames.end();
```

**Problem:** `hasComponentProvider()` does a linear search through component names. Called during tree reconciliation for every component creation.

**Fix:** Use `std::unordered_set<std::string>` for `m_componentNames`.

---

### P8. Snap scrolling does sort + unique + object creation on every layout update [P3-PERF]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionContextHelper.cpp:1255-1356`

**Problem:** `std::sort()` + `std::unique()` + creation of `InteractionTrackerInertiaRestingValue` objects for every snap point, on every layout update. For paginated content with 50+ pages, this is wasteful if snap points haven't changed.

**Fix:** Diff against previous snap points and only reconfigure when changed.

---

## SECTION 3: C++ BUGS

### C1. Null pointer dereference in RootComponentView() — 16+ crash sites [P0]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp:384-388`

```cpp
winrt::Microsoft::ReactNative::Composition::implementation::RootComponentView &
CompositionEventHandler::RootComponentView() const noexcept {
    auto island = m_wkRootView.get();  // weak_ref — can be null!
    return *winrt::get_self<...>(island)->GetComponentView();  // dereferences without check
}
```

**Problem:** `m_wkRootView` is a weak reference that returns null if the `ReactNativeIsland` has been destroyed. No null check exists. This method is called from **16+ locations** (lines 253, 279, 306, 333, 402, 403, 557, 580, 612, 635, 645, 655, 1030, 1044, 1106, 1132, 1179, 1548). Any pointer/keyboard/wheel event arriving after island teardown causes a crash.

**Fix:** Add null check, return `std::optional` or throw, and guard all 16+ call sites.

---

### C2. Thread-unsafe static globals in RichEdit library loading [P1]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/TextInput/WindowsTextInputComponentView.cpp:78-90`

```cpp
static HINSTANCE g_hInstRichEdit = nullptr;
static PCreateTextServices g_pfnCreateTextServices;

HRESULT HrEnsureRichEd20Loaded() noexcept {
    if (g_hInstRichEdit == nullptr) {       // TOCTOU race
        g_hInstRichEdit = LoadLibrary(...);
        g_pfnCreateTextServices = (PCreateTextServices)GetProcAddress(...);
    }
}
```

**Problem:** Two static globals accessed without synchronization. Concurrent TextInput creation from multiple threads can cause double `LoadLibrary` or a stale `g_pfnCreateTextServices` pointer.

**Fix:** Use `std::call_once` with `std::once_flag`.

---

### C3. Race condition on m_usingRendering flag in Timing module [P1]

**File:** `vnext/Microsoft.ReactNative/Modules/Timing.cpp` — lines 117, 144, 159, 161, 198, 202, 221, 236, 244, 269

**Problem:** `m_usingRendering` is a plain `bool` read and written from multiple threads/dispatcher callbacks: `OnTick()`, `PostRenderFrame()`, `StartRendering()`, `StartDispatcherTimer()`, `StopTicks()`, `createTimerOnQueue()`. No synchronization.

**Impact:** Lost updates can cause missed animation frames (jank) or duplicate timer processing.

**Fix:** Change to `std::atomic<bool>`.

---

### C4. Duplicate errorInfo allocation — error message may be lost [P1]

**File:** `vnext/Microsoft.ReactNative/Fabric/WindowsImageManager.cpp:74-76`

```cpp
auto errorInfo = std::make_shared<facebook::react::ImageErrorInfo>();
errorInfo = std::make_shared<facebook::react::ImageErrorInfo>();  // DUPLICATE — overwrites first
errorInfo->error = ::Microsoft::ReactNative::FormatHResultError(winrt::hresult_error(ex));
```

**Problem:** `errorInfo` is allocated twice. The first allocation is immediately leaked (overwritten). While line 76 does assign the error string, the duplicate allocation is wasteful and confusing. This was likely a merge artifact.

**Fix:** Remove the duplicate line 75.

---

### C5. Unchecked m_textServices usage after potentially failed initialization [P2]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/TextInput/WindowsTextInputComponentView.cpp:1836-1837`

**Problem:** If `CreateTextServices` fails, `m_textServices` remains null. Many call sites check for null (lines 710, 775, 830, 848, 1049, 1078), but **26+ call sites do not** (lines 571, 1025, 1180, 1263, 1265, 1269, 1273, 1283, 1329, 1392, 1393, 1416, 1441, 1666, 1764, 1784, 1885, 1890, 1897, 1903, 1912, 1937, 1961, 1964, 1966, 1969).

**Fix:** Either fail hard in `createVisual()` if text services can't be created, or add null checks to all TxSendMessage call sites.

---

### C6. CompTextHost holds raw `this` pointer — dangling if parent destroyed [P2]

**File:** `vnext/Microsoft.ReactNative/Fabric/Composition/TextInput/WindowsTextInputComponentView.cpp:1835`

```cpp
m_textHost = winrt::make<CompTextHost>(this);
```

**Problem:** `CompTextHost` stores a raw pointer to the `WindowsTextInputComponentView`. If the parent is destroyed before `CompTextHost` (e.g., due to async text services callbacks), the pointer dangles. Callbacks like `TxInvalidateRect()`, `TxViewChange()` would use-after-free.

**Fix:** Use weak reference or ensure CompTextHost lifetime is strictly bounded by parent.

---

## SECTION 4: JAVASCRIPT/TYPESCRIPT BUGS

### J1. Hover timeout assigned to wrong variable [P0]

**File:** `vnext/Libraries/Pressability/Pressability.windows.js:733`

```javascript
this._hoverInDelayTimeout = setTimeout(() => {
    onHoverOut(event);
}, delayHoverOut);
```

**Problem:** When scheduling a hover-out delay, the timeout is stored in `_hoverInDelayTimeout` instead of `_hoverOutDelayTimeout`. This means:
1. The hover-in timeout gets overwritten, so hover-in can fire unexpectedly
2. The hover-out timeout is never properly tracked, so it can't be cancelled
3. Calling `_cancelHoverOutDelayTimeout()` (line 725) won't cancel this timeout

**Fix:** Change `_hoverInDelayTimeout` to `_hoverOutDelayTimeout`.

---

### J2. Operator precedence bug in onStartShouldSetResponder [P0]

**File:** `vnext/Libraries/Pressability/Pressability.windows.js:483`

```javascript
onStartShouldSetResponder: (): boolean => {
    const {disabled} = this._config;
    return !disabled ?? true;
},
```

**Problem:** `!disabled ?? true` is parsed as `(!disabled) ?? true`. Since `!disabled` always produces a boolean (`true` or `false`), it is **never** `null` or `undefined`, so `?? true` is dead code. The expression always returns `!disabled`. While the end result may be accidentally correct (return true when not disabled), the intent was likely `!(disabled ?? true)` — default to disabled if undefined. As written, `disabled = undefined` → `!undefined` → `true` (becomes responder), which may be the desired behavior but the code is misleading.

**Fix:** Clarify intent. If the intent is "default to not-disabled": `return !(disabled ?? false)`. If "default to disabled": `return !(disabled ?? true)`. Remove the misleading `??`.

---

### J3. tabIndex to focusable conversion is inverted [P0]

**File:** `vnext/Libraries/Components/View/View.windows.js:147`

```javascript
if (tabIndex !== undefined) {
    processedProps.focusable = !tabIndex;
}
```

**Problem:** Per ARIA/web standards: `tabIndex={0}` means focusable, `tabIndex={-1}` means programmatically focusable only. The `!` operator inverts this:
- `tabIndex={0}` → `!0` → `true` (accidentally correct — 0 is falsy)
- `tabIndex={-1}` → `!(-1)` → `false` (accidentally correct — -1 is truthy)
- `tabIndex={1}` → `!1` → `false` (**WRONG** — should be focusable)
- `tabIndex={2}` → `!2` → `false` (**WRONG** — should be focusable)

Any positive tabIndex > 0 incorrectly makes the view non-focusable.

**Fix:** `processedProps.focusable = tabIndex >= 0;`

---

### J4. Modal event emitter has redundant/confusing platform check [P3]

**File:** `vnext/Libraries/Modal/Modal.windows.js:41-47`

**Problem:** Nested ternary re-checks platform after outer guard already narrowed it. Not a runtime bug but maintenance hazard. Simplify.

---

## SECTION 5: PR PLAN (upstream contributions)

> **Note:** The original review identified 23 issues across 18 individual PRs. These have been consolidated into **9 PRs** grouped by related concerns to reduce review overhead, minimize merge conflicts, and keep each PR self-contained. PR 17 (DPI scaling / T6) was dropped after investigation confirmed the existing code is correct.

---

### PR 1: Fix touch event handling — `fix/touch-event-handling`
**Issues:** T1, T2, T3 (also resolves T4, T5)  
**Priority:** P0 — Critical  
**Commits:** 3  
**Files changed:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp`, `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.h`  
**Dependency:** None (chain starter — PRs 2 and 4 depend on this)

**What's fixed:**
1. **Touch type detection (T1):** All pointer events were hardcoded as `UITouchType::Mouse`. Added switch on `pointerPoint.PointerDeviceType()` to correctly map Touch/Pen/Mouse.
2. **screenPoint coordinates (T2):** `screenPoint` was set to `ptLocal` (element-local) instead of `ptScaled` (scaled page coordinates). Fixed to use `ptScaled`.
3. **Touch cancel W3C compliance (T3):** `DispatchSynthesizedTouchCancelForActiveTouch()` filtered `touches` to only the same emitter. Changed to include all active touches per W3C spec (only `targetTouches` is per-emitter).

**PR title:** `Fix touch event handling: device type detection, screenPoint coordinates, and cancel W3C compliance`

---

### PR 2: Add null safety to RootComponentView — `fix/root-component-view-null-safety`
**Issues:** C1  
**Priority:** P0 — Critical  
**Commits:** 1  
**Files changed:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp`, `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.h`  
**Dependency:** PR 1 must merge first (same files)

**What's fixed:**
- `RootComponentView()` dereferenced a `weak_ref` without null checking. Changed return type from reference to pointer. Added null guards at all 18 call sites. Prevents crashes during island teardown when pointer/keyboard events arrive after `ReactNativeIsland` is destroyed.

**PR title:** `Add null safety to RootComponentView() to prevent crash during island teardown`

---

### PR 3: Fix JS component bugs — `fix/js-component-bugs`
**Issues:** J1, J2, J3  
**Priority:** P0 — Critical  
**Commits:** 2  
**Files changed:** `vnext/Libraries/Pressability/Pressability.windows.js`, `vnext/Libraries/Components/View/View.windows.js`  
**Dependency:** None

**What's fixed:**
1. **Pressability hover timeout (J1):** `this._hoverInDelayTimeout` was used instead of `this._hoverOutDelayTimeout`, causing hover-out timeout to overwrite hover-in and never be cancellable.
2. **Dead nullish coalescing (J2):** `!disabled ?? true` — the `??` is dead code since `!disabled` always produces a boolean. Simplified to `!disabled`.
3. **tabIndex focusable mapping (J3):** `!tabIndex` used boolean negation, which breaks for positive tabIndex values (1, 2, etc. become non-focusable). Changed to `tabIndex >= 0`.

**PR title:** `Fix Pressability hover timeout and tabIndex focusable mapping on Windows`

---

### PR 4: Optimize pointer event handling — `perf/pointer-event-handling`
**Issues:** P2, P3, P4  
**Priority:** P0-PERF — Critical performance  
**Commits:** 2  
**Files changed:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp`, `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.h`  
**Dependency:** PR 2 must merge first (same files)

**What's fixed:**
1. **Captured pointer lookup (P2):** Changed `m_capturedPointers` from `std::vector<PointerId>` to `std::unordered_set<PointerId>` for O(1) lookups instead of O(n) `std::find()`.
2. **Event path caching (P4):** Added single-entry cache (`m_cachedEventPathTag` + `m_cachedEventPath`) to `GetTouchableViewsInPathToRoot()` to avoid 600+ tree walks/sec on pointer events.

**PR title:** `Optimize pointer event handling: unordered_set for capture tracking and event path caching`

---

### PR 5: Eliminate O(n²) hit testing and optimize scroll — `perf/hit-testing-and-scroll`
**Issues:** P1, P5, P8  
**Priority:** P0-PERF — Critical performance  
**Commits:** 2  
**Files changed:** `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionContextHelper.cpp`, `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionViewComponentView.cpp`  
**Dependency:** None

**What's fixed:**
1. **O(n²) hit testing (P1, P5):** `InsertAt()`/`GetAt()` on Windows Composition children is O(n) linked-list iteration. Added parallel `std::vector` cache for O(1) indexed access. `anyHitTestHelper()` now collects children into a local vector instead of calling `GetAt(index)` in a loop.
2. **Snap scroll reconfiguration (P8):** Added `m_previousSnapPositions` cache to skip sorting/deduplication/InteractionTracker recreation when snap points haven't changed.

**PR title:** `Eliminate O(n²) hit testing and optimize snap scroll configuration`

---

### PR 6: Improve TextInput reliability — `fix/textinput-reliability`
**Issues:** C2, C5, C6  
**Priority:** P1 — High  
**Commits:** 2  
**Files changed:** `vnext/Microsoft.ReactNative/Fabric/Composition/TextInput/WindowsTextInputComponentView.cpp`, `vnext/Microsoft.ReactNative/Fabric/Composition/TextInput/WindowsTextInputComponentView.h`  
**Dependency:** None

**What's fixed:**
1. **Thread-safe RichEdit loading (C2):** Replaced bare `if (g_hInstRichEdit == nullptr)` with `std::call_once` + `std::once_flag` to prevent race conditions on concurrent TextInput creation.
2. **Null-safe text services (C5):** Added early return if `CreateTextServices` fails, preventing 26+ unchecked call sites from crashing.
3. **CompTextHost use-after-free (C6):** `CompTextHost` stored a raw `this` pointer to the parent view. Added `Detach()` method called from destructor, plus null checks in all 16 callbacks to prevent dangling pointer access.

**PR title:** `Improve TextInput reliability: thread-safe loading, null safety, and use-after-free fix`

---

### PR 7: Fix threading and error handling — `fix/threading-and-error-handling`
**Issues:** C3, C4  
**Priority:** P1 — High  
**Commits:** 2  
**Files changed:** `vnext/Microsoft.ReactNative/Modules/Timing.h`, `vnext/Microsoft.ReactNative/Fabric/WindowsImageManager.cpp`  
**Dependency:** None

**What's fixed:**
1. **Timing data race (C3):** Changed `m_usingRendering` from `bool` to `std::atomic<bool>`. Accessed from 10 locations across multiple dispatcher callbacks with no synchronization.
2. **Duplicate error allocation (C4):** Removed duplicate `auto errorInfo = std::make_shared<...>()` line in image loading error handler (likely a merge artifact).

**PR title:** `Fix Timing data race and remove duplicate image error allocation`

---

### PR 8: Data structure optimizations — `perf/data-structure-optimizations`
**Issues:** P6, P7  
**Priority:** P2-PERF — Medium performance  
**Commits:** 2  
**Files changed:** `vnext/Microsoft.ReactNative/Modules/Animated/AnimatedNode.cpp`, `vnext/Microsoft.ReactNative/Modules/Animated/AnimatedNode.h`, `vnext/Microsoft.ReactNative/Fabric/WindowsComponentDescriptorRegistry.cpp`, `vnext/Microsoft.ReactNative/Fabric/WindowsComponentDescriptorRegistry.h`  
**Dependency:** None

**What's fixed:**
1. **AnimatedNode children (P6):** Changed `m_children` from `std::vector<int64_t>` to `std::unordered_set<int64_t>` for O(1) child lookup and removal.
2. **Component descriptor registry (P7):** Changed `m_componentNames` from `std::vector<std::string>` to `std::unordered_set<std::string>` for O(1) `hasComponentProvider()` lookups.

**PR title:** `Use unordered_set for animated node and component registry lookups`

---

### PR 9: Dead code cleanup — `chore/dead-code-cleanup`
**Issues:** T7, J4  
**Priority:** P3 — Low  
**Commits:** 1  
**Files changed:** `vnext/Microsoft.ReactNative/Fabric/Composition/ScrollViewComponentView.cpp`, `vnext/src-win/Libraries/Modal/Modal.windows.js`  
**Dependency:** None

**What's fixed:**
1. **ScrollView dead code (T7):** Removed unused `auto f = args.Pointer(); auto g = f.PointerDeviceType();` variables.
2. **Modal event emitter (J4):** Simplified redundant nested ternary platform check in `NativeEventEmitter` constructor initialization.

**PR title:** `Clean up dead code in ScrollView and simplify Modal event emitter init`

---

### PR DEPENDENCY GRAPH

```
Group A — CompositionEventHandler.cpp/.h (3 PRs, must be sequential):
  PR 1 (touch fixes) → PR 2 (null safety) → PR 4 (pointer perf)

Group B — Independent (6 PRs, submit in parallel):
  PR 3, PR 5, PR 6, PR 7, PR 8, PR 9
```

Submit all Group B PRs + PR 1 on Day 1 (7 PRs total). After PR 1 merges, rebase and submit PR 2. After PR 2 merges, rebase and submit PR 4.

### SUMMARY

| PR | Branch | Title | Issues | Priority |
|----|--------|-------|--------|----------|
| 1 | `fix/touch-event-handling` | Touch type, screenPoint, cancel compliance | T1, T2, T3 | **P0** |
| 2 | `fix/root-component-view-null-safety` | RootComponentView null safety | C1 | **P0** |
| 3 | `fix/js-component-bugs` | Pressability hover + tabIndex focusable | J1, J2, J3 | **P0** |
| 4 | `perf/pointer-event-handling` | Captured pointer set + event path cache | P2, P3, P4 | **P0-PERF** |
| 5 | `perf/hit-testing-and-scroll` | O(n²) hit testing + snap scroll | P1, P5, P8 | **P0-PERF** |
| 6 | `fix/textinput-reliability` | Thread-safe loading + null safety + use-after-free | C2, C5, C6 | **P1** |
| 7 | `fix/threading-and-error-handling` | Timing atomic + image error duplicate | C3, C4 | **P1** |
| 8 | `perf/data-structure-optimizations` | AnimatedNode + component registry sets | P6, P7 | **P2-PERF** |
| 9 | `chore/dead-code-cleanup` | ScrollView dead code + Modal simplification | T7, J4 | **P3** |

**Total: 9 PRs covering 22 issues** (T6 DPI scaling dropped — confirmed correct after investigation)

---

## FILES INDEX

Key files requiring changes (sorted by number of issues):

| File | Issues |
|------|--------|
| `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp` | T1, T2, T3, C1, P2, P4 |
| `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.h` | C1, P2, P4 |
| `vnext/Microsoft.ReactNative/Fabric/Composition/TextInput/WindowsTextInputComponentView.cpp` | C2, C5, C6 |
| `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionContextHelper.cpp` | P1, P8 |
| `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionViewComponentView.cpp` | P5 |
| `vnext/Libraries/Pressability/Pressability.windows.js` | J1, J2 |
| `vnext/Libraries/Components/View/View.windows.js` | J3 |
| `vnext/Microsoft.ReactNative/Modules/Animated/AnimatedNode.cpp` | P6 |
| `vnext/Microsoft.ReactNative/Modules/Animated/AnimatedNode.h` | P6 |
| `vnext/Microsoft.ReactNative/Modules/Timing.h` | C3 |
| `vnext/Microsoft.ReactNative/Fabric/WindowsComponentDescriptorRegistry.cpp` | P7 |
| `vnext/Microsoft.ReactNative/Fabric/WindowsComponentDescriptorRegistry.h` | P7 |
| `vnext/Microsoft.ReactNative/Fabric/WindowsImageManager.cpp` | C4 |
| `vnext/Microsoft.ReactNative/Fabric/Composition/ScrollViewComponentView.cpp` | T7 |
| `vnext/src-win/Libraries/Modal/Modal.windows.js` | J4 |
