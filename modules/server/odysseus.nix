# modules/server/odysseus.nix
# Odysseus — self-hosted AI workspace (local-first ChatGPT/Claude alternative).
# Runs a Docker Compose stack: odysseus app + ChromaDB (vector memory) + SearXNG (search).
# Default port: 7000
#
# First start clones the Odysseus source then builds the Docker image (~5-10 min).
# Monitor progress: journalctl -fu odysseus
# Admin credentials are printed to the service log on first boot.
#
# Source: https://github.com/pewdiepie-archdaemon/odysseus
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.odysseus;
in
{
  options.vexos.server.odysseus = {
    enable = lib.mkEnableOption "Odysseus self-hosted AI workspace";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 7000;
      description = "Host port for the Odysseus web UI.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/odysseus";
      description = "Directory for persistent data (database, uploads, vector store, logs).";
    };

    authEnabled = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = "Enable login authentication. Keep true on any networked deployment.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      composeFile = pkgs.writeText "odysseus-compose.yml" ''
        services:
          odysseus:
            build:
              context: ${cfg.dataDir}/src
            ports:
              - "${toString cfg.port}:7000"
            volumes:
              - ${cfg.dataDir}/data:/app/data
              - ${cfg.dataDir}/logs:/app/logs
            environment:
              APP_PORT: "7000"
              APP_BIND: "0.0.0.0"
              AUTH_ENABLED: "${if cfg.authEnabled then "true" else "false"}"
              DATABASE_URL: "sqlite:///./data/app.db"
              CHROMADB_HOST: "chromadb"
              CHROMADB_PORT: "8100"
              SEARXNG_INSTANCE: "http://searxng:8080"
            depends_on:
              chromadb:
                condition: service_started
              searxng:
                condition: service_healthy
            restart: unless-stopped

          chromadb:
            image: chromadb/chroma:latest
            volumes:
              - ${cfg.dataDir}/chromadb:/chroma/chroma
            environment:
              ANONYMIZED_TELEMETRY: "false"
            restart: unless-stopped

          searxng:
            image: searxng/searxng:2026.5.31
            volumes:
              - ${cfg.dataDir}/searxng:/etc/searxng
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/healthz"]
              interval: 5s
              timeout: 3s
              retries: 20
      '';
    in
    {
      virtualisation.docker.enable = lib.mkDefault true;

      systemd.services.odysseus = {
        description = "Odysseus AI workspace (Docker Compose stack)";
        wantedBy    = [ "multi-user.target" ];
        requires    = [ "docker.service" ];
        after       = [ "docker.service" "network-online.target" ];

        preStart = ''
          mkdir -p ${cfg.dataDir}/{data,logs,chromadb,searxng,src}

          if [ ! -d ${cfg.dataDir}/src/.git ]; then
            ${pkgs.git}/bin/git clone --depth 1 \
              https://github.com/pewdiepie-archdaemon/odysseus.git \
              ${cfg.dataDir}/src
          fi

          if [ ! -f ${cfg.dataDir}/searxng/settings.yml ]; then
            SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)
            {
              echo "use_default_settings: true"
              echo "server:"
              echo "  secret_key: \"$SECRET\""
              echo "  limiter: false"
              echo "search:"
              echo "  formats:"
              echo "    - html"
              echo "    - json"
            } > ${cfg.dataDir}/searxng/settings.yml
          fi
        '';

        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
          ExecStart       = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} -p odysseus up -d --build";
          ExecStop        = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} -p odysseus down";
          TimeoutStartSec = 600;
        };
      };

      networking.firewall.allowedTCPPorts = [ cfg.port ];
    }
  );
}
