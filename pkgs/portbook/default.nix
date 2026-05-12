# pkgs/portbook/default.nix
# Pre-built portbook Linux binary package.
# Source: https://github.com/a-grasso/portbook/releases
#
# The hash placeholder below is replaced automatically by `just enable portbook`.
# To set it manually:
#   HASH=$(nix-prefetch-url --unpack \
#     https://github.com/a-grasso/portbook/releases/download/v0.2.1/portbook-x86_64-unknown-linux-gnu.tar.xz)
#   SRI=$(nix hash to-sri --type sha256 "$HASH")
#   sed -i "s|lib.fakeHash|\"$SRI\"|" pkgs/portbook/default.nix
{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, iproute2 }:

stdenv.mkDerivation rec {
  pname   = "portbook";
  version = "0.2.1";

  src = fetchurl {
    url  = "https://github.com/a-grasso/portbook/releases/download/v${version}/portbook-x86_64-unknown-linux-gnu.tar.xz";
    hash = "sha256-rMKS/ylTWgE05/J/HL/5t8BoRQsXafWyN7PJYnAAvt4=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs       = [ stdenv.cc.cc.lib ];

  # cargo-dist archives may place the binary at root or in a subdirectory.
  # Use find so the install is robust to either layout.
  sourceRoot    = ".";
  dontConfigure = true;
  dontBuild     = true;

  installPhase = ''
    runHook preInstall

    _bin=$(find . -maxdepth 2 -name portbook -type f -perm /111 | head -1)
    install -Dm755 "$_bin" $out/bin/portbook

    runHook postInstall
  '';

  # Wrap with iproute2 so that `ss` is on PATH for port discovery on Linux.
  postFixup = ''
    wrapProgram $out/bin/portbook \
      --prefix PATH : ${lib.makeBinPath [ iproute2 ]}
  '';

  meta = {
    description = "Auto-discovers localhost HTTP servers and labels them in a web UI or terminal list";
    homepage    = "https://github.com/a-grasso/portbook";
    license     = lib.licenses.mit;
    platforms   = [ "x86_64-linux" ];
    maintainers = [];
  };
}
