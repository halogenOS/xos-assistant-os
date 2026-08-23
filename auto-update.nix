# Pull-based self-updating: a timer polls this repository's own git host
# and rebuilds the running system from whatever its branch head is, so a
# commit here is a deployment — no push channel, no inbound access, which
# is the machine's whole design (nothing listens but sshd).
#
# Trade-offs, decided with the design (2026-08-23):
#
# - Pull over push: a push channel needs an inbound door or a deploy
#   credential held off-box; polling needs neither, at the price of up to
#   one interval of latency and a small periodic eval cost. The head
#   revision is compared over `git ls-remote` first, so an unchanged branch
#   costs one HTTPS request and no evaluation.
# - The repository is the deploy authority: whoever can push to the branch
#   operates the machine. That is already true of any config repo; polling
#   merely makes it immediate, and the repo host's access control is the
#   control point.
# - A broken commit fails the switch, not the machine: the running
#   generation keeps serving, the failure is in the journal, the head
#   revision is not recorded, and every following tick retries — the fix is
#   a new commit (or a revert). The timer interval is the retry backoff.
# - The rebuild happens on the box, so the box needs the build-world hosts
#   in its egress list (configuration.nix names them) and spends its own
#   CPU on evaluation. An off-box builder would spare that at the cost of a
#   push channel — rejected with it.
# - The switch is pinned to the revision that was compared, so what the
#   state file records is exactly what was applied, and a push racing the
#   poll is picked up whole on the next tick.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.autoUpdate;

  selfUpdate = pkgs.writeShellApplication {
    name = "xos-assistant-self-update";
    runtimeInputs = [
      pkgs.git
      pkgs.nixos-rebuild
      config.nix.package
    ];
    text = ''
      state=/var/lib/xos-assistant-auto-update/last-applied

      rev=$(git ls-remote ${lib.escapeShellArg cfg.repoUrl} \
        ${lib.escapeShellArg "refs/heads/${cfg.branch}"} | cut -f1)
      if [ -z "$rev" ]; then
        echo "the branch head could not be resolved; keeping the running system" >&2
        exit 1
      fi

      if [ -f "$state" ] && [ "$(cat "$state")" = "$rev" ]; then
        echo "already at $rev; nothing to do"
        exit 0
      fi

      echo "switching to $rev"
      nixos-rebuild switch --refresh \
        --flake ${lib.escapeShellArg "git+${cfg.repoUrl}?ref=${cfg.branch}&rev="}"$rev"${lib.escapeShellArg "#${config.networking.hostName}"}

      echo "$rev" >"$state"
    '';
  };
in
{
  options.custom.autoUpdate = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the host rebuilds itself from the repository's branch head.";
    };

    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/halogenOS/xos-assistant-os";
      description = ''
        This repository's clone URL — the host the updater polls. Must be
        reachable through the egress list in configuration.nix.
      '';
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "The branch whose head the host follows.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "How long after one poll finishes the next one starts.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.auto-update = {
      description = "Rebuild the system from the configuration repository";
      # A switch mid-collection would restart units under the operator's
      # feet; wait until the boot's secrets are in.
      after = [
        "network-online.target"
        "operator-secrets.service"
      ];
      wants = [ "network-online.target" ];
      # The switch this unit runs may change this very unit; restarting it
      # would kill the activation it is executing. Same precaution as
      # nixpkgs' own auto-upgrade service.
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe selfUpdate;
        StateDirectory = "xos-assistant-auto-update";
        StandardOutput = "journal";
        StandardError = "journal";
        # Evaluation and download can take a while on a small box; a hung
        # update must still not block the next tick forever.
        TimeoutStartSec = "45min";
      };
    };

    systemd.timers.auto-update = {
      description = "Periodic pull of the configuration repository";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitInactiveSec = cfg.interval;
        RandomizedDelaySec = "2min";
        Unit = "auto-update.service";
      };
    };
  };
}
