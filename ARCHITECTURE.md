# Architecture

- **`Omafiles.qml`** — composition root. Instantiates and wires every
  component; holds only state no single `logic/` component owns
  (navigation, window lifecycle, config constants).
- **`state/`** — `pragma Singleton` data holders, no logic beyond
  property declarations. Imports nothing but `QtQuick`.
- **`logic/`** — business logic (`property Item root: null` pattern),
  `Process`-based I/O. Reads/writes `state/` by singleton name.
- **`panels/`** — large always-visible UI (sidebar, file list,
  background tabs, preview). Calls into `logic/`, reads `state/`.
- **`dialogs/`** — modal/floating UI. Purely presentational (local
  `id: root`); receives data via property bindings/callbacks only.
- **`shared/`** — small reusable visual pieces, no awareness of
  `state/`/`logic/` at all.

## Dependency rules

1. `logic/` never imports `panels/`, `dialogs/`, or `shared/`.
2. `dialogs/` and `shared/` never import `state/` or `logic/` directly.
3. `state/` imports nothing but `QtQuick` — zero dependencies.
4. Only `Omafiles.qml` instantiates `logic/` components (one exception:
   `panels/ActiveFileList.qml` instantiates `logic/KeyboardShortcuts.qml`,
   since every dependency it needs is already a property on that panel).
5. No circular dependencies within `logic/` — see `DEPENDENCY_GRAPH.md`.
