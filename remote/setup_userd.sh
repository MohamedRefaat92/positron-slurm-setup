#!/bin/bash
# One-time setup, run on the cluster: a host key and settings for your own SSH server.
# Usage: bash setup_userd.sh
set -e
D="$HOME/.ssh/userd"
mkdir -p "$D" && chmod 700 "$HOME/.ssh" "$D"

# The server's identity. Made once and reused on every node.
[ -f "$D/ssh_host_ed25519_key" ] || ssh-keygen -q -t ed25519 -N "" -f "$D/ssh_host_ed25519_key"

# Only you, only with your SSH key.
cat > "$D/sshd_config" << EOF
HostKey $D/ssh_host_ed25519_key
PidFile $D/sshd.pid
AuthorizedKeysFile $HOME/.ssh/authorized_keys
AllowUsers $USER
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no
Subsystem sftp internal-sftp
AllowTcpForwarding yes
X11Forwarding no
EOF

echo "Done. Files are in $D"
