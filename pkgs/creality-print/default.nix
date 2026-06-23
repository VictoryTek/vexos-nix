# pkgs/creality-print/default.nix
# Creality Print AppImage — official slicer for Creality FDM printers.
# Source: https://github.com/CrealityOfficial/CrealityPrint/releases
#
# To update to a new version:
#   1. Update `version` and the `url` to point to the new release tag.
#   2. Recompute the hash (no Nix required):
#        curl -sL <new_url> | sha256sum
#        printf '%s' "<hex>" | xxd -r -p | base64 -w0
#      Prefix the result with "sha256-" and replace the hash below.
{ lib, appimageTools, fetchurl }:

appimageTools.wrapType2 {
  pname   = "creality-print";
  version = "7.1.0.4414";

  src = fetchurl {
    url  = "https://github.com/CrealityOfficial/CrealityPrint/releases/download/v7.1.0/CrealityPrint_ubuntu2004-V7.1.0.4414-x86_64-Release.AppImage";
    hash = "sha256-mBRIKVXn0VOHN8jhrOt1UBw0KJOupXyeD9ka16FP+9g=";
  };

  meta = {
    description = "Creality's official slicer for FDM 3D printers";
    homepage    = "https://github.com/CrealityOfficial/CrealityPrint";
    license     = lib.licenses.unfree;
    platforms   = [ "x86_64-linux" ];
    maintainers = [];
  };
}
