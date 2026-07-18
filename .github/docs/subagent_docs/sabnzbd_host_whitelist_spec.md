# SABnzbd External Access Fix — Spec

## Revision History

1. First diagnosis: `host_whitelist` / Caddy vhost. **Wrong** — user doesn't
   use Caddy for this, accesses via a raw Tailscale IP, and
   `host_whitelist` is a hostname-only check that never applies to raw-IP
   access.
2. Second diagnosis: `inet_exposure = "api+web (auth needed)"`. User
   confirmed the access path (Tailscale IP, regular browser, rebuilt and
   live) matched the RFC1918-vs-CGNAT theory, but rejected this fix and
   asked for a revert — forcing login on all access is a workaround for
   the classification gap, not the intended mechanism, and the repo
   default should keep whatever access level the LAN already has.
3. **Corrected fix (this version):** SABnzbd's own docs
   (`sabnzbd.org/wiki/configuration/5.0/special`) document a
   purpose-built setting for exactly this case: `misc.local_ranges` — a
   comma-separated list of CIDR ranges that SABnzbd treats as local
   network, overriding its default RFC1918/RFC4193-only classification.
   This is the intended fix, confirmed via SABnzbd's own documentation
   for the "Specials" config page, and does not change the login/auth
   posture at all.

## Current State Analysis

- `modules/server/arr.nix` configures SABnzbd with
  `settings.misc.host = "0.0.0.0"` only. No `local_ranges`,
  `host_whitelist`, or `inet_exposure` override — all upstream defaults.
- SABnzbd classifies "internet" vs "local" access using RFC1918
  (`192.168.x.x`, `10.x.x.x`, `172.16.x.x`) and RFC4193 ranges only.
- Tailscale assigns addresses from `100.64.0.0/10` (RFC 6598 shared/CGNAT
  space), which is in neither list, so SABnzbd treats a Tailscale-IP
  request as "internet" and denies it under the default
  `inet_exposure = none` — the exact "External internet access denied"
  page the user is hitting, confirmed via a regular browser, on the
  currently-live (rebuilt) config, using a raw Tailscale IP in the URL
  bar.
- `local_ranges` is documented specifically to let you extend what
  SABnzbd considers "local" without touching `inet_exposure` or
  `host_whitelist` at all — i.e., it fixes the classification instead of
  papering over it with a login requirement.

## Problem Definition

SABnzbd doesn't recognize Tailscale's CGNAT range as part of the local
network, so it denies access from it by default, regardless of how open
or restricted the rest of SABnzbd's access controls are configured.

## Proposed Solution

Add `services.sabnzbd.settings.misc.local_ranges = "100.64.0.0/10"` to
the existing `cfg.sabnzbd.enable` block in `modules/server/arr.nix`.
This is additive to whatever `inet_exposure`/auth behavior SABnzbd
already has configured (currently upstream default) — it only widens
what counts as "local," it does not change auth requirements.

## Implementation Steps

```nix
settings.misc = {
  host = "0.0.0.0";
  local_ranges = "100.64.0.0/10"; # Tailscale CGNAT range; not RFC1918/RFC4193,
                                  # so SABnzbd otherwise treats it as "internet"
};
```

Single-value change, same carve-out as before (option inside a subsystem
this module already declares, gated by `cfg.sabnzbd.enable`).

## Dependencies

None — `local_ranges` is accepted via the same freeform `configobj`
settings mechanism already used for `host`; no new packages or flake
inputs; no Context7/nixos MCP lookup needed for an internal string
setting.

## Configuration Changes

- `modules/server/arr.nix`: adds `settings.misc.local_ranges`, does not
  touch `inet_exposure` (left at upstream default — same as the LAN
  today, whatever that default proves to be for this host).

## Risks and Mitigations

- **Risk:** `100.64.0.0/10` covers the whole Tailscale CGNAT block, not
  just this tailnet's assigned addresses — in principle any device using
  that address space (not just this tailnet) would be classified as
  local by SABnzbd.
  **Mitigation:** Tailscale's WireGuard-based auth already gates who can
  reach that IP at all on this host; `local_ranges` only affects
  SABnzbd's internal internet/LAN classification, not actual network
  reachability. Accepted as consistent with how RFC1918 ranges are
  already unconditionally trusted by SABnzbd's own default.
