# Part 3: Run Positron on a compute node

Connected to the login node, Positron runs R and Python **on the login node**: shared, slow on cluster storage, and memory-capped (26 GiB per user on BMRC). Analysis belongs on a compute node.

BMRC doesn't let you SSH into compute nodes, even ones running your job. The workaround: a Slurm job runs **your own SSH server** on the node, and your laptop reaches it through the login node.

```
Mac: Positron
  │  ssh bmrc_compute
  ▼
cluster1 (login node)         normal SSH, port 22: the connection you already have open
  │  ssh -W compe020:45930    passes the bytes on, nothing more
  ▼
compe020, port 45930          YOUR sshd, running as you inside your Slurm job
  └─ Positron server, R and Python consoles, terminals: all run here
```

## Setup (once)

1. Copy the two scripts to the cluster and run the setup:
   ```bash
   scp remote/setup_userd.sh remote/positron_node.sbatch bmrc_cluster:
   ssh bmrc_cluster bash setup_userd.sh
   ```
   This creates `~/.ssh/userd/` with the server's key and settings ([`setup_userd.sh`](setup_userd.sh), 25 lines).
2. Make sure `~/.ssh/config` on your laptop has the `bmrc_compute` host ([template](../ssh/ssh_config.template)):
   ```
   Host bmrc_compute
       User abc123
       HostKeyAlias bmrc_compute
       ProxyCommand bash -c 'read n p < <(ssh -n bmrc_cluster cat .ssh/userd/current_node); exec ssh -W $n:$p bmrc_cluster'
   ```

## Every day

```bash
ssh bmrc_cluster 'sbatch -o ~/positron_%j.log ~/positron_node.sbatch'   # start the session
ssh bmrc_cluster 'squeue --me'                                           # wait for state R
positron --folder-uri "vscode-remote://ssh-remote+bmrc_compute/path/to/project"
ssh bmrc_cluster 'scancel -n positron'                                   # when done
```

Instead of the `positron` command you can use **Remote Explorer → `bmrc_compute` → Connect**, then **File → Open Folder…**. (To get the `positron` command: Command Palette → *Shell Command: Install 'positron' command in PATH*.)

**More resources** for one session: `sbatch -p long -c 8 --mem=64G -t 2-00:00:00 -o …`. The defaults (4 CPUs, 32 GB, 8 h on `short`) are at the top of [`positron_node.sbatch`](positron_node.sbatch).

## How it works

[`positron_node.sbatch`](positron_node.sbatch) is a normal Slurm job that:

1. picks a random high port (other people may be on the same node),
2. writes `<node> <port>` to `~/.ssh/userd/current_node` (your home folder is shared, so the login node can read it),
3. runs `sshd` with your settings until the job ends, then deletes `current_node`.

On the laptop, `bmrc_compute` has no address of its own. Its `ProxyCommand` reads `current_node` through the login node, then `ssh -W` asks the login node to relay the connection to that node and port. `-n` stops the first `ssh` from swallowing the connection's opening bytes. `HostKeyAlias` keeps one known-hosts entry for every node, because the server's key is the same wherever the job runs.

The server's settings (`~/.ssh/userd/sshd_config`) allow only you, only with your SSH key. `UsePAM no` because PAM, the system's login machinery, needs root.

> A private SSH server sidesteps the compute nodes' login policy. Check your cluster's rules, or ask support, before relying on it.

## Good to know

- **Closing Positron doesn't end the job.** The server keeps waiting for you, and the job keeps its CPUs and memory until the time limit. `scancel` it when you're done.
- **One session at a time.** A second job overwrites `current_node`.
- **Submitting jobs from the node works:** `sbatch` in Positron's terminal starts a separate job that outlives your session.
- **Internet:** BMRC's compute nodes reach the internet through a web proxy that's already set up, so installing packages works. Git over SSH (`git@github.com:…`) doesn't; use HTTPS remotes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `cat: …current_node: No such file` / `Connection closed by UNKNOWN port 65535` | No session is running: check `squeue --me`, start one |
| `Bad packet length` | The `ProxyCommand` is missing `-n` |
| `Permission denied (publickey)` | Your laptop's key isn't in `~/.ssh/authorized_keys` on the cluster ([Part 1](../ssh/README.md)) |
| The job ends at once | Read `~/positron_<jobid>.log` on the cluster |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | `~/.ssh/userd` was recreated: `ssh-keygen -R bmrc_compute` on the laptop |
| Can't reach `bmrc_cluster` at all | Log in again in a terminal (2FA); check the VPN |

**First check whether you need this at all:** start a job, then from the login node try `ssh <its node> hostname`. If that works, your cluster lets you in directly, and a plain `ProxyJump` to the node is simpler.
