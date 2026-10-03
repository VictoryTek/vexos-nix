# pkgs/vexos-vpn/default.nix
# vexos-vpn — PIA VPN client (WireGuard primary, OpenVPN backup) and the
# control CLI for the kill switch. The NixOS side (units, nftables ruleset,
# polkit, /etc/vexos-vpn/config) lives in modules/vpn.nix.
#
# Talks to PIA's own API (the one documented by PIA in
# github.com/pia-foss/manual-connections) by IP address only, with TLS pinned
# to PIA's CA (ca.rsa.4096.crt, vendored from that repo) — no DNS is needed to
# connect, which is what lets the kill switch block all clearnet DNS.
#
# shellcheck runs at build time via writeShellApplication.
{ writeShellApplication
, coreutils
, curl
, jq
, wireguard-tools
, openvpn
, iproute2
, nftables
, systemd
, dnsutils
, gnugrep
, util-linux
, gawk
, findutils
}:

writeShellApplication {
  name = "vexos-vpn";
  runtimeInputs = [
    coreutils curl jq wireguard-tools openvpn iproute2 nftables systemd
    dnsutils gnugrep util-linux gawk findutils
  ];
  text = ''
    PIA_CA="${./ca.rsa.4096.crt}"
  '' + builtins.readFile ./vexos-vpn.sh;
}
