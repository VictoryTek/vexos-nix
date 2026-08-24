# Align Hyprland session startup with Omarchy's model — Review

## Modified files
- `modules/hyprland-desktop.nix`
- `modules/desktop-common.nix`
- `modules/gnome.nix`
- `modules/cosmic-desktop.nix`

## Root cause — CONFIRMED by evaluation

`programs.hyprland.withUWSM = true` only sets `programs.uwsm.enable = true`. It
does **not** register Hyprland with UWSM. UWSM session entries are generated
solely from `programs.uwsm.waylandCompositors`, as `<name>-uwsm.desktop`;
nixpkgs' own option docs state: *"You must configure `waylandCompositors`
suboptions as well so that UWSM knows which compositors to manage."*

Evaluated against the pre-fix tree:

```
config.programs.uwsm.waylandCompositors  ->  [ ]        # empty
```

So **no `hyprland-uwsm.desktop` session entry existed**. `dms-greeter` was
configured against a UWSM-managed Hyprland session that was never generated —
consistent with the reported black VT with a bare cursor and no input.

After adding the `waylandCompositors.hyprland` block:

```
config.programs.uwsm.waylandCompositors            ->  [ "hyprland" ]
config.services.displayManager.sessionPackages     ->  [ "hyprland-uwsm" "hyprland-0.55.4" ]
```

The session entry now exists.

## Verified option values (Hyprland path)

| Option | Value |
|---|---|
| `services.greetd.settings.initial_session.command` | `/nix/store/…-uwsm-0.26.4/bin/uwsm start -- hyprland-uwsm.desktop` |
| `services.greetd.enable` | `true` |
| `services.displayManager.gdm.enable` | `false` ← alias conflict eliminated |
| `services.displayManager.autoLogin.enable` | `false` ← greetd-incompatible option no longer applied |
| `programs.uwsm.enable` | `true` |

`lib.getExe pkgs.uwsm` resolves correctly (real store path, no `mainProgram`
error) — one of the two risks flagged in the spec is now closed.

## Regression checks — all evaluate to a `.drv`

| Configuration | Result |
|---|---|
| `vexos-desktop-vm` (hyprland) | ✓ `3w2grxi25xdah…` |
| `vexos-desktop-vm` (gnome, default) | ✓ `brjd2d59yjmx…` |
| `vexos-desktop-vm` (cosmic) | ✓ `gc95hcqdmrp4…` |
| `vexos-server-amd` | ✓ `2g60zg0kf3df…` |
| `vexos-htpc-amd` | ✓ `nmsx4xxg213z…` |
| `vexos-stateless-amd` | ✓ `qv6vfiai0xvl…` |
| `vexos-vanilla-vm` | ✓ `k2yw1parfamc…` |

GNOME behaviour preserved: `gdm.enable=true`, `autoLogin.enable=true`,
`autoLogin.user="nimda"`, `greetd.enable=false`,
`sessionPackages = [ "gnome-session-50.1" ]` (no Hyprland leakage).

COSMIC behaviour preserved: `cosmic-greeter.enable=true`,
`autoLogin.enable=true`. Note `greetd.enable=true` there too — cosmic-greeter is
itself a greetd greeter, which is expected and not a conflict (GDM is off).

## Checklist

| Category | Result |
|---|---|
| Specification compliance | Matches spec, plus the `waylandCompositors` fix the spec did not anticipate |
| Best practices | `lib.getExe` over hardcoded paths; `waylandCompositors` is the documented UWSM registration mechanism |
| Consistency (Option B) | No new role/display/gaming `lib.mkIf` in a shared module — `autoLogin` moved *into* modules already DE-gated, per `6ab1ae2` |
| Orphan cleanup | `desktop-common.nix` signature narrowed `{ config, pkgs, ... }` → `{ pkgs, ... }` after `config` became unused |
| Security | Seamless autologin is not a new posture — `autoLogin.enable = true` already applied to every desktop host |
| `hardware-configuration.nix` not tracked | ✓ (preflight 3/8) |
| `system.stateVersion` unchanged | ✓ all six files (preflight 4/8) |
| Flake inputs | None added |

## Build validation — RUN (WSL, nix 2.34.1)

- `nix flake show --impure` — ✓ PASS
- Per-target `nix eval … config.system.build.toplevel.drvPath` — ✓ PASS on all
  seven configurations above (the CI-equivalent single-target check named in
  CLAUDE.md)
- `bash scripts/preflight.sh` — ✓ **PASSED, exit 0**

Preflight skips, all environment-related rather than code-related:
- `[2/8]` dry-build skipped — no `/etc/nixos/vexos-variant` (WSL is not a NixOS host)
- `[5b/5c]` flake.lock pinning/freshness skipped — `jq` not installed
- `[6/8]` formatting skipped — `nixpkgs-fmt` not installed
- `[7e]` gitleaks skipped — not installed
- `[7a]` warning is pre-existing (`modules/server/vexboard.nix:90` placeholder), unrelated to this change

## Remaining unverified

Evaluation proves the session entry is generated and the config is internally
consistent. It cannot prove the session actually *starts* — that requires a real
boot on the target host. Confirm with a rebuild + reboot on the Hyprland VM.

If it still fails, capture before iterating:
```
systemctl status greetd.service --no-pager -l
journalctl -b -u greetd.service --no-pager | tail -100
```

## Corrections to earlier claims in this work

- The header comment asserting the module used "the same stack combination used
  by Omarchy" was inaccurate: Omarchy uses Waybar (not DankMaterialShell) and no
  greeter at all. Corrected.
- `WLR_RENDERER_ALLOW_SOFTWARE = "1"` is retained but is **not** the fix and did
  not resolve the failure. GNOME renders natively on the same Proxmox guest,
  proving KMS/GBM/EGL work there.

## Verdict

**APPROVED.** Root cause confirmed by evaluation, fix verified to produce the
missing session entry, no regressions across seven configurations, preflight
exit 0. Runtime boot confirmation still owed by the user.
