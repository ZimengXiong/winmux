# WinMux *Beta*

WinMux is an intuitive, sidebar-first window manager for macOS. It began as an AeroSpace-derived codebase, but its runtime model is being reshaped around WinMux projects, workspaces, displays, tab groups, and sidebar workflows.



https://github.com/user-attachments/assets/69d8872a-d6f0-460e-95ad-d55013c3216e

An agent mode is in the works, read about it [here](https://blog.zimengxiong.com/#post/agents-will-need-a-good-window-manager) and see a [demo](https://cvx-me-api.alpacawebservices.com/api/storage/6dea289a-9559-49bd-87cf-42345f89c712
)—this is just for fun right now (dont expect anyone would use it), but still interesting to see.


## Highlights
### Sidebar
<a href="sidebar.mp4">
  <img src="sidebar.gif" width="800" alt="Sidebar demo">
</a>

The sidebar is a more interactively-performant and useful (though less customizable—WIP!) alternative to [Sketchybar](https://github.com/felixkratz/sketchybar) and traditional workspace menu bar dropdowns for most everyday tasks. It provides better visibility into spaces and spatial awareness on the desktop.

You can drag windows in and out of the sidebar from and to the current workspace. You can rearrange windows across all spaces using the sidebar, including tab groups.

![](sidebar.png)

The sidebar can be configured (as shown) to display the current date, time, battery, sound, and network interface (things that I used to have in sketchybar).



### Tab Groups
<a href="tabgroups.mp4">
  <img src="tabgroups.gif" width="800" alt="Tab groups demo">
</a>

Tab groups allow you to have many windows occupy the same footprint, similar to Yabai stacks but with browser-like tab behavior. This is useful when you want to have multiple pieces of reference information next to an editor, multiple tabs in different browser profiles, or, when you simply want multiple fullscreen views without the additional friction and overhead of creating a new workspace.

Unlike stack-only layouts, WinMux tab groups behave more intuitively like you would expect tabs to in browsers, and don't need a keyboard shortcut to activate. You can drag tabs from tab groups into another window's [intent zone](#managed-tiling-mode), or in between workspaces. You can also rearrange tab order within a tab group, and navigate through them with relative and absolute keybindings.


## Managed (Tiling) Mode
<a href="intentzones.mp4">
  <img src="intentzones.gif" width="800" alt="Managed mode intent zones demo">
</a>

WinMux has 6 intent (hover-hint) zones that make it easy to move windows without keyboard shortcuts:

1. Left/Right/Up/Down split
2. Form Tab Group (drag over top of a window)
3. Swap positions with window (drag over center)

## Unmanaged Mode (WIP)
<a href="cornersnapping.mp4">
  <img src="cornersnapping.gif" width="800" alt="Unmanaged mode corner snapping demo">
</a>

In unmanaged mode, WinMux does not perform tiling. It still supports tab groups and the sidebar. In lieu of tiling, WinMux supports traditional corner snapping.

Unmanaged mode can be toggled from the menu bar or via settings.

### Settings
![](settings.gif)

You do not need to open up a config file to change shortcuts for basic actions. More advanced actions still require editing of the config file (`~/.config/winmux/winmux.toml`). You can also edit, validate and reload the config file from within the settings!

### Misc
#### Exposé
![](expose.png)

WinMux comes with it's own mission-control-expose that shows you all the windows and tab groups in the current workspace. Trigger it with `⌃+i`

#### Displays
Multiple displays are managed. Each display can show its own visible workspace, and the sidebar can be scoped to the focused display, all displays, or a specific display.

#### Workspaces
You can NOT create workspaces that have no windows in them. Workspaces with no windows are automatically destroyed.

#### App Launching
WinMux supports single-modifer keybindings (e.g. triggering an action on press of `⌘`)

I highly recommend that you configure the apps you use every day to be launch with Left/Right Option+Command, or similar shortcuts. Here is some of the apps that I have keybinded:

```toml
[mode.main.binding-tap]
    left-alt = 'exec-and-forget /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --profile-directory="Default"'
    right-cmd = 'exec-and-forget /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --profile-directory="Profile 1"'

[mode.main.binding]
    # Disable the native "Hide App" shortcut.
    cmd-h = []

    cmd-d = 'exec-and-forget osascript ~/Documents/scripts/launchTerminalWindow.scpt'
    cmd-e = 'exec-and-forget osascript ~/Documents/scripts/launchFinderWindow.scpt'
```

```applescript
# ~/Documents/scripts/launchTerminalWindow.scpt
tell application "cmux"
    if it is running
        tell application "System Events" to tell process "cmux"
            click menu item "New Window" of menu "File" of menu bar 1
        end tell
    else
        activate
    end if
end tell

# ~/Documents/scripts/launchFinderWindow.scpt
tell application "Finder"
    if it is running
        tell application "System Events" to tell process "Finder"
            click menu item "New Finder Window" of menu "File" of menu bar 1
        end tell
    else
        activate
    end if
end tell

```

#### Architecture Direction
WinMux started from AeroSpace, but the goal is not to keep AeroSpace as the product model. Runtime behavior should be expressed in WinMux concepts: projects, workspaces, displays, monitors, tab groups, and sidebar state.

The eventual goal is still to keep exploring lower-level backends such as Yabai where it makes sense, but WinMux should not depend on old AeroSpace names or compatibility fallbacks in normal operation.

## Installation
Download the latest binary from releases and launch.

As WinMux is not signed, you will need to bypass gatekeeper:

```bash
xattr -dr com.apple.quarantine /Applications/WinMux.app/
```

## Migrating
### From AeroSpace
If `~/.config/winmux/winmux.toml` already exists, WinMux uses it as-is.

If it does not exist and an AeroSpace config exists, WinMux imports that config once into `~/.config/winmux/winmux.toml`, translating known AeroSpace-era names into current WinMux syntax. After that, WinMux reads the generated WinMux config and does not keep syncing or falling back to the AeroSpace source file.

If neither exists, WinMux creates a new WinMux config with the bundled defaults.

The importer translates:

- `accordion` layouts to `tab-group`
- `h_accordion` / `v_accordion` layout commands to `h_tab_group` / `v_tab_group`
- `accordion-padding` to `tab-group-padding`
- `AEROSPACE_*` workspace/window environment variables to `WINMUX_*`

After importing an AeroSpace config, add the WinMux-specific features you want with a block like this:

```toml
window-tabs.enabled = true
window-tabs.height = 36

[workspace-sidebar]
    enabled = true
    collapsed-width = 44
    width = 240
    monitor = 'main'
    # Reserve room for the visible macOS menu bar so the sidebar is not covered by the Apple menu.
    # Use 0 when the macOS menu bar auto-hides.
    menu-bar-reserve-height = 28
    show-status-pills = true
    show-date = true
```

New WinMux bootstrap configs include `menu-bar-reserve-height = 28` by default. Imported AeroSpace configs are migrated, but the importer only translates known compatibility names; add this key manually or set it from Settings if your sidebar starts underneath the macOS menu bar.
## Release Build
Release builds use XcodeGen/Xcode

Build, archive, zip, and publish a GitHub release:

```bash
make release VERSION=0.1.0
```

The release build uses automatic signing with your local Apple Development certificate and team configured in the Makefile.

To build the release artifact without publishing to GitHub:

```bash
make release VERSION=0.1.0 PUBLISH=0
```

You can report issues via `Menu Bar > Report an Issue on Github`. Please consider contributing!!

## Roadmap
- [x] Tab groups
- [x] Sidebar
- [x] Window Snapping
- [ ] Tab groups working in unmanaged mode
- [ ] Workspace renaming
- [ ] Sidebar customization/plugins system
- [ ] Support for Yabai
- [ ] Integrate trackpad swiping support (see some work I did on [JiTouch](https://github.com/ZimengXiong/Jitouch2))

## Credits
The app logo/icon is still Aerospace's and will proab stay that way for a while. Been focusing on getting everything working first.

- https://github.com/nikitabobko/AeroSpace
- https://github.com/rxhanson/rectangle
- https://github.com/asmvik/yabai
- https://github.com/felixkratz/sketchybar
