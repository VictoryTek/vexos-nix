# static_ip_keyfile_fix — Specification

## Current State

`modules/network.nix` writes a NetworkManager keyfile profile for static wired IP
via `networking.networkmanager.ensureProfiles.profiles`. The `ipv4` section currently
uses two separate keys:

```nix
ipv4 = {
  method    = "manual";
  addresses = config.vexos.network.staticWired.address;
  gateway   = config.vexos.network.staticWired.gateway;
  dns       = lib.concatStringsSep ";" config.vexos.network.staticWired.dns;
};
```

## Problem

The NM keyfile format (nm-settings-keyfile(5)) does not recognise `addresses` as a
valid key. The correct key is `address1` (and `address2`, etc. for multiple addresses),
which combines the IP/prefix and gateway in a single comma-separated value:

  address1=192.168.1.10/24,192.168.1.1

A separate `gateway` key does exist in the keyfile spec but is deprecated and ignored
when `address1` is present. Using `addresses` + `gateway` causes NetworkManager to
silently skip the static IP assignment and fall back to DHCP.

## Proposed Solution

Replace the `addresses` and `gateway` keys with a single `address1` key that combines
both values per the nm-settings-keyfile(5) spec.

```nix
ipv4 = {
  method   = "manual";
  address1 = "${config.vexos.network.staticWired.address},${config.vexos.network.staticWired.gateway}";
  dns      = lib.concatStringsSep ";" config.vexos.network.staticWired.dns;
};
```

## Files Modified

- `modules/network.nix` (lines 116-120: replace `addresses` + `gateway` with `address1`)

## Risks

- Any machine currently using `vexos.network.staticWired` will have their static IP
  actually applied for the first time after the next rebuild. This is the intended
  behaviour — the previous code was silently broken.
- No option signature change; no impact on machines not using `staticWired`.
