# positron-slurm-setup

Configuration and setup guides for running [Positron](https://positron.posit.co) on HPC clusters managed by SLURM.

---

## Sections

### 1. [`ssh/`](ssh/) — SSH configuration *(this section)*
Everything needed to connect Positron from your local machine to a remote cluster, including clusters with two-factor authentication.

- [`ssh/README.md`](ssh/README.md) — full guide
- [`ssh/ssh_config.template`](ssh/ssh_config.template) — drop-in `~/.ssh/config` template
- [`ssh/setup_ssh.sh`](ssh/setup_ssh.sh) — automated setup script

### 2. `positron/` — Positron settings *(coming soon)*
Optimal Positron settings for remote HPC work: interpreter configuration, R/Python environment detection, extension recommendations, and workspace settings.

### 3. `remote/` — Remote-side setup *(coming soon)*
SLURM job scripts and server-side configuration for running the Positron remote server on a compute node, including the `userd` pattern for connecting Positron directly to a compute node rather than the login node.

---

## Quick start

```bash
# 1. Generate SSH key and configure ~/.ssh/config
chmod +x ssh/setup_ssh.sh
./ssh/setup_ssh.sh

# 2. Enable native SSH transport in Positron
#    Settings → remoteSSH.transport → native

# 3. For 2FA clusters (e.g. BMRC): open a terminal first
ssh bmrc_cluster          # complete 2FA — this opens the shared socket

# 4. Connect from Positron
#    Remote Explorer → your cluster → Connect
```
