# pkgs/kiji-proxy/default.nix
# Pre-built kiji-proxy Linux binary package.
# Source: https://github.com/dataiku/kiji-proxy/releases
#
# The hash placeholder below is replaced automatically by `just enable kiji-proxy`.
# To set it manually:
#   HASH=$(nix-prefetch-url --unpack \
#     https://github.com/dataiku/kiji-proxy/releases/download/v1.0.0/kiji-privacy-proxy-1.0.0-linux-amd64.tar.gz)
#   SRI=$(nix hash to-sri --type sha256 "$HASH")
#   sed -i "s|lib.fakeHash|\"$SRI\"|" pkgs/kiji-proxy/default.nix
{ lib, stdenv, fetchurl, autoPatchelfHook }:

stdenv.mkDerivation rec {
  pname   = "kiji-proxy";
  version = "1.0.0";

  src = fetchurl {
    url    = "https://github.com/dataiku/kiji-proxy/releases/download/v${version}/kiji-privacy-proxy-${version}-linux-amd64.tar.gz";
    hash   = lib.fakeHash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs       = [ stdenv.cc.cc.lib ];

  # The tarball extracts to kiji-privacy-proxy-<version>-linux-amd64/
  sourceRoot = "kiji-privacy-proxy-${version}-linux-amd64";

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/kiji-proxy             $out/bin/kiji-proxy
    install -Dm755 lib/libonnxruntime.so.1.24.2 $out/lib/libonnxruntime.so.1.24.2
    ln -s libonnxruntime.so.1.24.2            $out/lib/libonnxruntime.so

    runHook postInstall
  '';

  meta = {
    description = "Privacy proxy that masks PII in AI API requests (OpenAI, Anthropic, etc.)";
    homepage    = "https://github.com/dataiku/kiji-proxy";
    license     = lib.licenses.asl20;
    platforms   = [ "x86_64-linux" ];
    maintainers = [];
  };
}
