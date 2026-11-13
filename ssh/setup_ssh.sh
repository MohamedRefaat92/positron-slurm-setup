#!/usr/bin/env bash
# setup_ssh.sh: make an SSH key, put it on the cluster, and add the hosts to ~/.ssh/config.
# Edit the three values below first, then run:  ./ssh/setup_ssh.sh
set -euo pipefail

BMRC_USER="YOUR_BMRC_USERNAME"        # e.g. abc123
LUDWIG_USER="YOUR_LUDWIG_USERNAME"    # delete the Ludwig lines below if you don't use it
LUDWIG_HOST="YOUR_LUDWIG_HOST"

KEY="$HOME/.ssh/id_ed25519"
CONFIG="$HOME/.ssh/config"

if [[ "$BMRC_USER $LUDWIG_USER $LUDWIG_HOST" == *YOUR_* ]]; then
    echo "Edit the usernames at the top of $0 first." >&2
    exit 1
fi

# 1. Key pair (skipped if you already have one)
[[ -f "$KEY" ]] || ssh-keygen -t ed25519 -f "$KEY" -N ""

# 2. Copy the public key to each cluster (asks for your password / 2FA once)
ssh-copy-id -i "$KEY.pub" "$BMRC_USER@cluster1.bmrc.ox.ac.uk"
ssh-copy-id -i "$KEY.pub" "$LUDWIG_USER@$LUDWIG_HOST"

# 3. Add the hosts to ~/.ssh/config (once; a backup is kept)
if grep -q "positron-slurm-setup" "$CONFIG" 2>/dev/null; then
    echo "$CONFIG already has the hosts; not changed."
    exit 0
fi
[[ -f "$CONFIG" ]] && cp "$CONFIG" "$CONFIG.bak"
cat >> "$CONFIG" << EOF

# === positron-slurm-setup ===
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    AddKeysToAgent yes
    IgnoreUnknown UseKeychain
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

Host bmrc_cluster
    HostName cluster1.bmrc.ox.ac.uk
    User $BMRC_USER
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist yes

Host bmrc_compute
    User $BMRC_USER
    HostKeyAlias bmrc_compute
    ProxyCommand bash -c 'read n p < <(ssh -n bmrc_cluster cat .ssh/userd/current_node); exec ssh -W \$n:\$p bmrc_cluster'

Host ludwig_cluster
    HostName $LUDWIG_HOST
    User $LUDWIG_USER
# === end positron-slurm-setup ===
EOF
echo "Added bmrc_cluster, bmrc_compute and ludwig_cluster to ~/.ssh/config."
echo "Next: run  ssh bmrc_cluster  in a terminal (2FA), then connect from Positron."
