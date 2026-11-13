# SSH Setup for Positron on HPC Clusters

This covers everything needed to connect Positron (and VS Code) to remote HPC clusters, including clusters that require two-factor authentication (2FA) like BMRC.

---

## Why this is needed

Positron's Remote-SSH extension runs SSH with `-o BatchMode=yes`, which disables all interactive prompts. On clusters that require password + OTP / Duo 2FA, this causes the connection to be rejected immediately after authentication — even though the credentials are correct.

VS Code's Remote-SSH works because it uses the system OpenSSH binary, which can display prompts. Positron also supports native OpenSSH transport (`remoteSSH.transport: native` in settings), but even then it passes `BatchMode=yes`, so 2FA still fails.

**The solution** is SSH connection multiplexing (`ControlMaster`). You authenticate once in a terminal; every subsequent connection (Positron, VS Code, another terminal) reuses the same authenticated socket and skips authentication entirely.

---

## 1. Generate an SSH key pair

Skip this step if you already have `~/.ssh/id_ed25519`.

```bash
ssh-keygen -t ed25519 -C "you@yourmachine" -f ~/.ssh/id_ed25519
```

Ed25519 is preferred over RSA: shorter keys, faster, and equally supported on all modern systems.

After generating, add the key to your agent so you do not have to type a passphrase each time:

```bash
# macOS
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Linux
ssh-add ~/.ssh/id_ed25519
```

To have the key loaded automatically on macOS, add this to `~/.ssh/config` (already included in the template below):

```
Host *
    AddKeysToAgent yes
    UseKeychain yes          # macOS only — remove on Linux
    IdentityFile ~/.ssh/id_ed25519
```

---

## 2. Copy your public key to each cluster

This allows key-based authentication so the cluster recognises your machine without a password. On clusters with 2FA you will still need to authenticate once during `ssh-copy-id`, but never again after.

```bash
# General form
ssh-copy-id -i ~/.ssh/id_ed25519.pub USER@HOSTNAME

# Examples (made-up usernames; 192.0.2.x is an address range reserved for documentation)
ssh-copy-id -i ~/.ssh/id_ed25519.pub abc123@cluster1.bmrc.ox.ac.uk   # BMRC username: e.g. abc123
ssh-copy-id -i ~/.ssh/id_ed25519.pub jdoe@192.0.2.10                 # cluster reached by IP address
```

If `ssh-copy-id` is not available, do it manually:

```bash
cat ~/.ssh/id_ed25519.pub | ssh USER@HOSTNAME "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

---

## 3. Configure `~/.ssh/config`

The full template is in [`ssh_config.template`](ssh_config.template). Copy the relevant blocks into your `~/.ssh/config` and fill in your usernames.

### Global defaults

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    AddKeysToAgent yes
    UseKeychain yes          # macOS only
    IdentityFile ~/.ssh/id_ed25519
```

### Clusters with 2FA (BMRC pattern)

```
Host bmrc_cluster
    HostName cluster1.bmrc.ox.ac.uk
    User YOUR_USERNAME
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist yes
```

**How `ControlMaster` works:**

| Option | What it does |
|---|---|
| `ControlMaster auto` | First connection opens a socket; subsequent ones reuse it |
| `ControlPath` | Where the socket file lives on disk |
| `ControlPersist yes` | Socket stays open after the first terminal exits |

**Workflow for 2FA clusters:**

```
# 1. Open a terminal (Ghostty, iTerm2, the built-in terminal — anywhere)
ssh bmrc_cluster          # complete 2FA here — socket is now open

# 2. Connect from Positron
# Remote Explorer → bmrc_cluster → Connect
# Positron reuses the socket. No 2FA prompt.
```

The socket file appears at `~/.ssh/cm-abc123@cluster1.bmrc.ox.ac.uk:22` for user `abc123` (path follows the `ControlPath` pattern). It is removed automatically when the connection is closed or times out.

To check whether a socket is active:

```bash
ssh -O check bmrc_cluster
```

To close it manually:

```bash
ssh -O exit bmrc_cluster
```

### Clusters with key-only auth (Ludwig pattern)

```
Host ludwig_cluster
    HostName YOUR_LUDWIG_HOST      # IP address or host name, e.g. 192.0.2.10
    User YOUR_USERNAME             # e.g. jdoe
```

No `ControlMaster` needed. Once your public key is on the server, Positron connects directly — `BatchMode=yes` works fine with key auth.

### Reaching a compute node through the login node

BMRC (and many clusters) only expose the login node externally. To connect Positron directly to a compute node running a SLURM job, you need a `ProxyCommand` that tunnels through the login node:

```
Host bmrc_compute
    User YOUR_USERNAME             # e.g. abc123
    HostKeyAlias bmrc_compute
    ProxyCommand bash -c 'read -r n p < <(ssh -n bmrc_cluster cat .ssh/userd/current_node 2>/dev/null); [ -n "$p" ] || { echo "No Positron session is running on the cluster. Start one with: positron-compute start" >&2; exit 1; }; exec ssh -W "$n:$p" bmrc_cluster'
```

This reads the compute node's address from a file your Slurm job writes, then tunnels through the login node. If no job is running, it says so instead of failing with a cryptic error. The `-n` matters: without it, the inner `ssh` swallows the start of the connection and you get `Bad packet length`.

The cluster side (the job that runs the SSH server and writes that file) is in [`remote/`](../remote/README.md).

### Other common patterns

**Jump host / bastion:**

```
Host internal_node
    HostName 10.0.1.50
    User researcher
    ProxyJump bastion.example.com
```

**Cloud HPC (AWS ParallelCluster, GCP, Azure) — separate key:**

```
Host cloud_hpc
    HostName login.aws-hpc.example.com
    User ec2-user
    IdentityFile ~/.ssh/cloud_hpc_key
```

---

## 4. Positron setting

Enable native OpenSSH transport so Positron delegates to the system `ssh` binary (which respects your `~/.ssh/config`):

**Positron Settings → search `remoteSSH.transport` → set to `native`**

Or add directly to `settings.json`:

```json
"remoteSSH.transport": "native"
```

This is required for `ControlMaster` to work from Positron. Without it, Positron uses its own built-in SSH implementation that ignores `~/.ssh/config` entirely.

---

## Quick-start: automated setup

Run [`setup_ssh.sh`](setup_ssh.sh) to do steps 1–3 automatically:

```bash
chmod +x ssh/setup_ssh.sh
./ssh/setup_ssh.sh
```

The script will generate a key (if needed), copy it to each cluster, and append the config block to `~/.ssh/config`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (keyboard-interactive)` | Positron's `BatchMode=yes` blocked 2FA | Open terminal SSH first to create control socket |
| `Could not establish connection` with empty log | IP blocked by fail2ban after too many attempts | Wait for block to lift; check with `ssh bmrc_cluster` in terminal |
| Control socket not reused | `remoteSSH.transport` not set to `native` | Set in Positron settings and restart |
| `Connection closed by remote` after 2FA succeeds | Server rejects the client's first probe command | Same fix — ControlMaster bypasses this entirely |
| Socket stale after reconnect | Previous session ended uncleanly | Run `ssh -O exit bmrc_cluster` then reconnect in terminal |
