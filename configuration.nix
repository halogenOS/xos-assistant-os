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

  # Outbound is UNRESTRICTED (2026-08-24, operator's decision). The assistant
  # is gaining features that read the open web — a search result is any host,
  # and a page it opens is a host nobody can enumerate in advance — so an
  # egress allowlist cannot express what this machine legitimately reaches.
  #
  # What that gives up, stated rather than glossed: the allowlist was a
  # containment boundary. A compromised or prompt-injected assistant could
  # previously only talk to the Bot API, the model endpoint and a few lookup
  # hosts; now it can talk to anything. The inbound side is unchanged and is
  # what still protects the machine — nothing listens but ssh on 2222, and the
  # cloud firewall refuses the rest.
  #
  # The DNS-resolved nftables sets went with it: they existed only to fill
  # that allowlist, and resolving hosts hourly for a ruleset nothing consults
  # would be work with no reader.

  # 2223 (initrd sshd, LUKS passphrase) is deliberately absent: it only ever
  # listens in stage 1, where this firewall does not exist yet, and nothing
  # binds it in the main system.
  networking.firewall.allowedTCPPorts = [
    2222 # admin OpenSSH
  ];

  # The credential validator makes a real HTTPS request to the Bot API. With
  # egress unrestricted there is no resolved ruleset for it to wait on, so the
  # ordering that existed for that reason is gone with it.
}
