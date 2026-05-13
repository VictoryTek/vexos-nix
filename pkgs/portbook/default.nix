# pkgs/portbook/default.nix
# Portbook built from source so that NixOS-specific patches can be applied.
# Source: https://github.com/a-grasso/portbook
#
# NixOS patch applied here (assets/app.js):
#   On NixOS every executable lives under /nix/store/…, so the `cmdline`
#   field is a long unreadable hash path.  We swap the display priority so
#   `command` (the short process name returned by `ss`, e.g. "code-server")
#   is shown first and cmdline is shown only as a fallback.
#
# To update to a new version:
#   1. Update `version` and fetch the new source hash:
#        nix-prefetch-url --unpack \
#          https://github.com/a-grasso/portbook/archive/refs/tags/v<VER>.tar.gz
#        nix hash to-sri --type sha256 <hash>
#   2. Set `cargoHash = lib.fakeHash;`, run `nix build .#vexos.portbook`,
#      copy the "got:" hash from the error, then update cargoHash.
{ lib, rustPlatform, fetchFromGitHub, makeWrapper, iproute2 }:

rustPlatform.buildRustPackage rec {
  pname   = "portbook";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "a-grasso";
    repo  = "portbook";
    rev   = "v${version}";
    hash  = "sha256-fVNvpZm7cCTo9+GyFy+wsyk5GUm3fSGBLc+BR0cq6V0=";
  };

  cargoHash = "sha256-OfiHUp3x3iuaDE1OJmr2QWLpIkBgn4tTd34GFZK1r30=";

  # NixOS display patch: prefer the short process name (e.g. "code-server")
  # over the full /nix/store/… cmdline in the portbook web UI card.
  postPatch = ''
    sed -i \
      's/c\.cmdline || c\.command || ""/c.command || c.cmdline || ""/g' \
      assets/app.js
  '';

  nativeBuildInputs = [ makeWrapper ];

  # Disable the test suite — tests spawn real TCP listeners on fixed ports
  # which can conflict in the Nix sandbox.
  doCheck = false;

  # Wrap with iproute2 so that `ss` is on PATH for port discovery on Linux.
  postFixup = ''
    wrapProgram $out/bin/portbook \
      --prefix PATH : ${lib.makeBinPath [ iproute2 ]}
  '';

  meta = {
    description = "Auto-discovers localhost HTTP servers and labels them in a web UI or terminal list";
    homepage    = "https://github.com/a-grasso/portbook";
    license     = lib.licenses.mit;
    platforms   = lib.platforms.linux;
    maintainers = [];
  };
}
