# positron-slurm-setup

A step-by-step guide to running [Positron](https://positron.posit.co) on a cluster managed by Slurm: connect from your laptop, get R and Python to start reliably, and run your session on a compute node rather than the crowded login node.

It's written for researchers who use a cluster for their analysis, not for system administrators. Every command can be copied as it is, and each section explains *why* a step is needed, so that you can fix things when they go differently. The examples use Oxford's BMRC cluster; [adapting to another cluster](#using-another-cluster) is mostly a matter of changing names.

---

## The picture

```
your laptop                     the cluster
┌──────────────┐   SSH    ┌─────────────────────┐        ┌───────────────────────────┐
│   Positron   │ ───────▶ │  login node          │ ─────▶ │  compute node             │
│  (the window │          │  shared by everyone; │        │  your Slurm job: its own  │
│   you see)   │          │  editing, submitting │        │  CPUs and memory; where R │
└──────────────┘          └─────────────────────┘        │  and Python should run    │
                                                          └───────────────────────────┘
```

Positron splits in two: the window on your laptop, and a **server** on the machine you connect to, which runs your R and Python consoles. Connecting to the login node is easy but puts that server, and your analysis, on a shared machine with tight limits. This guide gets you there first, then moves the server onto a compute node.

## Words you'll meet

| Term | Meaning |
|---|---|
| **Login node** | The machine you reach when you `ssh` to the cluster. Shared by all users; for editing, moving files and submitting jobs |
| **Compute node** | A machine that runs jobs. You get a share of one by asking Slurm |
| **Slurm job** | A request for CPUs, memory and time (`sbatch`, `salloc`), and whatever runs with them. When the time is up, it ends |
| **Partition** | A Slurm queue (`short`, `long`, …), each with its own limits |
| **SSH** | The encrypted connection from your laptop to the cluster. `ssh` is the program that opens it |
| **SSH key** | A pair of files that proves who you are without a password: the private key stays on your laptop, the public key goes on the cluster (`~/.ssh/authorized_keys`) |
| **SSH server (`sshd`)** | The program on the other end that accepts connections and checks your key |
| **Port** | A numbered "door" on a machine; each server listens on one. SSH normally uses 22 |
| **`~/.ssh/config`** | A file on your laptop that gives clusters short names (`bmrc_cluster`) and says how to reach them |
| **2FA** | Two-factor authentication: a code from your phone on top of a password or key |
| **Kernel** | The R or Python process behind a Positron console |

---

## The route

Work through these in order. Each part assumes the one before it.

### Part 1. Connect: [`ssh/`](ssh/README.md)

Set up an SSH key and `~/.ssh/config` so Positron can connect to the login node, including on clusters with 2FA (log in once in a terminal; Positron reuses that connection).

- [`ssh/README.md`](ssh/README.md): the guide
- [`ssh/setup_ssh.sh`](ssh/setup_ssh.sh): does it for you (key, copying it to the cluster, config)
- [`ssh/ssh_config.template`](ssh/ssh_config.template): the config, to copy from by hand

### Part 2. Make Positron start the right R and Python: [`positron/`](positron/README.md)

The settings Positron needs on a cluster, how to make it find your project's R and Python, and what to do when a console won't start ("Request failed with status code 500").

- [`positron/README.md`](positron/README.md): settings, interpreters, slow starts, memory on the login node
- [`positron/settings.user.jsonc`](positron/settings.user.jsonc): user settings to merge into yours

### Part 3. Move the session to a compute node: [`remote/`](remote/README.md)

Run Positron's server and consoles inside a Slurm job, on clusters that don't let you log in to compute nodes directly: a job runs your own SSH server on the node, and your laptop reaches it through the login node.

- [`remote/README.md`](remote/README.md): the idea, setup, daily use, how it works, troubleshooting
- [`remote/positron-compute`](remote/positron-compute): laptop commands: `setup`, `start`, `status`, `open`, `stop`
- [`remote/setup_userd.sh`](remote/setup_userd.sh) and [`remote/positron_userd.sbatch`](remote/positron_userd.sbatch): the cluster side

---

## Quick start

For those who want the commands first. The guides explain each step.

```bash
# --- Part 1: connect (once) -------------------------------------------------
# Edit the usernames at the top of ssh/setup_ssh.sh, then:
./ssh/setup_ssh.sh
# In Positron's settings: remoteSSH.transport → native

# --- Part 2: Positron settings (once) ----------------------------------------
# In Positron's settings: kernelSupervisor.connectionTimeout → 120
# In each project: see positron/README.md (interpreters, renv startup check)

# --- Part 3: compute node (once) ---------------------------------------------
ssh bmrc_cluster                      # terminal 1: log in with 2FA, leave it open
remote/positron-compute setup         # terminal 2: installs the cluster side
```

## Every day

```bash
ssh bmrc_cluster                      # 1. log in (2FA), unless the connection is still open
remote/positron-compute start         # 2. start a session; waits until it's ready
```

3. In Positron: **Remote Explorer → `bmrc_compute` → Connect**, and open your project.
4. When you're done: `remote/positron-compute stop`. Closing Positron alone leaves the job, and its reserved CPUs and memory, running until its time limit.

For quick edits, connecting to `bmrc_cluster` (the login node) is still fine.

---

## Using another cluster

| What | Where to change it |
|---|---|
| Login host, username | `~/.ssh/config` ([`ssh/`](ssh/README.md#3-configure-sshconfig)) |
| Whether you need the `ControlMaster` routine | Only on clusters with 2FA or passwords ([`ssh/`](ssh/README.md#clusters-with-2fa-bmrc-pattern)) |
| Whether you need Part 3's own SSH server | Not if the cluster lets you SSH into your job's node ([test](remote/README.md#2-first-check-can-you-ssh-into-a-compute-node)) |
| Partition and default resources | Top of [`remote/positron_userd.sbatch`](remote/positron_userd.sbatch) |
| Host names used by `positron-compute` | Top of [`remote/positron-compute`](remote/positron-compute), or `PC_LOGIN` / `PC_COMPUTE` ([details](remote/README.md#9-using-it-on-another-cluster)) |

## Repository layout

```
positron-slurm-setup/
├── README.md                      ← you are here
├── ssh/                           Part 1: laptop → login node
│   ├── README.md
│   ├── setup_ssh.sh
│   └── ssh_config.template
├── positron/                      Part 2: Positron settings and troubleshooting
│   ├── README.md
│   └── settings.user.jsonc
└── remote/                        Part 3: Positron on a compute node
    ├── README.md
    ├── positron-compute             runs on your laptop
    ├── setup_userd.sh               runs once on the cluster
    └── positron_userd.sbatch        the Slurm job
```

Checked against Positron 1.138 on BMRC (Slurm, GPFS storage), with a macOS laptop.
