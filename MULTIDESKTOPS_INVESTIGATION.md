# Multiple Desktop Support Investigation

Worktree: `/Users/zimengx/.codex/worktrees/0306/multidesktops`

## Current State

- WinMux currently has virtual workspaces, inherited from AeroSpace-style behavior. Invisible workspaces are hidden by moving their windows into off-screen corners, then restored when focused.
- Physical monitor support is intentionally narrowed to the main display. `Sources/AppBundle/model/Monitor.swift` returns `[mainMonitor]` for both `monitors` and `sortedMonitors`.
- Secondary displays are blocked by `UnsupportedMonitorGuard`, which overlays non-main screens and lets the user opt into leaving that display unmanaged.
- The workspace model already has most of the machinery for multiple visible slots: `screenPointToVisibleWorkspace`, `visibleWorkspaceToScreenPoint`, `Monitor.activeWorkspace`, and workspace monitor assignment by screen point.
- The app already listens to `NSWorkspace.activeSpaceDidChangeNotification`, but the handler only schedules a refresh. There is no persistent model of native macOS Desktop/Space IDs.
- The private API target exposes only `_AXUIElementGetWindow`; it does not yet expose SkyLight/CoreGraphics Services APIs for Spaces.

## Key Constraint

Apple exposes a public notification for active Space changes, but does not expose public APIs for enumerating Spaces, creating/destroying Spaces, switching Spaces by ID, or moving windows between Spaces. The AeroSpace docs explicitly call this out and explain why AeroSpace uses emulated workspaces instead of native Spaces.

So there are three viable directions:

## What "Using AeroSpace" Means Here

WinMux is currently a derivative/fork of AeroSpace, not a thin integration that shells out to an installed AeroSpace process.

Evidence in this repo:

- `legal/README.md` says WinMux is a derivative work of AeroSpace.
- `README.md` says WinMux is built on AeroSpace "for now".
- The CLI/config surface keeps AeroSpace names and env vars such as `AEROSPACE_WORKSPACE`.
- There is no package dependency on AeroSpace. The codebase contains the workspace tree, AX observer, command parser, and layout engine directly.

That means "enable multidesktops on AeroSpace" has two different meanings:

- If we mean "make this AeroSpace-derived code support multiple WinMux workspaces across displays", we can do that inside this repo by restoring the upstream-style multi-monitor model and removing the one-display guard.
- If we mean "use native macOS Desktops/Spaces instead of AeroSpace virtual workspaces", that is not what AeroSpace is designed for. It requires either a private SkyLight layer or a separate backend that already owns native Spaces.

## Enabling Multiple Desktops While Staying AeroSpace-Based

Upstream AeroSpace already has a coherent multi-monitor model:

- The workspace pool is shared across monitors.
- Each monitor shows one visible workspace.
- A workspace cannot be visible on two monitors at once.
- Workspaces can be force-assigned to monitors.
- AeroSpace recommends avoiding multiple native macOS Spaces and using its own virtual Workspaces instead.

WinMux currently has much of that model, but has disabled the display side:

- `Monitor.swift` returns only `[mainMonitor]`.
- `UnsupportedMonitorGuard` blocks non-main displays unless the user opts to leave them unmanaged.
- Sidebar config defaults to `monitor = 'main'`.

Recommended AeroSpace-based path:

1. Restore multi-monitor enumeration and monitor sorting.
2. Remove or invert `UnsupportedMonitorGuard` behind a config option such as `managed-monitors = ['main'] | ['all'] | [...]`.
3. Keep WinMux workspaces virtual; do not attempt native Spaces yet.
4. Make the sidebar multi-surface aware:
   - show all workspaces grouped by assigned monitor, or
   - show the focused monitor by default with a monitor switcher.
5. Add a native Space compatibility shim:
   - observe `NSWorkspace.activeSpaceDidChangeNotification`,
   - rebuild visible-window state,
   - avoid forcing focus to windows not visible in the active native Space.

This is the fastest useful path and keeps WinMux's custom features (tab groups, sidebar drag/drop, intent zones, lifecycle workspaces) under our control.

## Other WM Foundations

### Yabai

Best fit if true native macOS Spaces are a hard product requirement.

Why it is attractive:

- It explicitly controls/query windows, spaces, and displays through an IPC-oriented CLI.
- It supports space commands, display commands, rules, signals, and window-to-space operations.
- It has the most mature body of knowledge around macOS private Space/display behavior.

Risks:

- Many advanced space operations require a scripting addition injected into Dock.app, which requires partially disabling SIP.
- It is C/shell/IPC oriented, while WinMux is Swift/AppKit with in-process UI state.
- Building WinMux as a yabai backend would make tab groups and sidebar drag/drop depend on another process's source of truth.

Best use:

- Add a `YabaiBackend` experiment that queries `yabai -m query --spaces --windows --displays` and mirrors WinMux sidebar state.
- Use it as an optional native-Spaces backend, not as the immediate core rewrite.

### Glide

Interesting candidate if we want native Spaces integration without taking on yabai's scripting-addition model immediately.

Why it is attractive:

- It is a modern open-source macOS tiling WM.
- It advertises incremental Mission Control/native Spaces integration.
- It is Rust, MIT/Apache licensed, and seems architected around async macOS WM complexity.

Risks:

- Younger ecosystem than AeroSpace or yabai.
- Rust engine would be a major rewrite or an out-of-process backend.
- Need to inspect whether its Spaces integration is deep enough for our sidebar and drag/drop needs.

Best use:

- Study its architecture and Space model before writing our own native Space tracker.
- Consider ideas/code patterns, not a direct rebase.

### Tarmac

Interesting as a small Rust BSP/IPC WM, but less obviously a better foundation.

Why it is attractive:

- IPC and Lua events look backend-friendly.
- It has per-monitor workspaces, scratchpads, and borders.
- It is small enough to read.

Risks:

- Very young and low adoption.
- Uses private SkyLight for borders and has documented multi-monitor rough edges.
- It appears to be another virtual-workspace model rather than a mature native Spaces foundation.

Best use:

- Mine for IPC/event design and per-monitor workspace ideas.

### Amethyst

Good reference for stable AppKit/Swift tiling and native Space hotkey workflows, not a good WinMux foundation.

Why it is attractive:

- Mature Swift/macOS codebase.
- Uses native Spaces-oriented user workflows for "throw window to space" shortcuts.

Risks:

- Layout model is xmonad-style automatic layouts, not WinMux's tree/tab/sidebar model.
- Less CLI/IPC-first than AeroSpace/yabai.
- Rebase cost would be high while losing much of WinMux's current architecture.

Best use:

- Reference for Accessibility handling, permissions, and user-facing preferences.

### Hammerspoon / Phoenix / Rectangle / FlashSpace

These are useful references, but not better foundations for WinMux:

- Hammerspoon exposes `hs.spaces`, but its own docs call the module experimental and private-API based.
- Phoenix is a scriptable toolkit, not a tiling engine to rebase onto.
- Rectangle explicitly does not move windows to other Desktops/Spaces in the open-source app because Apple has no public API.
- FlashSpace is close in spirit to virtual workspaces, but it is GPL-3.0 and focused on workspace switching rather than a full tiling/tab/sidebar engine.

## Backend Recommendation

Do not rebase immediately.

For the next branch, stay AeroSpace-derived and implement multi-monitor WinMux workspaces first. This addresses the obvious "multiple desktops/displays" gap while preserving the UI features that make WinMux different.

In parallel, spike two backend experiments:

1. `NativeSpaceProbe`: read-only native Space/display/window visibility using public observation plus private enumeration behind an experimental flag.
2. `YabaiBackend`: optional out-of-process backend that mirrors native Spaces through yabai IPC for users willing to accept yabai/SIP tradeoffs.

After those spikes, choose:

- Keep AeroSpace-derived core if virtual workspaces remain acceptable.
- Build a native private-API layer if we need first-party native Spaces without external dependencies.
- Use yabai as an optional backend if native Spaces matter more than a single self-contained app.

## Option A: Make WinMux Workspaces Span Multiple Physical Monitors

This is the lowest-risk first step and does not require native macOS Spaces support.

Implementation outline:

- Restore real monitor enumeration in `Monitor.swift`:
  - `monitors = NSScreen.screens.map(...)`
  - `sortedMonitors` should match the existing monitor ID semantics from AeroSpace, likely left-to-right/top-to-bottom or NSScreen order depending on tests.
- Remove or soften `UnsupportedMonitorGuard` so non-main monitors are no longer blocked by default.
- Re-enable per-monitor workspace assignment paths already present in:
  - `Workspace.workspaceMonitor`
  - `Monitor.activeWorkspace`
  - `rearrangeWorkspacesOnMonitors()`
  - `MoveWorkspaceToMonitorCommand`
  - `MoveNodeToMonitorCommand`
  - `ListMonitorsCommand`
- Audit layout and sidebar UI for assumptions that use `mainMonitor`, especially:
  - `WorkspaceSidebarModel.updateWorkspaceSidebarModel()`
  - `WorkspaceSidebarPanel`
  - `WindowTabsPanel`
  - mouse drag/drop hit testing
- Keep the current emulated workspace behavior: inactive workspaces hide windows in corners.

Pros:

- No private Spaces API.
- Fits the existing model.
- Most command/test scaffolding already exists.

Cons:

- It is multi-monitor support, not true native Desktop/Space support.
- With `NSScreen.screensHaveSeparateSpaces == true`, moving windows between monitors can interact poorly with macOS Spaces.

## Option B: Observe Native Desktops, But Keep WinMux Workspaces Virtual

This is a compatibility layer for users who manually use Mission Control.

Implementation outline:

- Add a `NativeSpaceTracker` that listens to `NSWorkspace.activeSpaceDidChangeNotification`.
- On Space changes:
  - mark the active native desktop as changed,
  - refresh all visible windows,
  - avoid force-focusing a window that is no longer visible on the current native Space,
  - rebuild sidebar/window tabs from windows that AX and CGWindow currently report as visible.
- Use public `CGWindowListCopyWindowInfo(.optionOnScreenOnly, ...)` only as a visibility hint. It can answer "what is visible now", not "which Space owns this hidden window".
- Treat native Space switching as an external event, similar to display reconfiguration.

Pros:

- SIP-safe and App Store-style safer.
- Helps WinMux behave less strangely when the user switches macOS Desktops manually.

Cons:

- Cannot create/delete/switch/move native Spaces.
- Cannot know where off-Space windows live.
- Still should document that WinMux workspaces are the primary model.

## Option C: True Native macOS Desktop/Space Support

This means adopting private SkyLight/CoreGraphics Services APIs, similar in spirit to yabai.

Likely API surface to investigate/prototype:

- `CGSMainConnectionID` / `CGSDefaultConnection`
- `CGSCopyManagedDisplaySpaces`
- `CGSCopyActiveMenuBarDisplayIdentifier`
- `CGSGetActiveSpace`
- `CGSSpaceGetType`
- `CGSManagedDisplaySetCurrentSpace`
- private window-to-space operations used by yabai-like tools

Model changes:

- Introduce a native identity:
  - `NativeDisplayId`
  - `NativeSpaceId`
  - `NativeDesktop(displayId, spaceId, index, uuid, isActive, isFullscreen)`
- Replace `screenPointToVisibleWorkspace` with a more general active-surface map:
  - current: one visible workspace per monitor point
  - native: one visible workspace per active native Space/display pair
- Add a `WorkspacePlacement` concept:
  - `.virtual(monitorPoint)`
  - `.native(displayId, spaceId)`
- Teach focus/layout to verify that the target window is on the active native Space before focusing or laying out.
- Teach commands whether they target WinMux workspaces, native Desktops, or both.

Pros:

- Real native Desktops in the sidebar.
- Potential support for moving/focusing native Spaces.

Cons:

- Private API breakage risk across macOS releases.
- Some operations may require SIP-disabled scripting additions or elevated trust, depending on depth.
- More focus races, especially with multiple displays and native fullscreen Spaces.
- Large test burden because the current unit tests mock monitors/workspaces, not native Spaces.

## Implementation Sequence

Ship this in layers:

1. Re-enable true multi-monitor WinMux workspace support first. The architecture is already mostly shaped for it, and it removes the explicit one-monitor limitation.
2. Add native Space observation as a defensive compatibility layer. This should prevent obviously wrong focus/layout behavior when users switch Desktops manually.
3. Prototype SkyLight native Desktop enumeration behind an experimental config flag. Keep it read-only first: list native Desktops, active desktop per display, and visible windows. Only then consider switching/moving Spaces.

The first implementation branch should probably avoid the word "desktop" in core types until we decide whether "desktop" means a WinMux workspace, a macOS Space, or a display surface. Suggested new terms:

- `ManagedSurface`: a currently visible area WinMux can lay out into.
- `NativeSpace`: a macOS Space/Desktop identity.
- `WorkspacePlacement`: where a WinMux workspace currently belongs.

## High-Risk Files

- `Sources/AppBundle/model/Monitor.swift`
- `Sources/AppBundle/tree/Workspace.swift`
- `Sources/AppBundle/layout/refresh.swift`
- `Sources/AppBundle/focus.swift`
- `Sources/AppBundle/tree/MacWindow.swift`
- `Sources/AppBundle/tree/MacApp.swift`
- `Sources/AppBundle/ui/UnsupportedMonitorGuard.swift`
- `Sources/AppBundle/ui/WorkspaceSidebarModel.swift`
- `Sources/AppBundle/ui/WorkspaceSidebarPanel.swift`
- `Sources/PrivateApi/include/private.h`

## External Notes

- Apple documents `NSWorkspace.activeSpaceDidChangeNotification`, which is useful only for observation.
- AeroSpace documents that Apple does not provide public APIs for full Spaces control and that it therefore emulates workspaces.
- yabai exposes create/destroy/focus/move/query operations for Spaces, but its docs and installation notes imply the deeper behavior depends on private/system integration and macOS settings.
