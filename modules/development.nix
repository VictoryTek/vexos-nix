# modules/development.nix
# Development tools: VS Code, Python, Rust, TypeScript/Node, Podman, and general
# app-development utilities installed system-wide.
{ pkgs, ... }:
{
  # ── Podman (rootless container engine) ────────────────────────────────────
  # Provides a Docker-compatible API without a privileged daemon.
  virtualisation.podman = {
    enable     = true;
    dockerCompat = true;             # Adds a `docker` → `podman` symlink
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = [

    # ── Editor ────────────────────────────────────────────────────────────────
    pkgs.unstable.vscode-fhs                      # VS Code in FHS env (fixes launch on NixOS)

    # ── Python ────────────────────────────────────────────────────────────────
    pkgs.python3                                  # CPython interpreter
    pkgs.uv                                       # Fast Python package & project manager
    pkgs.ruff                                     # Python linter & formatter

    # ── TypeScript / Node ─────────────────────────────────────────────────────
    pkgs.nodePackages.typescript                  # TypeScript compiler (tsc)
    pkgs.pnpm                                     # Fast, disk-efficient Node package manager
    pkgs.bun                                      # All-in-one JS/TS runtime & bundler

    # ── Containers ────────────────────────────────────────────────────────────
    pkgs.podman-compose                           # docker-compose compatible CLI for Podman
    pkgs.buildah                                  # OCI image builder (rootless)
    pkgs.skopeo                                   # Container image inspection & transfer

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
