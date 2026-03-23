# Global Keyboard Shortcuts in React Native Windows

## Customer Request

> "We would like to detect keyboard shortcuts at application level to trigger actions (for instance: Ctrl+L to go back to the library), but we can't seem to find a way to do this."

This document provides a comprehensive analysis of the current state of keyboard handling in React Native Windows (RNW), existing workarounds to achieve global keyboard shortcuts today, and a proposal for native support.

---

## Table of Contents

1. [Current State of Keyboard Handling](#1-current-state-of-keyboard-handling)
2. [Is There Already a Way? (Yes — Workarounds)](#2-is-there-already-a-way-yes--workarounds)
3. [If We Need Native Support — Proposed Design](#3-if-we-need-native-support--proposed-design)
4. [Relevant Source Files](#4-relevant-source-files)
5. [Summary & Recommendation](#5-summary--recommendation)

---

## 1. Current State of Keyboard Handling

### 1.1 Architecture Overview

React Native Windows keyboard handling is **component-centric and focus-based**. Keyboard events only fire on the currently focused component and then bubble/tunnel through the component tree. There is **no built-in application-level keyboard shortcut manager**.

**Event flow (Fabric/Composition architecture):**

```
Win32 Message (WM_KEYDOWN / WM_KEYUP / WM_SYSKEYDOWN / WM_SYSKEYUP)
    │
    ▼
CompositionEventHandler::SendMessage()
    │
    ▼
CompositionEventHandler::onKeyDown() / onKeyUp()
    │
    ▼
RootComponentView::GetFocusedComponent()
    │
    ▼
ComponentView::OnKeyDown() / OnKeyUp()        ← dispatches to focused component only
    │
    ▼
HostPlatformViewEventEmitter::onKeyDown()      ← emits to JS
    │
    ▼
JS: onKeyDown / onKeyDownCapture / onKeyUp / onKeyUpCapture callbacks
```

### 1.2 Available JS Keyboard APIs

Every `View`, `TextInput`, and `Pressable` component supports these keyboard props:

```typescript
// Callback props
onKeyDown?: (args: IKeyboardEvent) => void;       // Bubble phase
onKeyDownCapture?: (args: IKeyboardEvent) => void; // Capture (tunneling) phase
onKeyUp?: (args: IKeyboardEvent) => void;          // Bubble phase
onKeyUpCapture?: (args: IKeyboardEvent) => void;   // Capture (tunneling) phase

// Declarative handled events (marks events as handled at native level)
keyDownEvents?: IHandledKeyboardEvent[];
keyUpEvents?: IHandledKeyboardEvent[];
```

**Event object shape (`IKeyboardEvent`):**

```typescript
interface INativeKeyboardEvent {
  altKey: boolean;
  ctrlKey: boolean;
  metaKey: boolean;     // Windows key
  shiftKey: boolean;
  key: string;          // W3C key value: "a", "Enter", "Meta", etc.
  code: string;         // W3C code value: "KeyA", "Enter", "MetaLeft", etc.
  eventPhase: number;   // 0=None, 1=Capturing, 2=AtTarget, 3=Bubbling
}
```

### 1.3 Hardcoded Global Shortcuts

Only two "global" shortcuts exist today, hardcoded in `CompositionEventHandler::onKeyDown()`:

| Shortcut | Action | Condition |
|----------|--------|-----------|
| `Shift+Ctrl+D` | Open Developer Menu | DevMode enabled |
| `Tab` / `Shift+Tab` | Move focus forward/backward | Always |

These are processed **after** the focused component has a chance to handle the event, and are implemented in C++ — not exposed to JavaScript.

### 1.4 Key Limitation

**The fundamental limitation is that `CompositionEventHandler::onKeyDown()` dispatches events to the focused component first.** If no component has focus, keyboard events from the JS side are effectively lost. There is no "catch-all" listener at the application level.

---

## 2. Is There Already a Way? (Yes — Workarounds)

While RNW does not have a dedicated global keyboard shortcut API, there are **two practical workarounds** available today.

### Workaround 1: Root View Wrapper with `onKeyDownCapture` (Recommended — JS Only)

Wrap your entire application in a focusable `<View>` that uses the **capture phase** (`onKeyDownCapture`) to intercept all keyboard events before they reach child components. The capture phase fires top-down (from root to target), so a handler on the root will see every keyboard event first.

```tsx
import React, {useCallback} from 'react';
import {View} from 'react-native';
import type {IKeyboardEvent} from 'react-native-windows';

// Define your global shortcuts
const GLOBAL_SHORTCUTS: Record<string, () => void> = {
  'ctrl+KeyL': () => {
    console.log('Navigate to Library');
    // navigation.navigate('Library');
  },
  'ctrl+KeyK': () => {
    console.log('Open Search');
    // openSearchOverlay();
  },
  'ctrl+shift+KeyS': () => {
    console.log('Save All');
    // saveAllDocuments();
  },
};

function buildShortcutKey(e: IKeyboardEvent['nativeEvent']): string {
  const parts: string[] = [];
  if (e.ctrlKey) parts.push('ctrl');
  if (e.shiftKey) parts.push('shift');
  if (e.altKey) parts.push('alt');
  if (e.metaKey) parts.push('meta');
  parts.push(e.code);
  return parts.join('+');
}

export default function App() {
  const handleGlobalKeyDown = useCallback((e: IKeyboardEvent) => {
    const key = buildShortcutKey(e.nativeEvent);
    const action = GLOBAL_SHORTCUTS[key];
    if (action) {
      action();
      // Note: To prevent the event from reaching child components,
      // you can mark it as handled. However, React Native does not
      // natively support stopPropagation on synthetic events.
      // Use keyDownEvents for declarative handled behavior.
    }
  }, []);

  return (
    <View
      style={{flex: 1}}
      focusable={true}
      onKeyDownCapture={handleGlobalKeyDown}
      // Declare which keys this view handles natively (prevents further processing)
      keyDownEvents={[
        {code: 'KeyL', ctrlKey: true, handledEventPhase: 1 /* Capturing */},
        {code: 'KeyK', ctrlKey: true, handledEventPhase: 1},
        {code: 'KeyS', ctrlKey: true, shiftKey: true, handledEventPhase: 1},
      ]}>
      {/* Your actual app content */}
      <YourAppNavigator />
    </View>
  );
}
```

**Pros:**
- Works today, no native changes needed
- Pure JavaScript solution
- Capture phase ensures the root sees events before any child
- `keyDownEvents` with `handledEventPhase: Capturing` prevents events from reaching children

**Cons:**
- Requires a focusable root View (the ReactNativeIsland/window must have focus)
- Slightly inelegant — overloads the root View's purpose
- If the RNW window itself doesn't have focus, shortcuts won't fire (this is expected Win32 behavior)
- The root View must be focusable and in the focus tree

### Workaround 2: Custom Native Module (C++ or C#)

For more robust handling (e.g., shortcuts that work regardless of which component has focus, or even when no React component is focused), write a native module that hooks into the window's message loop or installs a keyboard hook.

**C++ Native Module Example:**

```cpp
// GlobalKeyboardModule.h
#pragma once

#include <NativeModules.h>
#include <winrt/Microsoft.ReactNative.h>
#include <winrt/Windows.System.h>

namespace MyApp {

REACT_MODULE(GlobalKeyboardModule)
struct GlobalKeyboardModule {
  REACT_INIT(Initialize)
  void Initialize(React::ReactContext const &reactContext) noexcept {
    m_reactContext = reactContext;
  }

  // Register a keyboard shortcut from JS
  REACT_METHOD(RegisterShortcut)
  void RegisterShortcut(
      std::string shortcutId,
      std::string code,
      bool ctrlKey,
      bool shiftKey,
      bool altKey) noexcept {
    ShortcutDef def{code, ctrlKey, shiftKey, altKey};
    m_shortcuts[shortcutId] = def;
  }

  // Unregister a shortcut
  REACT_METHOD(UnregisterShortcut)
  void UnregisterShortcut(std::string shortcutId) noexcept {
    m_shortcuts.erase(shortcutId);
  }

  // Called from your app's message loop or subclassed window proc
  void HandleKeyMessage(UINT msg, WPARAM wParam, LPARAM lParam) noexcept {
    if (msg != WM_KEYDOWN && msg != WM_SYSKEYDOWN)
      return;

    bool ctrlDown = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
    bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    bool altDown = (GetKeyState(VK_MENU) & 0x8000) != 0;

    // Convert VirtualKey to code string (simplified)
    std::string code = VirtualKeyToCode(static_cast<int>(wParam));

    for (const auto &[id, def] : m_shortcuts) {
      if (def.code == code &&
          def.ctrlKey == ctrlDown &&
          def.shiftKey == shiftDown &&
          def.altKey == altDown) {
        // Emit event to JS
        OnShortcutPressed(id);
        return;
      }
    }
  }

  // Event emitted to JS when a shortcut is triggered
  REACT_EVENT(OnShortcutPressed)
  std::function<void(std::string)> OnShortcutPressed;

 private:
  struct ShortcutDef {
    std::string code;
    bool ctrlKey = false;
    bool shiftKey = false;
    bool altKey = false;
  };

  React::ReactContext m_reactContext;
  std::map<std::string, ShortcutDef> m_shortcuts;

  std::string VirtualKeyToCode(int vk) noexcept {
    // Map Win32 VK codes to W3C code strings
    // Use KeyboardUtils.h helpers from RNW for complete mapping
    if (vk >= 'A' && vk <= 'Z') {
      return std::string("Key") + static_cast<char>(vk);
    }
    // ... add more mappings as needed
    return "Unknown";
  }
};

} // namespace MyApp
```

**JS side usage:**

```typescript
import {NativeModules, NativeEventEmitter} from 'react-native';

const {GlobalKeyboardModule} = NativeModules;
const emitter = new NativeEventEmitter(GlobalKeyboardModule);

// Register shortcuts
GlobalKeyboardModule.RegisterShortcut('goToLibrary', 'KeyL', true, false, false);
GlobalKeyboardModule.RegisterShortcut('openSearch', 'KeyK', true, false, false);

// Listen for shortcut events
const subscription = emitter.addListener('OnShortcutPressed', (shortcutId: string) => {
  switch (shortcutId) {
    case 'goToLibrary':
      navigation.navigate('Library');
      break;
    case 'openSearch':
      openSearchOverlay();
      break;
  }
});

// Cleanup
subscription.remove();
```

**Pros:**
- Full control over keyboard interception at the native level
- Can work even when no React component has focus
- Can intercept before CompositionEventHandler processes the event
- Reusable across the app via a simple JS API

**Cons:**
- Requires native code (C++ or C#)
- Must hook into the window's message loop (requires app-side wiring)
- More complex to set up and maintain

---

## 3. If We Need Native Support — Proposed Design

If React Native Windows wants to provide first-class support for global keyboard shortcuts, here is a proposed design.

### 3.1 Option A: `onKeyDownCapture` / `onKeyUpCapture` on `ReactNativeIsland`

Expose keyboard capture events at the `ReactNativeIsland` level (the top-level hosting surface). This is similar to Win32's `PreviewKeyDown` or WPF's tunneling events.

**API Surface (C++/WinRT):**

```cpp
// In ReactNativeIsland.idl
runtimeclass ReactNativeIsland {
  // Existing members...

  // New: Application-level keyboard event
  event Windows.Foundation.TypedEventHandler<ReactNativeIsland, KeyRoutedEventArgs> KeyDown;
  event Windows.Foundation.TypedEventHandler<ReactNativeIsland, KeyRoutedEventArgs> KeyUp;
}
```

**Native implementation change in `CompositionEventHandler::onKeyDown()`:**

```cpp
void CompositionEventHandler::onKeyDown(
    const winrt::Microsoft::ReactNative::Composition::Input::KeyRoutedEventArgs &args) noexcept {

  // NEW: Fire application-level event FIRST
  if (auto strongRootView = m_wkRootView.get()) {
    strongRootView.RaiseKeyDown(args);  // New method
    if (args.Handled())
      return;
  }

  // Existing: dispatch to focused component
  if (auto focusedComponent = RootComponentView().GetFocusedComponent()) {
    winrt::get_self<...>(focusedComponent)->OnKeyDown(args);
    if (args.Handled())
      return;
  }

  // Existing: built-in shortcuts (DevMenu, Tab)
  // ...
}
```

**JS API:**

```typescript
import {useEffect} from 'react';
import {GlobalKeyboard} from 'react-native-windows';

function App() {
  useEffect(() => {
    const subscription = GlobalKeyboard.addListener('keyDown', (event) => {
      if (event.ctrlKey && event.code === 'KeyL') {
        navigation.navigate('Library');
      }
    });
    return () => subscription.remove();
  }, []);

  return <YourApp />;
}
```

### 3.2 Option B: Declarative Keyboard Accelerators (Inspired by WinUI)

Take inspiration from WinUI's `KeyboardAccelerator` API, allowing declarative shortcut registration.

**JS API:**

```tsx
import {KeyboardShortcut, KeyboardShortcutManager} from 'react-native-windows';

function App() {
  return (
    <KeyboardShortcutManager>
      <KeyboardShortcut
        code="KeyL"
        modifiers={['ctrl']}
        onActivated={() => navigation.navigate('Library')}
      />
      <KeyboardShortcut
        code="KeyK"
        modifiers={['ctrl']}
        onActivated={() => openSearch()}
      />
      <YourApp />
    </KeyboardShortcutManager>
  );
}
```

### 3.3 Option C: Hook-Based API (Simplest Addition)

A React hook that registers global shortcuts. This could be implemented as a thin wrapper over a native module.

**JS API:**

```typescript
import {useGlobalKeyboardShortcut} from 'react-native-windows';

function App() {
  useGlobalKeyboardShortcut(
    {code: 'KeyL', ctrlKey: true},
    () => navigation.navigate('Library'),
  );

  useGlobalKeyboardShortcut(
    {code: 'KeyK', ctrlKey: true},
    () => openSearch(),
  );

  return <YourApp />;
}
```

### 3.4 Recommended Approach

**Option A (ReactNativeIsland events) + Option C (hook-based API)** together provide the best solution:

- **Option A** gives the native infrastructure — a keyboard event on the hosting surface that fires before component dispatch
- **Option C** gives the ergonomic JS API that developers expect

The implementation would require:
1. Adding `KeyDown`/`KeyUp` events to `ReactNativeIsland` IDL
2. Modifying `CompositionEventHandler::onKeyDown()` to raise the island-level event first
3. Creating a `GlobalKeyboard` native module that listens to the island events
4. Exposing a `useGlobalKeyboardShortcut` hook in the `react-native-windows` JS package

**Estimated scope:** Medium — touches `ReactNativeIsland`, `CompositionEventHandler`, and adds a new JS module.

---

## 4. Relevant Source Files

### Core Keyboard Infrastructure (C++)

| File | Purpose |
|------|---------|
| `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.cpp` | Main keyboard event dispatcher; receives WM_KEYDOWN/WM_KEYUP and routes to focused component |
| `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionEventHandler.h` | Header for CompositionEventHandler |
| `vnext/Microsoft.ReactNative/Fabric/Composition/RootComponentView.h` | Root component that tracks focused component; handles focus navigation |
| `vnext/Microsoft.ReactNative/Fabric/Composition/ReactNativeIsland.h` | Top-level hosting surface (ContentIsland); potential hook point for global events |
| `vnext/Microsoft.ReactNative/Fabric/Composition/CompositionViewComponentView.cpp` | Per-component keyboard event handling |
| `vnext/Microsoft.ReactNative/Fabric/platform/react/renderer/components/view/KeyEvent.h` | KeyEvent and HandledKeyEvent struct definitions |
| `vnext/Microsoft.ReactNative/Fabric/platform/react/renderer/components/view/HostPlatformViewEventEmitter.h` | Emits keyboard events to JS layer |
| `vnext/Microsoft.ReactNative/Utils/KeyboardUtils.h` | VirtualKey to W3C key/code conversion utilities |

### JavaScript/TypeScript APIs

| File | Purpose |
|------|---------|
| `vnext/src-win/Libraries/Components/View/ViewPropTypes.d.ts` | TypeScript types for `IKeyboardEvent`, `IHandledKeyboardEvent`, keyboard props |
| `vnext/src-win/Libraries/Components/View/View.windows.js` | View component with keyboard event support |
| `vnext/src-win/Libraries/Components/Keyboard/KeyboardExtProps.ts` | Legacy `IKeyboardProps` interface (deprecated) |

### Documentation & Examples

| File | Purpose |
|------|---------|
| `vnext/proposals/active/keyboard-reconcile-desktop.md` | Comprehensive keyboard API design document |
| `packages/@react-native-windows/tester/src/js/examples-win/Keyboard/KeyboardExample.tsx` | Keyboard event examples |
| `packages/@react-native-windows/tester/src/js/examples-win/Keyboard/KeyboardFocusExample.windows.tsx` | Focus management examples |

---

## 5. Summary & Recommendation

### For the Customer (Today)

**Use Workaround 1 (Root View Capture)** — it works today, requires no native code, and handles most use cases:

```tsx
<View focusable={true} onKeyDownCapture={handleGlobalKeyDown} keyDownEvents={[...]}>
  <App />
</View>
```

The capture phase ensures the root View sees every keyboard event before any child component. Combined with `keyDownEvents` using `handledEventPhase: Capturing`, you can prevent shortcuts from triggering child component behavior.

**If the customer needs shortcuts that work when no React component has focus**, use Workaround 2 (Native Module) to hook into the Win32 message loop directly.

### For React Native Windows (Future)

Consider implementing first-class support via:
1. **`KeyDown`/`KeyUp` events on `ReactNativeIsland`** — native infrastructure
2. **`useGlobalKeyboardShortcut` hook** — ergonomic JS API
3. This aligns with WinUI's `KeyboardAccelerator` pattern and provides a clean, discoverable API for a common desktop application need.
