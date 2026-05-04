# Dash-to-Dock intellihide patch — Specification

**Investigated:** 2026-05-04
**Outcome:** ✅ **CLOSED — Option A selected. No patch implemented.**

## Resolution Summary

The user confirmed they are running Dash-to-Dock **v105**. All three signal
hooks proposed in the original AI-generated patch are already present in v105
(see §1.4). The extension was re-enabled across all four DE roles
(`modules/gnome-desktop.nix`, `modules/gnome-htpc.nix`,
`modules/gnome-server.nix`, `modules/gnome-stateless.nix`) on 2026-05-04
after having been commented out due to the autohide bug. v105 includes upstream
fixes in the same general area (`Properly disconnect various signal
connections`, `Fix delayed staged dock`, `Dash init glitches`). The decision
was to test with v105 unmodified and revisit only if the staleness symptom
persists.

If the issue recurs after testing, the next steps are (in order):
1. **Option B** — capture a `journalctl --user -u gnome-shell` reproduction
   and identify the actual signal/exception before patching anything.
2. **Option C** — try/catch hardening only (see §3.2 for the exact diff
   shape, and §4 for implementation steps). Do NOT add the buggy
   `_queueUpdate()` fallback from the original draft.
3. **Option D** — pin the `gnomeExtensions.dash-to-dock` src directly to a
   specific upstream tag via `overrideAttrs` to bypass nixpkgs lag.

---

**Status:** ⛔ **ORIGINAL PATCH — DO NOT IMPLEMENT AS DRAFTED.** Research shows
the proposed signal-hook additions are redundant with upstream and the only
remaining candidate change (try/catch around the per-window overlap test) does
not meet the project's `<implementationDiscipline>` bar in isolation.

This spec documents the research findings, the verbatim upstream source the
draft was checked against, and a recommended path forward. Phase 2 should NOT
generate `files/patches/dash-to-dock-intellihide.patch` or modify
`modules/gnome.nix` until the user confirms one of the alternative paths in
section 8.

---

## 1. Current state analysis

### 1.1 Dash-to-Dock version landscape

| Source | Version | Tag / commit | Notes |
|---|---|---|---|
| Upstream latest | **v105** | tag `extensions.gnome.org-v105`, commit `b1478f10a3fca9eaa5dc9d2f9907c20427e269f6` | Released ~3 weeks ago. GNOME Shell 45 – 50. |
| Upstream prior  | v104 | tag `extensions.gnome.org-v104`, commit `69c6ee5c7669b0a3b0077467cdbbcf3b39ddc44a` | Released 2026-03-23. |
| `nixos-unstable` | **must verify at implementation time** | `pkgs/desktops/gnome/extensions/extensions.json` is auto-generated and exceeds GitHub's blob viewer limit (7.83 MB), so the precise pinned version cannot be read inline. Phase 2 must run `nix eval --raw nixpkgs#gnomeExtensions.dash-to-dock.version` against the same `nixpkgs-unstable` revision pinned in [flake.lock](../../../flake.lock) before authoring any patch. |

The package consumer in this repo is [modules/gnome.nix](../../../modules/gnome.nix) line 212:

```nix
unstable.gnomeExtensions.dash-to-dock               # macOS-style dock
```

`pkgs.unstable` is constructed by `unstableOverlayModule` in
[flake.nix](../../../flake.nix) lines 44–53 by importing
`nixpkgs-unstable` as a fresh package set. `pkgs.unstable.gnomeExtensions.*`
is therefore evaluated independently of any overlay applied to top-level
`pkgs.gnomeExtensions.*`.

### 1.2 Verbatim upstream `intellihide.js` — signal-registration block

From <https://github.com/micheleg/dash-to-dock/blob/extensions.gnome.org-v105/intellihide.js> (constructor body):

```js
// Connect global signals
this._signalsHandler.add([
    // Add signals on windows created from now on
    global.display,
    'window-created',
    this._windowCreated.bind(this),
], [
    // triggered for instance when the window list order changes,
    // included when the workspace is switched
    global.display,
    'restacked',
    this._checkOverlap.bind(this),
], [
    // when windows are alwasy on top, the focus window can change
    // without the windows being restacked. Thus monitor window focus change.
    this._tracker,
    'notify::focus-app',
    this._checkOverlap.bind(this),
], [
    // update wne monitor changes, for instance in multimonitor when monitor are attached
    Utils.getMonitorManager(),
    'monitors-changed',
    this._checkOverlap.bind(this),
]);
```

The `_signalsHandler.add(...)` API takes one nested array per `(emitter,
signal, callback)` triple. Any patch must follow that same shape.

### 1.3 Verbatim upstream `_doCheckOverlap` per-window loop

```js
_doCheckOverlap() {
    if (!this._isEnabled || !this._targetBox)
        return;

    let overlaps = OverlapStatus.FALSE;
    let windows = global.get_window_actors().filter(wa => this._handledWindow(wa));

    if (windows.length > 0) {
        // ... topWindow / focusApp computation elided ...

        if (topWindow) {
            this._topApp = this._tracker.get_window_app(topWindow);
            this._focusApp = this._tracker.focus_app || this._topApp;

            windows = windows.filter(this._intellihideFilterInteresting, this);

            for (let i = 0;  i < windows.length; i++) {
                const win = windows[i].get_meta_window();

                if (win) {
                    const rect = win.get_frame_rect();

                    const test = (rect.x < this._targetBox.x2) &&
                               (rect.x + rect.width >= this._targetBox.x1) &&
                               (rect.y < this._targetBox.y2) &&
                               (rect.y + rect.height >= this._targetBox.y1);

                    if (test) {
                        overlaps = OverlapStatus.TRUE;
                        break;
                    }
                }
            }
        }
    }

    if (this._status !== overlaps) {
        this._status = overlaps;
        this.emit('status-changed', this._status);
    }
}
```

Note this is a `for ... break` loop, **not** `windows.some(...)` as the
user's draft suggested. There is already a `if (win)` null-guard.

### 1.4 Status of each proposed signal hook

| Proposed hook | Already wired in v105? | Evidence |
|---|---|---|
| `global.display 'window-created'`           | ✅ **already present** | First entry in the `_signalsHandler.add(...)` block above. |
| `global.display 'restacked'`                | ✅ **already present** | Second entry in the block. |
| `global.window_manager 'switch-workspace'`  | ⚠️ **redundant** | Not literally hooked, but the upstream comment on `'restacked'` explicitly states *"included when the workspace is switched"*. Mutter emits `restacked` immediately after a workspace switch, which already triggers `_checkOverlap`. Adding a second hook on `switch-workspace` would only cause a duplicate `_checkOverlap` call (debounced into the same 100 ms `INTELLIHIDE_CHECK_INTERVAL` window) and would not change behaviour. |

**Conclusion for §1.4:** of the three hooks the draft proposed, **two are
literally already there** and **the third is functionally redundant**. The
signal-hook portion of the proposed patch is a no-op.

---

## 2. Problem definition (and why the draft does not address it)

The reported symptom is "intellihide stays stale": the dock fails to
re-show / re-hide promptly after window state changes on Wayland.

The draft attributed this to (a) missing signal hooks and (b) an unguarded
exception in the per-window overlap loop. Research shows:

- **(a) is wrong against current upstream.** All hooks the draft would add
  are already wired in v105 (see §1.4).
- **(b) is theoretically possible** — `meta_window_get_frame_rect()` can
  throw on a stale Wayland actor whose `MetaWindow` has been disposed
  between `get_window_actors()` and `get_frame_rect()`. If it throws,
  `_doCheckOverlap` aborts before reaching the `_status !== overlaps`
  comparison and `'status-changed'` is never emitted, leaving the dock in
  the previous visibility state until the next signal trigger. **However**:
  - The next signal trigger is the 100 ms `INTELLIHIDE_CHECK_INTERVAL`
    timer (set up by `_checkOverlap`), so worst-case staleness is 100 ms,
    not unbounded.
  - We have no reproducer or stack trace tying the user's symptom to this
    code path.
  - v105's release notes explicitly include `Docking: Properly disconnect
    various signal connections`, `Fix delayed staged dock`, and `Dash init
    glitches` — i.e. upstream has been actively fixing dock-state-stuck
    bugs in this exact area in the most recent release.

In short: the draft was written against a mental model of intellihide.js
that does not match the current code, and the residual try/catch idea fixes
a hypothetical race we have no evidence is the actual root cause of the
user's symptom.

---

## 3. Proposed solution architecture

**None.** No patch file is specified. No overlay edit to `modules/gnome.nix`
is specified. See §8 for alternatives.

For completeness, the technical reference data needed if a patch is
authored later:

### 3.1 Overlay injection point (verified)

`pkgs.unstable.gnomeExtensions.dash-to-dock` is the consumer reference. It
resolves through `unstableOverlayModule` in flake.nix, which exposes
`unstable` via:

```nix
nixpkgs.overlays = [
  (final: prev: {
    unstable = import nixpkgs-unstable {
      inherit (final) config;
      inherit (final.stdenv.hostPlatform) system;
    };
  })
];
```

A *third* inline overlay added at the **end** of the existing
`nixpkgs.overlays = [ ... ]` list in
[modules/gnome.nix](../../../modules/gnome.nix) lines 19–60 *can* shallow-merge
a patched derivation onto the already-imported `prev.unstable` set:

```nix
(final: prev: {
  unstable = prev.unstable // {
    gnomeExtensions = prev.unstable.gnomeExtensions // {
      dash-to-dock = prev.unstable.gnomeExtensions.dash-to-dock.overrideAttrs (old: {
        patches = (old.patches or []) ++ [ ../files/patches/dash-to-dock-intellihide.patch ];
      });
    };
  };
})
```

This works because:

- Overlay order in `modules/gnome.nix` is: (1) unstable-pin top-level
  overrides, (2) Extensions-app desktop-file removal, (3) the new patch
  overlay would be third — by which point `prev.unstable` is the
  fully-imported nixpkgs-unstable instance.
- `prev.unstable` is a plain attrset (not a fixed-point), so `//` merging
  is valid. The unstable module list in flake.nix only sets `unstable`
  once and never re-reads it, so re-binding `unstable` in `final` does not
  trigger infinite recursion.
- The path `../files/patches/dash-to-dock-intellihide.patch` is correct
  relative to `modules/gnome.nix` (the `files/` directory is at repo root;
  `modules/` is one level deep).
- `gnomeExtensions.dash-to-dock` is built by `buildGnomeExtension.nix`
  which inherits `stdenv.mkDerivation`'s default `patchPhase`. The
  fetchzip source uses `stripRoot = false` and contains the JS files at
  the root of the extension folder; a unified diff with `a/intellihide.js`
  / `b/intellihide.js` headers and the standard `-p1` patchFlags will
  apply cleanly **provided the patch context matches the version actually
  pinned in nixos-unstable** (see §6).
- Context7-confirmed idiom: `overrideAttrs (old: { patches = (old.patches
  or []) ++ [ … ]; })` is the canonical nixpkgs pattern for appending
  patches to an existing derivation (per
  `/websites/nixos_manual_nixpkgs` overlay/overrideAttrs reference).

**Alternative injection point** (not recommended for this repo): adding
`overlays = [ patchOverlay ];` to the `import nixpkgs-unstable { … }` call
inside `unstableOverlayModule` in flake.nix would also work and would be
slightly more "correct" semantically (the patch becomes a property of
`unstable` itself rather than a downstream re-binding). It is rejected
because (a) the existing repo pattern keeps GNOME-related overlays in
`modules/gnome.nix`, and (b) the same patch file path issue applies.

### 3.2 If a patch is later written

A justified patch — restricted to the try/catch hardening only, **not**
the redundant signal hooks — would target the per-window loop in §1.3 and
look like:

```diff
--- a/intellihide.js
+++ b/intellihide.js
@@
             windows = windows.filter(this._intellihideFilterInteresting, this);

             for (let i = 0;  i < windows.length; i++) {
                 const win = windows[i].get_meta_window();

-                if (win) {
-                    const rect = win.get_frame_rect();
-
-                    const test = (rect.x < this._targetBox.x2) &&
-                               (rect.x + rect.width >= this._targetBox.x1) &&
-                               (rect.y < this._targetBox.y2) &&
-                               (rect.y + rect.height >= this._targetBox.y1);
-
-                    if (test) {
-                        overlaps = OverlapStatus.TRUE;
-                        break;
-                    }
+                if (win) {
+                    let test = false;
+                    try {
+                        const rect = win.get_frame_rect();
+                        test = (rect.x < this._targetBox.x2) &&
+                               (rect.x + rect.width >= this._targetBox.x1) &&
+                               (rect.y < this._targetBox.y2) &&
+                               (rect.y + rect.height >= this._targetBox.y1);
+                    } catch (_e) {
+                        // Wayland actor went stale between get_window_actors()
+                        // and get_frame_rect(); skip this window so the
+                        // overlap check still completes and 'status-changed'
+                        // is emitted with the latest computed value.
+                        test = false;
+                    }
+
+                    if (test) {
+                        overlaps = OverlapStatus.TRUE;
+                        break;
                     }
                 }
             }
```

The diff above is **illustrative only**. Exact line numbers and surrounding
whitespace depend on the version actually pinned in `nixos-unstable` at
implementation time, which Phase 2 must verify per §1.1.

The buggy `if (!overlaps && windows.length > 0) { this._queueUpdate(); }`
fallback from the user's original draft is **explicitly excluded** — it
would re-trigger `_checkOverlap` whenever no windows overlap (i.e. every
idle frame), causing an infinite update loop.

---

## 4. Implementation steps

**Phase 2 must NOT proceed.** Return to the user with the §8 alternatives.

If the user picks alternative C (proceed with try/catch hardening only),
the steps are:

1. Run `nix eval --raw .#nixosConfigurations.vexos-desktop-amd.pkgs.unstable.gnomeExtensions.dash-to-dock.version`
   to read the exact version currently pinned by flake.lock.
2. Fetch the `intellihide.js` for that exact tag from
   `https://raw.githubusercontent.com/micheleg/dash-to-dock/extensions.gnome.org-v<N>/intellihide.js`.
3. Author `files/patches/dash-to-dock-intellihide.patch` with the §3.2
   shape, using **real line numbers and real surrounding whitespace** from
   the file fetched in step 2.
4. Add the §3.1 overlay block as the third entry in the
   `nixpkgs.overlays = [ ... ]` list in `modules/gnome.nix`. Immediately
   above it, add a comment block referencing this spec, the upstream
   version the patch was authored against, and the rationale (Wayland
   stale-actor exception swallow only — no signal-hook changes).

---

## 5. Dependencies

None. Pure-Nix overlay + plain `.patch` file. No new flake inputs.

Context7 references consulted:

- `/websites/nixos_manual_nixpkgs` — confirmed
  `pkg.overrideAttrs (old: { … })` and `composeManyExtensions` semantics.
- nixpkgs source inspection — confirmed `buildGnomeExtension.nix` is a
  thin `stdenv.mkDerivation` wrapper that inherits the default
  `patchPhase`; appended `patches` will be applied with default `-p1`.

---

## 6. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Patch silently rots** when Dash-to-Dock upstream refactors `intellihide.js`. | (a) Comment in `modules/gnome.nix` referencing this spec and the upstream version the patch was authored against. (b) `nix flake check` and `nixos-rebuild dry-build` will fail loudly with a hunk-mismatch error if the patch stops applying — preflight will catch this. |
| 2 | **Version skew between research and implementation.** Research above is against upstream v105. `nixos-unstable` may pin a different version (104, or a later 106 if upstream releases). The signal-hook conclusions in §1.4 may not hold against a different version, and the §3.2 illustrative diff will not apply against a different version. | Phase 2 MUST re-verify §1.1 using `nix eval` and re-fetch the matching `intellihide.js` before authoring the patch. |
| 3 | **Wrong root cause.** If the user's actual symptom is unrelated to the per-window overlap loop (e.g. mutter compositor bug, multimonitor edge case, dconf setting, conflicting extension), this patch will not improve anything and adds maintenance burden. | Reproduce the symptom with `MUTTER_DEBUG=1 GNOME_SHELL_DEBUG=all` and inspect `journalctl --user -u gnome-shell` for actual exceptions before patching. |
| 4 | **Try/catch swallows a real bug.** A consistent exception from `get_frame_rect()` would currently be visible in `journalctl`; silencing it with `catch (_e) {}` would make a future regression harder to diagnose. | If the patch is implemented, log the swallowed exception with `console.warn` (or the dash-to-dock-internal logging helper if one exists in the same file) instead of an unconditional `_e` discard. |

---

## 7. Verification plan for Phase 3

If a patch is authored against alternative C, Phase 3 must run:

- `bash scripts/preflight.sh` (already required by the orchestrator's
  Phase 6 governance).
- `nix flake check` — must pass without `patch failed` errors.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — exercises
  the patched extension build for the most-common variant.
- `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` and
  `.#vexos-stateless-amd` — confirms the other DE roles still evaluate.
  `headless-server-*` and pure `server-*` roles do **not** import
  `modules/gnome.nix` and do not need to be dry-built for this change.
- Manual smoke test (post-deploy, out of scope for Phase 3 automation):
  toggle Dash-to-Dock intellihide on, open and close several windows
  rapidly on Wayland, confirm dock visibility updates within 100 ms and
  no exceptions appear in `journalctl --user -u gnome-shell`.

---

## 8. Recommended path forward — user decision required

The orchestrator should return this spec to the user and ask which of the
following to pursue. Do **not** advance to Phase 2 implementation without
an explicit choice, because the originally-requested patch is a no-op as
drafted.

**Alternative A — Drop the patch entirely (recommended).**
All three signal hooks the draft proposed are already wired upstream
(§1.4). The try/catch hardening fixes a hypothetical race we have no
evidence is the user's actual symptom, and v105 already includes upstream
fixes for the same general area. Wait for `nixpkgs` to bump
`gnomeExtensions.dash-to-dock` to v105 (or later) and re-test the
intellihide symptom on the unmodified package. No code changes; close this
spec as "investigated, no action needed".

**Alternative B — Investigate the actual root cause first.**
Reproduce the staleness symptom on the user's machine, capture the actual
exception or signal sequence from `journalctl --user -u gnome-shell` and
`MUTTER_DEBUG=1`, then design a targeted patch (or upstream bug report)
against whatever the real failure mode turns out to be. Re-spawn Phase 1
with the captured evidence.

**Alternative C — Proceed with try/catch hardening only.**
If the user wants defensive hardening anyway (accepting the
`<implementationDiscipline>` tradeoff), implement *only* the §3.2 patch
shape — try/catch around `get_frame_rect()` returning `false` on
exception, with a `console.warn` of the swallowed exception (per §6 risk
4). **Do not** add any signal hooks. **Do not** add the buggy
`_queueUpdate()` fallback. Phase 2 must follow the version-pinning steps
in §4.

**Alternative D — Pin Dash-to-Dock source to upstream v105 directly.**
Override `gnomeExtensions.dash-to-dock`'s `src` to fetch the v105 zip
directly, bypassing whatever older version `nixos-unstable` currently
pins. Lowest-risk way to get the upstream signal-disconnection fixes
without authoring a downstream patch. Requires recording the v105 sha256
in `modules/gnome.nix`. Out of scope for the original "intellihide patch"
request, but listed here because §1.1's "must verify version" warning may
turn out to indicate the user is running a pre-v105 build that already
fixes the symptom.
