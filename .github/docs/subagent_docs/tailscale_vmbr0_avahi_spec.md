# Tailscale on Server Roles with Proxmox vmbr0 - Research and Specification

Project: vexos-nix
Phase: 1 (Research and Specification)
Status: Ready for implementation
Date: 2026-05-16

---

## 1) Current state

### 1.1 Shared networking baseline (`modules/network.nix`)

- `services.avahi.denyInterfaces = [ "tailscale0" ];` is set in the shared network module.
- `services.tailscale.enable = true;` is also set in the shared network module.
- `services.tailscale.extraUpFlags = [ "--accept-routes=false" ];` is set, but NixOS module docs state `extraUpFlags` are only applied when `services.tailscale.authKeyFile` is set.

Relevant lines:
- `modules/network.nix`: Avahi deny interfaces around line 107, Tailscale enablement around lines 138-147.

### 1.2 Role import scope

`./modules/network.nix` is imported by:
- `configuration-desktop.nix`
- `configuration-htpc.nix`
- `configuration-stateless.nix`
- `configuration-server.nix`
- `configuration-headless-server.nix`

`configuration-vanilla.nix` does not import `./modules/network.nix`.

### 1.3 Proxmox module behavior (`modules/server/proxmox.nix`)

- Proxmox is optional (`vexos.server.proxmox.enable`, default false).
- When enabled, the module configures `vmbr0` via NetworkManager ensureProfiles and enables forwarding sysctls.
- The module currently does not override `services.tailscale.enable`.

### 1.4 Current evaluated values (confirmed via `nix eval`)

- `vexos-server-amd`: `services.tailscale.enable = true`
- `vexos-headless-server-amd`: `services.tailscale.enable = true`
- `vexos-vanilla-amd`: `services.tailscale.enable = false`
- `vexos-server-amd`: `vexos.server.proxmox.enable = false` by default

When extending `vexos-server-amd` in-memory with:
- `vexos.server.proxmox.enable = true`
- `vexos.server.proxmox.ipAddress = "192.168.100.10"`
- `vexos.server.proxmox.bridgeInterface = "eno1"`

the evaluated state is still:
- `services.tailscale.enable = true`
- `services.avahi.denyInterfaces = [ "tailscale0" ]`

### 1.5 Template/operator surface (`template/server-services.nix`)

- Proxmox toggles are present as commented examples.
- No current comment notes Tailscale behavior when Proxmox is enabled.

---

## 2) Problem definition

The unresolved finding is valid in operational intent, with one scope correction:

- Scope correction: Tailscale is not enabled on vanilla role, but it is enabled on all roles that import `modules/network.nix`, including `server` and `headless-server`.
- Risk: If Proxmox is enabled, the host uses `vmbr0` as bridge/management path. Keeping overlay networking enabled by default on this role increases routing and firewall complexity on hypervisor hosts and can create hard-to-debug connectivity issues.
- This is a safety/defaults issue rather than an active breakage in the current repo, because Proxmox is currently not enabled in tracked host files.

Decision requested by user:

- Should Avahi `denyInterfaces` include `vmbr0` by default? **No.**
- Reason: Proxmox commonly uses `vmbr0` as the host's primary bridge interface. Denying `vmbr0` would suppress mDNS advertisements and browsing on the primary LAN path for those hosts.

---

## 3) Research sources (credible, 6+)

1. NixOS tailscale module source (nixos-25.05)
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/services/networking/tailscale.nix
   - Used for option behavior, including `extraUpFlags` semantics and routing-related options.

2. NixOS avahi module source (nixos-25.05)
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/nixos/modules/services/networking/avahi-daemon.nix
   - Used for Nix option semantics for `allowInterfaces` / `denyInterfaces` and precedence.

3. Avahi daemon man page
   - https://manpages.debian.org/bookworm/avahi-daemon/avahi-daemon.conf.5.en.html
   - Confirms `deny-interfaces` behavior and precedence over `allow-interfaces`.

4. Proxmox network reference
   - https://pve.proxmox.com/pve-docs/pve-network-plain.html
   - Confirms bridge model and `vmbr0` as standard/default bridge naming and management pattern.

5. Tailscale CLI `up` reference
   - https://tailscale.com/docs/reference/tailscale-cli/up
   - Confirms `--accept-routes` behavior and platform default notes.

6. Tailscale subnet router documentation
   - https://tailscale.com/docs/features/subnet-routers
   - Used for route-injection behavior and caveats that inform conservative defaults on gateway-like hosts.

7. Nix module priority semantics
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.05/lib/modules.nix
   - Used for `mkOverride`, `mkDefault`, `mkForce`, and priority behavior.

---

## 4) Proposed architecture

Minimal safe fix, scoped to Proxmox-enabled hosts:

1. Keep shared `modules/network.nix` unchanged for now.
2. In `modules/server/proxmox.nix`, add a Proxmox-scope override that disables Tailscale when Proxmox is enabled:

```nix
services.tailscale.enable = lib.mkOverride 90 false;
```

Rationale:
- This is the smallest behavior change that addresses the risk where it actually matters (Proxmox-enabled server nodes).
- It avoids adding role conditionals to shared base modules.
- Priority `90` cleanly overrides the base plain assignment (`100`) in `modules/network.nix`.
- Advanced users still have a deliberate opt-in path (`lib.mkForce true` in host-specific config) if they knowingly want both.

Avahi decision:
- Keep `services.avahi.denyInterfaces = [ "tailscale0" ]` as-is.
- Do not add `vmbr0` to default deny list.

---

## 5) Exact file edits

### Required

1. `modules/server/proxmox.nix`
   - Inside `config = lib.mkIf cfg.enable { ... }`, add:

```nix
# Safety default for hypervisor bridge hosts: disable overlay VPN unless
# explicitly re-enabled by the operator.
services.tailscale.enable = lib.mkOverride 90 false;
```

   - Place near other networking declarations in the Proxmox block.

### Optional (comment-only operator clarity)

2. `template/server-services.nix`
   - In the Proxmox section comments, add a one-line note that Proxmox mode disables Tailscale by default in module logic and requires explicit host override to re-enable.

No edits proposed for:
- `modules/network.nix`
- `configuration-server.nix`
- `configuration-headless-server.nix`

---

## 6) Risks and mitigations

1. Risk: Operators may rely on Tailscale access to reach a Proxmox host.
   - Mitigation: Document the behavior and explicit override path (`lib.mkForce true`) in host config.

2. Risk: Overriding with too strong a priority can make intentional opt-in difficult.
   - Mitigation: Use `mkOverride 90 false` (not `mkForce false`) so explicit stronger overrides remain possible.

3. Risk: Adding `vmbr0` to Avahi deny list would break expected mDNS behavior on Proxmox LAN bridge.
   - Mitigation: Keep default deny list unchanged; if needed, let specific hosts opt in to `vmbr0` deny explicitly.

---

## 7) Validation plan

1. Static/eval validation

- Baseline values:
  - `nix eval --impure --json .#nixosConfigurations.vexos-server-amd.config.services.tailscale.enable`
  - `nix eval --impure --json .#nixosConfigurations.vexos-headless-server-amd.config.services.tailscale.enable`

- Proxmox-enabled in-memory eval (no file mutation), expecting `tailscale = false` after implementation:

```bash
nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString ./.);
  base = flake.nixosConfigurations.vexos-server-amd;
  cfg = base.extendModules {
    modules = [{
      vexos.server.proxmox.enable = true;
      vexos.server.proxmox.ipAddress = "192.168.100.10";
      vexos.server.proxmox.bridgeInterface = "eno1";
    }];
  };
in {
  tailscale = cfg.config.services.tailscale.enable;
  avahiDeny = cfg.config.services.avahi.denyInterfaces;
}'
```

Expected after implementation:
- `tailscale = false`
- `avahiDeny = [ "tailscale0" ]`

2. Repo validation

- `nix flake check --impure`
- `nix build --dry-run --impure .#nixosConfigurations.vexos-server-amd.config.system.build.toplevel`
- `nix build --dry-run --impure .#nixosConfigurations.vexos-headless-server-amd.config.system.build.toplevel`

3. Optional host-side dry-build check (if sudo available)

- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`

---

## 8) Expected modified files

- `modules/server/proxmox.nix` (required)
- `template/server-services.nix` (optional, comments only)
