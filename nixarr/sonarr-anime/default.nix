{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixarr.sonarr-anime;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
in
{
  options.nixarr.sonarr-anime = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Sonarr-Anime service.
      '';
    };

    package = mkPackageOption pkgs "sonarr" { };

    port = mkOption {
      type = types.port;
      default = 8990;
      description = "Port for Radarr Anime to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/sonarr-anime";
      defaultText = literalExpression ''"''${nixarr.stateDir}/sonarr-anime"'';
      example = "/nixarr/.state/sonarr-anime";
      description = ''
        The location of the state directory for the Sonarr-Anime service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/sonarr-anime
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.sonarr-anime.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Sonarr-Anime";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Sonarr-Anime traffic through the VPN.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.sonarr-anime.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${globals.sonarr-anime.group}.gid = globals.gids.${globals.sonarr-anime.group};
      users.${globals.sonarr-anime.user} = {
        isSystemUser = true;
        group = globals.sonarr-anime.group;
        uid = globals.uids.${globals.sonarr-anime.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${nixarr.mediaDir}/library'        0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/shows'  0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${cfg.stateDir}'                   0700 ${globals.sonarr-anime.user} ${globals.sonarr-anime.group} - -"
    ];

    systemd.services.sonarr-anime = {
      description = "Sonarr-Anime";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        SONARR__SERVER__PORT = "${builtins.toString cfg.port}";
      };

      serviceConfig = {
        Type = "simple";
        User = globals.sonarr-anime.user;
        Group = globals.sonarr-anime.group;
        ExecStart = "${(lib.getExe cfg.package)} -nobrowser -data=${cfg.stateDir}";
        Restart = "on-failure";
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.sonarr-anime.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # Port mappings
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString cfg.port}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.port;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString cfg.port}";
        };
      };
    };
  };
}
