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

    # ── postPatch: fix ripgrep path for VSCode ≥ 1.122.0 ─────────────────────
    #
    # VSCode 1.122.0 replaced @vscode/ripgrep with @vscode/ripgrep-universal.
    # The nixpkgs base postPatch hard-codes the old path:
    #   resources/app/node_modules/@vscode/ripgrep/bin/rg
    # which no longer exists in the 1.122.1 tarball.
    #
    # The new package's Linux x64 binary is at:
    #   resources/app/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg
    # (accessed after the base postPatch's `asar extract` step, which extracts
    # the asar — including all unpacked entries — to node_modules/).
    #
    # builtins.replaceStrings replaces ALL occurrences (both the `rm` and the
    # `ln -s` lines) and is a no-op if the old string is absent (forward-safe
    # once nixpkgs ships a native 1.122.x fix).
    postPatch = builtins.replaceStrings
      [ "resources/app/node_modules/@vscode/ripgrep/bin/rg" ]
      [ "resources/app/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg" ]
      (old.postPatch or "");
  });
}
