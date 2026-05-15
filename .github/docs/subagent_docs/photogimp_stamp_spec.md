# PhotoGIMP Stamp-Guarded Activation Spec

## Summary of Findings

Two separate Home Manager activation scripts handle PhotoGIMP orphan cleanup:

| File | Activation name | Lines | What it removes | When it runs |
|---|---|---|---|---|
| `home/photogimp.nix` | `cleanupPhotogimpOrphanFiles` | 45–69 | Real (non-symlink) files only | Every rebuild, when `photogimp.enable = true` |
| `home-stateless.nix` | `cleanupPhotogimpOrphans` | 76–111 | Both files AND symlinks; also runs `update-desktop-database` + `gtk-update-icon-cache` | Every rebuild on stateless role |

These are **not identical**. The desktop cleanup guards against pre-HM manual installs (only real files can conflict with `checkLinkTargets`). The stateless cleanup guards against migration from a desktop-role HM generation, which would have left symlinks in `$HOME` — it removes both and then refreshes caches.

### Import graph (confirmed)

- `home-desktop.nix` imports `./home/photogimp.nix` and sets `photogimp.enable = true`.
- `home-stateless.nix` does **not** import `./home/photogimp.nix`.
- The `cleanupPhotogimpOrphanFiles` activation in `home/photogimp.nix` is gated by `lib.mkIf config.photogimp.enable` and therefore never fires on stateless.

### Stateless ephemerality (critical context)

`modules/impermanence.nix` declares `/` as a fresh tmpfs on every boot.  
**User home directories are fully ephemeral** — no home data persists across reboots unless explicitly listed under `environment.persistence."${cfg.persistentPath}".users.nimda`.  
No such entries exist in the current base `impermanence.nix`.

Consequence for the stamp guard:

- A stamp at `$HOME/.local/share/vexos/` on stateless is **wiped every reboot** — it provides no persistence benefit.
- Since `$HOME` itself is ephemeral, any PhotoGIMP orphan files written during a desktop-role session are also gone on first stateless boot. The cleanup is effectively always a no-op from the first boot onwards, not "after several boots".
- For the stamp to survive reboots on stateless the path must be under `/persistent/`.

---

## Current Code

### `home/photogimp.nix` — lines 45–69

```nix
    home.activation.cleanupPhotogimpOrphanFiles =
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
        if [ -f "$DESKTOP_FILE" ] && [ ! -L "$DESKTOP_FILE" ]; then
          $VERBOSE_ECHO "PhotoGIMP: removing orphaned desktop file"
          $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
        fi

        for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
          ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
          if [ -f "$ICON_FILE" ] && [ ! -L "$ICON_FILE" ]; then
            $VERBOSE_ECHO "PhotoGIMP: removing orphaned icon $size/apps/photogimp.png"
            $DRY_RUN_CMD rm -f "$ICON_FILE"
          fi
        done

        for stray in \
          "$HOME/.local/share/icons/hicolor/photogimp.png" \
          "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
          if [ -f "$stray" ] && [ ! -L "$stray" ]; then
            $VERBOSE_ECHO "PhotoGIMP: removing stray file $stray"
            $DRY_RUN_CMD rm -f "$stray"
          fi
        done
      '';
```

### `home-stateless.nix` — lines 76–111

```nix
  home.activation.cleanupPhotogimpOrphans =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
      if [ -e "$DESKTOP_FILE" ] || [ -L "$DESKTOP_FILE" ]; then
        $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP desktop entry"
        $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
      fi

      for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
        ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
        if [ -e "$ICON_FILE" ] || [ -L "$ICON_FILE" ]; then
          $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP icon $size"
          $DRY_RUN_CMD rm -f "$ICON_FILE"
        fi
      done

      for stray in \
        "$HOME/.local/share/icons/hicolor/photogimp.png" \
        "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
        if [ -e "$stray" ] || [ -L "$stray" ]; then
          $VERBOSE_ECHO "Stateless: removing stray PhotoGIMP file $stray"
          $DRY_RUN_CMD rm -f "$stray"
        fi
      done

      APP_DIR="$HOME/.local/share/applications"
      ICON_DIR="$HOME/.local/share/icons/hicolor"
      if [ -d "$APP_DIR" ]; then
        $VERBOSE_ECHO "Stateless: refreshing desktop database after PhotoGIMP cleanup"
        $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database "$APP_DIR"
      fi
      if [ -d "$ICON_DIR" ]; then
        $VERBOSE_ECHO "Stateless: refreshing icon cache after PhotoGIMP cleanup"
        $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$ICON_DIR"
      fi
    '';
```

---

## Stamp Path Decision

The two activations handle different scenarios with different logic; they use **separate stamp paths**.

| File | Stamp path | Rationale |
|---|---|---|
| `home/photogimp.nix` | `$HOME/.local/share/vexos/.photogimp-orphan-cleanup-done` | Desktop `$HOME` is persistent; stamp survives rebuilds. |
| `home-stateless.nix` | `/persistent/home/nimda/.local/share/vexos/.stateless-photogimp-cleanup-done` | `$HOME` is ephemeral (wiped each reboot); stamp must live on the persistent subvolume. |

The stateless stamp is placed at an absolute path (not `$HOME`) because `$HOME` is a tmpfs that starts empty each boot. The `/persistent` mount is always available at activation time (`neededForBoot = true` per `modules/impermanence.nix`).

---

## Replacement Code

### `home/photogimp.nix` — replace lines 45–69

Replace the entire `home.activation.cleanupPhotogimpOrphanFiles` block with:

```nix
    home.activation.cleanupPhotogimpOrphanFiles =
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        STAMP="$HOME/.local/share/vexos/.photogimp-orphan-cleanup-done"
        if [ -f "$STAMP" ]; then
          $VERBOSE_ECHO "PhotoGIMP: orphan cleanup already done, skipping"
        else
          DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
          if [ -f "$DESKTOP_FILE" ] && [ ! -L "$DESKTOP_FILE" ]; then
            $VERBOSE_ECHO "PhotoGIMP: removing orphaned desktop file"
            $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
          fi

          for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
            ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
            if [ -f "$ICON_FILE" ] && [ ! -L "$ICON_FILE" ]; then
              $VERBOSE_ECHO "PhotoGIMP: removing orphaned icon $size/apps/photogimp.png"
              $DRY_RUN_CMD rm -f "$ICON_FILE"
            fi
          done

          for stray in \
            "$HOME/.local/share/icons/hicolor/photogimp.png" \
            "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
            if [ -f "$stray" ] && [ ! -L "$stray" ]; then
              $VERBOSE_ECHO "PhotoGIMP: removing stray file $stray"
              $DRY_RUN_CMD rm -f "$stray"
            fi
          done

          $DRY_RUN_CMD mkdir -p "$HOME/.local/share/vexos"
          $DRY_RUN_CMD touch "$STAMP"
        fi
      '';
```

**Change delta:** Wrap entire shell body in a `[ -f "$STAMP" ]` guard; create stamp directory and stamp file after cleanup.

---

### `home-stateless.nix` — replace lines 76–111

Replace the entire `home.activation.cleanupPhotogimpOrphans` block with:

```nix
  home.activation.cleanupPhotogimpOrphans =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      STAMP="/persistent/home/nimda/.local/share/vexos/.stateless-photogimp-cleanup-done"
      if [ -f "$STAMP" ]; then
        $VERBOSE_ECHO "Stateless: PhotoGIMP orphan cleanup already done, skipping"
      else
        DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
        if [ -e "$DESKTOP_FILE" ] || [ -L "$DESKTOP_FILE" ]; then
          $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP desktop entry"
          $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
        fi

        for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
          ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
          if [ -e "$ICON_FILE" ] || [ -L "$ICON_FILE" ]; then
            $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP icon $size"
            $DRY_RUN_CMD rm -f "$ICON_FILE"
          fi
        done

        for stray in \
          "$HOME/.local/share/icons/hicolor/photogimp.png" \
          "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
          if [ -e "$stray" ] || [ -L "$stray" ]; then
            $VERBOSE_ECHO "Stateless: removing stray PhotoGIMP file $stray"
            $DRY_RUN_CMD rm -f "$stray"
          fi
        done

        APP_DIR="$HOME/.local/share/applications"
        ICON_DIR="$HOME/.local/share/icons/hicolor"
        if [ -d "$APP_DIR" ]; then
          $VERBOSE_ECHO "Stateless: refreshing desktop database after PhotoGIMP cleanup"
          $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database "$APP_DIR"
        fi
        if [ -d "$ICON_DIR" ]; then
          $VERBOSE_ECHO "Stateless: refreshing icon cache after PhotoGIMP cleanup"
          $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$ICON_DIR"
        fi

        $DRY_RUN_CMD mkdir -p "/persistent/home/nimda/.local/share/vexos"
        $DRY_RUN_CMD touch "$STAMP"
      fi
    '';
```

**Change delta:** Hardcoded absolute stamp path under `/persistent`; wrap entire shell body in `[ -f "$STAMP" ]` guard; create stamp at end.

---

## No New Files Required

Both changes are in-place edits to existing files:

- `home/photogimp.nix` (lines 45–69 replaced)
- `home-stateless.nix` (lines 76–111 replaced)

---

## Risk Analysis

### 1. Fresh install — stamp does not exist

**Scenario:** New system. No prior PhotoGIMP install. No orphans.  
**Result:** Cleanup runs, finds nothing, writes stamp. Correct.  
**Risk:** None. A no-op cleanup followed by stamp creation is safe.

### 2. Stamp exists but cleanup never actually ran

**Scenario:** User manually created `$STAMP` before first activation.  
**Result:** Cleanup skipped permanently. If orphans existed, they remain.  
**Mitigation:** Only a self-inflicted issue (no tooling in this repo creates the stamp except the activation itself). On desktop, a blocked cleanup means the next `home-manager switch` would fail at `checkLinkTargets` — detectable and debuggable. The stamp can be deleted manually to re-run.  
**Risk:** Low. Not a regression from current behaviour (which has no guard at all).

### 3. Stateless stamp at `/persistent` — `/persistent` not mounted

**Scenario:** Activation runs before `/persistent` is bind-mounted.  
**Result:** `mkdir -p /persistent/home/nimda/...` fails; activation errors.  
**Mitigation:** `modules/impermanence.nix` asserts that `/persistent` must have `neededForBoot = true`, meaning the mount is available before stage-2 activation scripts. This path is safe on a correctly configured stateless host.  
**Risk:** Low. Any misconfigured host would already fail the module's own assertion before reaching HM activation.

### 4. Stateless — stamp wiped on tmpfs root (addressed by `/persistent` path)

**Scenario:** Stamp written to ephemeral `$HOME` would disappear each reboot.  
**Resolution:** Stamp is written to `/persistent/home/nimda/...`, not `$HOME`. The persistent subvolume is not wiped on reboot. This is explicit in the design above.  
**Risk:** None, given the chosen stamp path.

### 5. DRY_RUN_CMD interaction with `touch "$STAMP"`

**Scenario:** `$DRY_RUN_CMD touch "$STAMP"` is used. In dry-run mode this is a no-op, so the stamp is never created during dry-runs.  
**Result:** Correct. Dry-run activations should not mutate state. On the next real activation the cleanup runs and the stamp is written.  
**Risk:** None.

---

## Activation Hook

Both activations use `lib.hm.dag.entryBefore [ "checkLinkTargets" ]`, which is correct:

- The cleanup must run before HM tries to create symlinks for PhotoGIMP assets.
- The stamp check is a cheap `[ -f ]` test that adds negligible overhead to the activation chain.
- No change to the hook type is required.
