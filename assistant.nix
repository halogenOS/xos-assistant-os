# The halogenOS group assistant as a system service.
#
# The bot is one Rust binary taking one argument, the path of a TOML
# configuration file. Everything the file names is rendered here from the
# module's values into the nix store — safe there by construction, because
# the file carries secret *indirections* (environment variable names), never
# values. The two credentials come from foundrix's operator-secrets
# collector as an env file the service reads with EnvironmentFile=, so the
# boot blocks until a human has carried them in and the Bot API has
# confirmed the token.
#
# The machine serves no inbound HTTP: the adapter long-polls the Bot API,
# so the service is outbound-only and every host it may reach is named in
# configuration.nix's egress list.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.custom.assistant;

  # The assistant's workspace names the ledger framework by a relative path
  # one directory above its own root (its decision 0004: the framework has
  # no public home yet, the two ship as sibling checkouts). Compose exactly
  # that layout from the two flake inputs, then build the workspace out of
  # its subdirectory — the path dependencies resolve inside the composed
  # tree, and the assistant's own Cargo.lock covers both.
  workspace = pkgs.runCommand "assistant-workspace" { } ''
    mkdir -p "$out"
    cp -r --no-preserve=mode ${inputs.assistant-src} "$out"/halogenos-assistant
    cp -r --no-preserve=mode ${inputs.agent-ledger-src} "$out"/agent-ledger
  '';

  assistant = pkgs.rustPlatform.buildRustPackage {
    pname = "halogenos-assistant";
    version = "0.1.0";

    src = workspace;
    sourceRoot = "${workspace.name}/halogenos-assistant";
    cargoLock.lockFile = "${inputs.assistant-src}/Cargo.lock";

    # The source repository's own workflow proves the suite green before a
    # commit reaches its main branch; re-running it on every image build and
    # every self-update cycle would double the cost of each deployment for
    # a result already on the record there.
    doCheck = false;

    meta = {
      description = "halogenOS community assistant";
      mainProgram = "assistant";
      license = lib.licenses.gpl3Only;
    };
  };

  # TOML string literals, produced by the JSON encoder: a JSON string is a
  # valid TOML basic string, escapes included, so no hand-rolled quoting.
  tomlString = builtins.toJSON;

  # The rendered process configuration. Store and adapter state live under
  # the service's StateDirectory; the system prompt is read straight out of
  # the source input, so prompt changes deploy with the bot revision. Log
  # lines go to stderr, which the unit routes into the journal.
  configFile = pkgs.writeText "assistant.toml" ''
    store_path = "/var/lib/assistant/assistant.db"
    telegram_state_path = "/var/lib/assistant/telegram.offset"
    prompt_dir = ${tomlString "${inputs.assistant-src}/prompts"}
    log = "stderr"
    model = ${tomlString cfg.model}
    direct_chats = ${tomlString cfg.directChats}
    ${lib.optionalString (cfg.privacyPolicy != null) ''
      privacy_policy = ${tomlString cfg.privacyPolicy}
    ''}
    ${lib.optionalString (cfg.moderationHandle != null) ''
      moderation_handle = ${tomlString cfg.moderationHandle}
    ''}
    [endpoints]
    openrouter = ${tomlString cfg.modelEndpoint}

    [operators]
    telegram = ${tomlString cfg.telegramOperator}

    [secrets.bot_token]
    env = "BOT_TOKEN"

    [secrets.openrouter_key]
    env = "OPENROUTER_KEY"
  '';

  # The credential validator for the operator-secrets collector. The
  # mechanism's docs prefer a compiled binary over a shell script so no
  # value passes through a shell; this deployment accepts the script with
  # the same property held by hand: the token reaches curl as a config file
  # on stdin (printf is a shell builtin), so no process ever carries it in
  # its arguments, where /proc would expose it.
  #
  # Verdicts per the collector's stdio protocol: HTTP 200 from getMe proves
  # the token (`valid`), 401/404 disproves it (`invalid`), anything else —
  # including an unreachable Bot API — is `error`, which blocks and retries
  # instead of discarding a stored credential. The model key has no cheap
  # external proof, so it is accepted on presence alone.
  credentialsValidator = pkgs.writeShellApplication {
    name = "assistant-credentials-validator";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      emit() {
        jq -cn --arg status "$1" --arg message "$2" '{status: $status, message: $message}'
      }

      payload=$(cat)
      bot_token=$(jq -r '.fields.BOT_TOKEN // empty' <<<"$payload")
      openrouter_key=$(jq -r '.fields.OPENROUTER_KEY // empty' <<<"$payload")

      if [ -z "$bot_token" ]; then
        emit invalid "BOT_TOKEN is empty"
        exit 0
      fi
      if [ -z "$openrouter_key" ]; then
        emit invalid "OPENROUTER_KEY is empty"
        exit 0
      fi

      if ! response=$(printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$bot_token" \
        | curl --config - --silent --max-time 30 --output /dev/null --write-out '%{http_code}'); then
        emit error "the Bot API could not be reached"
        exit 0
      fi

      case "$response" in
        200) emit valid "the Bot API confirms the token" ;;
        401 | 404) emit invalid "the Bot API rejects the token" ;;
        *) emit error "unexpected Bot API status $response" ;;
      esac
    '';
  };
in
{
  options.custom.assistant = {
    telegramOperator = lib.mkOption {
      type = lib.types.str;
      description = ''
        The numeric Telegram user id of the one account whose group
        invitations the assistant accepts. Every other group add is refused
        and the assistant leaves the group; the placeholder "0" in the
        environment files matches no real account, so a host deployed
        before the value is set refuses every group safely.
      '';
    };

    privacyPolicy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The address the /privacy command answers with. Null leaves the key
        out, under which the bot answers its fixed not-yet-published line.
      '';
    };

    moderationHandle = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The moderation bot's handle the report tool files toward. Null
        leaves the key out, under which the report tool is not registered.
      '';
    };

    directChats = lib.mkOption {
      type = lib.types.enum [
        "on"
        "off"
      ];
      # Off until the deployment's direct-chat feature set ships — the
      # bot's own configuration doc names this as the deployment stance.
      default = "off";
      description = "Whether direct chats are served.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "vertex/gemini-3.7-flash@eu";
      description = ''
        The endpoint's identifier for the model, EU-pinned so conversation
        content stays in the EU.
      '';
    };

    modelEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://router.eu.requesty.ai/v1";
      description = ''
        The OpenRouter-compatible base URL the bot answers through — the
        Requesty EU router. A change here must be mirrored in the egress
        list in configuration.nix, which names the router's host.
      '';
    };

    credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/credentials/assistant.env";
      description = ''
        The env file holding BOT_TOKEN and OPENROUTER_KEY, written by the
        operator-secrets collector and read by the service. Rests on /var,
        which devices/hetzner puts on LUKS.
      '';
    };
  };

  config = {
    users.users.assistant = {
      isSystemUser = true;
      group = "assistant";
      home = "/var/lib/assistant";
    };
    users.groups.assistant = { };

    # The two credentials a human carries in at first boot: the collector
    # parks the boot, an operator answers over SSH (or the console), the
    # Bot API proves the token, and only then may the service start.
    # requiredBy installs Requires=/After= on the service, so an absent
    # credential blocks loudly instead of leaving the unit not started.
    foundrix.services.operator-secrets.secrets.assistant = {
      description = "Telegram bot token and model API key for the assistant";
      fields = {
        BOT_TOKEN = {
          description = "Telegram bot token (from @BotFather)";
          order = 10;
          sensitive = true;
        };
        OPENROUTER_KEY = {
          description = "API key for the configured model endpoint";
          order = 20;
          sensitive = true;
        };
      };
      validateCommand = [ (lib.getExe credentialsValidator) ];
      path = cfg.credentialsFile;
      owner = "assistant";
      mode = "0400";
      requiredBy = [ "assistant.service" ];
    };

    systemd.services.assistant = {
      description = "halogenOS group assistant";
      wantedBy = [ "multi-user.target" ];
      # The bot's first long poll goes out immediately, and its hosts are
      # admitted by resolved nftables entries — order behind the base
      # ruleset and the first resolution run, or the initial requests are
      # dropped until the resolver timer fires.
      after = [
        "network-online.target"
        "nftables.service"
        "nftables-dns-update.service"
      ];
      wants = [
        "network-online.target"
        "nftables-dns-update.service"
      ];

      serviceConfig = {
        Type = "simple";
        # A dedicated static user, not DynamicUser: the store under
        # StateDirectory and the credential file's ownership must survive
        # reboots with stable identity.
        User = "assistant";
        Group = "assistant";
        StateDirectory = "assistant";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/assistant";
        ExecStart = "${lib.getExe assistant} ${configFile}";
        EnvironmentFile = [ cfg.credentialsFile ];
        Restart = "on-failure";
        RestartSec = 10;
        # The binary stops cleanly on SIGTERM, systemd's default stop
        # signal.

        # Sandboxing, per the hardening set the framework's services use.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX" # nss lookups through resolved's socket
        ];
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        UMask = "0077";
      };
    };
  };
}
