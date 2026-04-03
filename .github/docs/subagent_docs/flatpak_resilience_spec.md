# Specification: Resilient Flatpak App Installation Service

**Feature:** flatpak_resilience  
**Date:** 2026-04-03  
**Status:** DRAFT  

---

## 1. Current State Analysis

### 1.1 Module Location

All Flatpak configuration lives in `modules/flatpak.nix`.

### 1.2 Current Service Structure

The module defines two systemd services:

| Service | Purpose | Stamp file |
|---|---|---|
| `flatpak-add-flathub.service` | Adds the Flathub remote once | `/var/lib/flatpak/.flathub-added` |
| `flatpak-install-apps.service` | Installs 17 apps from Flathub once | `/var/lib/flatpak/.apps-installed` |

Both services are `Type=oneshot` with `RemainAfterExit=true`.

### 1.3 Current `flatpak-install-apps` Script Logic

```
if stamp exists → exit 0 (no-op, all previously succeeded)
else:
  flatpak install --noninteractive --assumeyes flathub ALL_17_APPS_IN_ONE_CALL
  touch stamp
```

### 1.4 Apps Managed

```
com.bitwarden.desktop
io.github.pol_rivero.github-desktop-plus
com.github.tchx84.Flatseal
it.mijorus.gearlever
org.gimp.GIMP
io.missioncenter.MissionCenter
org.onlyoffice.desktopeditors
org.prismlauncher.PrismLauncher
com.simplenote.Simplenote
io.github.flattool.Warehouse
app.zen_browser.zen
com.mattjakeman.ExtensionManager
com.rustdesk.RustDesk
io.github.kolunmi.Bazaar
org.pulseaudio.pavucontrol
com.vysp3r.ProtonPlus
net.lutris.Lutris
```

### 1.5 Current `serviceConfig`

```nix
serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
```

No restart policy, no timeout configuration, no rate-limiting.

---

## 2. Problem Definition

### 2.1 Failure Mode

```
× flatpak-install-apps.service - Install Flatpak applications from Flathub (once)
   Active: failed (Result: exit-code)
   Process: ExecStart=... flatpak-install-apps-start (code=exited, status=1/FAILURE)

libostree HTTP error from remote flathub: Timeout was reached
Error: Failed to install net.lutris.Lutris: While pulling
app/net.lutris.Lutris/x86_64/stable from remote flathub: Timeout was reached
```

**Sequence of events:**
1. Service starts and stamp file does not exist.
2. `flatpak install` invokes a single batch containing all 17 apps.
3. 16 of 17 apps install successfully, writing 8.8 GB to disk.
4. `net.lutris.Lutris` (last in the list, largest app) times out mid-download.
5. `flatpak install` exits with status 1.
6. `touch /var/lib/flatpak/.apps-installed` is never reached.
7. The service enters `failed` state.

### 2.2 Root Causes

| # | Cause | Effect |
|---|---|---|
| **R1** | All apps installed in a single `flatpak install` call | One failure aborts all remaining or terminates the succeeded partial state without writing stamp |
| **R2** | No `Restart=` policy on the service | On the next boot the entire download is re-attempted (16 already-installed apps + the 1 that failed), wasting ~8.8 GB of bandwidth |
| **R3** | No per-app idempotency check | Even though flatpak technically prints a warning for already-installed apps (and may exit 0), the code structure does not explicitly skip them, making the retry cycle unnecessarily large |
| **R4** | No timeout override in systemd service | Default systemd oneshot timeout is infinity, so systemd will not kill the service during a very long stall; the libostree HTTP timeout (which does fire) is the only guard |

### 2.3 Non-Issues

- The HTTP timeout itself is not a NixOS-specific problem and cannot be overridden via a flatpak CLI flag. Flatpak defers HTTP timeout handling to libostree/curl/libsoup. There is no published `--http-timeout` flatpak flag.
- `net.lutris.Lutris` is simply a large app (~1.4 GB download) that is more likely to hit transient network timeouts than smaller apps.

---

## 3. Research Findings

### 3.1 Source 1 — Flatpak `install` Command Reference (docs.flatpak.org)

> "Normally install just ignores things that are already installed (printing a warning), but if `--or-update` is specified it silently turns it into an update operation instead."

**Key conclusions:**
- `flatpak install` **without** `--or-update` prints a warning but does **not** reliably produce exit code 0 in all scenarios when the app is already installed. Behavior has varied across versions.
- `flatpak install --or-update` silently converts install to update when app is present. This is idempotent but contacts the remote to check for updates, which could itself time out.
- The safest idempotency check is to query the local database: `flatpak list --app --columns=application`, which is a local lookup with no network call.

**Reference:** https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-install

### 3.2 Source 2 — systemd.service(5) man page (man7.org)

Key directives for resilient oneshot services:

| Directive | Behaviour |
|---|---|
| `Restart=on-failure` | Restart the service when the main process exits with a non-zero exit code, is killed by a signal, or times out |
| `RestartSec=N` | Wait N seconds before restarting. Default 100ms |
| `TimeoutStartSec=` | For `Type=oneshot`, this defaults to **infinity** (disabled) so systemd will not kill a long-running install |
| `Type=oneshot` note | `Restart=always` and `Restart=on-success` are **not allowed** for `Type=oneshot`. Only `on-failure`, `on-abnormal`, `on-abort`, `on-watchdog` are valid. |

**Reference:** https://man7.org/linux/man-pages/man5/systemd.service.5.html

### 3.3 Source 3 — systemd.unit(5) man page (man7.org)

Rate-limiting for service restarts:

> "`StartLimitIntervalSec=interval`, `StartLimitBurst=burst`: Configure unit start rate limiting. Units which are started more than burst times within an interval time span are not permitted to start any more."

- `StartLimitIntervalSec=0` disables rate limiting entirely.
- Default values come from `DefaultStartLimitIntervalSec` / `DefaultStartLimitBurst` in the system manager config (typically `10s` / `5`).
- For a service that may legitimately need many retries to pull several large apps, the default 5-in-10s limit will likely not be hit (downloads take minutes), but it is good practice to increase the interval.

**Reference:** https://man7.org/linux/man-pages/man5/systemd.unit.5.html

### 3.4 Source 4 — NixOS Wiki: Flatpak (wiki.nixos.org)

The NixOS Wiki's recommended imperative pattern for configuring remotes:

```nix
systemd.services.flatpak-repo = {
  wantedBy = [ "multi-user.target" ];
  path = [ pkgs.flatpak ];
  script = ''
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  '';
};
```

The wiki does not prescribe a pattern for app installation or restart policies, but the existing implementation in this project already follows the general structure correctly. The stamp-file approach is sound; the per-app loop and restart policy are the missing pieces.

**Reference:** https://wiki.nixos.org/wiki/Flatpak

### 3.5 Source 5 — Flatpak `list` command reference

`flatpak list` can be used to check local installation state without network access:

```
flatpak list --app --columns=application
```

This outputs one app ID per line, e.g.:
```
com.bitwarden.desktop
org.gimp.GIMP
...
```

It reads from the local OSTree repository database only — no HTTP calls. This makes it suitable for a fast per-app idempotency check inside the install loop.

**Reference:** https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-list

### 3.6 Source 6 — nixpkgs NixOS Flatpak module & community patterns (GitHub)

Examination of community NixOS flatpak patterns (including `gmodena/nix-flatpak` module design) reveals that:

- Per-app installation loops are the standard pattern in all declarative flatpak modules.
- Idempotency is always checked via `flatpak list` (local DB) rather than relying on `flatpak install` exit codes.
- Services are typically marked `wantedBy = [ "graphical-session.target" ]` or `multi-user.target`.
- The stamp file approach (as used by `flatpak-add-flathub.service` here) is well-established for first-boot services.

---

## 4. Proposed Solution Architecture

### 4.1 Design Decisions

| Decision | Rationale |
|---|---|
| Install each app **individually** in a `for` loop | Isolates failures; one timed-out app cannot prevent others from installing |
| Check `flatpak list` **before each install attempt** | Zero-cost local lookup; skips already-installed apps on every run without network calls |
| Exit with code 1 if **any** app failed to install | Causes the service to enter `failed` state, which triggers `Restart=on-failure` |
| Write stamp only when **all** apps are installed | Preserves the "first boot installs all" semantic; the service keeps retrying until complete |
| Add `Restart=on-failure` + `RestartSec=60` | Transient network failures auto-recover after 60 s without manual intervention |
| Add `StartLimitIntervalSec=600` + `StartLimitBurst=10` | Allows up to 10 retry attempts within 10 min; sufficient for real network issues while preventing infinite spin on persistent failures |
| Keep `RemainAfterExit=true` | Service stays in `active` state after the stamp is written, preventing accidental re-runs |
| **No change** to `flatpak-add-flathub.service` | It is not affected by the timeout problem and does not need modification |

### 4.2 Shell Script Pseudocode

```bash
#!/usr/bin/env bash
# Exit immediately if stamp exists (all apps installed on a previous boot)
if [ -f /var/lib/flatpak/.apps-installed ]; then
  exit 0
fi

FAILED=0

APPS=(
  com.bitwarden.desktop
  io.github.pol_rivero.github-desktop-plus
  com.github.tchx84.Flatseal
  it.mijorus.gearlever
  org.gimp.GIMP
  io.missioncenter.MissionCenter
  org.onlyoffice.desktopeditors
  org.prismlauncher.PrismLauncher
  com.simplenote.Simplenote
  io.github.flattool.Warehouse
  app.zen_browser.zen
  com.mattjakeman.ExtensionManager
  com.rustdesk.RustDesk
  io.github.kolunmi.Bazaar
  org.pulseaudio.pavucontrol
  com.vysp3r.ProtonPlus
  net.lutris.Lutris
)

for app in "${APPS[@]}"; do
  # Check local DB only — no network call
  if flatpak list --app --columns=application | grep -qx "$app"; then
    echo "flatpak: $app already installed, skipping"
    continue
  fi

  echo "flatpak: installing $app"
  if ! flatpak install --noninteractive --assumeyes flathub "$app"; then
    echo "flatpak: WARNING — failed to install $app"
    FAILED=1
  fi
done

if [ "$FAILED" -eq 0 ]; then
  touch /var/lib/flatpak/.apps-installed
  echo "flatpak: all apps installed successfully"
else
  echo "flatpak: one or more apps failed — will retry"
  exit 1   # triggers Restart=on-failure
fi
```

### 4.3 Updated `serviceConfig`

```nix
serviceConfig = {
  Type              = "oneshot";
  RemainAfterExit   = true;
  Restart           = "on-failure";
  RestartSec        = "60";
  StartLimitIntervalSec = "600";
  StartLimitBurst   = 10;
};
```

> **Note on `StartLimitIntervalSec` in NixOS**: In NixOS, the `unitConfig` attribute set is used for `[Unit]` section keys (including `StartLimitIntervalSec` and `StartLimitBurst`), while `serviceConfig` is used for `[Service]` section keys. The implementation must place these in the correct attribute set.

The corrected split:

```nix
unitConfig = {
  StartLimitIntervalSec = 600;
  StartLimitBurst       = 10;
};
serviceConfig = {
  Type            = "oneshot";
  RemainAfterExit = true;
  Restart         = "on-failure";
  RestartSec      = 60;
};
```

---

## 5. Implementation Steps

### 5.1 File to Modify

**`modules/flatpak.nix`** — only file requiring changes.

### 5.2 Change 1 — Replace the `script` block of `flatpak-install-apps`

**Remove:**
```nix
script = ''
  if [ -f /var/lib/flatpak/.apps-installed ]; then exit 0; fi
  flatpak install --noninteractive --assumeyes flathub \
    com.bitwarden.desktop \
    io.github.pol_rivero.github-desktop-plus \
    com.github.tchx84.Flatseal \
    it.mijorus.gearlever \
    org.gimp.GIMP \
    io.missioncenter.MissionCenter \
    org.onlyoffice.desktopeditors \
    org.prismlauncher.PrismLauncher \
    com.simplenote.Simplenote \
    io.github.flattool.Warehouse \
    app.zen_browser.zen \
    com.mattjakeman.ExtensionManager \
    com.rustdesk.RustDesk \
    io.github.kolunmi.Bazaar \
    org.pulseaudio.pavucontrol \
    com.vysp3r.ProtonPlus \
    net.lutris.Lutris
  touch /var/lib/flatpak/.apps-installed
'';
```

**Replace with:**
```nix
script = ''
  if [ -f /var/lib/flatpak/.apps-installed ]; then exit 0; fi

  FAILED=0

  for app in \
    com.bitwarden.desktop \
    io.github.pol_rivero.github-desktop-plus \
    com.github.tchx84.Flatseal \
    it.mijorus.gearlever \
    org.gimp.GIMP \
    io.missioncenter.MissionCenter \
    org.onlyoffice.desktopeditors \
    org.prismlauncher.PrismLauncher \
    com.simplenote.Simplenote \
    io.github.flattool.Warehouse \
    app.zen_browser.zen \
    com.mattjakeman.ExtensionManager \
    com.rustdesk.RustDesk \
    io.github.kolunmi.Bazaar \
    org.pulseaudio.pavucontrol \
    com.vysp3r.ProtonPlus \
    net.lutris.Lutris
  do
    if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
      echo "flatpak: $app already installed, skipping"
      continue
    fi
    echo "flatpak: installing $app"
    if ! flatpak install --noninteractive --assumeyes flathub "$app"; then
      echo "flatpak: WARNING — failed to install $app"
      FAILED=1
    fi
  done

  if [ "$FAILED" -eq 0 ]; then
    touch /var/lib/flatpak/.apps-installed
    echo "flatpak: all apps installed successfully"
  else
    echo "flatpak: one or more apps failed — will retry on next start"
    exit 1
  fi
'';
```

### 5.3 Change 2 — Replace `serviceConfig` and add `unitConfig`

**Remove:**
```nix
serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
```

**Replace with:**
```nix
unitConfig = {
  StartLimitIntervalSec = 600;
  StartLimitBurst       = 10;
};
serviceConfig = {
  Type            = "oneshot";
  RemainAfterExit = true;
  Restart         = "on-failure";
  RestartSec      = 60;
};
```

### 5.4 No Other Files Require Changes

- `flake.nix` — unchanged
- `configuration.nix` — unchanged
- `hosts/*.nix` — unchanged
- `modules/gpu/*.nix` — unchanged
- `scripts/preflight.sh` — unchanged
- No new dependencies or flake inputs required

---

## 6. Complete Updated Service Block

After both changes, the full `flatpak-install-apps` service definition in `modules/flatpak.nix` should read:

```nix
systemd.services.flatpak-install-apps = {
  description = "Install Flatpak applications from Flathub (once)";
  wantedBy    = [ "multi-user.target" ];
  after       = [ "flatpak-add-flathub.service" ];
  requires    = [ "flatpak-add-flathub.service" ];
  path        = [ pkgs.flatpak ];
  script = ''
    if [ -f /var/lib/flatpak/.apps-installed ]; then exit 0; fi

    FAILED=0

    for app in \
      com.bitwarden.desktop \
      io.github.pol_rivero.github-desktop-plus \
      com.github.tchx84.Flatseal \
      it.mijorus.gearlever \
      org.gimp.GIMP \
      io.missioncenter.MissionCenter \
      org.onlyoffice.desktopeditors \
      org.prismlauncher.PrismLauncher \
      com.simplenote.Simplenote \
      io.github.flattool.Warehouse \
      app.zen_browser.zen \
      com.mattjakeman.ExtensionManager \
      com.rustdesk.RustDesk \
      io.github.kolunmi.Bazaar \
      org.pulseaudio.pavucontrol \
      com.vysp3r.ProtonPlus \
      net.lutris.Lutris
    do
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
        echo "flatpak: $app already installed, skipping"
        continue
      fi
      echo "flatpak: installing $app"
      if ! flatpak install --noninteractive --assumeyes flathub "$app"; then
        echo "flatpak: WARNING — failed to install $app"
        FAILED=1
      fi
    done

    if [ "$FAILED" -eq 0 ]; then
      touch /var/lib/flatpak/.apps-installed
      echo "flatpak: all apps installed successfully"
    else
      echo "flatpak: one or more apps failed — will retry on next start"
      exit 1
    fi
  '';
  unitConfig = {
    StartLimitIntervalSec = 600;
    StartLimitBurst       = 10;
  };
  serviceConfig = {
    Type            = "oneshot";
    RemainAfterExit = true;
    Restart         = "on-failure";
    RestartSec      = 60;
  };
};
```

---

## 7. Dependencies

No new Nix inputs, packages, or external dependencies are introduced.

The existing `path = [ pkgs.flatpak ]` attribute already ensures the `flatpak` binary and `grep` (part of the base system) are available in the service's PATH.

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `flatpak list` grep regex false-positive (e.g. `org.app` matching `org.app.Extra`) | Low | `grep -qx` uses exact full-line match (`-x`). An app ID must match the entire line. |
| `Restart=on-failure` causing the service to spam retries if Flathub is permanently unreachable | Low | `StartLimitBurst=10` within `StartLimitIntervalSec=600` caps retries; after 10 failures in 10 min the service enters `failed` state and must be manually reset. |
| `RestartSec=60` delaying a successful install by 60 s on the first retry | Acceptable | The 60 s delay only applies to retries, not initial start. The initial run proceeds immediately.  The delay is intentional to allow transient network issues to resolve. |
| Service auto-restarts while a user is actively working, causing GNOME background flatpak pulls | Very low | `RemainAfterExit=true` means once the stamp exists, the service never restarts again. Retries only happen before the stamp is written (first boot, partial success). |
| `unitConfig` vs `serviceConfig` confusion in NixOS module system | Medium | `StartLimitIntervalSec` and `StartLimitBurst` are `[Unit]` section keys (not `[Service]`). The implementation must use `unitConfig` for them, not `serviceConfig`. The spec explicitly calls this out. |
| Existing failed stamp file not present causes full re-download on upgrade | N/A | The stamp is intentionally per-machne only. Fresh installs always run the full loop, but the per-app check ensures already-installed apps are skipped in seconds. |

---

## 9. Testing Validation Criteria

After implementation, the following conditions must hold:

1. `nix flake check --impure` passes with no evaluation errors.
2. `sudo nixos-rebuild dry-build --flake .#vexos-amd` succeeds.
3. `sudo nixos-rebuild dry-build --flake .#vexos-nvidia` succeeds.
4. `sudo nixos-rebuild dry-build --flake .#vexos-vm` succeeds.
5. Manually inspecting the generated systemd unit confirms:
   - `Restart=on-failure` is present in `[Service]`
   - `StartLimitIntervalSec=600` is present in `[Unit]`
   - The script contains `for app in … do … done` loop structure
   - The script contains `grep -qx "$app"` idempotency check
6. `hardware-configuration.nix` is NOT committed to the repository.
7. `system.stateVersion` is unchanged in `configuration.nix`.

---

## 10. Summary

The `flatpak-install-apps.service` times out because `net.lutris.Lutris` is a large app whose download exceeds the libostree HTTP timeout on a congested or slow connection. When the single-call `flatpak install` fails, no stamp file is written, causing full re-download on the next boot including the 8.8 GB of already-installed apps.

The fix has two parts:
1. **Per-app install loop with local idempotency check** — each app is installed individually; already-installed apps are skipped via a local `flatpak list` query; failures in one app don't block other apps.
2. **`Restart=on-failure` with rate limiting** — if any app fails, the service exits with code 1 and systemd automatically re-runs it after 60 seconds, up to 10 times per 10-minute window.

The stamp file semantics are preserved: it is written only when all apps are installed, and once written the service becomes a no-op permanently.

Only `modules/flatpak.nix` requires changes. No new flake inputs or packages are needed.
