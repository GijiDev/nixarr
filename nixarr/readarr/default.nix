{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.readarr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  port = 8787;
in {
  options.nixarr.readarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Readarr service.
      '';
    };

    package = mkPackageOption pkgs "readarr" {};

    port = mkOption {
      type = types.port;
      default = port;
      description = "Port for Readarr to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/readarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/readarr"'';
      example = "/nixarr/.state/readarr";
      description = ''
        The location of the state directory for the Readarr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/readarr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.readarr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Readarr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Readarr traffic through the VPN.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.readarr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${globals.readarr.group}.gid = globals.gids.${globals.readarr.group};
      users.${globals.readarr.user} = {
        isSystemUser = true;
        group = globals.readarr.group;
        uid = globals.uids.${globals.readarr.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${globals.readarr.user} root - -"

      "d '${nixarr.mediaDir}/library'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/books' 0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    systemd.services.readarr = {
      description = "Readarr";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      environment.READARR__SERVER__PORT = builtins.toString cfg.port;

      serviceConfig = {
        Type = "simple";
        User = globals.readarr.user;
        Group = globals.readarr.group;
        ExecStart = "${lib.getExe cfg.package} -nobrowser -data=${cfg.stateDir}";
        Restart = "on-failure";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.readarr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

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
