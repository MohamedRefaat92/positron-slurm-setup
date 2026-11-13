#!/bin/bash
#SBATCH -J positron
#SBATCH -p short
#SBATCH -c 4
#SBATCH --mem=32G
#SBATCH -t 08:00:00
# Runs your own SSH server on a compute node so Positron can connect to it.
# Needs setup_userd.sh to have been run once.
# Change resources here, or when submitting: sbatch -c 8 --mem=64G -t 12:00:00 ...

D="$HOME/.ssh/userd"
PORT=$(shuf -i 20000-60000 -n 1)                # a random high port
echo "$(hostname -s) $PORT" > "$D/current_node"  # tell your laptop where the server is
trap 'rm -f "$D/current_node"' EXIT              # and forget it when the job ends
/usr/sbin/sshd -D -e -p "$PORT" -f "$D/sshd_config"
