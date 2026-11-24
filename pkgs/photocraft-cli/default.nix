# pkgs/photocraft-cli/default.nix
# PhotoCraft (storytold) command-line tool, incl. the `photocraft-cli mcp` server.
# Not in nixpkgs, and a source build needs ~115 git-sourced crates plus Rust 1.100, so
# this installs the prebuilt `photocraft-cli` from the official Linux release tarball.
# It links only against glibc/libgcc; autoPatchelfHook fixes the interpreter.
#
# Update: set `version`, then
#   nix-prefetch-url https://github.com/storytold/photocraft/releases/download/v<VER>/photocraft-<VER>-linux-x86_64.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
# (compare with the release's SHA256SUMS.txt).
{ lib, stdenv, fetchurl, autoPatchelfHook }:
stdenv.mkDerivation rec {
  pname = "photocraft-cli";
  version = "0.23.1";

  src = fetchurl {
    url  = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-Q4Ou9noHzDcK0lCm7WABUgXT5sRj+vP/Sw9nuBeMz8g=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/photocraft-cli $out/bin/photocraft-cli
    runHook postInstall
  '';

  meta = {
    description = "PhotoCraft command-line tool and MCP server";
    homepage = "https://github.com/storytold/photocraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "photocraft-cli";
  };
}
