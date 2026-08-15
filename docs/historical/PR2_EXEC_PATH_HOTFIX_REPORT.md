# OmaFiles PR #2: D-Bus Exec Path Hotfix Report

## Hypothesis Confirmation
The hypothesis stated in the initial report was **confirmed**. 

When OmaFiles is run directly from the Omarchy plugin repository (`~/.config/omarchy/plugins/omafiles/`), the `cmake --install` step is bypassed. As a result, the `scripts/` directory is never copied to the global resource directory (`~/.local/share/omafiles/`). 

Because `install-integrations.sh` previously hardcoded `Exec=$RES_DIR/scripts/...`, the generated system integrations (D-Bus services and `.desktop` files) pointed to non-existent executable files. This directly caused the D-Bus daemon to fail activation of the file chooser portal backend, resulting in the silent failure in Zen Browser.

## The Exact Path Mismatch
- **Expected by D-Bus (Broken)**: `/home/josema/.local/share/omafiles/scripts/dbus-filechooser.py`
- **Actual Plugin Location (Valid)**: `/home/josema/.config/omarchy/plugins/omafiles/scripts/dbus-filechooser.py`

## The Patch
A targeted hotfix was applied to `scripts/install-integrations.sh`.

The script defines two variables:
- `RES_DIR`: The path to the global installation (requires `cmake --install`).
- `SELF_RES`: The path to the repository/plugin where the script itself lives.

The patch simply modifies the generation of the `.desktop` file and the three D-Bus service files to use `$SELF_RES` instead of `$RES_DIR` for their `Exec=` paths. 

```diff
-Exec=$RES_DIR/scripts/open-path.sh %u
+Exec=$SELF_RES/scripts/open-path.sh %u
...
-Exec=$RES_DIR/scripts/dbus-app-open.py
+Exec=$SELF_RES/scripts/dbus-app-open.py
...
-Exec=$RES_DIR/scripts/dbus-filemanager1.py
+Exec=$SELF_RES/scripts/dbus-filemanager1.py
...
-Exec=$RES_DIR/scripts/dbus-filechooser.py
+Exec=$SELF_RES/scripts/dbus-filechooser.py
```

## Validation & Safety
The `install-integrations.sh` script was re-run after applying the patch. 
Validation steps confirmed that:
1. The generated `.service` files now point to the correct absolute paths within the Omarchy plugin repository.
2. `dbus-filechooser.py` is present and executable.
3. D-Bus activation succeeds (verified via `dbus-send --print-reply --dest=org.freedesktop.impl.portal.desktop.omafiles /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer.Ping`).

**Why this is safe for Phase 31 / RC1:**
This patch is extremely low-risk. It does not alter the portal architecture, D-Bus interfaces, QML UI, or application logic. It solely ensures that the D-Bus daemon can locate and execute the Python scripts when OmaFiles is used directly as a repository plugin.

A single commit has been made to the repository containing only this fix.
