---
name: vexboard-openfirewall-default-review
feature: vexboard_openfirewall_default
phase: 3-review
---

# Review: vexboard openFirewall default change

## Specification Compliance

Change is exactly what the spec calls for: `default = false` → `default = true` in
`modules/server/vexboard.nix`, with an updated description. No other files touched.

## Checklist

- [x] Single-line default change; no logic added
- [x] No new `lib.mkIf` guards
- [x] No new dependencies
- [x] `hardware-configuration.nix` not tracked (`git ls-files` returned empty)
- [x] `stateVersion` unchanged in all `configuration-*.nix` files
- [x] No new flake inputs

## Build Validation

`sudo` unavailable in sandbox (no-new-privileges container); used `nix eval --impure`
(CI-equivalent per CLAUDE.md) for all required targets:

| Target | Result |
|---|---|
| `vexos-desktop-amd` | `/nix/store/s4wnsa8yvprmcssbi4krd3mhs4dg8x2w-nixos-system-vexos-26.05.drv` ✔ |
| `vexos-server-amd` | `/nix/store/dx5sqh8gi3ayj9h7lwpz4rpsfrkzba2b-nixos-system-vexos-26.05.drv` ✔ |
| `vexos-headless-server-amd` | `/nix/store/a5nczfb57lh1w4dir7pqym0r9zhl2f0s-nixos-system-vexos-26.05.drv` ✔ |
| `vexos-desktop-vm` | `/nix/store/hhpbyplx38zbxazvzbjwsn2isjrjrddm-nixos-system-vexos-26.05.drv` ✔ |
| `nix flake show --impure` | All outputs listed, no errors ✔ |

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

Security note: The preStart guard in the upstream module refuses to start if
`VEXBOARD_AUTH__SECRET` is absent or a placeholder, so opening the firewall by default
does not expose an unauthenticated endpoint.

## Verdict: PASS
