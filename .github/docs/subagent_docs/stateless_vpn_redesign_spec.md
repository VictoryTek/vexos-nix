# Stateless VPN + Kill Switch Redesign — Specification (Phase 1)

Status: **REVISION 2 — user decisions recorded (§4); awaiting go-ahead for Phase 2**
Date: 2026-10-03

---

## 1. Current state

| Piece | Where | How it works today |
|---|---|---|
| Kill switch | `modules/network-killswitch-stateless.nix` | iptables `vpn-kill-switch` chain jumped from `OUTPUT`, loaded via `networking.firewall.extraCommands`. Always on. Allows lo, ESTABLISHED, DHCP, `tun+`/`wg+`/`nordlynx`/`tailscale0`, DNS only to 1.1.1.1/9.9.9.9, RFC1918/link-local/multicast, then UDP 1194/1197/1198/51820/41641 + TCP 501/502 to **any** IP, then DROP. |
| DNS bootstrap | `modules/network.nix` (`vexos.network.forceFixedDns`) | Forces DNS on the **`wired-fallback` profile only** to 1.1.1.1;9.9.9.9. |
| VPN client | `modules/desktop-common.nix` | `networkmanager-openvpn` plugin; user imports `.ovpn` in GNOME Settings. |
| VPN profile persistence | `configuration-stateless.nix` | `/etc/NetworkManager/system-connections` persisted. Secrets default to *agent-owned*, so they live in the GNOME keyring in `$HOME`, which is tmpfs and wiped on every boot. |
| IPv6 | kill-switch module | `networking.enableIPv6 = false`. |
| Firewall | evaluated `vexos-stateless-amd` | iptables 1.8.13 (not nftables), `checkReversePath = true` (strict). |
| Versions (evaluated) | | OpenVPN 2.6.23, NetworkManager-openvpn 1.12.3, OpenSSL 3.6.4. |

History: the PIA proprietary client was added (`03fdc17`), then removed (`ce850d2`). The kill switch was then patched four times (`c103786`, `2ee1656`, `0a21f82`, `60fdbec`), each fix opening a new failure mode.

## 2. Problem definition: why it is unreliable

The user reports: kill switch on at boot (good), but the VPN either doesn't connect, or connects and then nothing gets out. These are the likely causes, ranked. Each is marked with how well it was verified.

1. **PIA's `.ovpn` files vs. OpenVPN 2.6 / OpenSSL 3.x.**
   - *Malformed CRL (verified upstream, may already be fixed in your files):* PIA's embedded `<crl-verify>` has malformed revocation dates. OpenSSL ≥ 3.3 rejects it ("utctime is too short"), so the connection fails. An OpenSSL maintainer confirmed it is PIA's CRL, not an OpenSSL bug. We ship OpenSSL 3.6.4. PIA's **currently published** `openvpn-strong.zip` (downloaded 2026-10-03) no longer contains `<crl-verify>`, but any older `.ovpn` you imported still does.
   - *`compress` directive (suspected, not tested):* the published files still contain a bare `compress`. On 2026-09-23, PIA's own `manual-connections` repo removed `compress` "due to server changes" (PR #225). A compression-framing mismatch typically shows as **"connected, but no traffic passes"**, which is exactly symptom #2.
   - *`cipher aes-256-cbc` with no `data-ciphers`:* OpenVPN 2.6 ignores `--cipher` during negotiation. This normally still negotiates GCM, but it is a known source of "failed to negotiate cipher" errors when NM-openvpn imports such files.
2. **DNS bootstrap only covers one NM profile.** `forceFixedDns` patches `wired-fallback` only. On Wi-Fi, or any other wired profile, the resolver is the router's, which the DNS guard drops. The `.ovpn` uses a hostname (`us-newjersey.privacy.network`), so it can't be resolved and OpenVPN never connects.
3. **Credentials don't survive a reboot.** The profile persists, but the password sits in a wiped keyring. Each boot re-prompts, and NM may give up silently before you answer.
4. **Too many moving parts own the state.** Kill-switch correctness depends on the NM profile, the GNOME secret agent, systemd-resolved's link-DNS choice, the firewall reload order, and which `.ovpn` the user imported. Nothing in the repo describes the tunnel declaratively.
5. **The kill switch's design is permissive.** VPN ports are open to *any* IP from *any* process, plus all of RFC1918. It is "block most things" rather than "allow only the tunnel." Every bug so far came from reasoning about holes.

Checked and **ruled out**: the port list is not the problem. A raw OpenVPN handshake probe got replies from PIA US East on UDP 1197, 1198 and 8080, so the allowed ports reach live servers.

## 3. Research summary

| # | Source | Takeaway |
|---|---|---|
| 1 | [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections) (PIA-maintained, last commit 2026-09-23) | **PIA supports WireGuard without its app** via a documented API: token (`/api/client/v2/token`, valid 24 h), server list (`serverlist.piaservers.net/vpninfo/servers/v6`), then `addKey` on `https://<wg-ip>:1337` (pinned with `ca.rsa.4096.crt`). The user's belief that "only OpenVPN files are offered" is out of date. |
| 2 | PIA server list v6 (fetched live) | Gives per-region **IPs** for `wg`, `ovpnudp`, `ovpntcp`, `meta`. Port groups: wg 1337; ovpnudp 8080/853/123/53; ovpntcp 80/443/853/8443; meta 443/8080. Connecting by IP removes the DNS bootstrap problem entirely. |
| 3 | [manual-connections PR #211](https://github.com/pia-foss/manual-connections/pull/211) and [PR #225](https://github.com/pia-foss/manual-connections/pull/225) | OpenVPN moved to 8080/udp and 8443/tcp, standard encryption was dropped (strong only), and `compress` was removed due to server changes. |
| 4 | [openssl/openssl discussion #24301](https://github.com/openssl/openssl/discussions/24301), [Manjaro thread](https://forum.manjaro.org/t/openvpn-profiles-no-longer-work-in-networkmanager-after-20240513-update/161401/7), [NixOS Discourse: PIA](https://discourse.nixos.org/t/connecting-to-private-internet-access-vpn-pia/67096) | PIA CRL plus OpenSSL ≥ 3.3 breaks connections. The NixOS user's fix was dropping `crl-verify`. The `Fuwn/pia.nix` flake has an open "cannot initiate a connection" issue. |
| 5 | [WireGuard: Routing & Network Namespaces](https://www.wireguard.com/netns/) | The fwmark/policy-routing model (wg-quick) versus the netns "ultimate kill switch." netns is leak-proof by construction but fights NetworkManager and Wi-Fi on a desktop. |
| 6 | [Mullvad app firewall design](https://mintlify.wiki/mullvad/mullvadvpn-app/security/firewall) | The reference kill switch: allow only (a) the **daemon's own marked packets** to (b) **the one relay IP:port**, plus DHCP, plus tunnel DNS. Apply atomically; fail closed. On Linux it uses nftables and an fwmark that only privileged processes can set. |
| 7 | [NixOS Discourse: WireGuard and firewall weirdness](https://discourse.nixos.org/t/solved-wireguard-and-firewall-weirdness/58126), [wg-quick(8)](https://man7.org/linux/man-pages/man8/wg-quick.8.html) | NixOS strict `checkReversePath` can drop WireGuard replies under fwmark routing. The fix is `"loose"` (or a rpfilter exemption). wg-quick's own kill-switch idiom is `! -o %i -m mark ! --mark <fwmark> -j REJECT`. |
| 8 | [OpenVPN forum: cipher vs data-ciphers](https://forums.openvpn.net/viewtopic.php?p=109301) | OpenVPN 2.6 ignores `--cipher` for negotiation. Configs must set `data-ciphers`. |
| 9 | [PIA KB: ports](https://helpdesk.privateinternetaccess.com/kb/articles/what-ports-are-used-by-your-vpn-service) | Official port list; matches #2. |

Additional research for revision 2:

| # | Source | Takeaway |
|---|---|---|
| 10 | [tadfisher/flake `pia-vpn.nix`](https://github.com/tadfisher/flake/blob/main/nixos/modules/pia-vpn.nix) (the backend vex-vpn originally vendored) | Prior art for PIA WireGuard on NixOS: latency-tests meta IPs, gets a token, runs addKey. But it **requires systemd-networkd** (which conflicts with NetworkManager), has **no kill switch**, and doesn't refresh tokens. Useful as a reference for API calls only. |
| 11 | Repo audit: `modules/stateless-disk.nix`, `modules/impermanence.nix`, `scripts/bare-metal-install.sh` | **No role uses LUKS.** On stateless, `/etc/ssh` is not persisted, so SSH host keys are regenerated every boot. |
| 12 | Repo audit: `modules/secrets-sops.nix`, `flake.nix` `sopsBase` | sops-nix is wired into server/headless-server only and is opt-in (`vexos.secrets.backend`). The encrypted file lives per host under `/etc/nixos` (template), not in this repo. |
| 13 | `~/Projects/vex-vpn` (last commit 2026-06-26) | Rust/GTK4/libadwaita app, ~3k LOC. It drives systemd units over D-Bus (zbus), has a tray (ksni), and its own profile model and `vex-vpn-killswitch` service. Its backend (vendored tadfisher module) is networkd-based. |

---

## 4. User decisions (2026-10-03)

| # | Decision |
|---|---|
| 1 | **WireGuard primary, OpenVPN kept as a backup protocol.** |
| 2 | **Also replace the toggleable kill switch on desktop and HTPC** (off by default there). |
| 3 | Prefer **sops** unless there are compelling reasons against it. See §5.6 for the reasons and the resolution. |
| 4 | **Fastest region picked automatically**, with the ability to switch regions at will. |
| 5 | Must work **wired or wireless on any hardware**. This is a hard requirement, and the design no longer depends on any NetworkManager profile. |
| 6 | vex-vpn may be reworked into the GUI for this backend. That happens later, in its own repo; this spec defines the contract it will use (§5.7). |

---

## 5. Architecture

### 5.1 Principles
- **One owner of tunnel state:** a NixOS-declared systemd service, not NetworkManager or GNOME. NM still manages Ethernet and Wi-Fi (any hardware, any profile), and the VPN sits on top of whatever link NM brings up.
- **No DNS outside the tunnel, ever.** Every PIA endpoint is addressed by IP from PIA's server list, and TLS names are pinned with `curl --connect-to` against PIA's CA.
- **The kill switch is an allow-list, not a block-list.** Default drop, and the only clearnet exit is packets carrying the VPN's firewall mark (the Mullvad model). No ordering-sensitive "allow X but not Y" chains.
- **Fail closed.** If the kill switch can't load, NetworkManager doesn't start.

### 5.2 Files (Option B module pattern)

| File | Content |
|---|---|
| `pkgs/vexos-vpn/default.nix` + `vexos-vpn.sh` | `writeShellApplication` CLI/daemon (curl, jq, wireguard-tools, openvpn, iproute2, nftables, systemd). Vendors PIA's public `ca.rsa.4096.crt`. |
| `modules/vpn.nix` | Universal base for roles that import it. Declares `vexos.vpn.*`, the units, polkit, nft ruleset, and `checkReversePath = "loose"`. Uses `lib.mkIf cfg.killSwitch.*`, which is a same-module option guard and allowed by the carve-out. |
| `modules/vpn-stateless.nix` | `vexos.vpn.autoConnect = true; vexos.vpn.killSwitch.enable = "always";` plus persisting `/var/lib/vexos-vpn`. |
| `configuration-desktop.nix`, `configuration-htpc.nix` | Swap the `network-killswitch-service.nix` import for `vpn.nix`. Defaults: VPN installed, not auto-connected, kill switch `"manual"` (off until toggled). |
| `configuration-stateless.nix` | Swap `network-killswitch-stateless.nix` for `vpn.nix` + `vpn-stateless.nix`. Remove the `system-connections` persist entry (no NM VPN profiles any more). Leave the Wi-Fi persistence question unchanged (separate concern). |
| **Delete** | `modules/network-killswitch-stateless.nix`, `modules/network-killswitch-service.nix`, the `forceFixedDns` option and its `ensureProfiles` block in `modules/network.nix` (its only consumer goes away). |
| `justfile` | Rewire `enable/disable-kill-switch`; add `vpn-up`, `vpn-down`, `vpn-status`, `vpn-region`, `vpn-regions`, `vpn-protocol`, `vpn-login`. |
| `modules/desktop-common.nix` | **Unchanged.** `networkmanager-openvpn` stays, so ad-hoc `.ovpn` imports for non-PIA uses still work; they just aren't the PIA path any more. |

### 5.3 Options
```nix
vexos.vpn = {
  protocol        = enum [ "wireguard" "openvpn" ]  (default "wireguard");  # build-time default; runtime switch overrides
  region          = str  (default "auto");          # "auto" = lowest latency; else a PIA region id e.g. "us-newjersey"
  autoConnect     = bool (default false);
  credentialsFile = str  (default "/var/lib/vexos-vpn/credentials");  # see §5.6
  killSwitch = {
    enable   = enum [ "off" "manual" "always" ] (default "manual");
    #   off    – no kill-switch unit at all
    #   manual – unit exists, not started at boot; toggled at runtime (desktop/htpc)
    #   always – started before network-pre.target, RequiredBy NetworkManager (stateless)
    allowLan = bool (default true);   # RFC1918 + link-local + multicast, minus DNS ports (NAS/SMB)
  };
};
```

Runtime state lives in `/var/lib/vexos-vpn/` (persisted on stateless): `state.json` (chosen region and protocol, which overrides the build-time defaults), `serverlist.json` (cached), `token` (24 h), `credentials`.

### 5.4 Connection daemon: `vexos-vpn.service`
`Type=notify` (or `simple` with a readiness file), `Restart=always`, `RestartSec=5`, `After=network-online.target vexos-killswitch.service`. Only the main process runs as root, with hardening set: `ProtectSystem=strict`, `ReadWritePaths=/var/lib/vexos-vpn`, `CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW`.

1. **Server list.** Load `serverlist.json`. If it is missing (first boot) **or** every cached endpoint fails, run a *bootstrap refresh*: add the root-only, transient nft rule "UDP 53 to 1.1.1.1 and TCP 443 to `@bootstrap`", resolve `serverlist.piaservers.net` with `dig @1.1.1.1`, add those IPs to `@bootstrap`, fetch, then flush `@bootstrap` and delete the rule. Otherwise refresh through the tunnel after each successful connect. Apps can never use the bootstrap hole, because it matches `meta skuid 0` only and lives for seconds.
2. **Region.** If `auto`, TCP-connect-time to each region's meta IP on 443 (the same method as PIA's `get_region.sh`), in parallel with a 1 s cap, and pick the lowest. Otherwise use the named region.
3. **Token.** POST credentials to `https://<meta-cn>/authv3/generateToken` via `--connect-to <cn>::<meta-ip>:` and `--cacert ca.rsa.4096.crt`. Cache it; refresh when older than 20 h.
4. **WireGuard:**
   - Generate an ephemeral keypair (memory only) and call `addKey` at `<wg-ip>:1337` (pinned).
   - Bring up the tunnel: `ip link add pia0 type wireguard`, then `wg set pia0 private-key … fwmark 0x5650 peer … endpoint <wg-ip>:<port> allowed-ips 0.0.0.0/0 persistent-keepalive 25`, and add the peer IP `/32`.
   - Routing: table 0x5650 `default dev pia0`; `ip rule add not fwmark 0x5650 table 0x5650`; `ip rule add table main suppress_prefixlength 0`. This is exactly wg-quick's scheme, so it survives Wi-Fi/Ethernet changes with no route edits.
5. **OpenVPN (backup):**
   - Generate `/run/vexos-vpn/pia.ovpn`: `dev pia0-ovpn`, `dev-type tun`, `proto udp`, `remote <ovpnudp-ip> 8080`, `verify-x509-name <cn> name`, `cipher`/`data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC`, `auth sha256`, `remote-cert-tls server`, `<ca>` = PIA 4096 CA.
   - **No `compress`, no `crl-verify`**: these are the two directives that break PIA on current OpenVPN/OpenSSL (§2).
   - Auth with the token as username and password, so the PIA password is never handed to OpenVPN.
   - `mark 0x5650` (OpenVPN's SO_MARK option) and `route-noexec` / `pull-filter ignore "redirect-gateway"`; then apply the **same** policy routing as WireGuard against `pia0-ovpn`. The kill switch and routing are identical for both protocols.
6. **DNS.** `resolvectl dns <iface> 10.0.0.242` (PIA in-tunnel DNS) and `resolvectl domain <iface> '~.'`, so systemd-resolved sends every query into the tunnel. Link DNS from NM stays configured but is never reachable (kill switch), so no leak even if resolved misbehaves.
7. **Health check.** Every 30 s: for WireGuard, a `latest-handshake` older than 180 s triggers a reconnect; for OpenVPN, rely on `ping-restart 60`. Region or protocol failure falls through to the next-best region (bounded retries, then back off and log).
8. **Teardown** (`ExecStopPost`): delete the interface and rules, and revert resolvectl. With the kill switch on, teardown leaves the machine offline.

Port forwarding is **out of scope**; it can be added later via PIA's `getSignature`/`bindPort`, and the API path is known.

### 5.5 Kill switch: `vexos-killswitch.service`
A separate nftables table, `inet vexos_killswitch`, loaded atomically with `nft -f`. It is independent of the NixOS iptables firewall: both stacks run on the same hooks, and a drop in either wins.

```
table inet vexos_killswitch {
  set pia_servers { type ipv4_addr; flags interval; }   # every meta/wg/ovpn IP from serverlist.json
  set bootstrap   { type ipv4_addr; }                   # transient, see §5.4 step 1
  set lan4        { type ipv4_addr; flags interval; elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4 } }

  chain output {
    type filter hook output priority filter; policy drop;
    oif lo accept
    meta nfproto ipv6 drop                         # v6 off anyway; defense in depth
    ct state established,related accept
    oifname { "pia0", "pia0-ovpn", "tailscale0" } accept
    meta mark 0x5650 ip daddr @pia_servers accept  # only the tunnel's own encrypted packets, only to PIA
    meta skuid 0 ip daddr @pia_servers tcp dport { 443, 1337 } accept   # token, addKey, latency probes (root only)
    udp sport 68 udp dport 67 accept               # DHCP (any interface: wired or Wi-Fi)
    # allowLan:
    ip daddr @lan4 udp dport { 53, 853 } drop      # DNS guard is part of the LAN rule, not ordering-dependent on other rules
    ip daddr @lan4 tcp dport { 53, 853 } drop
    ip daddr @lan4 accept
  }
}
```

Important behaviours:
- **Activation.** `always`: `WantedBy=multi-user.target`, `Before=network-pre.target`, `Wants=network-pre.target`, `RequiredBy=NetworkManager.service`. `manual`: the unit exists but is not wanted by anything.
- **Runtime off on stateless.** Stopping the unit is allowed via polkit with **`auth_admin_keep`** (password prompt) for `always` mode, and with no prompt in `manual` mode. On stateless a reboot always restores it. This is the "flexible, but foolproof when enabled" balance; tell me if you want stateless to refuse off entirely, as the current `just` recipe does.
- **Updating `@pia_servers`.** `vexos-vpn` repopulates it atomically after each server-list refresh.
- **Wi-Fi/Ethernet agnostic.** No rule names a physical interface or an NM profile.
- **Why an fwmark, not uid.** Only `CAP_NET_ADMIN` processes can set SO_MARK, and WireGuard marks its own UDP in-kernel. User processes can't forge it. Same reasoning as Mullvad (source #6).

### 5.6 Credentials: why the default is a root-only file, with sops supported
You asked for sops unless there's a compelling reason. Three reasons apply to this repo specifically:

1. **No disk encryption on any role (source #11).** sops-nix decrypts with an age key that must sit on the same unencrypted disk as the ciphertext. Anyone who can read `/persistent/var/lib/vexos-vpn/credentials` can equally read `/persistent/var/lib/sops-nix/key.txt` and the encrypted file. Encryption at rest buys **no** protection here. sops's real benefit, keeping secrets safe in git, doesn't apply either, since the encrypted file lives per host under `/etc/nixos`, not in this repo.
2. **Stateless regenerates SSH host keys every boot (source #11).** sops-nix's default host identity (`ssh_host_ed25519_key`) would change every reboot and fail to decrypt. We'd have to persist a dedicated age key. That works, but it adds state to the role whose purpose is minimal state.
3. **Changing credentials needs a workstation and a rebuild.** That means `sops edit`, re-encrypting to every host's recipient, then rebuilding. It also rules out the GUI login flow (§5.7).

**Resolution:** `vexos.vpn.credentialsFile` is just a path. By default `sudo vexos-vpn login` (or the GUI) writes a root:root 0400 file. Where sops is wanted (e.g. a server role that already uses it, or later, if LUKS is added), point it at `config.sops.secrets.pia-credentials.path` with no code change. If you'd rather have sops everywhere anyway, say so and I'll add sops-nix to the desktop, htpc and stateless module lists plus a persisted age key. If you **add LUKS later**, revisit this, because sops then adds real value.

### 5.7 vex-vpn GUI contract (no work in this phase)
The backend exposes everything a GUI needs without the GUI holding privileges:
- **Read:** `vexos-vpn status --json` (unprivileged) returns `{state, protocol, region, server_cn, endpoint_ip, public_ip, rx, tx, handshake_age, killswitch, killswitch_mode}`. `vexos-vpn regions --json` returns the list with cached latencies.
- **Act (via systemd D-Bus, polkit-gated for group `users`):** start/stop/restart `vexos-vpn.service`; start/stop `vexos-killswitch.service` (stop requires admin auth in `always` mode); `vexos-vpn-set@<value>.service`, a oneshot template that validates `<value>` (`region=<id>`, `protocol=wireguard|openvpn`), writes `state.json`, and restarts the daemon. Credentials go through `pkexec vexos-vpn login`.
- Because this is what vex-vpn already does (zbus → systemd units), the rework is: delete its `backend/`, profile model and vendored networkd module; keep the UI, tray and D-Bus layer; point it at these units and the JSON status. That's a separate spec in the vex-vpn repo, after this lands.

## 6. Implementation steps (Phase 2)

1. **`pkgs/vexos-vpn`.** Verify: `nix build`; `shellcheck` clean (writeShellApplication enforces this); `vexos-vpn regions --json` runs against a saved `serverlist.json` fixture.
2. **`modules/vpn.nix`** (options, three units + `vexos-vpn-set@`, polkit, nft file, rpfilter loose). Verify: `nix eval` toplevel drvPath for stateless, desktop and htpc.
3. **Role wiring and deletions** (§5.2) plus justfile. Verify: `grep` shows no references to the deleted modules or to `forceFixedDns`.
4. **Offline kill-switch leak test** in `unshare -rn`, with no PIA account needed. Load the evaluated ruleset with a dummy interface and fake `@pia_servers`, then check:
   - an unmarked UDP/TCP packet to a public IP is dropped
   - a marked packet to a `@pia_servers` IP passes
   - a marked packet to a non-PIA IP is dropped
   - LAN :445 passes and LAN :53 is dropped
   - IPv6 is dropped
5. **Phase 3/6** per CLAUDE.md (flake show, dry-builds incl. stateless + htpc, preflight).
6. **Live acceptance on real hardware (user):**
   - Run `sudo vexos-vpn login` and reboot.
   - The tunnel must come up unattended on **Wi-Fi and on Ethernet**.
   - Run `curl ifconfig.io` and a DNS-leak test.
   - `systemctl stop vexos-vpn` must leave the machine offline apart from the LAN.
   - `vexos-vpn region <x>` and `vexos-vpn protocol openvpn` must both reconnect.

## 7. Dependencies
All in nixpkgs (locked, no new flake inputs): `wireguard-tools`, `openvpn` (2.6.23), `curl`, `jq`, `dig` (`dnsutils`, bootstrap only), `nftables`, `iproute2`. PIA's public CA is vendored. Context7 is not applicable. The PIA API is verified against the PIA-maintained scripts (sources #1–#3) and the live server list.

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| PIA changes its API | Same API as their app; repo maintained (2026-09). Fails closed. `vexos-vpn status` shows the API error. |
| `authv3/generateToken` on meta IPs is deprecated in favour of `/api/client/v2/token` on `www.privateinternetaccess.com` | Try meta first; fall back to the v2 endpoint through the bootstrap path (§5.4.1). Phase 2 verifies which one works with a live account during acceptance. |
| Captive-portal Wi-Fi | `vexos-vpn killswitch off` (password on stateless) → log in → back on. Documented. |
| iptables (firewall) + nftables (kill switch) coexisting | Both supported on iptables-nft. Covered by the step 4 netns test. |
| `checkReversePath = "loose"` weakens spoofing protection slightly | Required for fwmark routing (source #7); same as NixOS wg-quick guidance. Only on roles importing `vpn.nix`. |
| Desktop/HTPC behaviour change | The kill switch stays off by default, as today. The GNOME VPN menu no longer shows PIA (use the CLI/just, then vex-vpn later). |
| SMB discovery (fragile, see memory) | `allowLan` keeps multicast 224.0.0.0/4 + RFC1918; mDNS is UDP 5353, untouched by the 53/853 guard. Desktop is unaffected unless the switch is on. |
| Tailscale on stateless only works once the VPN is up | Intended (no clearnet without VPN). Unchanged on desktop/htpc while the kill switch is off. |

---

## 9. Revision 3: final decisions and as-built notes (2026-10-03)

**User decisions:**
- Credentials: a root-only file, plus a sops-capable `credentialsFile` option.
- Stateless kill switch off: allowed with an admin password (polkit `AUTH_ADMIN_KEEP`), lasting until reboot.
- Credentials are **never shared with the agent**. Endpoints were verified with bogus credentials. The user verifies their own login with `just vpn-selftest`, which prints OK/FAILED only.

**Tailscale (verified on this host's live `ip rule`):**
- Tailscale marks its own packets `0x80000` and routes them via the main table (rule 5210), i.e. around any tunnel.
- While the kill switch is on, rule pref 5200 sends them into table 22096 (the tunnel). With the tunnel down they fall through and the kill switch drops them.
- Result: on stateless the tailnet is available only while PIA is up, relayed through PIA. Desktop and htpc are unchanged unless the kill switch is on.

**As-built deviations from §5:**
- `killSwitch.enable` is now `killSwitch.mode`.
- No `vexos.vpn.enable` option (importing the module enables it).
- `system-connections` stays persisted (Wi-Fi).
- No v2-token fallback (meta endpoint verified live).
- No committed server-list snapshot (self-expiring bootstrap instead).
- OpenVPN runs as root (SO_MARK on reconnect).
- Region/protocol changes go through polkit-gated `vexos-vpn-region@` / `vexos-vpn-protocol@` template units, so CLI and GUI need no sudo.
- A DNS-guard table (`inet vexos_vpn_dns`) is active whenever the tunnel is up, even with the kill switch off.

## 10. Revision 4: GUI-driven credentials and GUI delivery (2026-10-03)

User requirement: full control from the GUI, **including entering the PIA username and password**, with the CLI/justfile as backup. The GUI ships via flake and is installed on every role that imports `modules/vpn.nix`.

Backend additions (vexos-nix):
- `vexos-vpn login --stdin` reads username and password from stdin (for `pkexec vexos-vpn login --stdin`), so the secrets never touch argv, the environment, or the disk outside the root-only credentials file.
- `vexos-vpn logout` removes credentials and token, and stops the VPN.
- Both refuse when `credentialsFile` is not the default path (sops-managed).
- `status --json` gains `logged_in` (file existence only), `credentials_editable` and `autoconnect` (`AUTOCONNECT` written to `/etc/vexos-vpn/config`).

GUI delivery (follow-up, in vexos-nix, once vex-vpn is reworked per `vex_vpn_gui_rework_prompt.md`):
- Add flake input `vex-vpn` (`inputs.nixpkgs.follows = "nixpkgs"`).
- In `modules/vpn.nix`, import `inputs.vex-vpn.nixosModules.default` and set `programs.vex-vpn.enable = true`.
- Done in vexos-nix, not in the vex-vpn session, because the input can't be added until vex-vpn's new flake outputs exist.

Also: `scripts/preflight.sh` stage 7e now always runs gitleaks (fetched via `nix shell` when not installed), and it is a hard failure.

## 11. Revision 5: vex-vpn GUI hooked up (2026-10-03)

- `flake.nix`: new input `vex-vpn` (`github:victorytek/vex-vpn`, `inputs.nixpkgs.follows = "nixpkgs"`; its only other input, crane, has no inputs). `flake.lock` pins it to `0691d4e`; the lock change is purely additive.
- `modules/vpn.nix` imports `inputs.vex-vpn.nixosModules.default` and sets `programs.vex-vpn.enable = true` unconditionally, so every role that imports `vpn.nix` (desktop, htpc, stateless) gets the GUI and the tray autostart, and roles without the VPN (server, headless-server, vanilla) do not. Tray autostart is a systemd user service bound to `graphical-session.target` (GNOME; Hyprland via UWSM, which this repo already requires).
- The GUI is not in any binary cache, so it is a cargo release build on a fresh install, in the same class as `up`/`vexportal` (~2 min, ~1.9 GiB peak). `--max-jobs 1` stays as chosen; publishing it to a cache is the lever if install time matters.
