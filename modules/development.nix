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

  environment.systemPackages = with pkgs; [

    # ── Editor ────────────────────────────────────────────────────────────────
    unstable.vscode-fhs                           # VS Code in FHS env (fixes launch on NixOS)

    # ── Python ────────────────────────────────────────────────────────────────
    python3                                       # CPython interpreter
    uv                                            # Fast Python package & project manager
    ruff                                          # Python linter & formatter

    # ── Rust ──────────────────────────────────────────────────────────────────
    rustfmt                                       # Rust code formatter
    clippy                                        # Rust linter
    rustup                                        # Rust toolchain manager (rustc, cargo, clippy)

    # ── TypeScript / Node ─────────────────────────────────────────────────────
    nodejs                                        # Node.js runtime + npm
    nodePackages.typescript                       # TypeScript compiler (tsc)
    pnpm                                          # Fast, disk-efficient Node package manager
    bun                                           # All-in-one JS/TS runtime & bundler

    # ── Containers ────────────────────────────────────────────────────────────
    podman-compose                                # docker-compose compatible CLI for Podman
    buildah                                       # OCI image builder (rootless)
    skopeo                                        # Container image inspection & transfer

    # ── Flatpak development ───────────────────────────────────────────────────
    flatpak-builder                               # Build Flatpak application bundles

    # ── General dev utilities ─────────────────────────────────────────────────
    gh                                            # GitHub CLI
    git-lfs                                       # Git Large File Storage
    jq                                            # JSON processor / pretty-printer
    yq-go                                         # YAML / TOML / XML processor
    direnv                                        # Per-directory environment variables
    pre-commit                                    # Git hook framework
    sqlite                                        # Embedded SQL database + CLI
    httpie                                        # Human-friendly HTTP client
    mkcert                                        # Locally-trusted dev TLS certificates

    # ── Base system utilities ─────────────────────────────────────────────────
    brave                                         # Chromium-based browser
    git                                           # Version control
    curl                                          # HTTP / transfer CLI
    wget                                          # File downloader
    inxi                                          # System information tool
    htop                                          # Interactive process viewer

  ];
}
