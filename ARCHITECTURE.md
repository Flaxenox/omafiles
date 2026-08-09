# Architecture

Omafiles started as a single-file Quickshell plugin (~6900 lines) and has
been progressively decoupled into a **host-independent core** plus a
**thin Quickshell integration layer**. This document describes that
result as of the `core-v1-ready` milestone — the point from which a
second frontend (Qt6 standalone) can be built without restructuring
anything below it.

## Folder structure

```
Omafiles.qml                    Quickshell bootstrap (~90 lines)
core/
  OmafilesContent.qml            Full visual tree + wiring (composition root)
integrations/
  quickshell/
    HostBridge.qml                FloatingWindow + host `shell` object, isolated
logic/                           Business logic (Process-based I/O, state mutation)
state/                           pragma Singleton data holders
panels/                          Large always-visible UI (sidebar, file lists, preview)
dialogs/                         Modal/floating UI
shared/                          Small reusable visual pieces
services/                        Quickshell process/env/notify wrapped as an Omafiles-owned API
scripts/, *.sh                   Backing shell scripts (list-dir.sh, trash-info.sh, ...)
```

## Layers

```mermaid
graph TD
  Omafiles["Omafiles.qml (bootstrap)"] --> HostBridge["integrations/quickshell/HostBridge.qml"]
  Omafiles --> Content["core/OmafilesContent.qml"]
  HostBridge -.hosts.-> Content
  Content --> panels
  Content --> dialogs
  Content --> logic
  panels --> logic
  dialogs -. props/callbacks only .-> Content
  logic --> state
  logic --> services
  panels --> shared
  services -->|wraps| Quickshell[(Quickshell APIs)]
  HostBridge -->|wraps| Quickshell
```

- **`Omafiles.qml`** — the object the Quickshell host loader actually
  instantiates. Holds only what the plugin ABI requires on the root
  object (`shell`, `open()`, `close()`, `opened`) and creates
  `HostBridge` + `OmafilesContent`, wiring them together. No business
  logic.
- **`core/OmafilesContent.qml`** — the real composition root: every
  property, every controller instantiation (`NavigationController`,
  `DirLister`, `ActionEngine`, `TabOps`, ...), the full visual tree
  (Sidebar, active panel, background panels, every dialog). Knows
  nothing about Quickshell — `requestClose()` emits a `closeRequested()`
  signal instead of talking to a host object directly.
- **`integrations/quickshell/HostBridge.qml`** — the only file that
  imports `Quickshell`'s `FloatingWindow` and touches the host-injected
  `shell` object. Exposes `show()`/`hide()`/`close()` and a
  `closedExternally()` signal; that's the entire contract `Omafiles.qml`
  depends on.
- **`state/`** — `pragma Singleton` data holders, no logic beyond
  property declarations. Imports nothing but `QtQuick` (`state/TabsState.qml`
  is the one exception, importing `services/` for `Env.get("HOME")` at
  init).
- **`logic/`** — business logic (`property Item root: null` pattern,
  or `hostRoot`/`hostX` for `Repeater`/`ListView` delegates — see
  dependency rule 6). Reads/writes `state/` by singleton name, talks to
  the OS exclusively through `services/`.
- **`panels/`** — large always-visible UI. Calls into `logic/`, reads
  `state/`.
- **`dialogs/`** — modal/floating UI. Purely presentational (local
  `id: root`); receives data via property bindings/callbacks only.
- **`shared/`** — small reusable visual pieces, no awareness of
  `state/`/`logic/` at all.
- **`services/`** — the only place `Quickshell.Io.Process`,
  `Quickshell.execDetached`, and `Quickshell.env` are called directly.
  Exposes an Omafiles-owned API instead (`ProcessRunner`, `ProcessWatcher`,
  `Detached`, `Notifier`, `Env`) so callers never see Quickshell's own
  types or naming.

## Dependency rules

1. `logic/` never imports `panels/`, `dialogs/`, `shared/`, `core/`, or
   `integrations/`.
2. `dialogs/` and `shared/` never import `state/` or `logic/` directly.
3. `state/` imports nothing but `QtQuick` (and `services/` where noted
   above) — no dependency on `logic/`/`panels/`/`core/`.
4. `core/ControllerRegistry.qml` is the single owner of every `logic/`
   controller — the only file that instantiates them (Phase 11.C; it
   replaced `OmafilesContent` in this role to kill the star coupling flagged
   by the 2026-08-09 audit). `OmafilesContent` instantiates the registry and
   the focused frontend components (`MainLayout`, `DialogLayer`,
   `CommandFacade`, `AppBindings`), passing each only the controllers it
   uses. One exception stands: `panels/ActiveFileList.qml` instantiates
   `logic/KeyboardShortcuts.qml`, since every dependency it needs is already
   a property on that panel.
5. No circular dependencies within `logic/` — see `DEPENDENCY_GRAPH.md`.
6. `logic/` and `panels/` never import `Quickshell` or anything under
   `integrations/`. Only `services/` and `integrations/quickshell/` do.
7. Only `Omafiles.qml` imports `integrations/quickshell/`. Nothing under
   `core/`, `logic/`, `state/`, `panels/`, `dialogs/`, `shared/`, or
   `services/` imports `integrations/` at all.

## Host-independent vs. Quickshell-specific

**Independent of the host** (everything a future `integrations/standalone/`
would reuse untouched): `core/`, `logic/`, `state/`, `panels/`, `dialogs/`,
`shared/`, `services/`, and the backing `.sh` scripts. None of these
import `Quickshell` or reference a `FloatingWindow`/host `shell` object.

**Specific to Quickshell** (the only things a second frontend needs to
replace): `Omafiles.qml` (the bootstrap — a Qt6 standalone frontend
would have its own, e.g. `integrations/standalone/Main.qml` +
`main.cpp`) and `integrations/quickshell/HostBridge.qml` (a standalone
frontend would provide an equivalent backed by `ApplicationWindow`
instead of `FloatingWindow`, with no host `shell` object to talk to).
`services/*.qml` implementations also stay Quickshell-specific internally
(they wrap `Quickshell.Io.Process` etc.), but their *API* is already
host-agnostic — a standalone port only needs to reimplement their
insides, not touch any caller.

## Why this is a reusable core

`core/OmafilesContent.qml` has zero references to `FloatingWindow`,
`HostBridge`, or the host's `shell` object, and every dependency it pulls
in (`logic/`, `state/`, `panels/`, `dialogs/`, `shared/`, `services/`) is
equally Quickshell-free. It exposes exactly the surface a host needs:
`open(payload)`, `close()`, `opened`, and a `closeRequested()` signal.
Any QML host that can instantiate an `Item` and connect those four things
can run it — `integrations/quickshell/HostBridge.qml` is one such host,
backed by `FloatingWindow`; a future `integrations/standalone/Main.qml`
backed by `ApplicationWindow` is a mechanical addition, not a
restructuring.
