# Spec: Headless‑Server Install Drops to Black Screen + Blinking Cursor

Feature ID: `headless_install_blackscreen`
Author: Phase 1 Research Subagent
Scope: Bug fix to the live‑ISO install flow for the `headless-server` role
Status: Ready for Phase 2 implementation

---

## 1. Current State Analysis

### 1.1 What the user does

The user is running the **NixOS graphical live ISO**. Inside the live GNOME session they open a terminal and run:

```
curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh | bash
```

They pick role `4) Server` → `1) Headless`, then a GPU variant. The script then executes (excerpt from [scripts/install.sh](scripts/install.sh#L294)):

```bash
if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
  ...
  printf "Reboot now? [y/N] "
```

### 1.2 What the headless‑server config actually does (vs server)

[configuration-headless-server.nix](configuration-headless-server.nix#L1-L49) — the entire file:

```nix
{ config, pkgs, lib, ... }:
{
  imports = [
    ./modules/gpu.nix
    ./modules/branding.nix
    ./modules/network.nix
    ./modules/packages-common.nix
    ./modules/system.nix
    ./modules/server
    ./modules/nix.nix
    ./modules/locale.nix
    ./modules/users.nix
  ];

  console.earlySetup = true;
  console.packages   = [ pkgs.terminus_font ];
  console.font       = "ter-v32n";

  services.xserver.enable = lib.mkForce false;          # ← KEY LINE

  vexos.branding.role     = "headless-server";
  system.nixos.distroName = lib.mkOverride 500 "VexOS Headless Server";
  system.stateVersion = "25.11";
}
```

Notable absences (compared to [configuration-server.nix](configuration-server.nix#L1-L42)):

* **No** `./modules/gnome.nix`
* **No** `./modules/gnome-server.nix`
* **No** `./modules/branding-display.nix`
* **No** `./modules/audio.nix`
* **No** `./modules/flatpak.nix`

`configuration-server.nix` imports `gnome.nix` + `gnome-server.nix`, which transitively pull in `services.xserver.enable = true`, GDM, and `display-manager.service`. That is why the **GUI server** install flow works inside live‑ISO GNOME — switch‑to‑configuration keeps `display-manager.service` running across activation.

### 1.3 What the headless GPU modules actually do

* [modules/gpu/amd-headless.nix](modules/gpu/amd-headless.nix#L1-L42) — does **not** add `boot.initrd.kernelModules = [ "amdgpu" ]`. amdgpu still loads at the normal kernel module stage. **No DRM/KMS is blacklisted.**
* [modules/gpu/intel-headless.nix](modules/gpu/intel-headless.nix#L1-L42) — does **not** add `boot.initrd.kernelModules = [ "i915" ]`. Sets `i915.enable_guc=3` only. **No DRM/KMS blacklist.**
* [modules/gpu/nvidia-headless.nix](modules/gpu/nvidia-headless.nix#L1-L17) — imports `./nvidia.nix` and forces `hardware.nvidia.modesetting.enable = false`. **No driver blacklist; the proprietary nvidia kernel module still loads.**

So Hypothesis #5 ("headless GPU module disables all DRM / framebuffer") is **NOT** the cause. The frame buffer console exists; it is simply invisible (see §2).

### 1.4 What `nixos-rebuild switch` does to the running live ISO

`nixos-rebuild switch` runs `switch-to-configuration switch` after building. That script:

1. Loads the new generation’s systemd unit set into `/etc/systemd/system/…`.
2. Diffs against currently running units.
3. **Stops units that exist in the old config but not the new one.**
4. Starts/restarts changed units.

The **live ISO** is the "old" running config. Its `display-manager.service` (GDM) is part of the live ISO’s systemd state. The new headless‑server generation has **no `display-manager.service`** because:

* `services.xserver.enable = lib.mkForce false;`
* No GDM module is imported.

Therefore activation **stops `display-manager.service` mid‑rebuild**, killing the live GNOME session and every process running under it — including `gnome-terminal`, the user’s `bash`, and the `install.sh` controller script. (`sudo nixos-rebuild` itself, being a child of the sudo PAM session attached to the dying terminal, also typically receives SIGHUP via the controlling‑terminal hangup.)

### 1.5 Other suspected causes — verified NOT to be the cause

| Hypothesis | Verdict | Evidence |
|---|---|---|
| `systemd.defaultUnit = "multi-user.target"` set | **Not present** | Not in `configuration-headless-server.nix` or any imported module. |
| `getty@tty1.service` disabled | **Not present** | Not disabled anywhere. |
| `boot.kernelParams` removing `tty0` / `console=ttyS0` only | **Not present** | [modules/system.nix](modules/system.nix#L40-L46) only sets `elevator=kyber`. |
| Plymouth misconfig | **Not the cause** | `boot.plymouth.enable = lib.mkDefault false;` on headless ([modules/system.nix](modules/system.nix#L48-L50)); even if enabled, Plymouth runs in stage‑1, not during runtime activation. |
| `systemd.services."getty@tty1".enable = false` | **Not present** | Verified absent. |
| Kernel module blacklist | **Not present** | None of the headless GPU modules blacklist DRM/KMS drivers. |

---

## 2. Root Cause (Definitive)

There are **two stacked causes**, ranked by primary effect:

### Cause #1 (PRIMARY — kills the install flow)

> **Activating the new headless‑server generation while the live ISO’s GNOME session is still in use stops `display-manager.service` (GDM) as part of `switch-to-configuration switch`. This terminates the GNOME session, the GNOME terminal, and the `install.sh` bash process driving the rebuild — leaving the user staring at TTY1 with no controller process and no visible output.**

Specific triggers in this repo:

* [configuration-headless-server.nix](configuration-headless-server.nix#L37) — `services.xserver.enable = lib.mkForce false;`
* [configuration-headless-server.nix](configuration-headless-server.nix#L5-L15) — no `gnome.nix` import, so no GDM/display‑manager.service in the new generation’s systemd state.

Compare: [configuration-server.nix](configuration-server.nix#L5-L22) imports `gnome.nix` + `gnome-server.nix`, so `display-manager.service` survives activation.

### Cause #2 (SECONDARY — explains "blinking cursor" cosmetics)

> **Once the GUI is gone, TTY1 is a high‑resolution KMS framebuffer console using the live ISO’s tiny default 8×8 kernel font. At 1920×1080 / 4K, glyphs render ~2 px tall — effectively invisible — while the hardware cursor still blinks. The user perceives this as "black screen with blinking cursor".**

This is exactly the symptom the existing comment in [configuration-headless-server.nix](configuration-headless-server.nix#L17-L29) anticipates. The `console.earlySetup` / `ter-v32n` mitigation in that file applies only to the **new generation’s next boot** — it has no effect on the **live ISO’s already‑running console**, which still runs the ISO’s default font.

The rebuild may actually still be running (or have already finished) at this point, but the user has no usable display to confirm or interact with the post‑rebuild reboot prompt.

---

## 3. Reproduction Model (Step‑by‑Step)

1. User boots the NixOS graphical installer ISO; live GNOME starts, GDM autologs into `nixos`.
2. User opens GNOME Terminal and runs the curl one‑liner.
3. `install.sh` collects: role=`headless-server`, gpu=`amd` → `FLAKE_TARGET=vexos-headless-server-amd`.
4. Script invokes `sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-amd`.
5. Build phase runs (no visible problem; kernel/userland derive successfully).
6. Activation phase begins: `switch-to-configuration switch`.
7. systemd compares unit set: live ISO has `display-manager.service`; new generation does **not**.
8. systemd issues `systemctl stop display-manager.service` → GDM exits → X/Wayland session torn down → GNOME Shell killed → `gnome-terminal-server` killed → `bash` (parent of `install.sh`) receives SIGHUP from controlling‑TTY hangup → `install.sh` and its child `sudo nixos-rebuild` are SIGHUPed.
9. Kernel switches active VT to TTY1. KMS framebuffer is at panel native resolution; live ISO’s console font is the default 8×8 → glyphs ~2 px tall, blinking cursor visible at top‑left.
10. The activation may or may not have completed before the controlling process died; bootloader entry may or may not be installed; the user has no way to tell, no way to type "Reboot? [y/N]", and no obvious recovery path.

This sequence does NOT occur for `desktop` / `htpc` / `server` / `stateless` because all of them keep `display-manager.service` (GDM) declared in the new generation, so step 7 sees a match and step 8 never happens.

---

## 4. Proposed Solution

### 4.1 Options considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| (a) Detect headless target in `install.sh` and switch to `nixos-rebuild boot`, then prompt for reboot | Simple, single‑file change. Live GNOME stays alive throughout. The new system is fully built and bootloader entry installed; first real boot happens on user‑initiated reboot — exactly the user’s mental model. Standard NixOS practice for "switching into a system that can’t coexist with the current one". | User must reboot to enter the new system (already the desired flow per the bug report). | **CHOSEN** |
| (b) Add `lib.mkIf`‑gated GDM into headless to keep display alive during activation | Live install would work. | Violates project Module Architecture Pattern (no `lib.mkIf` in shared modules); adds 100s of MB of GNOME closure to a "headless" build; defeats the whole point of the role. | Rejected. |
| (c) Run `nixos-rebuild switch` under `systemd-run --scope --no-block --collect` to survive GUI teardown | Activation completes regardless of GDM death. | Output disappears with the terminal; user still sees blinking cursor; success/failure is invisible; status retrieval requires journal commands the user can’t see. Worse UX than (a). | Rejected. |
| (d) Switch only after first reboot via a one‑shot activation script | Conceptually appealing but NixOS has no clean "first‑boot only" hook tied to flake activation; would require stateful flag files outside the Nix model. | Hard to implement, fragile, role‑specific tech debt. | Rejected. |

### 4.2 Chosen approach

**Modify `scripts/install.sh` to use `nixos-rebuild boot` instead of `nixos-rebuild switch` when the resolved `ROLE` is `headless-server`. Print a clear notice explaining why, and require an explicit reboot at the end (no "stay logged in" option for headless, since there is no GUI to stay in).**

Rationale:

* `nixos-rebuild boot` performs the full build, installs the bootloader entry, and registers the new generation as the default — but does **not** call `switch-to-configuration switch`. No live unit reconfiguration occurs. GDM keeps running. The install script keeps running. The user keeps seeing output.
* On the next reboot the system boots straight into the headless generation. This matches the user’s stated mental model exactly: *"complete the rebuild in GNOME, then reboot into headless"*.
* Zero changes to any `.nix` file required. Zero risk of breaking other roles. Fully reversible.
* This is the documented, idiomatic NixOS pattern for the situation.

### 4.3 Optional follow‑up (NOT in scope of this fix)

Document in `README.md` that for the `headless-server` role the installer uses `nixos-rebuild boot` and requires a reboot to enter the new system. The implementation phase MAY add a one‑line README note but is not required to.

---

## 5. Implementation Steps (for Phase 2)

All changes are in **`scripts/install.sh` only**. No `.nix` files modified.

### 5.1 Add a derived flag near the top of the build section

After `FLAKE_TARGET` is computed (around [scripts/install.sh L186](scripts/install.sh#L186)), add:

```bash
# Headless server cannot be activated live: doing so stops display-manager.service
# during switch-to-configuration, killing the live ISO's GNOME session (and this
# script). Use `nixos-rebuild boot` to install the new generation as default
# without runtime activation; user reboots into the new system.
REBUILD_ACTION="switch"
if [ "$ROLE" = "headless-server" ]; then
  REBUILD_ACTION="boot"
fi
```

### 5.2 Replace the rebuild command and post‑rebuild flow

Around [scripts/install.sh L294-L317](scripts/install.sh#L294) (`if sudo nixos-rebuild switch …` block), change the literal `switch` to `${REBUILD_ACTION}` and split the success path so headless cannot pick "no reboot":

```bash
if sudo nixos-rebuild "${REBUILD_ACTION}" --flake "/etc/nixos#${FLAKE_TARGET}"; then
  echo ""
  if [ "$REBUILD_ACTION" = "boot" ]; then
    echo -e "${GREEN}${BOLD}✓ Build complete. New generation registered as default.${RESET}"
    echo -e "${YELLOW}A reboot is REQUIRED to enter the headless system.${RESET}"
    echo -e "${YELLOW}(Live activation is skipped on headless to avoid killing this session.)${RESET}"
    echo ""
    printf "Reboot now? [Y/n] "
    read -r REBOOT_CHOICE </dev/tty
    case "${REBOOT_CHOICE,,}" in
      n|no)
        echo -e "${YELLOW}Reboot skipped. Run 'systemctl reboot' when ready.${RESET}"
        ;;
      *)
        echo "Rebooting..."
        systemctl reboot
        ;;
    esac
  else
    echo -e "${GREEN}${BOLD}✓ Build and switch successful!${RESET}"
    echo ""
    printf "Reboot now? [y/N] "
    read -r REBOOT_CHOICE </dev/tty
    case "${REBOOT_CHOICE,,}" in
      y|yes)
        echo "Rebooting..."
        systemctl reboot
        ;;
      *)
        echo ""
        echo -e "${YELLOW}Skipping reboot. Log out and back in to apply session changes.${RESET}"
        echo ""
        ;;
    esac
  fi
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild ${REBUILD_ACTION} failed. Reboot skipped.${RESET}"
  echo "  Review the output above for errors and retry:"
  echo "    sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET}"
  echo ""
  exit 1
fi
```

Also update the pre‑rebuild banner around [scripts/install.sh L189](scripts/install.sh#L189) so the user is informed early:

```bash
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD} (action: ${REBUILD_ACTION})...${RESET}"
if [ "$REBUILD_ACTION" = "boot" ]; then
  echo -e "${YELLOW}Headless role: using 'nixos-rebuild boot' so this live GNOME session keeps running until reboot.${RESET}"
fi
echo ""
```

### 5.3 Files Phase 2 must modify

* [scripts/install.sh](scripts/install.sh) — only file changed.

---

## 6. Module Architecture Pattern Compliance

This fix touches **zero** `.nix` files and adds **zero** `lib.mkIf` guards anywhere. The role‑specific behaviour lives entirely in the role‑aware install script (already role‑aware via the `ROLE` variable). Fully compliant with the project’s "Option B: common base + role additions" rule.

---

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| User runs install on an *already‑installed* headless system (re‑rebuild from SSH) and `boot`+reboot is heavier than `switch` would have been. | Low | Low — adds one reboot. | Acceptable. The script targets first‑boot install primarily; SSH operators can always run `sudo nixos-rebuild switch` directly. A future enhancement could detect "already on a vexos generation" and prefer `switch`, but is out of scope. |
| `nixos-rebuild boot` installs bootloader entry but a hardware/initrd issue prevents the new system from booting. | Low | Medium — user reboots into a non‑working system. | Same risk exists for `switch` (next boot would also fail). User can pick the previous generation in the bootloader menu. No regression. |
| Default reboot prompt flipped to `[Y/n]` (default yes) for headless could surprise a user who expected `[y/N]`. | Low | Trivial. | Explicit prompt text and explanation; matches the necessity of rebooting. |
| BIOS/GRUB patching path ([scripts/install.sh L189-L246](scripts/install.sh#L189)) interacts with `boot` action. | Low | None. | `nixos-rebuild boot` installs whichever bootloader the configuration declares; the GRUB patch happens before `nixos-rebuild` runs and is independent of `switch` vs `boot`. |

---

## 8. Validation Plan

Phase 3 (Review) and Phase 6 (Preflight) MUST verify:

1. **Static script validation**
   * `bash -n scripts/install.sh` → no syntax errors.
   * `shellcheck scripts/install.sh` → no new warnings introduced by this change (existing warnings, if any, are not in scope).

2. **Logical inspection of the diff**
   * Confirm `REBUILD_ACTION` defaults to `switch`.
   * Confirm `REBUILD_ACTION=boot` only when `ROLE = "headless-server"`.
   * Confirm both success and failure branches use `${REBUILD_ACTION}` consistently in the user‑visible commands.
   * Confirm no other role’s flow is altered.

3. **Flake build sanity** (no `.nix` changed, but enforced by project rules)
   * `nix flake check`
   * `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
   * `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-nvidia`
   * `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-vm`
   * `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (regression smoke test)

4. **Manual / out‑of‑band verification (informational only — not required to gate merge)**
   * On a live ISO + headless‑server target, confirm the script reaches the post‑rebuild prompt with the GNOME terminal still visible and responsive.

5. **Negative confirmation**
   * Confirm `hardware-configuration.nix` is still NOT tracked.
   * Confirm `system.stateVersion` in `configuration-headless-server.nix` is unchanged ("25.11").

---

## 9. Out of Scope

* Any change to `.nix` files, GPU modules, or the headless console font setup. The existing `console.earlySetup` + `terminus_font` configuration is correct for the **post‑boot** experience and is unrelated to the live‑install flow.
* README documentation updates beyond what implementation may optionally add as a single line.
* Refactoring of `install.sh` beyond the minimal change needed for this fix.
