# pkgs/solidcraft-cli/default.nix
# SolidCraft (Tangency Labs) command-line tool, incl. the `solidcraft-cli mcp` server.
# Not in nixpkgs, and a source build needs Rust 1.99.1 plus a large workspace, so this
# installs the prebuilt `solidcraft-cli` from the official Linux release tarball.
# It links only against glibc/libgcc; autoPatchelfHook fixes the interpreter.
# (The GUI app itself comes from the Flatpak bundle in pkgs/craft-apps.)
#
# Update: set `version`, then
#   nix-prefetch-url https://github.com/tangency-labs/solidcraft/releases/download/v<VER>/solidcraft-<VER>-linux-x86_64.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
# (compare with the release's SHA256SUMS.txt).
{ lib, stdenv, fetchurl, autoPatchelfHook }:
stdenv.mkDerivation rec {
  pname = "solidcraft-cli";
  version = "0.48.1";

  src = fetchurl {
    url  = "https://github.com/tangency-labs/solidcraft/releases/download/v${version}/solidcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-B4G9cd4KZ6S/mK2eLMiqUkjTtufbK38d+uf0JlVdi2c=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/solidcraft-cli $out/bin/solidcraft-cli
    runHook postInstall
  '';

  meta = {
    description = "SolidCraft command-line tool and MCP server";
    homepage = "https://github.com/tangency-labs/solidcraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "solidcraft-cli";
  };
}
