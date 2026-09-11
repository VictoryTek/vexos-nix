# home/browser-extensions.nix
# Shared addition for every role that installs brave-origin (desktop, server,
# htpc, stateless — see home/gnome-common-browser.nix, which this mirrors):
# preinstalls the same 5 extensions into Brave Origin and LibreWolf, and
# defaults both to vertical tabs. Installed editable/removable, not locked —
# the user can disable or uninstall any of them afterward like any other
# extension.
#
# Extension IDs verified directly against live Chrome Web Store / addons.mozilla.org
# listings (and the AMO v5 API for Firefox GUIDs) — see
# .github/docs/subagent_docs/browser_extensions_vertical_tabs_spec.md for how
# each was confirmed, and why LibreWolf moved off Flatpak (modules/flatpak.nix)
# to the native nixpkgs package to make this possible at all.
{ config, pkgs, lib, ... }:
let
  # Brave Origin's actual per-user config dir (confirmed in
  # home/gnome-common-browser.nix's stale-lock handling).
  braveConfigDir = "${config.home.homeDirectory}/.config/BraveSoftware/Brave-Origin";

  # id = Chrome Web Store ID, amoGuid/amoSlug = Firefox (addons.mozilla.org) identity.
  extensions = [
    { name = "bitwarden";  id = "nngceckbapebfimnlniiiahkandclblb"; amoGuid = "{446900e4-71c2-419f-a6a7-df9c091e268b}";     amoSlug = "bitwarden-password-manager"; }
    { name = "clearcache"; id = "cppjkneekbjaeellbfkmgnhonkkjfpdn"; amoGuid = "clearcache@michel.de.almeida";               amoSlug = "clearcache"; }
    { name = "purpleads";  id = "lkgcfobnmghhbhgekffaadadhmeoindg"; amoGuid = "{a7399979-5203-4489-9861-b168187b52e1}";     amoSlug = "purpleadblock"; }
    { name = "smarthttps"; id = "cmleijjdpceldbelpnpkddofmcmcaknm"; amoGuid = "{b3e677f4-1150-4387-8629-da738260a48e}";     amoSlug = "smart-https-revived"; }
    { name = "tabliss";    id = "hipekcciheckooncpjeljhnekcoolahp"; amoGuid = "extension@tabliss.io";                      amoSlug = "tabliss"; }
  ];

  # Rendered once at eval time; the activation script below only ever copies
  # this static store path, matching the seedHyprlandConf pattern in
  # home/dank-material-shell.nix.
  braveInitialPreferences = pkgs.writeText "brave-origin-initial-preferences.json"
    (builtins.toJSON { brave.tabs.vertical_tabs_enabled = true; });
in
{
  # ── Brave Origin: preinstalled extensions ─────────────────────────────────
  # Chromium's "External Extensions" mechanism — a per-user, non-enterprise
  # channel that auto-installs on next launch but stays fully removable via
  # chrome://extensions, same as any normally-installed extension. Confirmed
  # present in the actual brave-origin binary (the "External Extensions"
  # string) — see the spec doc.
  home.file = builtins.listToAttrs (map
    (ext: {
      name  = "${braveConfigDir}/External Extensions/${ext.id}.json";
      value.text = builtins.toJSON {
        external_update_url = "https://clients2.google.com/service/update2/crx";
      };
    })
    extensions);

  # ── Brave Origin: default to vertical tabs ────────────────────────────────
  # brave.tabs.vertical_tabs_enabled — confirmed directly from the binary's
  # string table; no dedicated admin policy exists for it, so it's seeded the
  # same one-time way home/dank-material-shell.nix seeds hyprland.conf: only
  # written if the profile's Preferences file doesn't already exist, so it's
  # a first-run default the user is free to change afterward, and a no-op on
  # a host that already has a Brave profile.
  home.activation.seedBraveVerticalTabs =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="${braveConfigDir}/Default/Preferences"
      if [ ! -e "$target" ]; then
        run mkdir -p "${braveConfigDir}/Default"
        run cp ${braveInitialPreferences} "$target"
        run chmod u+w "$target"
      fi
    '';

  # ── LibreWolf: preinstalled extensions + vertical tabs default ───────────
  # policies.* is baked into a wrapped librewolf derivation's own
  # distribution/policies.json (self-contained, no system /etc write) —
  # confirmed by reading home-manager's mkFirefoxModule.nix source directly.
  # installation_mode "normal_installed" and Preferences "Status": "default"
  # both mean "set as the starting value, user can change it" — Mozilla's own
  # non-locked policy tier, matching Brave's editable/removable install above.
  programs.librewolf = {
    enable = true;

    policies = {
      ExtensionSettings = builtins.listToAttrs (map
        (ext: {
          name  = ext.amoGuid;
          value = {
            installation_mode = "normal_installed";
            install_url       = "https://addons.mozilla.org/firefox/downloads/latest/${ext.amoSlug}/latest.xpi";
          };
        })
        extensions);

      Preferences = {
        "sidebar.revamp"      = { Value = true; Status = "default"; };
        "sidebar.verticalTabs" = { Value = true; Status = "default"; };
      };
    };
  };
}
