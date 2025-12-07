{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixarr.radarr-anime;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
in
{
  options.nixarr.radarr-anime = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Radarr Anime service.
      '';
    };

    package = mkPackageOption pkgs "radarr" { };

    port = mkOption {
      type = types.port;
      default = 7879;
      description = "Port for Radarr Anime to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/radarr-anime";
      defaultText = literalExpression ''"''${nixarr.stateDir}/radarr-anime"'';
      example = "/nixarr/.state/radarr-anime";
      description = ''
        The location of the state directory for the Radarr Anime service.
        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/radarr-anime
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.radarr-anime.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Radarr Anime";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)
        Route Radarr Anime traffic through the VPN.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.radarr-anime.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${nixarr.mediaDir}/library'        0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/movies' 0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];
    systemd.tmpfiles.settings."10-radarr".${cfg.stateDir}.d = {
      inherit (globals.radarr-anime) user group;
      mode = "0700";
    };

    users = {
      groups.${globals.radarr-anime.group}.gid = globals.gids.${globals.radarr-anime.group};
      users.${globals.radarr-anime.user} = {
        isSystemUser = true;
        group = globals.radarr-anime.group;
        uid = globals.uids.${globals.radarr-anime.user};
      };
    };

    systemd.services.radarr-anime = {
      description = "Radarr Anime";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        RADARR__SERVER__PORT = "${builtins.toString cfg.port}";
      };

      serviceConfig = {
        Type = "simple";
        User = globals.radarr-anime.user;
        Group = globals.radarr-anime.group;
        ExecStart = "${(lib.getExe cfg.package)} -nobrowser -data=${cfg.stateDir}";
        Restart = "on-failure";
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.radarr-anime.vpnConfinement = mkIf cfg.vpn.enable {
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
