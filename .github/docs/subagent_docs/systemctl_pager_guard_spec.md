# Spec: Fix false "unit not found" errors caused by systemctl pager SIGPIPE

Feature name: `systemctl_pager_guard`
Date: 2026-09-05
Status: Phase 1 — Specification

## 1. Current state analysis

`just backup-now` fails on `vexos-vmc` (`vexos-headless-server-intel`) with:

```
error: restic-backups-main.service not found — enable it first with 'just enable backup'.
```

The unit exists and is fully functional. Verified on the host:

```
Loaded: loaded (/etc/systemd/system/restic-backups-main.service; linked; preset: ignored)
```

A manual `sudo systemctl start restic-backups-main.service --wait` returned 0 and completed a
full backup (`restic backup` with 7 service tags, then `unlock`, then `forget --prune`, all
`status=0/SUCCESS`).

## 2. Problem definition

The guard at `justfile:1791` is:

```bash
if ! systemctl list-unit-files restic-backups-main.service &>/dev/null; then
```

Measured on the affected host:

| Command | Exit |
|---|---|
| `systemctl list-unit-files --no-pager restic-backups-main.service` | **0** (lists `linked ignored`) |
| `systemctl list-unit-files restic-backups-main.service &>/dev/null` | **141** |

141 = 128 + 13 = SIGPIPE.

### Root cause

`systemctl` spawns a pager. The pager terminates immediately because the host has no
terminfo entry for `xterm-ghostty` (`'xterm-ghostty': unknown terminal type.`). `systemctl`
then receives SIGPIPE writing into the dead pager and exits 141. Because 141 is non-zero,
every `if ! systemctl ...` guard treats a healthy unit as missing.

The `list-unit-files` *verdict* was always correct. The failure is in how `systemctl`
writes output, not in what it reports.

### Why the terminfo entry is missing on this host

`ghostty` is installed via home-manager on `desktop`, `server`, `stateless` and `htpc`
(`home-desktop.nix:28`, `home-server.nix:15`, `home-stateless.nix:21`, `home-htpc.nix:172`),
and the `ghostty` package ships its own terminfo. `home-headless-server.nix` does not install
ghostty, so the headless-server role has no `xterm-ghostty` entry. Any SSH session from a
Ghostty client into a headless server hits this.

### Blast radius

`justfile` contains **44** `systemctl` invocations; only **2** pass `--no-pager`. Every
invocation whose exit code or stdout is consumed is affected on this host, including:

- `justfile:1791` — `backup-now` (observed failure)
- `justfile:1804`, `justfile:1841` — `backup-plex`, `restore-plex`
- `justfile:1933` — `restore-service` unit discovery
- `justfile:3798` — `kernel-build-now`
- `status <service>` and other `systemctl status` consumers

### Secondary defect

`justfile:1792` tells the user to run `just enable backup`, but `just enable` only edits
`/etc/nixos/server-services.nix` and prints `→ Run 'just rebuild' to apply.` — it never
rebuilds. When the unit genuinely is absent, the correct remedy names the rebuild.
`justfile:1841` already uses the correct wording (`just enable plex && just rebuild`).

## 3. Proposed solution architecture

Two independent, complementary changes.

### Change A — disable the pager for all justfile recipes (root-cause-proof)

Add one exported variable at the top of `justfile`:

```just
export SYSTEMD_PAGER := ""
```

`just` exports this to the environment of every recipe. `systemctl` honours
`SYSTEMD_PAGER`; empty disables paging. This fixes all 44 call sites at once and is correct
behaviour for non-interactive recipes regardless of terminfo state.

Rejected alternative: replacing the guard primitive with
`systemctl show -p LoadState --value` at each site. It does not address the cause (output
handling, not reporting), requires 5 edits, and `show` must be string-compared because it
exits 0 for missing units. Rejected as more code solving less of the problem.

Rejected alternative: appending `--no-pager` to 42 call sites. Same effect as one exported
variable, 42x the diff. Violates "Simplicity First".

### Change B — install the Ghostty terminfo on all roles (fixes the underlying gap)

Add `ghostty.terminfo` to the universal base package set in
`modules/packages-common.nix`, which is imported by all five non-vanilla roles
(`configuration-{desktop,server,htpc,headless-server,stateless}.nix`).

This is the upstream-documented pattern. nixpkgs 26.05
`pkgs/by-name/gh/ghostty/package.nix:122-126`:

> terminfo and shell integration should also be installable on remote machines
> ```nix
> environment.systemPackages = [ pkgs.ghostty.terminfo ];
> ```

`terminfo` is a declared output of the ghostty derivation (`package.nix:41`,
`moveToOutput share/terminfo $terminfo` at line 141), so this installs the terminfo
database only — not the terminal emulator.

Change B alone would fix the observed failure. Change A alone would fix the justfile but
leave `less`, `top`, `htop`, and bare `systemctl status` broken over SSH. Both are required.

## 4. Implementation steps

1. `justfile` — add `export SYSTEMD_PAGER := ""` near the top, above the `default` recipe,
   with a comment explaining the SIGPIPE failure mode.
   Verify: `grep -n 'SYSTEMD_PAGER' justfile` returns the line; `just --list` still works.
2. `justfile:1792` — reword the `backup-now` error to name the rebuild, matching the
   existing wording at `justfile:1841`.
   Verify: message reads `... enable it first with 'just enable backup && just rebuild'.`
3. `modules/packages-common.nix` — add `ghostty.terminfo` to `environment.systemPackages`
   with a comment, matching the file's existing inline-comment style.
   Verify: `nix flake show --impure` succeeds; dry-build evaluates.

## 5. Dependencies

No new flake inputs. `ghostty` is already in nixpkgs 26.05 and already used by four roles.
Context7 not applicable — no external library integration; the only third-party surface is
nixpkgs, verified directly against the pinned tree
(`/nix/store/5nkggxpr2qy7v4z4b7x2056a4wsgrgy3-source`, NixOS 26.05).

## 6. Configuration changes

`modules/packages-common.nix` gains one package on all five non-vanilla roles. Closure
growth is the terminfo output only (a few KB). `configuration-vanilla.nix` does not import
`packages-common.nix` and is deliberately unchanged.

## 7. Module Architecture Pattern compliance

`modules/packages-common.nix` is the universal base file. The addition applies
unconditionally to every role that imports it. No `lib.mkIf` guard is added, no
role-conditional logic introduced. Compliant with Option B.

## 8. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `SYSTEMD_PAGER=""` suppresses paging in recipes where a human wants scrolling (e.g. long `systemctl status`) | Low | Output still prints in full, just unpaged. Recipes are scripts, not interactive sessions; unpaged is the correct default. |
| `just` syntax for `export` unsupported in the installed version | Low | `export name := "value"` is long-standing `just` syntax; verified by running `just --list` and `just --evaluate` after the edit. |
| `ghostty.terminfo` attribute absent or renamed | Low | Verified present in the pinned 26.05 tree at `package.nix:41,141`. Dry-build confirms. |
| Adding a package to a universal base affects all roles | Low | Terminfo data only; no service, no daemon, no PATH entry. |

## 9. Success criteria

- `grep -c 'systemctl' justfile` invocations are all pager-immune via the exported variable.
- On a Ghostty SSH session into a headless server, `systemctl list-unit-files <unit>` with
  output redirected exits 0 for an existing unit.
- `just backup-now` starts the unit instead of reporting it missing.
- `nix flake show --impure` succeeds.
- `scripts/preflight.sh` exits 0.
