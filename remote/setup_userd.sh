#!/usr/bin/env bash
# setup_userd.sh — one-time setup for running Positron on a compute node.
#
# Run this ON THE CLUSTER (on the login node), once. It is safe to run again:
# it keeps your existing host key and only rewrites the config.
#
# What it does:
#   1. Creates ~/.ssh/userd/, the folder that holds everything for your own
#      private SSH server ("userd" = user daemon).
#   2. Creates that server's identity (its "host key"). The same key is used on
#      every node, so your laptop recognises the server wherever the job lands.
#   3. Writes the server's settings (sshd_config): key login only, only you.
#   4. Installs the Slurm job script (positron_userd.sbatch) next to them.
#   5. Checks that the settings are valid and that your laptop's key is allowed.
#
# Usage (on the cluster):
#   bash setup_userd.sh
# Or from your laptop, which copies the files over and runs this for you:
#   remote/positron-compute setup
# ---------------------------------------------------------------------------

set -euo pipefail

USERD_DIR="$HOME/.ssh/userd"
HOST_KEY="$USERD_DIR/ssh_host_ed25519_key"
CONFIG="$USERD_DIR/sshd_config"
JOB_SCRIPT_NAME="positron_userd.sbatch"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME="$(id -un)"

# The SSH server program. It is installed on almost every Linux machine, but
# isn't always on a normal user's PATH.
SSHD="${SSHD:-$(command -v sshd 2>/dev/null || echo /usr/sbin/sshd)}"
if [[ ! -x "$SSHD" ]]; then
    echo "ERROR: sshd not found (looked on PATH and at /usr/sbin/sshd)." >&2
    echo "       Find it with 'ls /usr/sbin/sshd /usr/local/sbin/sshd', then run:" >&2
    echo "       SSHD=/path/to/sshd bash $0" >&2
    exit 1
fi

echo "[1/5] Folder: $USERD_DIR"
mkdir -p "$USERD_DIR/logs"
chmod 700 "$HOME/.ssh" "$USERD_DIR"

echo "[2/5] Host key"
if [[ -f "$HOST_KEY" ]]; then
    echo "      exists, keeping it (a new one would make your laptop warn that the host changed)"
else
    ssh-keygen -q -t ed25519 -N "" -C "positron-userd host key for $ME" -f "$HOST_KEY"
    echo "      created"
fi
chmod 600 "$HOST_KEY"

echo "[3/5] Server settings: $CONFIG"
cat > "$CONFIG" << EOF
# Settings for your private SSH server, started by $JOB_SCRIPT_NAME inside a Slurm job.
# Written by setup_userd.sh; running it again overwrites this file.
# The port and the PID file are given on the command line by the job script,
# because they differ for every job.

# The server's identity. Same key on every node, so your laptop recognises it.
HostKey $HOST_KEY

# Who may log in, and how: only you, only with an SSH key from authorized_keys.
AllowUsers $ME
AuthorizedKeysFile $HOME/.ssh/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
HostbasedAuthentication no
PermitRootLogin no

# PAM is the system's login machinery. It needs root, and a server run by a
# normal user can't use it.
UsePAM no

# What Positron needs: file transfer (sftp) and port forwarding.
Subsystem sftp internal-sftp
AllowTcpForwarding yes
X11Forwarding no
AllowAgentForwarding no
PrintMotd no
LogLevel INFO
EOF
chmod 600 "$CONFIG"

echo "[4/5] Job script"
if [[ -f "$HERE/$JOB_SCRIPT_NAME" ]]; then
    if [[ "$HERE" != "$USERD_DIR" ]]; then
        cp "$HERE/$JOB_SCRIPT_NAME" "$USERD_DIR/$JOB_SCRIPT_NAME"
    fi
    chmod 700 "$USERD_DIR/$JOB_SCRIPT_NAME"
    echo "      installed at $USERD_DIR/$JOB_SCRIPT_NAME"
else
    echo "      WARNING: $JOB_SCRIPT_NAME not found next to this script; copy it to $USERD_DIR/ yourself."
fi

echo "[5/5] Checks"
# sshd -t only reads and checks the settings; it doesn't start a server.
if "$SSHD" -t -f "$CONFIG" -o "PidFile=$USERD_DIR/check.pid"; then
    echo "      settings are valid ($("$SSHD" -V 2>&1 | head -1 || true))"
else
    echo "ERROR: sshd rejected the settings above." >&2
    exit 1
fi

AK="$HOME/.ssh/authorized_keys"
if [[ -s "$AK" ]]; then
    echo "      $(grep -c -v -e '^#' -e '^$' "$AK") key(s) allowed in $AK"
    chmod 600 "$AK"
else
    echo "      WARNING: $AK is missing or empty, so nobody can log in to the server."
    echo "               From your laptop: ssh-copy-id -i ~/.ssh/id_ed25519.pub <login-host>"
fi
# sshd refuses keys if the home folder can be written by others (StrictModes).
if [[ -n "$(find "$HOME" -maxdepth 0 -perm /022 2>/dev/null)" ]]; then
    echo "      WARNING: your home folder is writable by others; sshd will refuse your key."
    echo "               Fix with: chmod go-w \"\$HOME\""
fi

echo ""
echo "Done. Start a session with:  sbatch ~/.ssh/userd/$JOB_SCRIPT_NAME"
echo "(or from your laptop:        remote/positron-compute start)"
