# Part 1: Connect Positron to the cluster

Goal: Positron on your laptop connects to the cluster's login node, including on clusters with two-factor authentication (2FA) such as BMRC.

## Why 2FA needs a trick

Positron's SSH can't show prompts, so it can't type a 2FA code. The fix is to log in **once in a terminal**, and let every later connection (Positron, other terminals) reuse that logged-in connection. In `~/.ssh/config` this is `ControlMaster`.

## Setup

**Quickest:** edit the usernames at the top of [`setup_ssh.sh`](setup_ssh.sh) and run it. It does the three steps below.

**By hand:**

1. **Make an SSH key** (skip if `~/.ssh/id_ed25519` exists):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
   ```
2. **Put the public key on the cluster** (asks for your password and 2FA once):
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519.pub abc123@cluster1.bmrc.ox.ac.uk
   ```
3. **Add the hosts to `~/.ssh/config`** from [`ssh_config.template`](ssh_config.template). The important part:
   ```
   Host bmrc_cluster
       HostName cluster1.bmrc.ox.ac.uk
       User abc123
       ControlMaster auto            # first connection opens a shared socket, later ones reuse it
       ControlPath ~/.ssh/cm-%r@%h:%p
       ControlPersist yes            # keep it open after you close the terminal
   ```
4. **In Positron:** Settings → `remoteSSH.transport` → `native`. Without it Positron ignores `~/.ssh/config`.

## Every day

```bash
ssh bmrc_cluster      # in a terminal: log in with 2FA (once per day, or after the connection drops)
```

Then in Positron: **Remote Explorer → `bmrc_cluster` → Connect**.

Clusters that accept your key without 2FA (e.g. `ludwig_cluster` in the template) need no terminal step.

To run on a compute node instead of the login node, continue with [Part 3](../remote/README.md).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Permission denied (keyboard-interactive)` in Positron | The shared connection isn't open: run `ssh bmrc_cluster` in a terminal first |
| Positron doesn't use the shared connection | Set `remoteSSH.transport` to `native` and restart Positron |
| `Connection refused` | You're off the network the cluster requires (connect the VPN), or the login node is down |
| Things hang after a network change | Close the stale connection: `ssh -O exit bmrc_cluster`, then log in again |
| Is the shared connection open? | `ssh -O check bmrc_cluster` |
