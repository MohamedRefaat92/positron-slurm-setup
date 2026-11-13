# Running Positron on a compute node

When Positron is connected to the login node, everything it starts runs on the login node: its server, the R and Python consoles, and your analysis. That's fine for editing files and quick checks, but not for analysis:

- **It's slow.** Login nodes are shared, and on cluster storage every file read waits. On BMRC a login shell took 13 s there against 1 s on a compute node, and R took minutes to start (figures in [`positron/`](../positron/README.md#4-a-kernel-wont-start-request-failed-with-status-code-500)). Kernels then time out.
- **It's capped.** Your processes on a login node share a per-user memory limit (26.3 GiB on BMRC), and going over gets your kernel killed. See [`positron/`](../positron/README.md#5-memory-on-a-shared-login-node).
- **It's not what login nodes are for.** Many clusters limit or kill heavy processes there.

This section moves Positron's server and consoles onto a **compute node**, inside a Slurm job that has its own CPUs and memory.

**Before you start:** you can already connect Positron to the login node ([`ssh/`](../ssh/README.md)), and on a 2FA cluster you know the "log in once in a terminal" routine.

---

## Contents

1. [The idea in plain words](#1-the-idea-in-plain-words)
2. [First check: can you SSH into a compute node?](#2-first-check-can-you-ssh-into-a-compute-node)
3. [One-time setup](#3-one-time-setup)
4. [Everyday use](#4-everyday-use)
5. [Choosing resources](#5-choosing-resources)
6. [How it works](#6-how-it-works)
7. [Working on the node: what's different](#7-working-on-the-node-whats-different)
8. [Troubleshooting](#8-troubleshooting)
9. [Using it on another cluster](#9-using-it-on-another-cluster)

---

## 1. The idea in plain words

To connect, Positron needs an **SSH server** on the machine it connects to: a program that answers the door and checks your key. Every node has one, but on many clusters the one on the compute nodes only lets administrators in.

The cluster still lets your *jobs* run any program you like on a compute node, and it lets the login node talk to compute nodes. So:

1. You submit a **Slurm job** whose only task is to run **a second SSH server, as you**, on the node it lands on. It listens on a free "door number" (port) and writes down where it is: `compe020 45930`.
2. On your laptop, the host `bmrc_compute` in `~/.ssh/config` has no fixed address. Each time you connect, it reads that note through the login node, and then has the login node pass the connection through to that node and port.
3. Positron connects to `bmrc_compute` like any other host. It doesn't know about the detour.

```
your laptop (Positron)
   │  ssh bmrc_compute
   ▼
login node  (cluster1)      ← the connection you already have; 2FA done once
   │  passes the bytes on to compe020, port 45930
   ▼
compute node (compe020)     ← your SSH server, running inside your Slurm job
   └─ Positron server, R and Python consoles, terminals: all run here
```

The job is the session. It gets exactly the CPUs, memory and time you asked Slurm for, and when it ends, the server stops and Positron disconnects. Nothing here gives you more than Slurm already granted you.

> **Ask your cluster's support first.** A private SSH server is a way around the compute nodes' login policy, and some clusters' usage rules forbid it. A short email asking whether it's acceptable protects your account, and they may offer a supported alternative.

---

## 2. First check: can you SSH into a compute node?

On many clusters you can, as long as you have a job running on that node. If so, you don't need the rest of this page. Test it on the login node:

```bash
salloc -p short -c 1 --mem=1G -t 00:30:00     # get a small job; note the node it prints, e.g. compe004
ssh compe004 hostname                          # from the login node, while that job runs
exit                                           # leave salloc, which ends the job
```

- **It prints the node's name:** you can connect directly. Add a host with `HostName compe004` and `ProxyJump bmrc_cluster` to `~/.ssh/config`, and change `HostName` when your job lands elsewhere.
- **`Connection closed by UNKNOWN port 65535`**, or a similar refusal: the node won't let you log in. On BMRC this happens for every login method, even with a job running there. Continue below.

The pattern below also needs the login node to reach compute nodes on high ports. That's almost always allowed (parallel programs depend on it), and the setup will tell you if it isn't.

---

## 3. One-time setup

You need [`setup_userd.sh`](setup_userd.sh) and [`positron_userd.sbatch`](positron_userd.sbatch) on the cluster, and the `bmrc_compute` host in your laptop's `~/.ssh/config`.

**On your laptop**, from this repository's folder:

```bash
ssh bmrc_cluster                    # in a terminal: log in (2FA) and leave it open
remote/positron-compute setup       # in a second terminal
```

`positron-compute setup` copies both files to `~/.ssh/userd/` on the cluster and runs `setup_userd.sh` there. That script:

| Step | What it does |
|---|---|
| Folder | Creates `~/.ssh/userd/` (only you can read it) and `~/.ssh/userd/logs/` |
| Host key | Creates the server's identity, `ssh_host_ed25519_key`, once. It's reused on every node, so your laptop recognises the server wherever the job runs |
| Settings | Writes `sshd_config`: you're the only user allowed, key login only ([details](#the-servers-settings-sshd_config)) |
| Job script | Installs `positron_userd.sbatch` in the same folder |
| Checks | Asks `sshd` to validate the settings, and checks that your laptop's key is in `~/.ssh/authorized_keys` |

It's safe to run again; it keeps the existing host key.

**The laptop side:** if you used [`ssh/setup_ssh.sh`](../ssh/setup_ssh.sh) or [`ssh/ssh_config.template`](../ssh/ssh_config.template), `bmrc_compute` is already in `~/.ssh/config`. Otherwise add it:

```
Host bmrc_compute
    User YOUR_USERNAME
    HostKeyAlias bmrc_compute
    ProxyCommand bash -c 'read -r n p < <(ssh -n bmrc_cluster cat .ssh/userd/current_node 2>/dev/null); [ -n "$p" ] || { echo "No Positron session is running on the cluster. Start one with: positron-compute start" >&2; exit 1; }; exec ssh -W "$n:$p" bmrc_cluster'
```

**Optional:** make `positron-compute` available from any folder:

```bash
mkdir -p ~/bin && ln -s "$PWD/remote/positron-compute" ~/bin/positron-compute
# and, if ~/bin isn't on your PATH yet, add this line to ~/.zshrc:  export PATH="$HOME/bin:$PATH"
```

<details>
<summary>Doing the setup by hand, without <code>positron-compute</code></summary>

```bash
# on your laptop
ssh bmrc_cluster 'mkdir -p ~/.ssh/userd'
scp remote/setup_userd.sh remote/positron_userd.sbatch bmrc_cluster:.ssh/userd/
# on the cluster
bash ~/.ssh/userd/setup_userd.sh
```
</details>

---

## 4. Everyday use

The login-node connection has to be open first. On a 2FA cluster that means a terminal where you ran `ssh bmrc_cluster` (with `ControlPersist yes`, it stays open after you close that terminal).

| | With `positron-compute` (on your laptop) | By hand |
|---|---|---|
| **Start** | `positron-compute start` | `ssh bmrc_cluster 'cd ~/.ssh/userd/logs && sbatch ../positron_userd.sbatch'` |
| **Wait until it runs** | `start` waits and tells you when it's ready | `ssh bmrc_cluster 'squeue -u $USER -n positron'` until `R` |
| **Connect** | Positron: **Remote Explorer → `bmrc_compute` → Connect** | same |
| **Open a project** | `positron-compute open /full/path/to/project` | Positron: **File → Open Folder…**, paste the path |
| **Check** | `positron-compute status` | `squeue` as above |
| **Stop** | `positron-compute stop` | `ssh bmrc_cluster 'scancel -n positron'` |

What `start` looks like:

```
$ positron-compute start
Submitted job 35162231. Waiting for it to start (Ctrl-C stops waiting; the job keeps going) …
  PENDING (Priority)
  running on compe020, starting the server …

Ready: job 35162231 on compe020.
In Positron: Remote Explorer → bmrc_compute → Connect (or: positron-compute open <folder>).
When you're done:  positron-compute stop
```

**Opening projects.** Positron remembers folders separately for each host. The first time, connect to `bmrc_compute`, then **File → Open Folder…** and paste the project's full path (e.g. `/well/mylab/users/abc123/projects/myproject`). After that it appears under `bmrc_compute` in Remote Explorer and in **File → Open Recent**. It's the same folder on shared storage as on the login node: the same files, `renv` and `.Rprofile`.

**Stop the job when you're done**, rather than just closing Positron (see [section 7](#closing-positron-doesnt-end-the-job)).

**One session at a time.** Every session job writes to the same `current_node` file, so only the newest one is reachable. `start` refuses to submit a second one.

---

## 5. Choosing resources

The defaults are at the top of [`positron_userd.sbatch`](positron_userd.sbatch): partition `short`, 4 CPUs, 32 GB, 8 hours. Change them there for good, or for one session, because options given to `start` (or to `sbatch`) override the file's:

```bash
positron-compute start -c 8 --mem=64G -t 12:00:00     # bigger and longer
positron-compute start -p long -t 3-00:00:00          # 3 days on the "long" partition
```

| Option | Meaning |
|---|---|
| `-p` / `--partition` | Which queue. Partitions differ in their time limits and machines |
| `-c` / `--cpus-per-task` | CPU cores for everything in the session, e.g. `future`/`BiocParallel` workers |
| `--mem` | Memory for the whole session (all consoles together) |
| `-t` / `--time` | How long the session lasts; it ends at this limit even if you're mid-analysis |

Points to keep in mind:

- **Ask for what you'll use.** Small requests start sooner, and Slurm's fair-share counts the time you *hold* resources, not the time you use them. An idle 8-core job overnight lowers the priority of your next jobs.
- **Check a partition's limits** on the cluster with `sinfo -o "%P %l %c %m"` (partition, maximum time, CPUs and memory per node). A job asking for more than its partition allows stays pending, with a reason such as `PartitionTimeLimit`.
- **GPUs:** use a GPU partition and add `--gres=gpu:1`.
- **Heavy, long computations** belong in their own `sbatch` jobs (or `targets` with `crew.cluster`), not in the interactive session. Then the session's time limit doesn't matter to them.

---

## 6. How it works

### The files

| File | Where | Role |
|---|---|---|
| [`setup_userd.sh`](setup_userd.sh) | cluster, run once | Creates the folder, host key and settings below |
| `~/.ssh/userd/sshd_config` | cluster | Your server's settings |
| `~/.ssh/userd/ssh_host_ed25519_key` | cluster | Your server's identity (private; mode 600) |
| [`positron_userd.sbatch`](positron_userd.sbatch) | cluster, `~/.ssh/userd/` | The job: starts the server and writes `current_node` |
| `~/.ssh/userd/current_node` | cluster | One line, `<node> <port>`, while a session runs |
| `~/.ssh/userd/logs/positron_<jobid>.log` | cluster | The job's log: the server's messages, logins, errors |
| `bmrc_compute` in `~/.ssh/config` | laptop | Reads `current_node`, tunnels there through the login node |
| [`positron-compute`](positron-compute) | laptop | Convenience commands for the steps above |

### The job, step by step

1. Picks a random port between 20000 and 60000 that nothing is using. Random, because other people may be on the same node.
2. Starts `sshd` with your settings on that port, and checks it's still alive two seconds later (retrying with another port if not).
3. Writes `<node> <port>` to `~/.ssh/userd/current_node`. Your home folder is shared storage, so the login node can read it.
4. Waits for as long as the server runs, which keeps the job, and with it the session, alive.
5. When the job ends (`scancel`, or the time limit, which both send a stop signal), it stops the server and removes `current_node`. It removes the file only if it still points to this job, so it doesn't break a newer session.

### The server's settings (`sshd_config`)

Normally the SSH server runs as the administrator (root) and reads `/etc/ssh/sshd_config`. Yours runs as you, so it has its own settings, pointing only at files you own:

| Setting | Why |
|---|---|
| `HostKey …/ssh_host_ed25519_key` | The server's identity. The system's keys can only be read by root, so you have your own |
| `AllowUsers <you>`, `PermitRootLogin no` | Only your account can log in. A server run by you couldn't log anyone in as somebody else anyway |
| `AuthorizedKeysFile ~/.ssh/authorized_keys`, `PubkeyAuthentication yes` | Your laptop's key is the way in |
| `PasswordAuthentication no`, `ChallengeResponseAuthentication no` | No passwords or 2FA prompts. A server run by a normal user can't check passwords; the 2FA happened at the login node |
| `UsePAM no` | PAM is the system's login machinery. It needs root, and it's also what keeps you out of compute nodes |
| `Subsystem sftp internal-sftp` | File transfer. Positron uses it to install its server and browse files |
| `AllowTcpForwarding yes` | Lets Positron forward ports to your laptop, e.g. to view a Shiny app |

The port and PID file aren't in this file; the job passes them on the command line, because they differ for every job.

### The laptop side (`ProxyCommand`)

`bmrc_compute` has no `HostName`. Instead, before each connection, `ssh` runs its `ProxyCommand`, which:

1. Runs `ssh -n bmrc_cluster cat .ssh/userd/current_node` and reads the node and port. The `-n` matters: without it, this inner `ssh` swallows the first bytes of your real connection, and the result is `Bad packet length`.
2. Stops with a clear message if there's no session.
3. Runs `ssh -W node:port bmrc_cluster`, which asks the login node to pass bytes to that node and port. Your laptop then talks to your server directly, encrypted end to end; the login node only relays.

Both steps reuse your open login-node connection (`ControlMaster`), so they're fast and need no further 2FA.

`HostKeyAlias bmrc_compute` stores the server's key under one fixed name. The node changes with each job, but the key doesn't, so the "is this the right host?" question comes up only the first time.

### What runs where

```
slurmstepd (your job)
└── sshd -D -p 45930              ← started by the job; runs until the job ends
    └── sshd: abc123 (session)    ← one per connection from your laptop
        └── positron-server
            ├── ark                 (R console)
            ├── python … ipykernel  (Python console)
            └── bash                (terminal tabs)
```

---

## 7. Working on the node: what's different

### Closing Positron doesn't end the job

Closing the window ends only your *connection* (the session branch above). The server at the top keeps waiting for the next connection, the job keeps running, and its CPUs and memory stay reserved until the time limit. That's useful (you can reconnect after a network drop), but end the job when you're done: `positron-compute stop`.

### The R console and R in a terminal are the same R

Positron's console runs R through **Ark**, a program that loads R and connects its input and output to Positron instead of to a terminal. That connection is what makes the Variables and Plots panes possible. The R doing the work is the same, so results are identical. What can differ is *which* R starts: check that Positron's interpreter is your project's (see [`positron/`](../positron/README.md#2-the-wrong-r-starts-or-the-projects-r-is-missing)).

Things started in a console or terminal end with it. Things submitted with `sbatch` belong to Slurm and keep running.

### Submitting jobs from the node

Positron's terminal on the compute node can run `sbatch`, `squeue` and `scancel` as on the login node (check once: `which sbatch`). A job submitted from there is separate from your session: it gets its own resources, and keeps running when the session ends. Two things to watch:

- It inherits your terminal's environment (the active conda env, and the session job's `SLURM_*` variables). If a job misbehaves, submit it with `sbatch --export=NONE` and set up its environment inside the script.
- `srun` on its own runs *inside* your session job, sharing its CPUs, rather than starting a new job.

`targets` with `crew.cluster` or `clustermq` submits through `sbatch`, so `tar_make()` in the session sends the heavy work out as separate jobs.

### Internet and installing packages

BMRC's compute nodes have no direct route to the internet. They reach it through a web **proxy**, which is already configured in your environment (`env | grep -i proxy`). A quick test:

```bash
curl -sI https://cloud.r-project.org | head -1
```

`HTTP/1.1 200 Connection established` is the proxy agreeing to connect you, which means it works. So:

- `install.packages()`, `renv`, `BiocManager`, `pip`, `conda` and `git clone https://…` work as usual.
- **Git over SSH** (`git@github.com:…`) doesn't go through a web proxy. Use HTTPS remotes, or push from the login node.
- On a cluster without even a proxy, install packages from a login-node terminal instead. They land in your project's library on shared storage, and the compute node sees them at once (restart R to load them).

---

## 8. Troubleshooting

Start with `positron-compute status` and `positron-compute log`.

| Symptom | Cause | Fix |
|---|---|---|
| `No Positron session is running on the cluster` | No job, or it ended (`current_node` is gone) | `positron-compute start` |
| `ssh: connect to host cluster1… Connection refused` | The login node itself is unreachable: off the university network/VPN, the node is down, or your address was briefly blocked after many attempts | Connect the VPN; try another login node if your cluster has one; wait 15–30 min |
| `start` says it can't reach the login node without a prompt | The 2FA connection isn't open | `ssh bmrc_cluster` in a terminal, then try again |
| Job stays `PENDING` | Waiting for resources; the reason is shown | Ask for less (`-c`, `--mem`, `-t`) or another partition |
| Job ends straight away | The server couldn't start | `positron-compute log`. Usually `setup_userd.sh` wasn't run, or `sshd` isn't at `/usr/sbin/sshd` |
| `Permission denied (publickey)` | Your laptop's key isn't allowed, or permissions are too open (sshd then ignores the key) | Run `setup_userd.sh` again: it checks both |
| `Bad packet length …` / `message authentication code incorrect` | The `ProxyCommand` lacks `-n`, so the inner `ssh` eats your connection's first bytes | Use the `ProxyCommand` above |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` for `bmrc_compute` | The host key was recreated (e.g. `~/.ssh/userd` was deleted) | If you know why: `ssh-keygen -R bmrc_compute` on the laptop, then reconnect |
| Positron connects to an old node, or reconnects endlessly | A previous session's job is still running, or Positron keeps retrying a dead one | `positron-compute status`; stop old jobs; close the old window |

---

## 9. Using it on another cluster

Nothing here is specific to BMRC except names and defaults:

1. **Partition** in `positron_userd.sbatch` (`--partition=short`): use one that exists (`sinfo`), or delete the line to use the cluster's default.
2. **Host names:** the `bmrc_cluster` inside the `ProxyCommand` (twice) must be your login host's name in `~/.ssh/config`. `positron-compute` uses `bmrc_cluster` and `bmrc_compute` unless you set `PC_LOGIN` and `PC_COMPUTE` (edit the top of the script, or `PC_LOGIN=mycluster positron-compute start`).
3. **2FA:** if the cluster accepts keys alone, `ControlMaster` is optional and nothing else changes.
4. **One cluster at a time per home folder:** the files live in `~/.ssh/userd/`. Clusters that share a home folder can't run two sessions at once.

Also check [section 2](#2-first-check-can-you-ssh-into-a-compute-node) first: if the cluster lets you SSH into your job's node, a plain `ProxyJump` is simpler.
