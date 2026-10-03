# Stateless VPN + Kill Switch Redesign — Review (Phase 3)

Date: 2026-10-03
Spec: `.github/docs/subagent_docs/stateless_vpn_redesign_spec.md` (revision 2, plus §9 below)
Verdict: **PASS** (with one environment limitation, see Build Validation)

## Files

| Status | Path |
|---|---|
| new | `pkgs/vexos-vpn/default.nix`, `pkgs/vexos-vpn/vexos-vpn.sh`, `pkgs/vexos-vpn/ca.rsa.4096.crt` (PIA public CA, sha256 `32e9b1d1…6c66ab`) |
| new | `modules/vpn.nix`, `modules/vpn-stateless.nix` |
| modified | `pkgs/default.nix`, `configuration-desktop.nix`, `configuration-htpc.nix`, `configuration-stateless.nix`, `modules/network.nix` (removed `forceFixedDns`), `justfile` |
| deleted | `modules/network-killswitch-stateless.nix`, `modules/network-killswitch-service.nix` |

## Findings

**Fixed during review (before this report):**
1. **CRITICAL: OpenVPN `user nobody` breaks reconnects.** A ping-restart re-creates the socket, and `SO_MARK` needs CAP_NET_ADMIN. The resulting unmarked packets would be dropped (kill switch on) or looped into the tunnel (kill switch off). Fix: OpenVPN stays root, with a comment explaining why.
2. **CRITICAL: `curl | head -n1` under `pipefail`.** `head` exits early, curl gets SIGPIPE, and a successful download reports failure. Fix: download to a file, then cut line 1.
3. **RECOMMENDED: `RuntimeDirectoryPreserve=restart`.** Without it, `last_error` vanished during systemd's retry wait.
4. **RECOMMENDED: `status` reported an error state as "disconnected".** Fix: an error state is preserved.
5. **RECOMMENDED: first WireGuard handshake not guaranteed.** Fix: one DNS query to PIA's in-tunnel resolver triggers it.

**Open, accepted (documented):**
- **Ruleset reload empties `@pia_servers`.** On reload (`nixos-rebuild switch` with a changed ruleset), `@pia_servers` is empty for the few milliseconds until `killswitch sync` refills it. Established flows (the live tunnel) pass via `ct state established`, so the impact is nil in practice.
- **Pre-existing connections survive a manual kill-switch enable.** Turning the kill switch on manually (desktop/htpc) leaves clearnet connections that already exist alive (`established,related`). Same as the old design. Stateless is unaffected because the kill switch loads before any network.
- **NetworkManager can't start while the kill switch is off on stateless.** If the user turns the kill switch off on stateless and NM is later restarted, NM refuses to start until the kill switch is back on. This is fail-closed by design; a reboot restores it.
- **Tailscale (when the kill switch is on) only works once the VPN is up,** and it is relayed through PIA (often via DERP, so higher latency). Verified via routing tests.

**Spec deviations (intentional, recorded in spec §9):**
- `killSwitch.enable` is renamed `killSwitch.mode` (clearer for an enum).
- No `vexos.vpn.enable` option: importing `vpn.nix` *is* enabling it, per the Option B pattern.
- `/etc/NetworkManager/system-connections` stays persisted on stateless, because it also holds Wi-Fi profiles. Removing it would regress Wi-Fi.
- No fallback to the v2 token endpoint. The meta `authv3/generateToken` endpoint was verified live (HTTP 403 "authentication failed" with bogus credentials), so the extra code path wasn't justified.
- No committed server-list snapshot. The first connect bootstraps it through a root-only, 60 s self-expiring hole instead.

## Test evidence

| Test | Result |
|---|---|
| `writeShellApplication` build (shellcheck) | pass |
| CLI, unprivileged, against the live PIA server list | `regions`, `status`, `status --json` and the latency ranking work (204/205 regions probed in parallel); root-only commands refuse or delegate to polkit units |
| Live `serverlist_fetch` (no kill switch) | 205 regions, signature stripped |
| PIA endpoints with bogus credentials (no user secrets used) | meta `authv3/generateToken` → 403; `v2/token` → 401; `wg:1337/addKey` → 401. All live; PIA CA pinning by IP works |
| **Kill switch + routing suite**, real generated ruleset loaded in `unshare -rn` netns, real 1,543-IP `@pia_servers` (oracle: a counter chain at priority 100 sees only what survived) | **30/30** |
| Ruleset reload idempotent; Tailscale marked traffic → tunnel when up, → dropped when down; tailnet routes still win | pass |

Kill-switch suite highlights:
- Blocked: web (TCP 443), public DNS, router DNS and DoT, all old "any IP" holes (1198, 41641), unmarked traffic to the PIA server, marked traffic to a non-PIA IP, and Tailscale traffic to the internet.
- Allowed: marked traffic to the PIA server, LAN SMB, mDNS, DHCP broadcast, and everything via `pia0`.
- The bootstrap hole is closed by default and expires by itself.
- With the kill switch **off** and the tunnel up, the DNS guard still blocks router and public DNS outside the tunnel.
- Teardown leaves no rules or tables behind.

## Build validation

| Step | Result |
|---|---|
| `nix flake show --impure` | 30 nixosConfigurations listed |
| dry-build closure: desktop-amd, desktop-nvidia, desktop-vm, stateless-amd, htpc-amd | **OK** (`nix build --dry-run` of `config.system.build.toplevel`) |
| server-amd, headless-server-amd | Fail on the ZFS `networking.hostId` placeholder assertion. **Pre-existing:** identical failure on HEAD `32a118d` (CI injects a stub hostId). Roles not otherwise touched. |
| `git ls-files hardware-configuration.nix` | empty |
| `system.stateVersion` | unchanged |
| new flake inputs | none (`flake.nix`/`flake.lock` unchanged) |

**Limitation:** this agent's sandbox can't run `sudo` ("no new privileges"), so `sudo nixos-rebuild dry-build` was replaced with the equivalent rootless `nix build --dry-run` of the same toplevel. New files are untracked, so evaluation used a `path:` flake ref. Phase 6 preflight must run after the user stages the new files.

## Scores

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 93% | A |
| Best Practices | 92% | A- |
| Functionality | 90% | A- |
| Code Quality | 90% | A- |
| Security | 95% | A |
| Performance | 95% | A |
| Consistency | 94% | A |
| Build Success | 95% | A |

**Overall Grade: A- (93%)**

Functionality is capped below an A because the end-to-end connect (token → addKey → handshake, and the OpenVPN backup) can only be proven on the user's machine with their credentials. See the acceptance steps in spec §6.6.

## Addendum: revision 4 review (2026-10-03)

| Check | Result |
|---|---|
| `writeShellApplication` build (shellcheck) with `login --stdin` / `logout` / new status fields | pass |
| `login --stdin` with a password containing spaces, `"` and `\` | round-trips byte-exact; file mode 0400 |
| Empty password | rejected (exit 1) |
| sops-style `credentialsFile` | `login` and `logout` refuse; `credentials_editable: false` |
| `status --json` `logged_in` before / after login / after logout | false / true / false |
| `/etc/vexos-vpn/config` on stateless / desktop / htpc | `AUTOCONNECT=true/false/false`, modes `always/manual/manual` |
| `pkexec` path used by the GUI prompt | `/run/wrappers/bin/pkexec` exists (setuid wrapper) |
| One-off gitleaks full-history scan | 1,280 commits, no leaks |

Verdict: **PASS**.
