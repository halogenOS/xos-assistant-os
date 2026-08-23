{
  applyHomeManagerShared,
  foundrixModules,
  modulesPath,
  lib,
  pkgs,
  config,
  ...
}:
let
  userName = "user";
in
{
  imports = [
    "${modulesPath}/profiles/minimal.nix"
    "${modulesPath}/profiles/perlless.nix"
    foundrixModules.profiles.server-baseline
    foundrixModules.config.home-manager
    foundrixModules.config.shell.zsh.lite
    foundrixModules.config.filesystem.var
    foundrixModules.services.secrets
    foundrixModules.services.operator-secrets
    foundrixModules.services.nftables-dns
    foundrixModules.config.networking.controlled-egress-firewall
    foundrixModules.config.networking.dns-resolvers
    ./assistant.nix
    ./auto-update.nix
  ];

  users.users.${userName} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    uid = 1000;
    shell = pkgs.zsh;
    hashedPassword = "$y$j9T$gV9uVMQ5oZ8mg4Opln0cz1$r2wok8rIwQm/7sdOEJT8QtKfCw.Jf3bHKHkZG6nF7c3";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK3LlSENwLSVob/uIKNoyjtSrffFs4lzNC9AMqxmEHSz simao@aludepp"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJfKqIYdQ+C/fWQic63h3XHSDuPcX10m22yewquDDix"
    ];
  };
  users.groups.${userName}.gid = config.users.users.${userName}.uid;

  # The initrd sshd is the remote channel for the /var LUKS passphrase
  # (devices/hetzner imports filesystem.var-luks). nixpkgs would default
  # these to root's keys, and root has none here — same operator, same key.
  boot.initrd.network.ssh.authorizedKeys = config.users.users.${userName}.openssh.authorizedKeys.keys;

  home-manager =
    applyHomeManagerShared {
      home.language = rec {
        base = "en_US.UTF-8";
        measurement = base;
        monetary = base;
        name = base;
        paper = base;
        time = base;
      };
      home.packages = with pkgs; [
        jq
        curl
        dig
        git
        tree
        bat
        fd
        file
        btop
        rsync
        vim
        fastfetch
        nftables
      ];
    }
    // {
      users.${userName}.home.stateVersion = "25.05";
    };

  environment.systemPackages = with pkgs; [
    conntrack-tools
  ];

  security.sudo.enable = true;

  services.openssh = {
    enable = true;
    # 2222 like the sibling infra hosts, so one operator habit covers the
    # fleet; nothing else listens on this machine.
    ports = [ 2222 ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  system.nixos-init.enable = true;
  boot.initrd.systemd.enable = true;

  system.etc.overlay.enable = true;
  services.userborn.enable = true;

  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  system.forbiddenDependenciesRegexes = lib.mkForce [ ];

  boot.uki.name = "xos-assistant";
  system.nixos.distroId = "xos-assistant";
  system.image.id = "xos-assistant-hetzner";
  system.image.version = "1";

  system.stateVersion = "25.05";

  # nameservers and FallbackDNS come from foundrix's dns-resolvers module
  services.resolved.settings.Resolve.DNSSEC = "false";

  # Dynamic DNS resolution for nftables. Two groups of hosts, and nothing
  # else leaves this machine:
  #
  # The assistant's outbound world — the Bot API, the model endpoint, and
  # the three lookup hosts (canonical forge, release mirror API, raw wiki
  # pages). The forge entry doubles as the self-updater's own repository
  # host.
  #
  # The self-updater's build world — the flake inputs (codeberg for
  # foundrix, github for nixpkgs/home-manager/nixos-hardware) and the
  # binary cache. api.github.com is shared with the release lookup.
  foundrix.services.nftables-dns = {
    enable = true;
    allowedConnections = [
      # assistant
      {
        host = "api.telegram.org";
        ports = [ 443 ];
      }
      {
        host = "router.eu.requesty.ai";
        ports = [ 443 ];
      }
      {
        host = "git.halogenos.org";
        ports = [ 443 ];
      }
      {
        host = "raw.githubusercontent.com";
        ports = [ 443 ];
      }
      {
        host = "api.github.com";
        ports = [ 443 ];
      }
      # self-updater
      {
        host = "cache.nixos.org";
        ports = [ 443 ];
      }
      {
        host = "codeberg.org";
        ports = [ 443 ];
      }
      {
        host = "github.com";
        ports = [ 443 ];
      }
      {
        host = "codeload.github.com";
        ports = [ 443 ];
      }
      # resolved's fallback servers
      {
        host = "cloudflare-dns.com";
        ports = [ 53 ];
        protocol = "udp";
      }
      {
        host = "dns.quad9.net";
        ports = [ 53 ];
        protocol = "udp";
      }
    ]
    ++ map (host: {
      inherit host;
      ports = [ 123 ];
      protocol = "udp";
    }) config.networking.timeServers;
    updateInterval = "1h";
  };

  # 2223 (initrd sshd, LUKS passphrase) is deliberately absent: it only ever
  # listens in stage 1, where this firewall does not exist yet, and nothing
  # binds it in the main system.
  networking.firewall.allowedTCPPorts = [
    2222 # admin OpenSSH
  ];

  foundrix.config.networking.controlled-egress-firewall = {
    enable = true;
    allowLinkLocalMetadata = true;
  };

  # The credential validator makes a real HTTPS request to the Bot API, and
  # that host is admitted by a resolved nftables entry, not a static rule:
  # both the base ruleset and the first resolution run must be in place
  # before the collector, or the validator's request is dropped and it
  # reports `error`.
  systemd.services.operator-secrets = {
    after = [
      "nftables.service"
      "nftables-dns-update.service"
    ];
    wants = [ "nftables-dns-update.service" ];
  };
}
