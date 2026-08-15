# OmaFiles PR #2: Installation Model Fix Report

## Architectural Correction
The previous hotfix that hardcoded `SELF_RES` (the Omarchy plugin directory) into the D-Bus `.service` files violated the standalone nature of OmaFiles. OmaFiles is a Qt6 application that must remain independent of the Omarchy directory structure, meaning it should work equally well when launched from a standalone installation or a source checkout.

To enforce this, we reverted the `Exec` paths in the generated `.desktop` and `.service` files back to `$RES_DIR` (the stable canonical resource location, typically `~/.local/share/omafiles`).

## The Solution
To accommodate the use case where a user runs OmaFiles as a plugin without performing a full `cmake --install`, a graceful fallback was added to `install-integrations.sh`. 

The script now automatically copies the `scripts/` directory from the repository (`$SELF_RES`) to the canonical location (`$RES_DIR`) during integration setup, if they are not the same directory.

### Exact Patch Details
The following block was inserted into `install-integrations.sh`:
```bash
# Ensure runtime scripts are available in the canonical resource directory
# without requiring a full cmake --install (e.g. when run from a plugin repo).
if [[ "$SELF_RES" != "$RES_DIR" && -d "$SELF_RES/scripts" ]]; then
  cp -r "$SELF_RES/scripts" "$RES_DIR/"
fi
```
Additionally, all `.service` files and the `.desktop` file were restored to use `Exec=$RES_DIR/scripts/...`.

## Validation
After clearing the existing scripts and re-running `install-integrations.sh`, the following was verified:

1. **Script Placement**: `dbus-filechooser.py` exists and is fully executable at `/home/josema/.local/share/omafiles/scripts/dbus-filechooser.py`.
2. **Service File Configuration**: The generated D-Bus service file correctly points to the `$RES_DIR` path:
   ```ini
   [D-BUS Service]
   Name=org.freedesktop.impl.portal.desktop.omafiles
   Exec=/home/josema/.local/share/omafiles/scripts/dbus-filechooser.py
   ```
3. **D-Bus Activation**: Sending a ping to `org.freedesktop.impl.portal.desktop.omafiles` successfully launched the Python daemon at the canonical location and returned a valid response.

Zen Browser (and any other application using the XDG Desktop Portal) will now successfully open the OmaFiles picker, regardless of whether OmaFiles was installed globally or run locally as a plugin.

A single clean commit containing this fix has been created.
