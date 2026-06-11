# vexboard_security — Specification

## Current State

`modules/server/vexboard.nix` has two insecure defaults:

1. **Placeholder auth secret (line 56):** `settings.auth.secret` is hardcoded to the
   string `"change-me-set-vexos.server.vexboard.secretFile"`. When `secretFile` is null
   (the default), this literal string becomes the active authentication secret. The string
   is committed to a public GitHub repository, so anyone who reads the source can
   authenticate to any VexBoard instance deployed without a `secretFile`.

2. **Firewall open by default (line 25):** `openFirewall` defaults to `true`. Combined
   with the placeholder secret, enabling VexBoard without any further configuration
   immediately exposes port 7280 on the LAN with a publicly-known auth secret.

Note: `openFirewall` only controls the firewall port rule. Service discovery (systemd
polling and Docker socket queries) is local and unaffected by this option.

## Proposed Solution

Two minimal changes to `modules/server/vexboard.nix`:

### Change 1 — Enforce `secretFile` at evaluation time

Add a `lib.throwIf` assertion inside the `config = lib.mkIf cfg.enable { ... }` block:

```nix
assertions = [
  {
    assertion = cfg.secretFile != null;
    message = ''
      vexos.server.vexboard.secretFile must be set before enabling VexBoard.
      Generate a secret with:  openssl rand -base64 48 > /etc/nixos/secrets/vexboard-secret
      Then set: vexos.server.vexboard.secretFile = "/etc/nixos/secrets/vexboard-secret";
    '';
  }
];
```

Using NixOS `assertions` (not `lib.throwIf`) so the error appears as a clean
`nixos-rebuild` failure with a readable message, rather than a raw Nix evaluation trace.

### Change 2 — Default `openFirewall` to `false`

```nix
openFirewall = lib.mkOption {
  type = lib.types.bool;
  default = false;   # was: true
  description = "Open the firewall for VexBoard's port. Set true to expose the dashboard on the LAN.";
};
```

## Files Changed

- `modules/server/vexboard.nix` — add assertion, change openFirewall default

## Risks and Mitigations

- **Breaking change for existing users:** Anyone running VexBoard with the old defaults
  will get a build error until they set `secretFile`. This is intentional — they were
  running with the placeholder secret.
- **openFirewall=false migration:** LAN access to VexBoard will stop after rebuild until
  the user explicitly adds `openFirewall = true`. The `template/server-services.nix`
  comment block for VexBoard already documents `secretFile` — no template change needed.
