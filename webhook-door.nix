# The public door for Telegram's webhook deliveries.
#
# Telegram pushes each update to https://xenia.halogenos.org the moment it
# exists — the delivery the operator chose on 2026-08-29 after three messages
# sat seven minutes in a silent long poll. Caddy terminates TLS with a
# Let's Encrypt certificate it acquires and renews itself (ACME retries until
# the DNS records exist, so this module is safe to ship ahead of them) and
# forwards exactly the webhook path to the assistant's loopback listener.
# The listener half lives in the assistant itself and arrives with its own
# release; until then the path answers 502, which carries nothing.
{ ... }:
let
  # The one hostname Telegram is registered against. The assistant's own
  # configuration names the same host in its webhook address; the two move
  # together or not at all.
  webhookHost = "xenia.halogenos.org";
  # The loopback port the assistant's webhook listener binds. This value is
  # the contract between this vhost and the assistant's configuration —
  # recorded here, consumed by both.
  webhookPort = 8085;
in
{
  services.caddy = {
    enable = true;
    virtualHosts.${webhookHost} = {
      extraConfig = ''
        # Only the webhook path reaches the assistant; every other request
        # to this host gets an empty 404, so the door describes nothing.
        handle /telegram/webhook {
          reverse_proxy 127.0.0.1:${toString webhookPort}
        }
        handle {
          respond 404
        }
      '';
    };
  };

  # 80 is ACME's HTTP challenge and Caddy's redirect; 443 is the door. The
  # Hetzner cloud firewall opened the same two on 2026-08-29.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
