# positron-slurm-setup

Configuration and setup guides for running [Positron](https://positron.posit.co) on HPC clusters managed by SLURM.

---

## Sections

### 1. [`ssh/`](ssh/) — SSH configuration
Everything needed to connect Positron from your local machine to a remote cluster, including clusters with two-factor authentication.

- [`ssh/README.md`](ssh/README.md) — full guide
- [`ssh/ssh_config.template`](ssh/ssh_config.template) — drop-in `~/.ssh/config` template
- [`ssh/setup_ssh.sh`](ssh/setup_ssh.sh) — automated setup script

### 2. [`positron/`](positron/) — Positron settings and troubleshooting
Getting Positron to start the project's own R and Python, and kernels that start reliably on cluster storage.

- [`positron/README.md`](positron/README.md) — settings, interpreter discovery, "status code 500" kernel failures, slow startup, login-node memory
- [`positron/settings.user.jsonc`](positron/settings.user.jsonc) — user settings to merge into yours

### 3. [`remote/`](remote/) — Positron on a compute node
Why the login node isn't enough, how to tell whether your cluster lets you SSH into compute nodes, and the `userd` pattern (your own SSH server inside a Slurm job) for when it doesn't.

- [`remote/README.md`](remote/README.md) — guide and the requirements for the job script *(job script itself: coming soon)*

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

# 5. Raise the kernel connection timeout (cluster storage is slow)
#    Settings → kernelSupervisor.connectionTimeout → 120
```

For analysis, connect to a compute node rather than the login node: see [`remote/`](remote/README.md). If a kernel won't start, see [`positron/`](positron/README.md#4-a-kernel-wont-start-request-failed-with-status-code-500).
