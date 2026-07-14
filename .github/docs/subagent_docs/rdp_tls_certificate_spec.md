# RDP TLS Certificate — Specification

**Feature:** `rdp_tls_certificate`
**Phase:** 1 — Research & Specification
**Date:** 2026-07-14
**Status:** Root cause confirmed against GNOME Remote Desktop upstream source.

---

## 1. Problem Definition

RDP has never successfully connected to any vexos machine — not from
`vexos-desktop-nvidia` (Remmina) and not from Windows (`mstsc`), targeting
`vexos-server-intel` over its Tailscale IP.

The symptom is *connection failure*, not authentication failure. That distinction
is the key diagnostic signal: an authentication or credential problem would produce
a rejected login, not a failure to connect. A failure to connect means **nothing is
listening on TCP 3389**.

---

## 2. Current State Analysis

### What the repo configures today

| Concern | Where | State |
|---|---|---|
| GNOME Remote Desktop daemon | `modules/gnome.nix:151` | `services.gnome.gnome-remote-desktop.enable = true` ✅ |
| Firewall port 3389 | `modules/gnome.nix:152` | `networking.firewall.allowedTCPPorts = [ 3389 ]` ✅ (all interfaces, incl. `tailscale0`) |
| Tailscale | `modules/network.nix:178` | enabled ✅ |
| `grdctl rdp enable` | `modules/remote-desktop.nix:87-89` | ✅ |
| `grdctl rdp set-credentials` | `modules/remote-desktop.nix:92-100` | ✅ |
| `grdctl rdp disable-view-only` | `modules/remote-desktop.nix:105-107` | ✅ |
| GNOME Keyring self-heal | `modules/remote-desktop.nix:79-81` | ✅ |
| **`grdctl rdp set-tls-cert`** | — | ❌ **NEVER SET ANYWHERE IN THE REPO** |
| **`grdctl rdp set-tls-key`** | — | ❌ **NEVER SET ANYWHERE IN THE REPO** |

Verified with a repo-wide grep: neither `set-tls-cert` nor `set-tls-key` nor any
certificate generation appears in any module, script, or justfile recipe.

### Why that is fatal

GNOME Remote Desktop **only speaks RDP over TLS**. It has no non-TLS transport.
It also **does not generate its own certificate** — upstream `README.md` explicitly
instructs the administrator to create one with `winpr-makecert`, `certtool`, or
`openssl` and then register the paths via `grdctl`.

The daemon's startup gate, `maybe_start_rdp_server()` in
[`src/grd-daemon.c`](https://github.com/GNOME/gnome-remote-desktop/blob/main/src/grd-daemon.c):

```c
  if ((certificate && key) ||
      grd_context_get_runtime_mode (priv->context) == GRD_RUNTIME_MODE_HANDOVER)
    {
      start_rdp_server (daemon);
    }
  else
    {
      g_message ("RDP TLS certificate and key not yet configured properly");
      start_rdp_server_when_ready (daemon, TRUE);
    }
```

The screen-share (user) daemon runs in `GRD_RUNTIME_MODE_SCREEN_SHARE`, **not**
`HANDOVER` — so the `else` branch is taken. `start_rdp_server()` is never called,
no listening socket is ever created, and the daemon parks indefinitely waiting for
the `tls-cert` / `tls-key` GSettings properties to become non-empty.

Confirmed against the upstream gschema
(`src/org.gnome.desktop.remote-desktop.gschema.xml.in`):

```xml
<key name='tls-cert' type='s'><default>''</default></key>
<key name='tls-key'  type='s'><default>''</default></key>
```

Both default to the empty string. Nothing in vexos ever changes them.

### Ruled out

- **Firewall** — 3389 is opened unconditionally on every interface, including `tailscale0`.
- **Tailscale** — up and running; `--accept-routes=false` does not affect inbound.
- **Credentials / keyring** — the eight prior commits on `modules/remote-desktop.nix`
  correctly land credentials in the keyring. That work is sound; it was simply
  solving the *next* problem, behind a gate that never opened.
- **Auth methods** — gschema default is `['credentials']`, so the
  `!auth_methods → return` guard in `maybe_start_rdp_server()` is not the blocker.
- **`view-only`** — would restrict input, not prevent connection.
- **Client choice** — Remmina and `mstsc` both fail identically, which is exactly what
  "no listener" predicts.

---

## 3. Proposed Solution

Generate a long-lived self-signed TLS certificate per host and register it with
`grdctl` before enabling RDP.

This slots into the **existing** `systemd.services.vexos-rdp-setup` system service in
`modules/remote-desktop.nix`. No new module, no new option, no new `lib.mkIf`.

### Certificate location

`/var/lib/vexos-rdp/{tls.crt,tls.key}`

- `/var/lib` is persistent on every role that imports `remote-desktop.nix`
  (`desktop`, `server`, `htpc`). Only `stateless` uses impermanence, and it does not
  import this module.
- Owned by `config.vexos.user.name` (the user daemon runs as that user and must read
  both files). Directory `0700`, key `0600`, cert `0644`.
- **Not** in the Nix store — a private key must never be world-readable.

### Certificate parameters

```
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout tls.key -out tls.crt -subj "/CN=<hostname>"
```

- Self-signed is correct here: RDP clients pin/accept the certificate on first use.
  Both Remmina and `mstsc` prompt once and remember. A CA-signed cert buys nothing
  on a Tailscale-private tailnet.
- 10-year lifetime avoids a silent expiry-induced regression.
- `-nodes` (no passphrase) is required — the daemon reads the key unattended.
- Generated **once**; regenerated only if either file is missing. Idempotent across
  rebuilds, so a client's pinned fingerprint stays stable.

### Execution order in `vexos-rdp-setup`

1. Generate cert/key if absent (root; no session needed).
2. Wait for the user session D-Bus socket. *(existing)*
3. Self-heal the GNOME Keyring. *(existing)*
4. **`grdctl rdp set-tls-cert` + `set-tls-key`** *(new)*
5. `grdctl rdp enable` *(existing)*
6. `grdctl rdp set-credentials` *(existing)*
7. `grdctl rdp disable-view-only` *(existing)*

TLS paths are set *before* `enable` so the daemon sees a complete configuration on
the first property change rather than parking on the `else` branch and relying on the
`start_rdp_server_when_ready()` watcher.

---

## 4. Implementation Steps

1. `modules/remote-desktop.nix`
   - Add `pkgs.openssl` to the service `path`.
   - Add a `certDir` / `certFile` / `keyFile` `let` binding.
   - Add the idempotent generate-if-missing block at the top of `script`.
   - Add the two `grdctl rdp set-tls-cert` / `set-tls-key` invocations before
     `grdctl rdp enable`.
   - Update the module header comment to document TLS as a first-class requirement.

**Verify:** `grdctl status` on the host reports a non-empty TLS certificate and key;
`ss -tlnp | grep 3389` shows `gnome-remote-de` listening.

2. No changes to `modules/gnome.nix` (firewall and daemon enablement are already correct).
3. No changes to `justfile` (`setup-rdp` already handles the password; the certificate
   requires no user input).

---

## 5. Dependencies

- `pkgs.openssl` — already in nixpkgs, already in the closure of every role. No new
  flake input. Context7 not applicable (no new external library or versioned API).

---

## 6. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Private key readable by other users | Dir `0700` + key `0600`, owned by the vexos user. |
| Key ends up in the Nix store | Generated at runtime into `/var/lib`, never via a Nix path. |
| Cert regenerated on every rebuild → clients re-prompt | Generation is guarded by an existence check on **both** files. |
| Cert expiry causes a silent future outage | 3650-day validity; regeneration is as simple as deleting the two files. |
| `openssl` missing from the unit's `PATH` | Added explicitly to `systemd.services.vexos-rdp-setup.path`. |
| Certificate does not survive a stateless-style wipe | `stateless` does not import this module — out of scope by design. |

---

## 7. Build Validation Constraint

The developer host for this change is **Windows** — `nix` is not available locally.
Per CLAUDE.md, `nix flake check` is forbidden regardless. Structural validation
(`nix flake show --impure`) and per-variant `nixos-rebuild dry-build` must therefore
run on a NixOS host or in GitHub Actions CI. This is stated explicitly rather than
skipped silently.

---

## 8. Sources

1. [GNOME/gnome-remote-desktop — `src/grd-daemon.c`, `maybe_start_rdp_server()`](https://github.com/GNOME/gnome-remote-desktop/blob/main/src/grd-daemon.c) — the TLS gate.
2. [GNOME/gnome-remote-desktop — `src/org.gnome.desktop.remote-desktop.gschema.xml.in`](https://github.com/GNOME/gnome-remote-desktop/blob/main/src/org.gnome.desktop.remote-desktop.gschema.xml.in) — `tls-cert`/`tls-key` default to `''`.
3. [GNOME/gnome-remote-desktop — `README.md`](https://github.com/GNOME/gnome-remote-desktop/blob/main/README.md) — "does not yet provide a way of creating TLS certificates"; documents `openssl`/`certtool`/`winpr-makecert`.
4. [nixpkgs — `nixos/modules/services/desktops/gnome/gnome-remote-desktop.nix`](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/desktops/gnome/gnome-remote-desktop.nix) — the NixOS module performs **no** certificate handling.
5. [Red Hat — Remotely accessing the desktop (RHEL 10)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/administering_rhel_by_using_the_gnome_desktop_environment/remotely-accessing-the-desktop) — TLS key + certificate are prerequisites for RDP.
6. [Oracle Linux — Configure GNOME Remote Desktop](https://docs.oracle.com/en/learn/ol-grd/index.html) — `grdctl rdp set-tls-cert` / `set-tls-key` as a mandatory setup step.
7. [SUSE — Configuring a Remote Desktop Server (SLES 16)](https://documentation.suse.com/sles/16.0/html/SLES-gnome-remote-desktop/index.html) — same requirement, independent vendor.
8. [Arch Linux forums — "gnome-remote-desktop starts, but doesn't open rdp port"](https://bbs.archlinux.org/viewtopic.php?id=302205) — the reported symptom (daemon up, port closed).
