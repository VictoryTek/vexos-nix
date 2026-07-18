# SABnzbd External Access Fix — Review

## Revision Note

Supersedes the first pass, which incorrectly targeted `host_whitelist` /
Caddy. User confirmed access is via a raw Tailscale IP, not a hostname or
Caddy vhost, which ruled that theory out. Root cause corrected against
SABnzbd's own docs (see updated spec) and re-implemented as
`inet_exposure`.

## Specification Compliance

Implementation matches the corrected spec exactly:
`services.sabnzbd.settings.misc.inet_exposure = "api+web (auth needed)"`
in the existing `cfg.sabnzbd.enable` block in `modules/server/arr.nix`,
replacing the removed `host_whitelist` line. User was explicitly asked and
chose "auth required everywhere" over "LAN passwordless."

## Best Practices / Consistency / Module Architecture

- Still a config value inside a subsystem the same module declares and
  gates via `cfg.sabnzbd.enable` — same carve-out as before, no new
  `lib.mkIf` in a shared file.
- `inet_exposure` is a declared, non-freeform option on
  `services.sabnzbd.settings.misc` (`enumFromAttrs` type), confirmed by
  reading the pinned nixpkgs sabnzbd module source. The string key
  `"api+web (auth needed)"` was verified to type-check and resolve to ini
  value `4` via a standalone `lib.evalModules`/`eval-config.nix`
  instantiation of just this module (isolated from the rest of the repo,
  since neither `vexos-desktop-*` nor the server hosts in this flake
  enable `vexos.server.arr.sabnzbd` by default — that's opt-in per the
  user's real `/etc/nixos` host, not this repo's tracked host files).

## Completeness

Addresses the actual mechanism: SABnzbd classifies "internet" access using
RFC 1918 ranges only, so Tailscale's CGNAT range (100.64.0.0/10) reads as
public and gets denied under the default `inet_exposure = none`. Setting
it to require login (rather than trying to whitelist an IP range SABnzbd
has no CIDR-whitelist mechanism for) resolves it for both LAN and
Tailscale access.

## Security

Strictly tightens/clarifies exposure: SABnzbd's web+API UI now requires
login for every request (LAN and Tailscale alike), rather than relying on
SABnzbd's own (incorrect, for this network) internet/LAN classification.
No credentials are hardcoded in Nix — `allowConfigWrite` defaults to
`true` here (all `configuration-*.nix` pin `stateVersion = "25.11"`, older
than the module's `26.05` cutoff for defaulting to read-only), so the user
sets the login through SABnzbd's own web UI, consistent with existing
practice in this repo (no plaintext credential assignments found in server
modules — confirmed by preflight stage 7/8).

## Build Validation

- `nix flake show --impure`: **pass**.
- `sudo nixos-rebuild dry-build`: **could not run** — sandbox blocks
  `sudo` ("no new privileges" flag); not a repo/code issue.
- CI-equivalent fallback, `nix eval --impure
  ".#nixosConfigurations.<config>.config.system.build.toplevel.drvPath"`:
  - `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`:
    **pass**.
  - `vexos-server-amd` / `vexos-headless-server-amd`: still blocked by the
    pre-existing, unrelated placeholder-`hostId` assertion
    (`hosts/server-amd.nix:15`, `hosts/headless-server-amd.nix:15`,
    introduced in commit `b161981`, predates and is untouched by this
    diff) — confirmed not caused by this change.
- Isolated module-level check confirming the actual option resolves
  correctly (see above): **pass**.
- `git ls-files hardware-configuration.nix`: empty — **pass**.
- `system.stateVersion`: unchanged in all `configuration-*.nix` — **pass**.
- No new flake inputs — **pass** (N/A for `follows`).
- `bash scripts/preflight.sh`: **exit 0**, all 8 stages green.

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

## Result: PASS
