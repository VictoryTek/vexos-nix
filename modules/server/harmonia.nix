# modules/server/harmonia.nix
# Harmonia — lightweight Nix binary cache server (nix-community, Rust).
# Default port: 5000 (upstream default; no conflict with other vexos services).
#
# Harmonia serves this host's own /nix/store read-only over HTTP. It has NO
# upload API — nothing can "push" to it. Paths become available by being built
# on this machine, or copied here with `nix copy --to ssh-ng://<host>`.
# If you need remote CI to publish into a cache, use Attic (modules/server/attic.nix)
# instead; the two are not interchangeable.
#
# Because it serves the whole store, every store path on this host becomes
# readable by anyone who can reach the port. Store paths are already
# world-readable locally, but this publishes them to the network — keep
# Harmonia on the LAN and do NOT expose it to the internet.
#
# The signing keypair is generated automatically on first activation (see the
# harmoniaKey activationScript below); there are no tokens, logins, or
# bootstrap steps. After enabling and rebuilding, run `just harmonia-info` to
# confirm the service is live and print the client configuration.
#
# Note on garbage collection: Harmonia only serves what is currently in the
# store, and modules/nix.nix sets min-free/max-free auto-GC. Anything that must
# stay served needs a GC root (`nix-store --add-root`).
{ config, lib, ... }:
let
  cfg = config.vexos.server.harmonia;
in
{
  options.vexos.server.harmonia = {
    enable = lib.mkEnableOption "Harmonia Nix binary cache server";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 5000;
      description = "Port for the Harmonia HTTP listener.";
    };

    signKeyPath = lib.mkOption {
      type    = lib.types.path;
      default = "/var/lib/harmonia/cache-priv-key.pem";
      description = ''
        Path to the binary cache signing key. Generated automatically on first
        activation if absent, together with a matching .pub file.
        Clients need the public half in nix.settings.trusted-public-keys —
        see vexos.harmonia.publicKey in modules/nix.nix.
      '';
    };

    openFirewall = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Open the firewall for Harmonia's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate the signing keypair on first activation so enabling Harmonia
    # doesn't require a manual key step (same approach as attic.nix's
    # atticSecret script). The key name is derived from the hostname so that
    # several vexos cache hosts never collide in a client's trusted-public-keys.
    #
    # The private key stays root-owned 0600: the upstream NixOS module passes it
    # to the service via systemd LoadCredential, which systemd reads as root
    # before dropping to the unit's DynamicUser. The public half is 0644 so
    # `just harmonia-info` can print it without sudo.
    system.activationScripts.harmoniaKey = ''
      if [ ! -e "${cfg.signKeyPath}" ]; then
        mkdir -p "$(dirname "${cfg.signKeyPath}")"
        chmod 0700 "$(dirname "${cfg.signKeyPath}")"
        ${config.nix.package}/bin/nix-store --generate-binary-cache-key \
          "${config.networking.hostName}-1" \
          "${cfg.signKeyPath}" \
          "${cfg.signKeyPath}.pub"
        chmod 0600 "${cfg.signKeyPath}"
        chmod 0644 "${cfg.signKeyPath}.pub"
      fi
    '';

    services.harmonia.cache = {
      enable       = true;
      signKeyPaths = [ cfg.signKeyPath ];
      settings.bind = "[::]:${toString cfg.port}";
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
