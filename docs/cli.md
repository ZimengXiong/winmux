# WinMux command-line guide

The `winmux` command controls the running WinMux app from a shell. Its command
surface follows AeroSpace conventions while adding WinMux projects, tab groups,
the sidebar, and a structured workflow for desktop assistants.

The client and app should normally come from the same installation. Socket
protocol compatibility is enforced; version and revision differences are
reported for diagnosis. If a command behaves differently from this guide,
check the installed command's help first:

```sh
winmux --version
winmux --help
winmux <command> --help
```

Built-in help is the authoritative syntax reference for the installed build.

- [Quick start](#quick-start)
- [Command conventions](#command-conventions)
- [Querying desktop state](#querying-desktop-state)
- [Projects](#projects)
- [Lazy workspaces](#lazy-workspaces)
- [Windows, layouts, and tab groups](#windows-layouts-and-tab-groups)
- [Monitors](#monitors)
- [Modes, bindings, and configuration](#modes-bindings-and-configuration)
- [Agent workflow](#agent-workflow)
- [Event subscriptions](#event-subscriptions)
- [Diagnostics and privacy](#diagnostics-and-privacy)
- [Complete command index](#complete-command-index)

## Quick start

Confirm that the client is on `PATH` and that the running app accepts commands:

```sh
command -v winmux
winmux --version
winmux list-monitors --count
```

`winmux --version` reports both client and server versions when the app is
reachable. It still exits successfully and reports the server as `Unknown` when
the app is not running, so use a real query such as `list-monitors --count` as
the health check.

Inspect the current desktop without changing it:

```sh
winmux list-projects --json
winmux list-workspaces --all --json
winmux list-windows --all --json
winmux list-monitors --json
winmux list-apps --json
```

Open WinMux's two interactive interfaces:

```sh
winmux open-sidebar
winmux palette
```

`open-sidebar` gives keyboard focus to the sidebar search. Typed letters search
the sidebar until it is dismissed or a selection is completed. `palette`
toggles the fuzzy window switcher.

## Command conventions

- Most window commands act on the focused window. For deterministic scripts,
  capture a window ID and pass `--window-id <id>` whenever the command supports
  it.

- Project display names and sidebar indices can change. Scripts should retain
  the stable `project-<UUID>` returned by `create-project` and use
  `--project-id` where available.

- Query filter options shown as `[no]` in help accept an optional `no`. For
  example, `--focused` selects focused items and `--focused no` excludes them.

- Use `--` where help shows `[--]` to stop option parsing before a name or
  pattern that could look like an option or reserved target.

- Standard input is never consumed implicitly. Commands that support pipelines
  require an explicit `--stdin`; use `--no-stdin` when you want to forbid it
  explicitly.

- Shell-quote colors such as `'#60A5FA'`. An unquoted `#` begins a shell
  comment.

- Unless the surrounding text calls a snippet a workflow, commands shown on
  separate lines are independent examples. Run only the operation you want.

The CLI uses these exit codes:

| Code | Meaning |
| ---: | --- |
| `0` | Success, help, or version output |
| `1` | Server, protocol, command, or validation failure |
| `2` | Local command-line usage or parsing error |

## Mental model

WinMux organizes the desktop as:

```text
project
└── workspace
    ├── tiled container tree
    │   ├── window
    │   └── tab-group container
    │       ├── window
    │       └── window
    └── floating windows
```

A project is a durable grouping with a stable ID, mutable name, color, and one
or more workspaces. Workspaces are lazy: moving a window to `new` obtains a new
workspace, and an ordinary workspace retires after its last window moves away.
WinMux may keep a project's minimum empty workspace so the project remains
navigable.

## Querying desktop state

### JSON

Use `--json` for scripts. Default fields vary by query, so select the exact
fields you depend on with `--format`:

```sh
winmux list-windows --all --json \
  --format '%{window-id} %{app-name} %{workspace} %{window-layout}'

winmux list-projects --json \
  --format '%{project-id} %{project-name} %{project-window-count}'
```

With `--json`, a custom format may contain interpolation fields and spaces.
Decorative literal separators are rejected. The result uses the requested field
names as JSON keys.

### Plain text

Plain formats can include text and the `%{tab}`, `%{newline}`, and
`%{right-padding}` helpers:

```sh
winmux list-windows --all \
  --format '%{window-id}%{tab}%{app-name}%{tab}%{workspace}%{tab}%{window-title}'

winmux list-projects \
  --format '%{project-id}%{tab}%{project-name}%{tab}%{project-window-count}'
```

### Available fields

The accepted interpolation field families are:

- Window: `window-id`, `window-is-fullscreen`, `window-title`,
  `window-layout`, and `window-parent-container-layout`, plus workspace,
  monitor, and app fields.

- Workspace: `workspace`, `workspace-is-focused`, `workspace-is-visible`, and
  `workspace-root-container-layout`, plus monitor fields.

- Project: `project-index`, `project-id`, `project-name`, `project-color`,
  `project-is-focused`, `project-is-visible`, `project-workspace-count`, and
  `project-window-count`.

- App: `app-bundle-id`, `app-name`, `app-pid`, `app-exec-path`, and
  `app-bundle-path`.

- Monitor: `monitor-id`, `monitor-appkit-nsscreen-screens-id`, `monitor-name`,
  and `monitor-is-main`.

`list-windows` requires an explicit scope: `--all`, `--focused`, one or more
`--workspace` selectors, or one or more `--monitor` selectors.

Examples that transform JSON use [`jq`](https://jqlang.org/). It is optional
for WinMux itself and is not included with macOS; install it separately if you
want to run those examples.

## Projects

### Create and enter a project

Capture the stable ID at creation time:

```sh
project_id="$(
  winmux create-project \
    --name 'Client Alpha' \
    --color '#60A5FA'
)"

printf 'Created %s\n' "$project_id"

winmux move-node-to-project \
  --project-id "$project_id" \
  --focus-follows-window
```

`move-node-to-project` moves the focused window to the first workspace in the
project. Use `--window-id <id>` to move a specific window.

The positional forms of `project` and `move-node-to-project` also accept a
project ID, a current 1-based sidebar index, `next`, or `prev`. Prefer
`--project-id` in automation so a project whose ID resembles another target is
unambiguous.

Switch to an existing project without moving a window:

```sh
winmux project --project-id "$project_id"
```

Or navigate relative to the sidebar order. Run either operation independently:

```sh
winmux project --wrap-around next
winmux move-node-to-project --focus-follows-window --wrap-around next
```

### Rename and recolor

```sh
winmux rename-project "$project_id" 'Client Alpha - Research'
winmux set-project-color "$project_id" '#AABBCC'
winmux set-project-color "$project_id" auto
```

These commands take the stable project ID positionally. Add `--fail-if-noop`
when a no-op should fail rather than warn and exit successfully.

### Delete safely

Project deletion is deliberately guarded. Re-read the current window count and
pass it back with the only supported action:

```sh
window_count="$(
  winmux list-projects --json |
    jq -er --arg id "$project_id" \
      '.[] | select(."project-id" == $id) | ."project-window-count"'
)"

winmux delete-project \
  --action move-windows-to-fallback \
  --if-window-count "$window_count" \
  --json \
  "$project_id"
```

Deletion moves the project's windows to the fallback project; it does not close
them. It refuses to run if the count changed after the query, and the default
project cannot be deleted.

## Lazy workspaces

Move the focused window to a newly allocated workspace and keep focus with it:

```sh
winmux move-node-to-workspace --focus-follows-window new
```

Here is a reversible live test that returns the same window to its original
workspace:

```sh
original_workspace="$(
  winmux list-workspaces --focused --format '%{workspace}'
)"

winmux move-node-to-workspace --focus-follows-window new
winmux move-node-to-workspace --focus-follows-window "$original_workspace"
```

Keep the terminal focused while running that example. To target another window,
pass `--window-id <id>`. To use `new` as a literal workspace name instead of the
control word, use:

```sh
winmux move-node-to-workspace -- new
```

Navigate and summon workspaces:

```sh
winmux workspace --wrap-around next
winmux workspace-back-and-forth
winmux summon-workspace work
```

For relative navigation, `workspace next` and `workspace prev` can consume a
newline-delimited candidate list only when `--stdin` is explicit.

## Windows, layouts, and tab groups

Capture a stable target before a series of operations:

```sh
window_id="$(
  winmux list-windows --focused --format '%{window-id}'
)"

winmux layout --window-id "$window_id" tiling
winmux resize --window-id "$window_id" width +160
```

Common focused-window operations include the following. Run each line
independently:

```sh
winmux focus left
winmux move right
winmux swap --swap-focus left
winmux split horizontal
winmux join-with right
winmux balance-sizes
```

`layout` accepts one or more candidate layouts. It switches to the first one
that is not already matched, which makes layout toggles convenient. Each line
below is an independent toggle:

```sh
winmux layout h_tiles v_tiles
winmux layout h_tab_group v_tab_group
winmux layout tiling floating
```

Create or adjust tab groups with:

```sh
winmux stack-with right
winmux focus tab-next
winmux focus --tab-index 1
```

WinMux fullscreen and native macOS fullscreen are separate operations. Run only
the operation you want:

```sh
winmux fullscreen
winmux macos-native-fullscreen
winmux macos-native-minimize
```

Native macOS fullscreen creates a macOS Space; WinMux fullscreen does not.

Directional `focus` and `move` commands expose boundary behavior through
`--boundaries` and `--boundaries-action`. Inspect their help before encoding a
policy in a script:

```sh
winmux focus --help
winmux move --help
```

## Monitors

Monitor targets accept a relative direction, `next`, `prev`, or a monitor
pattern. Monitor IDs are 1-based. After the read-only first line, each line is
an independent movement example:

```sh
winmux list-monitors --json
winmux focus-monitor --wrap-around next
winmux move-node-to-monitor --focus-follows-window next
winmux move-workspace-to-monitor --wrap-around prev
```

The monitor query can filter with `--focused`, `--mouse`, or their `no` forms.
Use `winmux <command> --help` for pattern matching and selector details.

## Modes, bindings, and configuration

Inspect configured modes without changing the active one:

```sh
winmux list-modes --json
winmux list-modes --current
```

Use `winmux mode <mode-name>` to activate a mode and
`winmux trigger-binding --mode <mode-name> -- <binding>` to invoke a configured
binding. These commands change input state or execute the binding's action, so
use names from the active config and run them deliberately.

Inspect config keys and validate changes before adopting them:

```sh
winmux config --config-path
winmux config --major-keys
winmux config --all-keys
winmux reload-config --dry-run
winmux reload-config
```

`reload-config --no-gui` suppresses configuration error UI for unattended
scripts. To change the temporary manager state, choose one operation:

```sh
winmux enable toggle
winmux enable off
winmux enable on
```

Add `--fail-if-noop` when an already-matching state should make `on` or `off`
fail.

## Agent workflow

`winmux agent` provides a freshness-guarded JSON workflow for assistants and
larger shell transformations. Print the current schema and behavioral contract
instead of hard-coding a copy from this guide:

```sh
winmux agent skill
```

Validate a fresh snapshot without changing the desktop:

```sh
winmux agent query | winmux agent check --stdin
```

Test the apply path with an empty operation list:

```sh
winmux agent query |
  jq '.edit.operations = []' |
  winmux agent apply --stdin
```

For a reviewable file-based edit:

```sh
(
  request="$(mktemp "${TMPDIR:-/tmp}/winmux-agent.XXXXXX")"
  edited="${request}.edited"
  trap 'rm -f "$request" "$edited"' EXIT

  winmux agent query --path "$request"

  jq '
    (first(.inventory.windows[] | select(.focused) | .windowId)
      // error("No focused WinMux window")) as $window_id
    | .edit.operations = [
        {type: "focusWindow", windowId: $window_id}
      ]
  ' "$request" > "$edited"

  winmux agent check --path "$edited"
  winmux agent apply --path "$edited"
)
```

Follow these rules when generating an agent edit:

- Preserve the full queried document, including `schemaVersion`, `snapshotId`,
  `worldId`, inventory, and reasoning; edit only the `edit` object.

- If desktop state changes and the request becomes stale, discard it and query
  again.

- `apply` validates automatically. `check` is an optional preflight that prints
  `OK` on success; a successful `apply` is silent.

- `--path` and `--stdin` are mutually exclusive. Agent stdin must be UTF-8 and
  is limited to 16 MiB.

- Validation happens before mutation, but operations in a multi-operation edit
  are applied sequentially and are not rollback-transactional. Prefer small,
  coherent batches.

The snapshot includes app names and window titles, which may contain private
information. Treat saved snapshots as sensitive artifacts.

## Event subscriptions

Subscribe to explicit event types:

```sh
winmux subscribe focus-changed focused-workspace-changed
```

Or subscribe to every event:

```sh
winmux subscribe --all
```

Events are emitted as one JSON object per line. Stateful event types send an
initial value by default; add `--no-send-initial` when only future changes are
wanted. The command runs until the socket disconnects or you interrupt it with
Control-C. `--all` and an explicit event list are mutually exclusive.

Available event names are:

- `focus-changed`
- `focused-monitor-changed`
- `focused-workspace-changed`
- `mode-changed`
- `window-detected`
- `binding-triggered`

## Diagnostics and privacy

Start troubleshooting with:

```sh
winmux doctor
winmux --version
winmux reload-config --dry-run
```

`doctor` reports permission, monitor, manager-state, and per-app Accessibility
latency diagnostics. If `--version` shows a server of `Unknown` or a real query
cannot connect, ensure `WinMux.app` is running and that the client came from the
same installation.

`debug-windows` is an interactive diagnostic intended for Accessibility API bug
reports. Its output can contain window metadata; inspect it before sharing.

Avoid casually running or pasting the output of:

```sh
winmux list-exec-env-vars
```

It prints the environment inherited by WinMux's `exec-*` commands and callbacks,
which may include secrets or private paths. Window titles, app paths, and agent
snapshots can also expose sensitive information.

## Complete command index

This index covers every public subcommand in the WinMux version shipped with
this documentation. Run `winmux <command> --help` for its complete installed
syntax.

### Projects and workspaces

| Command | Purpose |
| --- | --- |
| `create-project` | Create a project and print its stable ID |
| `delete-project` | Guardedly delete a project and move its windows to the fallback |
| `list-projects` | Query projects, metadata, and counts |
| `list-workspaces` | Query workspaces |
| `move-node-to-project` | Move a window to a project's first workspace |
| `move-node-to-workspace` | Move a window to a named, relative, or new workspace |
| `project` | Focus a project by ID, index, or relative target |
| `rename-project` | Rename a project by stable ID |
| `set-project-color` | Set or reset a project's sidebar color |
| `summon-workspace` | Move a workspace to the focused monitor |
| `workspace` | Focus a workspace |
| `workspace-back-and-forth` | Toggle between current and previous workspaces |

### Window focus, movement, and layout

| Command | Purpose |
| --- | --- |
| `balance-sizes` | Balance window sizes in a workspace |
| `close` | Close a window |
| `close-all-windows-but-current` | Close other windows on the focused workspace |
| `flatten-workspace-tree` | Remove unnecessary nested containers |
| `focus` | Focus a directional, DFS, tab, indexed, or ID-selected window |
| `focus-back-and-forth` | Toggle between current and previous focused elements |
| `fullscreen` | Control WinMux fullscreen |
| `join-with` | Place neighboring nodes under a common container |
| `layout` | Select or toggle tiling, floating, or tab-group layouts |
| `macos-native-fullscreen` | Control native macOS fullscreen |
| `macos-native-minimize` | Minimize a window through macOS |
| `move` | Move a window directionally within the layout |
| `move-node-to-monitor` | Move a window to another monitor |
| `move-workspace-to-monitor` | Move a workspace to another monitor |
| `resize` | Set or adjust width or height |
| `split` | Set the focused container's split orientation |
| `stack-with` | Put a window in the neighboring window's tab group |
| `swap` | Swap a window with another window |

### Queries, monitors, and interactive UI

| Command | Purpose |
| --- | --- |
| `focus-monitor` | Focus a monitor by direction, order, or pattern |
| `list-apps` | Query running user-interface applications |
| `list-modes` | Query configured binding modes |
| `list-monitors` | Query monitors |
| `list-windows` | Query scoped windows and their metadata |
| `mode` | Activate a binding mode |
| `move-mouse` | Move the pointer to a monitor or window position |
| `open-sidebar` | Open the sidebar with type-to-search active |
| `palette` | Toggle the fuzzy window switcher |
| `volume` | Adjust or mute system volume |

### Automation, configuration, and diagnostics

| Command | Purpose |
| --- | --- |
| `agent` | Query, validate, and apply structured layout edits |
| `config` | Query active configuration values and paths |
| `debug-windows` | Record interactive Accessibility diagnostics for bug reports |
| `doctor` | Report permissions, state, monitors, and Accessibility latency |
| `enable` | Temporarily enable, disable, or toggle WinMux |
| `list-exec-env-vars` | Print the environment inherited by callbacks and `exec-*` commands |
| `reload-config` | Validate or reload the active config |
| `subscribe` | Stream selected events as JSON lines |
| `trigger-binding` | Invoke a configured binding by mode and key |
