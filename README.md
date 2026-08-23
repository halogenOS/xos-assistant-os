# xos-assistant-os

The deployment configuration for the halogenOS community assistant: one
NixOS image per environment (`xos-assistant-int` and `xos-assistant-prod`),
built on the foundrix framework and run on Hetzner Cloud. The assistant
itself lives in the xos-assistant repository; this repository builds it
from source and wraps it in a machine.

The machine accepts no inbound service traffic. The bot long-polls the
Telegram Bot API, answers through an EU model endpoint, and reads the
project's forge, release mirror and wiki — all outbound. The only listeners
are the admin sshd on 2222 and, during early boot, the initrd sshd on 2223
for the disk passphrase. Outbound traffic is default-deny with every
permitted host named in the configuration; anything not on that list does
not leave the machine.

## Initial deployment

Build the image for the environment (quoting matters, the target name
carries `/` and `:`):

    nix build 'path:.#packages.x86_64-linux."xos-assistant-int/image:x86_64"'

Upload the resulting artifact as a Hetzner snapshot:

    export HCLOUD_TOKEN="<project API token>"
    hcloud-upload-image upload \
      --image-path result/*.raw.zst \
      --architecture x86 \
      --compression zstd \
      --description "xos-assistant-int"

Create the server from that snapshot with one Cloud Volume attached — the
volume becomes the encrypted `/var` holding the bot's store and the
credentials; the configuration finds it by the `scsi-0HC_Volume_*` disk id.
With the `hcloud` CLI:

    hcloud volume create --name xos-assistant-int-var --size 10 --location fsn1
    hcloud server create \
      --name xos-assistant-int \
      --type cx22 \
      --image <snapshot id from the upload> \
      --location fsn1 \
      --volume xos-assistant-int-var

First boot then blocks twice, by design:

1. **Disk passphrase (initrd, port 2223).** `ssh -p 2223 root@<address>`
   drops straight into the disk manager's prompt. The volume is blank, so
   the passphrase is asked twice and the volume is born encrypted. Every
   later boot asks once — an unattended reboot waits here until someone
   answers.
2. **Credentials (main system, port 2222).** The boot parks until the two
   operator-provided secrets exist. `ssh -p 2222 user@<address>`, run
   `operator-secrets-tui`, and answer: the Telegram bot token (proven
   immediately against the Bot API's `getMe` — a wrong token is refused at
   entry, an unreachable Bot API blocks and retries instead of rejecting)
   and the model endpoint's API key (accepted on presence). Both are
   written to the encrypted volume; later boots validate the stored file
   and only prompt again if it stopped validating.

After that the boot completes and `assistant.service` starts. Check it with
`journalctl -u assistant` — the startup line names every resolved path and
endpoint, never a secret.

Before the bot is useful, set the real operator id (and, when decided, the
privacy policy address and moderation handle) in the environment file — the
committed placeholders deliberately refuse every group add.

## Updates

The machine updates itself. A timer polls this repository's main branch
every 15 minutes, compares the branch head against the last applied
revision, and on a change runs `nixos-rebuild switch` pinned to the new
head. So:

- **Deploying a config change** is a commit to this repository. Within one
  interval every host has rebuilt itself; nothing is pushed to the boxes.
- **Deploying a new bot revision** is moving the `rev` pin on the
  `assistant-src` input (and `agent-ledger-src` when the framework moved),
  refreshing the lock, and committing.
- **A broken commit** fails the switch and changes nothing: the running
  generation keeps serving, the failure is in the journal
  (`journalctl -u auto-update`), and the fix is the next commit. Reverting
  the commit reverts the fleet.

The rebuild runs on the box, which is why the egress list carries the flake
input hosts and the binary cache alongside the bot's own hosts.

## Secrets

No secret exists in this repository, its history, or the nix store. The
configuration carries indirections only — the names of environment
variables the service reads from a file on the encrypted volume, owned by
the service user, mode 0400, written by the operator-secrets collector at
first boot. Rotating a
credential on a running host: `operator-secrets-tui --edit`, then restart
`assistant.service`.

## OPEN

- The `agent-ledger-src` input points at the framework's expected home
  beside the assistant's, which is not published yet. Until it exists,
  `nix flake lock` cannot pin it and the image cannot build; the lock file
  is committed with the first successful lock.
- The assistant and framework sources must be fetchable without
  credentials, by the image build and by every box's self-updater alike.
  If those repositories are private, either they become public or the
  fetch needs an access token on the box — an open decision, not made
  here.
