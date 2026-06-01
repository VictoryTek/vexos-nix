# overlays/vscode.nix
# Pin pkgs.unstable.vscode (and pkgs.unstable.vscode-fhs) to a specific
# version fetched directly from Microsoft's update servers, bypassing whatever
# version nixpkgs-unstable currently ships.
#
# Applied via .extend() on the nixpkgs-unstable import in flake.nix so that
# pkgs.unstable.vscode-fhs (used in home-desktop.nix programs.vscode) picks up
# this version automatically.
#
# To update to a new version, run:
#   just update-vscode <VERSION>
#
# To update manually:
#   1. Run: nix-prefetch-url https://update.code.visualstudio.com/<VERSION>/linux-x64/stable
#   2. Convert: nix hash to-sri --type sha256 <nix-base32-hash-from-step-1>
#   3. Update `version` and `hash` below.
final: prev: {
  vscode = prev.vscode.overrideAttrs (old: rec {
    # ── Pinned version — updated by: just update-vscode <VERSION> ────────────
    version = "1.122.1";

    src = prev.fetchurl {
      # Microsoft stable-channel tarball for linux-x64.
      # This URL redirects to the CDN; fetchurl follows the redirect via curl -L.
      url  = "https://update.code.visualstudio.com/${version}/linux-x64/stable";

      # SHA256 hash in SRI format (sha256-<base64>).
      # Updated by:  just update-vscode <VERSION>
      hash = "sha256-t26YN3E5XaSJ7gki8nm06hVh4ZvXDEU77M749ZrqfAo=";

      # Explicit name required: the URL path ends in "stable", not ".tar.gz",
      # so without this the Nix store path basename would be uninformative.
      name = "vscode-${version}-linux-x64.tar.gz";
    };
  });
}
