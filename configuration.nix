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
    ./webhook-door.nix
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

  # The assistant's character lives here rather than in the bot's own
  # repository (operator, 2026-08-24): a voice belongs to the deployment
  # wearing it, not to the shared source every deployment builds from.
  # Practically it also means changing how she speaks is a commit here and a
  # small rebuild, instead of a new bot revision and a full compile on the
  # machine. Both environments wear the same character, so it is set once.
  # Dates and clock in the group's own zone, so the assistant's date
  # marker and logs speak the members' time rather than UTC.
  time.timeZone = "Europe/Berlin";

  custom.assistant.persona = builtins.readFile ./persona.md;
  # glm-5.3-flash through sference, the EU-hosted provider on the same EU
  # router. Naming the provider pins the routing, so no region modifier —
  # the @eu form does not resolve for single-provider entries (tested
  # 2026-08-27). Swapped from vertex/gemini-3.7-flash@eu for cost and
  # capability.
  custom.assistant.model = "sference/glm-5.3-flash";
  # GLM-5.3-Flash serves a 1M-token window (1048576), as documented by the
  # model's provider listings; checked 2026-08-31.
  custom.assistant.contextWindow = 1048576;

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
