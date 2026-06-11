# libvirtd Socket Conflict Fix — Specification

## Current State Analysis

`modules/virtualization.nix` enables `virtualisation.libvirtd` with socket activation.
NixOS generates a libvirtd.service override with:

```
X-RestartIfChanged=false
Restart=no
```

The upstream libvirtd.service.in ships with:

```
[Unit]
PartOf=libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket
```

NixOS's generated override **drops the `PartOf` directive**. The NixOS socket units
(`libvirtd.socket`, `libvirtd-ro.socket`, `libvirtd-admin.socket`) contain no back-reference
to the service.

## Problem Definition

During `nixos-rebuild switch`, when the system already has libvirtd running from a
previous configuration:

1. switch-to-configuration sees the socket unit files changed (new store paths).
2. New socket units are started (`libvirtd.socket`, `libvirtd-ro.socket`,
   `libvirtd-admin.socket` appear in "starting the following units").
3. libvirtd.service is **not stopped** because `X-RestartIfChanged=false` and there is
   no `PartOf` relationship to trigger a stop when sockets change.
4. The new socket units activate a second libvirtd instance (new store-path PID).
5. The second instance cannot acquire the socket/lock held by the still-running first
   instance. It logs "Make forcefull daemon shutdown" twice and exits with code 1.
6. systemd reports libvirtd.service failed → switch-to-configuration exits with code 4
   ("config applied, services failed").
7. The installer treats any non-zero exit as fatal and reports failure.

Confirmed from journal:
- Failing PID 48322 store path: `sakk18vhxyjaz1fmf1n0lf627a36pmvn-system-units`
- Running PID 34882 store path: `qvazn28l32bsiija7f8mwksk52p9kg0y-system-units`
- All prior runs of libvirtd (same config, no switch in progress) exit cleanly (code 0).

## Proposed Solution

Add `PartOf=libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket` to the
libvirtd.service `[Unit]` section via NixOS module, restoring upstream behavior.

**Effect during switch:**
1. switch-to-configuration stops old socket units (unit files changed).
2. `PartOf` causes systemd to stop libvirtd.service when any of its sockets stop.
3. `KillMode=process` (already set by NixOS) ensures child QEMU VMs are **not** killed.
4. New socket units start cleanly.
5. libvirtd starts fresh (no conflict) when the next connection arrives.

No running VMs are affected because `KillMode=process` exempts child processes.

## Implementation Steps

**File:** `modules/virtualization.nix`

Add after the `virtualisation.libvirtd` block:

```nix
systemd.services.libvirtd.unitConfig = {
  PartOf = "libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket";
};
```

This appends to the `[Unit]` section of the generated override, preserving the existing
`After=libvirtd-config.service` and `Requires=libvirtd-config.service` directives.

## Dependencies

No new external dependencies. Pure NixOS module configuration.

## Configuration Changes

Only `modules/virtualization.nix` is modified. One new `systemd.services` attribute.

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Running VMs interrupted by libvirtd restart | Low | `KillMode=process` already set — QEMU child processes survive libvirtd restart |
| PartOf conflicts with NixOS module's unitConfig | Low | NixOS merges `unitConfig` attrs; existing keys (`After`, `Requires`) are preserved |
| Socket units not in `PartOf` list | None | All three sockets confirmed from install log: libvirtd.socket, libvirtd-ro.socket, libvirtd-admin.socket |
