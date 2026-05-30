<p align="center">
  <img src="resources/winmux-logo.svg" width="80" alt="WinMux logo">
</p>

<h1 align="center">WinMux <em>Beta</em></h1>

<p align="center">A sidebar-first window manager for macOS.</p>

![](winmux-overview.png)

## Highlights
### Projects
Projects are collection of workspaces. Think of it like a parent/child hiearchy, you can switch between projects. Each project has it's own set of workspaces.

### Sidebar
The sidebar is a more interactively-performant and useful alternative to [Sketchybar](https://github.com/felixkratz/sketchybar) and traditional workspace menu bar dropdowns for most everyday tasks. It provides better visibility into spaces and spatial awareness on the desktop.

You can drag windows in and out of the sidebar from and to the current workspace. You can rearrange windows across all spaces using the sidebar, including tab groups.

The sidebar can be configured (as shown) to display the current date and time.


### Tab Groups
![](tab-groups.png)
Tab groups allow you to have many windows occupy the same footprint, similar to Yabai stacks but with browser-like tab behavior. This is useful when you want to have multiple pieces of reference information next to an editor, multiple tabs in different browser profiles, or, when you simply want multiple fullscreen views without the additional friction and overhead of creating a new workspace.

Unlike stack-only layouts, WinMux tab groups behave more intuitively like you would expect tabs to in browsers, and don't need a keyboard shortcut to activate. You can drag tabs from tab groups into another window's [intent zone](#managed-tiling-mode), or in between workspaces. You can also rearrange tab order within a tab group, and navigate through them with relative and absolute keybindings.

### Philosophy

#### Workspaces
You can NOT create workspaces that have no windows in them. Workspaces with no windows are automatically destroyed.

### Multi-Monitors
Monitors share the global project/workspace state. Each monitor can be treated as *independent* from each other. They each just use the sidebar to browse through projects and 'select' a workspace to view. 

Monitors can not be attached to the same workspace at the same time. They can be on the same project at the same time.

#### App Launching
WinMux supports single-modifer keybindings (e.g. triggering an action on press of `⌘`)

I highly recommend that you configure the apps you use every day to be launch with Left/Right Option+Command, or similar shortcuts, otherwise it might be hard to launch common things into the current workspace (and instead, take you to the other workspace where the app is currently active). Here is some of the apps that I have keybinded:

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

## Installation
Download the latest binary from releases and launch.

As WinMux is not signed, you will need to bypass gatekeeper:

```bash
xattr -dr com.apple.quarantine /Applications/WinMux.app/
```

## Migrating
### From AeroSpace
If `~/.config/winmux/winmux.toml` already exists, WinMux uses it as-is.

If it does not exist and an AeroSpace config exists, WinMux imports it once into `~/.config/winmux/winmux.toml`. Users do not need to edit the generated config to get the WinMux experience: the importer automatically injects WinMux's current bundled defaults, including the sidebar and window tabs, then preserves AeroSpace keyboard configuration by importing `[mode...]` and `[key-mapping]` sections with known AeroSpace-era names translated into current WinMux syntax.

The reason for this shape is that AeroSpace users should keep their muscle memory without being left on an AeroSpace-shaped config. WinMux-specific behavior is owned by WinMux defaults, so first launch feels like WinMux rather than a compatibility mode that needs manual setup.

After that first import, WinMux reads the generated WinMux config and does not keep syncing or falling back to the AeroSpace source file.

If neither exists, WinMux creates a new WinMux config with the bundled defaults.

Inside imported keyboard sections, the importer translates:

- `accordion` layouts to `tab-group`
- `h_accordion` / `v_accordion` layout commands to `h_tab_group` / `v_tab_group`
- `accordion-padding` to `tab-group-padding`
- `AEROSPACE_*` workspace/window environment variables to `WINMUX_*`

## Credits
The app logo/icon is still Aerospace's and will proab stay that way for a while. Been focusing on getting everything working first.
