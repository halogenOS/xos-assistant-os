# xos-assistant-os

The deployment configuration for the halogenOS community assistant: one
NixOS image per environment (`xos-assistant-int` and `xos-assistant-prod`),
built on the foundrix framework and run on Hetzner Cloud. The assistant
itself lives in the xos-assistant repository; this repository builds it
from source and wraps it in a machine.

## Initial deployment

Build the image for the environment (quoting matters, the target name
carries `/` and `:`):

    nix build 'path:.#packages.x86_64-linux."xos-assistant-int/image:x86_64"'

Upload the artifact as a Hetzner snapshot with `hcloud-upload-image`
(`HCLOUD_TOKEN` in the environment), then create the server from that
snapshot with one Cloud Volume attached — the volume becomes the encrypted
`/var` holding the store and the credentials.

First boot blocks twice, by design: for the disk passphrase over the initrd
ssh, and then for the two operator secrets. Fill the secrets with
`operator-secrets-tui` over ssh — the Telegram bot token (validated at
entry) and the model endpoint key. Both land on the encrypted volume; later
boots validate the stored file.

Set the real operator id (and, when decided, the privacy policy address and
moderation handle) in the environment file before inviting the bot anywhere;
the committed placeholders refuse every group add.

## Updates

The machine updates itself. A timer polls this repository's main branch and
runs `nixos-rebuild switch` pinned to the new head on a change:

- A config change is a commit here; every host rebuilds within the interval.
- A new bot revision is moving the `rev` pin on the source input and
  committing.
- A broken commit fails the switch and changes nothing; the running
  generation keeps serving, and reverting the commit reverts the fleet.

## Secrets

No secret lives in this repository. The configuration carries indirections
only — the names of environment variables the service reads from a file
written by the operator-secrets collector at first boot. Rotate with
`operator-secrets-tui --edit`, then restart the service.
