#!/bin/bash
# positron_userd.sbatch — a Slurm job that runs your own SSH server on a compute
# node, so Positron can connect to that node.
#
# Set up once with setup_userd.sh, which installs this file as
#   ~/.ssh/userd/positron_userd.sbatch
#
# Start a session (on the cluster):
#   cd ~/.ssh/userd/logs && sbatch ../positron_userd.sbatch
# or from your laptop:
#   remote/positron-compute start
#
# The resources below are the defaults. Change them here, or per session on the
# command line, which overrides these lines:
#   sbatch -p long -c 8 --mem=64G -t 2-00:00:00 ../positron_userd.sbatch
#
# The session lasts as long as this job: when the job ends (time limit or
# scancel), the server stops and Positron is disconnected.
# ---------------------------------------------------------------------------
#SBATCH --job-name=positron
#SBATCH --partition=short          # BMRC partition; use one that exists on your cluster
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=08:00:00            # hours:minutes:seconds (or days-hours:minutes:seconds)
#SBATCH --output=positron_%j.log   # %j = job ID; relative to the folder you submit from

set -uo pipefail

USERD_DIR="$HOME/.ssh/userd"
CONFIG="$USERD_DIR/sshd_config"
NODE_FILE="$USERD_DIR/current_node"
JOB_ID="${SLURM_JOB_ID:-manual}"
PID_FILE="$USERD_DIR/sshd.$JOB_ID.pid"
SSHD="${SSHD:-$(command -v sshd 2>/dev/null || echo /usr/sbin/sshd)}"
NODE="$(hostname -s)"

say() { echo "[$(date '+%F %T')] $*"; }
die() { say "ERROR: $*" >&2; exit 1; }

[[ -f "$CONFIG" ]] || die "$CONFIG not found. Run setup_userd.sh once first."
[[ -x "$SSHD" ]]   || die "sshd not found at $SSHD."

# A port is "in use" if something already answers on it.
port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# Remove the "where am I" file when the job ends, but only if it still points
# here (a newer job may have replaced it).
SSHD_PID=""
ENTRY=""
cleanup() {
    [[ -n "$SSHD_PID" ]] && kill "$SSHD_PID" 2>/dev/null
    if [[ -n "$ENTRY" && "$(cat "$NODE_FILE" 2>/dev/null)" == "$ENTRY" ]]; then
        rm -f "$NODE_FILE"
    fi
    rm -f "$PID_FILE"
    say "Server stopped; job ending."
}
trap cleanup EXIT
# scancel and the time limit send SIGTERM; exit cleanly so cleanup runs.
trap 'say "Received stop signal."; exit 0' TERM INT HUP

# Start the server on a random free high port. Retry a few times in case the
# port is taken in the moment between checking and starting.
PORT=""
for attempt in 1 2 3 4 5; do
    candidate=$(shuf -i 20000-60000 -n 1)
    port_in_use "$candidate" && continue
    "$SSHD" -D -e -f "$CONFIG" -p "$candidate" -o "PidFile=$PID_FILE" &
    SSHD_PID=$!
    sleep 2
    if kill -0 "$SSHD_PID" 2>/dev/null; then
        PORT=$candidate
        break
    fi
    say "sshd did not start on port $candidate (attempt $attempt); trying another."
    SSHD_PID=""
done
[[ -n "$PORT" ]] || die "Could not start sshd. See the messages above."

# Tell the laptop where the server is: one line, "<node> <port>". The home
# folder is shared, so the login node can read this file.
ENTRY="$NODE $PORT"
if [[ -f "$NODE_FILE" ]]; then
    say "Note: replacing an older entry ($(cat "$NODE_FILE")). Only one session can be reached at a time."
fi
echo "$ENTRY" > "$NODE_FILE.tmp.$JOB_ID" && mv "$NODE_FILE.tmp.$JOB_ID" "$NODE_FILE"

say "Server running: node $NODE, port $PORT, job $JOB_ID"
say "Resources: ${SLURM_CPUS_PER_TASK:-?} CPUs, ${SLURM_MEM_PER_NODE:-?} MB memory, partition ${SLURM_JOB_PARTITION:-?}"
say "Connect from Positron: Remote Explorer -> your compute host (e.g. bmrc_compute) -> Connect"
say "End the session with: scancel $JOB_ID"

# Keep the job alive for as long as the server runs.
wait "$SSHD_PID"
say "sshd exited (status $?)."
