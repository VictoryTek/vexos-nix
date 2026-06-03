# modules/development.nix
# Development tools: VS Code, Python, Rust, TypeScript/Node, Docker, and general
# app-development utilities installed system-wide.
{ config, pkgs, ... }:
{
  # ── Docker ────────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable     = true;
    autoPrune.enable = true;         # weekly automatic cleanup of unused images/containers
  };

  # Add the primary user to the docker group so `docker` works without sudo.
  users.users.${config.vexos.user.name}.extraGroups = [ "docker" ];

  environment.systemPackages = [

    # ── Editor ────────────────────────────────────────────────────────────────
    pkgs.unstable.vscode-fhs                        # VS Code in FHS env (required on NixOS)

    # ── Python ────────────────────────────────────────────────────────────────
    pkgs.python3                                  # CPython interpreter
    pkgs.uv                                       # Fast Python package & project manager
    pkgs.ruff                                     # Python linter & formatter

    # ── TypeScript / Node ─────────────────────────────────────────────────────
    pkgs.nodePackages.typescript                  # TypeScript compiler (tsc)
    pkgs.pnpm                                     # Fast, disk-efficient Node package manager
    pkgs.bun                                      # All-in-one JS/TS runtime & bundler

    # ── Containers ────────────────────────────────────────────────────────────
    pkgs.docker-compose                           # docker compose v2 plugin / standalone CLI

    # ── Flatpak development ───────────────────────────────────────────────────
    pkgs.flatpak-builder                          # Build Flatpak application bundles

    # ── General dev utilities ─────────────────────────────────────────────────
    pkgs.gh                                       # GitHub CLI
    pkgs.git-lfs                                  # Git Large File Storage
    pkgs.jq                                       # JSON processor / pretty-printer
    pkgs.yq-go                                    # YAML / TOML / XML processor
    pkgs.pre-commit                               # Git hook framework
    pkgs.sqlite                                   # Embedded SQL database + CLI
    pkgs.httpie                                   # Human-friendly HTTP client
    pkgs.mkcert                                   # Locally-trusted dev TLS certificates
    pkgs.gcc                                      # C/C++ compiler (for native modules, etc.)

    # ── Nix tooling ───────────────────────────────────────────────────────────
    pkgs.nil                                      # Nix LSP server
    pkgs.nixpkgs-fmt                              # Nix code formatter
    pkgs.nix-output-monitor                       # Enhanced nix build output (nom)

    # ── Go ────────────────────────────────────────────────────────────────────
    pkgs.go                                       # Go programming language

  ];
}
