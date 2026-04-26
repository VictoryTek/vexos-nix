# modules/locale.nix
# Timezone and internationalisation defaults. Applies to all roles.
{ lib, ... }:
{
  time.timeZone      = lib.mkDefault "America/Chicago";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
}
