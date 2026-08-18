# v1.1 Feature Inventory & Roadmap Audit

**Scope:** analysis/audit only. No source code was modified while producing this
document. No branches created, no commits, no pushes.

**Baseline:** `v1.1-dev`, created from `v1.0-dev` HEAD
`8a426281654311b96135b8c23d55e0edaa0ce095` (content identical at the time of
this audit — verified, no diff, no unique commits either direction).

**Method:** every claim below is grounded in the current tree (README, docs/,
QML, C++ backend, scripts, CMake, packaging, git history, existing audit
reports) — read directly, not recalled from memory or from README marketing
copy. File:line citations are given wherever the finding depends on a
specific piece of code or prose.

---

## 1. Audit of current state — what OmaFiles can actually do today

Summarized from a full pass over `core/`, `panels/`, `dialogs/`, `shared/`,
`logic/`, `state/`, `backend/` (C++), `src/selfcheck/`, `scripts/`,
`CMakeLists.txt`, `packaging/`, and all 19 `docs/audits/*.md` + 35
`docs/historical/*.md` reports.

OmaFiles is a Qt6/QML file manager with a shared native C++ backend
(`Omafiles.Backend`, one `.so`). As of `v1.0.0` it has, confirmed by reading
the actual implementation (not just the README):

- **File operations**: native async copy/move/remove/mkdir/rename/trash
  (`backend/FileOperations*.cpp`), cooperative per-operation cancellation
  tokens, undo/redo (20-step LIFO) covering rename, new file/folder,
  delete→trash, move, bulk rename, chmod, make-link. Copy and compress are
  deliberately excluded from undo ("ambiguous to undo", `state/UndoState.qml:6-11`).
- **Search**: filename search via `tracker3`→`plocate`→native recursive
  fallback (`scripts/runtime/search-index.sh`, `logic/SearchBackend.qml`);
  content search (`content:` prefix) via a native multithreaded C++ worker
  (`backend/SearchWorker.cpp`) — despite a stale file-header comment calling
  it a "ripgrep script" (`logic/SearchBackend.qml:29-30`), it is not ripgrep
  and not a script.
- **Archives**: browse zip/7z/rar/tar-family without extracting
  (`logic/ArchiveBrowser.qml`); extract all four; **compress always produces
  `.zip` only**, hardcoded, no alternative format
  (`logic/ActionEngine.qml:893-919`).
- **Previews**: text with native syntax highlighting (10+ language families),
  image/PDF via the thumbnail pipeline, video thumbnail only (no playback),
  audio metadata only (no playback).
- **Thumbnails**: persistent SHA-1-keyed cache, atomic writes, age/size
  pruning, symlink-attack fix in place and regression-tested.
- **Network locations**: gvfs enumeration (SFTP/FTP/WebDAV/SMB) and mount/auth
  via `backend/NetworkResolver`; credentials are **session-only**, never
  persisted.
- **Tabs/navigation**: per-tab history, bookmarks (persisted), recents (max
  20, persisted), breadcrumbs, native path completion.
- **Clipboard/drag & drop**: internal clipboard plus real Wayland
  interoperability (`wl-copy`/`wl-paste`, `text/uri-list`), drag-out to other
  apps supported, not just internal drag.
- **Desktop integration**: self-registers as default file manager,
  `org.freedesktop.FileManager1` and FileChooser portal both implemented via
  Python/GLib D-Bus services, single-instance enforced.
- **Configuration**: two optional TOML files (`actions.toml`,
  `keybindings.toml`), both read-only from the app's side — no in-app editor,
  no generated template, no settings panel (a stated design philosophy, see
  §7 and §10).
- **Custom keybindings**: full rebinding except 5 OS-convention shortcuts;
  one documented, known gap — `SearchBar`/command palette keep their own
  independent arrow-key navigation, unaffected by remaps
  (README.md:168, confirmed in code).
- **Accessibility**: partial — `Accessible.role`/`Accessible.name` present in
  18 QML files (63 uses), but no live regions, no high-contrast/font-scale
  accessibility option, zero selfcheck coverage.
- **Error reporting**: exclusively `notify-send` fire-and-forget
  (`backend/Notifier.cpp:8-14`); the code itself documents this as a stopgap
  ("the migration to QDBus is later work", `backend/Notifier.h:10-13`,
  written 2026-08-09, never revisited since).
- **Packaging**: Arch-only (`packaging/arch/PKGBUILD`); **no AUR package has
  ever actually been published** — confirmed by three independent audit
  reports (`RELEASE_PREPARATION_REPORT.md:37,101`,
  `FINAL_RELEASE_AUDIT.md:114-115`, `P2_6_FINAL_1_0_SCOPE_AUDIT.md:129`); an
  earlier "AUR publication report" describing it as done
  (`docs/historical/PHASE40_AUR_PUBLICATION_REPORT.md`) was itself later
  flagged by forensic audits as rehearsal documentation that didn't match the
  PKGBUILD actually on disk at the time.
- **Regression suite**: 124 selfchecks across 13 modules — strong coverage of
  filesystem ops/trash/undo/actions/keybindings, weaker or absent coverage of
  search-index.sh, the three D-Bus integration scripts, `NetworkResolver`
  end-to-end, `CustomActions.qml` (zero coverage), path completion,
  clipboard/drag-drop, accessibility.

---

## 2. Already-completed work — explicitly excluded

Per your list, none of the following appear anywhere in this document as
"remaining work," and all were independently re-verified against the current
code rather than taken on faith:

custom keybindings · alternating row colors · C++ backend migration · P0
concurrency fixes · copy/data-integrity fixes · archive extraction security
fixes · thumbnail/cache security fixes · packaging/install fixes ·
partial-batch cancellation fixes · per-operation cancellation tokens ·
backend import fixes · architecture documentation regeneration · ActionEngine
architectural cleanup · ArchiveBrowser extraction · shared-component contract
cleanup (`MarqueeCatcher.qml`, `PathCompletionField.qml`) · Debian feedback
fixes · dependency documentation audit.

Also independently confirmed done and therefore excluded even though not on
your list: bulk rename as a feature (exists since pre-1.0, only an
empty-name edge-case bug was fixed in 1.0), the Ctrl+L address-field
background fix, and the xdg-mime documentation fix from this session.

---

## 3. User-facing feature inventory

| Area | State | Notes |
|---|---|---|
| File operations | Implemented | Copy/move/delete/trash/rename/bulk-rename/chmod/undo-redo all present. Chmod still shells out (`chmod` binary), not native. |
| Undo/redo | Implemented, one known gap | See §6 — completion-timing gap, deliberately deferred, documented in `docs/architecture/ARCHITECTURE.md:200-213`. |
| Search (filename) | Implemented | tracker3→plocate→native fallback chain, untested end-to-end (only the native fallback has selfcheck coverage). |
| Search (content) | Implemented | Native C++, no indexed backend for content (by design — content search is inherently exhaustive). |
| Archives — browse/extract | Implemented | zip/7z/rar/tar-family. |
| Archives — compress | Implemented, single-format | `.zip` only, hardcoded. Extending to `.tar.gz`/`.7z` is a genuine, scoped feature gap. |
| Archives — `.zst` | Inconsistent | Shown with an archive icon (`FileTypeConfig.archiveExt`) but not browsable/extractable (`isArchive()` doesn't include it) — small, self-contained bug. |
| Previews — text/image/PDF | Implemented | Native, fast. |
| Previews — video/audio playback | **Missing** | Only a static thumbnail (video) or metadata (audio) — no inline playback. Genuinely user-visible gap; see §9. |
| Thumbnails | Implemented | Cache, invalidation, symlink-attack fix all confirmed present. |
| Network locations (gvfs) | Implemented, credentials session-only | No persistent "remembered connection." See §9 for a scoped-down MVP. |
| Tabs/panels | Implemented | Per-tab history/preview/search state. |
| Navigation/bookmarks | Implemented | Persisted bookmarks + recents, default bookmark set. |
| Clipboard | Implemented | Internal + real Wayland system-clipboard interop. |
| Drag & drop | Implemented | Internal and to/from other apps; **zero selfcheck coverage**. |
| Bulk rename | Implemented | Pattern substitution, empty-name and duplicate detection. No regex/numbering/live-preview — possible small P2 enhancement, not urgent. |
| Permissions (chmod) | Implemented | Shell-based, not native; undo-covered. |
| Desktop integration | Implemented, extensively | Default-file-manager registration, FileManager1, FileChooser portal, single-instance. Zero selfcheck coverage of the actual D-Bus services (only that the install script resolves to a real file). |
| Configuration | Implemented, no UI | Two optional TOML files, read-only from the app, no generated template, no settings panel (deliberate philosophy, see §7/§10). |
| Accessibility | Partial | `Accessible.*` in 18 files; no live regions, no accessibility-oriented scaling, zero test coverage. Real gap, likely low priority for this project's actual audience. |
| Keyboard workflow | Implemented, extensively | Full rebinding, validation, help overlay always in sync; one documented gap (SearchBar/palette arrow-nav, see §6). |
| Update mechanism | **Missing entirely** | Deliberately not built yet — see §7, full investigation there. |
| Error reporting | Implemented, minimal | `notify-send` only, fire-and-forget, no history, no severity distinction beyond message text. Self-documented stopgap since 2026-08-09. Real gap; see §9. |

---

## 4. User feedback inventory

### Already fixed
- **Debian Sid tester feedback** (commit `d662782`, 2026-08-17):
  - Ctrl+L address field had no visible background → fixed same commit.
  - Alternating row colors, requested → deferred in that commit, **shipped
    the same day** in P2.4.
- **Reddit/Colemak feedback** ("`hjkl` navigation isn't ergonomic on
  non-QWERTY layouts") → shipped as the full custom-keybindings system
  (P2.5), with the SearchBar/palette limitation explicitly and prominently
  documented rather than silently left broken.

### Partially addressed
- **Debian Sid "Trash freeze" + Column/anchors warning report**: investigated
  extensively (empty/1/many/50 items, restore, permanent delete, repeated
  enter/leave) — **could not be reproduced**. Three regression guards were
  added defensively anyway, but the reported symptom itself was never
  confirmed or disproven. Listed as a genuine open known issue in §6.

### Still outstanding
- Nothing else was found framed as unresolved user-reported feedback beyond
  the two items above — there is no dedicated feedback-tracking file/folder
  in the repo; everything traceable lives in commit bodies and audit
  documents.

### Feature requests worth considering
- Nothing beyond what's already reflected in the shipped keybindings system
  and the feature-gap analysis in §3/§9. No recurring, multi-source feature
  request pattern (e.g. "the same complaint from 3+ people") was found in the
  available record — the feedback corpus here is small (one Debian tester
  pass, one Reddit mention), not a large backlog to mine.

---

## 5. Developer/architecture inventory

Only flagging items with a concrete, stated benefit — not proposing cleanup
for its own sake.

| Item | Concrete benefit | Risk if left alone |
|---|---|---|
| `backend/Notifier` still spawns `notify-send` per call instead of using `org.freedesktop.Notifications` over QDBus | Enables proper urgency levels, notification IDs (dedup/replace instead of stacking), and — combined with §9's in-app history — stops errors from being silently lost when a desktop notification is missed or DND is on | None (it works today); this is a stopgap the code itself has flagged as such since 2026-08-09 and nobody has revisited |
| Missing regression coverage: `search-index.sh` end-to-end, the 3 D-Bus integration scripts, `NetworkResolver` end-to-end, `CustomActions.qml` (zero coverage), `PathCompleter`, clipboard/system-clipboard sync, drag & drop | These are exactly the areas most likely to silently regress across Qt/distro updates, and none of them are covered by the 124-check suite today | Regressions in these areas would currently ship undetected |
| `-Wall -Wextra` not enabled anywhere in `CMakeLists.txt` | Zero-cost way to surface latent bugs the compiler can already see; explicitly named as deferred in 3 separate audit reports | Low, but free to fix |
| `packaging/arch/PKGBUILD` `sha256sums` still holds the **0.9.0** tarball's hash under a `pkgver=1.0.0` declaration (`PKGBUILD:20`, explicit `FIXME`) | Trivial, now-unblocked fix — the `v1.0.0` tag was created and published earlier in this same session, so the real hash (`44118a4be1cd449d4e932d2aa94dcd6244926c65eab37a405f5a52fdb9c537af`, computed against GitHub's generated source archive during that publication) is already known and just needs writing in | Anyone attempting to build this PKGBUILD as-is today gets a checksum mismatch against the real v1.0.0 tarball |
| `scripts/install-integrations.sh` hardcodes `${XDG_DATA_HOME:-$HOME/.local/share}/omafiles` even under a hypothetical `/usr`-prefixed system install | Blocks real AUR publication — flagged as such in `FINAL_RELEASE_AUDIT.md:114-115` and `RELEASE_PREPARATION_REPORT.md:101` | AUR package (if published as-is) would install its desktop/D-Bus integration files to the wrong, user-specific path regardless of who actually installed it |
| `CommandFacade.qml` internal duplication, flagged in P2.1 for its own follow-up audit, never done | Unknown size/benefit until someone actually looks — do **not** blindly refactor; do a short scoped investigation first | Low — nothing is broken today, this is speculative debt |
| `ActionEngine.qml` is 1220 lines, the product of two prior merges (`DragDropOps.qml`, `ConflictActions.qml`, archive logic folded in) | **Explicitly audited and deliberately kept intact** by P2.1 — re-splitting it was already considered and rejected once | See §10 — don't propose this again without new justification |

---

## 6. Known issues (deliberately deferred, verified still present)

| Issue | Still present? | Source |
|---|---|---|
| Undo/redo completion-timing gap: `pushUndo()` only fires inside the operation's own success callback; a Ctrl+Z pressed while the operation is still in flight silently no-ops (no queue, no feedback) | **Yes, confirmed present** | `docs/architecture/ARCHITECTURE.md:200-213`, cross-checked against `logic/ActionEngine.qml:35-36, 368-387` |
| `list-archive.sh`: empty/invalid archive listing quirk — documented via selfcheck test names ("documents pre-existing list-archive.sh quirk"), not actually fixed, only confirmed non-crashing | **Yes, still present** (distinct from the 7z top-level-folder ordering bug below, which **was** fixed) | `docs/audits/P2_3_ARCHIVE_EXTRACTION_REPORT.md:142-148`, `src/selfcheck/checks/CheckActions.qml` |
| `list-archive.sh`: 7z top-level-folder-misclassified-as-file (tool output ordering) | **Fixed** — two-pass collect-then-print approach | `scripts/runtime/list-archive.sh:38-46` |
| `shared/` contract violations | **Fixed** (both instances) | CHANGELOG.md `[1.0.0]`, "Architectural cleanup" |
| Remaining `core/` duplication follow-up (`CommandFacade.qml`, originally a "P2.2" that never happened) | **Still open**, unscoped | `docs/audits/P2_1_ACTIONENGINE_SHARED_AUDIT.md:248` |
| `-Wall -Wextra` not enabled | **Still true** | `CMakeLists.txt` (no warning flags anywhere) |
| Generic/misleading error messages | **Partially fixed** (the specific "Couldn't restore from trash" mislabel from 1.0's CHANGELOG); the underlying single-mechanism, no-history notification design remains, see §5 | CHANGELOG.md `[1.0.0]`, `backend/Notifier.h:10-13` |
| Bulk rename | **Resolved** — the empty-target-name edge case shipped fixed in 1.0.0, feature itself predates this cycle | CHANGELOG.md `[1.0.0]` |
| Trash "freeze" + Column/anchors warning, Debian tester report | **Unresolved, unreproduced** — 3 defensive regression guards added, root cause never confirmed | commit `d662782` body |
| SearchBar/command-palette independent arrow-key navigation, unaffected by keybinding remaps | **Present, intentional and documented** | README.md:168, `docs/audits/P2_5_CUSTOM_KEYBINDINGS_AUDIT.md:394-399` |
| `backend/Notifier` uses `notify-send` subprocess, not native QDBus notifications | **Still true**, deferred since commit `48b59f1` (2026-08-09), never revisited by any later audit | `backend/Notifier.h:10-13` |

---

## 7. Update mechanism investigation

**How OmaFiles is installed today:** almost exclusively manual/source
(`git clone` → `cmake --install` to `~/.local/...`, README.md:229-254). A
Arch `PKGBUILD` exists in-tree but **has never actually been published to
AUR** (confirmed by three independent audit reports, see §1). The PKGBUILD
overrides the default per-user install paths to `/usr/...` for packaging,
but the desktop-integration installer script (`install-integrations.sh`)
still hardcodes the per-user path regardless — a real blocker for AUR
publication (§5).

**Where version info lives today:** only `CMakeLists.txt:2`
(`project(omafiles VERSION 1.0.0 ...)`). It is **not** plumbed into the
running application at all — no `Q_PROPERTY`, no QML singleton, no
`app.setApplicationVersion()` call. This is a real, small prerequisite that
doesn't exist yet, confirmed by grep across the entire QML/C++ tree and
independently flagged in `docs/audits/P2_6_FINAL_1_0_SCOPE_AUDIT.md:132`.

**GitHub Releases:** now genuinely in use — `v1.0.0` tag and "OmaFiles 1.0.0"
GitHub Release were published earlier in this session. No code anywhere
queries the GitHub API, AUR RPC, or any remote version source today — this
would be entirely new.

### Design options

**A — Package-manager delegation via ownership detection (recommended).**
This is the design the project's own P2.6 audit already converged on
(`docs/audits/P2_6_FINAL_1_0_SCOPE_AUDIT.md:117-134`), and it holds up under
independent review:
- Detect install method via `pacman -Qo <path-to-running-binary>` — verified
  empirically in that audit to correctly report "no package owns this file"
  for the current manual/dev install.
- **Never poll automatically.** Update check is a manual, opt-in "Check for
  updates" trigger — no background timer, no daemon. Silent polling would be
  the app's first-ever telemetry-adjacent behavior, and nothing else in this
  codebase does that.
- On click: query AUR RPC (once actually published) or the GitHub Releases
  API for the latest tag, compare against the compiled-in `APP_VERSION`.
- If a pacman-owned install and an update exists: **open a terminal with
  `pacman -Syu omafiles` pre-filled, never auto-execute it.** Reuses the
  existing `Backend.TerminalResolver.launchTerminal()` (already used for
  "open terminal here").
- If ownership detection fails (unmanaged install, unknown path): the
  original audit recommended hiding the button entirely. **My refinement**:
  since the manual/`~/.local` build is the *dominant* real install path
  today (not an edge case), fully hiding the feature from the majority of
  actual users seems wasteful. Prefer a second, purely informational path
  (below) for this case instead of silence.

**B — Passive, informational-only version banner (recommended as a
complement to A, not a standalone design).** For installs where package
ownership can't be detected: same manual opt-in trigger, same GitHub
Releases API call, but the result is just "You're on v1.0.0 — v1.1.0 is
available, see the release page" with a link. No command is run, nothing is
downloaded, nothing is executed — purely informational, identical trust
model to reading the README by hand.

**C — In-app self-updating downloader (explicitly rejected).** Download a
new binary/tarball and swap it in directly, bypassing the package manager
entirely. This is exactly the pattern the task's own constraints rule out
("must NOT become a mechanism for downloading arbitrary executables"): it
would need to independently verify signatures/checksums, would conflict with
the package-manager-agnostic install model, and the trust surface (fetch +
execute arbitrary code, replace a running binary in place) is the highest of
any option here for the least benefit over A+B. **Do not build this.**

### Recommendation

Adopt **A+B combined**, gated on a real prerequisite chain: (1) `APP_VERSION`
plumbed into QML/C++ at build time — small, unblocked, do this regardless;
(2) an actual AUR package published (§9 headline #1) — without it, option A
has nothing to detect ownership of, and the update check has no meaningful
"latest version" source to compare against yet for the dominant Arch
audience. **This is why an update-check feature is explicitly not proposed
as a v1.1 headline in §9** — it is well-designed and ready to build, but its
own precondition (a published, stable AUR package with at least one real
version bump behind it) can't be satisfied inside the same release that
first publishes the package.

---

## 8. Ranked roadmap

### P0 — Critical correctness/security/data-loss/crash issues

**None identified.** No confirmed crash, data-loss, or security issue
remains open in the current tree — the P0 forensic-audit findings from
2026-08-16 were all remediated and verified (ASan-clean) before the 1.0.0
release. This is a genuinely good sign for the baseline v1.1 is starting
from, not an oversight in this audit.

### P1 — Important bugs or high-value functionality

| Title | State | User benefit | Complexity | Arch. risk | Blockers |
|---|---|---|---|---|---|
| Fix `PKGBUILD` `sha256sums` (stale 0.9.0 hash under `pkgver=1.0.0`) | Broken, `FIXME`-flagged | Low direct (no published package yet), but unblocks AUR work | Trivial (one line; correct hash already known: `44118a4be1cd449d4e932d2aa94dcd6244926c65eab37a405f5a52fdb9c537af`) | None | None — fully unblocked now |
| Fix `install-integrations.sh` hardcoded `$HOME/.local/share` path | Broken for system installs | Enables real AUR publication | Moderate (needs install-prefix-aware path resolution) | Low, self-contained script | Needed before any AUR submission |
| Plumb `APP_VERSION` into QML/C++ runtime | Missing entirely | Prerequisite for any future update mechanism | Small | None | Blocks update-mechanism work (§7) |
| Undo/redo completion-timing gap | Present, documented | Fixes a real (if narrow) correctness edge case | Moderate–high (~10 `pushUndo()` call sites need completion hooks; `FileOperations.mkdir()` has no `onDone` param at all today) | Medium — touches many call sites | None |
| Missing regression coverage (search-index.sh, D-Bus scripts, NetworkResolver, CustomActions.qml, PathCompleter, clipboard, drag&drop) | Absent | Long-term stability, catches silent regressions | Moderate (integration-style tests) | Low | None |
| `backend/Notifier` still uses `notify-send` subprocess | Present, self-flagged stopgap since 2026-08-09 | Enables proper severity/history (feeds headline #2, §9) | Moderate | Low | None |

### P2 — Useful improvements, UX polish, technical cleanup

| Title | State | User benefit | Complexity | Arch. risk |
|---|---|---|---|---|
| `.zst` shown with archive icon but not browsable/extractable | Inconsistent | Small correctness fix | Trivial | None |
| Enable `-Wall -Wextra` in `CMakeLists.txt` | Absent | Surfaces latent bugs for free | Trivial to enable, unknown effort to clean resulting warnings | Low |
| Investigate `CommandFacade.qml` duplication (scoped look only, not a blind refactor) | Flagged, never scoped | Unknown until investigated | Small (investigation) | None until a fix is designed |
| SearchBar/command-palette independent arrow-nav, unaffected by keybinding remaps | Present, documented limitation | Small keyboard-consistency win | Small | Low |
| Stale "ripgrep" comment in `SearchBackend.qml:29-30` | Doc drift | None (accuracy only) | Trivial | None |
| Advanced bulk rename (regex/numbering/live preview) | Basic version already works | Nice-to-have for power users | Moderate | Low |
| Compress to formats beyond `.zip` | Missing | Moderate — some users expect `.tar.gz`/`.7z` output | Moderate | Low |

---

## 9. v1.1 headline features

Four candidates, chosen for genuine user-visibility, not for being the
easiest items on the list.

### 1. Publish OmaFiles on AUR
**Why it belongs in v1.1:** this is the single highest-leverage thing that
could happen to this project's reach — right now the *only* real
installation path is "clone and build from source," which is a hard barrier
for the average Arch/CachyOS/Omarchy user this app is aimed at. Everything
needed is already 90% built (`PKGBUILD` exists, the release tag/checksum
problem is now trivially fixable, per §8).
**MVP:** fix `install-integrations.sh`'s hardcoded path, regenerate the
`sha256sums` against the real v1.0.0 tarball, actually submit to AUR.
**Explicitly NOT included:** Debian/`.deb`, Fedora/`.rpm`, Flatpak, or
AppImage packaging — single-distro scope, matching what the project already
supports everywhere else.

### 2. Native desktop notifications + in-app notification history
**Why it belongs in v1.1:** the current error-reporting story is exactly one
`notify-send` call with no history — this is directly implicated in the
unreproduced "Trash freeze" report (§6): if the user missed the one-shot
desktop notification, there's no way to find out afterward what happened.
This is both a real technical-debt item the code already flags (§5) and a
user-visible reliability gap.
**MVP:** migrate `backend/Notifier` to `org.freedesktop.Notifications` over
QDBus (proper icons/urgency, replaces the subprocess spawn), plus a small,
keyboard-accessible "recent notifications" panel so a missed toast isn't
lost forever.
**Explicitly NOT included:** a full notification center, actionable buttons
inside notifications (e.g. inline "Undo" from a notification), persistent
cross-session history, or any settings around notification behavior — all
scope creep for what's fundamentally a reliability fix.

### 3. Inline video & audio preview playback
**Why it belongs in v1.1:** this is the most concretely "users would
actually notice" gap in the current feature set — every comparable file
manager (Nautilus, Dolphin, PCManFM) plays media inline, and OmaFiles today
only shows a static thumbnail/metadata. It's a real feature gap, not
polish.
**MVP:** basic play/pause inline playback in the existing Preview panel for
formats already thumbnailed/metadata'd today, via Qt Multimedia (a new
dependency for this project — worth naming explicitly as the one added
external Qt module this cycle).
**Explicitly NOT included:** scrubbing/waveform visualization, playlists,
subtitle support, volume-level persistence — a media player is not the
product; a quick look is.

### 4. Saved network-connection profiles (not credentials)
**Why it belongs in v1.1:** gvfs network locations are supported but forget
everything on session end — a real, noticed friction point for anyone using
SFTP/SMB regularly. A naive fix (persisting passwords) would add a new
secure-storage dependency and a real security surface; a scoped-down version
avoids that entirely.
**MVP:** persist the connection *profile* (address, port, protocol,
username) via the already-existing `Backend.JsonStore` mechanism (same one
used for bookmarks/recents) — the user still has to type the password each
time, but no longer has to retype the whole server URI.
**Explicitly NOT included:** actual credential/password persistence, any new
dependency on a secret-storage service (libsecret/keyring) — that's a
legitimately larger, separate security-reviewed feature for a future cycle,
not v1.1.

**Not included as a headline, despite being fully investigated (§7): an
update-check button.** It's well-designed and ready, but it depends on
headline #1 landing and being stable first — there's nothing meaningful to
check updates against in the same cycle that first publishes the package.

---

## 10. Things we should NOT do in v1.1

- **Re-split `ActionEngine.qml`.** This was already audited and deliberately
  rejected once (`docs/audits/P2_1_ACTIONENGINE_SHARED_AUDIT.md`). Nothing
  new has changed that reopens that decision — don't propose it again
  without a concrete new trigger.
- **Build a settings/preferences panel.** The project's own reasoning against
  an update-check *toggle* generalizes: "no view-mode dropdowns, no
  icon-size sliders, no settings panel" is a stated design philosophy, not
  an oversight. Config stays TOML-file-based and read-only from the app.
- **Build the self-updating downloader (design C in §7).** Explicitly the
  wrong shape for this project — bypasses the package manager, adds a
  large trust/security surface, and the task's own constraints already rule
  it out.
- **Multi-distro packaging (deb/rpm/flatpak/AppImage) this cycle.** Getting
  a *working, real* AUR package published is itself the headline; spreading
  effort across four packaging formats before the first one is even live
  would be premature scope expansion.
- **Persist gvfs credentials/passwords.** A real feature, but it needs its
  own security review and a secret-storage dependency decision — folding it
  into v1.1 "while we're in the network-locations code anyway" would be
  exactly the kind of scope creep this section exists to reject. The
  connection-profile-only version in §9 is the right-sized piece for now.
- **Blind-refactor `CommandFacade.qml`.** It's flagged, but nobody has
  actually sized the duplication yet. Investigate first (P2, §8); don't
  schedule a refactor before knowing what it would even fix.
- **Chase the "Trash freeze" report by adding more speculative guards.**
  Three defensive guards were already added without ever reproducing the
  underlying issue. The right next step is better diagnostics (headline #2's
  notification history) so that *if* it happens again, there's finally
  something to look at — not a fourth guard added on a hunch.
- **Treat this document's P2 list as a queue to clear mechanically.** Several
  P2 items (accessibility, advanced bulk rename, compress-to-other-formats)
  are real but genuinely optional — v1.1 should ship when the P1s and the
  four headline features are done, not when every P2 row has a checkmark.
