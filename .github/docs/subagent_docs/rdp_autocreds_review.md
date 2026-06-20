# RDP Auto-Credentials — Review

## Specification Compliance

- ✅ `modules/remote-desktop.nix` created with `vexos.remoteDesktop.passwordFile` option
- ✅ Systemd user service `vexos-rdp-setup` created unconditionally (self-guards on file existence)
- ✅ Import added to `configuration-desktop.nix`, `configuration-server.nix`, `configuration-htpc.nix`
- ✅ `configuration-stateless.nix` NOT modified
- ✅ `just setup-rdp` recipe added to `justfile`
- ✅ Username derived from `config.vexos.user.name` automatically

## Best Practices

- ✅ No `lib.mkIf` role/display guards — module is unconditional; role membership via import list
- ✅ Service is idempotent — grdctl commands are safe to re-run on every session start
- ✅ `lib.escapeShellArg` used for all variable interpolations in the service script
- ✅ `printf '%s'` (no newline) used in `setup-rdp` recipe to avoid trailing-newline in password file
- ✅ `IFS= read -rsp` used for silent password input with no word-splitting

## Consistency

- ✅ Option naming follows `vexos.<subsystem>.<option>` pattern
- ✅ Service uses `oneshot` + `RemainAfterExit = true` — consistent with other one-shot services in the codebase (flatpak-add-flathub, flatpak-install-apps)
- ✅ `setup-rdp` recipe style matches existing interactive justfile recipes (password confirmation loop, colored output avoided for consistency)
- ✅ Secret path `/etc/nixos/secrets/rdp-password` follows the existing `/etc/nixos/secrets/` convention from `modules/secrets.nix`

## Correctness

- ✅ Stateless role confirmed to have NO `vexos-rdp-setup` service (verified by `nix eval`)
- ✅ Desktop role confirmed to have `vexos-rdp-setup` with `Type = oneshot` (verified by `nix eval`)
- ✅ Service gracefully exits 0 when password file is absent — no broken unit on machines not yet set up

## Security

- ✅ Password never enters Nix store (not a Nix option value, not in any `.nix` file)
- ✅ `/etc/nixos/secrets/rdp-password` written as root:root 0600 by `setup-rdp`
- ✅ `setup-rdp` recipe creates `/etc/nixos/secrets/` as 0700 root:root
- ✅ Credentials stored by grdctl in GNOME Keyring (libsecret) — not plaintext on D-Bus
- ✅ `just setup-rdp` uses `sudo tee` to write the file without exposing the password in the process list (printf piped to tee, not passed as a CLI argument to a privileged command)

## Build Validation

| Target | Result |
|--------|--------|
| `vexos-desktop-amd` | ✅ `/nix/store/n9yvh7csqm1zggvyb62pi9j0hqy0mwjc-nixos-system-vexos-26.05.drv` |
| `vexos-desktop-nvidia` | ✅ `/nix/store/fnay8yhy9b8mk4jsixkadnd7fhxngmyi-nixos-system-vexos-26.05.drv` |
| `vexos-desktop-vm` | ✅ `/nix/store/86gssbablz0sppcfa8q0fivswxrbbf8x-nixos-system-vexos-26.05.drv` |
| `vexos-server-amd` | ✅ `/nix/store/md1apkf96aq49p4l3a8rcq525gi6pkj6-nixos-system-vexos-26.05.drv` |
| `vexos-htpc-amd` | ✅ `/nix/store/7wc151zx87xx0b329jnqbcnibp1w711n-nixos-system-vexos-26.05.drv` |
| `vexos-stateless-amd` | ✅ `/nix/store/j3p3947i2gmzy63hp066sl9apx4z66xm-nixos-system-vexos-26.05.drv` (module absent — correct) |
| `vexos-headless-server-amd` | ✅ `/nix/store/aifas0y7hdlh31ddczknkwbmjwc7vg2l-nixos-system-vexos-26.05.drv` (unaffected) |
| `hardware-configuration.nix` tracked | ✅ Not tracked |
| `stateVersion` unchanged | ✅ All configs remain at `"25.11"` |

Note: evaluations used `path:.#` scheme to include the untracked `modules/remote-desktop.nix`
file. Once the file is staged (`git add`), standard `.#` evaluation will work identically.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Verdict: PASS
