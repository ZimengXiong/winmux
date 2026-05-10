# Deck

Deck is a project launcher for WinMux. It is intentionally explicit: a Deck profile says what to launch, then optional routing rules tell WinMux where the resulting windows should go.

Deck can be used by itself as a small Bunch-style launcher. When WinMux is running, Deck can also route matching windows into WinMux workspaces and tab groups through the `winmux agent` API.

## Commands

```sh
deck init winmux --root ~/Projects/WindowManagers/winmux
deck check winmux
deck open winmux
deck open winmux --no-winmux
deck open winmux --dry-run
deck edit winmux
deck list
```

By name, Deck reads profiles from:

```text
~/.config/deck/profiles/<name>.toml
```

`$XDG_CONFIG_HOME` is respected.

## WinMux Project Picker

WinMux also exposes Deck profiles in the workspace sidebar project picker. Each profile has two launch modes:

- `Append to Current Project`: creates a fresh set of workspaces at the end of the current project's workspace order, labels them with the TOML route names, and routes the launched windows there.
- `Open in New Project`: creates a fresh WinMux project first, then creates and labels the profile workspaces inside that project.

Both picker modes map TOML route names to newly-created WinMux workspaces so launching the same profile again does not reuse or overwrite an older project's workspaces. Plain `deck open <profile>` still uses the workspace names literally.

## Profile Example

```toml
name = "winmux"
root = "~/Projects/WindowManagers/winmux"

[env]
PORT = "3000"

[[actions]]
name = "Editor"
type = "shell"
run = "code --new-window \"$DECK_ROOT\""

[actions.route]
workspace = "code"
tab-group = "editor"
timeout-seconds = 12

[actions.match]
bundle-id = "com.microsoft.VSCode"

[[actions]]
name = "Codex"
type = "terminal"
command = "codex"

[actions.route]
workspace = "code"
tab-group = "agents"
timeout-seconds = 12

[actions.match]
bundle-id = "com.apple.Terminal"
title-contains = "winmux"

[[actions]]
name = "Browser"
type = "browser"
app = "Google Chrome"
profile = "Default"
new-window = true
urls = ["http://localhost:$PORT"]

[actions.route]
workspace = "browser"
tab-group = "local"
timeout-seconds = 12

[actions.match]
bundle-id = "com.google.Chrome"
```

## Action Types

- `shell`: runs `run` through `/bin/zsh -lc`.
- `terminal`: opens Terminal or iTerm and runs `command`.
- `browser`: opens URLs in a browser, with support for Chrome `profile` and `new-window`.
- `app`: opens an app by `app` name or `bundle-id`.
- `url`: opens `urls` with macOS.
- `file`: opens `path` or `paths` with macOS.
- `bunch`: opens a Bunch by URL scheme.

Shell actions support `wait = false` for long-running commands.

## Routing

Routing is optional. Each action can specify:

```toml
[actions.route]
workspace = "code"
tab-group = "agents"
reuse-existing = false
focus = false
timeout-seconds = 10
```

Deck queries WinMux before launch, runs the actions, then queries again. By default it routes only newly-created matching windows. Set `reuse-existing = true` when the action should also route windows that existed before `deck open`.

Matching supports:

```toml
[actions.match]
bundle-id = "com.google.Chrome"
app-name = "Google Chrome"
title-contains = "GitHub"
title-equals = "Exact Window Title"
```

When multiple actions target the same `workspace` and `tab-group`, Deck creates a WinMux tab group with the matching windows. If only one window matches, Deck moves that window to the workspace.

## Variables

Deck expands environment-style variables in commands, paths, and URLs:

- `$DECK_NAME`
- `$DECK_ROOT`
- `$PROJECT_ROOT`
- keys from `[env]`
- inherited process environment

Both `$NAME` and `${NAME}` are supported.
